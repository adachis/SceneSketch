import SwiftUI

struct RenderHistoryView: View {
    @Binding var document: StoryboardDocument
    let frameID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    private var index: Int? { document.frames.firstIndex { $0.id == frameID } }
    private var versions: [RenderVersion] { index.map { document.frames[$0].versions } ?? [] }
    private var selected: RenderVersion? { versions.first { $0.id == selection } ?? versions.first }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(L("Render history")).font(.title2.bold()); Spacer(); Button(L("Done")) { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
            Divider()
            HSplitView {
                List(versions, selection: $selection) { version in
                    VStack(alignment: .leading, spacing: 6) {
                        FrameImage(data: version.image).frame(width: 160, height: 90)
                        if version.createdAt.timeIntervalSince1970 > 0 { Text(version.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption) }
                        if let index, version.id == document.frames[index].imageRevision { Text(L("Current image")).font(.caption.bold()) }
                    }.padding(.vertical, 5).tag(version.id)
                }.frame(width: 200)
                if let selected {
                    VStack(alignment: .leading, spacing: 12) {
                        FrameImage(data: selected.image).frame(maxWidth: .infinity, maxHeight: .infinity)
                        DisclosureGroup(L("Rendered prompt")) { ScrollView { Text(selected.prompt).font(.caption).textSelection(.enabled) }.frame(maxHeight: 100) }
                        HStack {
                            Text(L("Seed: %@", String(selected.seed))).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(L("Restore shot description")) {
                                guard let index else { return }
                                document.frames[index].description = selected.description
                                document.frames[index].shot = selected.shot
                                document.frames[index].selectedReferenceIDs = selected.referenceIDs
                            }
                            Button(L("Use image")) { if let index { document.frames[index].selectVersion(selected.id) } }
                                .buttonStyle(.borderedProminent).disabled(index.map { document.frames[$0].imageRevision == selected.id } ?? true)
                        }
                    }.padding(20)
                }
            }
        }.frame(width: 1000, height: 650).onAppear { selection = versions.first?.id }
    }
}
