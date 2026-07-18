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
}
