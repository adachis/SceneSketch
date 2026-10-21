import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let storyboard = UTType(exportedAs: "com.adachis.storyboard.document", conformingTo: .json)
}

enum CameraShot: String, Codable, CaseIterable, Identifiable, Sendable {
    case wide = "Wide shot", medium = "Medium shot", close = "Close-up", shoulder = "Over the shoulder"
    var id: String { rawValue }
}

enum EntityKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case character, location
    var id: String { rawValue }
    var label: String { self == .character ? "Characters" : "Locations" }
    var symbol: String { self == .character ? "person.crop.circle" : "mappin.and.ellipse" }
}

struct StoryEntity: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var kind: EntityKind
    var name: String
    var description = ""
    var referenceIDs: [UUID] = []
}

struct ReferenceImage: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var data: Data
}

struct StoryScene: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title = "Scene 1"
    var synopsis = ""
    var locationID: UUID?
    var sourceText = ""
}

struct StoryboardFrame: Identifiable, Codable, Sendable {
    var id = UUID()
    var title = "Untitled frame"
    var description = ""
    var shot = CameraShot.wide
    var seed = UInt64.random(in: 1...UInt64(UInt32.max))
    var image: Data?
    var renderedPrompt: String?
    var imageRevision = UUID()
    var sceneID: UUID?
    var referenceIDs: [UUID] = []
    var selectedReferenceIDs: [UUID]?
    var sourceText = ""

    enum CodingKeys: String, CodingKey { case id, title, description, shot, seed, image, renderedPrompt, imageRevision, sceneID, referenceIDs, selectedReferenceIDs, sourceText }
    init(title: String = "Untitled frame", description: String = "", shot: CameraShot = .wide, image: Data? = nil, sceneID: UUID? = nil) {
        self.title = title; self.description = description; self.shot = shot; self.image = image; self.sceneID = sceneID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decode(String.self, forKey: .description)
        shot = try c.decode(CameraShot.self, forKey: .shot)
        seed = try c.decode(UInt64.self, forKey: .seed)
        image = try c.decodeIfPresent(Data.self, forKey: .image)
        renderedPrompt = try c.decodeIfPresent(String.self, forKey: .renderedPrompt)
        imageRevision = try c.decodeIfPresent(UUID.self, forKey: .imageRevision) ?? UUID()
        sceneID = try c.decodeIfPresent(UUID.self, forKey: .sceneID)
        referenceIDs = try c.decodeIfPresent([UUID].self, forKey: .referenceIDs) ?? []
        selectedReferenceIDs = try c.decodeIfPresent([UUID].self, forKey: .selectedReferenceIDs)
        sourceText = try c.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
    }
}

struct StoryboardDocument: FileDocument, Sendable {
    static var readableContentTypes: [UTType] { [.storyboard] }
    var version = 2
    var title = "Untitled story"
    var entities: [StoryEntity] = []
    var references: [ReferenceImage] = []
    var scenes = [StoryScene()]
    var frames = [StoryboardFrame()]

    init() { frames[0].sceneID = scenes[0].id }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        try self.init(data: data)
    }
    init(data: Data) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard (1...2).contains(payload.version) else { throw CocoaError(.fileReadUnsupportedScheme) }
        title = payload.title ?? "Untitled story"
        entities = payload.entities ?? []; references = payload.references ?? []
        scenes = payload.scenes ?? [StoryScene()]; frames = payload.frames
        if scenes.isEmpty { scenes = [StoryScene()] }
        let sceneIDs = Set(scenes.map(\.id))
        for i in frames.indices where frames[i].sceneID == nil || !sceneIDs.contains(frames[i].sceneID!) { frames[i].sceneID = scenes[0].id }
        guard Set(entities.map(\.id)).count == entities.count,
              Set(frames.map(\.id)).count == frames.count,
              Set(references.map(\.id)).count == references.count,
              sceneIDs.count == scenes.count else { throw CocoaError(.fileReadCorruptFile) }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: try encodedData()) }
    func encodedData() throws -> Data {
        try JSONEncoder().encode(Payload(version: 2, title: title, entities: entities, references: references, scenes: scenes, frames: frames))
    }
    private struct Payload: Codable {
        var version: Int
        var title: String?
        var entities: [StoryEntity]?
        var references: [ReferenceImage]?
        var scenes: [StoryScene]?
        var frames: [StoryboardFrame]
    }
    mutating func removeEntity(_ id: UUID) {
        guard let entity = entities.first(where: { $0.id == id }) else { return }
        for i in frames.indices { frames[i].description = frames[i].description.replacingOccurrences(of: EntityTokens.token(id), with: entity.name) }
        for i in scenes.indices where scenes[i].locationID == id { scenes[i].locationID = nil }
        entities.removeAll { $0.id == id }; removeUnusedReferences()
    }
    mutating func mergeEntity(_ sourceID: UUID, into targetID: UUID) {
        guard sourceID != targetID, let source = entities.first(where: { $0.id == sourceID }),
              let targetIndex = entities.firstIndex(where: { $0.id == targetID }), entities[targetIndex].kind == source.kind else { return }
        for i in frames.indices { frames[i].description = frames[i].description.replacingOccurrences(of: EntityTokens.token(sourceID), with: EntityTokens.token(targetID)) }
        for i in scenes.indices where scenes[i].locationID == sourceID { scenes[i].locationID = targetID }
        for id in source.referenceIDs where !entities[targetIndex].referenceIDs.contains(id) { entities[targetIndex].referenceIDs.append(id) }
        if !source.description.isEmpty && !entities[targetIndex].description.contains(source.description) {
            entities[targetIndex].description += entities[targetIndex].description.isEmpty ? source.description : "\n" + source.description
        }
        entities.removeAll { $0.id == sourceID }
    }
    mutating func removeUnusedReferences() {
        let used = Set(entities.flatMap(\.referenceIDs) + frames.flatMap(\.referenceIDs))
        references.removeAll { !used.contains($0.id) }
    }
}
