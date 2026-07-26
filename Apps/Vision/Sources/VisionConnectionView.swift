import MacDisplayConnectTransport
import SwiftUI

struct VisionConnectionView: View {
    let model: VisionConnectionModel

    var body: some View {
        VStack(spacing: 24) {
            status
            macList
        }
        .padding(40)
        .task {
            await model.startDiscovery()
        }
        .task {
            await model.monitorStatus()
        }
    }

    private var status: some View {
        VStack(spacing: 10) {
            connectionSymbols

            HStack(spacing: 8) {
                Text(model.phase.title)

                if model.isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            .font(.title.weight(.semibold))

            Text(model.phase.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private var connectionSymbols: some View {
        HStack(spacing: 16) {
            Image(systemName: "laptopcomputer")

            Image(systemName: "ellipsis")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Image(systemName: "visionpro")
        }
        .font(.system(size: 56))
        .symbolRenderingMode(.hierarchical)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mac and Apple Vision Pro")
    }

    @ViewBuilder
    private var macList: some View {
        if model.macs.isEmpty {
            if model.phase == .searching {
                ProgressView("Searching nearby…")
                    .controlSize(.large)
            }
        } else if let actionTitle = model.phase.actionTitle {
            VStack(spacing: 12) {
                ForEach(model.macs) { mac in
                    connectButton(for: mac, title: actionTitle)
                }
            }
            .frame(maxWidth: 420)
        }
    }

    private func connectButton(
        for mac: RemoteMac,
        title: String
    ) -> some View {
        Button {
            Task {
                await model.connect(to: mac)
            }
        } label: {
            HStack {
                Image(systemName: "macbook")
                    .accessibilityHidden(true)
                Text(mac.name)
                Spacer()
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.isConnecting)
        .accessibilityHint(
            "Asks this Mac to start Mac Virtual Display."
        )
    }
}
