import Foundation
import ImageIO
import UniformTypeIdentifiers
import Flux2Core
import FluxTextEncoders
import MLX
import Tokenizers

struct RenderedFrame: Sendable {
    let image: Data
    let prompt: String
    let seed: UInt64
}

actor RenderService {
    static let shared = RenderService()
    private var busy = false

    func render(frame: StoryboardFrame, document: StoryboardDocument? = nil, adapterURL: URL? = nil, progress: @escaping @Sendable (String) -> Void) async throws -> RenderedFrame {
        guard !busy else { throw RenderError.busy }
        busy = true
        defer { busy = false; MLX.Memory.clearCache(); Task { @MainActor in RuntimeActivity.shared.isRendering = false } }
        let installing = await MainActor.run { ModelManager.shared.isWorking }
        guard !installing else { throw RenderError.busy }
        await MainActor.run { RuntimeActivity.shared.isRendering = true }
        return try await Task.detached(priority: .userInitiated) {
            let context = try StoryContext(frame: frame, document: document ?? StoryboardDocument())
            try ModelPaths.require(.drawing)
            let root = try Self.modelDirectory()
            ModelRegistry.customModelsDirectory = root
            TextEncoderModelDownloader.customModelsDirectory = root
            TextEncoderModelDownloader.reconfigureHubApi()
            try ModelRegistry.setPathOverride(root.appendingPathComponent("flux/transformer"), for: .transformer(.klein4B_bf16))
            try ModelRegistry.setPathOverride(root.appendingPathComponent("vae"), for: .vae(.smallDecoder))
            progress(L("Preparing the frame description…"))
            var cleaned = context.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let needsTranslation = PromptNormalizer.needsEnglish(cleaned)
            do {
                let cleanUp = context.entities.isEmpty && UserDefaults.standard.object(forKey: "promptCleanupEnabled") as? Bool != false
                if needsTranslation || cleanUp {
                    cleaned = try await PromptNormalizer.rewrite(cleaned, shot: frame.shot.rawValue, modelRoot: root, cleanUp: cleanUp)
                }
            } catch {
                if needsTranslation { throw error }
                progress(L("Using your original description…"))
            }
            var englishDescriptions: [UUID: String] = [:]
            for entity in context.entities { englishDescriptions[entity.id] = RenderTextPolicy.prepare(try await PromptNormalizer.translateIfNeeded(entity.description, modelRoot: root)) }
            let englishScene = RenderTextPolicy.prepare(try await PromptNormalizer.translateIfNeeded(context.sceneContext, modelRoot: root))
            MLX.Memory.clearCache()
            let prompt = try context.prompt(sceneDescription: RenderTextPolicy.prepare(cleaned), englishDescriptions: englishDescriptions, englishScene: englishScene)
            progress(L("Preparing the image model…"))
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
                progress(L("Loading image model: %@%%", String(Int(fraction * 100))))
            }
            let tokenizerDirectory = localText ?? TextEncoderModelDownloader.findQwen3ModelPath(for: .qwen3_4B_4bit)
            if let tokenizerDirectory {
                let tokenizer = try await AutoTokenizer.from(modelFolder: tokenizerDirectory)
                let formatted = "<|im_start|>user\n" + prompt.replacingOccurrences(of: "[IMG]", with: "") + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
                guard tokenizer.encode(text: formatted, addSpecialTokens: false).count <= 512 else { throw StoryContextError.descriptionTooLong }
            }
            guard let adapter = adapterURL ?? Bundle.main.url(forResource: "StoryboardStyle", withExtension: "safetensors") else {
                throw RenderError.missingAdapter
            }
            _ = try pipeline.loadLoRA(.init(filePath: adapter.path, scale: 3.5))
            try Task.checkCancellation()
            progress(L("Drawing the frame…"))
            let references = try context.references.map { reference in
                let source = try ReferenceImages.cgImage(reference.image.data, maximumEdge: 1024)
                return reference.kind == .character ? ReferenceImages.faceCrop(source) : source
            }
            func draw(seed: UInt64) async throws -> CGImage {
                if references.isEmpty {
                    return try await pipeline.generateTextToImage(
                    prompt: prompt, height: 576, width: 1024, steps: 4, guidance: 1,
                    seed: seed, upsamplePrompt: false
                ) { step, total in progress(L("Drawing %@ of %@…", String(step), String(total))) }
                } else {
                    return try await pipeline.generateImageToImage(
                        prompt: prompt, images: references, height: 576, width: 1024,
                        steps: 4, guidance: 1, seed: seed, upsamplePrompt: false,
                        maxReferencePixels: StoryContext.referenceEdge * StoryContext.referenceEdge
                    ) { step, total in progress(L("Drawing %@ of %@…", String(step), String(total))) }
                }
            }
            var seed = frame.seed
            var image = try await draw(seed: seed)
            let lettering = RenderTextPolicy.letteringScore(image)
            if lettering > 0 {
                try Task.checkCancellation()
                progress(L("Drawing the frame…"))
                let candidateSeed = seed &+ 1
                do {
                    let candidate = try await draw(seed: candidateSeed)
                    if RenderTextPolicy.letteringScore(candidate) < lettering { image = candidate; seed = candidateSeed }
                } catch is CancellationError { throw CancellationError() }
                catch { /* Keep the completed frame if the optional retry fails. */ }
            }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                throw RenderError.encoding
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw RenderError.encoding }
            return RenderedFrame(image: data as Data, prompt: prompt, seed: seed)
        }.value
    }

    func describe(image: ReferenceImage, kind: EntityKind) async throws -> String {
        guard !busy else { throw RenderError.busy }
        busy = true
        defer { busy = false; MLX.Memory.clearCache(); Task { @MainActor in RuntimeActivity.shared.isRendering = false } }
        let installing = await MainActor.run { ModelManager.shared.isWorking }
        guard !installing else { throw RenderError.busy }
        await MainActor.run { RuntimeActivity.shared.isRendering = true }
        return try await Task.detached(priority: .userInitiated) {
            try ModelPaths.require(.vision)
            return try await VisualDescriber.describe(image: image, kind: kind, modelRoot: Self.modelDirectory())
        }.value
    }

    nonisolated static func modelDirectory() throws -> URL {
        let directory = try ModelPaths.root()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static func userMessage(for error: Error) -> String {
        if let error = error as? StoryContextError { return error.localizedDescription }
        if let error = error as? ModelError { return error.localizedDescription }
        switch error {
        case RenderError.busy: return L("Another frame is still generating.  Try again when it finishes.")
        case RenderError.missingAdapter: return L("The sketch model is missing from this copy of SceneSketch.  Reinstall the app.")
        case is URLError: return L("The model download couldn’t finish.  Check your connection and try again.")
        default: return L("The frame couldn’t be generated.  Your description is saved.  Try again, or restart the app.")
        }
    }
}

private enum RenderError: Error {
    case busy, missingAdapter, encoding
}
