import SwiftUI
import PDFKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF", images = "Images and data", csv = "Shot list (CSV)"
    var id: String { rawValue }
}

struct ExportView: View {
    @Binding var document: StoryboardDocument
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID>
    @State private var options: StoryboardExportOptions
    @State private var paperChoice: String
    @State private var format = ExportFormat.pdf
    @State private var preview: Data?
    @State private var preparing = false
    @State private var exporting = false
    @State private var error = ""
    @State private var exportedURL: URL?
    @AppStorage("interfaceLanguage") private var interfaceLanguage = ""
    init(document: Binding<StoryboardDocument>) {
        _document = document
        _selected = State(initialValue: Set(document.wrappedValue.scenes.map(\.id)))
        var value = StoryboardExportOptions()
        let defaults = UserDefaults.standard
        _paperChoice = State(initialValue: defaults.string(forKey: "exportPaper") ?? "")
        value.paper = ExportPaper(rawValue: defaults.string(forKey: "exportPaper") ?? "") ?? .letter
        value.orientation = ExportOrientation(rawValue: defaults.string(forKey: "exportOrientation") ?? "") ?? .landscape
        value.layout = ExportLayout(rawValue: defaults.integer(forKey: "exportLayout")) ?? .six
        _options = State(initialValue: value)
    }
    private var previewKey: String { "\(interfaceLanguage)-\(paperChoice)-\(format.rawValue)-\(options)-" + selected.map(\.uuidString).sorted().joined() }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(L("Export storyboard")).font(.title2.bold()); Spacer(); Button(L("Done")) { dismiss() }.disabled(exporting) }.padding(20)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(L("Format"), selection: $format) { ForEach(ExportFormat.allCases) { Text(L($0.rawValue)).tag($0) } }
                    if format == .pdf {
                        Picker(L("Paper"), selection: $paperChoice) {
                            Text(L("Choose paper size")).tag("")
                            ForEach(ExportPaper.allCases) { Text(L($0.rawValue)).tag($0.rawValue) }
                        }.onChange(of: paperChoice) { _, value in if let paper = ExportPaper(rawValue: value) { options.paper = paper } }
                        Picker(L("Orientation"), selection: $options.orientation) { ForEach(ExportOrientation.allCases) { Text(L($0.rawValue)).tag($0) } }
                        Picker(L("Layout"), selection: $options.layout) { ForEach(ExportLayout.allCases) { Text(L($0.label)).tag($0) } }
                        Toggle(L("Include descriptions"), isOn: $options.includeDescriptions)
                        Toggle(L("Include production and shot details"), isOn: $options.includeMetadata)
                        Toggle(L("Start each scene on a new page"), isOn: $options.newPagePerScene)
                    }
                    Toggle(L("Include shots without images"), isOn: $options.includeUnrendered)
                    HStack {
                        Text(L("Scenes")).font(.headline); Spacer()
                        Button(selected.count == document.scenes.count ? L("None") : L("All")) {
                            selected = selected.count == document.scenes.count ? [] : Set(document.scenes.map(\.id))
                        }.buttonStyle(.borderless)
                    }
                    List(document.scenes) { scene in
                        Toggle(isOn: Binding(get: { selected.contains(scene.id) }, set: { if $0 { selected.insert(scene.id) } else { selected.remove(scene.id) } })) {
                            VStack(alignment: .leading) {
                                Text(scene.title).lineLimit(2)
                                Text(L("Shots: %@", String(document.frames.filter { $0.sceneID == scene.id }.count))).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.listStyle(.inset).frame(minHeight: 130)
                }.padding(20).frame(width: 340).disabled(exporting)
                Divider()
                Group {
                    if format == .pdf {
                        if paperChoice.isEmpty { ContentUnavailableView(L("Choose a paper size"), systemImage: "doc") }
                        else if preparing { ProgressView(L("Preparing preview…")) }
                        else if let preview { PDFPreview(data: preview) }
                        else { ContentUnavailableView(L("Choose scenes to preview"), systemImage: "doc.richtext") }
                    } else {
                        ContentUnavailableView(format == .images ? L("Images and scene data") : L("Shot list"), systemImage: format == .images ? "photo.stack" : "tablecells", description: Text(format == .images ? L("PNG images, a CSV shot list, and JSON scene data.") : L("Scene and shot details for spreadsheet apps.")))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                if !error.isEmpty { Text(error).font(.callout).foregroundStyle(.red).lineLimit(3) }
                if let exportedURL { Button(L("Show export")) { NSWorkspace.shared.activateFileViewerSelecting([exportedURL]) } }
                Spacer()
                if exporting { ProgressView().controlSize(.small) }
                Button(L("Export…"), action: export).buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty || exporting || (format == .pdf && (paperChoice.isEmpty || preparing || preview == nil)))
            }.padding(18)
        }.frame(width: 1000, height: 700)
        .task(id: previewKey) {
            guard format == .pdf, !paperChoice.isEmpty else { preparing = false; preview = nil; return }
            preparing = true; preview = nil; error = ""
            let snapshot = document, scenes = selected, settings = options
            let work = Task.detached(priority: .userInitiated) { try StoryboardExporter.pdf(document: snapshot, scenes: scenes, options: settings) }
            do {
                let data = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation(); preview = data; preparing = false
            } catch is CancellationError {} catch { self.error = error.localizedDescription; preparing = false }
        }
    }
    private func export() {
        let snapshot = document, scenes = selected, includeUnrendered = options.includeUnrendered
        if format == .images {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.canCreateDirectories = true; panel.prompt = L("Export Here")
            panel.begin { result in
                guard result == .OK, let parent = panel.url else { return }
                var folder = parent.appendingPathComponent(StoryboardExporter.safeName(snapshot.title) + "-Export")
                var suffix = 2
                while FileManager.default.fileExists(atPath: folder.path) {
                    folder = parent.appendingPathComponent(StoryboardExporter.safeName(snapshot.title) + "-Export-\(suffix)"); suffix += 1
                }
                let target = folder; exporting = true; error = ""
                Task {
                    do {
                        try await Task.detached { try StoryboardExporter.bundle(document: snapshot, scenes: scenes, to: target, includeUnrendered: includeUnrendered) }.value
                        exportedURL = target
                    } catch { self.error = error.localizedDescription }
                    exporting = false
                }
            }
        } else {
            let isPDF = format == .pdf
            let panel = NSSavePanel(); panel.allowedContentTypes = isPDF ? [.pdf] : [.commaSeparatedText]
            panel.nameFieldStringValue = StoryboardExporter.safeName(snapshot.title) + (isPDF ? ".pdf" : ".csv")
            let pdfData = preview
            panel.begin { result in
                guard result == .OK, let url = panel.url else { return }
                exporting = true; error = ""
                Task {
                    do {
                        try await Task.detached {
                            let data = try isPDF ? (pdfData ?? Data()) : StoryboardExporter.csv(document: snapshot, scenes: scenes, includeUnrendered: includeUnrendered)
                            try data.write(to: url, options: .atomic)
                        }.value
                        exportedURL = url
                    } catch { self.error = L("The export couldn’t be saved.  Choose another destination.") }
                    exporting = false
                }
            }
        }
    }
}

