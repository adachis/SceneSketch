import Foundation
import PDFKit
import Vision

struct ScreenplayDraft: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var entities: [StoryEntity]
    var scenes: [StoryScene]
    var frames: [StoryboardFrame]
    var warnings: [String]

    func applying(to original: StoryboardDocument) -> StoryboardDocument {
        var result = original
        var mapping: [UUID: UUID] = [:]
        for entity in entities {
            if let index = result.entities.firstIndex(where: { $0.kind == entity.kind && $0.name.normalizedName == entity.name.normalizedName }) {
                mapping[entity.id] = result.entities[index].id
                if result.entities[index].description.isEmpty { result.entities[index].description = entity.description }
            } else { result.entities.append(entity); mapping[entity.id] = entity.id }
        }
        let empty = result.frames.count == 1 && result.frames[0].description.isEmpty && result.frames[0].image == nil
        if empty { result.frames = []; result.scenes = [] }
        var sceneMapping: [UUID: UUID] = [:]
        for var scene in scenes {
            let oldID = scene.id
            if result.scenes.contains(where: { $0.id == scene.id }) { scene.id = UUID() }
            sceneMapping[oldID] = scene.id
            scene.locationID = scene.locationID.flatMap { mapping[$0] }
            result.scenes.append(scene)
        }
        for var frame in frames {
            if result.frames.contains(where: { $0.id == frame.id }) { frame.id = UUID() }
            frame.sceneID = frame.sceneID.flatMap { sceneMapping[$0] }
            for (old, new) in mapping { frame.description = frame.description.replacingOccurrences(of: EntityTokens.token(old), with: EntityTokens.token(new)) }
            result.frames.append(frame)
        }
        if original.title == "Untitled story" || original.title == L("Untitled story") { result.title = title }
        return result
    }
}

