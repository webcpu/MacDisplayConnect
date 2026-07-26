import SwiftUI

struct ConnectionView: View {
    let model: ConnectionModel

    var body: some View {
        VStack(spacing: 24) {
            connectionSymbols
            statusText
            connectButton
        }
        .frame(width: 360)
        .padding(30)
        .task {
            model.refreshConnectionStatus()
            await model.startRemoteControl()
        }
    }

    private var connectionSymbols: some View {
        HStack(spacing: 16) {
            Image(systemName: "laptopcomputer")

            Image(systemName: "ellipsis")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Image(systemName: "visionpro")
        }
        .font(.system(size: 48))
        .symbolRenderingMode(.hierarchical)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mac and Apple Vision Pro")
    }

    private var statusText: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(model.phase.title)

                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            .font(.title2.weight(.semibold))

            Text(model.phase.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var connectButton: some View {
        Button {
            Task {
                await model.connectAndExtend()
            }
        } label: {
            Text(model.phase.actionTitle ?? "Connect")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.phase.actionTitle == nil)
        .opacity(model.phase.actionTitle == nil ? 0 : 1)
        .accessibilityHidden(model.phase.actionTitle == nil)
        .accessibilityHint(
            "Starts Mac Virtual Display on Apple Vision Pro."
        )
    }
}