private struct PDFPreview: NSViewRepresentable {
    let data: Data
    final class Coordinator { var data: Data? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; return view }
    func updateNSView(_ view: PDFView, context: Context) {
        if context.coordinator.data != data { view.document = PDFDocument(data: data); context.coordinator.data = data }
    }
}

struct ProductionDetailsView: View {
    @Binding var details: ProductionDetails
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            HStack { Text(L("Production details")).font(.title2.bold()); Spacer(); Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction) }.padding(20)
            Form {
                TextField(L("Production / company"), text: $details.production)
                TextField(L("Director"), text: $details.director)
                TextField(L("Storyboard artist"), text: $details.artist)
                TextField(L("Revision"), text: $details.revision)
                TextField(L("Date"), text: $details.date)
            }.formStyle(.grouped)
        }.frame(width: 550, height: 380)
    }
}

private struct ExportActionKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var exportStoryboard: (() -> Void)? {
        get { self[ExportActionKey.self] }
        set { self[ExportActionKey.self] = newValue }
    }
}
struct ExportCommands: Commands {
    @FocusedValue(\.exportStoryboard) private var export
    @AppStorage("interfaceLanguage") private var interfaceLanguage = ""
    var body: some Commands {
        let _ = interfaceLanguage
        CommandGroup(after: .saveItem) { Button(L("Export Storyboard…")) { export?() }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(export == nil) }
    }
}
