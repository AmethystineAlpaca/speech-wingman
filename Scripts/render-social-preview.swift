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
text("Speech Wingman", x:64, y:554, size:30, color:white, bold:true)
text("A SPEECH REMINDER APP FOR MAC", x:66, y:518, size:16, color:accent, bold:true)
text("Set a rule. Get a reminder", x:64, y:429, size:52, color:white, bold:true)
text("when your speech matches it.", x:64, y:368, size:52, color:white, bold:true)
let cards: [(CGFloat, String, String, String)] = [
    (64, "1  WRITE YOUR RULE", "Remind me if I speak", "badly about Tom."),
    (456, "2  SPEAK", "Tom is a very", "mean person."),
    (848, "3  SEE A REMINDER", "Try a more", "constructive phrasing.")
]
for (x, label, line1, line2) in cards {
    color(30,41,59).setFill()
    NSBezierPath(roundedRect: NSRect(x:x,y:154,width:368,height:165), xRadius:16,yRadius:16).fill()
    text(label, x:x+22, y:278, size:17, color:accent, bold:true)
    text(line1, x:x+22, y:226, size:25, color:white, bold:true)
    text(line2, x:x+22, y:191, size:25, color:white, bold:true)
}
text("Illustrative example · You write the rule; the app generates the reminder.", x:66, y:121, size:15, color:muted)
text("Runs offline on your Mac  ·  Apple Silicon  ·  Open-source preview", x:66, y:61, size:22, color:muted)
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
