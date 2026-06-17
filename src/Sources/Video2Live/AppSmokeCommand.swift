import AppKit
import AVFoundation
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers
import Video2LiveCore

enum AppSmokeCommand {
    private static let photosCommandFlag = "--smoke-save-to-photos"
    private static let workflowCommandFlag = "--smoke-app-workflow"
    private static let xiaomiXHSCommandFlag = "--smoke-xiaomi-xhs-export"
    @MainActor private static var didStart = false

    static var isRequested: Bool {
        CommandLine.arguments.contains(photosCommandFlag)
            || CommandLine.arguments.contains(workflowCommandFlag)
            || CommandLine.arguments.contains(xiaomiXHSCommandFlag)
    }

    @MainActor
    static func runIfRequested() {
        guard isRequested, !didStart else { return }
        didStart = true

        Task {
            let isWorkflowSmoke = CommandLine.arguments.contains(workflowCommandFlag)
            let isXiaomiXHSSmoke = CommandLine.arguments.contains(xiaomiXHSCommandFlag)
            do {
                resetLogIfNeeded()
                if isWorkflowSmoke {
                    log("APP_WORKFLOW_SMOKE_START")
                    let inputURL = try inputVideoURL()
                    log("APP_WORKFLOW_SMOKE_INPUT \(inputURL.path)")
                    let results = try await runAppWorkflowSmoke(inputURL: inputURL)
                    log("APP_WORKFLOW_SMOKE_OK")
                    for result in results {
                        logWorkflowResult(result)
                    }
                    Foundation.exit(0)
                }

                if isXiaomiXHSSmoke {
                    log("APP_XIAOMI_XHS_SMOKE_START")
                    let inputURL = try inputVideoURL()
                    log("APP_XIAOMI_XHS_SMOKE_INPUT \(inputURL.path)")
                    let results = try await runXiaomiXHSExportSmoke(inputURL: inputURL)
                    log("APP_XIAOMI_XHS_SMOKE_OK")
                    for result in results {
                        log("\(result.label).directory=\(result.package.directoryURL.path)")
                        log("\(result.label).motionPhoto=\(result.package.motionPhotoURL.path)")
                        log("\(result.label).fallbackVideo=\(result.package.fallbackVideoURL.path)")
                        log("\(result.label).coverPhoto=\(result.package.coverPhotoURL.path)")
                        log("\(result.label).manifest=\(result.package.manifestURL.path)")
                        log("\(result.label).hasXMPMetadata=\(result.validation.hasXMPMetadata)")
                        log("\(result.label).hasMotionPhotoFlag=\(result.validation.hasMotionPhotoFlag)")
                        log("\(result.label).hasMicroVideoOffset=\(result.validation.hasMicroVideoOffset)")
                        log("\(result.label).microVideoOffsetMatchesVideoLength=\(result.validation.microVideoOffsetMatchesVideoLength)")
                        log("\(result.label).containerItemLengthMatchesVideoLength=\(result.validation.containerItemLengthMatchesVideoLength)")
                        log("\(result.label).appendedVideoMatchesFallbackVideo=\(result.validation.appendedVideoMatchesFallbackVideo)")
                        log("\(result.label).fallbackVideoCodec=\(result.validation.fallbackVideoCodec ?? "unknown")")
                        log("\(result.label).fallbackVideoDurationSeconds=\(String(format: "%.3f", result.validation.fallbackVideoDurationSeconds))")
                        log("\(result.label).isSupportedVideoCodec=\(result.validation.isSupportedVideoCodec)")
                        log("\(result.label).isDurationCompatible=\(result.validation.isDurationCompatible)")
                        log("\(result.label).isValid=\(result.validation.isValid)")
                    }
                    Foundation.exit(0)
                }

                log("APP_PHOTOS_SMOKE_START")
                let inputURL = try inputVideoURL()
                log("APP_PHOTOS_SMOKE_INPUT \(inputURL.path)")
                let results = try await runPhotosSaveSmoke(inputURL: inputURL)
                log("APP_PHOTOS_SMOKE_OK")
                log("input=\(inputURL.path)")
                for result in results {
                    let photoSize = try photoPixelSize(for: result.package)
                    let videoSize = try await VideoAssetService.videoDisplaySize(for: AVURLAsset(url: result.package.videoURL))
                    log("\(result.label).assetIdentifier=\(result.package.assetIdentifier)")
                    log("\(result.label).photo=\(result.package.photoURL.path)")
                    log("\(result.label).video=\(result.package.videoURL.path)")
                    log("\(result.label).photoSize=\(Int(photoSize.width))x\(Int(photoSize.height))")
                    log("\(result.label).videoSize=\(Int(videoSize.width))x\(Int(videoSize.height))")
                    log("\(result.label).livePhotoSize=\(Int(result.livePhoto.size.width))x\(Int(result.livePhoto.size.height))")
                    log("\(result.label).photoIdentifierMatches=\(result.metadata.photoIdentifierMatches)")
                    log("\(result.label).videoIdentifierMatches=\(result.metadata.videoIdentifierMatches)")
                    log("\(result.label).videoCodec=\(result.metadata.videoCodec ?? "unknown")")
                    log("\(result.label).isSupportedVideoCodec=\(result.metadata.isSupportedVideoCodec)")
                    log("\(result.label).videoDurationSeconds=\(String(format: "%.3f", result.metadata.videoDurationSeconds))")
                    log("\(result.label).isDurationCompatible=\(result.metadata.isDurationCompatible)")
                    log("\(result.label).hasTimedMetadataTrack=\(result.metadata.hasTimedMetadataTrack)")
                    log("\(result.label).photosLocalIdentifier=\(result.savedAsset.localIdentifier)")
                    log("\(result.label).photosIsLivePhoto=\(result.savedAsset.isLivePhoto)")
                    log("\(result.label).photosCanLoadLivePhoto=\(result.savedAsset.canLoadLivePhoto)")
                    log("\(result.label).photosResourceTypes=\(result.savedAsset.resourceTypes.joined(separator: ","))")
                    log("\(result.label).photosHasLivePhotoResourcePair=\(result.savedAsset.hasLivePhotoResourcePair)")
                    log("\(result.label).photosAlbumTitle=\(result.savedAsset.albumTitle)")
                    log("\(result.label).photosIsInAlbum=\(result.savedAsset.isInAlbum)")
                    log("\(result.label).photosHasCloudIdentifier=\(result.savedAsset.hasCloudIdentifier)")
                    log("\(result.label).photosCloudIdentifier=\(result.savedAsset.cloudIdentifier ?? "none")")
                    log("\(result.label).photosCloudIdentifierError=\(result.savedAsset.cloudIdentifierError ?? "none")")
                    log("\(result.label).photosCloudIdentifierRoundTripLocalIdentifier=\(result.savedAsset.cloudIdentifierRoundTripLocalIdentifier ?? "none")")
                    log("\(result.label).photosCloudIdentifierRoundTripError=\(result.savedAsset.cloudIdentifierRoundTripError ?? "none")")
                    log("\(result.label).photosCloudIdentifierRoundTripMatches=\(result.savedAsset.cloudIdentifierRoundTripMatches)")
                    log("\(result.label).validationRecordPhotosID=\(AppViewModel.shortPhotosIdentifier(from: result.savedAsset.localIdentifier))")
                    log("\(result.label).validationRecordHasResourcePairField=\(result.validationRecord.contains("macOS Photos resources: pass"))")
                    log("\(result.label).validationRecordHasAlbumFields=\(result.validationRecord.contains("macOS Photos album: \(result.savedAsset.albumTitle)") && result.validationRecord.contains("iPhone lookup album: Photos > Albums > \(result.savedAsset.albumTitle)"))")
                    log("\(result.label).validationRecordHasDurationField=\(result.validationRecord.contains("MOV duration:"))")
                    log("\(result.label).validationRecordHasCloudIdentifierField=\(result.validationRecord.contains("iCloud cloud identifier:"))")
                    log("\(result.label).validationRecordHasCloudRoundTripField=\(result.validationRecord.contains("iCloud round trip:"))")
                    log("\(result.label).validationRecordHasIPhoneFields=\(result.validationRecord.contains("iPhone Photos sync") && result.validationRecord.contains("iPhone Live Photo playback"))")
                    log("\(result.label).validationRecordHasWeChatFields=\(result.validationRecord.contains("WeChat Moments selection") && result.validationRecord.contains("WeChat Moments publish"))")
                    log("\(result.label).validationRecordHasXiaohongshuFields=\(result.validationRecord.contains("Xiaohongshu selection") && result.validationRecord.contains("Xiaohongshu publish/draft"))")
                    log("\(result.label).validationRecordHistoryCount=\(result.validationRecordHistoryCount)")
                }
                Foundation.exit(0)
            } catch {
                let prefix = isWorkflowSmoke
                    ? "APP_WORKFLOW_SMOKE_FAIL"
                    : isXiaomiXHSSmoke
                    ? "APP_XIAOMI_XHS_SMOKE_FAIL"
                    : "APP_PHOTOS_SMOKE_FAIL"
                log("\(prefix): \(error.localizedDescription)")
                fputs("\(prefix): \(error.localizedDescription)\n", stderr)
                fflush(stderr)
                Foundation.exit(1)
            }
        }
    }

