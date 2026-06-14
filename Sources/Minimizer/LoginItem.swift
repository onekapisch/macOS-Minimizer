import ServiceManagement

/// Thin wrapper over SMAppService for the "Launch at Login" feature.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns an error if the change failed, otherwise nil.
    @discardableResult
    static func setEnabled(_ enable: Bool) -> Error? {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error
        }
    }
}
