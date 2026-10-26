import Foundation
import CoreGraphics
func check(_ value: @autoclosure () -> Bool, _ message: String) throws { if !value() { throw NSError(domain: message, code: 1) } }
@MainActor func diagnosticRecorderIsExplicitAndPrivate() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tabbed-diag-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = WindowDiagnosticRecorder(directory: root)
    recorder.write(.init(event: .selection, windowID: 1))
    try check(!FileManager.default.fileExists(atPath: root.path), "Disabled recording must not create a directory or log")
    try recorder.start()
    recorder.write(.init(event: .frameResult, windowID: 8, pid: 123,
        requestedFrame: [10, 20, 640, 480], sizeStatus: -25204, positionStatus: 0))
    recorder.stop()
    let url = root.appendingPathComponent("window-events.jsonl")
    let records = try String(contentsOf: url).split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
    try check(records.count == 3 && records.map { $0["sequence"] as! Int } == [1, 2, 3], "Records need one ordered session with explicit start/stop")
    let entry = records[1]["entry"] as! [String: Any]
    try check(entry["sizeStatus"] as? Int == -25204 && entry["positionStatus"] as? Int == 0, "AX result codes must survive serialization unchanged")
    try check(Set(entry.keys) == ["event", "windowID", "pid", "requestedFrame", "sizeStatus", "positionStatus"], "Diagnostic schema must not add content or free-form fields")
    let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
    let dirMode = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as! NSNumber
    try check(fileMode.intValue == 0o600 && dirMode.intValue == 0o700, "New logs and directory must be private to the user")
    let before = try Data(contentsOf: url)
    recorder.write(.init(event: .selection, windowID: 99))
    let after = try Data(contentsOf: url)
    try check(after == before, "Writes after Stop must have no effect")
}
@MainActor func diagnosticRotationAndSamplingAreBounded() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tabbed-diag-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = WindowDiagnosticRecorder(directory: root, maxBytes: 1024)
    try recorder.start()
    let sample = WindowDiagnosticEntry(event: .trackingSample, windowID: 1, cgFrame: [1, 2, 3, 4])
    recorder.write(sample); recorder.write(sample); recorder.write(sample)
    let rows = try String(contentsOf: root.appendingPathComponent("window-events.jsonl")).split(separator: "\n")
    try check(rows.count == 2, "Repeated identical tracking samples must be omitted")
    for id in 0..<100 { recorder.write(.init(event: .frameRequest, windowID: UInt32(id), requestedFrame: [1, 2, 3, 4])) }
    recorder.stop()
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    try check(Set(files.map(\.lastPathComponent)) == ["window-events.jsonl", "window-events.previous.jsonl"], "Rotation must retain exactly two fixed log files")
    for file in files {
        let data = try Data(contentsOf: file)
        try check(data.count <= 1024, "Each file must stay within its byte limit")
        for row in data.split(separator: 0x0A) { _ = try JSONSerialization.jsonObject(with: Data(row)) }
    }
    try check(recorder.failure == nil, "Normal rotation must not stop with an IO error")
}
@MainActor func diagnosticPathsRejectLinksAndStopOnFailure() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tabbed-diag-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("keep.txt")
    try Data("untouched".utf8).write(to: target)
    let logs = root.appendingPathComponent("logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: logs.appendingPathComponent("window-events.jsonl"), withDestinationURL: target)
    let recorder = WindowDiagnosticRecorder(directory: logs)
    var refused = false
    do { try recorder.start() } catch { refused = true }
    try check(refused && !recorder.isRecording, "A symlink log must not be followed or replaced")
    let preserved = try String(contentsOf: target)
    try check(preserved == "untouched", "Refusing a log path must preserve its target")
    let tiny = WindowDiagnosticRecorder(directory: root.appendingPathComponent("tiny"), maxBytes: 1)
    refused = false
    do { try tiny.start() } catch { refused = true }
    try check(refused && !tiny.isRecording && tiny.failure != nil, "An oversized entry must stop recording without recursion")
    let linkDir = root.appendingPathComponent("linked-logs")
    try FileManager.default.createSymbolicLink(at: linkDir, withDestinationURL: logs)
    let unsafe = WindowDiagnosticRecorder(directory: linkDir)
    refused = false
    do { try unsafe.start() } catch { refused = true }
    try check(refused && !unsafe.isRecording, "A symlink diagnostic directory must be rejected")
}
@MainActor func diagnosticNormalizationDoesNotLeakUnknownValues() throws {
    try check(WindowDiagnostics.frame(CGRect.null) == nil, "Nonfinite geometry must not break JSON encoding")
    try check(WindowDiagnostics.frame(CGRect(x: 1, y: 2, width: 3, height: 4)) == [1, 2, 3, 4], "Finite geometry must be retained")
    try check(WindowDiagnostics.notification("private-page-title https://example.invalid") == .other, "Unknown notification strings must be reduced to an enum")
}
MainActor.assumeIsolated { do {
 try diagnosticRecorderIsExplicitAndPrivate(); print("PASS: diagnosticRecorderIsExplicitAndPrivate")
 try diagnosticRotationAndSamplingAreBounded(); print("PASS: diagnosticRotationAndSamplingAreBounded")
 try diagnosticPathsRejectLinksAndStopOnFailure(); print("PASS: diagnosticPathsRejectLinksAndStopOnFailure")
 try diagnosticNormalizationDoesNotLeakUnknownValues(); print("PASS: diagnosticNormalizationDoesNotLeakUnknownValues")
} catch { print(error); exit(1) } }
