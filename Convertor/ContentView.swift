import Cocoa
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: ConvertorViewModel
    @EnvironmentObject var settings: Settings
    @State private var isTargeted: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var showSettings = false
    @State private var renamingItemID: UUID? = nil
    @State private var selectedItem: ConversionItem? = nil

    var body: some View {
        ZStack {
            mainContent
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: true
        ) { result in
            handleFileImporterResult(result)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
        .sheet(item: $selectedItem) { item in
            ItemSettingsView(itemID: item.id, viewModel: viewModel)
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            dragDropArea
            fileListView
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showFileImporter = true }) {
                    Label(String(localized: "Add Files"), systemImage: "plus")
                }
                .help(String(localized: "Add media files to convert"))
                
                Button(action: { viewModel.convertAllFiles() }) {
                    Label(String(localized: "Convert All"), systemImage: "play.fill")
                }
                .disabled(viewModel.conversionItems.isEmpty || viewModel.isConverting)
                .help(String(localized: "Start converting all files"))
                
                if viewModel.isConverting {
                    Button(action: { viewModel.cancelAllConversions() }) {
                        Label(String(localized: "Cancel All"), systemImage: "stop.fill")
                    }
                    .help(String(localized: "Cancel all conversions"))
                } else {
                    Button(action: { viewModel.clearConversionItems() }) {
                        Label(String(localized: "Clear"), systemImage: "trash")
                    }
                    .disabled(viewModel.conversionItems.isEmpty)
                    .help(String(localized: "Clear all files from list"))
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: { showSettings = true }) {
                    Label(String(localized: "Settings"), systemImage: "gear")
                }
                .help(String(localized: "Open settings"))
            }
        }
    }



    private var dragDropArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.gray.opacity(0.3),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [5, 5])
                )
                .frame(height: 80)

            HStack(spacing: 12) {
                Image(systemName: "arrow.down.doc")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(String(localized: "Drag files here"))
                    .foregroundColor(.secondary)
                Text("•")
                    .foregroundColor(.secondary)
                Button(String(localized: "Browse...")) {
                    showFileImporter = true
                }
                .buttonStyle(.link)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var fileListView: some View {
        Group {
            if viewModel.conversionItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(String(localized: "No media to convert."))
                        .foregroundColor(.secondary)
                        .font(.title3)
                    Text(String(localized: "Drag files or click Browse to get started"))
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.conversionItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: iconName(for: item.status))
                                    .foregroundColor(iconColor(for: item.status))
                                    .font(.body)
                                    .frame(width: 20)
                                
                                if renamingItemID == item.id {
                                    TextField(
                                        String(localized: "File name"),
                                        text: Binding(
                                            get: { item.customName },
                                            set: { newValue in
                                                viewModel.updateCustomName(
                                                    for: item.id, name: newValue)
                                            }
                                        ),
                                        onCommit: {
                                            renamingItemID = nil
                                        }
                                    )
                                    .textFieldStyle(.roundedBorder)
                                } else {
                                    Text(item.customName)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if item.status != .converting {
                                    Text(statusText(for: item.status))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if item.status == .converting {
                                    Text(String(format: "%.0f%%", item.progress * 100))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                    
                                    Button(action: { viewModel.cancelConversion(for: item.id) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(String(localized: "Cancel conversion"))
                                }
                            }
                            
                            if item.status == .converting {
                                ProgressView(value: item.progress)
                                    .progressViewStyle(.linear)
                                    .tint(.accentColor)
                            }
                            
                            if item.status == .failed, let errorMessage = item.errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            if item.status != .converting {
                                Button(action: {
                                    renamingItemID = item.id
                                }) {
                                    Label(String(localized: "Rename"), systemImage: "pencil")
                                }
                                
                                Button(action: {
                                    selectedItem = item
                                }) {
                                    Label(String(localized: "Settings"), systemImage: "gear")
                                }
                                
                                Divider()
                            }
                            
                            if item.status == .completed {
                                Button(action: {
                                    if let outputURL = item.outputURL {
                                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                                    }
                                }) {
                                    Label(String(localized: "Show in Finder"), systemImage: "folder")
                                }
                                
                                Divider()
                            }
                            
                            if item.status == .converting {
                                Button(action: {
                                    viewModel.cancelConversion(for: item.id)
                                }) {
                                    Label(String(localized: "Cancel"), systemImage: "xmark.circle")
                                }
                            } else {
                                Button(role: .destructive, action: {
                                    if let index = viewModel.conversionItems.firstIndex(where: {
                                        $0.id == item.id
                                    }) {
                                        viewModel.removeItems(at: IndexSet(integer: index))
                                    }
                                }) {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .padding(.horizontal)
            }
        }
    }



    // MARK: - Helper Functions

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { (url, error) in
                    if let url = url {
                        DispatchQueue.main.async {
                            viewModel.addFile(url: url)
                        }
                    }
                }
            }
        }
    }

    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                viewModel.addFile(url: url)
            }
        case .failure(let error):
            print(String(localized: "File selection error: ") + error.localizedDescription)
        }
    }

    private func iconName(for status: ConversionStatus) -> String {
        switch status {
        case .pending: return "hourglass"
        case .converting: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    private func iconColor(for status: ConversionStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .converting: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private func statusText(for status: ConversionStatus) -> String {
        switch status {
        case .pending: return String(localized: "Pending")
        case .converting: return String(localized: "Converting...")
        case .completed: return String(localized: "Completed")
        case .failed: return String(localized: "Failed")
        case .cancelled: return String(localized: "Cancelled")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = Settings()
        let viewModel = ConvertorViewModel(settings: settings)
        ContentView(viewModel: viewModel)
            .environmentObject(settings)
    }
}
