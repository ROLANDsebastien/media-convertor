import SwiftUI

struct ItemSettingsView: View {
    let itemID: UUID
    @ObservedObject var viewModel: ConvertorViewModel
    @Environment(\.dismiss) var dismiss

    var item: ConversionItem? {
        viewModel.conversionItems.first(where: { $0.id == itemID })
    }

    var body: some View {
        VStack(spacing: 0) {
            if let item = item {
                if item.mediaType == .video {
                    TabView {
                        VideoFormatSettingsView(item: item, viewModel: viewModel)
                            .tabItem {
                                Label(String(localized: "Format"), systemImage: "film")
                            }
                        
                        TracksSettingsView(item: item, viewModel: viewModel)
                            .tabItem {
                                Label(String(localized: "Tracks"), systemImage: "waveform")
                            }
                        
                        AdvancedSettingsView(item: item, viewModel: viewModel)
                            .tabItem {
                                Label(String(localized: "Advanced"), systemImage: "slider.horizontal.3")
                            }
                    }
                } else {
                    AudioFormatSettingsView(item: item, viewModel: viewModel)
                }
            } else {
                Text(String(localized: "Item not found"))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 400, height: 300)
        .padding(item?.mediaType == .audio ? 20 : 10)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done")) {
                    dismiss()
                }
            }
        }
    }
}

private struct VideoFormatSettingsView: View {
    let item: ConversionItem
    @ObservedObject var viewModel: ConvertorViewModel
    
    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Codec"), selection: Binding(
                    get: { item.videoCodec },
                    set: { viewModel.updateVideoCodec(for: item.id, codec: $0) }
                )) {
                    ForEach(VideoCodec.allCases, id: \.self) { codec in
                        Text(codec.rawValue).tag(codec)
                    }
                }
                
                Picker(String(localized: "Resolution"), selection: Binding(
                    get: { item.videoResolution },
                    set: { viewModel.updateVideoResolution(for: item.id, resolution: $0) }
                )) {
                    ForEach(VideoResolution.allCases, id: \.self) { res in
                        Text(res.rawValue).tag(res)
                    }
                }
                
                Picker(String(localized: "Quality"), selection: Binding(
                    get: { item.videoQuality },
                    set: { viewModel.updateVideoQuality(for: item.id, quality: $0) }
                )) {
                    ForEach(VideoQuality.allCases, id: \.self) { quality in
                        Text(quality.name).tag(quality)
                    }
                }
            } header: {
                Text(String(localized: "Video Options"))
            }
        }
        .formStyle(.grouped)
    }
}

private struct TracksSettingsView: View {
    let item: ConversionItem
    @ObservedObject var viewModel: ConvertorViewModel
    
    var body: some View {
        Form {
            Section {
                if item.availableAudioTracks.isEmpty {
                    Text(String(localized: "No audio tracks available"))
                        .foregroundColor(.secondary)
                } else {
                    Picker(String(localized: "Audio"), selection: Binding(
                        get: { item.selectedAudioTrackID },
                        set: { viewModel.updateSelectedAudioTrackID(for: item.id, trackID: $0) }
                    )) {
                        ForEach(item.availableAudioTracks) { track in
                            Text("\(track.language.uppercased()) - \(track.title)")
                                .tag(track.id as Int?)
                        }
                    }
                }
                
                if item.availableSubtitleTracks.isEmpty {
                    Text(String(localized: "No subtitle tracks available"))
                        .foregroundColor(.secondary)
                } else {
                    Picker(String(localized: "Subtitle"), selection: Binding(
                        get: { item.selectedSubtitleTrackID },
                        set: { viewModel.updateSelectedSubtitleTrackID(for: item.id, trackID: $0) }
                    )) {
                        Text(String(localized: "None")).tag(nil as Int?)
                        ForEach(item.availableSubtitleTracks) { track in
                            Text("\(track.language.uppercased()) - \(track.title)")
                                .tag(track.id as Int?)
                        }
                    }
                }
            } header: {
                Text(String(localized: "Track Selection"))
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettingsView: View {
    let item: ConversionItem
    @ObservedObject var viewModel: ConvertorViewModel
    
    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Video Bitrate (kbps)"), value: Binding(
                    get: { item.customVideoBitrate ?? 0 },
                    set: { viewModel.updateCustomVideoBitrate(for: item.id, bitrate: $0 > 0 ? $0 : nil) }
                ), formatter: NumberFormatter())
                
                TextField(String(localized: "Max File Size (MB)"), value: Binding(
                    get: { item.maxFileSizeMB ?? 0 },
                    set: { viewModel.updateMaxFileSize(for: item.id, size: $0 > 0 ? $0 : nil) }
                ), formatter: NumberFormatter())
            } header: {
                Text(String(localized: "Custom Constraints"))
            } footer: {
                Text(String(localized: "Leave 0 to use automatic values based on quality settings."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AudioFormatSettingsView: View {
    let item: ConversionItem
    @ObservedObject var viewModel: ConvertorViewModel
    
    var body: some View {
        Form {
            Section {
                if item.outputFormat == .aac {
                    Picker(String(localized: "Bitrate"), selection: Binding(
                        get: { item.audioBitrate },
                        set: { viewModel.updateAudioBitrate(for: item.id, bitrate: $0) }
                    )) {
                        ForEach(AudioBitrate.allCases, id: \.self) { bitrate in
                            Text("\(bitrate.rawValue)k").tag(bitrate)
                        }
                    }
                } else {
                    Text(String(localized: "ALAC is lossless, no bitrate selection needed."))
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(String(localized: "Audio Options"))
            }
        }
        .formStyle(.grouped)
    }
}

struct ItemSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let mockItem = ConversionItem(
            sourceURL: URL(fileURLWithPath: "/test.mp4"), mediaType: .video)
        let mockVM = ConvertorViewModel(settings: Settings())
        mockVM.conversionItems = [mockItem]
        return ItemSettingsView(itemID: mockItem.id, viewModel: mockVM)
    }
}
