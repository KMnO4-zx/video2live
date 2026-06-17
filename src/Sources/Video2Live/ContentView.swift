import AppKit
import Photos
import SwiftUI
import UniformTypeIdentifiers
import Video2LiveCore

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var dropTargeted = false
    @State private var hasAppeared = false

    var body: some View {
        ZStack(alignment: .top) {
            LiquidGlassBackground()

            VStack(spacing: 14) {
                ToolbarView()

                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 14) {
                        VideoWorkspaceView(dropTargeted: $dropTargeted)
                            .frame(minWidth: 620, maxWidth: .infinity, alignment: .top)

                        ControlsView()
                            .frame(width: 390)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                StatusBarView()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.top, 44)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.975)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: hasAppeared)

            if viewModel.isBusy {
                BusyOverlay(text: viewModel.statusText)
            }
        }
        .liquidGlassContainer(spacing: 14)
        .onAppear {
            hasAppeared = true
        }
    }
}

private struct ToolbarView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "livephoto")
                    .font(.system(size: 22, weight: .semibold))
                Text("Video2Live")
                    .font(.system(size: 18, weight: .semibold))
            }

            Spacer()

            Button {
                viewModel.openVideoFilePicker()
            } label: {
                Label("导入视频", systemImage: "square.and.arrow.down")
            }
            .video2LiveGlassButtonStyle()

            Button {
                viewModel.openCoverImagePicker()
            } label: {
                Label("上传封面", systemImage: "photo")
            }
            .video2LiveGlassButtonStyle()
            .disabled(viewModel.videoURL == nil)

            Button {
                viewModel.generateLivePhoto()
            } label: {
                Label("生成", systemImage: "wand.and.sparkles")
            }
            .video2LiveGlassButtonStyle(prominent: true)
            .disabled(!viewModel.canGenerate || viewModel.isBusy)

            Button {
                viewModel.saveGeneratedLivePhotoToPhotos()
            } label: {
                Label("保存到 Photos", systemImage: "icloud.and.arrow.up")
            }
            .video2LiveGlassButtonStyle(prominent: true)
            .disabled(viewModel.generatedPackage == nil || viewModel.isBusy)
        }
        .frame(minHeight: 48)
        .liquidGlass(cornerRadius: 24, padding: 10)
    }
}

private struct VideoWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Binding var dropTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.black.opacity(0.74))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(dropTargeted ? .cyan.opacity(0.85) : .white.opacity(0.15), lineWidth: dropTargeted ? 2 : 1)
                    }

                if viewModel.videoURL == nil {
                    VStack(spacing: 14) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 48, weight: .light))
                        Text("导入一个视频开始制作")
                            .font(.system(size: 22, weight: .semibold))
                        Text("支持拖入 MP4 / MOV，也可以选择本地文件。建议片段控制在 1-5 秒。")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.70))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                        Button {
                            viewModel.openVideoFilePicker()
                        } label: {
                            Label("选择视频", systemImage: "square.and.arrow.down")
                        }
                        .video2LiveGlassButtonStyle(prominent: true)
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                } else {
                    PlayerView(player: viewModel.player)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
                handleVideoDrop(providers)
            }

            if viewModel.videoURL != nil {
                TimelineView()
            }

            LivePreviewPanel()
        }
        .liquidGlass()
    }

    private func handleVideoDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }
            guard let url, isSupportedDroppedVideoURL(url) else {
                Task { @MainActor in
                    viewModel.rejectDroppedVideo(url)
                }
                return
            }
            Task { @MainActor in
                viewModel.importVideo(from: url)
            }
        }
        return true
    }
}

private func isSupportedDroppedVideoURL(_ url: URL) -> Bool {
    guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else {
        return false
    }
    return type.conforms(to: .movie)
        || type.conforms(to: .mpeg4Movie)
        || type.conforms(to: .quickTimeMovie)
}

