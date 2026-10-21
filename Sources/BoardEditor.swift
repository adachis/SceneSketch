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
    @State private var showExport = false
    @State private var showProduction = false
    @State private var showSetup = false
    @State private var models = ModelManager.shared
    @AppStorage("hasOfferedModelSetup") private var hasOfferedModelSetup = false
    @AppStorage("interfaceLanguage") private var interfaceLanguage = ""
    private var selectedIndex: Int? { document.frames.firstIndex { $0.id == selectedID } }
    private var currentSceneID: UUID? { selectedIndex.flatMap { document.frames[$0].sceneID } ?? sceneID ?? document.scenes.first?.id }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField(L("Story title"), text: $document.title).font(.headline).textFieldStyle(.plain).padding(16)
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
                                Button(L("Edit scene")) { sceneID = scene.id; selectedID = nil }
                                Button(L("Move scene up")) { moveScene(scene.id, offset: -1) }
                                Button(L("Move scene down")) { moveScene(scene.id, offset: 1) }
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
            } else { ContentUnavailableView(L("Add a scene to begin"), systemImage: "rectangle.stack") }
        }
        .frame(minWidth: 1060, minHeight: 700)
        .environment(\.locale, Locale(identifier: Localization.code))
        .environment(\.layoutDirection, Localization.isRightToLeft ? .rightToLeft : .leftToRight)
        .id(interfaceLanguage)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button(L("Add shot"), action: addFrame)
                    Button(L("Add scene"), action: addScene)
                } label: { Label(L("Add"), systemImage: "plus") }.disabled(busy)
                Button { showLibrary = true } label: { Label(L("Story Library"), systemImage: "person.2.crop.square.stack") }.disabled(busy)
                Button { importingScript = true } label: { Label(L("Import screenplay"), systemImage: "doc.badge.arrow.up") }.disabled(busy)
                Button { showExport = true } label: { Label(L("Export"), systemImage: "square.and.arrow.up") }.disabled(busy)
                Menu {
                    Button(L("Production details…")) { showProduction = true }
                    Button(L("Model setup…")) { showSetup = true }
                    Divider()
                    Button(L("Generate this scene")) { generate(ids: document.frames.filter { $0.sceneID == currentSceneID }.map(\.id)) }
                    Button(L("Export selected image…"), action: exportImage).disabled(selectedIndex.flatMap { document.frames[$0].image } == nil)
                    Divider()
                    Button(L("Delete selected shot"), role: .destructive) { showDelete = true }.disabled(selectedIndex == nil)
                    Button(L("Delete this scene…"), role: .destructive) { deleteScene = true }
                } label: { Label(L("Scene actions"), systemImage: "ellipsis.circle") }.disabled(busy)
                if busy { Button(stopRequested ? L("Stopping…") : L("Stop after frame")) { stopRequested = true }.disabled(stopRequested) }
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = document.frames.first?.id }; sceneID = document.scenes.first?.id
            if !hasOfferedModelSetup && !models.allReady { hasOfferedModelSetup = true; showSetup = true }
        }
        .focusedSceneValue(\.exportStoryboard, { showExport = true })
        .sheet(isPresented: $showExport) { ExportView(document: $document) }
        .sheet(isPresented: $showProduction) { ProductionDetailsView(details: $document.production) }
        .sheet(isPresented: $showSetup) { ModelSetupView() }
        .sheet(isPresented: $showLibrary) { LibraryEditor(document: $document) }
        .sheet(item: $draft) { value in
            ImportReview(draft: value) { approved in
                let prior = document; registerUndo(prior, name: L("Import screenplay"))
                document = approved.applying(to: document); selectedID = document.frames.last?.id; sceneID = document.scenes.last?.id
                status = L("Imported scenes: %@. Shots: %@.", String(approved.scenes.count), String(approved.frames.count))
            }
        }
        .fileImporter(isPresented: $importingScript, allowedContentTypes: [.pdf, .plainText, .xml, UTType(filenameExtension: "fountain") ?? .plainText, UTType(filenameExtension: "fdx") ?? .xml]) { result in
            do { importScript(try result.get()) } catch { errorMessage = L("The screenplay couldn’t be opened.") }
        }
        .alert(L("Couldn’t complete the action"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button(L("OK")) { errorMessage = nil } } message: { Text(errorMessage ?? L("Please try again.")) }
        .confirmationDialog(L("Delete this shot and its image?"), isPresented: $showDelete, titleVisibility: .visible) {
            Button(L("Delete shot"), role: .destructive) {
                guard let index = selectedIndex else { return }; registerUndo(document, name: "Delete shot")
                let preservedScene = currentSceneID; document.frames.remove(at: index); document.removeUnusedReferences(); sceneID = preservedScene; selectedID = document.frames.first(where: { $0.sceneID == preservedScene })?.id
            }
        }
        .confirmationDialog(L("Delete this scene and all its shots?"), isPresented: $deleteScene, titleVisibility: .visible) {
            Button(L("Delete scene"), role: .destructive) {
                let id = currentSceneID; registerUndo(document, name: "Delete scene")
                document.frames.removeAll { $0.sceneID == id }; document.scenes.removeAll { $0.id == id }; document.removeUnusedReferences()
                selectedID = document.frames.first?.id; sceneID = document.scenes.first?.id
            }
        }
        .safeAreaInset(edge: .bottom) { if selectedIndex == nil { Text(status).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(10) } }
    }
    private func sceneEditor(_ index: Int) -> some View {
        Form {
            TextField(L("Scene"), text: $document.scenes[index].title)
            Picker(L("Location"), selection: $document.scenes[index].locationID) {
                Text(L("None")).tag(Optional<UUID>.none)
                ForEach(document.entities.filter { $0.kind == .location }) { Text($0.name).tag(Optional($0.id)) }
            }
            TextField(L("Scene notes"), text: $document.scenes[index].synopsis, axis: .vertical).lineLimit(4...8)
            HStack {
                Button(L("Add shot"), action: addFrame)
                Button(L("Generate scene")) { generate(ids: document.frames.filter { $0.sceneID == document.scenes[index].id }.map(\.id)) }
            }
            if !document.scenes[index].sourceText.isEmpty { DisclosureGroup(L("Screenplay source")) { Text(document.scenes[index].sourceText).textSelection(.enabled) } }
        }.formStyle(.grouped).disabled(busy)
    }
    private func addFrame() {
        if document.scenes.isEmpty { addScene() }
        let id = currentSceneID
        let frame = StoryboardFrame(title: L("Shot %@", String(document.frames.filter { $0.sceneID == id }.count + 1)), sceneID: id)
        document.frames.append(frame); selectedID = frame.id
    }
    private func addScene() {
        let scene = StoryScene(title: L("Scene %@", String(document.scenes.count + 1)))
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
        models.refresh()
        guard models.drawingReady else { showSetup = true; return }
        guard !models.isWorking else { showSetup = true; return }
        guard !ids.isEmpty else { return }; busy = true; stopRequested = false
        RuntimeActivity.shared.beginBatch()
        Task {
            defer { RuntimeActivity.shared.endBatch() }
            var completed = 0; var failed = false
            for (offset, id) in ids.enumerated() {
                if stopRequested { break }
                guard let index = document.frames.firstIndex(where: { $0.id == id }), !document.frames[index].description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                var frame = document.frames[index]
                if frame.image != nil { frame.seed = UInt64.random(in: 1...UInt64(UInt32.max)) }
                let request = frame; let snapshot = document
                do {
                    status = L("Shot %@ of %@: preparing…", String(offset+1), String(ids.count))
                    let result = try await RenderService.shared.render(frame: request, document: snapshot) { update in Task { @MainActor in status = L("Shot %@ of %@: %@", String(offset+1), String(ids.count), update) } }
                    if let i = document.frames.firstIndex(where: { $0.id == id }) {
                        document.frames[i].seed = result.seed; document.frames[i].image = result.image
                        document.frames[i].renderedPrompt = result.prompt; document.frames[i].imageRevision = UUID(); completed += 1
                    }
                } catch { errorMessage = RenderService.userMessage(for: error); failed = true; break }
            }
            status = failed ? L("Generation failed after %@ frames.", String(completed)) : stopRequested ? L("Stopped after %@ frames.", String(completed)) : L("Generated %@ of %@ frames.", String(completed), String(ids.count)); busy = false
        }
    }
    private func importScript(_ url: URL) {
        busy = true; status = L("Reading screenplay…")
        Task {
            do {
                draft = try await Task.detached { try ScreenplayImporter.read(url) { update in Task { @MainActor in status = update } } }.value
                status = L("Review the imported screenplay.")
            } catch { errorMessage = (error as? ImportError)?.localizedDescription ?? L("The screenplay couldn’t be read.  Try a PDF, Final Draft, Fountain, or text file."); status = L("Import failed.") }
            busy = false
        }
    }
    private func exportImage() {
        guard let index = selectedIndex, let data = document.frames[index].image else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = document.frames[index].title + ".png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic); status = L("Image exported.") } catch { errorMessage = L("The image couldn’t be saved.  Choose another location.") }
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
