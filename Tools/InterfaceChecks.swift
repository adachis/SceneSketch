import AppKit
import SwiftUI

@MainActor
enum InterfaceChecks {
    static func render(language: String, output: URL) async throws {
        setenv("SCENESKETCH_INTERFACE_LANGUAGE", language, 1)
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        let view = NSHostingView(rootView: ModelSetupView()
            .environment(\.locale, Locale(identifier: language))
            .environment(\.layoutDirection, Localization.isRightToLeft ? .rightToLeft : .leftToRight))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view; view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150)); view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.coderInvalidValue) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try data.write(to: output)
        precondition(Localization.string("Story Library", language: language) != "Story Library" || language == "en")
        print("PASS: \(language) interface rendered without displaying or activating a window")
        window.contentView = nil
    }
}
