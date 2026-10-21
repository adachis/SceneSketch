import AppKit
import ImageIO
import UniformTypeIdentifiers
import Vision

struct ReferenceImages {
    static func importFile(_ url: URL) throws -> ReferenceImage {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 50_000_000 else { throw ImageError.tooLarge }
        let source = try Data(contentsOf: url)
        let image = try cgImage(source, maximumEdge: 1280)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw ImageError.invalid }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.invalid }
        return ReferenceImage(name: url.deletingPathExtension().lastPathComponent, data: data as Data)
    }
    static func cgImage(_ data: Data, maximumEdge: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumEdge
              ] as CFDictionary) else { throw ImageError.invalid }
        return image
    }
    static func faceCrop(_ image: CGImage) -> CGImage {
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        guard let face = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else { return image }
        let r = face.boundingBox
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let crop = CGRect(x: r.minX * Double(image.width), y: (1-r.maxY) * Double(image.height), width: r.width * Double(image.width), height: r.height * Double(image.height)).insetBy(dx: -r.width * Double(image.width) * 0.2, dy: -r.height * Double(image.height) * 0.35).intersection(bounds)
        return image.cropping(to: crop) ?? image
    }
}

enum ImageError: LocalizedError {
    case tooLarge, invalid
    var errorDescription: String? { self == .tooLarge ? L("Choose an image smaller than 50 MB.") : L("This image couldn’t be opened.  Try a PNG, JPEG, or HEIC file.") }
}
