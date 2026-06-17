import AppKit
@preconcurrency import AVFoundation
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

public enum LivePhotoBuilder {
    public static func build(
        sourceVideoURL: URL,
        startTime: Double,
        endTime: Double,
        coverImage: NSImage,
        targetSize: CGSize
    ) async throws -> LivePhotoPackage {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Video2Live", isDirectory: true)
            .appendingPathComponent("Output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let assetIdentifier = UUID().uuidString
        let photoURL = outputDirectory.appendingPathComponent("key-photo.jpg")
        let videoURL = outputDirectory.appendingPathComponent("paired-video.mov")

        try await writePairedMovie(
            sourceVideoURL: sourceVideoURL,
            to: videoURL,
            startTime: startTime,
            duration: max(0.1, endTime - startTime),
            assetIdentifier: assetIdentifier
        )

        let pairedVideoSize = try await VideoAssetService.videoDisplaySize(for: AVURLAsset(url: videoURL))
        let renderedCover = try ImageProcessing.renderCover(
            from: coverImage,
            targetSize: pairedVideoSize == .zero ? targetSize : pairedVideoSize,
            scale: 1,
            offset: .zero
        )
        try writePairedPhoto(renderedCover, to: photoURL, assetIdentifier: assetIdentifier)

        return LivePhotoPackage(
            assetIdentifier: assetIdentifier,
            photoURL: photoURL,
            videoURL: videoURL,
            coverImage: renderedCover
        )
    }

    private static func writePairedPhoto(_ image: NSImage, to url: URL, assetIdentifier: String) throws {
        let cgImage = try ImageProcessing.cgImage(from: image)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw Video2LiveError.imageEncodingFailed
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: [
                "17": assetIdentifier
            ],
            kCGImagePropertyOrientation: 1
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Video2LiveError.imageEncodingFailed
        }
    }

    private static func writePairedMovie(
        sourceVideoURL: URL,
        to outputURL: URL,
        startTime: Double,
        duration: Double,
        assetIdentifier: String
    ) async throws {
        let trimmedURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent("trimmed-source.mov")
        try await exportTrimmedMovie(
            sourceVideoURL: sourceVideoURL,
            to: trimmedURL,
            startTime: startTime,
            duration: duration,
            assetIdentifier: assetIdentifier
        )
        try await rewriteMovieWithTimedMetadata(
            sourceURL: trimmedURL,
            outputURL: outputURL,
            assetIdentifier: assetIdentifier
        )
    }