extension String {
    var normalizedName: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).replacingOccurrences(of: #"[.,]"#, with: " ", options: .regularExpression).split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}

struct ScriptParagraph: Sendable {
    var kind: String
    var text: String
}

enum ScreenplayImporter {
    static func read(_ url: URL, progress: @escaping @Sendable (String) -> Void) throws -> ScreenplayDraft {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size < 50_000_000 else { throw ImportError.tooLarge }
        let title = url.deletingPathExtension().lastPathComponent
        switch url.pathExtension.lowercased() {
        case "fdx":
            let reader = FDXReader(); let parser = XMLParser(data: try Data(contentsOf: url)); parser.delegate = reader
            parser.shouldResolveExternalEntities = false
            guard parser.parse() else { throw ImportError.invalid }
            return parse(reader.paragraphs, title: title)
        case "pdf":
            guard let pdf = PDFDocument(url: url), pdf.pageCount <= 400 else { throw ImportError.tooLarge }
            var paragraphs: [ScriptParagraph] = []; var ocrCount = 0; var inDialogue = false
            for index in 0..<pdf.pageCount {
                guard let page = pdf.page(at: index) else { continue }
                progress(L("Reading page %@ of %@…", String(index + 1), String(pdf.pageCount)))
                let text = page.string ?? ""
                var lines: [PositionedScriptLine] = []
                if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 30 {
                    lines = (page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []).compactMap { selection in
                        guard let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                        return PositionedScriptLine(text: text, bounds: selection.bounds(for: page))
                    }
                } else {
                    ocrCount += 1
                    let thumbnail = page.thumbnail(of: CGSize(width: 1600, height: 2100), for: .mediaBox)
                    var rect = CGRect(origin: .zero, size: thumbnail.size)
                    guard let image = thumbnail.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { continue }
                    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["en-US"]; request.usesLanguageCorrection = true
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    lines = (request.results ?? []).compactMap { observation in
                        guard let value = observation.topCandidates(1).first?.string else { return nil }
                        let r = observation.boundingBox
                        return PositionedScriptLine(text: value, bounds: CGRect(x:r.minX*612,y:r.minY*792,width:r.width*612,height:r.height*792))
                    }.sorted { $0.bounds.midY > $1.bounds.midY }
                }
                paragraphs += positionedParagraphs(lines, inDialogue: &inDialogue)
            }
            var draft = parse(paragraphs, title: title)
            if ocrCount > 0 { draft.warnings.append(L("Pages read with text recognition: %@. Review names, scene headings, and shot breaks.", String(ocrCount))) }
            return draft
        default:
            return parseText(try String(contentsOf: url, encoding: .utf8), title: title)
        }
    }

    struct PositionedScriptLine {
        var text: String
        var bounds: CGRect
    }
    static func positionedParagraphs(_ input: [PositionedScriptLine], inDialogue: inout Bool) -> [ScriptParagraph] {
        let lines = input.filter {
            !$0.text.matches(#"^\d+\.?([ \t]+\d+\.?)?$"#) && !$0.text.matches(#"^(?:\(?CONTINUED\)?[:.]?|\(MORE\))$"#)
        }
        let left = lines.map(\.bounds.minX).min() ?? 72
        var result: [ScriptParagraph] = []; var current = ""; var kind = "Action"; var previous: CGRect?
        func flush() { if !current.isEmpty { result.append(ScriptParagraph(kind: kind, text: current)); current = "" } }
        for line in lines {
            let text = line.text
            if let last = result.indices.last, result[last].kind == "Scene Heading", current.isEmpty,
               text == text.uppercased(), line.bounds.minX <= left+15,
               (previous.map { $0.minY - line.bounds.maxY < line.bounds.height } ?? false), !isHeading(text) {
                result[last].text += " " + text; previous = line.bounds; continue
            }
            if isHeading(text) {
                flush(); result.append(.init(kind: "Scene Heading", text: text)); inDialogue = false; previous = line.bounds; continue
            }
            if text.hasSuffix("TO:") || ["FADE IN:", "FADE OUT."].contains(text.uppercased()) { flush(); inDialogue = false; previous = line.bounds; continue }
            if line.bounds.minX >= left+105 && isCue(text) {
                flush()
                if let last = result.indices.last, result[last].kind == "Character", (previous.map { $0.minY - line.bounds.maxY < 4 } ?? false) {
                    result[last].text += " " + text
                } else { result.append(.init(kind: "Character", text: text)) }
                inDialogue = true; previous = line.bounds; continue
            }
            if inDialogue && text.hasPrefix("(") { previous = line.bounds; continue }
            let nextKind = inDialogue && line.bounds.minX >= left+35 ? "Dialogue" : "Action"
            if nextKind == "Action" { inDialogue = false }
            let gap = previous.map { $0.minY - line.bounds.maxY } ?? 0
            if nextKind != kind || gap > max(5, line.bounds.height*0.55) { flush() }
            kind = nextKind
            current += current.isEmpty ? text : " " + text
            previous = line.bounds
        }
        flush(); return result
    }

    static func parseText(_ text: String, title: String) -> ScreenplayDraft {
        let withoutComments = text.replacingOccurrences(of: #"/\*[\s\S]*?\*/|\[\[[\s\S]*?\]\]"#, with: "", options: .regularExpression)
        let lines = withoutComments.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var paragraphs: [ScriptParagraph] = []; var action: [String] = []; var dialogue = false
        func flush() { if !action.isEmpty { paragraphs.append(.init(kind: dialogue ? "Dialogue" : "Action", text: action.joined(separator: " "))); action = [] } }
        for (index, line) in lines.enumerated() {
            if line.isEmpty { flush(); dialogue = false; continue }
            if line.first == "#" || line == "===" || line.first == "~" { continue }
            if isHeading(line) { flush(); dialogue = false; paragraphs.append(.init(kind: "Scene Heading", text: line)); continue }
            if line.hasSuffix("TO:") || ["FADE IN:", "FADE OUT.", "CUT TO BLACK."].contains(line.uppercased()) { flush(); dialogue = false; continue }
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            let isolated = index == 0 || lines[index - 1].isEmpty
            if (line.first == "@" || isolated), isCue(line), !next.isEmpty {
                flush(); paragraphs.append(.init(kind: "Character", text: line)); dialogue = true
            } else if line.first == "(" && dialogue { continue }
            else { action.append(line) }
        }
        flush()
        return parse(paragraphs, title: title)
    }

    static func isHeading(_ value: String) -> Bool {
        value.replacingOccurrences(of: #"^\d+[A-Z]?\s+"#, with: "", options: .regularExpression).range(of: #"^(?:\.(?=[A-Za-z])|(?:INT\.?/EXT\.?|EXT\.?/INT\.?|INT\.?|EXT\.?|I/E\.?)\s)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func isCue(_ value: String) -> Bool {
        let text = cleanCue(value)
        return !text.isEmpty && text.count < 45 && !text.contains(":") && !text.contains("!") && !text.contains("?") && (!text.hasSuffix(".") || text.hasSuffix("SR.") || text.hasSuffix("JR.")) && (value.first == "@" || text == text.uppercased()) && text.rangeOfCharacter(from: .letters) != nil
    }
    private static func cleanCue(_ value: String) -> String {
        value.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "@^ "))
    }
    static func parse(_ paragraphs: [ScriptParagraph], title: String) -> ScreenplayDraft {
        var entities: [StoryEntity] = []
        let firstHeading = paragraphs.firstIndex { $0.kind == "Scene Heading" }
        for (index, paragraph) in paragraphs.enumerated() where paragraph.kind == "Character" {
            if let firstHeading, index < firstHeading { continue }
            let name = cleanCue(paragraph.text).capitalized
            if !name.isEmpty && !entities.contains(where: { $0.kind == .character && $0.name.normalizedName == name.normalizedName }) { entities.append(.init(kind: .character, name: name)) }
        }
        // Preserve explicit introductions instead of inventing missing appearance details.
        let intro = try! NSRegularExpression(pattern: #"\b([A-Z][A-Z' -]{1,28})(?:,|\s*\()\s*(\d{1,2}(?:s)?)[,)]\s*([^.!?\n]*)"#)
        for paragraph in paragraphs where paragraph.kind == "Action" {
            let value = paragraph.text as NSString
            for match in intro.matches(in: paragraph.text, range: NSRange(location: 0, length: value.length)) {
                let name = value.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces).capitalized
                let age = value.substring(with: match.range(at: 2))
                let rawDetails = value.substring(with: match.range(at: 3))
                let end = rawDetails.range(of: #"\b(?:opens?|walks?|runs?|looks?|enters?|sits?|stands?|says?|wears?|wearing|carries?|carrying|peers?|interviewed)\b"#, options: [.regularExpression, .caseInsensitive])?.lowerBound ?? rawDetails.endIndex
                let details = String(rawDetails[..<end])
                let description = (age + ", " + details).trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                if let i = entities.firstIndex(where: { $0.kind == .character && $0.name.normalizedName == name.normalizedName }) { if entities[i].description.isEmpty { entities[i].description = description } }
                else { entities.append(StoryEntity(kind: .character, name: name, description: description)) }
            }
        }
        let propMentions = ScreenplayProps.consolidated(paragraphs.enumerated().filter { index, paragraph in
            paragraph.kind == "Action" && (firstHeading == nil || index > firstHeading!)
        }.flatMap { ScreenplayProps.mentions(in: $0.element.text) })
        for mention in propMentions {
            if let index = entities.firstIndex(where: { $0.kind == .prop && $0.name.normalizedName == mention.name.normalizedName }) {
                if !entities[index].description.localizedCaseInsensitiveContains(mention.phrase) { entities[index].description += "; " + mention.phrase }
            } else { entities.append(StoryEntity(kind: .prop, name: mention.name, description: mention.phrase)) }
        }
        var scenes: [StoryScene] = []; var frames: [StoryboardFrame] = []; var speaker = ""
        for (index, paragraph) in paragraphs.enumerated() {
            let text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let firstHeading, index < firstHeading { continue }
            if paragraph.kind == "Scene Heading" {
                let heading = text.replacingOccurrences(of: #"^\d+[A-Z]?\s+"#, with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: ". ")).replacingOccurrences(of: #"\s*#[^#]+#\s*$|\s+\d+[A-Z]?$"#, with: "", options: .regularExpression)
                let name = heading.replacingOccurrences(of: #"^(?:INT\.?/EXT\.?|EXT\.?/INT\.?|INT\.?|EXT\.?|I/E\.?)\s+"#, with: "", options: [.regularExpression, .caseInsensitive]).replacingOccurrences(of: #"\s+[-–—]+\s+(?:DAY|NIGHT|DAWN|DUSK|MORNING|EVENING|AFTERNOON|CONTINUOUS|LATER|SAME).*"#, with: "", options: [.regularExpression, .caseInsensitive]).capitalized
                let location: StoryEntity
                if let existing = entities.first(where: { $0.kind == .location && $0.name.normalizedName == name.normalizedName }) { location = existing }
                else { location = StoryEntity(kind: .location, name: name); entities.append(location) }
                scenes.append(StoryScene(title: heading, locationID: location.id, sourceText: text)); speaker = ""
            } else if paragraph.kind == "Character" { speaker = cleanCue(text).capitalized }
            else {
                if scenes.isEmpty { scenes.append(StoryScene(title: L("Scene 1"))) }
                let sceneIndex = scenes.count - 1
                scenes[sceneIndex].sourceText += "\n\n" + (paragraph.kind == "Dialogue" ? speaker + ": " : "") + text
                if paragraph.kind == "Action" {
                    if let locationID = scenes[sceneIndex].locationID, let locationIndex = entities.firstIndex(where: { $0.id == locationID }), entities[locationIndex].description.isEmpty {
                        let sentences = text.components(separatedBy: ". ").filter { sentence in
                            sentence.range(of: #"\b(walls?|floor|ceiling|room|road|street|building|ridge|field|forest|river|mountain|door|window|house|hall|cave)\b"#, options: [.regularExpression,.caseInsensitive]) != nil &&
                            !entities.filter { $0.kind == .character }.contains { sentence.localizedCaseInsensitiveContains($0.name) }
                        }
                        entities[locationIndex].description = String(sentences.joined(separator: ". ").prefix(280))
                    }
                    var description = ScreenplayProps.link(text, mentions: propMentions, entities: entities)
                    for entity in entities where entity.kind == .character {
                        let regex = try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: entity.name) + "(?![\\p{L}\\p{N}])", options: .caseInsensitive)
                        description = regex.stringByReplacingMatches(in: description, range: NSRange(location: 0, length: (description as NSString).length), withTemplate: EntityTokens.token(entity.id))
                    }
                    var frame = StoryboardFrame(title: L("Shot %@", String(frames.filter { $0.sceneID == scenes[sceneIndex].id }.count + 1)), description: description, sceneID: scenes[sceneIndex].id)
                    frame.sourceText = text; frames.append(frame)
                } else if paragraph.kind == "Dialogue" {
                    if let i = frames.indices.last, frames[i].sceneID == scenes[sceneIndex].id { frames[i].sourceText += "\n" + speaker + ": " + text }
                }
            }
        }
        for scene in scenes where !frames.contains(where: { $0.sceneID == scene.id }) {
            frames.append(StoryboardFrame(title: L("Shot %@", "1"), description: "Establishing view of \(entities.first { $0.id == scene.locationID }?.name ?? scene.title).", sceneID: scene.id))
        }
        var warnings = [L("Shot breaks are proposed from action paragraphs.  Review staging before rendering.")]
        if firstHeading == nil { warnings.append(L("No standard scene headings were found.  The text was placed in one scene.")) }
        return ScreenplayDraft(title: title, entities: entities, scenes: scenes, frames: frames, warnings: warnings)
    }
}

private final class FDXReader: NSObject, XMLParserDelegate {
    var paragraphs: [ScriptParagraph] = []
    private var kind: String?; private var text = ""; private var inText = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "Paragraph" { kind = attributeDict["Type"]; text = "" }
        if elementName == "Text" { inText = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { text += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Text" { inText = false }
        if elementName == "Paragraph", let kind { paragraphs.append(.init(kind: kind, text: text)); self.kind = nil }
    }
}

enum ImportError: LocalizedError {
    case tooLarge, invalid
    var errorDescription: String? { self == .tooLarge ? L("Choose a screenplay smaller than 50 MB and 400 pages.") : L("This screenplay couldn’t be read.  Try a PDF, Final Draft, Fountain, or UTF-8 text file.") }
}

private extension String {
    func matches(_ pattern: String) -> Bool { range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
}
