import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
NSColor(calibratedRed: 0.035, green: 0.16, blue: 0.18, alpha: 1).setFill()
background.fill()
let track = NSBezierPath()
track.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 270, startAngle: 140, endAngle: 40, clockwise: false)
track.lineWidth = 74
track.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.15).setStroke()
track.stroke()
let arc = NSBezierPath()
arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 270, startAngle: 140, endAngle: 355, clockwise: false)
arc.lineWidth = 74
arc.lineCapStyle = .round
NSColor(calibratedRed: 0.23, green: 0.88, blue: 0.76, alpha: 1).setStroke()
arc.stroke()
let needle = NSBezierPath()
needle.move(to: NSPoint(x: 512, y: 512))
needle.line(to: NSPoint(x: 676, y: 664))
needle.lineWidth = 42
needle.lineCapStyle = .round
NSColor.white.setStroke()
needle.stroke()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 468, y: 468, width: 88, height: 88)).fill()
image.unlockFocus()
var rect = NSRect(x: 0, y: 0, width: size, height: size)
guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
      let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
    fatalError("Could not create icon")
}
try png.write(to: destination)
