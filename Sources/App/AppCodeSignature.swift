import Foundation
import Security

/// Diagnostic information only. A valid signature is not an Accessibility grant
/// and does not prove that macOS still has an older registration.
struct AppCodeSignature {
    let isAdHoc: Bool?
    let validationSucceeded: Bool

    static func current() -> AppCodeSignature {
        let unknown = AppCodeSignature(isAdHoc: nil, validationSucceeded: false)
        var runningCode: SecCode?
        guard SecCodeCopySelf([], &runningCode) == errSecSuccess,
              let runningCode else { return unknown }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(runningCode, [], &staticCode) == errSecSuccess,
              let staticCode else { return unknown }
        let valid = SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess,
              let values = information as? [String: Any],
              let flags = values[kSecCodeInfoFlags as String] as? NSNumber else { return unknown }
        return AppCodeSignature(isAdHoc: SecCodeSignatureFlags(rawValue: flags.uint32Value).contains(.adhoc),
                                validationSucceeded: valid)
    }

    func accessibilityRecoveryMessage(appPath: String) -> String {
        var message = "macOS is not granting Accessibility access to this running copy of Tabbed. Window management is inactive.\n\n"
        if validationSucceeded, isAdHoc == true {
            message += "This build uses a local ad-hoc signature. After an update, an enabled entry can still refer to an older copy. Tabbed cannot confirm or remove that entry itself.\n\n"
        } else if !validationSucceeded {
            message += "Tabbed could not verify its code signature. This does not identify the cause of the missing permission.\n\n"
        }
        message += "In System Settings → Privacy & Security → Accessibility:\n"
        message += "• If Tabbed is absent, add the current app and turn it ON.\n"
        message += "• If Tabbed is already ON but access is still inactive, select its old entry, press − to remove it, then press + to add the current app again and turn it ON. Remove only Tabbed's entry.\n\n"
        message += "Current app:\n\(appPath)\n\n"
        message += "Tabbed will recheck permission automatically and start monitoring once access takes effect. If it stays inactive, choose Recheck Accessibility Permission from its menu."
        return message
    }
}
