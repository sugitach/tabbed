import Foundation
import CoreGraphics

struct GeometrySample: Codable {
    let pid: Int32
    let windowID: UInt32
    let identifier: String
    let title: String
    let ax: RectRecord
    let cg: RectRecord
}

enum GeometryPolicy {
    static func valid(_ r: CGRect) -> Bool {
        [r.minX, r.minY, r.width, r.height, r.maxX, r.maxY].allSatisfy(\.isFinite) &&
            r.width > 0 && r.height > 0 && !r.isNull && !r.isInfinite
    }
    static func contentRegion(_ window: WindowRecord, frame: CGRect) throws -> CGRect {
        let offset = window.contentOffset.rect
        let local = CGRect(origin: .zero, size: frame.size)
        guard valid(frame), valid(offset), local.contains(offset) else {
            throw HarnessError.stop("Invalid fixture content region")
        }
        let region = offset.offsetBy(dx: frame.minX, dy: frame.minY).insetBy(dx: 12, dy: 12)
        guard valid(region) else { throw HarnessError.stop("Fixture content is too small for safe input") }
        return region
    }
}

/// Startup only: disagreement may wait, identity errors never retry. The same
/// 3-point AX/CG agreement remains required; temporal drift is limited to 0.5pt
/// relative to the first sample, not just to the immediately previous sample.
struct StableGeometryGate {
    let expected: FixtureRecord
    private var anchor: [GeometrySample]?
    private var since: TimeInterval = 0
    private var previousTime: TimeInterval?
    private var count = 0

    mutating func record(_ samples: [GeometrySample], at time: TimeInterval) throws -> Bool {
        guard time.isFinite, previousTime.map({ time > $0 }) ?? true else {
            throw HarnessError.stop("Invalid geometry sample time")
        }
        previousTime = time
        guard samples.count == expected.windows.count, !samples.isEmpty,
              zip(samples, expected.windows).allSatisfy({ sample, window in
                  sample.pid == expected.pid && sample.windowID == window.id &&
                  sample.identifier == window.identifier && sample.title == window.title
              }) else { throw HarnessError.stop("Geometry sample identity changed") }
        guard samples.allSatisfy({ GeometryPolicy.valid($0.ax.rect) && GeometryPolicy.valid($0.cg.rect) }) else {
            throw HarnessError.stop("Invalid sampled geometry")
        }
        guard samples.allSatisfy({ HarnessPolicy.close($0.ax.rect, $0.cg.rect) }) else {
            anchor = nil; count = 0
            return false
        }
        if let anchor, zip(samples, anchor).allSatisfy({ current, first in
            HarnessPolicy.close(current.ax.rect, first.ax.rect, tolerance: 0.5) &&
                HarnessPolicy.close(current.cg.rect, first.cg.rect, tolerance: 0.5)
        }) {
            count += 1
        } else {
            anchor = samples; since = time; count = 1
        }
        return count >= 3 && time - since >= 0.3
    }
}
