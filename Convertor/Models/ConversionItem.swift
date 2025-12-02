import Combine
import Foundation

// MARK: - MediaInfo Structures
struct AudioTrack: Identifiable, Hashable, Codable {
    var id: Int { index }
    let index: Int
    let language: String
    var title: String
}

struct SubtitleTrack: Identifiable, Hashable, Codable {
    var id: Int { index }
    let index: Int
    let language: String
    var title: String
}

// MARK: - FFProbe Structures for JSON Parsing
struct FFProbeResult: Codable {
    let streams: [FFProbeStream]
}

struct FFProbeStream: Codable {
    let index: Int
    let codec_type: String
    let tags: [String: String]?
}

enum MediaType: String, CaseIterable, Identifiable {
    case audio = "Audio"
    case video = "Video"
    var id: String { rawValue }
}

enum VideoCodec: String, CaseIterable, Identifiable {
    case h264 = "H.264"
    case h265 = "H.265 (HEVC)"
    case hevcCopy = "HEVC Passthrough (Copy)"
    var id: String { rawValue }
    var ffmpegCodec: String {
        switch self {
        case .hevcCopy: return "copy"
        #if arch(arm64)
            // Use VideoToolbox for hardware acceleration on Apple Silicon
            case .h264: return "h264_videotoolbox"
            case .h265: return "hevc_videotoolbox"
        #else
            // Fallback to software encoding on Intel Macs
            case .h264: return "libx264"
            case .h265: return "libx265"
        #endif
        }
    }
}

enum VideoResolution: String, CaseIterable, Identifiable {
    case r720p = "720p"
    case r1080p = "1080p"
    case r2160p = "2160p (4K)"
    var id: String { rawValue }
    var height: Int {
        switch self {
        case .r720p: return 720
        case .r1080p: return 1080
        case .r2160p: return 2160
        }
    }
}

enum AudioBitrate: Int, CaseIterable, Identifiable {
    case b256 = 256
    case b320 = 320
    var id: Int { rawValue }
}

struct ConversionItem: Identifiable, Equatable {
    let id = UUID()
    let sourceURL: URL
    var customName: String
    var status: ConversionStatus = .pending
    var mediaType: MediaType = .audio
    var outputFormat: OutputFormat = .aac
    var videoCodec: VideoCodec = .h264
    var videoResolution: VideoResolution = .r1080p
    var videoQuality: VideoQuality = .high
    var customVideoBitrate: Int? = nil
    var audioBitrate: AudioBitrate = .b256
    var maxFileSizeMB: Int? = nil
    var progress: Double = 0.0
    var errorMessage: String? = nil

    // New properties for track selection
    var availableAudioTracks: [AudioTrack] = []
    var availableSubtitleTracks: [SubtitleTrack] = []
    var selectedAudioTrackID: Int?
    var selectedSubtitleTrackID: Int?

    init(
        sourceURL: URL, mediaType: MediaType = .audio, outputFormat: OutputFormat = .aac,
        videoCodec: VideoCodec = .h264, videoResolution: VideoResolution = .r1080p,
        videoQuality: VideoQuality = .high, customVideoBitrate: Int? = nil,
        audioBitrate: AudioBitrate = .b256, maxFileSizeMB: Int? = nil
    ) {
        self.sourceURL = sourceURL
        self.customName = sourceURL.lastPathComponent
        self.mediaType = mediaType
        self.outputFormat = outputFormat
        self.videoCodec = videoCodec
        self.videoResolution = videoResolution
        self.videoQuality = videoQuality
        self.customVideoBitrate = customVideoBitrate
        self.audioBitrate = audioBitrate
        self.maxFileSizeMB = maxFileSizeMB
    }

    static func == (lhs: ConversionItem, rhs: ConversionItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum ConversionStatus: Equatable {
    case pending
    case converting
    case completed
    case failed
    case cancelled
}

enum OutputFormat: String, CaseIterable, Identifiable, Equatable {
    case aac = "AAC"
    case alac = "Apple Lossless"
    case mp4 = "MP4 (Video)"
    var id: String { rawValue }
}
