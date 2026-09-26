//
//  CoverTestImage.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Cover images for the widget cover tests, made in memory so no binary lives in the repository,
/// and the reading of a cover file written to disk, done with ImageIO on its own: the oracle of
/// "a readable JPEG whose longer side is at most N pixels" never goes through the code under test.
enum CoverTestImage {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// The pixel size of an image read from disk.
    struct PixelSize: Hashable {
        let width: Int
        let height: Int

        var longerSide: Int {
            max(width, height)
        }
    }

    /// A solid-color PNG of `width` × `height` pixels, a portrait cover by default.
    static func png(width: Int = 1000, height: Int = 1400) throws(Failure) -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw Failure(description: "Could not create a \(width)×\(height) bitmap context")
        }
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw Failure(description: "Could not render the \(width)×\(height) bitmap")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure(description: "Could not create a PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure(description: "Could not encode the PNG")
        }
        return data as Data
    }

    /// The pixel size of the file at `url` when it is a JPEG that decodes; `nil` when the file is
    /// missing, is not a JPEG or cannot be decoded.
    static func jpegPixelSize(at url: URL) -> PixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              type as String == UTType.jpeg.identifier,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return PixelSize(width: width, height: height)
    }
}
