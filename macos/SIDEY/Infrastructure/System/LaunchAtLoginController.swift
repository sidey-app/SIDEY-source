import Foundation
import ServiceManagement

@MainActor
struct LaunchAtLoginController {
    enum Mode: Equatable {
        case mainApp
    }

    let mode: Mode

    init(mode: Mode = AppReleaseChannel.resolve().loginItemMode) {
        self.mode = mode
    }

    private var service: SMAppService {
        switch mode {
        case .mainApp: SMAppService.mainApp
        }
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
}
