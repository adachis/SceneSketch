import Foundation
import PDFKit

struct ParticipantExportChecks {
    static func run(image: Data) throws {
        var document = StoryboardDocument()
        let scene = document.scenes[0]
        let excluded = StoryScene(title: "EXCLUDED SCENE")
        document.scenes.append(excluded)
        let character = StoryEntity(kind: .character, name: "Mara")
        let prop = StoryEntity(kind: .prop, name: "Red mug")
        let location = StoryEntity(kind: .location, name: "Cafe")
        let offscreen = StoryEntity(kind: .character, name: "Rowan")
        document.entities = [character, prop, location, offscreen]
        document.frames = [
            StoryboardFrame(description: EntityTokens.token(character.id) + " holds " + EntityTokens.token(prop.id) + ". " + EntityTokens.token(character.id) + " waits in " + EntityTokens.token(location.id) + ". Rowan watches. TEXT-ONLY-MARKER", image: image, sceneID: scene.id),
            StoryboardFrame(description: "Mara puts down a red mug.", sceneID: scene.id),
            StoryboardFrame(description: EntityTokens.token(offscreen.id), image: image, sceneID: excluded.id)
        ]
        let shots = try StoryboardExporter.shots(document: document, scenes: [scene.id])
        precondition(shots.count == 2)
        precondition(shots[0].characters.map(\.id) == [character.id])
        precondition(shots[0].props.map(\.id) == [prop.id])
        precondition(shots[1].characters.isEmpty && shots[1].props.isEmpty)
        var options = StoryboardExportOptions()
        options.includeDescriptions = false; options.includeMetadata = false
        options.includeCharacters = true
        let characterPDF = PDFDocument(data: try StoryboardExporter.pdf(document: document, scenes: [scene.id], options: options))!.string ?? ""
        precondition(characterPDF.contains("Characters: Mara") && !characterPDF.contains("Props:"))
        precondition(!characterPDF.contains("TEXT-ONLY-MARKER") && !characterPDF.contains("Rowan"))
        options.includeCharacters = false; options.includeProps = true
        let propPDF = PDFDocument(data: try StoryboardExporter.pdf(document: document, scenes: [scene.id], options: options))!.string ?? ""
        precondition(propPDF.contains("Props: Red mug") && !propPDF.contains("Characters:"))
        let defaultCSV = try String(decoding: StoryboardExporter.csv(document: document, scenes: [scene.id]), as: UTF8.self)
        precondition(!defaultCSV.components(separatedBy: "\r\n")[0].contains("Characters"))
        let selectedCSV = try String(decoding: StoryboardExporter.csv(document: document, scenes: [scene.id], includeCharacters: true, includeProps: true), as: UTF8.self)
        precondition(selectedCSV.components(separatedBy: "\r\n")[0].hasSuffix("\"Characters\",\"Props\""))
        precondition(selectedCSV.components(separatedBy: "\r\n")[1].hasSuffix("\"Mara\",\"Red mug\""))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try StoryboardExporter.bundle(document: document, scenes: [scene.id], to: root, includeCharacters: true, includeProps: true)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("storyboard.json"))) as! [String: Any]
        let rows = json["shots"] as! [[String: Any]]
        precondition(rows.count == 2)
        precondition((rows[0]["characters"] as! [[String: Any]]).map { $0["name"] as! String } == ["Mara"])
        precondition((rows[0]["props"] as! [[String: Any]]).map { $0["name"] as! String } == ["Red mug"])
        precondition((rows[1]["characters"] as! [Any]).isEmpty && (rows[1]["props"] as! [Any]).isEmpty)
        document.entities[0].name = "Mara Renamed"
        let renamed = try StoryboardExporter.shots(document: document, scenes: [scene.id])
        precondition(renamed[0].characters[0].name == "Mara Renamed")
        print("PASS: token-only participant lists, deduplication, scene selection, independent PDF toggles, hidden descriptions, CSV/JSON options, and renaming")
    }
}