private struct TimelineView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("片段裁剪")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(format(viewModel.selectedDuration)) / 建议 1-5 秒")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(viewModel.isSelectedDurationCompatible ? .green : .orange)
            }

            RangeTimelineSlider(
                duration: viewModel.duration,
                startTime: viewModel.startTime,
                endTime: viewModel.endTime,
                onStartChanged: viewModel.updateStartTime,
                onEndChanged: viewModel.updateEndTime
            )

            HStack {
                Label("起点", systemImage: "arrow.left.to.line.compact")
                    .frame(width: 72, alignment: .leading)
                Text(format(viewModel.startTime))
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
                Spacer()
                Label("终点", systemImage: "arrow.right.to.line.compact")
                    .frame(width: 72, alignment: .leading)
                Text(format(viewModel.endTime))
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.seekToStart()
                } label: {
                    Label("定位", systemImage: "backward.end")
                }
                .video2LiveGlassButtonStyle()

                Button {
                    viewModel.playPause()
                } label: {
                    Label("播放/暂停", systemImage: "playpause")
                }
                .video2LiveGlassButtonStyle()
            }
        }
        .padding(2)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2fs", value)
    }
}

private struct RangeTimelineSlider: View {
    @Environment(\.colorScheme) private var colorScheme
    let duration: Double
    let startTime: Double
    let endTime: Double
    let onStartChanged: (Double) -> Void
    let onEndChanged: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let safeDuration = max(duration, 0.01)
            let startX = CGFloat(startTime / safeDuration) * width
            let endX = CGFloat(endTime / safeDuration) * width
            let selectedWidth = max(4, endX - startX)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.black.opacity(colorScheme == .dark ? 0.28 : 0.12))
                    .overlay {
                        TimelineTicks()
                            .padding(.horizontal, 8)
                    }
                    .frame(height: 16)
                    .position(x: width / 2, y: 26)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(0.82),
                                Color.green.opacity(0.68)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: selectedWidth, height: 16)
                    .position(x: startX + selectedWidth / 2, y: 26)
                    .shadow(color: .cyan.opacity(0.24), radius: 10, x: 0, y: 4)

                timelineHandle(label: "S")
                    .position(x: startX, y: 26)
                    .highPriorityGesture(handleDrag(width: width, safeDuration: safeDuration, action: onStartChanged))

                timelineHandle(label: "E")
                    .position(x: endX, y: 26)
                    .highPriorityGesture(handleDrag(width: width, safeDuration: safeDuration, action: onEndChanged))
            }
            .coordinateSpace(name: "rangeTimeline")
            .contentShape(Rectangle())
        }
        .frame(height: 52)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("片段时间轴")
        .accessibilityValue(String(format: "%.2f 秒到 %.2f 秒", startTime, endTime))
    }

    private func handleDrag(width: CGFloat, safeDuration: Double, action: @escaping (Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("rangeTimeline"))
            .onChanged { value in
                let clampedX = min(max(value.location.x, 0), width)
                action(Double(clampedX / width) * safeDuration)
            }
    }

    private func timelineHandle(label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: 28, height: 36)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.48 : 0.72), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
            }
    }
}

