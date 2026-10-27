import Foundation
import CoreGraphics
import Darwin

/// Deliberately typed: no window titles, URLs, page content, or free-form
/// application strings can be passed to the diagnostic writer.
struct WindowDiagnosticEntry: Codable, Equatable {
    enum Event: String, Codable {
        case recordingStarted, recordingStopped, selection, layoutBegin, layoutEnd
        case parking, frameRequest, frameResult, frameRead, activationState
        case observerCreated, observerRegistered, notificationReceived, notificationIgnored
        case frameAdopted, trackingBegin, trackingSample, trackingEnd, closureCheck
        case memberRemoved, groupDissolved
        case panelOrderSnapshot, panelOrderRepair
        case applicationNotification, terminationRestoreBegin, terminationRestoreResult
        case inputMonitoringState, focusSnapshot, mainWindowRead
    }
    enum NotificationKind: String, Codable {
        case moved, resized, destroyed, minimized, created, focusChanged, mainChanged, applicationActivated, focusedElementChanged, other
    }
    enum Reason: String, Codable {
        case stopping, applyingLayout, unmanaged, unmatchedElement, inactive, unavailable
        case beforeActivation, afterActivation, applicationGone, invalidElement, identityChanged, unknown
        case valueEncodingFailed, identityMatches, dragging, wrongSpace
    }
    enum FrameSource: String, Codable { case accessibility, windowServer }
    var event: Event
    var windowID: UInt32? = nil
    var pid: Int32? = nil
    var groupID: UUID? = nil
    var activeWindowID: UInt32? = nil
    var trackingWindowID: UInt32? = nil
    var resolvedWindowID: UInt32? = nil
    var memberIDs: [UInt32]? = nil
    var groupFrame: [Double]? = nil
    var requestedFrame: [Double]? = nil
    var axFrame: [Double]? = nil
    var cgFrame: [Double]? = nil
    var status: Int32? = nil
    var sizeStatus: Int32? = nil
    var positionStatus: Int32? = nil
    var minimized: Bool? = nil
    var enhancedUI: Bool? = nil
    var applyingLayout: Bool? = nil
    var notification: NotificationKind? = nil
    var reason: Reason? = nil
    var source: FrameSource? = nil
    var panelWindowID: UInt32? = nil
    var panelFrame: [Double]? = nil
    var panelVisible: Bool? = nil
    var panelOrderIndex: Int? = nil
    var anchorOrderIndex: Int? = nil
    var observerInstalled: Bool? = nil
    var receivedMouseEvent: Bool? = nil
    var startupReinstallCount: Int? = nil
    var gestureCandidateFound: Bool? = nil
    var focusedWindowID: UInt32? = nil
    var mainWindowID: UInt32? = nil
    var focusedElementWindowID: UInt32? = nil
    var focusedWindowStatus: Int32? = nil
    var mainWindowStatus: Int32? = nil
    var focusedElementWindowStatus: Int32? = nil
    var frontmostPID: Int32? = nil
    var frontmostWindowID: UInt32? = nil
    var sampleDelay: Double? = nil
}

@MainActor
final class WindowDiagnosticRecorder {
    enum Failure: Error { case unsafePath, fileIO, oversizedEntry }
    let directory: URL
    let maxBytes: Int
    var onStateChange: (() -> Void)?
    private(set) var isRecording = false
    private(set) var failure: Failure?
    private var handle: FileHandle?
    private var bytes = 0
    private var sequence: UInt64 = 0
    private var session = UUID()
    private var lastTrackingSample: WindowDiagnosticEntry?
    private let encoder = JSONEncoder()
    private var current: URL { directory.appendingPathComponent("window-events.jsonl") }
    private var previous: URL { directory.appendingPathComponent("window-events.previous.jsonl") }

    init(directory: URL, maxBytes: Int = 8 * 1024 * 1024) {
        self.directory = directory
        self.maxBytes = maxBytes
        encoder.outputFormatting = [.sortedKeys]
    }

    func start() throws {
        guard !isRecording else { return }
        failure = nil
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            try checkPath(directory, directory: true)
            try rotate()
            session = UUID(); sequence = 0; lastTrackingSample = nil
            isRecording = true
            write(.init(event: .recordingStarted))
            guard isRecording else { throw failure ?? Failure.fileIO }
            onStateChange?()
        } catch {
            close(failure: (error as? Failure) ?? .fileIO)
            throw error
        }
    }

    func stop() {
        guard isRecording else { return }
        write(.init(event: .recordingStopped))
        close(failure: failure)
    }

    func write(_ entry: WindowDiagnosticEntry) {
        guard isRecording else { return }
        if entry.event == .trackingSample, lastTrackingSample == entry { return }
        lastTrackingSample = entry.event == .trackingSample ? entry : nil
        struct Record: Encodable {
            let schema = 1
            let session: UUID
            let sequence: UInt64
            let uptime: TimeInterval
            let entry: WindowDiagnosticEntry
        }
        do {
            sequence += 1
            var data = try encoder.encode(Record(session: session, sequence: sequence,
                uptime: ProcessInfo.processInfo.systemUptime, entry: entry))
            data.append(0x0A)
            guard data.count <= maxBytes else { throw Failure.oversizedEntry }
            if bytes + data.count > maxBytes { try rotate() }
            guard let handle else { throw Failure.fileIO }
            try handle.write(contentsOf: data)
            bytes += data.count
        } catch { close(failure: (error as? Failure) ?? .fileIO) }
    }

    private func checkPath(_ url: URL, directory: Bool) throws {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (a[.type] as? FileAttributeType) == (directory ? .typeDirectory : .typeRegular),
              (a[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              directory || (a[.referenceCount] as? NSNumber)?.intValue == 1 else { throw Failure.unsafePath }
    }

    private func rotate() throws {
        try handle?.close(); handle = nil
        let fm = FileManager.default
        // attributesOfItem also sees dangling symlinks; never follow or overwrite them.
        if (try? fm.attributesOfItem(atPath: previous.path)) != nil {
            try checkPath(previous, directory: false)
        }
        if (try? fm.attributesOfItem(atPath: current.path)) != nil {
            try checkPath(current, directory: false)
            if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
            try fm.moveItem(at: current, to: previous)
        }
        let fd = Darwin.open(current.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.fileIO }
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        bytes = 0
    }

    private func close(failure: Failure?) {
        try? handle?.close(); handle = nil
        isRecording = false
        self.failure = failure
        onStateChange?()
    }
}

@MainActor
enum WindowDiagnostics {
    static let recorder = WindowDiagnosticRecorder(directory:
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tabbed"))
    static var isRecording: Bool { recorder.isRecording }
    static func record(_ entry: @autoclosure () -> WindowDiagnosticEntry) {
        guard recorder.isRecording else { return }
        recorder.write(entry())
    }
    static func frame(_ frame: CGRect?) -> [Double]? {
        guard let frame else { return nil }
        let values = [frame.minX, frame.minY, frame.width, frame.height].map(Double.init)
        return values.allSatisfy(\.isFinite) ? values : nil
    }
    static func notification(_ value: String) -> WindowDiagnosticEntry.NotificationKind {
        switch value {
        case "AXMoved": return .moved
        case "AXResized": return .resized
        case "AXUIElementDestroyed": return .destroyed
        case "AXWindowMiniaturized": return .minimized
        case "AXWindowCreated": return .created
        case "AXFocusedWindowChanged": return .focusChanged
        case "AXMainWindowChanged": return .mainChanged
        case "AXApplicationActivated": return .applicationActivated
        case "AXFocusedUIElementChanged": return .focusedElementChanged
        default: return .other
        }
    }
}
