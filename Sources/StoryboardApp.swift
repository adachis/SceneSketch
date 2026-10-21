import SwiftUI

@main
struct StoryboardApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: StoryboardDocument()) { configuration in
            BoardEditor(document: configuration.$document)
        }
        .defaultSize(width: 1240, height: 800)
    }
}
