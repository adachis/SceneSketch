import SwiftUI

enum BoardAction: String, CaseIterable {
    case library = "Story Library", addShot = "Add shot", addScene = "Add scene", duplicate = "Duplicate shot"
    case merge = "Merge selected shots"
    case importScript = "Import screenplay", export = "Export Storyboard…", production = "Production details…", setup = "Model setup…"
    case render = "Generate frame", renderScene = "Generate this scene", renderMissing = "Generate missing images", stop = "Stop after frame"
    case previous = "Previous shot", next = "Next shot", approve = "Toggle approval", history = "Render history…", recover = "Recover storyboard…", delete = "Delete selected shot"
    var shortcut: KeyEquivalent {
        switch self {
        case .library: "l"
        case .addShot, .addScene: "n"
        case .duplicate: "d"
        case .importScript: "i"
        case .export: "e"
        case .production: "p"
        case .setup: "m"
        case .merge: "m"
        case .render, .renderScene, .renderMissing: .return
        case .stop: "."
        case .previous: "["
        case .next: "]"
        case .approve: "a"
        case .history: "h"
        case .recover: "r"
        case .delete: .delete
        }
    }
    var modifiers: EventModifiers {
        switch self {
        case .addScene, .renderMissing, .setup, .recover: [.command, .option]
        case .render, .duplicate, .previous, .next, .stop: [.command]
        default: [.command, .shift]
        }
    }
}
struct BoardCommandContext {
    let available: Set<BoardAction>
    let perform: (BoardAction) -> Void
}
private struct BoardCommandKey: FocusedValueKey { typealias Value = BoardCommandContext }
extension FocusedValues {
    var boardCommands: BoardCommandContext? {
        get { self[BoardCommandKey.self] }
        set { self[BoardCommandKey.self] = newValue }
    }
}
struct StoryboardCommands: Commands {
    @FocusedValue(\.boardCommands) private var context
    @AppStorage("interfaceLanguage") private var language = ""
    var body: some Commands {
        let _ = language
        CommandGroup(after: .saveItem) { command(.importScript); command(.export); command(.recover) }
        CommandMenu(L("Storyboard")) {
            command(.library); command(.production); command(.setup)
            Divider()
            command(.addShot); command(.addScene); command(.duplicate); command(.merge); command(.delete)
            Divider()
            command(.previous); command(.next); command(.approve); command(.history)
            Divider()
            command(.render); command(.renderScene); command(.renderMissing); command(.stop)
        }
    }
    private func command(_ action: BoardAction) -> some View {
        Button(L(action.rawValue)) { context?.perform(action) }
            .keyboardShortcut(action.shortcut, modifiers: action.modifiers)
            .disabled(context?.available.contains(action) != true)
    }
}
