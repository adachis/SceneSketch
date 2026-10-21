import AppKit
import Foundation
import SwiftUI
import FluxTextEncoders

@main
struct StoryboardCheck {
    @MainActor
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let mode = args.first else { return }
        let root = try RenderService.modelDirectory()
        TextEncoderModelDownloader.customModelsDirectory = root
        TextEncoderModelDownloader.reconfigureHubApi()
        if mode == "lettering-check" {
            for path in args.dropFirst() {
                let image = try ReferenceImages.cgImage(Data(contentsOf: URL(fileURLWithPath: path)), maximumEdge: 2048)
                print("\(URL(fileURLWithPath: path).lastPathComponent): \(RenderTextPolicy.letteringScore(image))")
            }
        } else if mode == "ui-language" {
            try await InterfaceChecks.render(language: args[1], output: URL(fileURLWithPath: args[2]))
        } else if mode == "models" {
            try await ModelChecks.run(catalogURL: URL(fileURLWithPath: args[1]), server: URL(string: args[2])!)
        } else if mode == "exports" {
            try ExportChecks.run(output: URL(fileURLWithPath: args[1]), image: URL(fileURLWithPath: args[2]))
        } else if mode == "library-layout" {
            try await LibraryLayoutChecks.run()
        } else if mode == "batch-check" {
            var document = StoryboardDocument()
            document.frames[0].description = "A traveler waits alone beside a river in a small town at sunrise. A wooden bridge crosses the water."
            for index in 0..<3 {
                document.frames[0].seed = UInt64(5700 + index)
                let result = try await RenderService.shared.render(frame: document.frames[0], document: document, adapterURL:URL(fileURLWithPath:args[1])) { _ in }
                document.frames[0].image = result.image
                print("Completed batch frame \(index+1)")
            }
        } else if mode == "ocr-test" {
            try StoryChecks.ocr()
        } else if mode == "parse" {
            let value = try ScreenplayImporter.read(URL(fileURLWithPath: args[1])) { _ in }
            let data = try JSONSerialization.data(withJSONObject: ["title":value.title,"scenes":value.scenes.map { scene in ["title":scene.title,"shots":value.frames.filter { $0.sceneID == scene.id }.count] },"characters":value.entities.filter { $0.kind == .character }.map { ["name":$0.name,"description":$0.description] },"locations":value.entities.filter { $0.kind == .location }.map(\.name),"shotCount":value.frames.count,"warnings":value.warnings], options: [.prettyPrinted,.sortedKeys])
            if args.count > 2 { try data.write(to: URL(fileURLWithPath: args[2])) } else { print(String(decoding:data,as:UTF8.self)) }
        } else if mode == "story" {
            try StoryChecks.run()
        } else if mode == "vision" {
            let reference = try ReferenceImages.importFile(URL(fileURLWithPath: args[1]))
            print(try await RenderService.shared.describe(image: reference, kind: args.count > 2 && args[2] == "location" ? .location : .character))
        } else if mode == "reference" || mode == "character-reference" {
            var document = StoryboardDocument()
            let count = min(3, Int(args[3]) ?? 1)
            for _ in 0..<count { let value = try ReferenceImages.importFile(URL(fileURLWithPath: args[1])); document.references.append(value); document.frames[0].referenceIDs.append(value.id) }
            if mode == "character-reference" {
                var character = StoryEntity(kind: .character, name: "Mara", description: "An adult woman with shoulder-length wavy brown hair and an oval face.")
                character.referenceIDs = document.frames[0].referenceIDs
                document.entities = [character]; document.frames[0].referenceIDs = []
                document.frames[0].description = args[4].replacingOccurrences(of: "{character}", with: EntityTokens.token(character.id))
            } else { document.frames[0].description = args[4] }
            document.frames[0].seed = 5700
            let result = try await RenderService.shared.render(frame: document.frames[0], document: document, adapterURL: URL(fileURLWithPath: args[2])) { print($0) }
            try result.image.write(to: URL(fileURLWithPath: args[5]))
            print(result.prompt)
        } else if mode == "document" {
            var original = StoryboardDocument()
            original.frames[0].description = "Two hikers on a bridge"
            original.frames[0].image = Data([1, 2, 3])
            let restored = try StoryboardDocument(data: original.encodedData())
            precondition(restored.frames[0].id == original.frames[0].id)
            precondition(restored.frames[0].image == original.frames[0].image)
            precondition(restored.frames[0].description == original.frames[0].description)
            do {
                _ = try StoryboardDocument(data: Data("{invalid".utf8))
                preconditionFailure("Corrupt documents must fail")
            } catch {}
            print("Document round trip and corrupt-file rejection passed")
        } else if mode == "normalize" {
            let description = args.dropFirst().joined(separator: " ")
            print(try await PromptNormalizer.rewrite(description, shot: "Wide shot", modelRoot: root))
        } else if mode == "render" {
            guard args.count >= 4 else { throw CocoaError(.validationMissingMandatoryProperty) }
            var frame = StoryboardFrame()
            frame.description = args[3]
            frame.seed = 5700
            let result = try await RenderService.shared.render(frame: frame, adapterURL: URL(fileURLWithPath: args[1])) { print($0) }
            try result.image.write(to: URL(fileURLWithPath: args[2]))
            print("Prompt: \(result.prompt)")
        } else if mode == "preview" {
            guard args.count >= 3 else { throw CocoaError(.validationMissingMandatoryProperty) }
            var document = StoryboardDocument()
            document.frames = [StoryboardFrame(title: "The platform", description: "A traveler waits at a rural train station.", image: try Data(contentsOf: URL(fileURLWithPath: args[1])))]
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            app.appearance = NSAppearance(named: .aqua)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: BoardEditor(document: .constant(document)))
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-l", String(window.windowNumber), args[2]]
                do {
                    try capture.run()
                    capture.waitUntilExit()
                    print("Preview capture status: \(capture.terminationStatus)")
                } catch { print(error.localizedDescription) }
                exit(0)
            }
            app.run()
        }
    }
}