    private static func exportTrimmedMovie(
        sourceVideoURL: URL,
        to outputURL: URL,
        startTime: Double,
        duration: Double,
        assetIdentifier: String
    ) async throws {
        let asset = AVURLAsset(url: sourceVideoURL)
        let composition = AVMutableComposition()
        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw Video2LiveError.missingVideoTrack
        }

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw Video2LiveError.exportFailed("无法创建视频轨道")
        }
        try videoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
        videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudioTrack = audioTracks.first,
           let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? audioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let preferredPreset = try await preferredExportPreset(for: composition, outputFileType: .mov)

        guard let exporter = AVAssetExportSession(asset: composition, presetName: preferredPreset) else {
            throw Video2LiveError.exportSessionUnavailable
        }
        exporter.shouldOptimizeForNetworkUse = true
        exporter.metadata = movieMetadata(assetIdentifier: assetIdentifier)

        try await export(exporter, to: outputURL)
    }

    private static func preferredExportPreset(for asset: AVAsset, outputFileType: AVFileType) async throws -> String {
        for preset in [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality] {
            let compatible = await AVAssetExportSession.compatibility(
                ofExportPreset: preset,
                with: asset,
                outputFileType: outputFileType
            )
            if compatible {
                return preset
            }
        }
        throw Video2LiveError.exportFailed("没有兼容的 MOV 导出预设")
    }

    private static func movieMetadata(assetIdentifier: String) -> [AVMetadataItem] {
        let contentIdentifier = AVMutableMetadataItem()
        contentIdentifier.identifier = .quickTimeMetadataContentIdentifier
        contentIdentifier.dataType = kCMMetadataBaseDataType_UTF8 as String
        contentIdentifier.value = assetIdentifier as NSString

        let software = AVMutableMetadataItem()
        software.identifier = .quickTimeMetadataSoftware
        software.dataType = kCMMetadataBaseDataType_UTF8 as String
        software.value = "Video2Live" as NSString

        return [contentIdentifier, software]
    }

    private static func stillImageTimeMetadataGroup() throws -> AVTimedMetadataGroup {
        let stillImageTime = AVMutableMetadataItem()
        stillImageTime.keySpace = .quickTimeMetadata
        stillImageTime.key = "com.apple.quicktime.still-image-time" as NSString
        stillImageTime.dataType = kCMMetadataBaseDataType_SInt8 as String
        stillImageTime.value = 0 as NSNumber
        return AVTimedMetadataGroup(
            items: [stillImageTime],
            timeRange: CMTimeRange(
                start: .zero,
                duration: CMTime(value: 1, timescale: 600)
            )
        )
    }

    private static func rewriteMovieWithTimedMetadata(
        sourceURL: URL,
        outputURL: URL,
        assetIdentifier: String
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        writer.metadata = movieMetadata(assetIdentifier: assetIdentifier)

        let timedMetadataGroup = try stillImageTimeMetadataGroup()
        guard let metadataFormatDescription = timedMetadataGroup.copyFormatDescription() else {
            throw Video2LiveError.exportFailed("无法创建 timed metadata 格式描述")
        }
        let metadataInput = AVAssetWriterInput(
            mediaType: .metadata,
            outputSettings: nil,
            sourceFormatHint: metadataFormatDescription
        )
        let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        guard writer.canAdd(metadataInput) else {
            throw Video2LiveError.exportFailed("无法添加 timed metadata 轨道")
        }
        writer.add(metadataInput)

        var mediaPairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        for track in videoTracks {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw Video2LiveError.exportFailed("无法添加视频读取轨道")
            }
            reader.add(output)

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            input.transform = try await track.load(.preferredTransform)
            guard writer.canAdd(input) else {
                throw Video2LiveError.exportFailed("无法添加视频写入轨道")
            }
            writer.add(input)
            mediaPairs.append((output, input))
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for track in audioTracks {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { continue }
            reader.add(output)

            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { continue }
            writer.add(input)
            mediaPairs.append((output, input))
        }

        guard !mediaPairs.isEmpty else {
            throw Video2LiveError.exportFailed("没有可写入的媒体轨道")
        }
        guard writer.startWriting() else {
            throw Video2LiveError.exportFailed(writer.error?.localizedDescription ?? "AVAssetWriter 启动失败")
        }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw Video2LiveError.exportFailed(reader.error?.localizedDescription ?? "AVAssetReader 启动失败")
        }
        writer.startSession(atSourceTime: .zero)

        guard metadataAdaptor.append(timedMetadataGroup) else {
            reader.cancelReading()
            writer.cancelWriting()
            throw Video2LiveError.exportFailed(writer.error?.localizedDescription ?? "timed metadata 写入失败")
        }
        metadataInput.markAsFinished()

        let readerRef = SendableReference(reader)
        let writerRef = SendableReference(writer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let dispatchGroup = DispatchGroup()
            let failureState = RewriteFailureState()

            for (index, pair) in mediaPairs.enumerated() {
                dispatchGroup.enter()
                let outputRef = SendableReference(pair.0)
                let inputRef = SendableReference(pair.1)
                let queue = DispatchQueue(label: "Video2Live.movie-rewrite.track-\(index)")
                inputRef.value.requestMediaDataWhenReady(on: queue) {
                    while inputRef.value.isReadyForMoreMediaData {
                        if let sampleBuffer = outputRef.value.copyNextSampleBuffer() {
                            if !inputRef.value.append(sampleBuffer) {
                                failureState.markFailed()
                                readerRef.value.cancelReading()
                                inputRef.value.markAsFinished()
                                dispatchGroup.leave()
                                return
                            }
                        } else {
                            inputRef.value.markAsFinished()
                            dispatchGroup.leave()
                            return
                        }
                    }
                }
            }

            dispatchGroup.notify(queue: DispatchQueue(label: "Video2Live.movie-rewrite.finish")) {
                if failureState.isFailed || readerRef.value.status == .failed || readerRef.value.status == .cancelled {
                    writerRef.value.cancelWriting()
                    continuation.resume(throwing: Video2LiveError.exportFailed(readerRef.value.error?.localizedDescription ?? writerRef.value.error?.localizedDescription ?? "媒体重写失败"))
                    return
                }

                writerRef.value.finishWriting {
                    if writerRef.value.status == .completed {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: Video2LiveError.exportFailed(writerRef.value.error?.localizedDescription ?? "MOV metadata 封装失败"))
                    }
                }
            }
        }
    }

    private static func export(_ exporter: AVAssetExportSession, to outputURL: URL) async throws {
        do {
            try await exporter.export(to: outputURL, as: .mov)
        } catch {
            throw Video2LiveError.exportFailed(error.localizedDescription)
        }
    }
}

