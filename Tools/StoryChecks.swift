import Foundation
import SwiftUI
import AppKit
import PDFKit

@MainActor struct StoryChecks {
    static func run() throws {
        var doc = StoryboardDocument()
        var character = StoryEntity(kind: .character, name: "Mara", description: "Short black hair; angular face.")
        let location = StoryEntity(kind: .location, name: "Observatory", description: "A domed stone building.")
        let images = (0..<5).map { ReferenceImage(name: "Reference \($0)", data: Data([UInt8($0)])) }
        character.referenceIDs = images.map(\.id)
        doc.entities = [character, location]; doc.references = images
        doc.scenes[0].locationID = location.id
        doc.frames[0].description = EntityTokens.token(character.id) + " opens the door."
        let context = try StoryContext(frame: doc.frames[0], document: doc)
        precondition(context.description == "Mara opens the door.")
        precondition(context.references.count == 3 && context.missingSelectionCount == 2)
        let prompt = try context.prompt(sceneDescription: context.description); precondition(prompt.contains("angular face"))
        precondition(prompt.contains("wordless composition") && prompt.contains("blank panels"))
        let unlettered = RenderTextPolicy.prepare("A menu board and framed sign that says 'COFFEE' stand beside a woman.")
        precondition(!unlettered.contains("COFFEE") && !unlettered.contains("menu") && unlettered.contains("woman"))
        precondition(RenderTextPolicy.prepare("A woman uses sign language.") == "A woman uses sign language.")
        doc.entities[0].name = "Marisol"
        let renamed = try StoryContext(frame: doc.frames[0], document: doc); precondition(renamed.description == "Marisol opens the door.")
        doc.frames[0].selectedReferenceIDs = []
        let none = try StoryContext(frame: doc.frames[0], document: doc); precondition(none.references.isEmpty)
        let encoded = try doc.encodedData(); let restored = try StoryboardDocument(data: encoded)
        precondition(restored.entities.count == 2 && restored.references.count == 5 && restored.scenes.count == 1)
        doc.removeEntity(character.id)
        precondition(doc.frames[0].description == "Marisol opens the door." && doc.references.isEmpty)
        let clean = StableAppearance.description(from: #"{"hair_color":"black hair","face":"oval face","skin":"wearing a red coat","clothing":"blue jeans"}"#)
        precondition(clean.contains("black hair") && clean.contains("oval face") && !clean.contains("coat") && !clean.contains("jeans"))
        let script = """
        Title: Night Watch

        INT. OBSERVATORY - NIGHT

        MARA, 30s, short black hair, opens the dome.

        MARA
        The light is back.

        EXT. OBSERVATORY - DAWN

        Mara watches the ridge.

        JON
        We should go.
        """
        let draft = ScreenplayImporter.parseText(script, title: "Night Watch")
        precondition(draft.scenes.count == 2 && draft.frames.count == 2)
        precondition(draft.entities.filter { $0.kind == .character }.count == 2)
        precondition(draft.entities.filter { $0.kind == .location }.count == 1)
        precondition(draft.frames.allSatisfy { !EntityTokens.matches($0.description).isEmpty })
        let imported = draft.applying(to: StoryboardDocument())
        precondition(imported.scenes.count == 2 && imported.frames.count == 2)
        let repeated = draft.applying(to: imported)
        precondition(repeated.entities.count == imported.entities.count)
        var bad = doc.frames[0]; bad.selectedReferenceIDs = images.map(\.id)
        do { _ = try StoryContext(frame: bad, document: doc); preconditionFailure("Must reject over-limit input") } catch StoryContextError.tooManyReferences {}
        let legacy: [String: Any] = ["version": 1, "frames": [["id": UUID().uuidString, "title": "Legacy", "description": "An old frame.", "shot": "Wide shot", "seed": 22]]]
        let migrated = try StoryboardDocument(data: JSONSerialization.data(withJSONObject: legacy))
        precondition(migrated.frames[0].sceneID == migrated.scenes[0].id && migrated.version == 3)
        var mergeDoc = restored
        let duplicate = StoryEntity(kind: .character, name: "Alias", description: "Same person")
        mergeDoc.entities.append(duplicate)
        mergeDoc.frames[0].description += EntityTokens.token(duplicate.id)
        mergeDoc.mergeEntity(duplicate.id, into: character.id)
        precondition(!mergeDoc.entities.contains { $0.id == duplicate.id })
        precondition(!mergeDoc.frames[0].description.contains(duplicate.id.uuidString))
        precondition(mergeDoc.entities.first { $0.id == character.id }!.description.contains("Same person"))
        var richText = EntityTokens.token(character.id) + " enters."
        let component = TokenTextEditor(text: Binding(get: { richText }, set: { richText = $0 }), entities: [character], insertion: .constant(nil))
        let coordinator = component.makeCoordinator(); let textView = NSTextView(frame: .zero)
        coordinator.editor = textView; coordinator.refresh(richText, entities: [character])
        precondition(textView.string.contains("\u{FFFC}"))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification))
        precondition(richText == EntityTokens.token(character.id) + " enters.")
        var dialogue = false
        let lines = [
            ScreenplayImporter.PositionedScriptLine(text: "INT. LAB - NIGHT", bounds: CGRect(x:108,y:700,width:200,height:12)),
            .init(text: "MARA", bounds:CGRect(x:252,y:670,width:60,height:12)),
            .init(text: "GET OUT!", bounds:CGRect(x:180,y:658,width:80,height:12)),
            .init(text: "She closes the door.", bounds:CGRect(x:108,y:634,width:200,height:12))]
        let parsed = ScreenplayImporter.positionedParagraphs(lines, inDialogue: &dialogue)
        precondition(parsed.filter { $0.kind == "Character" }.map(\.text) == ["MARA"])
        precondition(parsed.contains { $0.kind == "Dialogue" && $0.text == "GET OUT!" })
        print("PASS: token attachment round trip, merge, and layout-aware dialogue detection")
        print("PASS: document migration, reference limits, persistent tokens, renaming, deletion, appearance safety, scene parsing, and import merge")
    }
    static func ocr() throws {
        let canvas = NSImage(size: NSSize(width: 612, height: 792)); canvas.lockFocus()
        NSColor.white.setFill(); NSRect(x:0,y:0,width:612,height:792).fill()
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font:font,.foregroundColor:NSColor.black]
        for (text,x,y) in [("INT. OBSERVATORY - NIGHT",108.0,700.0),("Mara opens the dome.",108,660),("MARA",252,620),("The light is back.",180,600)] {
            (text as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:attrs)
        }
        canvas.unlockFocus()
        let pdf = PDFDocument(); pdf.insert(PDFPage(image: canvas)!, at:0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf")
        defer { try? FileManager.default.removeItem(at:url) }
        precondition(pdf.write(to:url))
        let draft = try ScreenplayImporter.read(url) { _ in }
        precondition(draft.scenes.count == 1 && draft.frames.count >= 1)
        precondition(draft.entities.contains { $0.name.uppercased() == "MARA" })
        precondition(draft.warnings.contains { $0.contains("text recognition") })
        print("PASS: scanned PDF OCR, scene heading, and character detection")
    }

}
