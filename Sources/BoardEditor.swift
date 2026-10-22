import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BoardEditor: View {
    @Binding private var storedDocument: StoryboardDocument
    init(document: Binding<StoryboardDocument>) { _storedDocument = document }
    private var document: StoryboardDocument {
        get { storedDocument }
        nonmutating set { DocumentEditing.apply(newValue, to: $storedDocument, undoManager: undoManager) }
    }
    private var documentBinding: Binding<StoryboardDocument> {
        Binding(get: { storedDocument }, set: { DocumentEditing.apply($0, to: $storedDocument, undoManager: undoManager) })
    }
    @Environment(\.undoManager) private var undoManager
    @State private var selectedIDs = Set<UUID>()
    private var selectedID: UUID? {
        get { selectedIDs.count == 1 ? selectedIDs.first : nil }
        nonmutating set { selectedIDs = Set(newValue.map { [$0] } ?? []) }
    }
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
    @State private var showHistory = false
    @State private var showRecovery = false
    @State private var filter = ShotFilter.all
    @State private var recoverySession = UUID()
    @State private var recoveryTask: Task<Void, Never>?
    @State private var recoveryWarning = ""
    @State private var models = ModelManager.shared
    @AppStorage("hasOfferedModelSetup") private var hasOfferedModelSetup = false
    @AppStorage("interfaceLanguage") private var interfaceLanguage = ""
    private var selectedIndex: Int? { document.frames.firstIndex { $0.id == selectedID } }
    private var selectedFrames: [StoryboardFrame] { document.frames.filter { selectedIDs.contains($0.id) } }
    private var currentSceneID: UUID? {
        if !selectedFrames.isEmpty {
            return Set(selectedFrames.compactMap(\.sceneID)).count == 1 ? selectedFrames.first?.sceneID : nil
        }
        return sceneID ?? document.scenes.first?.id
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField(L("Story title"), text: documentBinding.title).font(.headline).textFieldStyle(.plain).padding(16)
                Picker(L("Filter shots"), selection: $filter) { ForEach(ShotFilter.allCases) { Text(L($0.rawValue)).tag($0) } }
                    .labelsHidden().accessibilityLabel(L("Filter shots")).padding(.horizontal, 12).padding(.bottom, 8)
                List(selection: $selectedIDs) {
                    ForEach(document.scenes) { scene in
                        Section(isExpanded: Binding(get: { !collapsedScenes.contains(scene.id) }, set: { if $0 { collapsedScenes.remove(scene.id) } else { collapsedScenes.insert(scene.id) } })) {
                            ForEach(document.frames.filter { $0.sceneID == scene.id && filter.includes($0) }) { frame in
                                HStack(spacing: 9) {
                                    FrameImage(data: frame.image).frame(width: 70, height: 40).clipped().cornerRadius(4)
                                    Text(frame.title).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if frame.approved { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).accessibilityLabel(L("Approved")) }
                                }.padding(.vertical, 4).tag(frame.id)
                            }
                            .onMove { source, destination in moveFrames(sceneID: scene.id, source: source, destination: destination) }
                        } header: {
                            Button { sceneID = scene.id; selectedID = nil } label: {
                                HStack { Text(scene.title).lineLimit(2); Spacer(); Text(filter == .all ? "\(document.frames.filter { $0.sceneID == scene.id }.count)" : "\(document.frames.filter { $0.sceneID == scene.id && filter.includes($0) }.count) / \(document.frames.filter { $0.sceneID == scene.id }.count)").monospacedDigit() }
                            }.buttonStyle(.plain).contextMenu {
                                Button(L("Edit scene")) { sceneID = scene.id; selectedID = nil }
                                Button(L("Move scene up")) { moveScene(scene.id, offset: -1) }
                                Button(L("Move scene down")) { moveScene(scene.id, offset: 1) }
                            }
                        }
                    }
                }.disabled(busy)
                if selectedIDs.count > 1 { selectionFooter }
            }.navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 340)
        } detail: {
            if selectedIDs.count > 1 {
                selectionDetails
            } else if let index = selectedIndex {
                FrameEditor(document: documentBinding, frameID: document.frames[index].id, busy: busy, status: status, showHistory: $showHistory, generate: { generate(ids: [document.frames[index].id]) })
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
                    Button(L("Duplicate shot"), action: duplicateFrame).disabled(selectedIndex == nil)
                } label: { Label(L("Add"), systemImage: "plus") }.disabled(busy)
                Button { showLibrary = true } label: { Label(L("Story Library"), systemImage: "person.2.crop.square.stack") }.disabled(busy)
                Button { importingScript = true } label: { Label(L("Import screenplay"), systemImage: "doc.badge.arrow.up") }.disabled(busy)
                Button { showExport = true } label: { Label(L("Export"), systemImage: "square.and.arrow.up") }.disabled(busy)
                Menu {
                    Button(L("Production details…")) { showProduction = true }
                    Button(L("Model setup…")) { showSetup = true }
                    Button(L("Recover storyboard…")) { showRecovery = true }
                    Divider()
                    Button(L("Generate this scene")) { generate(ids: document.frames.filter { $0.sceneID == currentSceneID }.map(\.id)) }
                    Button(L("Generate missing images")) { generate(ids: document.frames.filter { $0.sceneID == currentSceneID && $0.image == nil }.map(\.id)) }
                    Button(L("Render history…")) { showHistory = true }.disabled(selectedIndex.flatMap { document.frames[$0].image } == nil)
                    Button(L("Export selected image…"), action: exportImage).disabled(selectedIndex.flatMap { document.frames[$0].image } == nil)
                    Divider()
                    Button(L("Delete selected shot"), role: .destructive) { showDelete = true }.disabled(selectedIndex == nil)
                    Button(L("Delete this scene…"), role: .destructive) { deleteScene = true }.disabled(currentSceneID == nil)
                } label: { Label(L("Scene actions"), systemImage: "ellipsis.circle") }.disabled(busy)
                if busy { Button(stopRequested ? L("Stopping…") : L("Stop after frame")) { stopRequested = true }.disabled(stopRequested) }
            }
        }
        .onAppear {
            if selectedIDs.isEmpty { selectedID = document.frames.first?.id }; sceneID = document.scenes.first?.id
            if !hasOfferedModelSetup && !models.allReady { hasOfferedModelSetup = true; showSetup = true }
        }
        .focusedSceneValue(\.boardCommands, BoardCommandContext(available: availableCommands, perform: perform))
        .onChange(of: storedDocument) { _, snapshot in
            let valid = Set(snapshot.frames.filter { filter.includes($0) }.map(\.id))
            let previousSelection = selectedIDs
            selectedIDs.formIntersection(valid)
            if !previousSelection.isEmpty && selectedIDs.isEmpty {
                selectedID = snapshot.frames.first(where: { filter.includes($0) })?.id
            }
            recoveryTask?.cancel()
            let session = recoverySession
            recoveryTask = Task {
                do {
                    try await Task.sleep(for: .seconds(2))
                    try await RecoveryStorage.shared.save(snapshot, session: session)
                    recoveryWarning = ""
                } catch is CancellationError {} catch { recoveryWarning = L("Recovery snapshot couldn’t be saved.  Save your storyboard with File > Save.") }
            }
        }
        .onChange(of: filter) { _, value in
            selectedIDs.formIntersection(Set(document.frames.filter { value.includes($0) }.map(\.id)))
            if selectedIDs.isEmpty {
                selectedID = document.frames.first(where: { value.includes($0) })?.id
            }
        }
        .sheet(isPresented: $showRecovery) { RecoveryView { value in document = value; selectedID = value.frames.first?.id; sceneID = value.scenes.first?.id } }
        .overlay(alignment: .bottom) { if !recoveryWarning.isEmpty { Text(recoveryWarning).padding(8).background(.regularMaterial) } }
        .sheet(isPresented: $showExport) { ExportView(document: documentBinding) }
        .sheet(isPresented: $showProduction) { ProductionDetailsView(details: documentBinding.production) }
        .sheet(isPresented: $showSetup) { ModelSetupView() }
        .sheet(isPresented: $showLibrary) { LibraryEditor(document: documentBinding) }
        .sheet(item: $draft) { value in
            ImportReview(draft: value) { approved in
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
                guard let index = selectedIndex else { return }
                let preservedScene = currentSceneID; document.frames.remove(at: index); document.removeUnusedReferences(); sceneID = preservedScene; selectedID = document.frames.first(where: { $0.sceneID == preservedScene })?.id
            }
        }
        .confirmationDialog(L("Delete this scene and all its shots?"), isPresented: $deleteScene, titleVisibility: .visible) {
            Button(L("Delete scene"), role: .destructive) {
                let id = currentSceneID
                document.frames.removeAll { $0.sceneID == id }; document.scenes.removeAll { $0.id == id }; document.removeUnusedReferences()
                selectedID = document.frames.first?.id; sceneID = document.scenes.first?.id
            }
        }
        .safeAreaInset(edge: .bottom) { if selectedIndex == nil { Text(status).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(10) } }
    }
    private var selectionFooter: some View {
        HStack {
            Text(L("%@ shots selected", String(selectedIDs.count))).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(L("Merge"), action: mergeSelectedShots)
                .disabled(busy || !document.canMergeShots(selectedIDs))
                .help(L("Merge selected shots"))
        }.padding(12)
    }
    private var selectionDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("%@ shots selected", String(selectedIDs.count))).font(.title2.bold())
            Text(document.canMergeShots(selectedIDs)
                 ? L("Merge combines descriptions, source text, references, and shot details.  The first shot’s title and camera are kept, and every rendered image stays in history.")
                 : L("Select shots in one scene to merge."))
                .foregroundStyle(.secondary)
            List(selectedFrames) { frame in Text(frame.title) }
        }.padding(24)
    }
    private func sceneEditor(_ index: Int) -> some View {
        Form {
            TextField(L("Scene"), text: documentBinding.scenes[index].title)
            Picker(L("Location"), selection: documentBinding.scenes[index].locationID) {
                Text(L("None")).tag(Optional<UUID>.none)
                ForEach(document.entities.filter { $0.kind == .location }) { Text($0.name).tag(Optional($0.id)) }
            }
            TextField(L("Scene notes"), text: documentBinding.scenes[index].synopsis, axis: .vertical).lineLimit(4...8)
            HStack {
                Button(L("Add shot"), action: addFrame)
                Button(L("Generate scene")) { generate(ids: document.frames.filter { $0.sceneID == document.scenes[index].id }.map(\.id)) }
            }
            if !document.scenes[index].sourceText.isEmpty { DisclosureGroup(L("Screenplay source")) { Text(document.scenes[index].sourceText).textSelection(.enabled) } }
        }.formStyle(.grouped).disabled(busy)
    }
    private func addFrame() {
        if document.scenes.isEmpty { addScene() }
        let id = currentSceneID ?? sceneID ?? document.scenes.first?.id
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
        guard filter == .all else { return }
        var local = document.frames.filter { $0.sceneID == sceneID }; local.move(fromOffsets: source, toOffset: destination)
        var iterator = local.makeIterator()
        for i in document.frames.indices where document.frames[i].sceneID == sceneID { if let next = iterator.next() { document.frames[i] = next } }
    }
    private var availableCommands: Set<BoardAction> {
        if busy { return stopRequested ? [] : [.stop] }
        if showLibrary || showExport || showProduction || showSetup || showRecovery || showHistory || importingScript || showDelete || deleteScene || draft != nil { return [] }
        var result: Set<BoardAction> = [.library, .addShot, .addScene, .importScript, .export, .production, .setup, .recover]
        if currentSceneID != nil { result.formUnion([.renderScene, .renderMissing]) }
        if document.canMergeShots(selectedIDs) { result.insert(.merge) }
        if !document.frames.isEmpty { result.formUnion([.previous, .next]) }
        if selectedIndex != nil {
            result.formUnion([.duplicate, .delete])
            if let i = selectedIndex, !document.frames[i].description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.insert(.render) }
            if let i = selectedIndex, document.frames[i].image != nil { result.formUnion([.approve, .history]) }
        }
        return result
    }
    private func perform(_ action: BoardAction) {
        guard availableCommands.contains(action) else { return }
        switch action {
        case .library: showLibrary = true
        case .addShot: addFrame()
        case .addScene: addScene()
        case .duplicate: duplicateFrame()
        case .merge: mergeSelectedShots()
        case .importScript: importingScript = true
        case .export: showExport = true
        case .production: showProduction = true
        case .setup: showSetup = true
        case .recover: showRecovery = true
        case .render: if let selectedID { generate(ids: [selectedID]) }
        case .renderScene: generate(ids: document.frames.filter { $0.sceneID == currentSceneID }.map(\.id))
        case .renderMissing: generate(ids: document.frames.filter { $0.sceneID == currentSceneID && $0.image == nil }.map(\.id))
        case .stop: stopRequested = true
        case .previous: navigate(-1)
        case .next: navigate(1)
        case .approve: if let i = selectedIndex { document.frames[i].approved.toggle() }
        case .history: showHistory = true
        case .delete: showDelete = true
        }
    }
    private func navigate(_ offset: Int) {
        let frames = document.scenes.flatMap { scene in document.frames.filter { $0.sceneID == scene.id && filter.includes($0) } }
        guard !frames.isEmpty else { return }
        let current = frames.firstIndex(where: { $0.id == selectedID }) ?? 0
        let next = max(0, min(frames.count - 1, current + offset))
        selectedID = frames[next].id
        if let scene = frames[next].sceneID { collapsedScenes.remove(scene) }
    }
    private func duplicateFrame() {
        guard let i = selectedIndex else { return }
        let copy = document.frames[i].duplicated()
        document.frames.insert(copy, at: i + 1); selectedID = copy.id
        filter = .all
    }
    private func mergeSelectedShots() {
        guard !busy else { return }
        var next = document
        guard let id = next.mergeShots(selectedIDs) else { return }
        DocumentEditing.apply(next, to: $storedDocument, undoManager: undoManager, name: L("Merge shots"))
        filter = .all
        selectedID = id
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
                        document.frames[i].storeRender(image: result.image, prompt: result.prompt, seed: result.seed, source: request, referenceIDs: result.referenceIDs); completed += 1
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

struct FrameImage: View {
    let data: Data?
    var body: some View {
        if let data, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
        else { Rectangle().fill(.quaternary.opacity(0.4)).aspectRatio(16/9, contentMode: .fit).overlay(Image(systemName: "rectangle.dashed").foregroundStyle(.secondary)) }
    }
}