private final class SendableReference<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private final class RewriteFailureState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Video2Live.movie-rewrite.state")
    private var failed = false

    func markFailed() {
        queue.sync {
            failed = true
        }
    }

    var isFailed: Bool {
        queue.sync {
            failed
        }
    }
}

public enum PhotoLibraryWriter {
    public static let albumTitle = "Video2Live"

    public static func save(photoURL: URL, videoURL: URL) async throws -> SavedLivePhotoAsset {
        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            throw Video2LiveError.photoLibraryDenied
        }

        let createdIdentifier = CreatedIdentifierBox()
        let existingAlbum = fetchAlbum()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let state = ThrowingVoidContinuationState()
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let photoOptions = PHAssetResourceCreationOptions()
                photoOptions.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: photoURL, options: photoOptions)

                let videoOptions = PHAssetResourceCreationOptions()
                videoOptions.shouldMoveFile = false
                request.addResource(with: .pairedVideo, fileURL: videoURL, options: videoOptions)
                guard let placeholder = request.placeholderForCreatedAsset else {
                    return
                }
                createdIdentifier.value = placeholder.localIdentifier
                let albumRequest: PHAssetCollectionChangeRequest?
                if let existingAlbum {
                    albumRequest = PHAssetCollectionChangeRequest(for: existingAlbum)
                } else {
                    albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                }
                albumRequest?.addAssets([placeholder] as NSArray)
            } completionHandler: { success, error in
                if success {
                    state.resumeReturning(continuation)
                } else {
                    state.resume(
                        continuation,
                        throwing: Video2LiveError.photoLibrarySaveFailed(error?.localizedDescription ?? "未知错误")
                    )
                }
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20) {
                state.resume(
                    continuation,
                    throwing: Video2LiveError.photoLibrarySaveFailed("Photos 写入事务超时")
                )
            }
        }

        guard let localIdentifier = createdIdentifier.value else {
            throw Video2LiveError.photoLibrarySaveFailed("Photos 未返回新资产标识")
        }
        return try await verifyLivePhotoAsset(localIdentifier: localIdentifier)
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            let state = PhotoAuthorizationContinuationState()
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                state.resume(continuation, returning: status)
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10) {
                state.resume(continuation, returning: .denied)
            }
        }
    }

    private static func verifyLivePhotoAsset(localIdentifier: String) async throws -> SavedLivePhotoAsset {
        for attempt in 0..<10 {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            if let asset = assets.firstObject {
                let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
                let resourceTypes = resourceTypeNames(for: asset)
                let cloudIdentifierResult = cloudIdentifier(for: localIdentifier)
                if isLivePhoto {
                    let canLoadLivePhoto = await canLoadLivePhoto(for: asset)
                    let isInAlbum = assetIsInAlbum(localIdentifier: localIdentifier)
                    let hasResourcePair = resourceTypes.contains("photo") && resourceTypes.contains("pairedVideo")
                    if (canLoadLivePhoto && isInAlbum && hasResourcePair) || attempt == 9 {
                        return SavedLivePhotoAsset(
                            localIdentifier: localIdentifier,
                            isLivePhoto: true,
                            canLoadLivePhoto: canLoadLivePhoto,
                            albumTitle: albumTitle,
                            isInAlbum: isInAlbum,
                            resourceTypes: resourceTypes,
                            cloudIdentifier: cloudIdentifierResult.identifier,
                            cloudIdentifierError: cloudIdentifierResult.error,
                            cloudIdentifierRoundTripLocalIdentifier: cloudIdentifierResult.roundTripLocalIdentifier,
                            cloudIdentifierRoundTripError: cloudIdentifierResult.roundTripError
                        )
                    }
                } else if attempt == 9 {
                    return SavedLivePhotoAsset(
                        localIdentifier: localIdentifier,
                        isLivePhoto: false,
                        canLoadLivePhoto: false,
                        albumTitle: albumTitle,
                        isInAlbum: assetIsInAlbum(localIdentifier: localIdentifier),
                        resourceTypes: resourceTypes,
                        cloudIdentifier: cloudIdentifierResult.identifier,
                        cloudIdentifierError: cloudIdentifierResult.error,
                        cloudIdentifierRoundTripLocalIdentifier: cloudIdentifierResult.roundTripLocalIdentifier,
                        cloudIdentifierRoundTripError: cloudIdentifierResult.roundTripError
                    )
                }
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw Video2LiveError.photoLibrarySaveFailed("无法在 Photos 中找到新保存的资产")
    }

    private static func canLoadLivePhoto(for asset: PHAsset) async -> Bool {
        await withCheckedContinuation { continuation in
            let state = BoolContinuationState()
            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, info in
                if livePhoto != nil {
                    state.resume(continuation, returning: true)
                    return
                }

                if info?[PHLivePhotoInfoErrorKey] is Error
                    || (info?[PHLivePhotoInfoCancelledKey] as? Bool ?? false)
                    || !(info?[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false) {
                    state.resume(continuation, returning: false)
                }
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8) {
                state.resume(continuation, returning: false)
            }
        }
    }

    private static func resourceTypeNames(for asset: PHAsset) -> [String] {
        PHAssetResource.assetResources(for: asset)
            .map { resourceTypeName($0.type) }
            .sorted()
    }

    private static func cloudIdentifier(for localIdentifier: String) -> CloudIdentifierLookupResult {
        let cloudLookup = cloudIdentifierMapping(for: localIdentifier, timeout: 5)
        guard let cloudIdentifier = cloudLookup.cloudIdentifier else {
            return CloudIdentifierLookupResult(
                identifier: nil,
                error: cloudLookup.error,
                roundTripLocalIdentifier: nil,
                roundTripError: nil
            )
        }

        let roundTripLookup = localIdentifierMapping(for: cloudIdentifier, timeout: 5)
        return CloudIdentifierLookupResult(
            identifier: cloudIdentifier.stringValue,
            error: nil,
            roundTripLocalIdentifier: roundTripLookup.localIdentifier,
            roundTripError: roundTripLookup.error
        )
    }

    private static func cloudIdentifierMapping(
        for localIdentifier: String,
        timeout: TimeInterval
    ) -> (cloudIdentifier: PHCloudIdentifier?, error: String?) {
        let box = CloudIdentifierMappingBox()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            let mapping = PHPhotoLibrary.shared()
                .cloudIdentifierMappings(forLocalIdentifiers: [localIdentifier])[localIdentifier]
            guard let mapping else {
                box.set(cloudIdentifier: nil, error: "missing mapping")
                semaphore.signal()
                return
            }

            switch mapping {
            case .success(let cloudIdentifier):
                box.set(cloudIdentifier: cloudIdentifier, error: nil)
            case .failure(let error):
                box.set(cloudIdentifier: nil, error: error.localizedDescription)
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            return (nil, "cloud identifier lookup timed out")
        }
        return box.snapshot()
    }

    private static func localIdentifierMapping(
        for cloudIdentifier: PHCloudIdentifier,
        timeout: TimeInterval
    ) -> (localIdentifier: String?, error: String?) {
        let box = LocalIdentifierMappingBox()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            let mapping = PHPhotoLibrary.shared()
                .localIdentifierMappings(for: [cloudIdentifier])[cloudIdentifier]
            guard let mapping else {
                box.set(localIdentifier: nil, error: "missing round-trip mapping")
                semaphore.signal()
                return
            }

            switch mapping {
            case .success(let localIdentifier):
                box.set(localIdentifier: localIdentifier, error: nil)
            case .failure(let error):
                box.set(localIdentifier: nil, error: error.localizedDescription)
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            return (nil, "cloud identifier round-trip lookup timed out")
        }
        return box.snapshot()
    }

    private static func resourceTypeName(_ type: PHAssetResourceType) -> String {
        switch type {
        case .photo:
            "photo"
        case .video:
            "video"
        case .audio:
            "audio"
        case .alternatePhoto:
            "alternatePhoto"
        case .fullSizePhoto:
            "fullSizePhoto"
        case .fullSizeVideo:
            "fullSizeVideo"
        case .adjustmentData:
            "adjustmentData"
        case .adjustmentBasePhoto:
            "adjustmentBasePhoto"
        case .pairedVideo:
            "pairedVideo"
        case .fullSizePairedVideo:
            "fullSizePairedVideo"
        case .adjustmentBasePairedVideo:
            "adjustmentBasePairedVideo"
        case .adjustmentBaseVideo:
            "adjustmentBaseVideo"
        case .photoProxy:
            "photoProxy"
        @unknown default:
            "unknown-\(type.rawValue)"
        }
    }

    private static func fetchAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumTitle)
        options.fetchLimit = 1
        return PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: options
        ).firstObject
    }

    private static func assetIsInAlbum(localIdentifier: String) -> Bool {
        guard let album = fetchAlbum() else { return false }
        var isInAlbum = false
        PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, stop in
            if asset.localIdentifier == localIdentifier {
                isInAlbum = true
                stop.pointee = true
            }
        }
        return isInAlbum
    }
}

