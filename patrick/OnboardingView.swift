import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var accessStore: SafariAccessStore
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Patrick")
                    .font(.largeTitle.bold())
                Text("Filled toolbar icons show when a page is in your Safari bookmarks or Reading List.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Step 1 — Connect Safari") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        accessStore.isConnected ? "Safari is connected" : "Safari is not connected",
                        systemImage: accessStore.isConnected ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(accessStore.isConnected ? .green : .primary)

                    if accessStore.isConnected {
                        Text(accessStore.connectionSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(accessStore.statusMessage)
                            .font(.callout)
                    }

                    if !accessStore.isConnected {
                        Button("Connect Safari") {
                            accessStore.connectSafari()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Step 2 — Turn on extensions") {
                ExtensionRowsView()
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!accessStore.isConnected)
            }
        }
        .padding(28)
        .frame(minWidth: 520, minHeight: 560)
        .onAppear {
            accessStore.reloadFromDefaults()
            accessStore.refreshExtensions()
        }
    }
}
