import SwiftUI

struct ImportReview: View {
    @State var draft: ScreenplayDraft
    let apply: (ScreenplayDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var excluded = Set<UUID>()
    @State private var excludedShots = Set<UUID>()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Review screenplay import")).font(.title2.bold())
            TextField(L("Story title"), text: $draft.title)
            Text(L("Scenes: %@ · Proposed shots: %@", String(draft.scenes.count-excluded.count), String(draft.frames.filter { !excluded.contains($0.sceneID ?? UUID()) && !excludedShots.contains($0.id) }.count))).foregroundStyle(.secondary)
            TabView {
                List {
                    ForEach(draft.scenes) { scene in
                        DisclosureGroup {
                            ForEach(draft.frames.filter { $0.sceneID == scene.id }) { frame in
                                Toggle((try? EntityTokens.resolve(frame.description, entities: draft.entities)) ?? frame.description, isOn: Binding(get: { !excludedShots.contains(frame.id) }, set: { if $0 { excludedShots.remove(frame.id) } else { excludedShots.insert(frame.id) } })).font(.callout).padding(.vertical, 4)
                            }
                        } label: {
                            Toggle(scene.title, isOn: Binding(get: { !excluded.contains(scene.id) }, set: { if $0 { excluded.remove(scene.id) } else { excluded.insert(scene.id) } }))
                        }
                    }
                }.tabItem { Text(L("Scenes and shots")) }
                entityList(.character).tabItem { Text(L("Characters")) }
                entityList(.location).tabItem { Text(L("Locations")) }
            }
            ForEach(draft.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button(L("Cancel")) { dismiss() }; Spacer()
                Button(L("Import into story")) {
                    var result = draft
                    result.scenes.removeAll { excluded.contains($0.id) }
                    result.frames.removeAll { excluded.contains($0.sceneID ?? UUID()) || excludedShots.contains($0.id) }
                    apply(result); dismiss()
                }.buttonStyle(.borderedProminent).disabled(draft.scenes.count == excluded.count || draft.scenes.isEmpty)
            }
        }.padding(24).frame(width: 780, height: 650)
    }
    private func entityList(_ kind: EntityKind) -> some View {
        List {
            ForEach(draft.entities.indices.filter { draft.entities[$0].kind == kind }, id: \.self) { index in
                VStack(alignment: .leading) {
                    TextField(L("Name"), text: $draft.entities[index].name).font(.headline)
                    TextField(L("Description"), text: $draft.entities[index].description, axis: .vertical).lineLimit(2...4)
                }.padding(.vertical, 6)
            }
        }
    }
}
