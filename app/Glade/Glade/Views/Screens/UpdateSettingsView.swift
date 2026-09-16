import SwiftUI

struct UpdateSettingsView: View {
    @Bindable var updates: UpdateController
    @AppStorage(UpdateChannel.storageKey) private var channelRaw = UpdateChannel.release.rawValue

    private var channel: UpdateChannel { UpdateChannel(rawValue: channelRaw) ?? .release }
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    var body: some View {
        Form {
            Section("Updates") {
                Picker("Update channel", selection: $channelRaw) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.displayName).tag(channel.rawValue)
                    }
                }
                Text(channel.caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                #if DEBUG
                Text("Automatic updates are disabled in development builds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                #else
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticChecks($0) }
                ))
                #endif

                if channel.requiresNewerBuild(than: UpdateChannel.installed(in: version)) {
                    Text("You’ll move to \(channel.displayName) when a newer build is available. Changing channels does not install an older version.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("Version \(version) (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: channelRaw) { _, _ in updates.channelDidChange() }
    }
}

struct CheckForUpdatesButton: View {
    @Bindable var updates: UpdateController

    var body: some View {
        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.canCheckForUpdates)
    }
}