private struct TimelineTicks: View {
    var body: some View {
        GeometryReader { geometry in
            let count = 9
            ForEach(0..<count, id: \.self) { index in
                let x = CGFloat(index) / CGFloat(count - 1) * geometry.size.width
                Capsule(style: .continuous)
                    .fill(.white.opacity(index == 0 || index == count - 1 ? 0.4 : 0.22))
                    .frame(width: 1, height: index == 0 || index == count - 1 ? 10 : 7)
                    .position(x: x, y: geometry.size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ControlsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("封面")
                    .font(.system(size: 15, weight: .semibold))

                Picker("封面来源", selection: $viewModel.coverMode) {
                    ForEach(CoverMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.coverMode == .videoFrame {
                    VideoFrameCoverPicker()
                } else {
                    UploadedCoverPicker()
                }
            }
            .liquidGlass(cornerRadius: 22)

            VStack(alignment: .leading, spacing: 10) {
                Text("输出")
                    .font(.system(size: 15, weight: .semibold))

                OutputMetric(title: "视频尺寸", value: "\(Int(viewModel.videoSize.width)) x \(Int(viewModel.videoSize.height))")
                OutputMetric(title: "裁剪时长", value: String(format: "%.2f 秒", viewModel.selectedDuration))
                OutputMetric(title: "封面模式", value: viewModel.coverMode.rawValue)
                OutputMetric(title: "MOV 编码", value: codecStatus)
                OutputMetric(title: "MOV 时长", value: movieDurationStatus)
                OutputMetric(title: "配对校验", value: pairingStatus)
                OutputMetric(title: "照片权限", value: photosPermissionStatus)
                OutputMetric(title: "Photos", value: photosStatus)
                OutputMetric(title: "Photos 预览", value: photosLivePhotoLoadStatus)
                OutputMetric(title: "Photos 资源", value: photosResourcePairStatus)
                OutputMetric(title: "Photos 相册", value: photosAlbumStatus)
                OutputMetric(title: "Photos ID", value: photosIdentifierStatus)
                OutputMetric(title: "iCloud ID", value: cloudIdentifierStatus)
                OutputMetric(title: "iCloud 回查", value: cloudIdentifierRoundTripStatus)
                OutputMetric(title: "验证记录", value: validationRecordHistoryStatus)
                OutputMetric(title: "小米/小红书", value: androidExportStatus)

                Divider().opacity(0.3)

                Button {
                    viewModel.generateLivePhoto()
                } label: {
                    Label("生成 Live Photo", systemImage: "livephoto")
                        .frame(maxWidth: .infinity)
                }
                .video2LiveGlassButtonStyle(prominent: true)
                .disabled(!viewModel.canGenerate || viewModel.isBusy)

                Button {
                    viewModel.saveGeneratedLivePhotoToPhotos()
                } label: {
                    Label("保存到 Photos", systemImage: "photo.stack")
                        .frame(maxWidth: .infinity)
                }
                .video2LiveGlassButtonStyle(prominent: true)
                .disabled(viewModel.generatedPackage == nil || viewModel.isBusy)

                Button {
                    viewModel.exportXiaomiXiaohongshuPackage()
                } label: {
                    Label("导出候选动态图 JPG", systemImage: "photo.badge.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .video2LiveGlassButtonStyle(prominent: true)
                .disabled(viewModel.generatedPackage == nil || viewModel.isBusy)

                Button {
                    viewModel.openXiaomiXiaohongshuExportFolder()
                } label: {
                    Label("显示手机上传 JPG", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .video2LiveGlassButtonStyle()
                .disabled(viewModel.androidExportPackage == nil || viewModel.isBusy)

                Button {
                    viewModel.openPhotosPrivacySettings()
                } label: {
                    Label("打开照片权限设置", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .video2LiveGlassButtonStyle()
                .disabled(!photosPermissionNeedsAction || viewModel.isBusy)

                Button {
                    viewModel.openPhotosApp()
                } label: {
                    Label("打开 Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .video2LiveGlassButtonStyle()
                .disabled(viewModel.savedAsset == nil)

                Button {
                    viewModel.copyPhotosIdentifierToClipboard()
                } label: {
                    Label("复制 Photos ID", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .video2LiveGlassButtonStyle()
                .disabled(viewModel.savedAsset == nil)

                Button {
                    viewModel.copyDeviceValidationRecordToClipboard()
                } label: {
                    Label("复制验证记录", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .video2LiveGlassButtonStyle()
                .disabled(viewModel.savedAsset == nil)

                Button {
                    viewModel.copyAllDeviceValidationRecordsToClipboard()
                } label: {
                    Label("复制全部验证记录", systemImage: "list.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .video2LiveGlassButtonStyle()
                .disabled(viewModel.validationRecords.isEmpty)
            }
            .liquidGlass(cornerRadius: 22)
        }
    }

    private var photosPermissionStatus: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized:
            return "已允许"
        case .limited:
            return "有限访问"
        case .notDetermined:
            return "待授权"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "受限"
        @unknown default:
            return "未知"
        }
    }

    private var photosPermissionNeedsAction: Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .denied, .restricted:
            return true
        case .authorized, .limited, .notDetermined:
            return false
        @unknown default:
            return true
        }
    }

    private var photosStatus: String {
        guard let savedAsset = viewModel.savedAsset else {
            return "未保存"
        }
        return savedAsset.isLivePhoto ? "Live Photo 已验证" : "已保存，待确认"
    }

    private var photosLivePhotoLoadStatus: String {
        guard let savedAsset = viewModel.savedAsset else {
            return "-"
        }
        return savedAsset.canLoadLivePhoto ? "可重新加载" : "未验证"
    }

    private var photosResourcePairStatus: String {
        guard let savedAsset = viewModel.savedAsset else {
            return "-"
        }
        return savedAsset.hasLivePhotoResourcePair ? "photo + pairedVideo" : "未验证"
    }

    private var photosAlbumStatus: String {
        guard let savedAsset = viewModel.savedAsset else {
            return "-"
        }
        return savedAsset.isInAlbum ? savedAsset.albumTitle : "未归档"
    }

    private var photosIdentifierStatus: String {
        guard let localIdentifier = viewModel.savedAsset?.localIdentifier else {
            return "-"
        }
        return AppViewModel.shortPhotosIdentifier(from: localIdentifier)
    }

    private var cloudIdentifierStatus: String {
        guard let savedAsset = viewModel.savedAsset else {
            return "-"
        }
        guard let cloudIdentifier = savedAsset.cloudIdentifier, !cloudIdentifier.isEmpty else {
            return "未取得"
        }
        return String(cloudIdentifier.prefix(12))
    }

    private var cloudIdentifierRoundTripStatus: String {
        guard let savedAsset = viewModel.savedAsset else {
            return "-"
        }
        return savedAsset.cloudIdentifierRoundTripMatches ? "同一资产" : "未验证"
    }

    private var validationRecordHistoryStatus: String {
        viewModel.validationRecords.isEmpty ? "-" : "\(viewModel.validationRecords.count) 条"
    }

    private var androidExportStatus: String {
        guard let validation = viewModel.androidExportValidation else {
            return "未导出"
        }
        return validation.isValid ? "候选 JPG 已生成" : "待确认"
    }

    private var codecStatus: String {
        guard let validation = viewModel.generatedMetadataValidation else {
            return "未生成"
        }
        guard validation.isSupportedVideoCodec else {
            return "不支持"
        }
        return validation.videoCodec ?? "未知"
    }

    private var movieDurationStatus: String {
        guard let validation = viewModel.generatedMetadataValidation else {
            return "未生成"
        }
        let value = String(format: "%.2f 秒", validation.videoDurationSeconds)
        return validation.isDurationCompatible ? value : "\(value) 异常"
    }

    private var pairingStatus: String {
        guard let validation = viewModel.generatedMetadataValidation else {
            return "未生成"
        }
        return validation.isPaired && validation.hasTimedMetadataTrack ? "已验证" : "异常"
    }
}

private struct VideoFrameCoverPicker: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = viewModel.videoFrameCover {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Label("Key Photo", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(8)
                            .background(.thinMaterial, in: Capsule())
                            .padding(8)
                    }
            }

            Slider(
                value: Binding(
                    get: { viewModel.coverTime },
                    set: { viewModel.updateCoverTime($0) }
                ),
                in: viewModel.startTime...max(viewModel.endTime, viewModel.startTime + 0.01)
            )
            HStack {
                Text("封面帧")
                Spacer()
                Text(String(format: "%.2fs", viewModel.coverTime))
                    .monospacedDigit()
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }
}

private struct UploadedCoverPicker: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = viewModel.uploadedCover {
                CropEditor(image: image)
            } else {
                Button {
                    viewModel.openCoverImagePicker()
                } label: {
                    Label("选择封面图片", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .video2LiveGlassButtonStyle()
            }
        }
    }
}

private struct CropEditor: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let image: NSImage
    @GestureState private var dragTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let imageSize = sourcePixelSize
                let imageRect = fittedRect(imageSize: imageSize, containerSize: geometry.size)
                let targetAspect = max(0.01, viewModel.videoSize.width / max(viewModel.videoSize.height, 1))
                let baseSelection = viewModel.cropSelection.clamped(sourceSize: imageSize, targetAspect: targetAspect)
                let previewSelection = selectionByApplyingDrag(
                    baseSelection,
                    drag: dragTranslation,
                    imageRect: imageRect,
                    sourceSize: imageSize,
                    targetAspect: targetAspect
                )
                let cropRect = displayCropRect(selection: previewSelection, imageRect: imageRect, sourceSize: imageSize, targetAspect: targetAspect)

                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    Rectangle()
                        .fill(.black.opacity(0.42))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .mask {
                            CropMask(cropRect: cropRect, containerSize: geometry.size)
                                .fill(style: FillStyle(eoFill: true))
                        }

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.94), lineWidth: 2)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.06))
                        }
                        .frame(width: cropRect.width, height: cropRect.height)
                        .position(x: cropRect.midX, y: cropRect.midY)
                        .shadow(color: .black.opacity(0.55), radius: 8)
                        .gesture(
                            DragGesture()
                                .updating($dragTranslation) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    let next = selectionByApplyingDrag(
                                        baseSelection,
                                        drag: value.translation,
                                        imageRect: imageRect,
                                        sourceSize: imageSize,
                                        targetAspect: targetAspect
                                    )
                                    viewModel.updateCropSelection(next, sourceImage: image)
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / max(lastMagnification, 0.01)
                                    lastMagnification = value
                                    let next = CropSelection(
                                        centerX: viewModel.cropSelection.centerX,
                                        centerY: viewModel.cropSelection.centerY,
                                        width: viewModel.cropSelection.width / max(delta, 0.01)
                                    )
                                    viewModel.updateCropSelection(next, sourceImage: image)
                                }
                                .onEnded { _ in
                                    lastMagnification = 1
                                }
                        )

                    VStack {
                        Spacer()
                        Text("比例锁定 \(Int(viewModel.videoSize.width)):\(Int(viewModel.videoSize.height))")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)

            HStack {
                Image(systemName: "minus.magnifyingglass")
                Slider(
                    value: Binding(
                        get: { viewModel.cropSelection.width },
                        set: { width in
                            viewModel.updateCropSelection(
                                CropSelection(
                                    centerX: viewModel.cropSelection.centerX,
                                    centerY: viewModel.cropSelection.centerY,
                                    width: width
                                ),
                                sourceImage: image
                            )
                        }
                    ),
                    in: 0.12...1
                )
                Image(systemName: "plus.magnifyingglass")
            }

            Button {
                viewModel.updateCropSelection(CropSelection(), sourceImage: image)
            } label: {
                Label("重置裁剪", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .video2LiveGlassButtonStyle()
        }
    }

    private var sourcePixelSize: CGSize {
        var rect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return image.size
    }

    private func fittedRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func selectionByApplyingDrag(
        _ selection: CropSelection,
        drag: CGSize,
        imageRect: CGRect,
        sourceSize: CGSize,
        targetAspect: CGFloat
    ) -> CropSelection {
        guard imageRect.width > 0, imageRect.height > 0 else { return selection }
        return CropSelection(
            centerX: selection.centerX + drag.width / imageRect.width,
            centerY: selection.centerY + drag.height / imageRect.height,
            width: selection.width
        )
        .clamped(sourceSize: sourceSize, targetAspect: targetAspect)
    }

    private func displayCropRect(selection: CropSelection, imageRect: CGRect, sourceSize: CGSize, targetAspect: CGFloat) -> CGRect {
        let sourceCrop = selection.cropRect(in: sourceSize, targetAspect: targetAspect)
        let scale = imageRect.width / max(sourceSize.width, 1)
        return CGRect(
            x: imageRect.minX + sourceCrop.minX * scale,
            y: imageRect.minY + sourceCrop.minY * scale,
            width: sourceCrop.width * scale,
            height: sourceCrop.height * scale
        )
    }
}

private struct CropMask: Shape {
    let cropRect: CGRect
    let containerSize: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(origin: .zero, size: containerSize))
        path.addRoundedRect(in: cropRect, cornerSize: CGSize(width: 14, height: 14))
        return path
    }
}

private struct LivePreviewPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Photo 预览")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if viewModel.livePhoto != nil {
                    Button {
                        viewModel.replayLivePhotoPreview()
                    } label: {
                        Label("重播", systemImage: "play.circle")
                    }
                    .video2LiveGlassButtonStyle()
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.black.opacity(0.38))

