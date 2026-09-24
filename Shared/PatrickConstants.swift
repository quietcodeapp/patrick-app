import Foundation

enum PatrickConstants {
    static let appGroupID = "group.ltd.quietcode.patrick"
    static let bookmarkURLsKey = "bookmarkURLs"
    static let readingListURLsKey = "readingListURLs"
    static let lastRefreshKey = "lastRefreshDate"
    static let hasAccessKey = "hasBookmarksAccess"
    static let safariFileMtimeKey = "safariFileModificationTime"
    static let bookmarkParserVersionKey = "bookmarkParserVersion"
    static let bookmarkExtensionPingKey = "extensionLastPing.bookmark"
    static let readingListExtensionPingKey = "extensionLastPing.readingList"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func fillColorHex(for list: BookmarkListKind) -> String {
        switch list {
        case .bookmark: "#e67e7c"
        case .readingList: "#f0d04e"
        }
    }
}

enum BookmarkListKind: String, Codable {
    case bookmark
    case readingList
}
