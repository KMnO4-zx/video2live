import AppKit
@preconcurrency import AVFoundation
import Foundation

public enum FileStaging {
    public static func copyIntoWorkspace(_ sourceURL: URL) throws -> URL {
        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Video2Live", isDirectory: true)
            .appendingPathComponent("Input", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}

public enum VideoAssetService {
    public static func videoDisplaySize(for asset: AVURLAsset) async throws -> CGSize {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw Video2LiveError.missingVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = naturalSize.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    public static func videoCodecFourCC(for asset: AVURLAsset) async throws -> String {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw Video2LiveError.missingVideoTrack
        }
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            throw Video2LiveError.exportFailed("无法读取视频编码格式")
        }
        return fourCCString(CMFormatDescriptionGetMediaSubType(formatDescription))
    }

    public static func frameImage(from videoURL: URL, at seconds: Double) async throws -> NSImage {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, any Error>) in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? Video2LiveError.exportFailed("无法抽取视频帧"))
                }
            }
        }
        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }

    private static func fourCCString(_ value: FourCharCode) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "\(value)"
    }
}

public enum ImageProcessing {
    public static func cgImage(from image: NSImage) throws -> CGImage {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw Video2LiveError.imageEncodingFailed
        }
        return cgImage
    }

    public static func renderCover(from image: NSImage, targetSize: CGSize, scale: CGFloat, offset: CGSize) throws -> NSImage {
        let cgImage = try cgImage(from: image)
        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let target = CGSize(width: max(1, round(targetSize.width)), height: max(1, round(targetSize.height)))
        let baseScale = max(target.width / sourceSize.width, target.height / sourceSize.height)
        let effectiveScale = max(1, scale) * baseScale
        let drawSize = CGSize(width: sourceSize.width * effectiveScale, height: sourceSize.height * effectiveScale)
        let origin = CGPoint(
            x: (target.width - drawSize.width) / 2 + offset.width,
            y: (target.height - drawSize.height) / 2 + offset.height
        )

        return try renderBitmap(size: target) { context in
            context.draw(cgImage, in: CGRect(origin: origin, size: drawSize))
        }
    }

    public static func renderCover(from image: NSImage, targetSize: CGSize, cropSelection: CropSelection) throws -> NSImage {
        let cgImage = try cgImage(from: image)
        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let target = CGSize(width: max(1, round(targetSize.width)), height: max(1, round(targetSize.height)))
        let targetAspect = target.width / max(target.height, 1)
        let cropRect = cropSelection
            .cropRect(in: sourceSize, targetAspect: targetAspect)
            .integral

        guard let cropped = cgImage.cropping(to: cropRect) else {
            throw Video2LiveError.imageEncodingFailed
        }

        return try renderBitmap(size: target) { context in
            context.draw(cropped, in: CGRect(origin: .zero, size: target))
        }
    }

    private static func renderBitmap(size: CGSize, draw: (CGContext) -> Void) throws -> NSImage {
        let width = max(1, Int(round(size.width)))
        let height = max(1, Int(round(size.height)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw Video2LiveError.imageEncodingFailed
        }

        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)

        guard let output = context.makeImage() else {
            throw Video2LiveError.imageEncodingFailed
        }
        return NSImage(cgImage: output, size: CGSize(width: width, height: height))
    }
}