public enum LivePhotoMetadataInspector {
    public static func inspect(package: LivePhotoPackage) async throws -> LivePhotoMetadataValidation {
        let photoIdentifier = try photoAssetIdentifier(at: package.photoURL)
        let videoAsset = AVURLAsset(url: package.videoURL)
        let videoIdentifier = try await videoAssetIdentifier(in: videoAsset)
        let videoCodec = try await VideoAssetService.videoCodecFourCC(for: videoAsset)
        let videoDuration = CMTimeGetSeconds(try await videoAsset.load(.duration))
        let metadataTracks = try await videoAsset.loadTracks(withMediaType: .metadata)

        return LivePhotoMetadataValidation(
            expectedAssetIdentifier: package.assetIdentifier,
            photoAssetIdentifier: photoIdentifier,
            videoAssetIdentifier: videoIdentifier,
            videoCodec: videoCodec,
            videoDurationSeconds: videoDuration,
            hasTimedMetadataTrack: !metadataTracks.isEmpty
        )
    }

    private static func photoAssetIdentifier(at url: URL) throws -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw Video2LiveError.imageEncodingFailed
        }

        if let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any] {
            return makerApple["17"] as? String
        }
        if let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [CFString: Any] {
            return makerApple["17" as CFString] as? String
        }
        return nil
    }

    private static func videoAssetIdentifier(in asset: AVURLAsset) async throws -> String? {
        let metadata = try await asset.load(.metadata)
        for item in metadata where item.identifier == .quickTimeMetadataContentIdentifier {
            return try await item.load(.stringValue)
        }
        return nil
    }
}

