import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LibraryEditor: View {
    @Binding var document: StoryboardDocument
    @Environment(\.dismiss) private var dismiss
    @State private var kind = EntityKind.character
    @State private var selection: UUID?
    @State private var importing = false
    @State private var pendingImages: [ReferenceImage] = []
    @State private var showUseChoice = false
    @State private var proposal: DescriptionProposal?
    @State private var working = false
    @State private var message = ""
    @State private var deleteEntity = false
    @State private var deleteReference: UUID?
    @State private var mergeTarget: UUID?
    @State private var showMerge = false
    private var index: Int? { document.entities.firstIndex { $0.id == selection } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Story library").font(.title2.bold()); Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).disabled(working)
            }.padding()
            Divider()
            HSplitView {
                VStack {
                    Picker("Library", selection: $kind) { ForEach(EntityKind.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    List(selection: $selection) { ForEach(document.entities.filter { $0.kind == kind }) { entity in Label(entity.name, systemImage: entity.kind.symbol).tag(entity.id) } }
                    HStack {
                        Button { let value = StoryEntity(kind: kind, name: kind == .character ? "New character" : "New location"); document.entities.append(value); selection = value.id } label: { Label("Add", systemImage: "plus") }
                        Spacer()
                        Button { deleteEntity = true } label: { Image(systemName: "trash") }.disabled(index == nil)
                    }
                }.padding().frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
                if let index {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                TextField("Name", text: $document.entities[index].name).font(.title2)
                                Menu("Merge with") {
                                    ForEach(document.entities.filter { $0.kind == document.entities[index].kind && $0.id != selection }) { target in
                                        Button(target.name) { mergeTarget = target.id; showMerge = true }
                                    }
                                }.disabled(document.entities.filter { $0.kind == document.entities[index].kind }.count < 2)
                            }
                            Text("Description").font(.headline)
                            TextEditor(text: $document.entities[index].description).frame(height: 180).padding(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                            HStack { Text("Reference images").font(.headline); Spacer(); Button("Add images…") { importing = true }.disabled(document.entities[index].referenceIDs.count >= 12) }
                            if !document.entities[index].referenceIDs.isEmpty {
                                Button("Review description from images…") {
                                    pendingImages = document.entities[index].referenceIDs.prefix(3).compactMap { id in document.references.first { $0.id == id } }
                                    showUseChoice = true
                                }
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
                                ForEach(document.entities[index].referenceIDs, id: \.self) { id in
                                    if let image = document.references.first(where: { $0.id == id }) {
                                        VStack(spacing: 6) {
                                            ReferenceThumbnail(image: image).frame(height: 115)
                                            Text(image.name).font(.caption).lineLimit(1)
                                            HStack {
                                                Button(document.entities[index].referenceIDs.first == id ? "Primary" : "Make primary") {
                                                    document.entities[index].referenceIDs.removeAll { $0 == id }; document.entities[index].referenceIDs.insert(id, at: 0)
                                                }.disabled(document.entities[index].referenceIDs.first == id)
                                                Button { deleteReference = id } label: { Image(systemName: "xmark.circle") }
                                            }.font(.caption)
                                        }
                                    }
                                }
                            }
                            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
                        }.padding(22)
                    }.frame(minWidth: 470)
                } else { ContentUnavailableView("Select a character or location", systemImage: kind.symbol).frame(minWidth: 470) }
            }.disabled(working)
        }.frame(width: 850, height: 620)
        .onChange(of: kind) { _, _ in selection = document.entities.first(where: { $0.kind == kind })?.id }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            do { attach(try result.get()) } catch { message = "The selected images couldn’t be opened." }
        }
        .dropDestination(for: URL.self) { urls, _ in attach(urls); return true }
        .confirmationDialog("Merge these entries?", isPresented: $showMerge, titleVisibility: .visible) {
            Button("Merge entries") {
                if let source = selection, let target = mergeTarget { document.mergeEntity(source, into: target); selection = target; message = "Entries merged." }
            }
        } message: { Text("Descriptions and references are combined, and linked shots use the destination entry.") }
        .confirmationDialog("How should these images be used?", isPresented: $showUseChoice, titleVisibility: .visible) {
            Button("Visual references only") { pendingImages = [] }
            if let index, !document.entities[index].description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Enhance existing description") { describe(replace: false) }
                Button("Recreate description…") { describe(replace: true) }
            } else { Button("Create description…") { describe(replace: true) } }
        } message: { Text("Enhance keeps the current description.  Recreate proposes a replacement for review.") }
        .sheet(item: $proposal) { value in
            DescriptionReview(proposal: value) { description in
                if let i = document.entities.firstIndex(where: { $0.id == value.entityID }) { document.entities[i].description = description; message = "Description updated." }
                proposal = nil
            }
        }
        .confirmationDialog("Delete this library entry?", isPresented: $deleteEntity, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) { if let selection { document.removeEntity(selection); self.selection = nil } }
        } message: { Text("Linked pills become plain names.  Unused reference images are removed.") }
        .confirmationDialog("Remove this reference image?", isPresented: Binding(get: { deleteReference != nil }, set: { if !$0 { deleteReference = nil } }), titleVisibility: .visible) {
            Button("Remove image", role: .destructive) { if let index, let id = deleteReference { document.entities[index].referenceIDs.removeAll { $0 == id }; document.removeUnusedReferences() }; deleteReference = nil }
        }
    }
    private func attach(_ urls: [URL]) {
        guard let index, !working else { return }
        do {
            let remaining = 12-document.entities[index].referenceIDs.count
            guard !urls.isEmpty, urls.count <= min(3, remaining) else { message = "Add up to \(min(3, remaining)) images at a time."; return }
            let images = try urls.map { url in
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try ReferenceImages.importFile(url)
            }
            pendingImages = images
            document.references.append(contentsOf: images); document.entities[index].referenceIDs.append(contentsOf: images.map(\.id))
            showUseChoice = true; message = "\(images.count) reference images added."
        } catch { message = (error as? ImageError)?.localizedDescription ?? "The images couldn’t be opened.  Try PNG, JPEG, or HEIC files." }
    }
    private func describe(replace: Bool) {
        guard let index else { return }
        let entity = document.entities[index]; let images = pendingImages; pendingImages = []
        working = true; message = "Reading reference images…"
        Task {
            do {
                var parts: [String] = []
                for image in images {
                    let value = try await RenderService.shared.describe(image: image, kind: entity.kind)
                    if !parts.contains(value) { parts.append(value) }
                }
                let generated = parts.joined(separator: ". ")
                let text = !replace && !entity.description.isEmpty ? entity.description + "\n" + generated : generated
                proposal = DescriptionProposal(entityID: entity.id, name: entity.name, description: text, replacing: replace, creating: entity.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                message = "Review the proposed description."
            } catch { message = (error as? DescriptionError)?.localizedDescription ?? "The description couldn’t be generated.  Your images are saved; try again or edit the description manually." }
            working = false
        }
    }
}

struct DescriptionProposal: Identifiable {
    var id = UUID()
    var entityID: UUID
    var name: String
    var description: String
    var replacing: Bool
    var creating: Bool
}
struct DescriptionReview: View {
    let proposal: DescriptionProposal
    let apply: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(proposal.creating ? "Describe \(proposal.name)" : proposal.replacing ? "Replace \(proposal.name)’s description" : "Enhance \(proposal.name)’s description").font(.title2)
            TextEditor(text: $text).frame(minHeight: 220)
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button(proposal.creating ? "Use description" : proposal.replacing ? "Replace description" : "Apply description") { apply(text); dismiss() }.buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 600).onAppear { text = proposal.description }
    }
}
struct ReferenceThumbnail: View {
    let image: ReferenceImage
    var body: some View {
        if let value = NSImage(data: image.data) { Image(nsImage: value).resizable().scaledToFit() }
        else { Image(systemName: "photo") }
    }
}
