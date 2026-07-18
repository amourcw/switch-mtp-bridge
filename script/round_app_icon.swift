import AppKit

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift round_app_icon.swift <input.png> <output.png>")
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSImage(contentsOf: input) else {
    fatalError("Cannot read source icon")
}

let size = NSSize(width: 1254, height: 1254)
guard let representation = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1254,
    pixelsHigh: 1254,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Cannot create bitmap")
}

representation.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
NSColor.clear.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
NSBezierPath(roundedRect: NSRect(x: 3, y: 3, width: 1248, height: 1248), xRadius: 204, yRadius: 204).addClip()
image.draw(
    in: NSRect(origin: .zero, size: size),
    from: NSRect(origin: .zero, size: image.size),
    operation: .copy,
    fraction: 1
)
NSGraphicsContext.restoreGraphicsState()

guard let png = representation.representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode icon")
}
try png.write(to: output)
