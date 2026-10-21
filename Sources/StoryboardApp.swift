import SwiftUI
import AppKit

@main
struct StoryboardApp: App {
    @NSApplicationDelegateAdaptor(LaunchDelegate.self) private var launchDelegate

    var body: some Scene {
        DocumentGroup(newDocument: StoryboardDocument()) { configuration in
            BoardEditor(document: configuration.$document)
        }
        .defaultSize(width: 1240, height: 800)
        .commands { ExportCommands() }
        Settings { SceneSketchSettings() }
    }
}

@MainActor
final class LaunchDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard NSDocumentController.shared.documents.isEmpty else { return }
            do {
                _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            } catch {
                NSLog("Unable to open the initial storyboard: %@", error.localizedDescription)
            }
        }
    }
}
