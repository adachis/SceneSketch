import Foundation
import CoreGraphics
import CoreText
import ImageIO

enum ExportPaper: String, CaseIterable, Identifiable, Codable, Sendable {
    case letter = "US Letter", a4 = "A4"
    var id: String { rawValue }
    var size: CGSize { self == .letter ? CGSize(width: 612, height: 792) : CGSize(width: 595.28, height: 841.89) }
}

enum ExportOrientation: String, CaseIterable, Identifiable, Codable, Sendable {
    case landscape = "Landscape", portrait = "Portrait"
    var id: String { rawValue }
}

enum ExportLayout: Int, CaseIterable, Identifiable, Codable, Sendable {
    case two = 2, three = 3, four = 4, six = 6, twelve = 12, sixteen = 16
    var id: Int { rawValue }
    var label: String { "\(rawValue) panels" }
    func columns(_ orientation: ExportOrientation) -> Int {
        if orientation == .portrait {
            switch self { case .two, .three: 1; case .four, .six: 2; case .twelve: 3; case .sixteen: 4 }
        } else {
            switch self { case .two, .four: 2; case .three, .six: 3; case .twelve, .sixteen: 4 }
        }
    }
}

struct StoryboardExportOptions: Equatable, Sendable {
    var paper = ExportPaper.letter
    var orientation = ExportOrientation.landscape
    var layout = ExportLayout.six
    var includeDescriptions = true
    var includeMetadata = true
    var includeUnrendered = true
    var newPagePerScene = true
    var pageSize: CGSize {
        let s = paper.size
        return orientation == .landscape ? CGSize(width: s.height, height: s.width) : s
    }
}

struct ExportShot: Sendable {
    let sceneNumber: Int
    let scene: StoryScene
    let number: String
    let frame: StoryboardFrame
    let description: String
    var label: String { L("Scene %@ · Shot %@", String(sceneNumber), number) }
}

enum StoryboardExporter {
    static func shots(document: StoryboardDocument, scenes: Set<UUID>, includeUnrendered: Bool = true) throws -> [ExportShot] {
        var result: [ExportShot] = []
        for (sceneIndex, scene) in document.scenes.enumerated() where scenes.contains(scene.id) {
            for (index, frame) in document.frames.filter({ $0.sceneID == scene.id }).enumerated() {
                if !includeUnrendered && frame.image == nil { continue }
                result.append(ExportShot(sceneNumber: sceneIndex + 1, scene: scene,
                    number: frame.details.number.isEmpty ? String(index + 1) : frame.details.number,
                    frame: frame, description: try EntityTokens.resolve(frame.description, entities: document.entities)))
            }
        }
        guard !result.isEmpty else { throw ExportError.noShots }
        return result
    }

