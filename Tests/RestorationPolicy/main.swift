import Foundation
import CoreGraphics
let target = CGRect(x: 100, y: 200, width: 800, height: 600)
var reads = 0, waits = 0
assert(WindowRestoration.verify(frame: target, read: {
    reads += 1
    return reads < 4 ? target.offsetBy(dx: -1000, dy: 0) : target
}, wait: { waits += 1 }) && waits == 3)
waits = 0
assert(!WindowRestoration.verify(frame: target, read: { nil }, wait: { waits += 1 }) && waits == 10)
assert(!WindowRestoration.verify(frame: target, read: { CGRect(x:100,y:200,width:900,height:600) }, wait: {}))
print("PASS: delayed publication, bounded unavailable geometry, real size mismatch")
