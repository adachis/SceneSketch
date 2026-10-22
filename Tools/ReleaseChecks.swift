import Foundation
import SwiftUI
enum ReleaseChecks {
 @MainActor static func run() async throws {
  var doc = StoryboardDocument(); let original = doc
  let binding = Binding(get: { doc }, set: { doc = $0 })
  let undo = UndoManager(); undo.groupsByEvent = false
  var edit = doc; edit.title = "Test"
  undo.beginUndoGrouping(); DocumentEditing.apply(edit, to: binding, undoManager: undo); undo.endUndoGrouping()
  precondition(doc.title == "Test"); undo.undo(); precondition(doc == original); undo.redo(); precondition(doc.title == "Test")
  var frame = StoryboardFrame(description: "A child lowers the binoculars.")
  let id = UUID(); let oldSource = frame
  frame.storeRender(image: Data([1]), prompt: "One", seed: 1, source: oldSource, referenceIDs: [id])
  let firstID = frame.imageRevision; let newSource = frame
  frame.storeRender(image: Data([2]), prompt: "Two", seed: 2, source: newSource, referenceIDs: [])
  precondition(frame.history.count == 1 && frame.versions.count == 2)
  frame.selectVersion(firstID); precondition(frame.image == Data([1]) && frame.seed == 1 && frame.history.count == 1)
  frame.sceneID = doc.scenes[0].id; doc.frames = [frame]; doc.references = [ReferenceImage(id: id, name: "Old", data: Data([0]))]
  doc.removeUnusedReferences(); precondition(doc.references.count == 1)
  let restored = try StoryboardDocument(data: doc.encodedData()); precondition(restored == doc)
  let copy = frame.duplicated(); precondition(copy.id != frame.id && copy.image == nil && copy.history.isEmpty && copy.description == frame.description)
  precondition(ShotFilter.missing.includes(copy)); precondition(!ShotFilter.approved.includes(copy))
  precondition(ShotStaging.prepare(frame.description).contains("at waist level"))
  precondition(!PromptFidelity.preservesContent(original: "Mara lowers binoculars", candidate: "Mara uses binoculars"))
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  setenv("SCENESKETCH_RECOVERY_DIR", folder.path, 1)
  defer { try? FileManager.default.removeItem(at: folder) }
  let session = UUID(); try await RecoveryStorage.shared.save(doc, session: session)
  doc.title = "Updated"; try await RecoveryStorage.shared.save(doc, session: session)
  let entries = try await RecoveryStorage.shared.entries(); precondition(entries.count == 2)
  let recovered = try StoryboardDocument(data: Data(contentsOf: entries.first { $0.previous }!.id)); precondition(recovered.title == "Test")
  var approved = doc; approved.frames[0].approved = true; doc = approved
  var changed = doc; changed.frames[0].description += " Near a window."
  undo.beginUndoGrouping(); DocumentEditing.apply(changed, to: binding, undoManager: undo); undo.endUndoGrouping()
  precondition(!doc.frames[0].approved); undo.undo(); precondition(doc.frames[0].approved); undo.redo(); precondition(!doc.frames[0].approved)
  let current = folder.appendingPathComponent(session.uuidString + ".sketchboard")
  try Data("truncated".utf8).write(to: current, options: .atomic)
  let survivors = try await RecoveryStorage.shared.entries(); precondition(survivors.count == 1 && survivors[0].previous)
  var large = StoryboardDocument()
  large.frames = (0..<600).map { i in
   var frame = StoryboardFrame(title: "Shot \(i)", description: "A traveler waits on the platform.", image: Data(repeating: UInt8(i % 256), count: 65536), sceneID: large.scenes[0].id)
   frame.approved = i % 2 == 0
   return frame
  }
  let largeData = try large.encodedData(); let roundTrip = try StoryboardDocument(data: largeData)
  precondition(roundTrip.frames.count == 600 && roundTrip.frames[599].image == large.frames[599].image)
  try await RecoveryStorage.shared.save(large, session: UUID())
  print("PASS: 600-shot save/reopen, approval invalidation with Undo/Redo, and corrupt-current recovery fallback")
  print("PASS: Undo/Redo, render history, restored seed, schema 4 round trip, historical references, duplication, filters, prompt action guard, atomic recovery and previous snapshot")
 }
}

@MainActor
private struct EditableTextFixture: View {
    @Binding var document: StoryboardDocument
    let manager: UndoManager
    var body: some View {
        TokenTextEditor(text: Binding(get: { document.frames[0].description }, set: { value in
            var next = document; next.frames[0].description = value
            DocumentEditing.apply(next, to: $document, undoManager: manager)
        }), entities: document.entities, insertion: .constant(nil))
    }
}

extension ReleaseChecks {
    @MainActor static func editor() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let shortcuts = BoardAction.allCases.map { String($0.shortcut.character) + ":" + String($0.modifiers.rawValue) }
        precondition(Set(shortcuts).count == shortcuts.count)
        var doc = StoryboardDocument()
        let person = StoryEntity(kind: .character, name: "Mara")
        doc.entities = [person]; doc.frames[0].description = EntityTokens.token(person.id) + " waits."
        let before = doc.frames[0].description
        let manager = UndoManager(); manager.groupsByEvent = false
        let host = NSHostingView(rootView: EditableTextFixture(document: Binding(get: { doc }, set: { doc = $0 }), manager: manager))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host; host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let text = descendants(host).compactMap { $0 as? NSTextView }.first!
        precondition(text.accessibilityLabel() == L("Shot description"))
        manager.beginUndoGrouping()
        text.insertText(" Near the door.", replacementRange: NSRange(location: text.string.utf16.count, length: 0))
        manager.endUndoGrouping()
        precondition(doc.frames[0].description == before + " Near the door.")
        manager.undo(); precondition(doc.frames[0].description == before)
        manager.redo(); precondition(doc.frames[0].description == before + " Near the door.")
        window.contentView = nil
        print("PASS: unique menu shortcuts, accessible description field, native text insertion with pills, Undo and Redo")
    }
}
