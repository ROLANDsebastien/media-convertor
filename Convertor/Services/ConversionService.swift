import Combine
import Foundation

// MARK: - MediaInfo Service

enum MediaInfoError: Error, LocalizedError {
    case ffmpegNotFound
    case ffmpegFailed(String)
    case trackParsingFailed

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg executable not found."
        case .ffmpegFailed(let details):
            return "Failed to get media information with ffmpeg: \(details)"
        case .trackParsingFailed:
            return "Failed to parse track information from ffmpeg output."
        }
    }
}

class MediaInfoService {

    func getMediaInfo(for fileURL: URL) async throws -> (
        audio: [AudioTrack], subtitles: [SubtitleTrack]
    ) {
        guard let ffmpegURL = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) else {
            throw MediaInfoError.ffmpegNotFound
        }
        return try await runFFmpegForInfo(executableURL: ffmpegURL, fileURL: fileURL)
    }

    private func runFFmpegForInfo(executableURL: URL, fileURL: URL) async throws -> (
        audio: [AudioTrack], subtitles: [SubtitleTrack]
    ) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-i", fileURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0
                && !errorOutput.contains("At least one output file must be specified")
            {
                // ffmpeg returns status 1 when just getting info, which is expected.
                // We only throw an error if the status is not 1 OR if the expected info message isn't there.
                if process.terminationStatus != 1 {
                    throw MediaInfoError.ffmpegFailed(errorOutput)
                }
            }

            return parseTracks(from: errorOutput)

        } catch {
            throw MediaInfoError.ffmpegFailed(error.localizedDescription)
        }
    }

    private func parseTracks(from ffmpegOutput: String) -> (
        audio: [AudioTrack], subtitles: [SubtitleTrack]
    ) {
        var audioTracks: [AudioTrack] = []
        var subtitleTracks: [SubtitleTrack] = []

        // Regex to capture stream index, language, and title for audio and subtitle tracks
        let regex = try! NSRegularExpression(
            pattern: "Stream #0:(\\d+)(?:\\((.*?)\\))?: (Audio|Subtitle): (.*)")

        let lines = ffmpegOutput.components(separatedBy: .newlines)
        var streamMetadata: [Int: [String: String]] = [:]
        var currentStreamIndex: Int? = nil

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.starts(with: "Stream #") {
                let nsRange = NSRange(
                    trimmedLine.startIndex..<trimmedLine.endIndex, in: trimmedLine)
                if let match = regex.firstMatch(in: trimmedLine, options: [], range: nsRange) {
                    let indexRange = Range(match.range(at: 1), in: trimmedLine)!
                    let index = Int(String(trimmedLine[indexRange]))!

                    let langRange = Range(match.range(at: 2), in: trimmedLine)
                    let lang = langRange.map { String(trimmedLine[$0]) } ?? "und"

                    let typeRange = Range(match.range(at: 3), in: trimmedLine)!
                    let type = String(trimmedLine[typeRange])

                    currentStreamIndex = index
                    streamMetadata[index] = ["language": lang]

                    if type == "Audio" {
                        audioTracks.append(AudioTrack(index: index, language: lang, title: ""))
                    } else if type == "Subtitle" {
                        subtitleTracks.append(
                            SubtitleTrack(index: index, language: lang, title: ""))
                    }
                }
            } else if currentStreamIndex != nil, trimmedLine.starts(with: "Metadata:") {
                // Subsequent lines contain metadata for the last matched stream
            } else if let streamIndex = currentStreamIndex,
                let colonRange = trimmedLine.range(of: ":")
            {
                let key = String(trimmedLine[..<colonRange.lowerBound]).trimmingCharacters(
                    in: .whitespaces)
                let value = String(trimmedLine[colonRange.upperBound...]).trimmingCharacters(
                    in: .whitespaces)
                if key == "title" {
                    if let i = audioTracks.firstIndex(where: { $0.index == streamIndex }) {
                        audioTracks[i].title = value
                    } else if let i = subtitleTracks.firstIndex(where: { $0.index == streamIndex })
                    {
                        subtitleTracks[i].title = value
                    }
                }
            }
        }

        return (audioTracks, subtitleTracks)
    }
}

// MARK: - Conversion Service

