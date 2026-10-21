import SwiftUI
import AppKit

struct TokenTextEditor: NSViewRepresentable {
    @Binding var text: String
    let entities: [StoryEntity]
    @Binding var insertion: UUID?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = PillTextView(); view.isRichText = true; view.importsGraphics = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.font = .systemFont(ofSize: 14); view.textColor = .labelColor; view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 8, height: 10)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.entities = entities
        view.delegate = context.coordinator; view.setAccessibilityLabel("Shot description")
        scroll.documentView = view; context.coordinator.editor = view
        context.coordinator.refresh(text, entities: entities)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        (scroll.documentView as? PillTextView)?.entities = entities
        if context.coordinator.lastText != text || context.coordinator.names != entities.map({ $0.name }) {
            context.coordinator.refresh(text, entities: entities)
        }
        if insertion == nil { context.coordinator.handledInsertion = nil }
        if let id = insertion, context.coordinator.handledInsertion != id, let entity = entities.first(where: { $0.id == id }), let view = context.coordinator.editor {
            context.coordinator.handledInsertion = id
            view.window?.makeFirstResponder(view)
            view.insertText(NSAttributedString(attachment: EntityAttachment(entity)), replacementRange: view.selectedRange())
            view.typingAttributes = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]
            DispatchQueue.main.async { insertion = nil }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TokenTextEditor
        weak var editor: NSTextView?
        var lastText = ""
        var names: [String] = []
        var updating = false
        var handledInsertion: UUID?
        init(_ parent: TokenTextEditor) { self.parent = parent }
        func refresh(_ text: String, entities: [StoryEntity]) {
            guard let view = editor else { return }; updating = true; defer { updating = false }
            let rendered = NSMutableAttributedString(string: "")
            let source = text as NSString; var offset = 0
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]
            for item in EntityTokens.matches(text) {
                rendered.append(NSAttributedString(string: source.substring(with: NSRange(location: offset, length: item.range.location-offset)), attributes: attributes))
                if let entity = entities.first(where: { $0.id == item.id }) { rendered.append(NSAttributedString(attachment: EntityAttachment(entity))) }
                else { rendered.append(NSAttributedString(string: "[Missing reference]", attributes: attributes)) }
                offset = NSMaxRange(item.range)
            }
            rendered.append(NSAttributedString(string: source.substring(from: offset), attributes: attributes))
            let cursor = min(view.selectedRange().location, rendered.length)
            view.textStorage?.setAttributedString(rendered); view.setSelectedRange(NSRange(location: cursor, length: 0))
            lastText = text; names = entities.map(\.name)
        }
        func textDidChange(_ notification: Notification) {
            guard !updating, let storage = editor?.textStorage else { return }
            let plain = NSMutableString(string: storage.string)
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: .reverse) { value, range, _ in
                if let attachment = value as? EntityAttachment { plain.replaceCharacters(in: range, with: EntityTokens.token(attachment.entityID)) }
            }
            lastText = plain as String; parent.text = lastText
        }
    }
}

private final class EntityAttachment: NSTextAttachment {
    let entityID: UUID
    init(_ entity: StoryEntity) {
        entityID = entity.id
        super.init(data: nil, ofType: nil)
        let label = (entity.kind == .character ? "● " : "◆ ") + entity.name
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let size = (label as NSString).size(withAttributes: [.font: font])
        let canvas = NSImage(size: NSSize(width: size.width+14, height: 23))
        canvas.lockFocus()
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: canvas.size), xRadius: 7, yRadius: 7).fill()
        (label as NSString).draw(at: NSPoint(x: 7, y: 4), withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
        canvas.unlockFocus(); image = canvas; bounds = NSRect(x: 0, y: -5, width: canvas.size.width, height: canvas.size.height)
    }
    required init?(coder: NSCoder) { return nil }
}
private final class PillTextView: NSTextView {
    var entities: [StoryEntity] = []
    private let tokenType = NSPasteboard.PasteboardType("com.adachis.storyboard.token-text")
    override func copy(_ sender: Any?) {
        guard let selected = textStorage?.attributedSubstring(from: selectedRange()) else { return }
        let raw = NSMutableString(string: selected.string)
        selected.enumerateAttribute(.attachment, in: NSRange(location: 0, length: selected.length), options: .reverse) { value, range, _ in
            if let item = value as? EntityAttachment { raw.replaceCharacters(in: range, with: EntityTokens.token(item.entityID)) }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(raw as String, forType: tokenType)
        NSPasteboard.general.setString((try? EntityTokens.resolve(raw as String, entities: entities)) ?? raw as String, forType: .string)
    }
    override func cut(_ sender: Any?) { copy(sender); insertText("", replacementRange: selectedRange()) }
    override func paste(_ sender: Any?) {
        guard var value = NSPasteboard.general.string(forType: tokenType) ?? NSPasteboard.general.string(forType: .string) else { return }
        if EntityTokens.matches(value).contains(where: { token in !entities.contains(where: { $0.id == token.id }) }) {
            value = NSPasteboard.general.string(forType: .string) ?? value
        }
        let result = NSMutableAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor])
        for token in EntityTokens.matches(value).reversed() {
            if let entity = entities.first(where: { $0.id == token.id }) { result.replaceCharacters(in: token.range, with: NSAttributedString(attachment: EntityAttachment(entity))) }
        }
        insertText(result, replacementRange: selectedRange())
        typingAttributes = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]
    }
}
