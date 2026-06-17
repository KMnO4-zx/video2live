import AppKit
import Foundation
import Photos

public enum CoverMode: String, CaseIterable, Identifiable {
    case videoFrame = "视频选帧"
    case uploadedImage = "上传图片"

    public var id: String { rawValue }
}

public struct LivePhotoPackage: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let assetIdentifier: String
    public let photoURL: URL
    public let videoURL: URL
    public let coverImage: NSImage
}

public struct SavedLivePhotoAsset: Sendable {
    public let localIdentifier: String
    public let isLivePhoto: Bool
    public let canLoadLivePhoto: Bool
    public let albumTitle: String
    public let isInAlbum: Bool
    public let resourceTypes: [String]
    public let cloudIdentifier: String?
    public let cloudIdentifierError: String?
    public let cloudIdentifierRoundTripLocalIdentifier: String?
    public let cloudIdentifierRoundTripError: String?

    public var hasPhotoResource: Bool {
        resourceTypes.contains("photo")
    }

    public var hasPairedVideoResource: Bool {
        resourceTypes.contains("pairedVideo")
    }

    public var hasLivePhotoResourcePair: Bool {
        hasPhotoResource && hasPairedVideoResource
    }

    public var hasCloudIdentifier: Bool {
        cloudIdentifier?.isEmpty == false
    }

    public var cloudIdentifierRoundTripMatches: Bool {
        cloudIdentifierRoundTripLocalIdentifier == localIdentifier
    }
}

public struct AndroidMotionPhotoPackage: Sendable {
    public let directoryURL: URL
    public let motionPhotoURL: URL
    public let fallbackVideoURL: URL
    public let coverPhotoURL: URL
    public let manifestURL: URL
}

public struct AndroidMotionPhotoValidation: Sendable {
    public let hasXMPMetadata: Bool
    public let hasMotionPhotoFlag: Bool
    public let hasMicroVideoOffset: Bool
    public let microVideoOffsetMatchesVideoLength: Bool
    public let containerItemLengthMatchesVideoLength: Bool
    public let appendedVideoMatchesFallbackVideo: Bool
    public let fallbackVideoCodec: String?
    public let fallbackVideoDurationSeconds: Double

    public var isSupportedVideoCodec: Bool {
        guard let fallbackVideoCodec else { return false }
        return ["avc1", "hvc1", "hev1"].contains(fallbackVideoCodec)
    }

    public var isDurationCompatible: Bool {
        fallbackVideoDurationSeconds.isFinite
            && fallbackVideoDurationSeconds >= 0.95
            && fallbackVideoDurationSeconds <= 5.10
    }

    public var isValid: Bool {
        hasXMPMetadata
            && hasMotionPhotoFlag
            && hasMicroVideoOffset
            && microVideoOffsetMatchesVideoLength
            && containerItemLengthMatchesVideoLength
            && appendedVideoMatchesFallbackVideo
            && isSupportedVideoCodec
            && isDurationCompatible
    }
}

public struct LivePhotoMetadataValidation: Sendable {
    public let expectedAssetIdentifier: String
    public let photoAssetIdentifier: String?
    public let videoAssetIdentifier: String?
    public let videoCodec: String?
    public let videoDurationSeconds: Double
    public let hasTimedMetadataTrack: Bool

    public var photoIdentifierMatches: Bool {
        photoAssetIdentifier == expectedAssetIdentifier
    }

    public var videoIdentifierMatches: Bool {
        videoAssetIdentifier == expectedAssetIdentifier
    }

    public var isPaired: Bool {
        photoIdentifierMatches && videoIdentifierMatches
    }

    public var isSupportedVideoCodec: Bool {
        guard let videoCodec else { return false }
        return ["avc1", "hvc1", "hev1"].contains(videoCodec)
    }

    public var isDurationCompatible: Bool {
        // AVFoundation export can add small frame/timescale rounding around the selected 1-5s range.
        videoDurationSeconds.isFinite
            && videoDurationSeconds >= 0.95
            && videoDurationSeconds <= 5.10
    }
}

public struct CropSelection: Equatable {
    public var centerX: CGFloat
    public var centerY: CGFloat
    public var width: CGFloat

    public init(centerX: CGFloat = 0.5, centerY: CGFloat = 0.5, width: CGFloat = 1.0) {
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
    }

    public func clamped(sourceSize: CGSize, targetAspect: CGFloat) -> CropSelection {
        guard sourceSize.width > 0, sourceSize.height > 0, targetAspect > 0 else {
            return CropSelection()
        }

        let maxWidthByHeight = targetAspect * sourceSize.height / sourceSize.width
        let clampedWidth = min(max(width, 0.12), min(1, maxWidthByHeight))
        let cropHeight = clampedWidth * sourceSize.width / targetAspect / sourceSize.height
        let halfWidth = clampedWidth / 2
        let halfHeight = cropHeight / 2

        return CropSelection(
            centerX: min(max(centerX, halfWidth), 1 - halfWidth),
            centerY: min(max(centerY, halfHeight), 1 - halfHeight),
            width: clampedWidth
        )
    }

    public func cropRect(in sourceSize: CGSize, targetAspect: CGFloat) -> CGRect {
        let selection = clamped(sourceSize: sourceSize, targetAspect: targetAspect)
        let cropWidth = selection.width * sourceSize.width
        let cropHeight = cropWidth / targetAspect
        let origin = CGPoint(
            x: selection.centerX * sourceSize.width - cropWidth / 2,
            y: selection.centerY * sourceSize.height - cropHeight / 2
        )
        return CGRect(origin: origin, size: CGSize(width: cropWidth, height: cropHeight))
            .intersection(CGRect(origin: .zero, size: sourceSize))
    }
}

public enum Video2LiveError: LocalizedError {
    case invalidVideo
    case missingVideoTrack
    case missingCoverImage
    case exportSessionUnavailable
    case exportFailed(String)
    case invalidClipDuration
    case imageEncodingFailed
    case photoLibraryDenied
    case photoLibrarySaveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVideo:
            "无法读取视频文件。"
        case .missingVideoTrack:
            "视频中没有可用的视频轨道。"
        case .missingCoverImage:
            "请先选择或上传 Live Photo 封面。"
        case .exportSessionUnavailable:
            "当前视频无法创建导出会话。"
        case .exportFailed(let reason):
            "视频导出失败：\(reason)"
        case .invalidClipDuration:
            "请选择 1 到 5 秒的视频片段后再生成 Live Photo。"
        case .imageEncodingFailed:
            "封面图片写入失败。"
        case .photoLibraryDenied:
            "没有 Photos 相册写入权限。请在系统设置 > 隐私与安全性 > 照片中允许 Video2Live 访问，或重置 com.video2live.mac 的 Photos 权限后重新运行。"
        case .photoLibrarySaveFailed(let reason):
            "保存到 Photos 失败：\(reason)"
        }
    }
}
