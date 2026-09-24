import Foundation
import os.log

// Writes Safari Bookmarks.plist by merging single leaves in or out.
//
// We never replace the whole file. Only insert/remove single leaves on user action.
//
// Delete used to no-op when Children was NSArray instead of NSMutableArray.
// mutableChildren() copies immutable arrays before editing.

struct BookmarkFolderInfo: Codable {
    let uuid: String
    let title: String
    let depth: Int
}

enum SafariBookmarkMutator {
    enum MutatorError: LocalizedError {
        case invalidURL
        case unreadable
        case missingFolder
        case writeFailed
        case notFound

        var errorDescription: String? {
            switch self {
            case .invalidURL: "This page cannot be saved."
            case .unreadable: "Could not read Safari bookmarks."
            case .missingFolder: "Could not find the Safari list."
            case .writeFailed: "Could not write Safari bookmarks."
            case .notFound: "Bookmark not found."
            }
        }
    }

    private static let queue = DispatchQueue(label: "patrick.bookmark.mutator")

    static func listBookmarkFolders() throws -> [BookmarkFolderInfo] {
        try queue.sync {
            let root = try loadMutable(from: SafariBookmarkCache.safariBookmarksURL)
            var folders: [BookmarkFolderInfo] = []
            collectFolders(node: root, depth: 0, into: &folders)
            return folders
        }
    }

    static func folderUUID(forURL rawURL: String, list: BookmarkListKind) throws -> String? {
        try queue.sync {
            let normalized = SafariBookmarkIndex.normalizeURL(rawURL)
            guard !normalized.isEmpty else { return nil }
            let root = try loadMutable(from: SafariBookmarkCache.safariBookmarksURL)
            return parentFolderUUID(for: normalized, list: list, node: root, parentUUID: nil)
        }
    }

    static func add(
        url rawURL: String,
        title: String?,
        to list: BookmarkListKind,
        folderUUID: String? = nil
    ) throws {
        try queue.sync {
            try mutate { root in
                let normalized = SafariBookmarkIndex.normalizeURL(rawURL)
                guard !normalized.isEmpty else { throw MutatorError.invalidURL }
                let folder = resolveFolder(list: list, folderUUID: folderUUID, in: root)
                guard let folder else { throw MutatorError.missingFolder }
                try insertIfMissing(
                    normalizedURL: normalized,
                    rawURL: rawURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    title: title,
                    list: list,
                    folder: folder,
                    root: root
                )
                if list == .bookmark, let uuid = folder["WebBookmarkUUID"] as? String {
                    BookmarkFolderSettings.setLastFolderUUID(uuid)
                }
            }
        }
    }

    static func move(url rawURL: String, toFolderUUID: String) throws {
        try queue.sync {
            try mutate { root in
                let normalized = SafariBookmarkIndex.normalizeURL(rawURL)
                guard !normalized.isEmpty else { throw MutatorError.invalidURL }
                guard let target = findFolder(uuid: toFolderUUID, in: root) else {
                    throw MutatorError.missingFolder
                }
                guard let leaf = detachLeaf(normalizedURL: normalized, list: .bookmark, from: root) else {
                    throw MutatorError.notFound
                }
                let children = folderChildren(target)
                children.insert(leaf, at: 0)
                BookmarkFolderSettings.setLastFolderUUID(toFolderUUID)
            }
        }
    }

    @discardableResult
    static func remove(url rawURL: String, from list: BookmarkListKind) throws -> Int {
        try queue.sync {
            var removed = 0
            try mutate { root in
                let normalized = SafariBookmarkIndex.normalizeURL(rawURL)
                guard !normalized.isEmpty else { throw MutatorError.invalidURL }
                removed = removeMatching(normalizedURL: normalized, list: list, from: root)
                if removed == 0 {
                    os_log(.error, "Patrick remove found 0 leaves for %{public}@", normalized)
                } else {
                    os_log(.default, "Patrick removed %d leaf(es) for %{public}@", removed, normalized)
                }
            }
            return removed
        }
    }

    private static func mutate(_ work: (NSMutableDictionary) throws -> Void) throws {
        let fileURL = SafariBookmarkCache.safariBookmarksURL
        let root = try loadMutable(from: fileURL)
        try work(root)
        try write(root, to: fileURL)
    }

