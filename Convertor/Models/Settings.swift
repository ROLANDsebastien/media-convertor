import Combine
import Foundation

enum OutputDirectoryType: String, CaseIterable, Identifiable {
    case documents = "Documents"
    case downloads = "Downloads"
    case custom = "Custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .documents: return String(localized: "Documents")
        case .downloads: return String(localized: "Downloads")
        case .custom: return String(localized: "Custom Folder")
        }
    }

    var url: URL? {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"
        switch self {
        case .documents:
            return URL(fileURLWithPath: home).appendingPathComponent("Documents")
        case .downloads:
            return URL(fileURLWithPath: home).appendingPathComponent("Downloads")
        case .custom:
            return nil
        }
    }
}

enum AudioQuality: Int, CaseIterable, Identifiable {
    case low, medium, high, veryHigh, lossless
    var id: Int { self.rawValue }

    var name: String {
        switch self {
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high: return String(localized: "High")
        case .veryHigh: return String(localized: "Very High")
        case .lossless: return String(localized: "Lossless")
        }
    }

    var bitrate: Int {
        switch self {
        case .low: return 96
        case .medium: return 128
        case .high: return 192
        case .veryHigh: return 256
        case .lossless: return 0  // alac is lossless
        }
    }
}

enum VideoQuality: Int, CaseIterable, Identifiable {
    case low, medium, high, veryHigh
    var id: Int { self.rawValue }

    var name: String {
        switch self {
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high: return String(localized: "High")
        case .veryHigh: return String(localized: "Very High")
        }
    }

    var bitrate: Int {
        switch self {
        case .low: return 1000  // 1 Mbps
        case .medium: return 2000  // 2 Mbps
        case .high: return 4000  // 4 Mbps
        case .veryHigh: return 6000  // 6 Mbps
        }
    }
}

class Settings: ObservableObject {
    @Published var defaultAudioFormat: OutputFormat {
        didSet {
            UserDefaults.standard.set(defaultAudioFormat.rawValue, forKey: "defaultAudioFormat")
        }
    }



    @Published var defaultOutputFormat: OutputFormat {
        didSet {
            UserDefaults.standard.set(defaultOutputFormat.rawValue, forKey: "defaultOutputFormat")
        }
    }

    @Published var audioQuality: AudioQuality {
        didSet {
            UserDefaults.standard.set(audioQuality.rawValue, forKey: "audioQuality")
        }
    }

    @Published var videoQuality: VideoQuality {
        didSet {
            UserDefaults.standard.set(videoQuality.rawValue, forKey: "videoQuality")
        }
    }

    @Published var defaultVideoCodec: VideoCodec {
        didSet {
            UserDefaults.standard.set(defaultVideoCodec.rawValue, forKey: "defaultVideoCodec")
        }
    }

    @Published var defaultVideoResolution: VideoResolution {
        didSet {
            UserDefaults.standard.set(
                defaultVideoResolution.rawValue, forKey: "defaultVideoResolution")
        }
    }

    @Published var defaultAudioBitrate: AudioBitrate {
        didSet {
            UserDefaults.standard.set(defaultAudioBitrate.rawValue, forKey: "defaultAudioBitrate")
        }
    }

    @Published var maxConcurrentTasks: Int {
        didSet {
            UserDefaults.standard.set(maxConcurrentTasks, forKey: "maxConcurrentTasks")
        }
    }

    @Published var outputDirectoryType: OutputDirectoryType {
        didSet {
            UserDefaults.standard.set(outputDirectoryType.rawValue, forKey: "outputDirectoryType")
            // Update the computed outputDirectory
            updateOutputDirectory()
        }
    }

    @Published var customOutputDirectory: URL? {
        didSet {
            guard let url = customOutputDirectory else {
                UserDefaults.standard.removeObject(forKey: "customOutputDirectory")
                UserDefaults.standard.removeObject(forKey: "customOutputDirectoryPath")
                updateOutputDirectory()
                return
            }

            // Try to create a security-scoped bookmark for persistence
            do {
                let bookmark = try url.bookmarkData(
                    options: .withSecurityScope, includingResourceValuesForKeys: nil,
                    relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: "customOutputDirectory")
                UserDefaults.standard.removeObject(forKey: "customOutputDirectoryPath")
            } catch {
                // If bookmark creation fails, store the path directly
                UserDefaults.standard.set(url.path, forKey: "customOutputDirectoryPath")
                UserDefaults.standard.removeObject(forKey: "customOutputDirectory")
            }
            updateOutputDirectory()
        }
    }

    var outputDirectory: URL? {
        switch outputDirectoryType {
        case .documents, .downloads:
            return outputDirectoryType.url ?? URL(fileURLWithPath: (ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())")).appendingPathComponent("Documents")
        case .custom:
            return customOutputDirectory
        }
    }

    private func updateOutputDirectory() {
        // This will trigger any observers of outputDirectory
        objectWillChange.send()
    }

    init() {
        self.defaultAudioFormat =
            OutputFormat(
                rawValue: UserDefaults.standard.string(forKey: "defaultAudioFormat") ?? "aac")
            ?? .aac

        self.defaultOutputFormat =
            OutputFormat(
                rawValue: UserDefaults.standard.string(forKey: "defaultOutputFormat") ?? "aac")
            ?? .aac
        self.audioQuality =
            AudioQuality(rawValue: UserDefaults.standard.integer(forKey: "audioQuality")) ?? .high
        self.videoQuality =
            VideoQuality(rawValue: UserDefaults.standard.integer(forKey: "videoQuality")) ?? .medium
        self.defaultVideoCodec =
            VideoCodec(
                rawValue: UserDefaults.standard.string(forKey: "defaultVideoCodec") ?? "H.264")
            ?? .h264
        self.defaultVideoResolution =
            VideoResolution(
                rawValue: UserDefaults.standard.string(forKey: "defaultVideoResolution") ?? "1080p")
            ?? .r1080p
        self.defaultAudioBitrate =
            AudioBitrate(rawValue: UserDefaults.standard.integer(forKey: "defaultAudioBitrate"))
            ?? .b256
        self.maxConcurrentTasks =
            UserDefaults.standard.integer(forKey: "maxConcurrentTasks") == 0
            ? 4 : UserDefaults.standard.integer(forKey: "maxConcurrentTasks")

        // Load output directory type
        self.outputDirectoryType =
            OutputDirectoryType(
                rawValue: UserDefaults.standard.string(forKey: "outputDirectoryType") ?? "downloads"
            )
            ?? .downloads

        // Load custom directory if needed
        self.customOutputDirectory = nil
        if outputDirectoryType == .custom {
            // Try to load from bookmark first
            if let bookmark = UserDefaults.standard.data(forKey: "customOutputDirectory") {
                do {
                    var isStale = false
                    self.customOutputDirectory = try URL(
                        resolvingBookmarkData: bookmark, options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale)
                    if isStale {
                        // Clear stale bookmark
                        UserDefaults.standard.removeObject(forKey: "customOutputDirectory")
                        self.customOutputDirectory = nil
                    }
                } catch {
                    // Clear invalid bookmark data
                    UserDefaults.standard.removeObject(forKey: "customOutputDirectory")
                    self.customOutputDirectory = nil
                }
            }
            // If no bookmark, try to load from path
            else if let path = UserDefaults.standard.string(forKey: "customOutputDirectoryPath") {
                self.customOutputDirectory = URL(fileURLWithPath: path)
            }
        }
    }
}
