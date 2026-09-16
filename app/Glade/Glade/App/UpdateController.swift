import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class UpdateController {
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false

    @ObservationIgnored private let delegate: UpdaterDelegate
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var hasStarted = false

    init() {
        let delegate = UpdaterDelegate()
        self.delegate = delegate // Sparkle retains its delegate weakly.
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        #if DEBUG
        // Set these before starting so a development build never schedules an update.
        controller.updater.automaticallyChecksForUpdates = false
        controller.updater.automaticallyDownloadsUpdates = false
        #endif
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let value = updater.canCheckForUpdates
                Task { @MainActor [weak self] in self?.canCheckForUpdates = value }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let value = updater.automaticallyChecksForUpdates
                Task { @MainActor [weak self] in self?.automaticallyChecksForUpdates = value }
            },
        ]
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        #if !DEBUG
        controller.updater.automaticallyChecksForUpdates = enabled
        #endif
    }

    func channelDidChange() {
        // Re-read the selected channels on the next check, including a scheduled check.
        controller.updater.resetUpdateCycleAfterShortDelay()
    }
}

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UpdateChannel.current().sparkleAllowedChannels
    }
}
