import Cocoa
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @Environment(\.dismiss) var dismiss
    @AppStorage("isDarkMode") private var isDarkMode = false

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings, isDarkMode: $isDarkMode)
                .tabItem {
                    Label(String(localized: "General"), systemImage: "gear")
                }
            
            AudioSettingsView(settings: settings)
                .tabItem {
                    Label(String(localized: "Audio"), systemImage: "music.note")
                }
            
            VideoSettingsView(settings: settings)
                .tabItem {
                    Label(String(localized: "Video"), systemImage: "film")
                }
        }
        .frame(width: 450, height: 300)
        .padding()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done")) {
                    dismiss()
                }
            }
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var settings: Settings
    @Binding var isDarkMode: Bool
    
    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Dark Mode"), isOn: $isDarkMode)
                    .onChange(of: isDarkMode) { _, newValue in
                        NSApp.appearance = newValue ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
                    }
            } header: {
                Text(String(localized: "Appearance"))
            }
            
            Section {
                Stepper(
                    String(localized: "Max Concurrent Tasks: ") + "\(settings.maxConcurrentTasks)",
                    value: $settings.maxConcurrentTasks,
                    in: 1...16
                )
            } header: {
                Text(String(localized: "Performance"))
            }
            
            Section {
                Picker(String(localized: "Location"), selection: $settings.outputDirectoryType) {
                    ForEach(OutputDirectoryType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                
                if settings.outputDirectoryType == .custom {
                    HStack {
                        Text(settings.customOutputDirectory?.lastPathComponent ?? String(localized: "Select..."))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose...")) {
                            selectCustomFolder()
                        }
                    }
                }
            } header: {
                Text(String(localized: "Output Directory"))
            }
        }
        .formStyle(.grouped)
    }
    
    private func selectCustomFolder() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Output Folder"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                settings.customOutputDirectory = url
            }
        }
    }
}

private struct AudioSettingsView: View {
    @ObservedObject var settings: Settings
    
    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Format"), selection: $settings.defaultAudioFormat) {
                    ForEach([OutputFormat.aac, .alac], id: \.self) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                
                Picker(String(localized: "Quality"), selection: $settings.audioQuality) {
                    ForEach(AudioQuality.allCases) { quality in
                        Text(quality.name).tag(quality)
                    }
                }
            } header: {
                Text(String(localized: "Default Audio Options"))
            }
        }
        .formStyle(.grouped)
    }
}

private struct VideoSettingsView: View {
    @ObservedObject var settings: Settings
    
    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Codec"), selection: $settings.defaultVideoCodec) {
                    ForEach(VideoCodec.allCases, id: \.self) { codec in
                        Text(codec.rawValue).tag(codec)
                    }
                }
                
                Picker(String(localized: "Quality"), selection: $settings.videoQuality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.name).tag(quality)
                    }
                }
            } header: {
                Text(String(localized: "Default Video Options"))
            }
        }
        .formStyle(.grouped)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: Settings())
    }
}
