import AppKit
import ImageIO
import UniformTypeIdentifiers

// Typographic project artwork. No screenshots, user preferences, or personal content.
let width = 1280, height = 640
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1) }
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, bold: Bool = false) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular), .foregroundColor: color])
}
color(15,23,42).setFill(); NSBezierPath(rect: NSRect(x:0,y:0,width:width,height:height)).fill()
let white = color(248,250,252), muted = color(203,213,225), accent = color(94,234,212)
text("Speech Wingman", x:72, y:520, size:54, color:white, bold:true)
text("ON-DEVICE SPEECH + CUSTOM AI REMINDERS", x:74, y:483, size:17, color:accent, bold:true)
text("Your voice. Your rules.", x:72, y:359, size:58, color:white, bold:true)
text("Multiple rules. One floating button.", x:74, y:302, size:30, color:muted)
for (x, label) in [(CGFloat(72), "OFFLINE INFERENCE"), (CGFloat(446), "MIXED-LANGUAGE SPEECH"), (CGFloat(820), "ONE-CLICK LISTENING")] {
    color(30,41,59).setFill()
    NSBezierPath(roundedRect: NSRect(x:x,y:203,width:344,height:56), xRadius:12,yRadius:12).fill()
    text(label, x:x+20, y:221, size:18, color:accent, bold:true)
}
text("For meetings, rehearsals, and wonderfully specific ideas.", x:74, y:119, size:25, color:muted)
text("v0.3.0  ·  macOS  ·  Apple Silicon  ·  Open source", x:74, y:64, size:20, color:muted)
NSGraphicsContext.restoreGraphicsState()
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let encoded = NSMutableData()
let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, bitmap.cgImage!, nil)
precondition(CGImageDestinationFinalize(destination))

let data = encoded as Data
var clean = Data(data.prefix(8))
var cursor = 8
while cursor + 12 <= data.count {
    let length = data[cursor..<cursor+4].reduce(0) { ($0 << 8) | Int($1) }
    let end = cursor + length + 12
    precondition(end <= data.count)
    let kind = String(decoding: data[cursor+4..<cursor+8], as: UTF8.self)
    if !["tEXt", "zTXt", "iTXt", "eXIf"].contains(kind) { clean.append(data[cursor..<end]) }
    cursor = end
}
try clean.write(to: url)
