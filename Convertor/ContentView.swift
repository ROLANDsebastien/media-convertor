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
        VStack {
            titleView
            dragDropArea
            fileListView
            Spacer()
            controlsView
        }
    }

    private var titleView: some View {
        ZStack {
            Text(String(localized: "Media Converter"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 10)
            HStack {
                Spacer()
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                }
                .padding(.bottom, 10)
            }
        }
        .padding(.horizontal)
    }

    private var dragDropArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(isTargeted ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.gray.opacity(0.4),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: [5, 10])
                )
                .frame(height: 150)
                .padding(.horizontal)

            VStack {
                Image(systemName: "square.and.arrow.down")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                Text(String(localized: "Drag and drop your media files here"))
                    .foregroundColor(.gray)
                Text(String(localized: "or click to select"))
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .onTapGesture {
                showFileImporter = true
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .padding(.bottom)
    }

    private var fileListView: some View {
        Group {
            if viewModel.conversionItems.isEmpty {
                Spacer()
                Text(String(localized: "No media to convert."))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(viewModel.conversionItems) { item in
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemName: iconName(for: item.status))
                                    .foregroundColor(iconColor(for: item.status))
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
                                        .onTapGesture(count: 2) {
                                            if item.status != .converting {
                                                renamingItemID = item.id
                                            }
                                        }
                                }
                                Spacer()
                                if item.status == .converting {
                                    ProgressView(value: item.progress)
                                        .frame(width: 100)
                                        .overlay(
                                            Text(String(format: "%.0f%%", item.progress * 100))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .offset(y: 12),  // Adjust this offset if needed
                                            alignment: .bottom
                                        )
                                } else {
                                    Text(statusText(for: item.status))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if item.status == .converting {
                                    Button(action: { viewModel.cancelConversion(for: item.id) }) {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Button(action: {
                                    selectedItem = item
                                }) {
                                    Image(systemName: "gear")
                                }
                                .buttonStyle(.borderless)
                                Button(action: {
                                    if let index = viewModel.conversionItems.firstIndex(where: {
                                        $0.id == item.id
                                    }) {
                                        viewModel.removeItems(at: IndexSet(integer: index))
                                    }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                                .disabled(item.status == .converting)
                            }
                            if item.status == .failed, let errorMessage = item.errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }

                        }
                        .padding(.vertical, 5)
                        .contextMenu {
                            Button(role: .destructive) {
                                if let index = viewModel.conversionItems.firstIndex(where: {
                                    $0.id == item.id
                                }) {
                                    viewModel.removeItems(at: IndexSet(integer: index))
                                }
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                    }

                }
                .listStyle(.inset)
                .frame(minHeight: 150, maxHeight: .infinity)
                .cornerRadius(10)
                .padding(.horizontal)
            }
        }
    }

    private var controlsView: some View {
        VStack {
            actionButtonsView
        }
        .padding(.vertical)
        .cornerRadius(15)
        .padding()
    }

    private var actionButtonsView: some View {
        HStack {
            if viewModel.isConverting {
                Button(String(localized: "Cancel All")) {
                    viewModel.cancelAllConversions()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
            } else {
                Button(String(localized: "Clear List")) {
                    viewModel.clearConversionItems()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
            }

            Spacer()

            Button(String(localized: "Convert All")) {
                viewModel.convertAllFiles()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.conversionItems.isEmpty || viewModel.isConverting)
        }
        .padding(.horizontal)
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
