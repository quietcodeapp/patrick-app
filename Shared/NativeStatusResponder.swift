import Foundation

// Native bridge for Safari Web Extension messages.
// bookmark: popup add/remove/move + folders; readingList: toolbar toggle.
// add/remove/move: merge a single leaf into or out of the plist, then refresh the cache.

struct NativeLookupRequest: Decodable {
    let action: String
    let url: String?
    let list: String?
    let title: String?
    let folderUUID: String?
}

struct NativeLookupResponse: Encodable {
    let inList: Bool
    let color: String
    let hasAccess: Bool
    let error: String?
    let folderUUID: String?
}

enum NativeStatusResponder {
    static func handle(message: Any?, list: BookmarkListKind) -> [String: Any] {
        recordPing(for: list)
        guard let payload = decodeRequest(from: message) else {
            return encode(response(for: list, inList: false, hasAccess: false, error: "invalid_request"))
        }

        switch payload.action {
        case "lookup":
            return handleLookup(payload, extensionList: list)
        case "toggle":
            return handleToggle(payload, extensionList: list)
        case "add":
            return handleAdd(payload, extensionList: list)
        case "remove":
            return handleRemove(payload, extensionList: list)
        case "move":
            return handleMove(payload)
        case "folders":
            return handleFolders()
        default:
            return encode(response(for: list, inList: false, hasAccess: false, error: "unknown_action"))
        }
    }

    private static func handleLookup(_ request: NativeLookupRequest, extensionList: BookmarkListKind) -> [String: Any] {
        let color = PatrickConstants.fillColorHex(for: extensionList)
        let index = SafariBookmarkCache.refreshIfSafariFileChanged() ?? SafariBookmarkCache.loadCachedIndex()

        guard SafariBookmarkCache.hasAccess() else {
            return encode(response(for: extensionList, inList: false, hasAccess: false, error: "no_access", color: color))
        }

        guard let url = request.url,
              let listRaw = request.list,
              let list = BookmarkListKind(rawValue: listRaw)
        else {
            return encode(response(for: extensionList, inList: false, hasAccess: true, error: "missing_fields", color: color))
        }

        let folderUUID = (try? SafariBookmarkMutator.folderUUID(forURL: url, list: list))
        return encode(response(
            for: extensionList,
            inList: index.contains(url, in: list),
            hasAccess: true,
            folderUUID: folderUUID,
            color: color
        ))
    }

    private static func handleToggle(_ request: NativeLookupRequest, extensionList: BookmarkListKind) -> [String: Any] {
        let color = PatrickConstants.fillColorHex(for: extensionList)
        guard SafariBookmarkCache.hasAccess() else {
            return encode(response(for: extensionList, inList: false, hasAccess: false, error: "no_access", color: color))
        }
        guard let url = request.url,
              let listRaw = request.list,
              let list = BookmarkListKind(rawValue: listRaw)
        else {
            return encode(response(for: extensionList, inList: false, hasAccess: true, error: "missing_fields", color: color))
        }

        let index = SafariBookmarkCache.refreshIfSafariFileChanged() ?? SafariBookmarkCache.loadCachedIndex()
        let currentlyIn = index.contains(url, in: list)

        do {
            if currentlyIn {
                try SafariBookmarkMutator.remove(url: url, from: list)
            } else {
                try SafariBookmarkMutator.add(url: url, title: request.title, to: list, folderUUID: request.folderUUID)
            }
            let refreshed = SafariBookmarkCache.refreshFromStoredBookmark() ?? index
            let folderUUID = (try? SafariBookmarkMutator.folderUUID(forURL: url, list: list))
            return encode(response(
                for: extensionList,
                inList: refreshed.contains(url, in: list),
                hasAccess: true,
                folderUUID: folderUUID,
                color: color
            ))
        } catch {
            return encode(response(
                for: extensionList,
                inList: currentlyIn,
                hasAccess: true,
                error: (error as? LocalizedError)?.errorDescription ?? "toggle_failed",
                color: color
            ))
        }
    }

    private static func handleAdd(_ request: NativeLookupRequest, extensionList: BookmarkListKind) -> [String: Any] {
        let color = PatrickConstants.fillColorHex(for: extensionList)
        guard SafariBookmarkCache.hasAccess() else {
            return encode(response(for: extensionList, inList: false, hasAccess: false, error: "no_access", color: color))
        }
        guard let url = request.url,
              let listRaw = request.list,
              let list = BookmarkListKind(rawValue: listRaw)
        else {
            return encode(response(for: extensionList, inList: false, hasAccess: true, error: "missing_fields", color: color))
        }

        do {
            try SafariBookmarkMutator.add(url: url, title: request.title, to: list, folderUUID: request.folderUUID)
            let refreshed = SafariBookmarkCache.refreshFromStoredBookmark() ?? SafariBookmarkCache.loadCachedIndex()
            let folderUUID = (try? SafariBookmarkMutator.folderUUID(forURL: url, list: list))
            return encode(response(
                for: extensionList,
                inList: refreshed.contains(url, in: list),
                hasAccess: true,
                folderUUID: folderUUID,
                color: color
            ))
        } catch {
            return encode(response(for: extensionList, inList: false, hasAccess: true, error: (error as? LocalizedError)?.errorDescription ?? "add_failed", color: color))
        }
    }

