import AppKit
@preconcurrency import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum AndroidMotionPhotoExporter {
    public static func export(
        package: LivePhotoPackage,
        outputDirectory: URL
    ) async throws -> AndroidMotionPhotoPackage {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let diagnosticsDirectory = outputDirectory.appendingPathComponent("_debug", isDirectory: true)
        try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)

        let fallbackVideoURL = diagnosticsDirectory.appendingPathComponent("fallback-video.mp4")
        let coverPhotoURL = diagnosticsDirectory.appendingPathComponent("cover.jpg")
        let motionPhotoURL = outputDirectory.appendingPathComponent("xiaomi-xhs-live-photo.jpg")
        let manifestURL = outputDirectory.appendingPathComponent("README-Xiaomi-XHS.txt")

        try await exportMP4(sourceURL: package.videoURL, outputURL: fallbackVideoURL)
        try writeCoverJPEG(package.coverImage, to: coverPhotoURL)
        try writeAndroidMotionPhotoJPEG(
            coverImage: package.coverImage,
            videoURL: fallbackVideoURL,
            outputURL: motionPhotoURL
        )
        try writeManifest(
            package: package,
            motionPhotoURL: motionPhotoURL,
            fallbackVideoURL: fallbackVideoURL,
            coverPhotoURL: coverPhotoURL,
            manifestURL: manifestURL
        )

        return AndroidMotionPhotoPackage(
            directoryURL: outputDirectory,
            motionPhotoURL: motionPhotoURL,
            fallbackVideoURL: fallbackVideoURL,
            coverPhotoURL: coverPhotoURL,
            manifestURL: manifestURL
        )
    }

    public static func validate(package: AndroidMotionPhotoPackage) async throws -> AndroidMotionPhotoValidation {
        let motionPhotoData = try Data(contentsOf: package.motionPhotoURL)
        let fallbackVideoData = try Data(contentsOf: package.fallbackVideoURL)
        let xmpText = String(decoding: motionPhotoData, as: UTF8.self)
        let microVideoOffset = integerValue(in: xmpText, key: "GCamera:MicroVideoOffset")
        let containerLength = integerValue(in: xmpText, key: "Item:Length", preferNonZero: true)
        let fallbackAsset = AVURLAsset(url: package.fallbackVideoURL)
        let duration = CMTimeGetSeconds(try await fallbackAsset.load(.duration))
        let codec = try await VideoAssetService.videoCodecFourCC(for: fallbackAsset)

        return AndroidMotionPhotoValidation(
            hasXMPMetadata: xmpText.contains("x:xmpmeta"),
            hasMotionPhotoFlag: xmpText.contains("MotionPhoto=\"1\"") || xmpText.contains("MicroVideo=\"1\""),
            hasMicroVideoOffset: microVideoOffset != nil,
            microVideoOffsetMatchesVideoLength: microVideoOffset == fallbackVideoData.count,
            containerItemLengthMatchesVideoLength: containerLength == fallbackVideoData.count,
            appendedVideoMatchesFallbackVideo: motionPhotoData.suffix(fallbackVideoData.count).elementsEqual(fallbackVideoData),
            fallbackVideoCodec: codec,
            fallbackVideoDurationSeconds: duration
        )
    }

    private static func exportMP4(sourceURL: URL, outputURL: URL) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let preset = try await preferredMP4ExportPreset(for: asset)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Video2LiveError.exportSessionUnavailable
        }
        exporter.shouldOptimizeForNetworkUse = true

        do {
            try await exporter.export(to: outputURL, as: .mp4)
        } catch {
            throw Video2LiveError.exportFailed(error.localizedDescription)
        }
    }

    private static func preferredMP4ExportPreset(for asset: AVAsset) async throws -> String {
        for preset in [AVAssetExportPresetHighestQuality, AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720] {
            let compatible = await AVAssetExportSession.compatibility(
                ofExportPreset: preset,
                with: asset,
                outputFileType: .mp4
            )
            if compatible {
                return preset
            }
        }
        throw Video2LiveError.exportFailed("没有兼容的小米/小红书 MP4 导出预设")
    }

    private static func writeCoverJPEG(_ image: NSImage, to url: URL) throws {
        let cgImage = try ImageProcessing.cgImage(from: image)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw Video2LiveError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Video2LiveError.imageEncodingFailed
        }
    }

    private static func writeAndroidMotionPhotoJPEG(
        coverImage: NSImage,
        videoURL: URL,
        outputURL: URL
    ) throws {
        let jpegData = try jpegData(from: coverImage)
        let videoData = try Data(contentsOf: videoURL)
        let xmp = motionPhotoXMP(videoLength: videoData.count)
        let jpegWithXMP = try insertXMPPacket(xmp, intoJPEGData: jpegData)
        var output = Data()
        output.reserveCapacity(jpegWithXMP.count + videoData.count)
        output.append(jpegWithXMP)
        output.append(videoData)
        try output.write(to: outputURL, options: .atomic)
    }

    private static func jpegData(from image: NSImage) throws -> Data {
        let cgImage = try ImageProcessing.cgImage(from: image)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw Video2LiveError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Video2LiveError.imageEncodingFailed
        }
        return data as Data
    }

    private static func motionPhotoXMP(videoLength: Int) -> String {
        """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
                xmlns:Camera="http://ns.google.com/photos/1.0/camera/"
                xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
                xmlns:Container="http://ns.google.com/photos/1.0/container/"
                xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
                Camera:MotionPhoto="1"
                Camera:MotionPhotoVersion="1"
                Camera:MotionPhotoPresentationTimestampUs="0"
                Camera:MicroVideo="1"
                Camera:MicroVideoVersion="1"
                Camera:MicroVideoOffset="\(videoLength)"
                Camera:MicroVideoPresentationTimestampUs="0"
                GCamera:MotionPhoto="1"
                GCamera:MotionPhotoVersion="1"
                GCamera:MotionPhotoPresentationTimestampUs="0"
                GCamera:MicroVideo="1"
                GCamera:MicroVideoVersion="1"
                GCamera:MicroVideoOffset="\(videoLength)"
                GCamera:MicroVideoPresentationTimestampUs="0">
              <Container:Directory>
                <rdf:Seq>
                  <rdf:li rdf:parseType="Resource" Item:Mime="image/jpeg" Item:Semantic="Primary" Item:Length="0" Item:Padding="0"/>
                  <rdf:li rdf:parseType="Resource" Item:Mime="video/mp4" Item:Semantic="MotionPhoto" Item:Length="\(videoLength)" Item:Padding="0"/>
                </rdf:Seq>
              </Container:Directory>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    private static func insertXMPPacket(_ xmp: String, intoJPEGData jpegData: Data) throws -> Data {
        let bytes = [UInt8](jpegData.prefix(2))
        guard bytes == [0xff, 0xd8] else {
            throw Video2LiveError.imageEncodingFailed
        }

        var payload = Data("http://ns.adobe.com/xap/1.0/".utf8)
        payload.append(0)
        payload.append(Data(xmp.utf8))
        let segmentLength = payload.count + 2
        guard segmentLength <= Int(UInt16.max) else {
            throw Video2LiveError.exportFailed("Android Motion Photo XMP metadata 过大")
        }

        var app1 = Data([0xff, 0xe1, UInt8((segmentLength >> 8) & 0xff), UInt8(segmentLength & 0xff)])
        app1.append(payload)

        var output = Data()
        output.reserveCapacity(jpegData.count + app1.count)
        output.append(jpegData.prefix(2))
        output.append(app1)
        output.append(jpegData.dropFirst(2))
        return output
    }

    private static func writeManifest(
        package: LivePhotoPackage,
        motionPhotoURL: URL,
        fallbackVideoURL: URL,
        coverPhotoURL: URL,
        manifestURL: URL
    ) throws {
        let text = """
        Video2Live Xiaomi / Xiaohongshu Export

        Upload/share this one file:
        \(motionPhotoURL.lastPathComponent)

        Do not upload the MP4 fallback unless Xiaohongshu fails to recognize the JPG as a dynamic/live image.

        Use on Xiaomi 17 Pro:
        1. Transfer this JPG to the phone:
           \(motionPhotoURL.lastPathComponent)
        2. Open it in Xiaomi Gallery first. If Gallery recognizes it as a dynamic/live photo, use the same JPG in Xiaohongshu.
        3. In Xiaohongshu, choose the JPG from the phone album/file picker. The Finder icon on Mac will still look like a normal JPG.
        4. If Xiaohongshu Android does not recognize it as a live image, use the fallback video only as a normal video post:
           \(fallbackVideoURL.lastPathComponent)

        Files:
        - \(motionPhotoURL.lastPathComponent): Android Motion Photo candidate JPEG with embedded MP4 payload. This is the primary upload file.
        - _debug/\(fallbackVideoURL.lastPathComponent): Standard MP4 fallback for Xiaohongshu video posting.
        - _debug/\(coverPhotoURL.lastPathComponent): Static cover image for inspection.

        Live Photo asset identifier:
        \(package.assetIdentifier)
        """
        try text.write(to: manifestURL, atomically: true, encoding: .utf8)
    }

    private static func integerValue(in text: String, key: String, preferNonZero: Bool = false) -> Int? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: key))=\"([0-9]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        let values = matches.compactMap { match -> Int? in
            guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[valueRange])
        }
        if preferNonZero {
            return values.first(where: { $0 > 0 }) ?? values.first
        }
        return values.first
    }
}
