import AppKit
import SwiftUI

@MainActor
enum LibraryLayoutChecks {
    static func run() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        for count in [0, 2, 80] {
            var document = StoryboardDocument()
            document.entities = (0..<count).map { StoryEntity(kind: .character, name: "Character \($0 + 1)") }
            let host = NSHostingView(rootView: LibraryEditor(document: .constant(document)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let splits = descendants(host).compactMap { $0 as? NSSplitView }
            guard let split = splits.first else { throw Failure("No library split view") }
            let rect = host.convert(split.bounds, from: split)
            print("Library with \(count) entries: split \(rect), host \(host.bounds)")
            guard rect.height >= 500, rect.width >= 800 else {
                throw Failure("Library content collapsed on its first layout")
            }
            for child in split.arrangedSubviews {
                guard child.frame.height >= 500 else { throw Failure("Library column collapsed on its first layout") }
            }
            window.contentView = nil
        }
        print("PASS: initial Story Library layout with empty, short, and long lists, without activating a window")
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
