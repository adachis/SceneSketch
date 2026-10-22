import Foundation

struct EntityToken: Sendable {
    let range: NSRange
    let id: UUID
}

enum EntityTokens {
    static func token(_ id: UUID) -> String { "[[entity:\(id.uuidString)]]" }
    static func matches(_ text: String) -> [EntityToken] {
        let regex = try! NSRegularExpression(pattern: #"\[\[entity:([A-Fa-f0-9-]{36})\]\]"#)
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap {
            guard let id = UUID(uuidString: source.substring(with: $0.range(at: 1))) else { return nil }
            return EntityToken(range: $0.range, id: id)
        }
    }
    static func resolve(_ text: String, entities: [StoryEntity]) throws -> String {
        let result = NSMutableString(string: text)
        for item in matches(text).reversed() {
            guard let entity = entities.first(where: { $0.id == item.id }) else { throw StoryContextError.missingEntity }
            result.replaceCharacters(in: item.range, with: entity.name)
        }
        return result as String
    }
    static func mentioned(_ text: String, entities: [StoryEntity]) -> [StoryEntity] {
        var seen = Set<UUID>()
        return matches(text).compactMap { token in
            guard seen.insert(token.id).inserted else { return nil }
            return entities.first { $0.id == token.id }
        }
    }
}

enum StoryContextError: LocalizedError {
    case missingEntity, tooManyReferences, descriptionTooLong
    var errorDescription: String? {
        switch self {
        case .missingEntity: L("A linked library entry is missing.  Remove or replace its pill.")
        case .tooManyReferences: L("Choose up to three reference images for this frame.")
        case .descriptionTooLong: L("Shorten the frame or appearance descriptions before generating.")
        }
    }
}

struct RenderReference: Identifiable, Sendable {
    var id: UUID { image.id }
    let image: ReferenceImage
    let label: String
    let kind: EntityKind?
}

struct StoryContext: Sendable {
    static let referenceLimit = 3
    static let referenceEdge = 256
    let frame: StoryboardFrame
    let entities: [StoryEntity]
    let references: [RenderReference]
    let availableReferences: [RenderReference]
    let description: String
    let sceneContext: String
    let missingSelectionCount: Int

    init(frame: StoryboardFrame, document: StoryboardDocument) throws {
        self.frame = frame
        description = try EntityTokens.resolve(frame.description, entities: document.entities)
        let scene = document.scenes.first(where: { $0.id == frame.sceneID })
        sceneContext = [scene?.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
        var linked = EntityTokens.mentioned(frame.description, entities: document.entities)
        if let scene = document.scenes.first(where: { $0.id == frame.sceneID }),
           let location = document.entities.first(where: { $0.id == scene.locationID }), !linked.contains(where: { $0.id == location.id }) { linked.append(location) }
        entities = linked
        var available: [RenderReference] = []; var seen = Set<UUID>()
        func append(_ id: UUID, label: String, kind: EntityKind?) {
            guard seen.insert(id).inserted, let image = document.references.first(where: { $0.id == id }) else { return }
            available.append(RenderReference(image: image, label: label, kind: kind))
        }
        for id in frame.referenceIDs { append(id, label: "Shot reference", kind: nil) }
        // Use one primary image per linked entity before considering alternate images.
        for entity in linked { if let id = entity.referenceIDs.first { append(id, label: entity.name, kind: entity.kind) } }
        for entity in linked { for id in entity.referenceIDs.dropFirst() { append(id, label: entity.name, kind: entity.kind) } }
        availableReferences = available
        let chosen = frame.selectedReferenceIDs ?? Array(available.prefix(Self.referenceLimit).map(\.id))
        guard chosen.count <= Self.referenceLimit else { throw StoryContextError.tooManyReferences }
        let chosenSet = Set(chosen)
        references = available.filter { chosenSet.contains($0.id) }
        missingSelectionCount = available.count - references.count
    }
    func prompt(sceneDescription: String, englishDescriptions: [UUID: String] = [:], englishScene: String? = nil) throws -> String {
        let identities = entities.filter { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { "\($0.kind.promptLabel) \($0.name): \(englishDescriptions[$0.id] ?? $0.description)" }.joined(separator: "\n")
        let guide = references.enumerated().map { index, ref in
            "Reference image \(index + 1): \(ref.label)." + (ref.kind == .character ? " Use this person's facial identity only. Follow the new shot for pose, gaze, action, and clothing." : ref.kind == .location ? " Preserve this location's architecture and layout." : ref.kind == .prop ? " Preserve this object's shape, materials, colors, and distinctive physical features." : " Use as visual context; follow the new shot for action and pose.")
        }.joined(separator: "\n")
        let setting = (englishScene ?? sceneContext).isEmpty ? "" : "Setting, only where compatible with the shot: \(englishScene ?? sceneContext)."
        let result = "SBFRM7. \(frame.shot.rawValue). \(sceneDescription)\n" +
            "The shot above determines the visible action, gaze, positions, and objects. One continuous frame; each named character appears once. " +
            "Loose colored-pencil outlines, visible hatching, soft painted shading, full-color cinematic storyboard.\n" +
            "\(setting)\n\(identities)\n\(guide)\n" +
            "Reference images supply appearance only; do not copy their pose or composition unless the shot requests it. Clean wordless composition with blank panels and plain unmarked surfaces."

        guard result.count <= 5000 else { throw StoryContextError.descriptionTooLong }
        return result
    }
}
