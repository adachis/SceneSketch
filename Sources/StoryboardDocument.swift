import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let storyboard = UTType(exportedAs: "com.adachis.storyboard.document", conformingTo: .json)
}

enum CameraShot: String, Codable, CaseIterable, Identifiable, Sendable {
    case extremeWide = "Extreme wide shot", wide = "Wide shot", medium = "Medium shot", mediumClose = "Medium close-up", close = "Close-up", extremeClose = "Extreme close-up", shoulder = "Over the shoulder"
    var id: String { rawValue }
}

struct ProductionDetails: Codable, Equatable, Sendable {
    var production = ""
    var director = ""
    var artist = ""
    var revision = ""
    var date = ""
}

struct ShotDetails: Codable, Equatable, Sendable {
    var number = ""
    var lens = ""
    var duration = ""
    var movement = ""
    var dialogue = ""
    var notes = ""
}

enum EntityKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case character, location, prop
    var id: String { rawValue }
    var label: String { switch self { case .character: "Characters"; case .location: "Locations"; case .prop: "Props" } }
    var symbol: String { switch self { case .character: "person.crop.circle"; case .location: "mappin.and.ellipse"; case .prop: "cube" } }
    var newName: String { switch self { case .character: L("New character"); case .location: L("New location"); case .prop: L("New prop") } }
    var promptLabel: String { switch self { case .character: "Character"; case .location: "Location"; case .prop: "Prop" } }
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
    var title = L("Scene 1")
    var synopsis = ""
    var locationID: UUID?
    var sourceText = ""
}

struct RenderVersion: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var image: Data
    var prompt: String
    var seed: UInt64
    var description: String
    var shot: CameraShot
    var referenceIDs: [UUID]
}

enum ShotFilter: String, CaseIterable, Identifiable {
    case all = "All shots", missing = "Missing images", unapproved = "Unapproved", approved = "Approved"
    var id: String { rawValue }
    func includes(_ frame: StoryboardFrame) -> Bool {
        switch self { case .all: true; case .missing: frame.image == nil; case .unapproved: !frame.approved; case .approved: frame.approved }
    }
}

struct StoryboardFrame: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title = L("Untitled frame")
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
    var details = ShotDetails()
    var approved = false
    var history: [RenderVersion] = []
    var renderedAt = Date()
    var renderedDescription: String?
    var renderedShot: CameraShot?
    var renderedReferenceIDs: [UUID] = []

    var currentVersion: RenderVersion? {
        image.map { RenderVersion(id: imageRevision, createdAt: renderedAt, image: $0, prompt: renderedPrompt ?? "", seed: seed,
            description: renderedDescription ?? description, shot: renderedShot ?? shot, referenceIDs: renderedReferenceIDs) }
    }
    var versions: [RenderVersion] { (history + (currentVersion.map { [$0] } ?? [])).sorted { $0.createdAt > $1.createdAt } }
    mutating func storeRender(image: Data, prompt: String, seed: UInt64, source: StoryboardFrame, referenceIDs: [UUID]) {
        if let currentVersion { history.append(currentVersion) }
        self.image = image; renderedPrompt = prompt; self.seed = seed; imageRevision = UUID(); renderedAt = Date()
        renderedDescription = source.description; renderedShot = source.shot; renderedReferenceIDs = referenceIDs; approved = false
    }
    mutating func selectVersion(_ id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        let selected = history.remove(at: index)
        if let currentVersion { history.append(currentVersion) }
        image = selected.image; renderedPrompt = selected.prompt; seed = selected.seed; imageRevision = selected.id
        renderedAt = selected.createdAt; renderedDescription = selected.description; renderedShot = selected.shot
        renderedReferenceIDs = selected.referenceIDs; approved = false
    }
    func duplicated() -> Self {
        var copy = self; copy.id = UUID(); copy.title = L("%@ copy", title); copy.seed = UInt64.random(in: 1...UInt64(UInt32.max))
        copy.image = nil; copy.history = []; copy.renderedPrompt = nil; copy.renderedDescription = nil
        copy.renderedShot = nil; copy.renderedReferenceIDs = []; copy.imageRevision = UUID(); copy.approved = false
        return copy
    }

    enum CodingKeys: String, CodingKey { case id, title, description, shot, seed, image, renderedPrompt, imageRevision, sceneID, referenceIDs, selectedReferenceIDs, sourceText, details, approved, history, renderedAt, renderedDescription, renderedShot, renderedReferenceIDs }
    init(title: String = L("Untitled frame"), description: String = "", shot: CameraShot = .wide, image: Data? = nil, sceneID: UUID? = nil) {
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
        details = try c.decodeIfPresent(ShotDetails.self, forKey: .details) ?? ShotDetails()
        approved = try c.decodeIfPresent(Bool.self, forKey: .approved) ?? false
        history = try c.decodeIfPresent([RenderVersion].self, forKey: .history) ?? []
        renderedAt = try c.decodeIfPresent(Date.self, forKey: .renderedAt) ?? Date(timeIntervalSince1970: 0)
        renderedDescription = try c.decodeIfPresent(String.self, forKey: .renderedDescription)
        renderedShot = try c.decodeIfPresent(CameraShot.self, forKey: .renderedShot)
        renderedReferenceIDs = try c.decodeIfPresent([UUID].self, forKey: .renderedReferenceIDs) ?? []
        guard Set(history.map(\.id)).count == history.count, !history.contains(where: { $0.id == imageRevision }) else { throw CocoaError(.fileReadCorruptFile) }
    }
}

struct StoryboardDocument: FileDocument, Equatable, Sendable {
    static var readableContentTypes: [UTType] { [.storyboard] }
    var version = 4
    var title = L("Untitled story")
    var production = ProductionDetails()
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
        guard (1...4).contains(payload.version) else { throw CocoaError(.fileReadUnsupportedScheme) }
        title = payload.title ?? L("Untitled story")
        production = payload.production ?? ProductionDetails()
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
        try JSONEncoder().encode(Payload(version: 4, title: title, production: production, entities: entities, references: references, scenes: scenes, frames: frames))
    }
    private struct Payload: Codable {
        var version: Int
        var title: String?
        var production: ProductionDetails?
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
        let used = Set(entities.flatMap(\.referenceIDs) + frames.flatMap(\.referenceIDs) + frames.flatMap(\.renderedReferenceIDs) + frames.flatMap { $0.history.flatMap(\.referenceIDs) })
        references.removeAll { !used.contains($0.id) }
    }
}
