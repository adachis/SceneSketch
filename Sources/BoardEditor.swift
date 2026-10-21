import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BoardEditor: View {
    @Binding var document: StoryboardDocument
    @State private var selectedID: UUID?
    @State private var busy = false
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?
    @State private var showDelete = false

    private var selectedIndex: Int? { document.frames.firstIndex { $0.id == selectedID } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(Array(document.frames.enumerated()), id: \.element.id) { index, frame in
                    HStack(spacing: 10) {
                        FrameImage(data: frame.image, revision: frame.imageRevision)
                            .frame(width: 82, height: 46).clipped().cornerRadius(4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(frame.title).font(.headline).lineLimit(1)
                            Text("\(index + 1) · \(frame.shot.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5).tag(frame.id)
                }
                .onMove { source, destination in document.frames.move(fromOffsets: source, toOffset: destination) }
            }
            .navigationTitle("Frames")
            .navigationSplitViewColumnWidth(min: 240, ideal: 275, max: 380)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addFrame) { Label("Add frame", systemImage: "plus") }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                }
            }
        } detail: {
            if let index = selectedIndex {
                HSplitView {
                    VStack(spacing: 0) {
                        FrameImage(data: document.frames[index].image, revision: document.frames[index].imageRevision)
                            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                        HStack {
                            Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            Spacer()
                            if busy { ProgressView().controlSize(.small) }
                        }
                        .frame(height: 42).padding(.horizontal, 18)
                    }
                    .frame(minWidth: 380)
                    VStack(alignment: .leading, spacing: 18) {
                        TextField("Frame title", text: $document.frames[index].title).font(.title2).textFieldStyle(.plain)
                        Picker("Camera", selection: $document.frames[index].shot) {
                            ForEach(CameraShot.allCases) { shot in Text(shot.rawValue).tag(shot) }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description").font(.headline)
                            TextEditor(text: $document.frames[index].description)
                                .font(.body).frame(minHeight: 160, maxHeight: .infinity)
                                .scrollContentBackground(.hidden)
                                .padding(8).background(.background, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        }
                        HStack {
                            Text("Variation").foregroundStyle(.secondary)
                            Spacer()
                            TextField("Seed", value: $document.frames[index].seed, format: .number.grouping(.never))
                                .multilineTextAlignment(.trailing).frame(width: 120)
                            Button { document.frames[index].seed = UInt64.random(in: 1...UInt64(UInt32.max)) }
                            label: { Image(systemName: "shuffle") }
                            .help("New variation")
                        }
                        Button { generate(index) } label: {
                            Label(busy ? "Generating…" : "Generate frame", systemImage: "pencil.and.outline")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(busy || document.frames[index].description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                    .padding(22).frame(minWidth: 280, idealWidth: 310, maxWidth: 370)
                    .disabled(busy)
                }
                .navigationTitle(document.frames[index].title)
            } else {
                ContentUnavailableView("No frame selected", systemImage: "rectangle.stack")
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .toolbar {
            ToolbarItemGroup {
                Button(action: exportImage) { Label("Export image", systemImage: "square.and.arrow.up") }
                    .disabled(selectedIndex.map { document.frames[$0].image == nil } ?? true)
                Button { showDelete = true } label: { Label("Delete frame", systemImage: "trash") }
                    .disabled(selectedIndex == nil || busy)
            }
        }
        .onAppear { if selectedID == nil { selectedID = document.frames.first?.id } }
        .alert("Couldn’t generate the frame", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
        .confirmationDialog("Delete this frame and its image?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete frame", role: .destructive, action: deleteFrame)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func addFrame() {
        let frame = StoryboardFrame(title: "Frame \(document.frames.count + 1)")
        document.frames.append(frame)
        selectedID = frame.id
    }
    private func deleteFrame() {
        guard let index = selectedIndex else { return }
        document.frames.remove(at: index)
        selectedID = document.frames.isEmpty ? nil : document.frames[min(index, document.frames.count - 1)].id
    }
    private func generate(_ index: Int) {
        let frame = document.frames[index]
        busy = true; status = "Preparing…"
        task = Task {
            do {
                let result = try await RenderService.shared.render(frame: frame) { update in
                    Task { @MainActor in status = update }
                }
                if let destination = document.frames.firstIndex(where: { $0.id == frame.id }) {
                    document.frames[destination].image = result.image
                    document.frames[destination].imageRevision = UUID()
                    document.frames[destination].renderedPrompt = result.prompt
                }
                status = "Frame ready"
            } catch {
                errorMessage = RenderService.userMessage(for: error)
                status = "Generation failed"
            }
            busy = false; task = nil
        }
    }
    private func exportImage() {
        guard let index = selectedIndex, let data = document.frames[index].image else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = document.frames[index].title + ".png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic); status = "Image exported" }
            catch { errorMessage = "The image couldn’t be saved.  Choose another location and try again." }
        }
    }
}

private struct FrameImage: View {
    let data: Data?
    let revision: UUID
    private static let cache = NSCache<NSString, NSImage>()
    var body: some View {
        if let image = image {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Rectangle().fill(.quaternary.opacity(0.4))
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(Image(systemName: "rectangle.dashed").foregroundStyle(.secondary))
        }
    }
    private var image: NSImage? {
        guard let data else { return nil }
        let key = revision.uuidString as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        Self.cache.countLimit = 40
        Self.cache.setObject(image, forKey: key)
        return image
    }
}
