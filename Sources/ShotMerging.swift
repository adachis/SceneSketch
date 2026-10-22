import Foundation

extension StoryboardDocument {
    func canMergeShots(_ ids: Set<UUID>) -> Bool {
        let selected = frames.filter { ids.contains($0.id) }
        return ids.count > 1 && selected.count == ids.count &&
            selected.first?.sceneID != nil && Set(selected.compactMap(\.sceneID)).count == 1
    }

    /// Keeps the first shot's identity and camera while preserving the selected shots' content.
    @discardableResult
    mutating func mergeShots(_ ids: Set<UUID>) -> UUID? {
        guard canMergeShots(ids) else { return nil }
        let selected = frames.filter { ids.contains($0.id) }
        var merged = selected[0]
        merged.description = joined(selected.map(\.description))
        merged.sourceText = joined(selected.map(\.sourceText))
        merged.details = ShotDetails(
            number: joined(selected.map(\.details.number)), lens: joined(selected.map(\.details.lens)),
            duration: joined(selected.map(\.details.duration)), movement: joined(selected.map(\.details.movement)),
            dialogue: joined(selected.map(\.details.dialogue)), notes: joined(selected.map(\.details.notes)))
        var seenReferences = Set<UUID>()
        merged.referenceIDs = selected.flatMap { $0.referenceIDs + ($0.selectedReferenceIDs ?? []) }
            .filter { seenReferences.insert($0).inserted }
        // Reapply the normal three-image budget instead of combining incompatible explicit selections.
        merged.selectedReferenceIDs = nil
        merged.approved = false

        let active = selected.compactMap(\.currentVersion).first
        var seenVersions: [UUID: RenderVersion] = active.map { [$0.id: $0] } ?? [:]
        merged.history = []
        for var version in selected.flatMap(\.versions) {
            if let previous = seenVersions[version.id] {
                if previous == version { continue }
                version.id = UUID()
            }
            seenVersions[version.id] = version
            if version.id != active?.id { merged.history.append(version) }
        }
        if let active {
            merged.image = active.image; merged.imageRevision = active.id; merged.renderedAt = active.createdAt
            merged.seed = active.seed; merged.renderedPrompt = active.prompt; merged.renderedDescription = active.description
            merged.renderedShot = active.shot; merged.renderedReferenceIDs = active.referenceIDs
        }
        let index = frames.firstIndex { $0.id == merged.id }!
        frames[index] = merged
        frames.removeAll { ids.contains($0.id) && $0.id != merged.id }
        return merged.id
    }

    private func joined(_ values: [String]) -> String {
        values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n\n")
    }
}
