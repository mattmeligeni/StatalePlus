import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
// PNG 1024×1024 senza canale alfa: lo sfondo trasparente diventa del colore indicato (r,g,b 0…255).
let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(srgbRed: Double(a[3])! / 255, green: Double(a[4])! / 255, blue: Double(a[5])! / 255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
ctx.draw(img, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
