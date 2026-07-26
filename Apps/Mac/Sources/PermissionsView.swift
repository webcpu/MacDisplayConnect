import MacDisplayConnectTransport
import SwiftUI

struct PermissionsView: View {
    let model: ConnectionModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Permissions Required")
                    .font(.title2.weight(.semibold))

                Text(
                    "Mac Display Connect needs both permissions "
                        + "before it can connect."
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                accessibilityRow

                Divider()
                    .padding(.leading, 40)

                localNetworkRow
            }
            .padding(.horizontal, 16)
            .background(
                .quaternary.opacity(0.35),
                in: RoundedRectangle(cornerRadius: 12)
            )

            localNetworkInstructions
        }
        .frame(width: 360)
        .padding(30)
    }

    private var accessibilityRow: some View {
        HStack(spacing: 12) {
            permissionIcon(isGranted: model.accessibilityAccessGranted)

            VStack(alignment: .leading, spacing: 3) {
                Text("Accessibility")
                    .font(.headline)
                Text("Lets the app operate Screen Mirroring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if model.accessibilityAccessGranted {
                allowedLabel
            } else {
                Button("Enable") {
                    model.requestAccessibilityPermission()
                }
            }
        }
        .padding(.vertical, 14)
    }

    private var localNetworkRow: some View {
        HStack(spacing: 12) {
            permissionIcon(isGranted: model.localNetworkAccess == .granted)

            VStack(alignment: .leading, spacing: 3) {
                Text("Local Network")
                    .font(.headline)
                Text("Lets Apple Vision Pro find this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            localNetworkAction
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var localNetworkAction: some View {
        switch model.localNetworkAccess {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Checking Local Network access")
        case .granted:
            allowedLabel
        case .needsAccess:
            Button("Open Settings") {
                model.openSystemSettings()
            }
        case .unavailable:
            Text("Unavailable")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var localNetworkInstructions: some View {
        switch model.localNetworkAccess {
        case .needsAccess:
            Text(
                "In System Settings, choose Privacy & Security, "
                    + "then Local Network, and enable Mac Display Connect."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        case .unavailable:
            Text(
                "Local Network is temporarily unavailable. "
                    + "Check Wi-Fi and try again."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        case .checking:
            Text(
                "Respond to the Local Network prompt if macOS shows one."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        case .granted:
            EmptyView()
        }
    }

    private func permissionIcon(isGranted: Bool) -> some View {
        Image(
            systemName: isGranted
                ? "checkmark.circle.fill"
                : "exclamationmark.circle.fill"
        )
        .font(.title2)
        .foregroundStyle(isGranted ? Color.green : Color.orange)
        .accessibilityHidden(true)
    }

    private var allowedLabel: some View {
        Text("Allowed")
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
    }
}
