import AppKit
import Combine
import Darwin
import Foundation
import os.log

enum PatrickExtension: String, CaseIterable, Identifiable {
    case bookmark
    case readingList

    var id: String { rawValue }

    var listKind: BookmarkListKind {
        switch self {
        case .bookmark: .bookmark
        case .readingList: .readingList
        }
    }

    var displayName: String {
        switch self {
        case .bookmark: "Patrick Bookmark Star"
        case .readingList: "Patrick Readling List"
        }
    }
}

enum ExtensionEnablement: Equatable {
    case checking
    case on
    case off
}

@MainActor
final class SafariAccessStore: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var bookmarkCount = 0
    @Published private(set) var readingListCount = 0
    @Published private(set) var statusMessage = "Connect Safari to show filled icons in the toolbar."
    @Published private(set) var needsFullDiskAccess = false
    @Published private(set) var bookmarkEnablement: ExtensionEnablement = .checking
    @Published private(set) var readingListEnablement: ExtensionEnablement = .checking

    private var waitingForFullDiskAccess = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        reloadFromDefaults()
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.waitingForFullDiskAccess && !self.isConnected {
                    _ = self.finishConnectIfPossible()
                }
                self.refreshExtensions()
            }
            .store(in: &cancellables)
        Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshExtensions() }
            .store(in: &cancellables)
        refreshExtensions()
    }

    var connectionSummary: String {
        guard isConnected else { return "Safari is not connected." }
        return "\(bookmarkCount) saved pages, \(readingListCount) reading list items."
    }

    func reloadFromDefaults() {
        if SafariBookmarkCache.containerURL == nil {
            os_log(.error, "Patrick App Group container is unavailable.")
            statusMessage = "Could not connect. Try again."
            isConnected = false
            return
        }
        applyIndex(SafariBookmarkCache.loadCachedIndex(), connected: SafariBookmarkCache.hasAccess())
    }

    func connectSafari() {
        if finishConnectIfPossible() {
            return
        }
        waitingForFullDiskAccess = true
        needsFullDiskAccess = true
        statusMessage = ConnectError.needsFullDiskAccess.errorDescription ?? "Could not connect. Try again."
        openFullDiskAccessSettings()
    }

    func openPrivacySettings() {
        waitingForFullDiskAccess = true
        needsFullDiskAccess = true
        openFullDiskAccessSettings()
    }

    func enablement(of extension: PatrickExtension) -> ExtensionEnablement {
        switch `extension` {
        case .bookmark: bookmarkEnablement
        case .readingList: readingListEnablement
        }
    }

    func refreshExtensions() {
        for item in PatrickExtension.allCases {
            let key = item == .bookmark
                ? PatrickConstants.bookmarkExtensionPingKey
                : PatrickConstants.readingListExtensionPingKey
            let timestamp = PatrickConstants.sharedDefaults?.double(forKey: key) ?? 0
            let value: ExtensionEnablement = timestamp > 0 && Date().timeIntervalSince1970 - timestamp < 120 ? .on : .off
            switch item {
            case .bookmark: bookmarkEnablement = value
            case .readingList: readingListEnablement = value
            }
        }
    }

    @discardableResult
    private func finishConnectIfPossible() -> Bool {
        do {
            let index = try SafariBookmarkCache.importFromKnownSafariLocation()
            waitingForFullDiskAccess = false
            needsFullDiskAccess = false
            applyIndex(index, connected: true)
            return true
        } catch {
            os_log(.error, "Patrick Safari read failed: %{public}@", error.localizedDescription)
            return false
        }
    }

    private func applyIndex(_ index: SafariBookmarkIndex, connected: Bool) {
        isConnected = connected
        lastRefresh = index.refreshedAt == .distantPast ? nil : index.refreshedAt
        bookmarkCount = index.bookmarkURLs.count
        readingListCount = index.readingListURLs.count
        statusMessage = connected
            ? "Safari is connected. \(connectionSummary)"
            : "Connect Safari to show filled icons in the toolbar."
    }

    private func openFullDiskAccessSettings() {
        let home = RealUserHome.url
        let paths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path,
            home.appendingPathComponent("Library/Mail").path,
            home.appendingPathComponent("Library/Safari/Bookmarks.plist").path,
        ]
        for path in paths {
            let descriptor = open(path, O_RDONLY | O_CLOEXEC)
            if descriptor >= 0 { close(descriptor) }
        }

        let settingsURLs = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for string in settingsURLs {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
