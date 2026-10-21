import Foundation
import ImageIO
import UniformTypeIdentifiers
import Flux2Core
import FluxTextEncoders
import MLX

struct RenderedFrame: Sendable {
    let image: Data
    let prompt: String
}

actor RenderService {
    static let shared = RenderService()
    private var busy = false

    func render(frame: StoryboardFrame, adapterURL: URL? = nil, progress: @escaping @Sendable (String) -> Void) async throws -> RenderedFrame {
        guard !busy else { throw RenderError.busy }
        busy = true
        defer { busy = false; MLX.Memory.clearCache() }
        return try await Task.detached(priority: .userInitiated) {
            let root = try Self.modelDirectory()
            ModelRegistry.customModelsDirectory = root
            TextEncoderModelDownloader.customModelsDirectory = root
            TextEncoderModelDownloader.reconfigureHubApi()
            try ModelRegistry.setPathOverride(root.appendingPathComponent("flux/transformer"), for: .transformer(.klein4B_bf16))
            try ModelRegistry.setPathOverride(root.appendingPathComponent("vae"), for: .vae(.smallDecoder))
            progress("Preparing the frame description…")
            var cleaned = frame.description.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                cleaned = try await PromptNormalizer.rewrite(cleaned, shot: frame.shot.rawValue, modelRoot: root)
            } catch {
                progress("Using your original description…")
            }
            MLX.Memory.clearCache()
            let prompt = "SBFRM7. A single full-color cinematic storyboard frame with loose colored-pencil outlines, visible hatching, and soft painted shading. The composition fills the entire rectangular frame edge to edge. \(frame.shot.rawValue). \(cleaned)"
            progress("Preparing the image model…")
            let textDirectory = root.appendingPathComponent("text")
            let localText = FileManager.default.fileExists(atPath: textDirectory.appendingPathComponent("config.json").path) ? textDirectory : nil
            let pipeline = Flux2Pipeline(
                model: .klein4B,
                quantization: .init(textEncoder: .mlx4bit, transformer: .int4),
                memoryOptimization: .ultraLowMemory,
                vaeVariant: .smallDecoder,
                kleinEncoderPath: localText
            )
            pipeline.memoryProfile = .conservative
            pipeline.keepTextEncoderLoaded = false
            pipeline.clearCacheEveryNSteps = 1
            try await pipeline.loadModels { fraction, _ in
                progress("Downloading image model: \(Int(fraction * 100))%")
            }
            guard let adapter = adapterURL ?? Bundle.main.url(forResource: "StoryboardStyle", withExtension: "safetensors") else {
                throw RenderError.missingAdapter
            }
            _ = try pipeline.loadLoRA(.init(filePath: adapter.path, scale: 3.5))
            try Task.checkCancellation()
            progress("Drawing the frame…")
            let image = try await pipeline.generateTextToImage(
                prompt: prompt, height: 576, width: 1024, steps: 4, guidance: 1,
                seed: frame.seed, upsamplePrompt: false
            ) { step, total in progress("Drawing \(step) of \(total)…") }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                throw RenderError.encoding
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw RenderError.encoding }
            return RenderedFrame(image: data as Data, prompt: prompt)
        }.value
    }

    nonisolated static func modelDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["STORYBOARD_MODELS_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Storyboard/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static func userMessage(for error: Error) -> String {
        switch error {
        case RenderError.busy: return "Another frame is still generating.  Try again when it finishes."
        case RenderError.missingAdapter: return "The sketch model is missing from this copy of Storyboard.  Reinstall the app."
        case is URLError: return "The model download couldn’t finish.  Check your connection and try again."
        default: return "The frame couldn’t be generated.  Your description is saved.  Try again, or restart the app."
        }
    }
}

private enum RenderError: Error {
    case busy, missingAdapter, encoding
}