                if viewModel.livePhoto == nil {
                    Text("生成后在这里播放 Live Photo")
                        .foregroundStyle(.secondary)
                } else {
                    LivePhotoPreviewView(
                        livePhoto: viewModel.livePhoto,
                        playbackRequest: viewModel.previewPlaybackRequest
                    )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .frame(height: 180)
        }
        .liquidGlass(cornerRadius: 22)
    }
}

private struct OutputMetric: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

private struct StatusBarView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.errorText == nil ? "info.circle" : "exclamationmark.triangle.fill")
                .foregroundStyle(viewModel.errorText == nil ? Color.secondary : Color.orange)
            Text(viewModel.errorText ?? viewModel.statusText)
                .lineLimit(1)
            Spacer()
            Text(viewModel.generatedPackage?.assetIdentifier ?? "未生成")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .liquidGlass(cornerRadius: 18, padding: 10)
    }
}

private struct BusyOverlay: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.1)
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .frame(width: 260)
        .liquidGlass(cornerRadius: 24)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: text)
    }
}

private struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: backgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            DiagonalRefractionBands()
                .opacity(colorScheme == .dark ? 0.44 : 0.32)
        }
        .overlay {
            Rectangle()
                .fill(colorScheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.10))
        }
        .ignoresSafeArea()
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.07, green: 0.09, blue: 0.11),
                Color(red: 0.10, green: 0.18, blue: 0.19),
                Color(red: 0.22, green: 0.18, blue: 0.11)
            ]
        }
        return [
            Color(red: 0.76, green: 0.88, blue: 0.92),
            Color(red: 0.96, green: 0.91, blue: 0.76),
            Color(red: 0.78, green: 0.91, blue: 0.82)
        ]
    }
}

private struct DiagonalRefractionBands: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<5) { index in
                    Rectangle()
                        .fill(bandGradient(index: index))
                        .frame(width: geometry.size.width * 1.7, height: 70 + CGFloat(index) * 12)
                        .rotationEffect(.degrees(-18))
                        .offset(x: -geometry.size.width * 0.36, y: CGFloat(index) * geometry.size.height * 0.2 - geometry.size.height * 0.18)
                        .blur(radius: 18)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func bandGradient(index: Int) -> LinearGradient {
        let darkPalette = [
            Color.cyan.opacity(0.18),
            Color.green.opacity(0.10),
            Color.yellow.opacity(0.10),
            Color.white.opacity(0.08),
            Color.mint.opacity(0.12)
        ]
        let lightPalette = [
            Color.cyan.opacity(0.22),
            Color.orange.opacity(0.14),
            Color.green.opacity(0.12),
            Color.white.opacity(0.34),
            Color.blue.opacity(0.10)
        ]
        let palette = colorScheme == .dark ? darkPalette : lightPalette
        return LinearGradient(
            colors: [
                .clear,
                palette[index % palette.count],
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
