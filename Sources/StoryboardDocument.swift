import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let storyboard = UTType(exportedAs: "com.adachis.storyboard.document", conformingTo: .json)
}

enum CameraShot: String, Codable, CaseIterable, Identifiable {
    case wide = "Wide shot"
    case medium = "Medium shot"
    case close = "Close-up"
    case shoulder = "Over the shoulder"
    var id: String { rawValue }
}

struct StoryboardFrame: Identifiable, Codable {
    var id = UUID()
    var title = "Untitled frame"
    var description = ""
    var shot = CameraShot.wide
    var seed = UInt64.random(in: 1...UInt64(UInt32.max))
    var image: Data?
    var renderedPrompt: String?
    var imageRevision = UUID()
}

struct StoryboardDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.storyboard] }
    var version = 1
    var frames = [StoryboardFrame()]

    init() {}
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.version == 1 else { throw CocoaError(.fileReadUnsupportedScheme) }
        version = payload.version
        frames = payload.frames
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(Payload(version: version, frames: frames))
        return FileWrapper(regularFileWithContents: data)
    }
    private struct Payload: Codable {
        var version: Int
        var frames: [StoryboardFrame]
    }
}
