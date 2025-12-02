import AVFoundation
import Combine
import Foundation
import SwiftUI
import UserNotifications

class ConvertorViewModel: ObservableObject {
    @Published var conversionItems: [ConversionItem] = []

    @Published var isConverting: Bool = false

    private let conversionService = ConversionService()
    private let mediaInfoService = MediaInfoService()
    private var conversionQueue = PassthroughSubject<UUID, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var conversionCancellables: [UUID: AnyCancellable] = [:]
    private var queuedItemIDs = Set<UUID>()
    private let settings: Settings
    private var activeConversions = 0

    init(settings: Settings) {
        self.settings = settings

        setupConversionQueue()
    }

    private func setupConversionQueue() {
        conversionQueue
            .flatMap(maxPublishers: .max(settings.maxConcurrentTasks)) {
                [weak self] itemID -> AnyPublisher<(UUID, Result<URL, Error>), Never> in
                guard let self = self,
                    let index = self.conversionItems.firstIndex(where: { $0.id == itemID })
                else {
                    return Empty().eraseToAnyPublisher()
                }

                let item = self.conversionItems[index]

                let conversionPublisher = self.conversionService.convert(
                    item: item,
                    outputDirectory: self.settings.outputDirectory,
                    progressHandler: { progress in
                        DispatchQueue.main.async {
                            self.updateProgress(for: itemID, progress: progress)
                        }
                    }
                )
                .map { url in (itemID, Result.success(url)) }
                .catch { error in Just((itemID, Result.failure(error))) }
                .handleEvents(receiveSubscription: { subscription in
                    DispatchQueue.main.async {
                        self.activeConversions += 1
                        if let index = self.conversionItems.firstIndex(where: { $0.id == itemID }) {
                            var item = self.conversionItems[index]
                            item.status = .converting
                            self.conversionItems[index] = item
                            self.conversionCancellables[itemID] = AnyCancellable(subscription)
                        }
                    }
                })
                .handleEvents(receiveCancel: { [weak self] in
                    guard let self = self else { return }
                    print("🛑 Conversion cancelled, terminating FFmpeg process")
                    // Terminate FFmpeg process
                    // Note: process is captured from the convert function, but since it's async, we can't access it here
                    // The termination is handled in ConversionService
                    DispatchQueue.main.async {
                        self.queuedItemIDs.remove(itemID)
                        self.conversionCancellables.removeValue(forKey: itemID)
                        self.updateStatus(for: itemID, status: .cancelled)
                        self.activeConversions -= 1
                        self.sendNextPending()
                    }
                })
                .eraseToAnyPublisher()

                return conversionPublisher
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (itemID, result) in
                guard let self = self else { return }

                self.queuedItemIDs.remove(itemID)
                self.conversionCancellables.removeValue(forKey: itemID)

                // Ignore result if the item has been cancelled
                if self.conversionItems.first(where: { $0.id == itemID })?.status == .cancelled {
                    self.activeConversions -= 1
                    self.sendNextPending()
                    return
                }
                switch result {
                case .success(let url):
                    self.updateStatus(for: itemID, status: .completed, outputURL: url)
                case .failure(let error):
                    self.updateStatus(
                        for: itemID, status: .failed, error: error.localizedDescription)
                }
                self.activeConversions -= 1
                self.sendNextPending()
            }
            .store(in: &cancellables)
    }

    func addFile(url: URL) {
        print(
            "🔍 Adding file: \(url.lastPathComponent), extension: \(url.pathExtension.lowercased())")
        Task {
            let ext = url.pathExtension.lowercased()
            let isAudio = ["flac", "wav", "mp3", "aac", "m4a"].contains(ext)
            let isVideo = ["mkv", "mp4", "avi", "mov", "m4v", "webm"].contains(ext)

            if isAudio {
                print("🎵 Detected audio file")
                let newItem = ConversionItem(
                    sourceURL: url,
                    mediaType: .audio,
                    outputFormat: settings.defaultAudioFormat,
                    audioBitrate: settings.defaultAudioBitrate
                )
                if !conversionItems.contains(where: { $0.sourceURL == newItem.sourceURL }) {
                    await MainActor.run {
                        conversionItems.append(newItem)
                        print("✅ Audio item added: \(newItem.customName)")
                    }
                } else {
                    print("⚠️ Audio item already exists")
                }
            } else if isVideo {
                print("🎬 Detected video file")
                var newItem = ConversionItem(
                    sourceURL: url,
                    mediaType: .video,
                    outputFormat: .mp4,
                    videoCodec: settings.defaultVideoCodec,
                    videoResolution: settings.defaultVideoResolution,
                    videoQuality: settings.videoQuality,
                    audioBitrate: settings.defaultAudioBitrate
                )

                do {
                    let (audioTracks, subtitleTracks) = try await mediaInfoService.getMediaInfo(
                        for: url)
                    newItem.availableAudioTracks = audioTracks
                    newItem.availableSubtitleTracks = subtitleTracks
                    // Select the first audio track by default, if any
                    newItem.selectedAudioTrackID = audioTracks.first?.id
                    // No subtitle track selected by default
                    newItem.selectedSubtitleTrackID = nil
                    print(
                        "📊 Media info retrieved: \(audioTracks.count) audio tracks, \(subtitleTracks.count) subtitle tracks"
                    )
                } catch {
                    print("❌ Error getting media info: \(error.localizedDescription)")
                    // Even if getting info fails, add the file for conversion with default settings
                }

                if !conversionItems.contains(where: { $0.sourceURL == newItem.sourceURL }) {
                    await MainActor.run {
                        conversionItems.append(newItem)
                        print(
                            "✅ Video item added: \(newItem.customName), output format: \(newItem.outputFormat)"
                        )
                    }
                } else {
                    print("⚠️ Video item already exists")
                }
            } else {
                print("❓ Unsupported file type")
            }
        }
    }

