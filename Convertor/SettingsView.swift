import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("isDarkMode") private var isDarkMode = false

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "Settings"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)

            ScrollView {
                Form {
                    Section(header: Text(String(localized: "Appearance"))) {
                        Toggle(String(localized: "Dark Mode"), isOn: $isDarkMode)
                            .onChange(of: isDarkMode) { _, newValue in
                                NSApp.appearance =
                                    newValue
                                    ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
                            }
                    }

                    Section(header: Text(String(localized: "Default Audio Settings"))) {
                        Picker(String(localized: "Audio Format"), selection: $settings.defaultAudioFormat) {
                            ForEach([OutputFormat.aac, .alac], id: \.self) { format in
                                Text(format.rawValue.uppercased()).tag(format)
                            }
                        }

                        Picker(String(localized: "Audio Quality"), selection: $settings.audioQuality) {
                            ForEach(AudioQuality.allCases) { quality in
                                Text(quality.name).tag(quality)
                            }
                        }
                    }

                    Section(header: Text(String(localized: "Default Video Settings"))) {
                        Picker(String(localized: "Video Codec"), selection: $settings.defaultVideoCodec) {
                             ForEach(VideoCodec.allCases, id: \.self) { codec in
                                 Text(codec.rawValue).tag(codec)
                             }
                         }

                         Picker(String(localized: "Video Quality"), selection: $settings.videoQuality) {
                             ForEach(VideoQuality.allCases) { quality in
                                 Text(quality.name).tag(quality)
                             }
                         }
                     }

                    Section(header: Text(String(localized: "Performance"))) {
                        Stepper(
                            String(localized: "Maximum Concurrent Tasks: ") + "\(settings.maxConcurrentTasks)",
                            value: $settings.maxConcurrentTasks,
                            in: 1...16
                        )
                    }

                    Section(header: Text(String(localized: "Output Directory"))) {
                        Picker(String(localized: "Output Directory"), selection: $settings.outputDirectoryType) {
                            ForEach(OutputDirectoryType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }

                        if settings.outputDirectoryType == .custom {
                            HStack {
                                Text(
                                    settings.customOutputDirectory?.lastPathComponent
                                        ?? String(localized: "Select...")
                                )
                                .foregroundColor(.secondary)
                                Spacer()
                                Button(String(localized: "Select...")) {
                                    selectCustomFolder()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .padding()
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
        }
        .frame(width: 600, height: 650)
    }

    private func selectCustomFolder() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Output Folder"
        openPanel.message = "Select a folder where converted files will be saved."
        openPanel.showsHiddenFiles = false
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = true

        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                settings.customOutputDirectory = url
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: Settings())
    }
}
