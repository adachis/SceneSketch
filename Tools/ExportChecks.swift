import Foundation
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ExportChecks {
    static func run(output: URL, image: URL) throws {
        var document = StoryboardDocument()
        document.title = "Café Layout Study"
        document.production = ProductionDetails(production: "Orchard Films", director: "Morgan Chen", artist: "Alex Rivera", revision: "Draft 2", date: "October 2026")
        let first = StoryScene(title: "INT. CAFÉ - MORNING")
        let second = StoryScene(title: "INT. CAFÉ - AFTERNOON")
        document.scenes = [first, second]; document.frames = []
        let character = StoryEntity(kind: .character, name: "Mara", description: "Short wavy hair.")
        document.entities = [character]
        let imageData = try Data(contentsOf: image)
        for (sceneIndex, scene) in document.scenes.enumerated() {
            for index in 0..<7 {
                var frame = StoryboardFrame(title: "Shot \(index + 1)", description: EntityTokens.token(character.id) + " waits beside the café table. The window is on the left.", image: index == 6 ? nil : imageData, sceneID: scene.id)
                frame.details.lens = "50 mm"; frame.details.duration = "4 sec"; frame.details.movement = "Slow dolly in"
                frame.details.dialogue = "She says, \"The coffee is here.\""
                if index == 0 && sceneIndex == 0 { frame.details.notes = String(repeating: "Preserve the screen direction and leave room above the subject. ", count: 85) + "LAST-NOTE" }
                document.frames.append(frame)
            }
        }
        let all = Set(document.scenes.map(\.id))
        let restored = try StoryboardDocument(data: document.encodedData())
        precondition(restored.version == 3 && restored.production == document.production && restored.frames[0].details == document.frames[0].details)
        let selected = try StoryboardExporter.shots(document: document, scenes: [second.id], includeUnrendered: false)
        precondition(selected.count == 6 && selected.allSatisfy { $0.scene.id == second.id })
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for orientation in ExportOrientation.allCases {
            for layout in ExportLayout.allCases {
                var options = StoryboardExportOptions(); options.orientation = orientation; options.layout = layout
                for paper in ExportPaper.allCases {
                    options.paper = paper
                    let data = try StoryboardExporter.pdf(document: document, scenes: all, options: options)
                    let pdf = PDFDocument(data: data)!
                    precondition(pdf.pageCount >= 2)
                    let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()
                    precondition(text.contains("LAST-NOTE") && text.contains("Mara") && !text.contains("[[entity:"))
                    let bounds = pdf.page(at: 0)!.bounds(for: .mediaBox)
                    precondition(abs(bounds.width - options.pageSize.width) < 0.1 && abs(bounds.height - options.pageSize.height) < 0.1)
                    if paper == .letter && ((orientation == .landscape && layout == .six) || (orientation == .portrait && layout == .three) || (orientation == .landscape && layout == .sixteen)) {
                        try data.write(to: output.appendingPathComponent("\(layout.rawValue)-panel-\(orientation.rawValue.lowercased()).pdf"))
                    }
                }
            }
        }
        let subset = try StoryboardExporter.pdf(document: document, scenes: [second.id], options: StoryboardExportOptions())
        precondition(!(PDFDocument(data: subset)!.string ?? "").contains(first.title))
        let bundle = output.appendingPathComponent(UUID().uuidString)
        try StoryboardExporter.bundle(document: document, scenes: [second.id], to: bundle)
        let contents = try FileManager.default.contentsOfDirectory(atPath: bundle.path)
        precondition(contents.filter { $0.hasSuffix(".png") }.count == 6)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: bundle.appendingPathComponent("storyboard.json"))) as! [String: Any]
        precondition((json["scenes"] as! [Any]).count == 1 && (json["shots"] as! [Any]).count == 7)
        let csv = try String(contentsOf: bundle.appendingPathComponent("shots.csv"), encoding: .utf8)
        precondition(csv.contains("She says, \"\"The coffee is here.\"\"") && csv.contains("Mara") && !csv.contains("[[entity:"))
        try FileManager.default.removeItem(at: bundle)
        print("PASS: 24 PDF layouts, full overflow notes, scene filtering, metadata round trip, CSV escaping, and image/data export")
    }
}