    @MainActor
    private static func runAppWorkflowSmoke(inputURL: URL) async throws -> [WorkflowSmokeResult] {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw Video2LiveError.invalidVideo
        }

        let viewModel = AppViewModel()

        log("APP_WORKFLOW_SMOKE_STAGE importVideo")
        try await viewModel.importVideoAndWait(from: inputURL)
        try require(viewModel.videoURL != nil, "视频导入后 videoURL 为空")
        try require(viewModel.player.currentItem != nil, "视频导入后播放器没有 currentItem")
        try require(viewModel.duration >= 1, "视频时长不足 1 秒")
        try require(viewModel.videoSize.width > 0 && viewModel.videoSize.height > 0, "视频尺寸无效")
        try require(viewModel.videoFrameCover != nil, "视频帧封面未生成")
        log("APP_WORKFLOW_SMOKE_IMPORTED duration=\(viewModel.duration) size=\(Int(viewModel.videoSize.width))x\(Int(viewModel.videoSize.height))")

        log("APP_WORKFLOW_SMOKE_STAGE trim")
        let start = min(max(0.5, viewModel.duration * 0.1), max(0, viewModel.duration - 1))
        viewModel.updateStartTime(start)
        viewModel.updateEndTime(start + 10)
        try require(viewModel.selectedDuration >= 1, "裁剪片段短于 1 秒")
        try require(viewModel.selectedDuration <= 5, "裁剪片段长于 5 秒")
        try require(viewModel.isSelectedDurationCompatible, "裁剪片段不满足 1-5 秒生成条件")
        try require(viewModel.canGenerate, "视频选帧模式下 1-5 秒片段仍无法生成")
        try require(viewModel.coverTime >= viewModel.startTime && viewModel.coverTime <= viewModel.endTime, "封面时间不在裁剪区间内")
        log("APP_WORKFLOW_SMOKE_TRIM start=\(viewModel.startTime) end=\(viewModel.endTime) selected=\(viewModel.selectedDuration)")