    func removeItems(at offsets: IndexSet) {
        let idsToRemove = offsets.map { conversionItems[$0].id }
        idsToRemove.forEach { cancelConversion(for: $0) }
        conversionItems.remove(atOffsets: offsets)
    }

    func clearConversionItems() {
        cancelAllConversions()
        queuedItemIDs.removeAll()
        conversionItems.removeAll()
    }

    func convertAllFiles() {
        print("🚀 Starting conversion of all files")
        guard !isConverting else {
            print("⚠️ Already converting, skipping")
            return
        }
        isConverting = true
        activeConversions = 0
        queuedItemIDs.removeAll()
        print(
            "📋 Total items: \(conversionItems.count), pending: \(conversionItems.filter { $0.status == .pending }.count)"
        )

        for _ in 0..<settings.maxConcurrentTasks {
            sendNextPending()
        }
    }

    private func sendNextPending() {
        if activeConversions < settings.maxConcurrentTasks,
            let nextItem = conversionItems.first(where: { $0.status == .pending && !queuedItemIDs.contains($0.id) })
        {
            print("▶️ Sending item to conversion queue: \(nextItem.customName)")
            queuedItemIDs.insert(nextItem.id)
            conversionQueue.send(nextItem.id)
        } else {
            print("⏸️ No pending items or max concurrent reached")
        }
    }

    func cancelConversion(for itemID: UUID) {
        conversionCancellables[itemID]?.cancel()
        conversionCancellables.removeValue(forKey: itemID)
        if let index = conversionItems.firstIndex(where: { $0.id == itemID }) {
            conversionItems[index].status = .cancelled
        }
    }

    func cancelAllConversions() {
        conversionCancellables.values.forEach { $0.cancel() }
        conversionCancellables.removeAll()
        activeConversions = 0
        isConverting = false
    }

    private func updateStatus(for itemID: UUID, status: ConversionStatus, error: String? = nil, outputURL: URL? = nil) {
        if let index = conversionItems.firstIndex(where: { $0.id == itemID }) {
            var item = conversionItems[index]
            item.status = status
            if let error = error {
                item.errorMessage = error
            }
            if let outputURL = outputURL {
                item.outputURL = outputURL
            }
            conversionItems[index] = item

            if status == .completed {
                sendCompletionNotification(for: item)
            }

            if conversionItems.allSatisfy({
                $0.status == .completed || $0.status == .failed || $0.status == .cancelled
            }) {
                isConverting = false
            }
        }
    }

    private func sendCompletionNotification(for item: ConversionItem) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Conversion Completed")
        content.body = String(
            format: NSLocalizedString("%@ has been converted successfully.", comment: ""),
            item.sourceURL.lastPathComponent)
        content.sound = .default

        // Pour macOS, l'icône de l'application est automatiquement utilisée
        // Pas besoin de la définir explicitement

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func updateProgress(for itemID: UUID, progress: Double) {
        if let index = conversionItems.firstIndex(where: { $0.id == itemID }) {
            conversionItems[index].progress = progress
        }
    }

    // Functions to update item properties from UI
    func updateOutputFormat(for id: UUID, format: OutputFormat) {
        if let index = conversionItems.firstIndex(where: { $0.id == id }) {
            conversionItems[index].outputFormat = format
        }
    }

    func updateVideoCodec(for id: UUID, codec: VideoCodec) {
        if let index = conversionItems.firstIndex(where: { $0.id == id }) {
            conversionItems[index].videoCodec = codec
        }
    }

    func updateVideoResolution(for id: UUID, resolution: VideoResolution) {
        if let index = conversionItems.firstIndex(where: { $0.id == id }) {
            conversionItems[index].videoResolution = resolution
        }
    }

    func updateVideoQuality(for id: UUID, quality: VideoQuality) {
        if let index = conversionItems.firstIndex(where: { $0.id == id }) {
            conversionItems[index].videoQuality = quality
        }
    }

    func updateCustomVideoBitrate(for id: UUID, bitrate: Int?) {
        if let index = conversionItems.firstIndex(where: { $0.id == id }) {
            conversionItems[index].customVideoBitrate = bitrate
        }
    }

    func updateAudioBitrate(for id: UUID, bitrate: AudioBitrate) {
        if let index = conversionItems.firstIndex(where: { $0.id == id }) {
            conversionItems[index].audioBitrate = bitrate
        }
    }

    func updateMaxFileSize(for id: UUID, size: Int?) {
        if let index = conversionItems.firstIndex(where: { $0.id == id }) {
            conversionItems[index].maxFileSizeMB = size
        }
    }

    func updateSelectedAudioTrackID(for id: UUID, trackID: Int?) {
        if let index = conversionItems.firstIndex(where: { $0.id == id }) {
            conversionItems[index].selectedAudioTrackID = trackID
        }
    }

    func updateSelectedSubtitleTrackID(for id: UUID, trackID: Int?) {
        if let index = conversionItems.firstIndex(where: { $0.id == id }) {
            conversionItems[index].selectedSubtitleTrackID = trackID
        }
    }

    func updateCustomName(for id: UUID, name: String) {
        if let index = conversionItems.firstIndex(where: { $0.id == id }) {
            conversionItems[index].customName = name
        }
    }
}