enum ConversionError: Error, LocalizedError {
    case ffmpegNotFound
    case ffmpegNotExecutable
    case inputFileDoesNotExist
    case inputFileNotReadable
    case cannotCreateOutputDirectory(Error)
    case outputDirectoryNotAccessible
    case ffmpegProcessFailed(Int32, String)
    case ffmpegProcessStartFailed(Error)
    case durationParsingFailed

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound: return String(localized: "FFmpeg executable not found.")
        case .ffmpegNotExecutable: return String(localized: "FFmpeg executable is not executable.")
        case .inputFileDoesNotExist: return String(localized: "Input file does not exist.")
        case .inputFileNotReadable: return String(localized: "Input file is not readable.")
        case .cannotCreateOutputDirectory(let error):
            return String(localized: "Cannot create output directory: ")
                + error.localizedDescription
        case .outputDirectoryNotAccessible:
            return String(
                localized:
                    "Output directory is not accessible. Please select a different directory in settings."
            )
        case .ffmpegProcessFailed(let code, let stderr):
            return String(
                format: NSLocalizedString(
                    "FFmpeg process failed with exit code %d: \n%@", comment: ""), code, stderr)
        case .ffmpegProcessStartFailed(let error):
            return String(localized: "Failed to start FFmpeg process: ")
                + error.localizedDescription
        case .durationParsingFailed: return String(localized: "Could not parse media duration.")
        }
    }
}

class ConversionService {

    private let languageCodeMapping: [String: String] = [
        "fra": "French", "fre": "French",
        "eng": "English",
        "spa": "Spanish", "esl": "Spanish",
        "deu": "German", "ger": "German",
        "jpn": "Japanese",
        "ita": "Italian",
        "por": "Portuguese",
        "rus": "Russian",
        "zho": "Chinese", "chi": "Chinese",
    ]

