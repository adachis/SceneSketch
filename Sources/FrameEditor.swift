import SwiftUI
import UniformTypeIdentifiers

struct FrameEditor: View {
    @Binding var document: StoryboardDocument
    let frameID: UUID
    let busy: Bool
    let status: String
    let generate: () -> Void
    @State private var insertion: UUID?
    @State private var showReferences = false
    @State private var importing = false
    @State private var message = ""
    @State private var removing: UUID?
    private var index: Int? { document.frames.firstIndex { $0.id == frameID } }
    private var context: StoryContext? { index.flatMap { try? StoryContext(frame: document.frames[$0], document: document) } }
    var body: some View {
        if let index {
            HSplitView {
                VStack(spacing: 0) {
                    FrameImage(data: document.frames[index].image).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack { Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2); Spacer(); if busy { ProgressView().controlSize(.small) } }.frame(height: 46).padding(.horizontal, 18)
                }.frame(minWidth: 360)
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Shot title", text: $document.frames[index].title).font(.title2).textFieldStyle(.plain)
                    Picker("Scene", selection: $document.frames[index].sceneID) { ForEach(document.scenes) { Text($0.title).tag(Optional($0.id)) } }
                    Picker("Camera", selection: $document.frames[index].shot) { ForEach(CameraShot.allCases) { Text($0.rawValue).tag($0) } }
                    HStack {
                        Text("Description").font(.headline); Spacer()
                        Menu {
                            ForEach(EntityKind.allCases) { kind in
                                Section(kind.label) { ForEach(document.entities.filter { $0.kind == kind }) { entity in Button(entity.name) { insertion = entity.id } } }
                            }
                        } label: { Label("Insert", systemImage: "at") }.disabled(document.entities.isEmpty)
                    }
                    TokenTextEditor(text: $document.frames[index].description, entities: document.entities, insertion: $insertion)
                        .frame(minHeight: 140).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    Button { showReferences.toggle() } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text("References"); Spacer(); Text("\(context?.references.count ?? 0) / \(StoryContext.referenceLimit)").monospacedDigit(); Image(systemName: "chevron.down") }
                            ProgressView(value: Double(context?.references.count ?? 0), total: Double(StoryContext.referenceLimit))
                            if let c = context, c.missingSelectionCount > 0 { Text("\(c.missingSelectionCount) additional images available").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.buttonStyle(.plain)
                    .popover(isPresented: $showReferences) { referencePicker(index).padding(16).frame(width: 380, height: 420) }
                    Button("Add shot reference…") { importing = true }.disabled(document.frames[index].referenceIDs.count >= 3)
                    if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                    if !document.frames[index].sourceText.isEmpty { DisclosureGroup("Screenplay source") { ScrollView { Text(document.frames[index].sourceText).font(.caption).textSelection(.enabled) }.frame(maxHeight: 90) } }
                    Button(action: generate) { Label(busy ? "Generating…" : (document.frames[index].image == nil ? "Generate frame" : "Generate another"), systemImage: "pencil.and.outline").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(document.frames[index].description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.return, modifiers: .command)
                }.padding(20).frame(minWidth: 310, idealWidth: 350, maxWidth: 400).disabled(busy)
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                do {
                    let urls = try result.get(); let remaining = 3-document.frames[index].referenceIDs.count
                    guard urls.count <= remaining else { message = "Choose up to \(remaining) more shot reference images."; return }
                    let images = try urls.map { url in
                        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        return try ReferenceImages.importFile(url)
                    }
                    document.references.append(contentsOf: images); document.frames[index].referenceIDs.append(contentsOf: images.map(\.id))
                    document.frames[index].selectedReferenceIDs = nil; message = "Reference images added."
                } catch { message = "The images couldn’t be added.  Choose PNG, JPEG, or HEIC files under 50 MB." }
            }
            .confirmationDialog("Remove this shot reference?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove reference", role: .destructive) { if let id = removing { document.frames[index].referenceIDs.removeAll { $0 == id }; document.removeUnusedReferences() }; removing = nil }
            }
        }
    }
    private func referencePicker(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Images for this frame").font(.headline); Spacer(); Button("Auto") { document.frames[index].selectedReferenceIDs = nil } }
            if let c = context {
                Text("\(c.references.count) of \(StoryContext.referenceLimit) selected").font(.caption)
                List(c.availableReferences) { reference in
                    HStack {
                        Toggle(isOn: Binding(get: { context?.references.contains(where: { $0.id == reference.id }) ?? false }, set: { on in
                            var ids = context?.references.map(\.id) ?? []
                            if on && ids.count < StoryContext.referenceLimit { ids.append(reference.id) } else if !on { ids.removeAll { $0 == reference.id } }
                            document.frames[index].selectedReferenceIDs = ids
                        })) { HStack { ReferenceThumbnail(image: reference.image).frame(width: 52, height: 48); VStack(alignment: .leading) { Text(reference.label); Text(reference.image.name).font(.caption).foregroundStyle(.secondary) } } }
                        .disabled(c.references.count >= StoryContext.referenceLimit && !c.references.contains(where: { $0.id == reference.id }))
                        if document.frames[index].referenceIDs.contains(reference.id) { Button { removing = reference.id } label: { Image(systemName: "trash") }.buttonStyle(.plain) }
                    }
                }
            }
        }
    }
}
