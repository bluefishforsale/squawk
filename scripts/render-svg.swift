// Rasterizes SVG files to PNG next to them. Usage: swift render.swift <size> <svg>...
import AppKit

let size = Int(CommandLine.arguments[1])!
for path in CommandLine.arguments.dropFirst(2) {
    let url = URL(fileURLWithPath: path)
    guard let image = NSImage(contentsOf: url) else {
        print("cannot read \(path)")
        continue
    }
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let out = url.deletingPathExtension().appendingPathExtension("png")
    try! bitmap.representation(using: .png, properties: [:])!.write(to: out)
    print(out.path)
}
