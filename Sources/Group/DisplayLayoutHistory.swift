import Foundation
import CoreGraphics

/// Geometry only: no application content, window titles or display names.
struct DisplayLayoutHistory: Codable {
    struct Entry: Codable {
        let configuration: String
        let frame: CGRect
    }
    private(set) var entries: [Entry] = []
    static let capacity = 16

    var isValid: Bool {
        entries.count <= Self.capacity && Set(entries.map(\.configuration)).count == entries.count &&
        entries.allSatisfy {
            !$0.configuration.isEmpty && $0.configuration.utf8.count <= 8192 && Self.validFrame($0.frame)
        }
    }

    static func validFrame(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite &&
        frame.width > 0 && frame.height > 0
    }

    func frame(for configuration: String) -> CGRect? {
        entries.first { $0.configuration == configuration }?.frame
    }

    mutating func remember(_ frame: CGRect, for configuration: String) {
        guard Self.validFrame(frame), !configuration.isEmpty else { return }
        entries.removeAll { $0.configuration == configuration }
        entries.append(Entry(configuration: configuration, frame: frame))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }
}

/// Canonical Quartz geometry: independent of display enumeration order. The
/// primary display is included because it defines both AX/AppKit coordinate origins.
enum DisplayConfiguration {
    struct Screen {
        let identity: String
        let bounds: CGRect
        let pixelWidth: Int
        let pixelHeight: Int
        let rotation: Double
        let mirrorIdentity: String
        let primary: Bool
    }

    static func key(for screens: [Screen]) -> String {
        let components: [String] = screens.map { screen in
            let geometry = [screen.bounds.minX, screen.bounds.minY, screen.bounds.width, screen.bounds.height]
                .map { String(Double($0)) }.joined(separator: ",")
            return [screen.identity, geometry, String(screen.pixelWidth), String(screen.pixelHeight),
                    String(screen.rotation), screen.mirrorIdentity, screen.primary ? "primary" : "secondary"]
                .joined(separator: ":")
        }
        return components.sorted().joined(separator: "|")
    }
}
