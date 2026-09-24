import Foundation

struct SafariBookmarkIndex: Codable, Equatable {
    let bookmarkURLs: Set<String>
    let readingListURLs: Set<String>
    let refreshedAt: Date

    static let parserVersion = 3
    static let empty = SafariBookmarkIndex(bookmarkURLs: [], readingListURLs: [], refreshedAt: .distantPast)

    func contains(_ url: String, in list: BookmarkListKind) -> Bool {
        let normalized = Self.normalizeURL(url)
        guard !normalized.isEmpty else { return false }
        switch list {
        case .bookmark: return bookmarkURLs.contains(normalized)
        case .readingList: return readingListURLs.contains(normalized)
        }
    }

    static func normalizeURL(_ raw: String) -> String {
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased()
        else { return "" }

        components.scheme = scheme
        components.host = host
        components.fragment = nil

        var path = components.percentEncodedPath
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
            components.percentEncodedPath = path
        }

        guard let normalized = components.url?.absoluteString else { return "" }
        return normalized
    }

    static func load(from plistURL: URL) throws -> SafariBookmarkIndex {
        try load(from: try POSIXFileRead.data(atPath: plistURL.path))
    }

    static func load(from data: Data) throws -> SafariBookmarkIndex {
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let root = propertyList as? NSDictionary else {
            return .empty
        }

        var bookmarkURLs = Set<String>()
        var readingListURLs = Set<String>()
        walk(node: root, inReadingList: false, bookmarkURLs: &bookmarkURLs, readingListURLs: &readingListURLs)

        return SafariBookmarkIndex(
            bookmarkURLs: bookmarkURLs,
            readingListURLs: readingListURLs,
            refreshedAt: Date()
        )
    }

    private static func walk(
        node: NSDictionary,
        inReadingList: Bool,
        bookmarkURLs: inout Set<String>,
        readingListURLs: inout Set<String>
    ) {
        let title = node["Title"] as? String ?? ""
        let inReadingListFolder = inReadingList || title == "com.apple.ReadingList"

        if let urlString = leafURLString(in: node) {
            let normalized = normalizeURL(urlString)
            if !normalized.isEmpty {
                if inReadingListFolder || isReadingListLeaf(node) {
                    readingListURLs.insert(normalized)
                } else {
                    bookmarkURLs.insert(normalized)
                }
            }
        }

        guard let children = node["Children"] as? NSArray else { return }
        for child in children {
            guard let childNode = child as? NSDictionary else { continue }
            walk(
                node: childNode,
                inReadingList: inReadingListFolder,
                bookmarkURLs: &bookmarkURLs,
                readingListURLs: &readingListURLs
            )
        }
    }

    private static func isReadingListLeaf(_ node: NSDictionary) -> Bool {
        guard node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf" else { return false }
        return node["ReadingList"] is NSDictionary
    }

    private static func leafURLString(in node: NSDictionary) -> String? {
        let type = node["WebBookmarkType"] as? String
        if type == "WebBookmarkTypeList" || type == "WebBookmarkTypeProxy" {
            return nil
        }
        if let urlString = node["URLString"] as? String, !urlString.isEmpty {
            return urlString
        }
        if let uri = node["URIDictionary"] as? NSDictionary,
           let urlString = uri["URLString"] as? String,
           !urlString.isEmpty {
            return urlString
        }
        return nil
    }
}