    func convert(
        item: ConversionItem, outputDirectory: URL?,
        progressHandler: @escaping (Double) -> Void
    ) -> AnyPublisher<URL, Error> {
        var process: Process?

        return Future<URL, Error> { [self] promise in
            Task(priority: .userInitiated) {
                do {
                    guard let ffmpegURL = Bundle.main.url(forResource: "ffmpeg", withExtension: nil)
                    else {
                        promise(.failure(ConversionError.ffmpegNotFound))
                        return
                    }

                    guard FileManager.default.isExecutableFile(atPath: ffmpegURL.path) else {
                        promise(.failure(ConversionError.ffmpegNotExecutable))
                        return
                    }

                    guard FileManager.default.fileExists(atPath: item.sourceURL.path) else {
                        promise(.failure(ConversionError.inputFileDoesNotExist))
                        return
                    }

                    guard FileManager.default.isReadableFile(atPath: item.sourceURL.path) else {
                        promise(.failure(ConversionError.inputFileNotReadable))
                        return
                    }

                    let outputURL = self.getOutputURL(
                        for: item.sourceURL, outputFormat: item.outputFormat,
                        outputDirectory: outputDirectory)
                    let outputDir = outputURL.deletingLastPathComponent()

                    print("📂 Output directory: \(outputDir.path)")
                    print("📄 Output file: \(outputURL.path)")

                    // Start accessing security scoped resources
                    let inputDidStartAccessing = item.sourceURL
                        .startAccessingSecurityScopedResource()
                    let outputDidStartAccessing = outputDir.startAccessingSecurityScopedResource()
                    defer {
                        if inputDidStartAccessing {
                            item.sourceURL.stopAccessingSecurityScopedResource()
                        }
                        if outputDidStartAccessing {
                            outputDir.stopAccessingSecurityScopedResource()
                        }
                    }

                    // Check if output directory is accessible
                    if !FileManager.default.isWritableFile(atPath: outputDir.path) {
                        print("❌ ERROR: Output directory not writable: \(outputDir.path)")
                        throw ConversionError.outputDirectoryNotAccessible
                    }
                    print("✅ Output directory is writable: \(outputDir.path)")

                    try FileManager.default.createDirectory(
                        at: outputDir, withIntermediateDirectories: true)

                    let duration = try await self.getDuration(
                        for: item.sourceURL, ffmpegURL: ffmpegURL)
                    let hasPicture =
                        item.mediaType == .audio
                        ? self.checkForAttachedPicture(in: item.sourceURL, ffmpegURL: ffmpegURL)
                        : false
                    
                    // Variable pour stocker l'URL de la miniature temporaire (pour nettoyage ultérieur)
                    var temporaryThumbnailURL: URL? = nil

                    var arguments: [String]
                    if item.mediaType == .audio {
                        if hasPicture {
                            arguments = [
                                "-i", item.sourceURL.path,
                                "-map_metadata", "0",
                                "-map", "0:a",
                                "-map", "0:v",
                                "-c:a", item.outputFormat == .aac ? "aac" : "alac",
                                "-c:v", "copy",
                                "-disposition:v", "attached_pic",
                            ]
                        } else {
                            arguments = [
                                "-i", item.sourceURL.path,
                                "-map_metadata", "0",
                                "-vn",
                                "-c:a", item.outputFormat == .aac ? "aac" : "alac",
                            ]
                        }

                        if item.outputFormat == .aac {
                            arguments.append(contentsOf: ["-b:a", "\(item.audioBitrate.rawValue)k"])
                        }
                    } else if item.mediaType == .video {
                        // Video conversion
                        print("🎬 Starting video conversion for \(item.sourceURL.lastPathComponent)")
                        
                        if item.videoCodec == .hevcCopy {
                            // Pour la conversion passthrough, on génère d'abord une miniature
                            // pour que macOS/QuickLook puisse afficher un aperçu
                            let thumbnailURL = outputURL.deletingLastPathComponent()
                                .appendingPathComponent("thumb_\(UUID().uuidString).jpg")
                            temporaryThumbnailURL = thumbnailURL
                            
                            // Extraire une frame à 10% de la durée comme miniature
                            let thumbnailTime = duration * 0.1
                            let thumbnailProcess = Process()
                            thumbnailProcess.executableURL = ffmpegURL
                            thumbnailProcess.arguments = [
                                "-ss", String(format: "%.2f", thumbnailTime),
                                "-i", item.sourceURL.path,
                                "-vframes", "1",
                                "-q:v", "2",
                                "-y",
                                thumbnailURL.path
                            ]
                            
                            do {
                                try thumbnailProcess.run()
                                thumbnailProcess.waitUntilExit()
                            } catch {
                                print("⚠️ Warning: Could not generate thumbnail: \(error.localizedDescription)")
                            }
                            
                            // Vérifier si la miniature a été créée
                            let hasThumbnail = FileManager.default.fileExists(atPath: thumbnailURL.path)
                            
                            if hasThumbnail {
                                // Conversion avec miniature intégrée
                                arguments = [
                                    "-i", item.sourceURL.path,
                                    "-i", thumbnailURL.path,
                                    "-map", "0:v",
                                    "-map", "1:v",
                                    "-c:v:0", "copy",
                                    "-c:v:1", "mjpeg",
                                    "-disposition:v:0", "default",
                                    "-disposition:v:1", "attached_pic",
                                    "-tag:v:0", "hvc1",
                                    "-movflags", "+faststart"
                                ]
                            } else {
                                // Fallback sans miniature
                                arguments = [
                                    "-i", item.sourceURL.path,
                                    "-map", "0:v",
                                    "-c:v", "copy",
                                    "-tag:v", "hvc1",
                                    "-movflags", "+faststart"
                                ]
                            }
                            
                            if let audioTrackID = item.selectedAudioTrackID {
                                arguments.append(contentsOf: ["-map", "0:\(audioTrackID)", "-c:a", "copy"])
                            } else {
                                arguments.append(contentsOf: ["-map", "0:a?", "-c:a", "copy"])
                            }
                        } else {
                            var videoBitrate = item.customVideoBitrate ?? item.videoQuality.bitrate
                            if let maxSize = item.maxFileSizeMB, item.customVideoBitrate == nil {
                                // Calculate adaptive bitrate to fit in max size (only if not custom)
                                let targetBits = Double(maxSize * 1024 * 1024 * 8)  // bits
                                let audioBitsPerSecond = Double(item.audioBitrate.rawValue * 1000)
                                let availableBitsForVideo = targetBits - (audioBitsPerSecond * duration)
                                if availableBitsForVideo > 0 {
                                    videoBitrate = Int(availableBitsForVideo / duration / 1000)  // kbps
                                    videoBitrate = max(videoBitrate, 500)  // minimum 500kbps
                                }
                            }
                            arguments = [
                                "-i", item.sourceURL.path,
                                "-map", "0:v",  // Map video stream
                                "-c:v", item.videoCodec.ffmpegCodec,
                                "-b:v", "\(videoBitrate)k",
                                "-vf", "scale=-2:\(item.videoResolution.height)",
                                "-c:a", "aac",
                                "-b:a", "\(item.audioBitrate.rawValue)k",
                                "-movflags", "+faststart",
                            ]
                            if item.videoCodec == .h265 {
                                arguments.append(contentsOf: ["-tag:v", "hvc1"])
                            }
                            if let audioTrackID = item.selectedAudioTrackID {
                                arguments.append(contentsOf: ["-map", "0:\(audioTrackID)"])
                            } else {
                                // If no specific audio track is selected, map the first audio stream by default.
                                // The '?’ makes it optional, so ffmpeg won't fail if there's no audio.
                                arguments.append(contentsOf: ["-map", "0:a?"])
                            }
                        }
                        
                        if let subtitleTrackID = item.selectedSubtitleTrackID {
                            var subtitleArgs = [
                                "-map", "0:\(subtitleTrackID)",
                                "-c:s", "mov_text",
                            ]

                            if let subtitle = item.availableSubtitleTracks.first(where: {
                                $0.index == subtitleTrackID
                            }) {
                                // Set language metadata if available
                                if !subtitle.language.isEmpty, subtitle.language != "und" {
                                    subtitleArgs.append(contentsOf: [
                                        "-metadata:s:s:0", "language=\(subtitle.language)",
                                    ])
                                }

                                // Set title metadata
                                if !subtitle.title.isEmpty {
                                    subtitleArgs.append(contentsOf: [
                                        "-metadata:s:s:0", "title=\(subtitle.title)",
                                    ])
                                }
                            }
                            arguments.append(contentsOf: subtitleArgs)
                        }
                    } else {
                        // Audio conversion
                        print("🎵 Starting audio conversion for \(item.sourceURL.lastPathComponent)")
                        if hasPicture {
                            arguments = [
                                "-i", item.sourceURL.path,
                                "-map_metadata", "0",
                                "-map", "0:a",
                                "-map", "0:v",
                                "-c:a", item.outputFormat == .aac ? "aac" : "alac",
                                "-c:v", "copy",
                                "-disposition:v", "attached_pic",
                            ]
                        } else {
                            arguments = [
                                "-i", item.sourceURL.path,
                                "-map_metadata", "0",
                                "-vn",
                                "-c:a", item.outputFormat == .aac ? "aac" : "alac",
                            ]
                        }

                        if item.outputFormat == .aac {
                            arguments.append(contentsOf: ["-b:a", "\(item.audioBitrate.rawValue)k"])
                        }
                    }

                    arguments.append(contentsOf: ["-y", outputURL.path])

                    process = Process()
                    process!.executableURL = ffmpegURL
                    process!.arguments = arguments

                    let errorPipe = Pipe()
                    process!.standardError = errorPipe

                    let errorFileHandle = errorPipe.fileHandleForReading
                    errorFileHandle.readabilityHandler = { handle in
                        let data = handle.availableData
                        if let output = String(data: data, encoding: .utf8) {
                            if let progress = self.parseProgress(from: output, duration: duration) {
                                progressHandler(progress)
                            }
                        }
                    }

                    process!.terminationHandler = { process in
                        errorFileHandle.readabilityHandler = nil
                        
                        // Nettoyer la miniature temporaire si elle existe
                        if let thumbURL = temporaryThumbnailURL {
                            try? FileManager.default.removeItem(at: thumbURL)
                            print("🧹 Cleaned up temporary thumbnail")
                        }
                        
                        print(
                            "🔚 FFmpeg process terminated with status: \(process.terminationStatus)")
                        if process.terminationStatus == 255 {
                            // Cancelled (SIGTERM = 255), don't report as error
                            print("ℹ️ FFmpeg process cancelled")
                            return
                        }
                        if process.terminationStatus == 0 {
                            // Vérifier si le fichier de sortie existe réellement
                            if FileManager.default.fileExists(atPath: outputURL.path) {
                                print("✅ SUCCESS: Output file created at: \(outputURL.path)")
                                let attributes = try? FileManager.default.attributesOfItem(
                                    atPath: outputURL.path)
                                if let fileSize = attributes?[.size] as? Int64 {
                                    print("📁 File size: \(fileSize) bytes")
                                }
                                promise(.success(outputURL))
                            } else {
                                print(
                                    "❌ ERROR: FFmpeg reported success but output file not found at: \(outputURL.path)"
                                )
                                // Lister le contenu du répertoire de sortie
                                let outputDir = outputURL.deletingLastPathComponent()
                                if let contents = try? FileManager.default.contentsOfDirectory(
                                    at: outputDir, includingPropertiesForKeys: nil)
                                {
                                    print(
                                        "📂 Output directory contents: \(contents.map { $0.lastPathComponent })"
                                    )
                                }
                                promise(
                                    .failure(
                                        ConversionError.ffmpegProcessFailed(
                                            0, "Output file not created")))
                            }
                        } else {
                            let errorData = errorFileHandle.readDataToEndOfFile()
                            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                            print("❌ FFmpeg failed with exit code: \(process.terminationStatus)")
                            print("❌ FFmpeg error output: \(errorOutput)")
                            promise(
                                .failure(
                                    ConversionError.ffmpegProcessFailed(
                                        process.terminationStatus, errorOutput)))
                        }
                    }

                    print("FFmpeg Path: \(ffmpegURL.path)")
                    print("FFmpeg Arguments: \(arguments.joined(separator: " "))")
                    process!.launch()
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .handleEvents(receiveCancel: {
            print("🛑 Conversion cancelled, terminating FFmpeg process")
            process?.terminate()
            // Wait a bit for clean termination
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if process?.isRunning == true {
                    process?.interrupt()
                }
            }
        })
        .eraseToAnyPublisher()
    }

    private func getDuration(for fileURL: URL, ffmpegURL: URL) async throws -> Double {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = ["-i", fileURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        let lines = errorOutput.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("Duration:") {
                let components = line.components(separatedBy: "Duration: ")
                if components.count > 1 {
                    let timeString = components[1].components(separatedBy: ",")[0]
                        .trimmingCharacters(in: .whitespaces)
                    let timeComponents = timeString.components(separatedBy: ":")
                    if timeComponents.count == 3 {
                        let hours = Double(timeComponents[0]) ?? 0
                        let minutes = Double(timeComponents[1]) ?? 0
                        let seconds = Double(timeComponents[2]) ?? 0
                        return hours * 3600 + minutes * 60 + seconds
                    }
                }
            }
        }

        throw ConversionError.durationParsingFailed
    }

    private nonisolated func parseProgress(from output: String, duration: Double) -> Double? {
        let lines = output.components(separatedBy: .init(charactersIn: "\r\n"))
        if let progressLine = lines.last(where: { $0.contains("time=") }) {
            let components = progressLine.components(separatedBy: "time=")
            if components.count > 1 {
                let timeString = components[1].components(separatedBy: " ")[0]
                let timeComponents = timeString.components(separatedBy: ":")
                if timeComponents.count == 3 {
                    let hours = Double(timeComponents[0]) ?? 0
                    let minutes = Double(timeComponents[1]) ?? 0
                    let seconds = Double(timeComponents[2]) ?? 0
                    let currentTime = hours * 3600 + minutes * 60 + seconds
                    if duration > 0 {
                        return min(max(currentTime / duration, 0), 1)
                    }
                }
            }
        }
        return nil
    }

    private nonisolated func checkForAttachedPicture(in inputURL: URL, ffmpegURL: URL) -> Bool {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = ["-i", inputURL.path, "-map", "0:v?", "-f", "null", "-"]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if let errorData = try? errorPipe.fileHandleForReading.readToEnd(),
                let errorOutput = String(data: errorData, encoding: .utf8)
            {
                return errorOutput.contains("Stream #0:") && errorOutput.contains("Video:")
            }
        } catch {
            print("❌ ERROR: Cannot check for attached picture: \(error.localizedDescription)")
        }

        return false
    }

    private nonisolated func getOutputURL(
        for fileURL: URL, outputFormat: OutputFormat, outputDirectory: URL?
    )
        -> URL
    {
        let directory =
            outputDirectory
            ?? URL(
                fileURLWithPath: (ProcessInfo.processInfo.environment["HOME"]
                    ?? "/Users/\(NSUserName())")
            ).appendingPathComponent("Documents")
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension: String
        switch outputFormat {
        case .aac, .alac:
            fileExtension = "m4a"
        case .mp4:
            fileExtension = "mp4"
        }
        let outputFilename = "\(filename).\(fileExtension)"
        let outputURL = directory.appendingPathComponent(outputFilename)

        // If output path is the same as input path, add suffix to avoid overwriting
        if outputURL.standardized.path.compare(fileURL.standardized.path, options: .caseInsensitive)
            == .orderedSame
        {
            let newOutputFilename = "\(filename)_converted.\(fileExtension)"
            return directory.appendingPathComponent(newOutputFilename)
        }

        return outputURL
    }
}
