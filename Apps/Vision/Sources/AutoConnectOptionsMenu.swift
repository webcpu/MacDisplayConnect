import SwiftUI

struct AutoConnectOptionsMenu: View {
    @Bindable var preference: AutoConnectPreference

    var body: some View {
        Menu {
            Toggle(
                "Automatically Reconnect",
                isOn: $preference.isEnabled
            )
        } label: {
            Label("Options", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Options")
    }
}
