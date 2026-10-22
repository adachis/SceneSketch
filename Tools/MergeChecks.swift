import Foundation
import SwiftUI
import AppKit

enum MergeChecks {
    @MainActor static func selection() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let defaults = UserDefaults.standard
        let previousSetup = defaults.object(forKey: "hasOfferedModelSetup")
        defaults.set(true, forKey: "hasOfferedModelSetup")
        defer {
            if let previousSetup { defaults.set(previousSetup, forKey: "hasOfferedModelSetup") }
            else { defaults.removeObject(forKey: "hasOfferedModelSetup") }
        }
        var document = StoryboardDocument()
        document.frames = (1...3).map { StoryboardFrame(title: "Shot \($0)", description: "Action \($0).", sceneID: document.scenes[0].id) }
        let host = NSHostingView(rootView: BoardEditor(document: Binding(get: { document }, set: { document = $0 })))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        guard let list = descendants(host).compactMap({ $0 as? NSTableView }).first(where: { $0.numberOfRows >= 3 }) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        precondition(list.allowsMultipleSelection)
        let rows = IndexSet(integersIn: (list.numberOfRows - 2)..<list.numberOfRows)
        list.selectRowIndexes(rows, byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        precondition(list.selectedRowIndexes == rows)
        func findMerge(_ element: Any) -> (any NSAccessibilityProtocol)? {
            guard let element = element as? any NSAccessibilityProtocol else { return nil }
            if element.accessibilityRole() == .button && (element.accessibilityLabel() == L("Merge") || element.accessibilityTitle() == L("Merge")) { return element }
            for child in element.accessibilityChildren() ?? [] { if let found = findMerge(child) { return found } }
            return nil
        }
        guard let button = findMerge(host) else { throw CocoaError(.validationMissingMandatoryProperty) }
        precondition(button.accessibilityPerformPress())
        try await Task.sleep(for: .milliseconds(150))
        precondition(document.frames.count == 2)
        precondition(document.frames[1].description == "Action 2.\n\nAction 3.")
        print("PASS: native multiple selection reveals Merge and merges the selected range without activating a window")
    }

    @MainActor static func run() throws {
        var doc = StoryboardDocument()
        let scene = doc.scenes[0].id
        let person = StoryEntity(kind: .character, name: "Mara")
        doc.entities = [person]
        doc.references = (0..<5).map { ReferenceImage(name: "Reference \($0)", data: Data([UInt8($0)])) }
        var first = StoryboardFrame(title: "The screen", description: "ON THE TV SCREEN:", shot: .close, sceneID: scene)
        first.sourceText = first.description; first.referenceIDs = [doc.references[0].id]
        first.details.notes = "Keep the reflection."; first.details.lens = "50 mm"
        var second = StoryboardFrame(description: EntityTokens.token(person.id) + " presents the news.", sceneID: scene)
        second.sourceText = "Mara presents the news."; second.referenceIDs = Array(doc.references.dropFirst().map(\.id))
        second.selectedReferenceIDs = [doc.references[1].id, doc.references[2].id, doc.references[3].id]
        second.details.notes = "The room is dark."; second.details.dialogue = "A storm is coming."
        second.storeRender(image: Data([1]), prompt: "First image", seed: 11, source: second, referenceIDs: [doc.references[3].id])
        second.storeRender(image: Data([2]), prompt: "Second image", seed: 12, source: second, referenceIDs: [doc.references[4].id])
        var third = StoryboardFrame(description: "The map flashes.", sceneID: scene)
        third.storeRender(image: Data([3]), prompt: "Third image", seed: 13, source: third, referenceIDs: [])
        let untouched = StoryboardFrame(description: "Mara turns away.", sceneID: scene)
        doc.frames = [first, second, untouched, third]
        let original = doc
        let selected: Set<UUID> = [third.id, first.id, second.id]
        precondition(doc.canMergeShots(selected))
        precondition(doc.mergeShots(selected) == first.id)
        let merged = doc.frames[0]
        precondition(doc.frames.count == 2 && doc.frames[1] == untouched)
        precondition(merged.title == first.title && merged.shot == .close && !merged.approved)
        precondition(merged.description == [first.description, second.description, third.description].joined(separator: "\n\n"))
        precondition(merged.sourceText.contains("Mara presents") && merged.details.notes.contains("room is dark"))
        precondition(merged.details.lens == "50 mm" && merged.details.dialogue == second.details.dialogue)
        precondition(merged.image == Data([2]) && merged.seed == 12 && merged.versions.count == 3)
        precondition(Set(merged.versions.map(\.image)) == Set([Data([1]), Data([2]), Data([3])]))
        precondition(merged.referenceIDs.count == 5 && merged.selectedReferenceIDs == nil)
        doc.removeUnusedReferences(); precondition(doc.references.count == 5)
        let context = try StoryContext(frame: merged, document: doc)
        precondition(context.references.count <= StoryContext.referenceLimit)
        let restored = try StoryboardDocument(data: doc.encodedData())
        precondition(restored == doc)

        let binding = Binding(get: { doc }, set: { doc = $0 })
        let manager = UndoManager(); manager.groupsByEvent = false
        doc = original; var next = doc; next.mergeShots(selected)
        manager.beginUndoGrouping(); DocumentEditing.apply(next, to: binding, undoManager: manager, name: "Merge shots"); manager.endUndoGrouping()
        manager.undo(); precondition(doc == original)
        manager.redo(); precondition(doc == next)
        var invalid = original
        precondition(invalid.mergeShots([first.id]) == nil && invalid == original)
        precondition(invalid.mergeShots([first.id, UUID()]) == nil && invalid == original)
        invalid.frames[1].sceneID = UUID(); let crossScene = invalid
        precondition(invalid.mergeShots([first.id, second.id]) == nil && invalid == crossScene)
        var collision = original
        var older = second.currentVersion!
        older.image = Data([9]); older.description = "A different saved image."
        collision.frames[0].history = [older]
        collision.mergeShots([first.id, second.id])
        precondition(collision.frames[0].versions.count == 3)
        precondition(Set(collision.frames[0].versions.map(\.image)) == Set([Data([9]), Data([1]), Data([2])]))
        _ = try StoryboardDocument(data: collision.encodedData())
        print("PASS: ordered multi-shot merge, all images and references, source text, details, reference budget, save/reopen, and single-step Undo/Redo")
    }
}
