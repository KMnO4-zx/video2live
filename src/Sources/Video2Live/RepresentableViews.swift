import AVKit
import Photos
import PhotosUI
import SwiftUI

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

struct LivePhotoPreviewView: NSViewRepresentable {
    let livePhoto: PHLivePhoto?
    let playbackRequest: Int

    func makeNSView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .aspectFit
        view.isMuted = false
        view.audioVolume = 0.7
        return view
    }

    func updateNSView(_ nsView: PHLivePhotoView, context: Context) {
        if nsView.livePhoto !== livePhoto {
            nsView.livePhoto = livePhoto
            context.coordinator.lastPlaybackRequest = nil
        }

        guard livePhoto != nil else {
            context.coordinator.lastPlaybackRequest = nil
            return
        }

        if context.coordinator.lastPlaybackRequest != playbackRequest {
            context.coordinator.lastPlaybackRequest = playbackRequest
            nsView.stopPlayback()
            nsView.startPlayback(with: .full)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastPlaybackRequest: Int?
    }
}
