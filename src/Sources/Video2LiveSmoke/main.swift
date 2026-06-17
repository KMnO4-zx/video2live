import AppKit
import AVFoundation
import Foundation
import Photos
import Video2LiveCore

@main
struct Video2LiveSmoke {
    static func main() async {
        do {
            let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let root = FileManager.default.fileExists(atPath: currentDirectory.appendingPathComponent("videos/lulu.mp4").path)
                ? currentDirectory
                : currentDirectory.deletingLastPathComponent()
            let inputURL = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
                ?? root.appendingPathComponent("videos/lulu.mp4")

            let stagedURL = try FileStaging.copyIntoWorkspace(inputURL)
            let asset = AVURLAsset(url: stagedURL)
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            let size = try await VideoAssetService.videoDisplaySize(for: asset)
            let clipDuration = min(max(1.0, min(3.0, duration)), min(5.0, duration))

            let videoFrameCover = try await VideoAssetService.frameImage(from: stagedURL, at: 0)
            let videoFrameResult = try await buildAndRequest(
                label: "videoFrame",
                stagedURL: stagedURL,
                clipDuration: clipDuration,
                cover: videoFrameCover,
                targetSize: size
            )

            let uploadedSource = makeSyntheticUploadedCover()
            let uploadedCover = try ImageProcessing.renderCover(
                from: uploadedSource,
                targetSize: size,
                cropSelection: CropSelection(centerX: 0.56, centerY: 0.47, width: 0.76)
            )
            let uploadedResult = try await buildAndRequest(
                label: "uploadedCover",
                stagedURL: stagedURL,
                clipDuration: clipDuration,
                cover: uploadedCover,
                targetSize: size
            )

            print("SMOKE_OK")
            print("input=\(inputURL.path)")
            try await printResult(videoFrameResult)
            try await printResult(uploadedResult)
        } catch {
            fputs("SMOKE_FAIL: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func buildAndRequest(
        label: String,
        stagedURL: URL,
        clipDuration: Double,
        cover: NSImage,
        targetSize: CGSize
    ) async throws -> (label: String, package: LivePhotoPackage, livePhoto: PHLivePhoto, metadata: LivePhotoMetadataValidation) {
        let package = try await LivePhotoBuilder.build(
            sourceVideoURL: stagedURL,
            startTime: 0,
            endTime: clipDuration,
            coverImage: cover,
            targetSize: targetSize
        )
        let metadata = try await LivePhotoMetadataInspector.inspect(package: package)
        guard metadata.isPaired, metadata.hasTimedMetadataTrack, metadata.isSupportedVideoCodec, metadata.isDurationCompatible else {
            throw Video2LiveError.exportFailed("Live Photo 元数据配对校验失败")
        }
        let livePhoto = try await requestLivePhoto(package: package)
        return (label, package, livePhoto, metadata)
    }

    private static func printResult(_ result: (label: String, package: LivePhotoPackage, livePhoto: PHLivePhoto, metadata: LivePhotoMetadataValidation)) async throws {
        let photoImage = NSImage(contentsOf: result.package.photoURL) ?? result.package.coverImage
        let photoCGImage = try ImageProcessing.cgImage(from: photoImage)
        let videoSize = try await VideoAssetService.videoDisplaySize(for: AVURLAsset(url: result.package.videoURL))

        print("\(result.label).assetIdentifier=\(result.package.assetIdentifier)")
        print("\(result.label).photo=\(result.package.photoURL.path)")
        print("\(result.label).video=\(result.package.videoURL.path)")
        print("\(result.label).photoSize=\(photoCGImage.width)x\(photoCGImage.height)")
        print("\(result.label).videoSize=\(Int(videoSize.width))x\(Int(videoSize.height))")
        print("\(result.label).livePhotoSize=\(Int(result.livePhoto.size.width))x\(Int(result.livePhoto.size.height))")
        print("\(result.label).photoIdentifierMatches=\(result.metadata.photoIdentifierMatches)")
        print("\(result.label).videoIdentifierMatches=\(result.metadata.videoIdentifierMatches)")
        print("\(result.label).videoCodec=\(result.metadata.videoCodec ?? "unknown")")
        print("\(result.label).isSupportedVideoCodec=\(result.metadata.isSupportedVideoCodec)")
        print("\(result.label).videoDurationSeconds=\(String(format: "%.3f", result.metadata.videoDurationSeconds))")
        print("\(result.label).isDurationCompatible=\(result.metadata.isDurationCompatible)")
        print("\(result.label).hasTimedMetadataTrack=\(result.metadata.hasTimedMetadataTrack)")
    }

    private static func makeSyntheticUploadedCover() -> NSImage {
        let size = CGSize(width: 1400, height: 2200)
        let image = NSImage(size: size)
        image.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.03, green: 0.48, blue: 0.72, alpha: 1),
            NSColor(calibratedRed: 0.95, green: 0.74, blue: 0.24, alpha: 1)
        ])?.draw(in: bounds, angle: 72)

        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
        let linePath = NSBezierPath()
        linePath.lineWidth = 10
        for index in stride(from: -600, through: 2000, by: 260) {
            linePath.move(to: CGPoint(x: CGFloat(index), y: 0))
            linePath.line(to: CGPoint(x: CGFloat(index) + 900, y: size.height))
        }
        linePath.stroke()

        let badgeRect = NSRect(x: 150, y: 930, width: 1100, height: 340)
        NSColor(calibratedWhite: 1, alpha: 0.86).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 36, yRadius: 36).fill()

        let title = "Uploaded Cover"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 108, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1)
        ]
        title.draw(in: badgeRect.insetBy(dx: 72, dy: 102), withAttributes: attributes)

        image.unlockFocus()
        return image
    }

    private static func requestLivePhoto(package: LivePhotoPackage) async throws -> PHLivePhoto {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PHLivePhoto, any Error>) in
            var didResume = false
            PHLivePhoto.request(
                withResourceFileURLs: [package.photoURL, package.videoURL],
                placeholderImage: package.coverImage,
                targetSize: .zero,
                contentMode: .aspectFit
            ) { livePhoto, info in
                if didResume {
                    return
                }
                if let error = info[PHLivePhotoInfoErrorKey] as? Error {
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }
                if let livePhoto, !(info[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false) {
                    didResume = true
                    continuation.resume(returning: livePhoto)
                }
            }
        }
    }
}