    static func pdf(document: StoryboardDocument, scenes: Set<UUID>, options: StoryboardExportOptions) throws -> Data {
        let shots = try shots(document: document, scenes: scenes, includeUnrendered: options.includeUnrendered)
        let size = options.pageSize
        let columns = options.layout.columns(options.orientation), rows = options.layout.rawValue / columns
        let gap: CGFloat = 14, margin: CGFloat = 30, top: CGFloat = 82, bottom: CGFloat = 30
        let cardSize = CGSize(width: (size.width - 2 * margin - CGFloat(columns - 1) * gap) / CGFloat(columns),
                              height: (size.height - top - bottom - CGFloat(rows - 1) * gap) / CGFloat(rows))
        var pages: [[ExportShot]] = [], current: [ExportShot] = []
        for shot in shots {
            if current.count == options.layout.rawValue || (options.newPagePerScene && current.last?.scene.id != shot.scene.id && !current.isEmpty) {
                pages.append(current); current = []
            }
            current.append(shot)
        }
        if !current.isEmpty { pages.append(current) }
        var continuations: [(String, String)] = []
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ExportError.encoding }
        for (pageIndex, page) in pages.enumerated() {
            try Task.checkCancellation()
            beginPage(context, size: size)
            header(context, document: document, scene: options.newPagePerScene ? page.first?.scene.title : nil, size: size, metadata: options.includeMetadata)
            for (index, shot) in page.enumerated() {
                let x = margin + CGFloat(index % columns) * (cardSize.width + gap)
                let y = top + CGFloat(index / columns) * (cardSize.height + gap)
                let card = CGRect(origin: CGPoint(x: x, y: y), size: cardSize)
                let overflow = drawCard(context, shot: shot, card: card, height: size.height, options: options)
                if !overflow.isEmpty { continuations.append((shot.label + " — " + shot.frame.title, overflow)) }
            }
            footer(context, size: size, page: pageIndex + 1)
            context.endPDFPage()
        }
        var pageNumber = pages.count
        for (title, body) in continuations {
            var remaining = body
            while !remaining.isEmpty {
                try Task.checkCancellation()
                pageNumber += 1
                beginPage(context, size: size)
                header(context, document: document, scene: L("Shot notes"), size: size, metadata: options.includeMetadata)
                _ = text(context, title, rect: CGRect(x: margin, y: 82, width: size.width - 2 * margin, height: 34), height: size.height, fontSize: 12, bold: true)
                let used = text(context, remaining, rect: CGRect(x: margin, y: 122, width: size.width - 2 * margin, height: size.height - 162), height: size.height, fontSize: 10)
                guard used > 0 else { throw ExportError.encoding }
                remaining = (remaining as NSString).substring(from: used)
                footer(context, size: size, page: pageNumber)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    private static func drawCard(_ context: CGContext, shot: ExportShot, card: CGRect, height: CGFloat, options: StoryboardExportOptions) -> String {
        let inset: CGFloat = 7
        let labelHeight: CGFloat = options.includeMetadata ? 30 : 18
        context.setStrokeColor(gray: 0.7, alpha: 1); context.setLineWidth(0.5)
        context.stroke(flip(card, height))
        _ = text(context, shot.label, rect: CGRect(x: card.minX + inset, y: card.minY + 5, width: card.width - inset * 2, height: 13), height: height, fontSize: 8, bold: true)
        if options.includeMetadata {
            let details = [L(shot.frame.shot.rawValue), shot.frame.details.lens, shot.frame.details.duration].filter { !$0.isEmpty }.joined(separator: " · ")
            _ = text(context, details, rect: CGRect(x: card.minX + inset, y: card.minY + 18, width: card.width - inset * 2, height: 12), height: height, fontSize: 7)
        }
        let sideNotes = options.includeDescriptions && options.orientation == .portrait && options.layout.rawValue <= 3
        let imageWidth = sideNotes ? (card.width - inset * 3) * 0.64 : card.width - inset * 2
        let availableHeight = max(20, card.height - labelHeight - (options.includeDescriptions && !sideNotes ? 40 : 9))
        let imageHeight = min(imageWidth * 9 / 16, availableHeight)
        let imageRect = CGRect(x: card.minX + inset, y: card.minY + labelHeight, width: imageWidth, height: imageHeight)
        if let imageData = shot.frame.image, let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let scale = min(imageRect.width / CGFloat(image.width), imageRect.height / CGFloat(image.height))
            let rendered = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let rect = CGRect(x: imageRect.midX - rendered.width / 2, y: imageRect.midY - rendered.height / 2, width: rendered.width, height: rendered.height)
            context.draw(image, in: flip(rect, height))
        } else {
            context.setFillColor(gray: 0.96, alpha: 1); context.fill(flip(imageRect, height))
            _ = text(context, L("Not rendered"), rect: CGRect(x: imageRect.minX + 6, y: imageRect.midY - 6, width: imageRect.width - 12, height: 14), height: height, fontSize: 8)
        }
        guard options.includeDescriptions else { return "" }
        let notes = noteText(shot, metadata: options.includeMetadata)
        let rect = sideNotes
            ? CGRect(x: imageRect.maxX + inset, y: card.minY + labelHeight, width: card.maxX - imageRect.maxX - inset * 2, height: card.height - labelHeight - 23)
            : CGRect(x: card.minX + inset, y: imageRect.maxY + 6, width: card.width - inset * 2, height: max(1, card.maxY - imageRect.maxY - 23))
        let used = text(context, notes, rect: rect, height: height, fontSize: options.layout.rawValue >= 12 ? 7 : 9)
        if used < (notes as NSString).length {
            _ = text(context, L("Continued in shot notes"), rect: CGRect(x: card.minX + inset, y: card.maxY - 14, width: card.width - inset * 2, height: 11), height: height, fontSize: 7)
            return notes
        }
        return ""
    }

    private static func noteText(_ shot: ExportShot, metadata: Bool) -> String {
        var parts = [shot.description]
        if metadata {
            if !shot.frame.details.movement.isEmpty { parts.append(L("Camera: %@", shot.frame.details.movement)) }
            if !shot.frame.details.dialogue.isEmpty { parts.append(L("Dialogue: %@", shot.frame.details.dialogue)) }
            if !shot.frame.details.notes.isEmpty { parts.append(L("Notes: %@", shot.frame.details.notes)) }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func beginPage(_ context: CGContext, size: CGSize) {
        var bounds = CGRect(origin: .zero, size: size)
        let data = Data(bytes: &bounds, count: MemoryLayout<CGRect>.size)
        context.beginPDFPage([kCGPDFContextMediaBox as String: data] as CFDictionary)
        context.setFillColor(gray: 1, alpha: 1); context.fill(CGRect(origin: .zero, size: size))
    }

    private static func header(_ context: CGContext, document: StoryboardDocument, scene: String?, size: CGSize, metadata: Bool) {
        _ = text(context, document.title, rect: CGRect(x: 30, y: 23, width: size.width - 60, height: 23), height: size.height, fontSize: 16, bold: true)
        var subtitle = [scene ?? L("Storyboard")]
        if metadata {
            let p = document.production
            subtitle += [p.production, p.director.isEmpty ? "" : L("Director: %@", p.director), p.artist.isEmpty ? "" : L("Artist: %@", p.artist), p.revision, p.date].filter { !$0.isEmpty }
        }
        _ = text(context, subtitle.joined(separator: " · "), rect: CGRect(x: 30, y: 49, width: size.width - 60, height: 26), height: size.height, fontSize: 8)
    }

    private static func footer(_ context: CGContext, size: CGSize, page: Int) {
        _ = text(context, L("Page %@", String(page)), rect: CGRect(x: size.width - 90, y: size.height - 21, width: 60, height: 12), height: size.height, fontSize: 8)
    }

    private static func flip(_ rect: CGRect, _ height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    @discardableResult private static func text(_ context: CGContext, _ value: String, rect: CGRect, height: CGFloat, fontSize: CGFloat, bold: Bool = false) -> Int {
        guard !value.isEmpty else { return 0 }
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)]
        let string = NSAttributedString(string: value, attributes: attributes)
        let setter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: flip(rect, height), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        context.saveGState(); context.textMatrix = .identity; CTFrameDraw(frame, context); context.restoreGState()
        return CTFrameGetVisibleStringRange(frame).length
    }

    static func csv(document: StoryboardDocument, scenes: Set<UUID>, includeUnrendered: Bool = true) throws -> Data {
        let rows = try shots(document: document, scenes: scenes, includeUnrendered: includeUnrendered)
        var values = [["Scene", "Scene title", "Shot", "Shot title", "Shot size", "Description", "Lens", "Duration", "Camera movement", "Dialogue", "Notes", "Image"]]
        values += rows.map { shot in
            [String(shot.sceneNumber), shot.scene.title, shot.number, shot.frame.title, L(shot.frame.shot.rawValue), shot.description,
             shot.frame.details.lens, shot.frame.details.duration, shot.frame.details.movement, shot.frame.details.dialogue, shot.frame.details.notes, shot.frame.image == nil ? "" : imageName(shot)]
        }
        let result = values.map { row in row.map { value in
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { value.hasPrefix($0) }) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",") }.joined(separator: "\r\n")
        return Data(result.utf8)
    }

    static func bundle(document: StoryboardDocument, scenes: Set<UUID>, to folder: URL, includeUnrendered: Bool = true) throws {
        let rows = try shots(document: document, scenes: scenes, includeUnrendered: includeUnrendered)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.path) else { throw ExportError.destinationExists }
        let staging = folder.deletingLastPathComponent().appendingPathComponent(".scenesketch-export-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        for row in rows { try Task.checkCancellation(); if let data = row.frame.image { try data.write(to: staging.appendingPathComponent(imageName(row)), options: .atomic) } }
        try csv(document: document, scenes: scenes, includeUnrendered: includeUnrendered).write(to: staging.appendingPathComponent("shots.csv"))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = ExportData(title: document.title, production: document.production, scenes: document.scenes.filter { scenes.contains($0.id) },
                              shots: rows.map { ExportData.Shot(id: $0.frame.id, sceneID: $0.scene.id, number: $0.number, title: $0.frame.title, size: $0.frame.shot.rawValue, description: $0.description, details: $0.frame.details, image: $0.frame.image == nil ? nil : imageName($0)) })
        try encoder.encode(json).write(to: staging.appendingPathComponent("storyboard.json"))
        try fm.moveItem(at: staging, to: folder)
    }

    static func safeName(_ title: String) -> String {
        let words = title.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return String((words.isEmpty ? "Storyboard" : words.joined(separator: "-")).prefix(80))
    }
    private static func imageName(_ shot: ExportShot) -> String { String(format: "scene-%03d-", shot.sceneNumber) + shot.frame.id.uuidString.lowercased() + ".png" }
}

private struct ExportData: Codable {
    var title: String
    var production: ProductionDetails
    var scenes: [StoryScene]
    var shots: [Shot]
    struct Shot: Codable {
        var id: UUID
        var sceneID: UUID
        var number: String
        var title: String
        var size: String
        var description: String
        var details: ShotDetails
        var image: String?
    }
}

enum ExportError: LocalizedError {
    case noShots, encoding, destinationExists
    var errorDescription: String? {
        switch self {
        case .noShots: L("Choose at least one scene with shots to export.")
        case .encoding: L("The export couldn’t be created.  Try a different layout or destination.")
        case .destinationExists: L("That export folder already exists.  Choose a different name.")
        }
    }
}
