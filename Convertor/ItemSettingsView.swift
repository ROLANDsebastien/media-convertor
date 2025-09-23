import SwiftUI

struct ItemSettingsView: View {
    let itemID: UUID
    @ObservedObject var viewModel: ConvertorViewModel
    @Environment(\.presentationMode) var presentationMode

    var item: ConversionItem? {
        viewModel.conversionItems.first(where: { $0.id == itemID })
    }

    var body: some View {
        VStack(spacing: 20) {
            if let item = item {
                Text(String(localized: "Settings for ") + item.customName)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)

                ScrollView {
                     Form {

                        if item.mediaType == .video {
                            Section(header: Text(String(localized: "Video Settings"))) {
                                Picker(
                                    String(localized: "Codec"),
                                    selection: Binding(
                                        get: { item.videoCodec },
                                        set: { viewModel.updateVideoCodec(for: item.id, codec: $0) }
                                    )
                                ) {
                                    ForEach(VideoCodec.allCases, id: \.self) { codec in
                                        Text(codec.rawValue).tag(codec)
                                    }
                                }

                                Picker(
                                    String(localized: "Resolution"),
                                    selection: Binding(
                                        get: { item.videoResolution },
                                        set: {
                                            viewModel.updateVideoResolution(
                                                for: item.id, resolution: $0)
                                        }
                                    )
                                ) {
                                    ForEach(VideoResolution.allCases, id: \.self) { res in
                                        Text(res.rawValue).tag(res)
                                    }
                                }

                                Picker(
                                    String(localized: "Quality"),
                                    selection: Binding(
                                        get: { item.videoQuality },
                                        set: {
                                            viewModel.updateVideoQuality(for: item.id, quality: $0)
                                        }
                                    )
                                ) {
                                    ForEach(VideoQuality.allCases, id: \.self) { quality in
                                        Text(quality.name).tag(quality)
                                    }
                                }
                            }

                            Section(header: Text(String(localized: "Tracks"))) {
                                if !item.availableAudioTracks.isEmpty {
                                    Picker(
                                        String(localized: "Audio Track"),
                                        selection: Binding(
                                            get: { item.selectedAudioTrackID },
                                            set: {
                                                viewModel.updateSelectedAudioTrackID(
                                                    for: item.id, trackID: $0)
                                            })
                                    ) {
                                        ForEach(item.availableAudioTracks) { track in
                                            Text("\(track.language.uppercased()) - \(track.title)")
                                                .tag(track.id as Int?)
                                        }
                                    }
                                }

                                if !item.availableSubtitleTracks.isEmpty {
                                    Picker(
                                        String(localized: "Subtitle Track"),
                                        selection: Binding(
                                            get: { item.selectedSubtitleTrackID },
                                            set: {
                                                viewModel.updateSelectedSubtitleTrackID(
                                                    for: item.id, trackID: $0)
                                            })
                                    ) {
                                        Text(String(localized: "None")).tag(nil as Int?)
                                        ForEach(item.availableSubtitleTracks) { track in
                                            Text("\(track.language.uppercased()) - \(track.title)")
                                                .tag(track.id as Int?)
                                        }
                                    }
                                }
                            }

                            Section(header: Text(String(localized: "Advanced"))) {
                                HStack {
                                    Text(String(localized: "Video Bitrate (kbps)"))
                                    Spacer()
                                    TextField(
                                        "",
                                        value: Binding(
                                            get: { item.customVideoBitrate ?? 0 },
                                            set: {
                                                viewModel.updateCustomVideoBitrate(
                                                    for: item.id, bitrate: $0 > 0 ? $0 : nil)
                                            }
                                        ), formatter: NumberFormatter()
                                    )
                                    .frame(width: 80)
                                }

                                HStack {
                                    Text(String(localized: "Max File Size (MB)"))
                                    Spacer()
                                    TextField(
                                        "",
                                        value: Binding(
                                            get: { item.maxFileSizeMB ?? 0 },
                                            set: {
                                                viewModel.updateMaxFileSize(
                                                    for: item.id, size: $0 > 0 ? $0 : nil)
                                            }
                                        ), formatter: NumberFormatter()
                                    )
                                    .frame(width: 80)
                                }
                            }
                        }

                        if item.outputFormat == .aac {
                            Section(header: Text(String(localized: "Audio Bitrate"))) {
                                Picker(
                                    String(localized: "Bitrate"),
                                    selection: Binding(
                                        get: { item.audioBitrate },
                                        set: {
                                            viewModel.updateAudioBitrate(for: item.id, bitrate: $0)
                                        }
                                    )
                                ) {
                                    ForEach(AudioBitrate.allCases, id: \.self) { bitrate in
                                        Text("\(bitrate.rawValue)k").tag(bitrate)
                                    }
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .padding()
                    .disabled(item.status == .converting)
                }

                HStack {
                    Spacer()
                    Button(String(localized: "Done")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.horizontal)
                .padding(.bottom)
            } else {
                Text("Item not found")
            }
        }
        .frame(width: 600, height: item?.mediaType == .audio ? 350 : 650)
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
