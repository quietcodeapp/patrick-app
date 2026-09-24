import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var accessStore: SafariAccessStore

    var body: some View {
        Form {
            Section("Safari") {
                Label(
                    accessStore.isConnected ? "Connected" : "Not connected",
                    systemImage: accessStore.isConnected ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(accessStore.isConnected ? .green : .orange)

                if accessStore.isConnected {
                    Text(accessStore.connectionSummary)
                        .foregroundStyle(.secondary)

                    if let lastRefresh = accessStore.lastRefresh {
                        Text("Last updated \(lastRefresh.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !accessStore.isConnected {
                    Button("Connect Safari") {
                        accessStore.connectSafari()
                    }
                }

                if accessStore.isConnected {
                    Text("Safari extensions update the toolbar on their own. You can quit Patrick after you connect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if accessStore.needsFullDiskAccess && !accessStore.isConnected {
                    Text("If Patrick is not listed, click + in Full Disk Access and choose /Applications/Patrick.app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Turn On in System Settings") {
                        accessStore.openPrivacySettings()
                    }
                }
            }

            Section("Extensions") {
                ExtensionRowsView()
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 520)
        .navigationTitle("Patrick")
        .onAppear {
            accessStore.reloadFromDefaults()
            accessStore.refreshExtensions()
        }
    }
}
