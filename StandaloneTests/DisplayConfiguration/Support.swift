@MainActor final class DisplayConfigurationMonitor {
    static var key: String? = "A"
    static var appKitReady = true
    var revision: UInt64 = 0
    var pending = false
    var state: (revision: UInt64, pending: Bool) { (revision, pending) }
    func acknowledge(_ expected: UInt64) -> Bool {
        guard expected == revision else { return false }
        pending = false; return true
    }
    static func currentKey() -> String? { key }
    static func appKitMatchesQuartz() -> Bool { appKitReady }
}
