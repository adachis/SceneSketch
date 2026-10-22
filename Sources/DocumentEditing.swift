import SwiftUI
import AppKit

@MainActor
enum DocumentEditing {
    static func apply(_ proposed: StoryboardDocument, to binding: Binding<StoryboardDocument>, undoManager: UndoManager?, name: String = L("Edit storyboard")) {
        let previous = binding.wrappedValue
        guard previous != proposed else { return }
        var next = proposed
        for index in next.frames.indices where next.frames[index].approved {
            let frame = next.frames[index]
            guard let old = previous.frames.first(where: { $0.id == frame.id }), old.approved else { continue }
            var linked = Set(EntityTokens.mentioned(frame.description, entities: next.entities).map(\.id))
            if let location = next.scenes.first(where: { $0.id == frame.sceneID })?.locationID { linked.insert(location) }
            let sceneChanged = previous.scenes.first(where: { $0.id == old.sceneID }) != next.scenes.first(where: { $0.id == frame.sceneID })
            if old.description != frame.description || old.shot != frame.shot || old.referenceIDs != frame.referenceIDs ||
                old.selectedReferenceIDs != frame.selectedReferenceIDs || old.imageRevision != frame.imageRevision || sceneChanged ||
                previous.entities.filter({ linked.contains($0.id) }) != next.entities.filter({ linked.contains($0.id) }) {
                next.frames[index].approved = false
            }
        }
        restore(next, to: binding, undoManager: undoManager, name: name)
    }

    private static func restore(_ value: StoryboardDocument, to binding: Binding<StoryboardDocument>, undoManager: UndoManager?, name: String) {
        let previous = binding.wrappedValue
        undoManager?.registerUndo(withTarget: DocumentUndoTarget.shared) { [weak undoManager] _ in
            restore(previous, to: binding, undoManager: undoManager, name: name)
        }
        undoManager?.setActionName(name)
        binding.wrappedValue = value
    }
}

@MainActor private final class DocumentUndoTarget: NSObject { static let shared = DocumentUndoTarget() }

actor RecoveryStorage {
    static let shared = RecoveryStorage()
    static func directory() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["SCENESKETCH_RECOVERY_DIR"] { return URL(fileURLWithPath: path) }
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("SceneSketch/Recovery", isDirectory: true)
    }
    func save(_ document: StoryboardDocument, session: UUID) throws {
        try Task.checkCancellation()
        let data = try document.encodedData()
        try Task.checkCancellation()
        let folder = try Self.directory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(session.uuidString + ".sketchboard")
        // Preserve a verified previous snapshot before atomically replacing the current one.
        if let previous = try? Data(contentsOf: url), (try? StoryboardDocument(data: previous)) != nil {
            try previous.write(to: folder.appendingPathComponent(session.uuidString + ".previous.sketchboard"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "sketchboard" && !$0.lastPathComponent.contains(".previous.") }
            .sorted { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast > (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast }
        for old in files.dropFirst(20) where old != url {
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.removeItem(at: old.deletingPathExtension().appendingPathExtension("previous.sketchboard"))
        }
    }
    func entries() throws -> [RecoveryEntry] {
        let folder = try Self.directory()
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "sketchboard" }.compactMap { url in
                guard let data = try? Data(contentsOf: url), let document = try? StoryboardDocument(data: data) else { return nil }
                return RecoveryEntry(id: url, title: document.title, date: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast,
                    shots: document.frames.count, previous: url.lastPathComponent.contains(".previous."))
            }.sorted { $0.date > $1.date }
    }
}

struct RecoveryEntry: Identifiable, Sendable {
    var id: URL
    var title: String
    var date: Date
    var shots: Int
    var previous: Bool
}

struct RecoveryView: View {
    let recover: (StoryboardDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [RecoveryEntry] = []
    @State private var selection: URL?
    @State private var confirm = false
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Recover storyboard")).font(.title2.bold())
            List(entries, selection: $selection) { entry in
                VStack(alignment: .leading) {
                    Text(entry.title + (entry.previous ? " — " + L("Previous snapshot") : ""))
                    Text(entry.date.formatted() + " · " + L("Shots: %@", String(entry.shots))).font(.caption).foregroundStyle(.secondary)
                }.tag(entry.id)
            }.overlay { if entries.isEmpty { ContentUnavailableView(L("No recovery snapshots"), systemImage: "clock.arrow.circlepath") } }
            if !message.isEmpty { Text(message).foregroundStyle(.red) }
            HStack {
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Recover")) { confirm = true }.disabled(selection == nil)
            }
        }.padding(24).frame(width: 620, height: 460)
        .task { do { entries = try await RecoveryStorage.shared.entries() } catch { message = L("Recovery snapshots couldn’t be read.") } }
        .confirmationDialog(L("Replace the current storyboard with this snapshot?"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L("Recover")) {
                guard let selection else { return }
                do { recover(try StoryboardDocument(data: Data(contentsOf: selection))); dismiss() }
                catch { message = L("This snapshot couldn’t be opened.") }
            }
        } message: { Text(L("You can undo this change.")) }
    }
}