    private static func handleRemove(_ request: NativeLookupRequest, extensionList: BookmarkListKind) -> [String: Any] {
        let color = PatrickConstants.fillColorHex(for: extensionList)
        guard SafariBookmarkCache.hasAccess() else {
            return encode(response(for: extensionList, inList: false, hasAccess: false, error: "no_access", color: color))
        }
        guard let url = request.url,
              let listRaw = request.list,
              let list = BookmarkListKind(rawValue: listRaw)
        else {
            return encode(response(for: extensionList, inList: false, hasAccess: true, error: "missing_fields", color: color))
        }

        let index = SafariBookmarkCache.refreshIfSafariFileChanged() ?? SafariBookmarkCache.loadCachedIndex()
        let currentlyIn = index.contains(url, in: list)

        do {
            try SafariBookmarkMutator.remove(url: url, from: list)
            let refreshed = SafariBookmarkCache.refreshFromStoredBookmark() ?? index
            return encode(response(
                for: extensionList,
                inList: refreshed.contains(url, in: list),
                hasAccess: true,
                color: color
            ))
        } catch {
            return encode(response(for: extensionList, inList: currentlyIn, hasAccess: true, error: (error as? LocalizedError)?.errorDescription ?? "remove_failed", color: color))
        }
    }

    private static func handleMove(_ request: NativeLookupRequest) -> [String: Any] {
        let color = PatrickConstants.fillColorHex(for: .bookmark)
        guard SafariBookmarkCache.hasAccess() else {
            return encode(response(for: .bookmark, inList: false, hasAccess: false, error: "no_access", color: color))
        }
        guard let url = request.url, let folderUUID = request.folderUUID else {
            return encode(response(for: .bookmark, inList: false, hasAccess: true, error: "missing_fields", color: color))
        }

        let index = SafariBookmarkCache.refreshIfSafariFileChanged() ?? SafariBookmarkCache.loadCachedIndex()
        do {
            try SafariBookmarkMutator.move(url: url, toFolderUUID: folderUUID)
            let refreshed = SafariBookmarkCache.refreshFromStoredBookmark() ?? index
            return encode(response(
                for: .bookmark,
                inList: refreshed.contains(url, in: .bookmark),
                hasAccess: true,
                folderUUID: folderUUID,
                color: color
            ))
        } catch {
            return encode(response(
                for: .bookmark,
                inList: index.contains(url, in: .bookmark),
                hasAccess: true,
                error: (error as? LocalizedError)?.errorDescription ?? "move_failed",
                folderUUID: (try? SafariBookmarkMutator.folderUUID(forURL: url, list: .bookmark)),
                color: color
            ))
        }
    }

    private static func handleFolders() -> [String: Any] {
        guard SafariBookmarkCache.hasAccess() else {
            return ["folders": [], "hasAccess": false, "error": "no_access"]
        }
        do {
            let folders = try SafariBookmarkMutator.listBookmarkFolders()
            let data = try JSONEncoder().encode(folders)
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            return [
                "folders": json,
                "hasAccess": true,
                "lastFolderUUID": resolvedDefaultFolderUUID(from: folders)
            ]
        } catch {
            return ["folders": [], "hasAccess": true, "error": (error as? LocalizedError)?.errorDescription ?? "folders_failed"]
        }
    }

    private static func resolvedDefaultFolderUUID(from folders: [BookmarkFolderInfo]) -> String {
        let last = BookmarkFolderSettings.lastFolderUUID() ?? ""
        if folders.contains(where: { $0.uuid == last }) {
            return last
        }
        return folders.first(where: { $0.depth == 0 })?.uuid ?? folders.first?.uuid ?? ""
    }

    private static func decodeRequest(from message: Any?) -> NativeLookupRequest? {
        if let dictionary = message as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dictionary),
           let request = try? JSONDecoder().decode(NativeLookupRequest.self, from: data) {
            return request
        }

        if let text = message as? String,
           let data = text.data(using: .utf8),
           let request = try? JSONDecoder().decode(NativeLookupRequest.self, from: data) {
            return request
        }

        return nil
    }

    private static func response(
        for list: BookmarkListKind,
        inList: Bool,
        hasAccess: Bool,
        error: String? = nil,
        folderUUID: String? = nil,
        color: String? = nil
    ) -> NativeLookupResponse {
        NativeLookupResponse(
            inList: inList,
            color: color ?? PatrickConstants.fillColorHex(for: list),
            hasAccess: hasAccess,
            error: error,
            folderUUID: folderUUID
        )
    }

    private static func encode(_ response: NativeLookupResponse) -> [String: Any] {
        var object: [String: Any] = [
            "inList": response.inList,
            "color": response.color,
            "hasAccess": response.hasAccess
        ]
        if let error = response.error {
            object["error"] = error
        }
        if let folderUUID = response.folderUUID {
            object["folderUUID"] = folderUUID
        }
        return object
    }

    static func recordPing(for list: BookmarkListKind) {
        PatrickConstants.sharedDefaults?.set(Date().timeIntervalSince1970, forKey: pingKey(for: list))
    }

    private static func pingKey(for list: BookmarkListKind) -> String {
        switch list {
        case .bookmark: PatrickConstants.bookmarkExtensionPingKey
        case .readingList: PatrickConstants.readingListExtensionPingKey
        }
    }
}