    private static func loadMutable(from fileURL: URL) throws -> NSMutableDictionary {
        let data = try readData(from: fileURL)
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let root = try PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: &format
        ) as? NSMutableDictionary else {
            throw MutatorError.unreadable
        }
        return root
    }

    private static func readData(from url: URL) throws -> Data {
        var coordinatorError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { coordinatedURL in
            result = Result { try POSIXFileRead.data(atPath: coordinatedURL.path) }
        }
        if let coordinatorError { throw coordinatorError }
        switch result {
        case .success(let data): return data
        case .failure(let error): throw error
        case nil: return try POSIXFileRead.data(atPath: url.path)
        }
    }

    private static func write(_ root: NSMutableDictionary, to fileURL: URL) throws {
        let output = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { url in
            do {
                try output.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }

    private static func resolveFolder(
        list: BookmarkListKind,
        folderUUID: String?,
        in root: NSMutableDictionary
    ) -> NSMutableDictionary? {
        if list == .readingList {
            return findFolder(named: "com.apple.ReadingList", in: root)
        }
        if let folderUUID, !folderUUID.isEmpty, let folder = findFolder(uuid: folderUUID, in: root) {
            return folder
        }
        if let last = BookmarkFolderSettings.lastFolderUUID(), !last.isEmpty,
           let folder = findFolder(uuid: last, in: root) {
            return folder
        }
        return root
    }

    private static func insertIfMissing(
        normalizedURL: String,
        rawURL: String,
        title: String?,
        list: BookmarkListKind,
        folder: NSMutableDictionary,
        root: NSMutableDictionary
    ) throws {
        if contains(normalizedURL: normalizedURL, list: list, in: root) { return }
        let children = folderChildren(folder)
        children.insert(makeLeaf(url: rawURL, title: title, list: list, template: children), at: 0)
    }

    @discardableResult
    private static func removeMatching(normalizedURL: String, list: BookmarkListKind, from root: NSMutableDictionary) -> Int {
        removeMatching(normalizedURL: normalizedURL, list: list, node: root, inReadingList: false)
    }

    @discardableResult
    private static func removeMatching(
        normalizedURL: String,
        list: BookmarkListKind,
        node: NSMutableDictionary,
        inReadingList: Bool
    ) -> Int {
        let title = node["Title"] as? String ?? ""
        let currentlyInReadingList = inReadingList || title == "com.apple.ReadingList"
        guard let children = mutableChildren(of: node) else {
            return 0
        }

        var removed = 0
        var index = children.count - 1
        while index >= 0 {
            guard let child = children[index] as? NSMutableDictionary else {
                index -= 1
                continue
            }
            if let url = leafURL(in: child),
               SafariBookmarkIndex.normalizeURL(url) == normalizedURL {
                let isReadingListLeaf = currentlyInReadingList || child["ReadingList"] is NSDictionary
                let shouldRemove = list == .readingList ? isReadingListLeaf : !isReadingListLeaf
                if shouldRemove {
                    children.removeObject(at: index)
                    removed += 1
                }
            } else {
                removed += removeMatching(
                    normalizedURL: normalizedURL,
                    list: list,
                    node: child,
                    inReadingList: currentlyInReadingList
                )
            }
            index -= 1
        }
        return removed
    }

    private static func detachLeaf(
        normalizedURL: String,
        list: BookmarkListKind,
        from root: NSMutableDictionary
    ) -> NSMutableDictionary? {
        detachLeaf(normalizedURL: normalizedURL, list: list, node: root, inReadingList: false)
    }

    private static func detachLeaf(
        normalizedURL: String,
        list: BookmarkListKind,
        node: NSMutableDictionary,
        inReadingList: Bool
    ) -> NSMutableDictionary? {
        let title = node["Title"] as? String ?? ""
        let currentlyInReadingList = inReadingList || title == "com.apple.ReadingList"
        guard let children = mutableChildren(of: node) else { return nil }

        for index in 0..<children.count {
            guard let child = children[index] as? NSMutableDictionary else { continue }
            if let url = leafURL(in: child),
               SafariBookmarkIndex.normalizeURL(url) == normalizedURL {
                let isReadingListLeaf = currentlyInReadingList || child["ReadingList"] is NSDictionary
                let shouldRemove = list == .readingList ? isReadingListLeaf : !isReadingListLeaf
                if shouldRemove {
                    children.removeObject(at: index)
                    return child
                }
            }
            if let detached = detachLeaf(
                normalizedURL: normalizedURL,
                list: list,
                node: child,
                inReadingList: currentlyInReadingList
            ) {
                return detached
            }
        }
        return nil
    }

    private static func contains(normalizedURL: String, list: BookmarkListKind, in root: NSMutableDictionary) -> Bool {
        contains(normalizedURL: normalizedURL, list: list, node: root, inReadingList: false)
    }

    private static func contains(
        normalizedURL: String,
        list: BookmarkListKind,
        node: NSDictionary,
        inReadingList: Bool
    ) -> Bool {
        let title = node["Title"] as? String ?? ""
        let currentlyInReadingList = inReadingList || title == "com.apple.ReadingList"
        if let url = leafURL(in: node),
           SafariBookmarkIndex.normalizeURL(url) == normalizedURL {
            let isReadingListLeaf = currentlyInReadingList || node["ReadingList"] is NSDictionary
            return list == .readingList ? isReadingListLeaf : !isReadingListLeaf
        }
        guard let children = node["Children"] as? NSArray else { return false }
        for child in children {
            guard let childNode = child as? NSDictionary else { continue }
            if contains(normalizedURL: normalizedURL, list: list, node: childNode, inReadingList: currentlyInReadingList) {
                return true
            }
        }
        return false
    }

    private static func parentFolderUUID(
        for normalizedURL: String,
        list: BookmarkListKind,
        node: NSMutableDictionary,
        parentUUID: String?
    ) -> String? {
        let title = node["Title"] as? String ?? ""
        let inReadingList = title == "com.apple.ReadingList"
        let nodeUUID = node["WebBookmarkUUID"] as? String
        let folderUUID = node["WebBookmarkType"] as? String == "WebBookmarkTypeList" ? nodeUUID : parentUUID

        if let url = leafURL(in: node),
           SafariBookmarkIndex.normalizeURL(url) == normalizedURL {
            let isReadingListLeaf = inReadingList || node["ReadingList"] is NSDictionary
            let matches = list == .readingList ? isReadingListLeaf : !isReadingListLeaf
            return matches ? parentUUID : nil
        }

        guard let children = node["Children"] as? NSArray else { return nil }
        for child in children {
            guard let childNode = child as? NSMutableDictionary else { continue }
            if let found = parentFolderUUID(
                for: normalizedURL,
                list: list,
                node: childNode,
                parentUUID: folderUUID
            ) {
                return found
            }
        }
        return nil
    }

    private static func collectFolders(node: NSDictionary, depth: Int, into folders: inout [BookmarkFolderInfo]) {
        let type = node["WebBookmarkType"] as? String
        let title = node["Title"] as? String ?? ""
        if type == "WebBookmarkTypeList", title != "com.apple.ReadingList" {
            if let uuid = node["WebBookmarkUUID"] as? String {
                let identifier = node["WebBookmarkIdentifier"] as? String
                folders.append(BookmarkFolderInfo(
                    uuid: uuid,
                    title: displayFolderTitle(title, identifier: identifier),
                    depth: depth
                ))
            }
            if let children = node["Children"] as? NSArray {
                for child in children {
                    guard let childNode = child as? NSDictionary else { continue }
                    collectFolders(node: childNode, depth: depth + 1, into: &folders)
                }
            }
            return
        }
        guard let children = node["Children"] as? NSArray else { return }
        for child in children {
            guard let childNode = child as? NSDictionary else { continue }
            collectFolders(node: childNode, depth: depth, into: &folders)
        }
    }

    /// Safari plist folder labels mapped for the popup.
    /// Chrome analog: Bookmarks bar ≈ Favorites, Other bookmarks ≈ Bookmarks Menu.
    /// The plist root list has an empty Title; show it as "Bookmarks".
    private static func displayFolderTitle(_ title: String, identifier: String? = nil) -> String {
        if title.isEmpty {
            if identifier == "BookmarksBar" { return "Favorites" }
            if identifier == "BookmarksMenu" { return "Bookmarks Menu" }
            return "Bookmarks"
        }
        switch title {
        case "BookmarksBar": return "Favorites"
        case "BookmarksMenu": return "Bookmarks Menu"
        default: return title
        }
    }

    private static func findFolder(named title: String, in node: NSMutableDictionary) -> NSMutableDictionary? {
        if node["Title"] as? String == title,
           node["WebBookmarkType"] as? String == "WebBookmarkTypeList" {
            return node
        }
        guard let children = node["Children"] as? NSArray else { return nil }
        for child in children {
            guard let childNode = child as? NSMutableDictionary else { continue }
            if let match = findFolder(named: title, in: childNode) { return match }
        }
        return nil
    }

    private static func findFolder(uuid: String, in node: NSMutableDictionary) -> NSMutableDictionary? {
        if node["WebBookmarkUUID"] as? String == uuid,
           node["WebBookmarkType"] as? String == "WebBookmarkTypeList" {
            return node
        }
        guard let children = node["Children"] as? NSArray else { return nil }
        for child in children {
            guard let childNode = child as? NSMutableDictionary else { continue }
            if let match = findFolder(uuid: uuid, in: childNode) { return match }
        }
        return nil
    }

    /// PropertyListSerialization often returns NSArray for Children. Copy before remove.
    private static func mutableChildren(of node: NSMutableDictionary) -> NSMutableArray? {
        if let mutable = node["Children"] as? NSMutableArray { return mutable }
        if let immutable = node["Children"] as? NSArray {
            let mutable = NSMutableArray(array: immutable)
            node["Children"] = mutable
            return mutable
        }
        return nil
    }

    private static func folderChildren(_ folder: NSMutableDictionary) -> NSMutableArray {
        if let existing = mutableChildren(of: folder) { return existing }
        let children = NSMutableArray()
        folder["Children"] = children
        return children
    }

    private static func makeLeaf(
        url: String,
        title: String?,
        list: BookmarkListKind,
        template: NSMutableArray
    ) -> NSMutableDictionary {
        if let sample = firstLeaf(in: template) {
            let leaf = (sample.mutableCopy() as? NSMutableDictionary) ?? NSMutableDictionary()
            leaf["WebBookmarkType"] = "WebBookmarkTypeLeaf"
            leaf["WebBookmarkUUID"] = UUID().uuidString
            leaf["URLString"] = url
            let displayTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? url
            if let uri = leaf["URIDictionary"] as? NSMutableDictionary {
                uri["title"] = displayTitle
            } else {
                leaf["URIDictionary"] = NSMutableDictionary(dictionary: ["title": displayTitle])
            }
            leaf.removeObject(forKey: "ReadingList")
            leaf.removeObject(forKey: "ReadingListNonSync")
            if list == .readingList {
                leaf["ReadingList"] = NSMutableDictionary(dictionary: [
                    "DateAdded": Date(),
                    "PreviewText": "",
                ])
            }
            return leaf
        }

        let leaf = NSMutableDictionary()
        leaf["WebBookmarkType"] = "WebBookmarkTypeLeaf"
        leaf["WebBookmarkUUID"] = UUID().uuidString
        leaf["URLString"] = url
        let displayTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? url
        leaf["URIDictionary"] = NSMutableDictionary(dictionary: ["title": displayTitle])
        if list == .readingList {
            leaf["ReadingList"] = NSMutableDictionary(dictionary: [
                "DateAdded": Date(),
                "PreviewText": "",
            ])
        }
        return leaf
    }

    private static func firstLeaf(in children: NSArray) -> NSMutableDictionary? {
        for child in children {
            guard let node = child as? NSMutableDictionary else { continue }
            if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf" {
                return node
            }
            if let nested = node["Children"] as? NSArray,
               let leaf = firstLeaf(in: nested) {
                return leaf
            }
        }
        return nil
    }

    private static func leafURL(in node: NSDictionary) -> String? {
        let type = node["WebBookmarkType"] as? String
        if type == "WebBookmarkTypeList" || type == "WebBookmarkTypeProxy" { return nil }
        if let urlString = node["URLString"] as? String, !urlString.isEmpty { return urlString }
        if let uri = node["URIDictionary"] as? NSDictionary,
           let urlString = uri["URLString"] as? String,
           !urlString.isEmpty { return urlString }
        return nil
    }
}

enum BookmarkFolderSettings {
    private static let lastFolderKey = "lastBookmarkFolderUUID"

    static func lastFolderUUID() -> String? {
        PatrickConstants.sharedDefaults?.string(forKey: lastFolderKey)
    }

    static func setLastFolderUUID(_ uuid: String) {
        PatrickConstants.sharedDefaults?.set(uuid, forKey: lastFolderKey)
    }
}
