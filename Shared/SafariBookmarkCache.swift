import Darwin
import Foundation
import os.log

enum SafariBookmarkCache {
    private static var processIndex: SafariBookmarkIndex?
    private static var processFileMtime: Date?

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PatrickConstants.appGroupID)
    }

    static var safariBookmarksURL: URL {
        RealUserHome.url.appendingPathComponent("Library/Safari/Bookmarks.plist", isDirectory: false)
    }

    static func loadCachedIndex() -> SafariBookmarkIndex {
        if let processIndex {
            return processIndex
        }
        guard let defaults = PatrickConstants.sharedDefaults else { return .empty }
        let bookmarks = Set(defaults.stringArray(forKey: PatrickConstants.bookmarkURLsKey) ?? [])
        let readingList = Set(defaults.stringArray(forKey: PatrickConstants.readingListURLsKey) ?? [])
        let refreshedAt = defaults.object(forKey: PatrickConstants.lastRefreshKey) as? Date ?? .distantPast
        let index = SafariBookmarkIndex(bookmarkURLs: bookmarks, readingListURLs: readingList, refreshedAt: refreshedAt)
        processIndex = index
        let storedMtime = defaults.double(forKey: PatrickConstants.safariFileMtimeKey)
        processFileMtime = storedMtime > 0 ? Date(timeIntervalSince1970: storedMtime) : nil
        return index
    }

    static func hasAccess() -> Bool {
        return PatrickConstants.sharedDefaults?.bool(forKey: PatrickConstants.hasAccessKey) ?? false
    }

    static func save(
        _ index: SafariBookmarkIndex,
        safariFileModificationDate: Date? = nil
    ) {
        let defaults = PatrickConstants.sharedDefaults
        let storedMtime = defaults?.double(forKey: PatrickConstants.safariFileMtimeKey) ?? 0
        let fileMtime = safariFileModificationDate
            ?? (storedMtime > 0 ? Date(timeIntervalSince1970: storedMtime) : nil)
        let previous = processIndex ?? loadCachedIndex()

        if index.bookmarkURLs.isEmpty && index.readingListURLs.isEmpty,
           hasAccess(),
           !previous.bookmarkURLs.isEmpty || !previous.readingListURLs.isEmpty {
            os_log(.error, "Patrick refused to replace bookmark cache with an empty parse.")
            return
        }

        processIndex = index
        processFileMtime = fileMtime

        guard let defaults else { return }
        defaults.set(Array(index.bookmarkURLs).sorted(), forKey: PatrickConstants.bookmarkURLsKey)
        defaults.set(Array(index.readingListURLs).sorted(), forKey: PatrickConstants.readingListURLsKey)
        defaults.set(index.refreshedAt, forKey: PatrickConstants.lastRefreshKey)
        defaults.set(true, forKey: PatrickConstants.hasAccessKey)
        defaults.set(fileMtime?.timeIntervalSince1970 ?? 0, forKey: PatrickConstants.safariFileMtimeKey)
        defaults.set(SafariBookmarkIndex.parserVersion, forKey: PatrickConstants.bookmarkParserVersionKey)
        defaults.synchronize()
    }

    static func importFromKnownSafariLocation() throws -> SafariBookmarkIndex {
        let url = safariBookmarksURL
        let data = try readSafariBookmarksData(from: url)
        let index = try SafariBookmarkIndex.load(from: data)
        save(
            index,
            safariFileModificationDate: modificationDate(at: url)
        )
        return index
    }

    @discardableResult
    static func refreshIfSafariFileChanged() -> SafariBookmarkIndex? {
        let fileDate = safariBookmarksModificationDate()
        if let fileDate,
           let processFileMtime,
           let processIndex,
           fileDate.timeIntervalSince(processFileMtime) <= 0,
           !isEmpty(processIndex) {
            return processIndex
        }

        let cached = loadCachedIndex()
        let defaults = PatrickConstants.sharedDefaults
        let cacheVersion = defaults?.integer(forKey: PatrickConstants.bookmarkParserVersionKey) ?? 0
        let storedMtime = processFileMtime ?? {
            let timestamp = defaults?.double(forKey: PatrickConstants.safariFileMtimeKey) ?? 0
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }()
        if cacheVersion >= SafariBookmarkIndex.parserVersion,
           let fileDate,
           let storedMtime,
           fileDate.timeIntervalSince(storedMtime) <= 0,
           !isEmpty(cached) {
            return cached
        }

        // A failed stat is usually TCC or a mid-write. Keep the last good cache.
        if fileDate == nil {
            return cached
        }

        if let index = refreshFromStoredBookmark() {
            if !isEmpty(index) || isEmpty(cached) {
                return index
            }
        } else {
            return cached
        }

        for attempt in 0..<5 {
            usleep(25_000)
            if let index = refreshFromStoredBookmark(), !isEmpty(index) {
                return index
            }
            if attempt == 4 {
                os_log(.error, "Patrick kept the previous bookmark cache after a busy Safari write.")
            }
        }
        return cached
    }

    private static func isEmpty(_ index: SafariBookmarkIndex) -> Bool {
        index.bookmarkURLs.isEmpty && index.readingListURLs.isEmpty
    }

    static func safariBookmarksModificationDate() -> Date? {
        modificationDate(at: safariBookmarksURL)
    }

    private static func modificationDate(at url: URL) -> Date? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        let seconds = TimeInterval(info.st_mtimespec.tv_sec)
        let nanos = TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        return Date(timeIntervalSince1970: seconds + nanos)
    }

    @discardableResult
    static func refreshFromStoredBookmark() -> SafariBookmarkIndex? {
        do {
            return try importFromKnownSafariLocation()
        } catch {
            os_log(.error, "Patrick Safari read failed: %{public}@", error.localizedDescription)
            return nil
        }
    }

    private static func readSafariBookmarksData(from url: URL) throws -> Data {
        var coordinatorError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinatorError
        ) { coordinatedURL in
            result = Result { try POSIXFileRead.data(atPath: coordinatedURL.path) }
        }
        if coordinatorError != nil {
            return try POSIXFileRead.data(atPath: url.path)
        }
        switch result {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        case nil:
            return try POSIXFileRead.data(atPath: url.path)
        }
    }

}

enum ConnectError: LocalizedError {
    case needsFullDiskAccess

    var errorDescription: String? {
        switch self {
        case .needsFullDiskAccess:
            "Turn on Patrick in System Settings. Then return to this window."
        }
    }
}
