import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func makeIcon(_ size: Int, _ path: String) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    let s = CGFloat(size)
    ctx.setFillColor(CGColor(red: 0.035, green: 0.055, blue: 0.10, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    let frame = CGRect(x: s*0.13, y: s*0.13, width: s*0.74, height: s*0.74)
    ctx.setFillColor(CGColor(red: 0.10, green: 0.13, blue: 0.20, alpha: 1)); ctx.addPath(CGPath(roundedRect: frame, cornerWidth: s*0.10, cornerHeight: s*0.10, transform: nil)); ctx.fillPath()
    ctx.saveGState(); ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: s*0.045, dy: s*0.045), cornerWidth: s*0.06, cornerHeight: s*0.06, transform: nil)); ctx.clip()
    ctx.setFillColor(CGColor(red: 0.98, green: 0.48, blue: 0.22, alpha: 1)); ctx.fill(CGRect(x: 0, y: s*0.48, width: s, height: s*0.4))
    ctx.setFillColor(CGColor(red: 0.17, green: 0.38, blue: 0.58, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s*0.55))
    ctx.setFillColor(CGColor(red: 1.0, green: 0.78, blue: 0.32, alpha: 1)); ctx.fillEllipse(in: CGRect(x: s*0.60, y: s*0.57, width: s*0.15, height: s*0.15))
    let mountain = CGMutablePath(); mountain.move(to: CGPoint(x: -s*0.05, y: s*0.18)); mountain.addLine(to: CGPoint(x: s*0.27, y: s*0.53)); mountain.addLine(to: CGPoint(x: s*0.45, y: s*0.35)); mountain.addLine(to: CGPoint(x: s*0.82, y: s*0.73)); mountain.addLine(to: CGPoint(x: -s*0.05, y: s*0.73)); mountain.closeSubpath(); ctx.setFillColor(CGColor(red: 0.06, green: 0.16, blue: 0.25, alpha: 1)); ctx.addPath(mountain); ctx.fillPath()
    ctx.restoreGState()
    ctx.setStrokeColor(CGColor(red: 0.30, green: 0.78, blue: 0.78, alpha: 1)); ctx.setLineWidth(s*0.025); ctx.addPath(CGPath(roundedRect: frame, cornerWidth: s*0.10, cornerHeight: s*0.10, transform: nil)); ctx.strokePath()
    guard let image = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }; CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
}
for argument in CommandLine.arguments.dropFirst() { let parts = argument.split(separator: ":", maxSplits: 1).map(String.init); if parts.count == 2, let size = Int(parts[0]) { makeIcon(size, parts[1]) } }
