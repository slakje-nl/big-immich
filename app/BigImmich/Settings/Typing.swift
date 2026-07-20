//
//  Typing.swift
//  BigImmich
//
//  Created by Maciej Płoński on 18/01/2026.
//

import Combine
import ImmichAPI
import KeychainHelper
import SwiftUI

enum SlideshowDirection: String, CaseIterable, Identifiable {
    case oldestToNewest
    case newestToOldest
    case randomized

    var id: String {
        rawValue
    }
}

enum SlideshowAction: String, CaseIterable, Identifiable {
    case goToNext
    case goToPrevious

    var id: String {
        rawValue
    }
}

enum SlideshowOnceEndedAction: String, CaseIterable, Identifiable {
    case stopAndNotify
    case startAgain
    case loadAnotherAlbum

    var id: String {
        rawValue
    }
}

enum SlideshowOnceEndedAnotherAlbumSelection: String, CaseIterable, Identifiable {
    case older
    case newer
    case random

    var id: String {
        rawValue
    }
}

enum SlideshowShowProgressBar: String, CaseIterable, Identifiable {
    case always
    case never

    var id: String {
        rawValue
    }
}

/// How video is streamed from Immich.
///
/// `classic` uses the legacy progressive `/video/playback` endpoint (a single pre-generated
/// transcode; works on any server). `hls` uses Immich 3.0+ real-time HLS transcoding
/// (`/video/stream/main.m3u8`), which re-encodes on the fly to a streamable bitrate and
/// supports adaptive quality — requires the server to have HLS transcoding enabled.
enum SlideshowVideoEngine: String, CaseIterable, Identifiable {
    case classic
    case hls

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .classic: "Classic (progressive)"
        case .hls: "Adaptive (HLS)"
        }
    }
}

/// Preferred HLS quality. `auto` lets the player adapt to bandwidth (may drop under
/// congestion, recovers automatically). A pinned resolution caps the ladder so playback
/// stays at that quality and buffers instead of downgrading. The actual variant is resolved
/// at runtime against what the server advertises in the master playlist.
enum SlideshowVideoQuality: String, CaseIterable, Identifiable {
    case auto
    case uhd2160
    case qhd1440
    case fhd1080
    case hd720
    case sd480

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .auto: "Auto (adaptive)"
        case .uhd2160: "2160p (4K)"
        case .qhd1440: "1440p"
        case .fhd1080: "1080p"
        case .hd720: "720p"
        case .sd480: "480p"
        }
    }

    /// Compact label for the in-slideshow options overlay, so the row stays on one line — just
    /// "Auto" for the adaptive mode and the bare resolution for the pinned ones.
    var shortLabel: String {
        switch self {
        case .auto: "Auto"
        case .uhd2160: "2160p"
        case .qhd1440: "1440p"
        case .fhd1080: "1080p"
        case .hd720: "720p"
        case .sd480: "480p"
        }
    }

    /// The pinned rendition height in pixels, or `nil` for `auto`.
    var maxHeight: Int? {
        switch self {
        case .auto: nil
        case .uhd2160: 2160
        case .qhd1440: 1440
        case .fhd1080: 1080
        case .hd720: 720
        case .sd480: 480
        }
    }
}

/// Which Immich rendition the slideshow requests for each photo. Smaller renditions
/// download faster on slow networks; maps to the `size` param on the thumbnail endpoint.
enum SlideshowImageQuality: String, CaseIterable, Identifiable {
    case thumbnail
    case preview
    case fullsize
    case original

    var id: String {
        rawValue
    }

    var thumbnailSize: ThumbnailSize {
        switch self {
        case .thumbnail: .thumbnail
        case .preview: .preview
        case .fullsize: .fullsize
        case .original: .original
        }
    }
}

protocol SlideshowSettingsProtocol {
    var slideshowInterval: Int { get set }
    var slideshowDirection: SlideshowDirection { get set }
    var slideshowLeftAction: SlideshowAction { get set }
    var slideshowRightAction: SlideshowAction { get set }
    var slideshowOnceEndedAction: SlideshowOnceEndedAction { get set }
    var slideshowOnceEndedAnotherAlbumSelection:
        SlideshowOnceEndedAnotherAlbumSelection { get set }
    var slideshowShowProgressBar: SlideshowShowProgressBar { get set }
    var slideshowImageQuality: SlideshowImageQuality { get set }
    var slideshowPreloadVideos: Bool { get set }
    var slideshowVideoEngine: SlideshowVideoEngine { get set }
    var slideshowVideoQuality: SlideshowVideoQuality { get set }
    var slideshowShowVideoStats: Bool { get set }
}

final class SlideshowSettings: ObservableObject, SlideshowSettingsProtocol {
    @AppStorage("slideshowInterval") var slideshowInterval: Int = 5
    @AppStorage("slideshowDirection") var slideshowDirection:
        SlideshowDirection = .oldestToNewest
    @AppStorage("slideshowLeftAction") var slideshowLeftAction:
        SlideshowAction = .goToNext
    @AppStorage("slideshowRightAction") var slideshowRightAction:
        SlideshowAction = .goToPrevious
    @AppStorage("slideshowOnceEndedAction") var slideshowOnceEndedAction: SlideshowOnceEndedAction = .stopAndNotify
    @AppStorage("slideshowOnceEndedAnotherAlbum") var slideshowOnceEndedAnotherAlbumSelection:
        SlideshowOnceEndedAnotherAlbumSelection = .random
    @AppStorage("slideshowShowProgressBar") var slideshowShowProgressBar: SlideshowShowProgressBar = .always
    @AppStorage("slideshowImageQuality") var slideshowImageQuality: SlideshowImageQuality = .fullsize
    @AppStorage("slideshowPreloadVideos") var slideshowPreloadVideos: Bool = true
    /// Defaults to the legacy Classic (progressive) engine — it works on any server. Switching
    /// to Adaptive (HLS) opts into real-time transcoding + the on-screen quality menu.
    @AppStorage("slideshowVideoEngine") var slideshowVideoEngine: SlideshowVideoEngine = .classic
    // Defaults to a pinned 1080p rather than Auto: slideshow clips are often very short, and HLS
    // ABR cold-starts on the lowest rung and ramps up over several seconds — worsened by real-time
    // transcoding, where each step up waits on the server to spin up that variant. A short clip
    // ends before Auto ever climbs, so it looks stuck at low quality. Pinning starts at full
    // quality immediately (buffering briefly if needed) instead of adapting.
    @AppStorage("slideshowVideoQuality") var slideshowVideoQuality: SlideshowVideoQuality = .fhd1080
    @AppStorage("slideshowShowVideoStats") var slideshowShowVideoStats: Bool = false
}
