import Foundation
import CryptoKit

enum ModelChecks {
    static func run(catalogURL: URL, server: URL) async throws {
        let catalog = try ModelCatalog.load(from: catalogURL)
        precondition(catalog.files.count >= 15 && Set(catalog.files.map(\.group)) == Set(ModelGroup.allCases))
        precondition(catalog.files.allSatisfy { $0.url.path.range(of: "/resolve/[a-f0-9]{40}/", options: .regularExpression) != nil })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scenesketch-model-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        precondition(!catalog.isReady(.drawing, at: root))
        let bytes = Data((0..<524_288).map { UInt8($0 % 251) })
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        var file = ModelFile(group: .drawing, path: "weights/model.bin", url: server.appendingPathComponent("range.bin"), bytes: Int64(bytes.count), sha256: sha)
        let folder = root.appendingPathComponent("weights")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try bytes.prefix(1024).write(to: root.appendingPathComponent(file.path + ".partial"))
        try await ModelInstaller.shared.install(files: [file], at: root) { _, _ in }
        let initial = try Data(contentsOf: root.appendingPathComponent(file.path))
        precondition(initial == bytes)
        file.url = server.appendingPathComponent("does-not-exist.bin")
        try await ModelInstaller.shared.install(files: [file], at: root) { _, _ in }
        var corrupt = file; corrupt.path = "weights/corrupt.bin"; corrupt.url = server.appendingPathComponent("bad.bin")
        do {
            try await ModelInstaller.shared.install(files: [corrupt], at: root) { _, _ in }
            preconditionFailure("A corrupt model must fail verification")
        } catch ModelError.integrity {}
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent(corrupt.path).path))
        var slow = file; slow.path = "weights/slow.bin"; slow.url = server.appendingPathComponent("slow.bin")
        let request = slow
        let transfer = Task { try await ModelInstaller.shared.install(files: [request], at: root) { _, _ in } }
        try await Task.sleep(for: .milliseconds(80)); transfer.cancel()
        do { try await transfer.value; preconditionFailure("A paused download must cancel") } catch is CancellationError {}
        let partial = root.appendingPathComponent(slow.path + ".partial")
        precondition(FileManager.default.fileExists(atPath: partial.path))
        try await ModelInstaller.shared.install(files: [slow], at: root) { _, _ in }
        let resumed = try Data(contentsOf: root.appendingPathComponent(slow.path))
        precondition(resumed == bytes)
        var noRange = file; noRange.path = "weights/no-range.bin"; noRange.url = server.appendingPathComponent("no-range.bin")
        try bytes.prefix(1200).write(to: root.appendingPathComponent(noRange.path + ".partial"))
        try await ModelInstaller.shared.install(files: [noRange], at: root) { _, _ in }
        let restarted = try Data(contentsOf: root.appendingPathComponent(noRange.path))
        precondition(restarted == bytes)
        print("PASS: pinned model catalog, missing-model detection, streaming download, resume, pause, restart without range support, checksum rejection, and verified cache reuse")
    }
}
