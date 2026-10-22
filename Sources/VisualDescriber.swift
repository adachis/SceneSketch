import Foundation
import CoreImage
import MLXVLM
import MLXLMCommon
import FluxTextEncoders

struct StableAppearance {
    // Only these physical fields can leave the visual-description boundary.
    static let choices: [(String, [String])] = [
        ("age", ["child", "teenager", "young adult", "adult", "older adult"]),
        ("face", ["oval face", "round face", "square face", "long face", "heart-shaped face"]),
        ("skin", ["very light skin", "light skin", "medium skin", "brown skin", "dark skin"]),
        ("hair_color", ["black hair", "brown hair", "blond hair", "red hair", "gray hair", "white hair", "bald"]),
        ("hair_texture", ["straight hair", "wavy hair", "curly hair", "coily hair"]),
        ("hair_length", ["short hair", "medium-length hair", "long hair"]),
        ("facial_hair", ["clean-shaven", "mustache", "short beard", "full beard"])
    ]
    static func supportedDescription(from response: String, evidence: String) -> String {
        let known = Set(evidence.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
        return description(from: response).components(separatedBy: ", ").filter { phrase in
            phrase.split(separator: " ").allSatisfy { known.contains(String($0)) }
        }.joined(separator: ", ")
    }
    static func description(from response: String) -> String {
        guard let start = response.firstIndex(of: "{"), let end = response.lastIndex(of: "}"), start <= end,
              let data = String(response[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return "" }
        return choices.compactMap { key, allowed in
            guard let value = object[key]?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), allowed.contains(value) else { return nil }
            return value
        }.joined(separator: ", ")
    }
}

struct VisualDescriber {
    static func describe(image: ReferenceImage, kind: EntityKind, modelRoot: URL) async throws -> String {
        let identifier = "mlx-community/Qwen3.5-2B-4bit"
        TextEncoderModelDownloader.customModelsDirectory = modelRoot
        TextEncoderModelDownloader.reconfigureHubApi()
        let directory = modelRoot.appendingPathComponent(identifier)
        if !FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path) {
            throw ModelError.notInstalled(.vision)
        }
        let template = directory.appendingPathComponent("chat_template.jinja")
        if !FileManager.default.fileExists(atPath: template.path) {
            throw ModelError.notInstalled(.vision)
        }
        let model = try await VLMModelFactory.shared.loadContainer(from: directory, using: LocalTokenizerLoader())
        let session = ChatSession(model, generateParameters: .init(maxTokens: 280, temperature: 0), additionalContext: ["enable_thinking": false])
        var cgImage = try ReferenceImages.cgImage(image.data, maximumEdge: 512)
        if kind == .character { cgImage = ReferenceImages.faceCrop(cgImage) }
        let prompt: String
        if kind == .character {
            let schema = StableAppearance.choices.map { "\($0.0): \($0.1.joined(separator: " | ")) | unknown" }.joined(separator: "\n")
            prompt = "Describe only the visible person's permanent physical appearance. Ignore all clothes, glasses, jewelry, accessories, pose, expression, and background. Return a JSON object with exactly these keys, selecting one exact value for each; use unknown when uncertain.\n" + schema
        } else if kind == .location {
            prompt = "Describe only permanent physical features of this location. Ignore people, animals, vehicles, portable objects, weather, time of day, and lighting. Return a JSON object with exactly these keys: architecture, materials, layout, terrain, landmarks. Each value must be one short factual phrase, or unknown. Do not invent details or name the location."
        } else {
            prompt = "Describe the main physical object or prop in this image for consistent storyboard appearances. Focus on the object itself, ignoring people, hands, background, lighting, camera angle, and other objects. Return a JSON object with exactly these keys: object, shape, colors, materials, distinctive_features. Every value must be a string containing one short factual phrase, or unknown; never use arrays. Use unknown when a material cannot be established from visible evidence. Do not invent unseen details, infer a brand, transcribe text, or describe an action."
        }
        let response = try await session.respond(to: prompt, image: .ciImage(CIImage(cgImage: cgImage)))
        if ProcessInfo.processInfo.environment["STORYBOARD_DIAGNOSTICS"] == "1" { print("Vision response: " + response) }
        let result: String
        switch kind {
        case .character: result = StableAppearance.description(from: response)
        case .location: result = LocationAppearance.description(from: response)
        case .prop: result = PropAppearance.description(from: response)
        }
        guard !result.isEmpty, result.count < 2000 else { throw DescriptionError.uncertain }
        return result
    }
}

struct PropAppearance {
    static func description(from response: String) -> String {
        guard let start = response.firstIndex(of: "{"), let end = response.lastIndex(of: "}"), start <= end,
              let data = String(response[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return ["object", "shape", "colors", "materials", "distinctive_features"].compactMap { key in
            let raw = (object[key] as? String) ?? (object[key] as? [String])?.reduce(into: [String]()) { values, item in
                if !values.contains(item) { values.append(item) }
            }.joined(separator: ", ")
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty, value.lowercased() != "unknown", value.count < 300 else { return nil }
            return value
        }.joined(separator: "; ")
    }
}

enum DescriptionError: LocalizedError {
    case uncertain
    var errorDescription: String? { L("The image didn’t yield a reliable description.  It is still saved as a visual reference; you can describe it manually.") }
}

struct LocationAppearance {
    static func description(from response: String) -> String {
        guard let start = response.firstIndex(of: "{"), let end = response.lastIndex(of: "}"), start <= end,
              let data = String(response[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return "" }
        return ["architecture", "materials", "layout", "terrain", "landmarks"].compactMap { key in
            guard let value = object[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  value.lowercased() != "unknown", !value.isEmpty, value.count < 400,
                  value.range(of: #"\b(people|person|woman|women|man|men|child|children|wearing|suitcase|vehicle|car)\b"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
            return key.capitalized + ": " + value
        }.joined(separator: ". ")
    }
}
