import Foundation
import CoreGraphics

struct E2EWindowState: Codable {
    let geometry: GeometrySample
    let minimized: Bool
    let onscreen: Bool
}

struct E2EPanel: Codable {
    let id: UInt32
    let frame: RectRecord
}

enum E2EPolicy {
    static let mode = "E2E_GROUP_UNGROUP_QUIT"
    static func sameFrames(_ a: E2EWindowState, _ b: E2EWindowState, tolerance: CGFloat = 3) -> Bool {
        // Compare each API with its own prior observation. AX/CG need not equal each other.
        HarnessPolicy.close(a.geometry.ax.rect, b.geometry.ax.rect, tolerance: tolerance) &&
            HarnessPolicy.close(a.geometry.cg.rect, b.geometry.cg.rect, tolerance: tolerance)
    }
    static func visible(_ w: E2EWindowState, in screen: CGRect) -> Bool {
        !w.minimized && w.onscreen && HarnessPolicy.visible(w.geometry.ax.rect, in: screen) &&
            HarnessPolicy.visible(w.geometry.cg.rect, in: screen)
    }
    static func grouped(_ rows: [E2EWindowState], at target: E2EWindowState, in screen: CGRect) -> Bool {
        guard rows.count == 2 else { return false }
        return visible(rows[0], in: screen) && sameFrames(rows[0], target) &&
            !rows[1].minimized && !HarnessPolicy.visible(rows[1].geometry.ax.rect, in: screen) &&
            !HarnessPolicy.visible(rows[1].geometry.cg.rect, in: screen) && !sameFrames(rows[1], target)
    }
    static func separated(_ rows: [E2EWindowState], baseline: [E2EWindowState], in screen: CGRect) -> Bool {
        rows.count == 2 && baseline.count == 2 && zip(rows, baseline).allSatisfy {
            visible($0.0, in: screen) && sameFrames($0.0, $0.1)
        }
    }
    static func restored(_ rows: [E2EWindowState], at target: E2EWindowState, in screen: CGRect) -> Bool {
        rows.count == 2 && rows.allSatisfy { visible($0, in: screen) && sameFrames($0, target) }
    }
    static func stable(_ a: [E2EWindowState], _ b: [E2EWindowState]) -> Bool {
        a.count == 2 && b.count == 2 && zip(a,b).allSatisfy {
            $0.0.geometry.pid == $0.1.geometry.pid && $0.0.geometry.windowID == $0.1.geometry.windowID &&
            $0.0.geometry.identifier == $0.1.geometry.identifier && $0.0.geometry.title == $0.1.geometry.title &&
            $0.0.minimized == $0.1.minimized && $0.0.onscreen == $0.1.onscreen && sameFrames($0.0,$0.1,tolerance:0.5)
        }
    }
    static func stripCandidates(_ panels:[E2EPanel], at target:E2EWindowState)->[E2EPanel] {
        let frame=target.geometry.ax.rect
        let expected=CGRect(x:frame.minX,y:frame.minY-28,width:frame.width,height:28)
        return panels.filter { $0.id>0 && HarnessPolicy.close($0.frame.rect,expected) }
    }
    static func dragPoints(from start: CGPoint, to end: CGPoint) throws -> [CGPoint] {
        guard [start.x,start.y,end.x,end.y].allSatisfy(\.isFinite),
              abs(end.y-start.y) <= 0.5, abs(end.x-start.x) >= 40, abs(end.x-start.x) <= 600 else {
            throw HarnessError.stop("E2E supports only bounded horizontal fixture drags")
        }
        let delta=end.x-start.x, first=CGPoint(x:start.x+(delta>0 ? 12 : -12),y:start.y)
        let count=Int(ceil(abs(end.x-first.x)/100))
        return [first]+(1...count).map { i in
            CGPoint(x:first.x+(end.x-first.x)*CGFloat(i)/CGFloat(count),y:end.y)
        }
    }
}
