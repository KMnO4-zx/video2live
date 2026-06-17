import AppKit
import AVFoundation
import Photos
import SwiftUI
import UniformTypeIdentifiers
import Video2LiveCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var videoURL: URL?
    @Published var player = AVPlayer()
    @Published var duration: Double = 0
    @Published var videoSize: CGSize = CGSize(width: 1080, height: 1920)
    @Published var startTime: Double = 0
    @Published var endTime: Double = 3
    @Published var coverTime: Double = 0
    @Published var coverMode: CoverMode = .videoFrame
    @Published var videoFrameCover: NSImage?
    @Published var uploadedCover: NSImage?
    @Published var cropSelection = CropSelection()
    @Published var generatedPackage: LivePhotoPackage?
    @Published var generatedMetadataValidation: LivePhotoMetadataValidation?
    @Published var savedAsset: SavedLivePhotoAsset?
    @Published var validationRecords: [String] = []
    @Published var androidExportPackage: AndroidMotionPhotoPackage?
    @Published var androidExportValidation: AndroidMotionPhotoValidation?
    @Published var livePhoto: PHLivePhoto?
    @Published var previewPlaybackRequest = 0
    @Published var isBusy = false
    @Published var statusText = "导入视频开始制作 Live Photo"
    @Published var errorText: String?

    private let minClipLength = 1.0
    private let maxClipLength = 5.0
    private let maxExportClipLength = 4.95
    private var playbackTimeObserver: Any?

    init() {
        installPlaybackBoundaryObserver()
    }

    var selectedDuration: Double {
        max(0, endTime - startTime)
    }

    var isSelectedDurationCompatible: Bool {
        selectedDuration >= minClipLength && selectedDuration <= maxClipLength
    }

    var canGenerate: Bool {
        videoURL != nil && isSelectedDurationCompatible && (coverMode == .videoFrame || uploadedCover != nil)
    }

    func openVideoFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "导入视频"
        panel.message = "选择一个 MP4、MOV 或其他系统可读取的视频文件。"
        panel.prompt = "导入"
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        statusText = "请选择要导入的视频文件。"
        errorText = nil

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.importVideo(from: url)
            }
        }
    }

    func openCoverImagePicker() {
        let panel = NSOpenPanel()
        panel.title = "上传封面"
        panel.message = "选择一张图片作为 Live 图封面。"
        panel.prompt = "上传"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        statusText = "请选择封面图片。"
        errorText = nil

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.importCoverImage(from: url)
            }
        }
    }

    func importVideo(from url: URL) {
        Task {
            await setBusy(true, "正在导入视频...")
            do {
                try await importVideoAndWait(from: url)
            } catch {
                errorText = error.localizedDescription
                statusText = "导入失败"
            }
            await setBusy(false)
        }
    }

    func importVideoAndWait(from url: URL) async throws {
        let localURL = try FileStaging.copyIntoWorkspace(url)
        let asset = AVURLAsset(url: localURL)
        let loadedDuration = try await asset.load(.duration)
        let size = try await VideoAssetService.videoDisplaySize(for: asset)
        let seconds = max(CMTimeGetSeconds(loadedDuration), 0)

        videoURL = localURL
        duration = seconds
        videoSize = size
        startTime = 0
        endTime = min(max(minClipLength, min(maxClipLength, seconds)), seconds)
        coverTime = 0
        coverMode = .videoFrame
        uploadedCover = nil
        cropSelection = CropSelection()
        generatedPackage = nil
        generatedMetadataValidation = nil
        savedAsset = nil
        validationRecords = []
        androidExportPackage = nil
        androidExportValidation = nil
        livePhoto = nil
        player.replaceCurrentItem(with: AVPlayerItem(url: localURL))
        try await refreshVideoFrameCover()
        statusText = "已导入：\(localURL.lastPathComponent)"
        errorText = nil
    }

    func rejectDroppedVideo(_ url: URL?) {
        statusText = "导入失败"
        if let url {
            errorText = "\(url.lastPathComponent) 不是支持的视频文件，请拖入 MP4 / MOV 等常见视频。"
        } else {
            errorText = "请拖入 MP4 / MOV 等常见视频文件。"
        }
    }

    func importCoverImage(from url: URL) {
        do {
            let localURL = try FileStaging.copyIntoWorkspace(url)
            guard let image = NSImage(contentsOf: localURL) else {
                throw Video2LiveError.missingCoverImage
            }
            let sourceSize = sourcePixelSize(for: image)
            let targetAspect = max(0.01, videoSize.width / max(videoSize.height, 1))
            uploadedCover = image
            coverMode = .uploadedImage
            cropSelection = CropSelection().clamped(sourceSize: sourceSize, targetAspect: targetAspect)
            generatedPackage = nil
            generatedMetadataValidation = nil
            savedAsset = nil
            androidExportPackage = nil
            androidExportValidation = nil
            livePhoto = nil
            statusText = "已载入封面：\(localURL.lastPathComponent)"
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    func updateStartTime(_ value: Double) {
        guard duration > 0 else { return }
        let maxStart = max(0, duration - minClipLength)
        startTime = min(max(0, value), maxStart)
        if endTime < startTime + minClipLength {
            endTime = min(duration, startTime + minClipLength)
        }
        if endTime > startTime + maxClipLength {
            endTime = min(duration, startTime + maxClipLength)
        }
        coverTime = min(max(coverTime, startTime), endTime)
        generatedPackage = nil
        generatedMetadataValidation = nil
        savedAsset = nil
        androidExportPackage = nil
        androidExportValidation = nil
        livePhoto = nil
        keepPlayerInsideSelectedRange()
    }

    func updateEndTime(_ value: Double) {
        guard duration > 0 else { return }
        let minEnd = min(duration, startTime + minClipLength)
        let maxEnd = min(duration, startTime + maxClipLength)
        endTime = min(max(value, minEnd), maxEnd)
        coverTime = min(max(coverTime, startTime), endTime)
        generatedPackage = nil
        generatedMetadataValidation = nil
        savedAsset = nil
        androidExportPackage = nil
        androidExportValidation = nil
        livePhoto = nil
        keepPlayerInsideSelectedRange()
    }

    func updateCoverTime(_ value: Double) {
        Task {
            try? await updateCoverTimeAndWait(value)
        }
    }

    func updateCoverTimeAndWait(_ value: Double) async throws {
        coverTime = min(max(value, startTime), endTime)
        generatedPackage = nil
        generatedMetadataValidation = nil
        savedAsset = nil
        androidExportPackage = nil
        androidExportValidation = nil
        livePhoto = nil
        try await refreshVideoFrameCover()
    }

    func playPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            playSelectedRangeFromStart()
        }
    }

    func seekToStart() {
        seekPlayer(to: startTime)
    }

    var currentPlaybackTime: Double {
        CMTimeGetSeconds(player.currentTime())
    }

    func enforcePlaybackBoundaryForCurrentTime() {
        pauseIfPlaybackReachedSelectedEnd(player.currentTime())
    }

    func generateLivePhoto() {
        Task {
            await setBusy(true, "正在生成 Live Photo 资源...")
            do {
                try await generateLivePhotoAndWait()
            } catch {
                errorText = error.localizedDescription
                statusText = "生成失败"
            }
            await setBusy(false)
        }
    }

    func generateLivePhotoAndWait() async throws {
        guard isSelectedDurationCompatible else { throw Video2LiveError.invalidClipDuration }
        guard let videoURL else { throw Video2LiveError.invalidVideo }
        let cover = try await resolvedCoverImage()
        let exportEndTime = startTime + min(selectedDuration, maxExportClipLength)
        let package = try await LivePhotoBuilder.build(
            sourceVideoURL: videoURL,
            startTime: startTime,
            endTime: exportEndTime,
            coverImage: cover,
            targetSize: videoSize
        )
        let validation = try await LivePhotoMetadataInspector.inspect(package: package)
        guard validation.isPaired else {
            throw Video2LiveError.exportFailed("Live Photo 静态图和 MOV 配对标识不一致")
        }
        guard validation.hasTimedMetadataTrack else {
            throw Video2LiveError.exportFailed("Live Photo MOV 缺少 still-image-time metadata")
        }
        guard validation.isSupportedVideoCodec else {
            throw Video2LiveError.exportFailed("Live Photo MOV 编码不是 H.264/HEVC")
        }
        guard validation.isDurationCompatible else {
            throw Video2LiveError.exportFailed("Live Photo MOV 时长不是 1-5 秒")
        }
        generatedPackage = package
        generatedMetadataValidation = validation
        savedAsset = nil
        androidExportPackage = nil
        androidExportValidation = nil
        requestPreview(for: package)
        statusText = "Live Photo 已生成，配对和编码已验证。"
        errorText = nil
    }

    func saveGeneratedLivePhotoToPhotos() {
        Task {
            await setBusy(true, "正在保存到 Photos...")
            do {
                _ = try await saveGeneratedLivePhotoToPhotosAndWait()
            } catch {
                errorText = error.localizedDescription
                statusText = "保存失败"
            }
            await setBusy(false)
        }
    }

    @discardableResult
    func saveGeneratedLivePhotoToPhotosAndWait() async throws -> SavedLivePhotoAsset {
        guard let generatedPackage else { throw Video2LiveError.exportFailed("没有可保存的 Live Photo 资源") }
        let photoURL = generatedPackage.photoURL
        let videoURL = generatedPackage.videoURL
        let savedAsset = try await PhotoLibraryWriter.save(photoURL: photoURL, videoURL: videoURL)
        self.savedAsset = savedAsset
        appendDeviceValidationRecordIfAvailable()
        statusText = savedAsset.isLivePhoto && savedAsset.canLoadLivePhoto && savedAsset.isInAlbum && savedAsset.hasLivePhotoResourcePair && savedAsset.cloudIdentifierRoundTripMatches
            ? "已保存到 macOS Photos，iCloud 标识可回查到同一资产。"
            : savedAsset.isLivePhoto && savedAsset.canLoadLivePhoto && savedAsset.isInAlbum && savedAsset.hasLivePhotoResourcePair && savedAsset.hasCloudIdentifier
            ? "已保存到 macOS Photos，已取得 iCloud 可追踪标识。"
            : savedAsset.isLivePhoto && savedAsset.canLoadLivePhoto && savedAsset.isInAlbum && savedAsset.hasLivePhotoResourcePair
            ? "已保存到 macOS Photos，并加入 \(savedAsset.albumTitle) 相册。"
            : savedAsset.isLivePhoto && savedAsset.canLoadLivePhoto && savedAsset.hasLivePhotoResourcePair
            ? "已保存到 macOS Photos，资源对和 Live Photo 预览已验证。"
            : savedAsset.isLivePhoto && savedAsset.canLoadLivePhoto
            ? "已保存到 macOS Photos，并可作为 Live Photo 重新加载。"
            : savedAsset.isLivePhoto
            ? "已保存到 macOS Photos，并识别为 Live Photo。"
            : "已保存到 macOS Photos，但需要在 Photos 中确认 Live Photo 标记。"
        errorText = nil
        return savedAsset
    }

    func exportXiaomiXiaohongshuPackage() {
        guard generatedPackage != nil else {
            errorText = "请先生成 Live Photo 资源后再导出候选动态图 JPG"
            return
        }

        let panel = NSOpenPanel()
        panel.title = "选择导出位置"
        panel.message = "将在你选择的位置创建一个 Video2Live-Xiaomi-XHS 导出文件夹。"
        panel.prompt = "导出到这里"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultXiaomiXiaohongshuExportParentDirectory()
        statusText = "请选择候选动态图 JPG 的导出位置。"
        errorText = nil

        panel.begin { [weak self] response in
            guard response == .OK, let parentDirectory = panel.url else { return }
            Task { @MainActor in
                await self?.exportXiaomiXiaohongshuPackage(toParentDirectory: parentDirectory)
            }
        }
    }

    private func exportXiaomiXiaohongshuPackage(toParentDirectory parentDirectory: URL) async {
        await setBusy(true, "正在导出候选动态图 JPG...")
        do {
            let outputDirectory = timestampedXiaomiXiaohongshuExportDirectory(in: parentDirectory)
            _ = try await exportXiaomiXiaohongshuPackageAndWait(outputDirectory: outputDirectory)
            openXiaomiXiaohongshuExportFolder()
        } catch {
            errorText = error.localizedDescription
            statusText = "候选动态图 JPG 导出失败"
        }
        await setBusy(false)
    }

    func exportXiaomiXiaohongshuPackageToDefaultLocation() {
        Task {
            await exportXiaomiXiaohongshuPackage(toParentDirectory: defaultXiaomiXiaohongshuExportParentDirectory())
        }
    }

    @discardableResult
    func exportXiaomiXiaohongshuPackageAndWait(outputDirectory: URL? = nil) async throws -> AndroidMotionPhotoPackage {
        guard let generatedPackage else {
            throw Video2LiveError.exportFailed("请先生成 Live Photo 资源后再导出候选动态图 JPG")
        }
        let directory = outputDirectory ?? timestampedXiaomiXiaohongshuExportDirectory(
            in: defaultXiaomiXiaohongshuExportParentDirectory()
        )
        let exported = try await AndroidMotionPhotoExporter.export(
            package: generatedPackage,
            outputDirectory: directory
        )
        let validation = try await AndroidMotionPhotoExporter.validate(package: exported)
        guard validation.isValid else {
            throw Video2LiveError.exportFailed("小米/小红书导出包校验失败")
        }
        androidExportPackage = exported
        androidExportValidation = validation
        statusText = "已导出候选动态图 JPG：\(exported.motionPhotoURL.lastPathComponent)"
        errorText = nil
        return exported
    }

    func openXiaomiXiaohongshuExportFolder() {
        guard let uploadURL = androidExportPackage?.motionPhotoURL else {
            errorText = "还没有可显示的小红书上传 JPG"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([uploadURL])
    }

    private func refreshVideoFrameCover() async throws {
        guard let videoURL else { return }
        let image = try await VideoAssetService.frameImage(from: videoURL, at: coverTime)
        videoFrameCover = image
    }

    private func resolvedCoverImage() async throws -> NSImage {
        if coverMode == .videoFrame {
            guard let videoURL else { throw Video2LiveError.invalidVideo }
            let frame = try await VideoAssetService.frameImage(from: videoURL, at: coverTime)
            return try ImageProcessing.renderCover(from: frame, targetSize: videoSize, scale: 1, offset: .zero)
        }

        guard let uploadedCover else { throw Video2LiveError.missingCoverImage }
        return try ImageProcessing.renderCover(
            from: uploadedCover,
            targetSize: videoSize,
            cropSelection: cropSelection
        )
    }

    func updateCropSelection(_ selection: CropSelection, sourceImage: NSImage) {
        let sourceSize = sourcePixelSize(for: sourceImage)
        let targetAspect = max(0.01, videoSize.width / max(videoSize.height, 1))
        cropSelection = selection.clamped(sourceSize: sourceSize, targetAspect: targetAspect)
        generatedPackage = nil
        generatedMetadataValidation = nil
        savedAsset = nil
        livePhoto = nil
    }

    func openPhotosApp() {
        let candidates = [
            URL(fileURLWithPath: "/System/Applications/Photos.app"),
            URL(fileURLWithPath: "/Applications/Photos.app")
        ]
        guard let photosURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            errorText = "未找到 Photos.app"
            return
        }
        NSWorkspace.shared.openApplication(at: photosURL, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error {
                Task { @MainActor in
                    self?.errorText = error.localizedDescription
                }
            }
        }
    }

    func openPhotosPrivacySettings() {
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")
        if let settingsURL, NSWorkspace.shared.open(settingsURL) {
            statusText = "请在系统设置中允许 Video2Live 访问照片，然后重新保存。"
            errorText = nil
            return
        }

        let candidates = [
            URL(fileURLWithPath: "/System/Applications/System Settings.app"),
            URL(fileURLWithPath: "/Applications/System Settings.app"),
            URL(fileURLWithPath: "/System/Applications/System Preferences.app"),
            URL(fileURLWithPath: "/Applications/System Preferences.app")
        ]
        guard let settingsAppURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            errorText = "未找到系统设置，请手动打开 隐私与安全性 > 照片。"
            return
        }
        NSWorkspace.shared.openApplication(at: settingsAppURL, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error {
                Task { @MainActor in
                    self?.errorText = error.localizedDescription
                }
            } else {
                Task { @MainActor in
                    self?.statusText = "请在系统设置中允许 Video2Live 访问照片，然后重新保存。"
                    self?.errorText = nil
                }
            }
        }
    }

    func copyPhotosIdentifierToClipboard() {
        guard let localIdentifier = savedAsset?.localIdentifier else {
            errorText = "还没有可复制的 Photos ID"
            return
        }
        let identifier = Self.shortPhotosIdentifier(from: localIdentifier)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(identifier, forType: .string)
        statusText = "已复制 Photos ID：\(identifier)"
        errorText = nil
    }

    func copyDeviceValidationRecordToClipboard() {
        guard let record = deviceValidationRecord() else {
            errorText = "保存并验证 Live Photo 后才能复制验证记录"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record, forType: .string)
        statusText = "已复制 iPhone/社交验证记录"
        errorText = nil
    }

    func copyAllDeviceValidationRecordsToClipboard() {
        guard !validationRecords.isEmpty else {
            errorText = "还没有可复制的验证记录"
            return
        }
        let joinedRecords = validationRecords.enumerated()
            .map { index, record in
                """
                # Video2Live validation record \(index + 1)
                \(record)
                """
            }
            .joined(separator: "\n\n---\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(joinedRecords, forType: .string)
        statusText = "已复制 \(validationRecords.count) 条验证记录"
        errorText = nil
    }

    func deviceValidationRecord() -> String? {
        guard let savedAsset, let generatedPackage, let generatedMetadataValidation else {
            return nil
        }
        let photosID = Self.shortPhotosIdentifier(from: savedAsset.localIdentifier)
        let livePhotoStatus = savedAsset.isLivePhoto ? "pass" : "pending"
        let albumStatus = savedAsset.isInAlbum ? "pass" : "pending"
        let codec = generatedMetadataValidation.videoCodec ?? "unknown"
        let pairingStatus = generatedMetadataValidation.isPaired && generatedMetadataValidation.hasTimedMetadataTrack ? "pass" : "fail"
        let codecStatus = generatedMetadataValidation.isSupportedVideoCodec ? "pass" : "fail"
        let movieDurationStatus = generatedMetadataValidation.isDurationCompatible ? "pass" : "fail"
        let photosResourceStatus = savedAsset.hasLivePhotoResourcePair ? "pass" : "fail"
        let photosResourceTypes = savedAsset.resourceTypes.joined(separator: ",")
        let cloudIdentifierStatus = savedAsset.hasCloudIdentifier ? "present" : "missing"
        let cloudIdentifierValue = savedAsset.cloudIdentifier ?? savedAsset.cloudIdentifierError ?? "unavailable"
        let cloudRoundTripStatus = savedAsset.cloudIdentifierRoundTripMatches ? "pass" : "pending"
        let cloudRoundTripValue = savedAsset.cloudIdentifierRoundTripLocalIdentifier
            ?? savedAsset.cloudIdentifierRoundTripError
            ?? "unavailable"

        return """
        Video2Live validation record
        Photos ID: \(photosID)
        Asset identifier: \(generatedPackage.assetIdentifier)
        Cover mode: \(coverMode.rawValue)
        Clip: \(String(format: "%.2f", startTime))s-\(String(format: "%.2f", endTime))s (\(String(format: "%.2f", selectedDuration))s)
        Size: \(Int(videoSize.width))x\(Int(videoSize.height))
        MOV codec: \(codec) (\(codecStatus))
        MOV duration: \(String(format: "%.2f", generatedMetadataValidation.videoDurationSeconds))s (\(movieDurationStatus))
        Pairing metadata: \(pairingStatus)
        macOS Photos Live Photo: \(livePhotoStatus)
        macOS Photos resources: \(photosResourceStatus) (\(photosResourceTypes))
        macOS Photos album: \(savedAsset.albumTitle) (\(albumStatus))
        iCloud cloud identifier: \(cloudIdentifierStatus) (\(cloudIdentifierValue))
        iCloud round trip: \(cloudRoundTripStatus) (\(cloudRoundTripValue))
        iPhone lookup album: Photos > Albums > \(savedAsset.albumTitle)
        iPhone Photos sync: pass/fail
        iPhone Live Photo playback: pass/fail
        WeChat Moments selection: pass/fail
        WeChat Moments publish: pass/fail
        Xiaohongshu selection: pass/fail
        Xiaohongshu publish/draft: pass/fail
        Notes:
        """
    }

    private func appendDeviceValidationRecordIfAvailable() {
        guard let record = deviceValidationRecord() else { return }
        validationRecords.append(record)
    }

    private func defaultXiaomiXiaohongshuExportParentDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private func timestampedXiaomiXiaohongshuExportDirectory(in parentDirectory: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        return parentDirectory.appendingPathComponent("Video2Live-Xiaomi-XHS-\(stamp)", isDirectory: true)
    }

    static func shortPhotosIdentifier(from localIdentifier: String) -> String {
        String(localIdentifier.split(separator: "/").first ?? Substring(localIdentifier))
    }

    private func sourcePixelSize(for image: NSImage) -> CGSize {
        var rect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return image.size
    }

    private func requestPreview(for package: LivePhotoPackage) {
        livePhoto = nil
        PHLivePhoto.request(
            withResourceFileURLs: [package.photoURL, package.videoURL],
            placeholderImage: package.coverImage,
            targetSize: .zero,
            contentMode: .aspectFit
        ) { [weak self] livePhoto, info in
            Task { @MainActor in
                if let error = info[PHLivePhotoInfoErrorKey] as? Error {
                    self?.errorText = error.localizedDescription
                    return
                }
                self?.livePhoto = livePhoto
                self?.previewPlaybackRequest += 1
            }
        }
    }

    func replayLivePhotoPreview() {
        guard livePhoto != nil else { return }
        previewPlaybackRequest += 1
    }

    private func installPlaybackBoundaryObserver() {
        playbackTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.pauseIfPlaybackReachedSelectedEnd(time)
            }
        }
    }

    private func pauseIfPlaybackReachedSelectedEnd(_ time: CMTime) {
        guard player.timeControlStatus == .playing else { return }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, selectedDuration > 0, seconds >= endTime else { return }
        player.pause()
        seekPlayer(to: endTime)
    }

    private func keepPlayerInsideSelectedRange() {
        let seconds = currentPlaybackTime
        guard seconds.isFinite else { return }
        if seconds < startTime || seconds > endTime {
            seekPlayer(to: startTime)
        }
    }

    private func playSelectedRangeFromStart() {
        let start = min(max(startTime, 0), max(duration, 0))
        player.seek(
            to: CMTime(seconds: start, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor in
                self?.player.play()
            }
        }
    }

    private func seekPlayer(to seconds: Double) {
        let clamped = min(max(seconds, 0), max(duration, 0))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func setBusy(_ value: Bool, _ status: String? = nil) async {
        isBusy = value
        if let status {
            statusText = status
        }
    }
}
