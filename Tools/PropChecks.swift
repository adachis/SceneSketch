import Foundation

struct PropChecks {
    static func run() throws {
        let script = """
        INT. STATION - DAY

        MARA, 30s, short black hair, waits by the door.

        She lifts a battered red leather suitcase and a key.

        The suitcase has a brass clasp. She sets it down.

        She studies a silver pocket watch. They watch the train arrive.

        A gun lies on the table. There is no blue bottle here.
        """
        let draft = ScreenplayImporter.parseText(script, title: "Luggage")
        let props = draft.entities.filter { $0.kind == .prop }
        precondition(props.count == 2, "Only the described suitcase and watch should be imported: \(props)")
        let suitcase = props.first { $0.name.contains("Suitcase") }!
        precondition(suitcase.description.contains("battered red leather") && suitcase.description.contains("brass clasp"))
        let suitcaseShots = draft.frames.filter { $0.description.contains(EntityTokens.token(suitcase.id)) }
        precondition(suitcaseShots.count == 2)
        let watchShot = draft.frames.first { $0.sourceText.contains("pocket watch") }!
        precondition(watchShot.description.contains("They watch the train"))
        precondition(!props.contains { $0.name.contains("Gun") || $0.name.contains("Bottle") || $0.name.contains("Key") })
        let ambiguous = ScreenplayImporter.parseText("INT. ROOM - DAY\n\nA red suitcase sits beside a blue suitcase.\n\nThe suitcase moves.", title: "Two cases")
        precondition(ambiguous.entities.filter { $0.kind == .prop }.count == 2)
        precondition(EntityTokens.matches(ambiguous.frames[1].description).isEmpty)
        var document = draft.applying(to: StoryboardDocument())
        let restored = try StoryboardDocument(data: document.encodedData())
        precondition(restored.entities.filter { $0.kind == .prop }.count == 2)
        let appliedAgain = draft.applying(to: restored)
        precondition(appliedAgain.entities.count == restored.entities.count)
        let context = try StoryContext(frame: suitcaseShots[0], document: restored)
        let prompt = try context.prompt(sceneDescription: context.description)
        precondition(prompt.contains("Prop Battered Red Leather Suitcase") && !prompt.contains("Location Battered"))
        let duplicate = StoryEntity(kind: .prop, name: "Travel case", description: "A brass clasp.")
        document.entities.append(duplicate)
        document.frames[0].description += EntityTokens.token(duplicate.id)
        document.mergeEntity(duplicate.id, into: suitcase.id)
        precondition(!document.frames[0].description.contains(duplicate.id.uuidString))
        document.removeEntity(suitcase.id)
        precondition(!document.frames.contains { $0.description.contains(EntityTokens.token(suitcase.id)) })
        let appearance = PropAppearance.description(from: #"{"object":"pocket watch","colors":["silver","silver"],"materials":"metal","shape":"round","distinctive_features":"engraved rim","clothing":"red coat"}"#)
        precondition(appearance.contains("silver") && appearance.contains("engraved rim") && !appearance.contains("red coat"))
        print("PASS: described-prop extraction, bare-noun exclusion, unambiguous links, verb preservation, prop persistence, merge/delete, and appearance fields")
    }
}
