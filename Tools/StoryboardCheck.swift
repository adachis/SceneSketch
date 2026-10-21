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
        if mode == "document" {
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
