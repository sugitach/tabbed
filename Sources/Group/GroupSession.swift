import Foundation
import CoreGraphics
import Darwin

/// Session identity contains no window titles, document names or URLs.
struct SavedWindowIdentity: Codable, Hashable {
    let id: UInt32
    let pid: Int32
    let processLaunchTime: TimeInterval
    let bundleID: String?
}

struct SavedWindowGroup: Codable {
    let windows: [SavedWindowIdentity]
    let selectedID: UInt32
    let frame: CGRect
    var displayConfiguration: String? = nil
    var displayLayouts: DisplayLayoutHistory? = nil
}

struct GroupSession: Codable {
    var version = 1
    var groups: [SavedWindowGroup]

    var isValid: Bool {
        guard version == 1, groups.count <= 128 else { return false }
        var seen = Set<UInt32>()
        return groups.allSatisfy { group in
            guard group.displayLayouts?.isValid != false,
                  group.displayConfiguration.map({ !$0.isEmpty && $0.utf8.count <= 8192 }) ?? true else { return false }
            let f = group.frame
            guard (2...256).contains(group.windows.count),
                  f.origin.x.isFinite, f.origin.y.isFinite,
                  f.width.isFinite, f.height.isFinite,
                  f.width > 0, f.height > 0,
                  group.windows.contains(where: { $0.id == group.selectedID }) else { return false }
            return group.windows.allSatisfy { window in
                window.id > 0 && window.pid > 0 && window.processLaunchTime.isFinite
                    && window.processLaunchTime > 0 && seen.insert(window.id).inserted
            }
        }
    }
}

/// Atomic, private per-app state. No application content is persisted.
struct GroupSessionStore {
    let url: URL

    static var standard: GroupSessionStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return GroupSessionStore(url: root
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.local.Tabbed", isDirectory: true)
            .appendingPathComponent("window-groups.json"))
    }

    func load() -> GroupSession? {
        // A size bound also prevents malformed local data from causing a huge decode.
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              size.isRegularFile == true, size.isSymbolicLink != true,
              let bytes = size.fileSize, bytes <= 1_048_576,
              let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(GroupSession.self, from: data),
              session.isValid else { return nil }
        return session
    }

    func save(_ session: GroupSession) throws {
        guard session.isValid else { throw CocoaError(.fileWriteInvalidFileName) }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(session)
        guard data.count <= 1_048_576 else { throw CocoaError(.fileWriteOutOfSpace) }
        // Foundation's atomic Data writer follows a destination symlink. Create
        // a private file and rename it over the directory entry instead.
        var template = Array(directory.appendingPathComponent(".window-groups.XXXXXX").path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let temporary = String(cString: template)
        defer { close(fd); unlink(temporary) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
        guard fsync(fd) == 0, rename(temporary, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
