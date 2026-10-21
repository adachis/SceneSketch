import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BoardEditor: View {
    @Binding var document: StoryboardDocument
    @Environment(\.undoManager) private var undoManager
    @State private var selectedID: UUID?
    @State private var collapsedScenes = Set<UUID>()
    @State private var sceneID: UUID?
    @State private var busy = false
    @State private var stopRequested = false
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var showDelete = false
    @State private var deleteScene = false
    @State private var showLibrary = false
    @State private var importingScript = false
    @State private var draft: ScreenplayDraft?
    private var selectedIndex: Int? { document.frames.firstIndex { $0.id == selectedID } }
    private var currentSceneID: UUID? { selectedIndex.flatMap { document.frames[$0].sceneID } ?? sceneID ?? document.scenes.first?.id }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField("Story title", text: $document.title).font(.headline).textFieldStyle(.plain).padding(16)
                List(selection: $selectedID) {
                    ForEach(document.scenes) { scene in
                        Section(isExpanded: Binding(get: { !collapsedScenes.contains(scene.id) }, set: { if $0 { collapsedScenes.remove(scene.id) } else { collapsedScenes.insert(scene.id) } })) {
                            ForEach(document.frames.filter { $0.sceneID == scene.id }) { frame in
                                HStack(spacing: 9) {
                                    FrameImage(data: frame.image).frame(width: 70, height: 40).clipped().cornerRadius(4)
                                    Text(frame.title).lineLimit(1)
                                }.padding(.vertical, 4).tag(frame.id)
                            }
                            .onMove { source, destination in moveFrames(sceneID: scene.id, source: source, destination: destination) }
                        } header: {
                            Button { sceneID = scene.id; selectedID = nil } label: {
                                HStack { Text(scene.title).lineLimit(2); Spacer(); Text("\(document.frames.filter { $0.sceneID == scene.id }.count)").monospacedDigit() }
                            }.buttonStyle(.plain).contextMenu {
                                Button("Edit scene") { sceneID = scene.id; selectedID = nil }
                                Button("Move scene up") { moveScene(scene.id, offset: -1) }
                                Button("Move scene down") { moveScene(scene.id, offset: 1) }
                            }
                        }
                    }
                }.disabled(busy)
            }.navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 340)
        } detail: {
            if let index = selectedIndex {
                FrameEditor(document: $document, frameID: document.frames[index].id, busy: busy, status: status, generate: { generate(ids: [document.frames[index].id]) })
            } else if let sceneIndex = document.scenes.firstIndex(where: { $0.id == currentSceneID }) {
                sceneEditor(sceneIndex)
            } else { ContentUnavailableView("Add a scene to begin", systemImage: "rectangle.stack") }
        }
        .frame(minWidth: 1060, minHeight: 700)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Add shot", action: addFrame)
                    Button("Add scene", action: addScene)
                } label: { Label("Add", systemImage: "plus") }.disabled(busy)
                Button { showLibrary = true } label: { Label("Story library", systemImage: "person.2.crop.square.stack") }.disabled(busy)
                Button { importingScript = true } label: { Label("Import screenplay", systemImage: "doc.badge.arrow.up") }.disabled(busy)
                Menu {
                    Button("Generate this scene") { generate(ids: document.frames.filter { $0.sceneID == currentSceneID }.map(\.id)) }
                    Button("Export selected image…", action: exportImage).disabled(selectedIndex.flatMap { document.frames[$0].image } == nil)
                    Divider()
                    Button("Delete selected shot", role: .destructive) { showDelete = true }.disabled(selectedIndex == nil)
                    Button("Delete this scene…", role: .destructive) { deleteScene = true }
                } label: { Label("Scene actions", systemImage: "ellipsis.circle") }.disabled(busy)
                if busy { Button(stopRequested ? "Stopping…" : "Stop after frame") { stopRequested = true }.disabled(stopRequested) }
            }
        }
        .onAppear { if selectedID == nil { selectedID = document.frames.first?.id }; sceneID = document.scenes.first?.id }
        .sheet(isPresented: $showLibrary) { LibraryEditor(document: $document) }
        .sheet(item: $draft) { value in
            ImportReview(draft: value) { approved in
                let prior = document; registerUndo(prior, name: "Import screenplay")
                document = approved.applying(to: document); selectedID = document.frames.last?.id; sceneID = document.scenes.last?.id
                status = "Imported \(approved.scenes.count) scenes and \(approved.frames.count) shots."
            }
        }
        .fileImporter(isPresented: $importingScript, allowedContentTypes: [.pdf, .plainText, .xml, UTType(filenameExtension: "fountain") ?? .plainText, UTType(filenameExtension: "fdx") ?? .xml]) { result in
            do { importScript(try result.get()) } catch { errorMessage = "The screenplay couldn’t be opened." }
        }
        .alert("Couldn’t complete the action", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Please try again.") }
        .confirmationDialog("Delete this shot and its image?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete shot", role: .destructive) {
                guard let index = selectedIndex else { return }; registerUndo(document, name: "Delete shot")
                let preservedScene = currentSceneID; document.frames.remove(at: index); document.removeUnusedReferences(); sceneID = preservedScene; selectedID = document.frames.first(where: { $0.sceneID == preservedScene })?.id
            }
        }
        .confirmationDialog("Delete this scene and all its shots?", isPresented: $deleteScene, titleVisibility: .visible) {
            Button("Delete scene", role: .destructive) {
                let id = currentSceneID; registerUndo(document, name: "Delete scene")
                document.frames.removeAll { $0.sceneID == id }; document.scenes.removeAll { $0.id == id }; document.removeUnusedReferences()
                selectedID = document.frames.first?.id; sceneID = document.scenes.first?.id
            }
        }
        .safeAreaInset(edge: .bottom) { if selectedIndex == nil { Text(status).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(10) } }
    }
    private func sceneEditor(_ index: Int) -> some View {
        Form {
            TextField("Scene", text: $document.scenes[index].title)
            Picker("Location", selection: $document.scenes[index].locationID) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(document.entities.filter { $0.kind == .location }) { Text($0.name).tag(Optional($0.id)) }
            }
            TextField("Scene notes", text: $document.scenes[index].synopsis, axis: .vertical).lineLimit(4...8)
            HStack {
                Button("Add shot", action: addFrame)
                Button("Generate scene") { generate(ids: document.frames.filter { $0.sceneID == document.scenes[index].id }.map(\.id)) }
            }
            if !document.scenes[index].sourceText.isEmpty { DisclosureGroup("Screenplay source") { Text(document.scenes[index].sourceText).textSelection(.enabled) } }
        }.formStyle(.grouped).disabled(busy)
    }
    private func addFrame() {
        if document.scenes.isEmpty { addScene() }
        let id = currentSceneID
        let frame = StoryboardFrame(title: "Shot \(document.frames.filter { $0.sceneID == id }.count + 1)", sceneID: id)
        document.frames.append(frame); selectedID = frame.id
    }
    private func addScene() {
        let scene = StoryScene(title: "Scene \(document.scenes.count + 1)")
        document.scenes.append(scene); sceneID = scene.id; selectedID = nil
    }
    private func moveScene(_ id: UUID, offset: Int) {
        guard let index = document.scenes.firstIndex(where: { $0.id == id }), document.scenes.indices.contains(index+offset) else { return }
        document.scenes.swapAt(index, index+offset)
    }
    private func moveFrames(sceneID: UUID, source: IndexSet, destination: Int) {
        var local = document.frames.filter { $0.sceneID == sceneID }; local.move(fromOffsets: source, toOffset: destination)
        var iterator = local.makeIterator()
        for i in document.frames.indices where document.frames[i].sceneID == sceneID { if let next = iterator.next() { document.frames[i] = next } }
    }
    private func registerUndo(_ prior: StoryboardDocument, name: String) {
        let binding = $document
        undoManager?.registerUndo(withTarget: UndoToken.shared) { _ in binding.wrappedValue = prior }
        undoManager?.setActionName(name)
    }
    private func generate(ids: [UUID]) {
        guard !ids.isEmpty else { return }; busy = true; stopRequested = false
        Task {
            var completed = 0; var failed = false
            for (offset, id) in ids.enumerated() {
                if stopRequested { break }
                guard let index = document.frames.firstIndex(where: { $0.id == id }), !document.frames[index].description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                var frame = document.frames[index]
                if frame.image != nil { frame.seed = UInt64.random(in: 1...UInt64(UInt32.max)) }
                let request = frame; let snapshot = document
                do {
                    status = "Shot \(offset+1) of \(ids.count): preparing…"
                    let result = try await RenderService.shared.render(frame: request, document: snapshot) { update in Task { @MainActor in status = "Shot \(offset+1) of \(ids.count): \(update)" } }
                    if let i = document.frames.firstIndex(where: { $0.id == id }) {
                        document.frames[i].seed = request.seed; document.frames[i].image = result.image
                        document.frames[i].renderedPrompt = result.prompt; document.frames[i].imageRevision = UUID(); completed += 1
                    }
                } catch { errorMessage = RenderService.userMessage(for: error); failed = true; break }
            }
            status = failed ? "Generation failed after \(completed) frames." : stopRequested ? "Stopped after \(completed) frames." : "Generated \(completed) of \(ids.count) frames."; busy = false
        }
    }
    private func importScript(_ url: URL) {
        busy = true; status = "Reading screenplay…"
        Task {
            do {
                draft = try await Task.detached { try ScreenplayImporter.read(url) { update in Task { @MainActor in status = update } } }.value
                status = "Review the imported screenplay."
            } catch { errorMessage = (error as? ImportError)?.localizedDescription ?? "The screenplay couldn’t be read.  Try a PDF, Final Draft, Fountain, or text file."; status = "Import failed." }
            busy = false
        }
    }
    private func exportImage() {
        guard let index = selectedIndex, let data = document.frames[index].image else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = document.frames[index].title + ".png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic); status = "Image exported." } catch { errorMessage = "The image couldn’t be saved.  Choose another location." }
        }
    }
}
@MainActor private final class UndoToken: NSObject { static let shared = UndoToken() }

struct FrameImage: View {
    let data: Data?
    var body: some View {
        if let data, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
        else { Rectangle().fill(.quaternary.opacity(0.4)).aspectRatio(16/9, contentMode: .fit).overlay(Image(systemName: "rectangle.dashed").foregroundStyle(.secondary)) }
    }
}