private final class CreatedIdentifierBox: @unchecked Sendable {
    var value: String?
}

private struct CloudIdentifierLookupResult: Sendable {
    let identifier: String?
    let error: String?
    let roundTripLocalIdentifier: String?
    let roundTripError: String?
}

private final class CloudIdentifierMappingBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cloudIdentifier: PHCloudIdentifier?
    private var error: String?

    func set(cloudIdentifier: PHCloudIdentifier?, error: String?) {
        lock.lock()
        self.cloudIdentifier = cloudIdentifier
        self.error = error
        lock.unlock()
    }

    func snapshot() -> (cloudIdentifier: PHCloudIdentifier?, error: String?) {
        lock.lock()
        let result = (cloudIdentifier, error)
        lock.unlock()
        return result
    }
}

private final class LocalIdentifierMappingBox: @unchecked Sendable {
    private let lock = NSLock()
    private var localIdentifier: String?
    private var error: String?

    func set(localIdentifier: String?, error: String?) {
        lock.lock()
        self.localIdentifier = localIdentifier
        self.error = error
        lock.unlock()
    }

    func snapshot() -> (localIdentifier: String?, error: String?) {
        lock.lock()
        let result = (localIdentifier, error)
        lock.unlock()
        return result
    }
}

private final class BoolContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<Bool, Never>, returning value: Bool) {
        lock.lock()
        let shouldResume = !didResume
        if shouldResume {
            didResume = true
        }
        lock.unlock()

        if shouldResume {
            continuation.resume(returning: value)
        }
    }
}

private final class ThrowingVoidContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resumeReturning(_ continuation: CheckedContinuation<Void, any Error>) {
        lock.lock()
        let shouldResume = !didResume
        if shouldResume {
            didResume = true
        }
        lock.unlock()

        if shouldResume {
            continuation.resume()
        }
    }

    func resume(_ continuation: CheckedContinuation<Void, any Error>, throwing error: any Error) {
        lock.lock()
        let shouldResume = !didResume
        if shouldResume {
            didResume = true
        }
        lock.unlock()

        if shouldResume {
            continuation.resume(throwing: error)
        }
    }
}

private final class PhotoAuthorizationContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<PHAuthorizationStatus, Never>, returning status: PHAuthorizationStatus) {
        lock.lock()
        let shouldResume = !didResume
        if shouldResume {
            didResume = true
        }
        lock.unlock()

        if shouldResume {
            continuation.resume(returning: status)
        }
    }
}
