import AppKit
import XCTest
@testable import Video2LiveCore

final class Video2LiveCoreTests: XCTestCase {
    func testCropSelectionLocksToTargetAspectAndClampsWithinSource() {
        let sourceSize = CGSize(width: 1400, height: 2200)
        let targetAspect = 9.0 / 16.0
        let selection = CropSelection(centerX: 0.02, centerY: 0.98, width: 0.95)
            .clamped(sourceSize: sourceSize, targetAspect: targetAspect)
        let cropRect = selection.cropRect(in: sourceSize, targetAspect: targetAspect)

        XCTAssertGreaterThanOrEqual(cropRect.minX, 0)
        XCTAssertGreaterThanOrEqual(cropRect.minY, 0)
        XCTAssertLessThanOrEqual(cropRect.maxX, sourceSize.width + 0.001)
        XCTAssertLessThanOrEqual(cropRect.maxY, sourceSize.height + 0.001)
        XCTAssertEqual(cropRect.width / cropRect.height, targetAspect, accuracy: 0.001)
    }

    func testRenderCoverProducesExactLandscapePixels() throws {
        let image = makeTestImage(size: CGSize(width: 640, height: 480))
        let rendered = try ImageProcessing.renderCover(
            from: image,
            targetSize: CGSize(width: 1920, height: 1080),
            scale: 1,
            offset: .zero
        )
        let cgImage = try ImageProcessing.cgImage(from: rendered)

        XCTAssertEqual(cgImage.width, 1920)
        XCTAssertEqual(cgImage.height, 1080)
    }

    func testRenderCropSelectionProducesExactPortraitPixels() throws {
        let image = makeTestImage(size: CGSize(width: 1400, height: 2200))
        let rendered = try ImageProcessing.renderCover(
            from: image,
            targetSize: CGSize(width: 1080, height: 1920),
            cropSelection: CropSelection(centerX: 0.56, centerY: 0.47, width: 0.76)
        )
        let cgImage = try ImageProcessing.cgImage(from: rendered)

        XCTAssertEqual(cgImage.width, 1080)
        XCTAssertEqual(cgImage.height, 1920)
    }

    func testDefaultCropSelectionUsesFullSameAspectImage() {
        let sourceSize = CGSize(width: 1920, height: 1080)
        let targetAspect = 16.0 / 9.0
        let cropRect = CropSelection()
            .cropRect(in: sourceSize, targetAspect: targetAspect)

        XCTAssertEqual(cropRect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(cropRect.minY, 0, accuracy: 0.001)
        XCTAssertEqual(cropRect.width, sourceSize.width, accuracy: 0.001)
        XCTAssertEqual(cropRect.height, sourceSize.height, accuracy: 0.001)
    }

    func testLivePhotoDurationCompatibilityAllowsExportRoundingOnly() {
        let roundedFiveSecondExport = LivePhotoMetadataValidation(
            expectedAssetIdentifier: "asset",
            photoAssetIdentifier: "asset",
            videoAssetIdentifier: "asset",
            videoCodec: "hvc1",
            videoDurationSeconds: 5.04,
            hasTimedMetadataTrack: true
        )
        let tooLongExport = LivePhotoMetadataValidation(
            expectedAssetIdentifier: "asset",
            photoAssetIdentifier: "asset",
            videoAssetIdentifier: "asset",
            videoCodec: "hvc1",
            videoDurationSeconds: 5.40,
            hasTimedMetadataTrack: true
        )

        XCTAssertTrue(roundedFiveSecondExport.isDurationCompatible)
        XCTAssertFalse(tooLongExport.isDurationCompatible)
    }

    private func makeTestImage(size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.4, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.18, alpha: 1).setFill()
        NSRect(x: size.width * 0.2, y: size.height * 0.2, width: size.width * 0.6, height: size.height * 0.6).fill()
        image.unlockFocus()
        return image
    }
}
