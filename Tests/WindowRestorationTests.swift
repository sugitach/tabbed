import Foundation
import XCTest

/// XCTest adapter for the same CLT-only behavioral suite used by Tests/test.sh.
/// No production type introduced by a fix is referenced by this target.
final class WindowRestorationTests: XCTestCase {
    func testWindowManagementRegressions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("Tests/test.sh").path, "internal"]
        process.currentDirectoryURL = root
        // Inherit output so compiler errors and individual failures remain visible.
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "See the internal regression output and result.json")
    }
}
