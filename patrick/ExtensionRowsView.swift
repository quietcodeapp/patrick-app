import SwiftUI

struct ExtensionRowsView: View {
    @EnvironmentObject private var accessStore: SafariAccessStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PatrickExtension.allCases) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(.body)
                        Text(statusLabel(accessStore.enablement(of: item)))
                            .font(.caption)
                            .foregroundStyle(statusColor(accessStore.enablement(of: item)))
                    }
                    Spacer()
                }
            }
        }
    }

    private func statusLabel(_ enablement: ExtensionEnablement) -> String {
        switch enablement {
        case .checking: "Checking…"
        case .on: "On"
        case .off: "Off"
        }
    }

    private func statusColor(_ enablement: ExtensionEnablement) -> Color {
        switch enablement {
        case .checking: .secondary
        case .on: .green
        case .off: .secondary
        }
    }
}