        log("APP_WORKFLOW_SMOKE_STAGE boundedPlayback")
        let exportEndTime = viewModel.endTime
        viewModel.updateEndTime(viewModel.startTime + 1.0)
        try require(abs(viewModel.selectedDuration - 1.0) < 0.02, "播放边界测试未能设置 1 秒片段")
        viewModel.seekToStart()
        viewModel.playPause()
        try await Task.sleep(nanoseconds: 300_000_000)
        try await seek(viewModel.player, to: viewModel.endTime + 0.2)
        viewModel.player.play()
        viewModel.enforcePlaybackBoundaryForCurrentTime()
        try await waitForBoundedPlaybackStop(viewModel)
        let playbackTime = viewModel.currentPlaybackTime
        try require(playbackTime >= viewModel.startTime && playbackTime <= viewModel.endTime + 0.3, "播放器停止位置不在裁剪片段附近")
        log("APP_WORKFLOW_SMOKE_PLAYBACK_BOUNDED current=\(playbackTime) end=\(viewModel.endTime)")
        viewModel.updateEndTime(exportEndTime)

        log("APP_WORKFLOW_SMOKE_STAGE videoFrameCover")
        try await viewModel.updateCoverTimeAndWait(viewModel.startTime + viewModel.selectedDuration / 2)
        try require(viewModel.videoFrameCover != nil, "更新封面时间后视频帧封面为空")
        try require(viewModel.canGenerate, "视频选帧模式下无法生成")
        try await viewModel.generateLivePhotoAndWait()
        let videoFrameResult = try await validateViewModelPackage(label: "videoFrame", viewModel: viewModel)

