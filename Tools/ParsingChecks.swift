import Foundation
import CoreGraphics

enum ParsingChecks {
    static func run() throws {
        let labels = ["ON THE TV SCREEN:", "ON THE TV SCREEN", "ON THE MONITOR", "INSERT:", "CLOSE ON MARA",
                      "MARA'S POV", "POV OF MARA", "THROUGH THE BINOCULARS", "MONTAGE:", "BACK TO SCENE"]
        for label in labels {
            let draft = ScreenplayImporter.parseText("INT. ROOM - NIGHT\n\nMara sits.\n\n\(label)\n\nA presenter stands beside a map.\n\nMara turns away.", title: "Labels")
            precondition(draft.frames.count == 3, "Split shot label: \(label)")
            precondition(draft.frames[1].sourceText.contains(label) && draft.frames[1].sourceText.contains("presenter"))
            precondition(!draft.entities.contains { $0.kind == .character && $0.name.normalizedName == label.normalizedName })
        }
        let lowerCaseAction = ScreenplayImporter.parseText("INT. ROOM - NIGHT\n\nShe points to:\n\nA locked door.", title: "Action")
        precondition(lowerCaseAction.frames.first?.sourceText == "She points to:")
        let upperCaseAction = ScreenplayImporter.parseText("INT. ROOM - NIGHT\n\nSHE POINTS TO:\n\nA locked door.", title: "Action")
        precondition(upperCaseAction.frames.count == 1 && upperCaseAction.frames[0].sourceText.contains("SHE POINTS TO:"))
        let cut = ScreenplayImporter.parseText("INT. ROOM - DAY\n\nMara waits.\n\nCUT TO:\n\nEXT. ROAD - NIGHT\n\nA car stops.", title: "Cut")
        precondition(cut.scenes.count == 2 && cut.frames.count == 2)
        precondition(cut.frames.allSatisfy { !$0.sourceText.contains("CUT TO:") })
        for transition in ["FADE TO:", "SMASH TO:", "FLASH TO:", "FADE TO BLACK.", "DISSOLVES TO:", "WIPE TO:", "> CUT TO:"] {
            let draft = ScreenplayImporter.parseText("INT. ROOM - DAY\n\nMara waits.\n\n\(transition)\n\nA car stops.", title: "Transition")
            precondition(draft.frames.count == 2 && !draft.frames.contains { $0.sourceText.contains(transition) })
        }
        let forced = ScreenplayImporter.parseText("INT. ROOM - DAY\n\n!MARA SHUTS THE DOOR\n\n@MARA\nWait.", title: "Forced elements")
        precondition(forced.frames.count == 1 && forced.frames[0].sourceText.contains("MARA SHUTS THE DOOR"))
        precondition(forced.frames[0].sourceText.contains("Mara: Wait."))
        let introduction = ScreenplayImporter.parseText("INT. ROOM - DAY\n\nA NEWS ANCHORWOMAN (20s) sits at a desk.\n\nANCHORWOMAN\nA storm is coming.", title: "Introduction")
        precondition(introduction.entities.filter { $0.kind == .character }.map(\.name) == ["Anchorwoman"])

        func p(_ kind: String, _ text: String, page: Bool = false) -> ScriptParagraph { .init(kind: kind, text: text, startsPage: page) }
        let continued = ScreenplayImporter.parse([p("Scene Heading", "INT. ROOM - DAY"), p("Action", "Mara opens the"), p("Action", "heavy door.", page: true)], title: "Continuation")
        precondition(continued.frames.count == 1 && continued.frames[0].sourceText == "Mara opens the heavy door.")
        let complete = ScreenplayImporter.parse([p("Scene Heading", "INT. ROOM - DAY"), p("Action", "Mara waits."), p("Action", "A car stops.", page: true)], title: "New paragraph")
        precondition(complete.frames.count == 2)
        let ambiguousPage = ScreenplayImporter.parse([p("Action", "MARA WAITS"), p("Action", "A car stops.", page: true)], title: "Ambiguous page break")
        precondition(ambiguousPage.frames.count == 2)
        let samePage = ScreenplayImporter.parse([p("Action", "Mara opens the"), p("Action", "heavy door.")], title: "Uncertain")
        precondition(samePage.frames.count == 2)
        let boundary = ScreenplayImporter.parse([p("Action", "Mara opens the"), p("Transition", "CUT TO:"), p("Action", "heavy door.", page: true)], title: "Transition")
        precondition(boundary.frames.count == 2)
        let sceneBoundary = ScreenplayImporter.parse([p("Scene Heading", "INT. ROOM - DAY"), p("Action", "ON THE TV SCREEN:"), p("Scene Heading", "EXT. ROAD - DAY"), p("Action", "A car stops.")], title: "Boundary")
        precondition(sceneBoundary.frames.count == 2 && sceneBoundary.frames[0].sceneID != sceneBoundary.frames[1].sceneID)
        let dialogueOnly = ScreenplayImporter.parse([p("Scene Heading", "INT. ROOM - DAY"), p("Character", "MARA"), p("Dialogue", "Wait."), p("Scene Heading", "EXT. ROAD - DAY"), p("Action", "A car stops.")], title: "Dialogue")
        precondition(dialogueOnly.frames[0].sceneID == dialogueOnly.scenes[0].id)
        precondition(dialogueOnly.frames[0].sourceText.contains("Mara: Wait."))

        var inDialogue = false
        let lines: [ScreenplayImporter.PositionedScriptLine] = [
            .init(text: "12A.", bounds: CGRect(x: 501, y: 790, width: 35, height: 12)),
            .init(text: "INT. ROOM - NIGHT", bounds: CGRect(x: 108, y: 750, width: 220, height: 12)),
            .init(text: "ON THE TV SCREEN", bounds: CGRect(x: 108, y: 726, width: 180, height: 12)),
            .init(text: "A presenter stands beside a map.", bounds: CGRect(x: 108, y: 702, width: 310, height: 12)),
            .init(text: "(CONTINUED)", bounds: CGRect(x: 501, y: 40, width: 60, height: 12))]
        let positioned = ScreenplayImporter.positionedParagraphs(lines, inDialogue: &inDialogue, leftMargin: 108)
        let pdfDraft = ScreenplayImporter.parse(positioned, title: "PDF")
        precondition(pdfDraft.scenes[0].title == "INT. ROOM - NIGHT")
        precondition(pdfDraft.frames.count == 1 && pdfDraft.frames[0].sourceText.contains("presenter"))
        inDialogue = true
        let dialoguePage: [ScreenplayImporter.PositionedScriptLine] = [
            .init(text: "MARA (CONT'D)", bounds: CGRect(x: 252, y: 750, width: 120, height: 12)),
            .init(text: "It is time.", bounds: CGRect(x: 180, y: 726, width: 150, height: 12))]
        let dialogue = ScreenplayImporter.positionedParagraphs(dialoguePage, inDialogue: &inDialogue, leftMargin: 108)
        precondition(dialogue.map(\.kind) == ["Character", "Dialogue"])

        let fdx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FinalDraft><Content>
        <Paragraph Type="Scene Heading"><Text>INT. ROOM - NIGHT</Text></Paragraph>
        <Paragraph Type="Shot"><Text>ON THE </Text><Text>TV SCREEN:</Text></Paragraph>
        <Paragraph Type="Action"><Text>A presenter stands beside a map.</Text></Paragraph>
        <Paragraph Type="Character"><Text>ANNOUNCER</Text></Paragraph>
        <Paragraph Type="Dialogue"><Text>A storm is coming.</Text></Paragraph>
        </Content></FinalDraft>
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".fdx")
        defer { try? FileManager.default.removeItem(at: url) }
        try fdx.write(to: url, atomically: true, encoding: .utf8)
        let fdxDraft = try ScreenplayImporter.read(url) { _ in }
        precondition(fdxDraft.frames.count == 1 && fdxDraft.frames[0].sourceText.contains("ON THE TV SCREEN:"))
        precondition(fdxDraft.frames[0].sourceText.contains("Announcer: A storm is coming."))
        print("PASS: shot labels, transitions, Fountain forcing, PDF continuation, dialogue margins, scene boundaries, and FDX Shot paragraphs")
    }
}
