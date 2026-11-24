import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: xcrun swift render-keypad-icons.swift <output-directory>")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let symbols = [
    ("mac", "apple.logo"),
    ("swap", "arrow.left.arrow.right"),
    ("pc", "square.grid.2x2.fill"),
    ("pip", "pip.fill"),
    ("power", "power"),
]
let configuration = NSImage.SymbolConfiguration(pointSize: 96, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

for (name, symbolName) in symbols {
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: name)?
        .withSymbolConfiguration(configuration) else {
        fatalError("System symbol unavailable: \(symbolName)")
    }
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Unable to create bitmap")
    }
    let scale = min(112 / symbol.size.width, 112 / symbol.size.height)
    let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
    let frame = NSRect(x: (128 - size.width) / 2, y: (128 - size.height) / 2,
                       width: size.width, height: size.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    symbol.draw(in: frame, from: .zero, operation: .copy, fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode \(symbolName)")
    }
    let output = outputDirectory.appendingPathComponent("lg-\(name).png")
    try data.write(to: output, options: .atomic)
    print("\(output.lastPathComponent): \(symbolName), 128x128")
}