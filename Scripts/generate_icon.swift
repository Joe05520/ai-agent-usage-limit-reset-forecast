import AppKit
let destination = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.086, green: 0.22, blue: 0.196, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 198, yRadius: 198).fill()
NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.83, alpha: 1).setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: 206, y: 206, width: 612, height: 612)); ring.lineWidth = 24; ring.stroke()
let arc = NSBezierPath(); arc.appendArc(withCenter: NSPoint(x:512,y:440), radius:172, startAngle:0,endAngle:180);arc.lineWidth=26;arc.lineCapStyle = .round;arc.stroke()
let needle=NSBezierPath();needle.move(to:NSPoint(x:512,y:452));needle.line(to:NSPoint(x:630,y:682));needle.lineWidth=26;needle.lineCapStyle = .round;needle.stroke()
NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.83, alpha: 1).setFill()
NSBezierPath(ovalIn:NSRect(x:480,y:408,width:64,height:64)).fill()
image.unlockFocus()
let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:destination))