        log("APP_WORKFLOW_SMOKE_STAGE uploadedCover")
        let coverURL = try writeSyntheticUploadedCover()
        viewModel.importCoverImage(from: coverURL)
        try require(viewModel.uploadedCover != nil, "上传封面未载入")
        try require(viewModel.coverMode == .uploadedImage, "上传封面后 coverMode 未切换")
        if let uploadedCover = viewModel.uploadedCover {
            viewModel.updateCropSelection(
                CropSelection(centerX: 0.58, centerY: 0.43, width: 0.72),
                sourceImage: uploadedCover
            )
        }
        try require(viewModel.canGenerate, "上传封面模式下无法生成")
        try await viewModel.generateLivePhotoAndWait()
        let uploadedCoverResult = try await validateViewModelPackage(label: "uploadedCover", viewModel: viewModel)

        return [videoFrameResult, uploadedCoverResult]
    }

    @MainActor
    private static func validateViewModelPackage(label: String, viewModel: AppViewModel) async throws -> WorkflowSmokeResult {
        guard let package = viewModel.generatedPackage else {
            throw Video2LiveError.exportFailed("\(label) 没有生成 Live Photo package")
        }
        guard let generatedMetadata = viewModel.generatedMetadataValidation else {
            throw Video2LiveError.exportFailed("\(label) UI 生成路径没有记录 metadata 校验结果")
        }
        let metadata = try await LivePhotoMetadataInspector.inspect(package: package)
        try require(generatedMetadata.isPaired, "\(label) UI 生成路径记录的配对标识不一致")
        try require(generatedMetadata.hasTimedMetadataTrack, "\(label) UI 生成路径记录缺少 timed metadata track")
        try require(generatedMetadata.isSupportedVideoCodec, "\(label) UI 生成路径记录的 codec 不是 H.264/HEVC")
        try require(generatedMetadata.isDurationCompatible, "\(label) UI 生成路径记录的 MOV 时长不是 1-5 秒")
        try require(generatedMetadata.videoCodec == metadata.videoCodec, "\(label) UI 记录 codec 和文件实际 codec 不一致")
        try require(abs(generatedMetadata.videoDurationSeconds - metadata.videoDurationSeconds) < 0.02, "\(label) UI 记录 MOV 时长和文件实际时长不一致")
        try require(metadata.isPaired, "\(label) JPEG/MOV 配对标识不一致")
        try require(metadata.hasTimedMetadataTrack, "\(label) 缺少 timed metadata track")
        try require(metadata.isSupportedVideoCodec, "\(label) paired MOV 编码不是 H.264/HEVC")
        try require(metadata.isDurationCompatible, "\(label) paired MOV 时长不是 1-5 秒")

        let livePhoto = try await requestLivePhoto(package: package)
        try await waitForViewModelPreview(viewModel, label: label)
        let photoSize = try photoPixelSize(for: package)
        let videoSize = try await VideoAssetService.videoDisplaySize(for: AVURLAsset(url: package.videoURL))

        try require(Int(photoSize.width) == Int(videoSize.width) && Int(photoSize.height) == Int(videoSize.height), "\(label) key photo 和 paired video 尺寸不一致")

        return WorkflowSmokeResult(
            label: label,
            package: package,
            livePhoto: livePhoto,
            metadata: metadata,
            photoSize: photoSize,
            videoSize: videoSize,
            previewPlaybackRequest: viewModel.previewPlaybackRequest
        )
    }

    @MainActor
    private static func waitForViewModelPreview(_ viewModel: AppViewModel, label: String) async throws {
        for _ in 0..<30 {
            if viewModel.livePhoto != nil {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw Video2LiveError.exportFailed("\(label) PHLivePhotoView 预览资源未加载")
    }

    @MainActor
    private static func waitForBoundedPlaybackStop(_ viewModel: AppViewModel) async throws {
        for _ in 0..<40 {
            let playbackTime = viewModel.currentPlaybackTime
            if viewModel.player.timeControlStatus != .playing,
               playbackTime >= viewModel.startTime,
               playbackTime <= viewModel.endTime + 0.3 {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        throw Video2LiveError.exportFailed(
            "播放器未在裁剪终点自动暂停，current=\(viewModel.currentPlaybackTime), end=\(viewModel.endTime), status=\(String(describing: viewModel.player.timeControlStatus))"
        )
    }

    @MainActor
    private static func seek(_ player: AVPlayer, to seconds: Double) async throws {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let didFinish = await withCheckedContinuation { continuation in
            let state = BoolContinuationState()

            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                state.resume(continuation, returning: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                state.resume(continuation, returning: false)
            }
        }
        guard didFinish else {
            throw Video2LiveError.exportFailed("播放器 seek 超时，无法验证裁剪播放边界")
        }
    }

    private static func inputVideoURL() throws -> URL {
        if let value = argument(after: "--input") {
            return URL(fileURLWithPath: value)
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            currentDirectory.appendingPathComponent("videos/lulu.mp4"),
            currentDirectory.deletingLastPathComponent().appendingPathComponent("videos/lulu.mp4")
        ]
        if let candidate = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return candidate
        }
        throw Video2LiveError.invalidVideo
    }

    private static func argument(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = CommandLine.arguments.index(after: index)
        guard CommandLine.arguments.indices.contains(valueIndex) else { return nil }
        return CommandLine.arguments[valueIndex]
    }

    @MainActor
    private static func runXiaomiXHSExportSmoke(inputURL: URL) async throws -> [XiaomiXHSSmokeResult] {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw Video2LiveError.invalidVideo
        }

        let viewModel = AppViewModel()
        try await viewModel.importVideoAndWait(from: inputURL)
        let clipDuration = min(max(1.0, min(3.0, viewModel.duration)), min(5.0, viewModel.duration))
        viewModel.updateStartTime(0)
        viewModel.updateEndTime(clipDuration)

        log("APP_XIAOMI_XHS_SMOKE_STAGE videoFrame")
        viewModel.coverMode = .videoFrame
        try await viewModel.updateCoverTimeAndWait(0)
        try await viewModel.generateLivePhotoAndWait()
        let videoFrameResult = try await exportAndValidateXiaomiPackage(
            label: "videoFrame",
            viewModel: viewModel
        )

        log("APP_XIAOMI_XHS_SMOKE_STAGE uploadedCover")
        let coverURL = try writeSyntheticUploadedCover()
        viewModel.importCoverImage(from: coverURL)
        try require(viewModel.uploadedCover != nil, "上传封面未载入")
        if let uploadedCover = viewModel.uploadedCover {
            viewModel.updateCropSelection(
                CropSelection(centerX: 0.56, centerY: 0.47, width: 0.76),
                sourceImage: uploadedCover
            )
        }
        try await viewModel.generateLivePhotoAndWait()
        let uploadedResult = try await exportAndValidateXiaomiPackage(
            label: "uploadedCover",
            viewModel: viewModel
        )

        return [videoFrameResult, uploadedResult]
    }

    @MainActor
    private static func exportAndValidateXiaomiPackage(
        label: String,
        viewModel: AppViewModel
    ) async throws -> XiaomiXHSSmokeResult {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Video2Live", isDirectory: true)
            .appendingPathComponent("XiaomiXHSSmoke-\(label)-\(UUID().uuidString)", isDirectory: true)
        let exported = try await viewModel.exportXiaomiXiaohongshuPackageAndWait(outputDirectory: directory)
        guard let validation = viewModel.androidExportValidation else {
            throw Video2LiveError.exportFailed("\(label) 小米/小红书导出后没有校验结果")
        }
        try require(validation.isValid, "\(label) 小米/小红书导出包校验失败")
        try require(FileManager.default.fileExists(atPath: exported.motionPhotoURL.path), "\(label) motion photo 文件不存在")
        try require(FileManager.default.fileExists(atPath: exported.fallbackVideoURL.path), "\(label) fallback MP4 文件不存在")
        try require(FileManager.default.fileExists(atPath: exported.coverPhotoURL.path), "\(label) cover 文件不存在")
        try require(FileManager.default.fileExists(atPath: exported.manifestURL.path), "\(label) manifest 文件不存在")
        let motionSize = try exported.motionPhotoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let videoSize = try exported.fallbackVideoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try require(motionSize > videoSize, "\(label) motion photo 未包含追加视频数据")
        return XiaomiXHSSmokeResult(label: label, package: exported, validation: validation)
    }

    @MainActor
    private static func runPhotosSaveSmoke(inputURL: URL) async throws -> [SmokeSaveResult] {
        log("APP_PHOTOS_SMOKE_STAGE inputReady")
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw Video2LiveError.invalidVideo
        }

        let viewModel = AppViewModel()
        try await viewModel.importVideoAndWait(from: inputURL)
        guard let stagedURL = viewModel.videoURL else {
            throw Video2LiveError.invalidVideo
        }

        log("APP_PHOTOS_SMOKE_STAGE assetLoad")
        let asset = AVURLAsset(url: stagedURL)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        log("APP_PHOTOS_SMOKE_STAGE duration \(duration)")
        let size = try await VideoAssetService.videoDisplaySize(for: asset)
        log("APP_PHOTOS_SMOKE_STAGE size \(Int(size.width))x\(Int(size.height))")
        let clipDuration = min(max(1.0, min(3.0, duration)), min(5.0, duration))
        viewModel.updateStartTime(0)
        viewModel.updateEndTime(clipDuration)

        log("APP_PHOTOS_SMOKE_STAGE videoFrame")
        viewModel.coverMode = .videoFrame
        try await viewModel.updateCoverTimeAndWait(0)
        let videoFrameResult = try await generatePreviewSaveAndRecord(
            label: "videoFrame",
            viewModel: viewModel
        )
        try require(viewModel.validationRecords.count == 1, "视频选帧保存后验证记录历史数量不正确")

        log("APP_PHOTOS_SMOKE_STAGE uploadedCover")
        let coverURL = try writeSyntheticUploadedCover()
        viewModel.importCoverImage(from: coverURL)
        try require(viewModel.uploadedCover != nil, "上传封面未载入")
        try require(viewModel.coverMode == .uploadedImage, "上传封面后 coverMode 未切换")
        if let uploadedCover = viewModel.uploadedCover {
            viewModel.updateCropSelection(
                CropSelection(centerX: 0.56, centerY: 0.47, width: 0.76),
                sourceImage: uploadedCover
            )
        }
        let uploadedResult = try await generatePreviewSaveAndRecord(
            label: "uploadedCover",
            viewModel: viewModel
        )
        try require(viewModel.validationRecords.count == 2, "两种封面保存后验证记录历史没有保留两条记录")
        try require(viewModel.validationRecords[0].contains("Cover mode: 视频选帧"), "验证记录历史缺少视频选帧记录")
        try require(viewModel.validationRecords[1].contains("Cover mode: 上传图片"), "验证记录历史缺少上传图片记录")

        return [videoFrameResult, uploadedResult]
    }

    @MainActor
    private static func generatePreviewSaveAndRecord(
        label: String,
        viewModel: AppViewModel
    ) async throws -> SmokeSaveResult {
        try require(viewModel.canGenerate, "\(label) AppViewModel 当前状态无法生成 Live Photo")
        log("APP_PHOTOS_SMOKE_BUILD \(label)")
        try await viewModel.generateLivePhotoAndWait()
        guard let package = viewModel.generatedPackage else {
            throw Video2LiveError.exportFailed("\(label) 没有生成 Live Photo package")
        }
        guard let generatedMetadata = viewModel.generatedMetadataValidation else {
            throw Video2LiveError.exportFailed("\(label) UI 生成路径没有记录 metadata 校验结果")
        }
        let metadata = try await LivePhotoMetadataInspector.inspect(package: package)
        try require(generatedMetadata.videoCodec == metadata.videoCodec, "\(label) UI 记录 codec 和文件实际 codec 不一致")
        try require(generatedMetadata.isDurationCompatible, "\(label) UI 生成路径记录的 MOV 时长不是 1-5 秒")
        try require(abs(generatedMetadata.videoDurationSeconds - metadata.videoDurationSeconds) < 0.02, "\(label) UI 记录 MOV 时长和文件实际时长不一致")
        try require(metadata.isPaired, "\(label) Live Photo 元数据配对校验失败")
        try require(metadata.hasTimedMetadataTrack, "\(label) 缺少 timed metadata track")
        try require(metadata.isSupportedVideoCodec, "\(label) paired MOV 编码不是 H.264/HEVC")
        try require(metadata.isDurationCompatible, "\(label) paired MOV 时长不是 1-5 秒")

        log("APP_PHOTOS_SMOKE_PREVIEW \(label)")
        try await waitForViewModelPreview(viewModel, label: label)
        guard let livePhoto = viewModel.livePhoto else {
            throw Video2LiveError.exportFailed("\(label) PHLivePhotoView 预览资源未加载")
        }

        log("APP_PHOTOS_SMOKE_SAVE \(label)")
        let savedAsset = try await viewModel.saveGeneratedLivePhotoToPhotosAndWait()
        guard savedAsset.isLivePhoto else {
            throw Video2LiveError.photoLibrarySaveFailed("Photos 保存成功但未标记为 Live Photo")
        }
        guard savedAsset.canLoadLivePhoto else {
            throw Video2LiveError.photoLibrarySaveFailed("Photos 保存成功但无法通过 PhotoKit 重新加载 Live Photo")
        }
        guard savedAsset.hasLivePhotoResourcePair else {
            throw Video2LiveError.photoLibrarySaveFailed("Photos 保存成功但资源类型缺少 photo 或 pairedVideo")
        }
        guard savedAsset.isInAlbum else {
            throw Video2LiveError.photoLibrarySaveFailed("Photos 保存成功但未加入 \(savedAsset.albumTitle) 相册")
        }
        guard !savedAsset.hasCloudIdentifier
            || savedAsset.cloudIdentifierRoundTripMatches
            || savedAsset.cloudIdentifierRoundTripLocalIdentifier == nil else {
            throw Video2LiveError.photoLibrarySaveFailed("iCloud cloud identifier 未能回查到同一个 Photos 资产")
        }

        guard let validationRecord = viewModel.deviceValidationRecord() else {
            throw Video2LiveError.exportFailed("\(label) 保存后无法生成设备/社交验证记录")
        }
        let shortPhotosID = AppViewModel.shortPhotosIdentifier(from: savedAsset.localIdentifier)
        try require(validationRecord.contains("Photos ID: \(shortPhotosID)"), "\(label) 验证记录缺少 Photos ID")
        try require(validationRecord.contains("Asset identifier: \(package.assetIdentifier)"), "\(label) 验证记录缺少 Live Photo asset identifier")
        try require(validationRecord.contains("MOV codec: \(metadata.videoCodec ?? "unknown")"), "\(label) 验证记录缺少 MOV codec")
        try require(validationRecord.contains("MOV duration:"), "\(label) 验证记录缺少 MOV duration")
        try require(validationRecord.contains("macOS Photos Live Photo: pass"), "\(label) 验证记录没有标记 macOS Photos 通过")
        try require(validationRecord.contains("macOS Photos resources: pass"), "\(label) 验证记录没有标记 Photos 资源对通过")
        try require(validationRecord.contains("macOS Photos album: \(savedAsset.albumTitle) (pass)"), "\(label) 验证记录缺少 Photos 相册通过状态")
        try require(validationRecord.contains("iCloud cloud identifier:"), "\(label) 验证记录缺少 iCloud cloud identifier 字段")
        try require(validationRecord.contains("iCloud round trip:"), "\(label) 验证记录缺少 iCloud round trip 字段")
        try require(validationRecord.contains("iPhone lookup album: Photos > Albums > \(savedAsset.albumTitle)"), "\(label) 验证记录缺少 iPhone 相册查找路径")
        try require(validationRecord.contains("iPhone Photos sync: pass/fail"), "\(label) 验证记录缺少 iPhone 同步字段")
        try require(validationRecord.contains("WeChat Moments publish: pass/fail"), "\(label) 验证记录缺少微信朋友圈发布字段")
        try require(validationRecord.contains("Xiaohongshu publish/draft: pass/fail"), "\(label) 验证记录缺少小红书发布字段")

        log("APP_PHOTOS_SMOKE_VERIFIED \(label) \(savedAsset.localIdentifier)")
        return SmokeSaveResult(
            label: label,
            package: package,
            livePhoto: livePhoto,
            metadata: metadata,
            savedAsset: savedAsset,
            validationRecord: validationRecord,
            validationRecordHistoryCount: viewModel.validationRecords.count
        )
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

    private static func photoPixelSize(for package: LivePhotoPackage) throws -> CGSize {
        let image = NSImage(contentsOf: package.photoURL) ?? package.coverImage
        let cgImage = try ImageProcessing.cgImage(from: image)
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private static func writeSyntheticUploadedCover() throws -> URL {
        let image = makeSyntheticUploadedCover()
        let cgImage = try ImageProcessing.cgImage(from: image)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Video2Live", isDirectory: true)
            .appendingPathComponent("WorkflowSmoke", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("uploaded-cover-\(UUID().uuidString).jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw Video2LiveError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Video2LiveError.imageEncodingFailed
        }
        return url
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

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 108, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1)
        ]
        "Uploaded Cover".draw(in: badgeRect.insetBy(dx: 72, dy: 102), withAttributes: attributes)

        image.unlockFocus()
        return image
    }

    private static func log(_ message: String) {
        print(message)
        if let logURL = argument(after: "--smoke-log") {
            append(message: message, to: URL(fileURLWithPath: logURL))
        }
        fflush(stdout)
    }

    private static func resetLogIfNeeded() {
        guard let logURL = argument(after: "--smoke-log") else { return }
        let url = URL(fileURLWithPath: logURL)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    private static func append(message: String, to url: URL) {
        let line = "\(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func logWorkflowResult(_ result: WorkflowSmokeResult) {
        log("\(result.label).assetIdentifier=\(result.package.assetIdentifier)")
        log("\(result.label).photo=\(result.package.photoURL.path)")
        log("\(result.label).video=\(result.package.videoURL.path)")
        log("\(result.label).photoSize=\(Int(result.photoSize.width))x\(Int(result.photoSize.height))")
        log("\(result.label).videoSize=\(Int(result.videoSize.width))x\(Int(result.videoSize.height))")
        log("\(result.label).livePhotoSize=\(Int(result.livePhoto.size.width))x\(Int(result.livePhoto.size.height))")
        log("\(result.label).photoIdentifierMatches=\(result.metadata.photoIdentifierMatches)")
        log("\(result.label).videoIdentifierMatches=\(result.metadata.videoIdentifierMatches)")
        log("\(result.label).videoCodec=\(result.metadata.videoCodec ?? "unknown")")
        log("\(result.label).isSupportedVideoCodec=\(result.metadata.isSupportedVideoCodec)")
        log("\(result.label).videoDurationSeconds=\(String(format: "%.3f", result.metadata.videoDurationSeconds))")
        log("\(result.label).isDurationCompatible=\(result.metadata.isDurationCompatible)")
        log("\(result.label).hasTimedMetadataTrack=\(result.metadata.hasTimedMetadataTrack)")
        log("\(result.label).previewPlaybackRequest=\(result.previewPlaybackRequest)")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw Video2LiveError.exportFailed(message)
        }
    }
}

private struct WorkflowSmokeResult {
    let label: String
    let package: LivePhotoPackage
    let livePhoto: PHLivePhoto
    let metadata: LivePhotoMetadataValidation
    let photoSize: CGSize
    let videoSize: CGSize
    let previewPlaybackRequest: Int
}

private struct SmokeSaveResult {
    let label: String
    let package: LivePhotoPackage
    let livePhoto: PHLivePhoto
    let metadata: LivePhotoMetadataValidation
    let savedAsset: SavedLivePhotoAsset
    let validationRecord: String
    let validationRecordHistoryCount: Int
}

private struct XiaomiXHSSmokeResult {
    let label: String
    let package: AndroidMotionPhotoPackage
    let validation: AndroidMotionPhotoValidation
}

private final class BoolContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<Bool, Never>, returning value: Bool) {
        let shouldResume: Bool
        lock.lock()
        if didResume {
            shouldResume = false
        } else {
            didResume = true
            shouldResume = true
        }
        lock.unlock()

        if shouldResume {
            continuation.resume(returning: value)
        }
    }
}
