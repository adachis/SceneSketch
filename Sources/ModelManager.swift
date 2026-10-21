import Foundation
import Observation
import CryptoKit

enum ModelGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case drawing, prompt, vision
    var id: String { rawValue }
    var title: String {
        switch self { case .drawing: L("Drawing"); case .prompt: L("Prompt cleanup"); case .vision: L("Image descriptions") }
    }
    var detail: String {
        switch self {
        case .drawing: L("FLUX.2 Klein 4B and its text encoder")
        case .prompt: L("Qwen3 0.6B")
        case .vision: L("Qwen3.5 2B")
        }
    }
}

struct ModelFile: Codable, Identifiable, Sendable {
    var group: ModelGroup
    var path: String
    var url: URL
    var bytes: Int64
    var sha256: String
    var id: String { path }
}

struct ModelCatalog: Codable, Sendable {
    var version: Int
    var files: [ModelFile]
    static func load(from url: URL) throws -> ModelCatalog {
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.version == 1, !value.files.isEmpty, Set(value.files.map(\.path)).count == value.files.count,
              value.files.allSatisfy({ file in
                  file.bytes > 0 && !file.path.hasPrefix("/") && !file.path.split(separator: "/").contains("..") &&
                  file.url.scheme == "https" && file.url.host == "huggingface.co" &&
                  file.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
              }) else { throw ModelError.catalog }
        return value
    }
    static func bundled() throws -> ModelCatalog {
        let override = ProcessInfo.processInfo.environment["SCENESKETCH_MODEL_CATALOG"].map { URL(fileURLWithPath: $0) }
        guard let url = override ?? Bundle.main.url(forResource: "ModelCatalog", withExtension: "json") else { throw ModelError.catalog }
        return try load(from: url)
    }
    func files(for groups: Set<ModelGroup>) -> [ModelFile] { files.filter { groups.contains($0.group) } }
    func isReady(_ group: ModelGroup, at root: URL) -> Bool {
        let needed = files(for: [group])
        return !needed.isEmpty && needed.allSatisfy { Self.hasExpectedSize($0, at: root) }
    }
    static func hasExpectedSize(_ file: ModelFile, at root: URL) -> Bool {
        guard let size = try? root.appendingPathComponent(file.path).resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return Int64(size) == file.bytes
    }
    static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation(); hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func isVerified(_ file: ModelFile, at root: URL) throws -> Bool {
        guard hasExpectedSize(file, at: root) else { return false }
        return try digest(root.appendingPathComponent(file.path)) == file.sha256
    }
}

enum ModelPaths {
    static func root() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        if let path = env["SCENESKETCH_MODELS_DIR"] ?? env["STORYBOARD_MODELS_DIR"] { return URL(fileURLWithPath: path, isDirectory: true) }
        if let selected = UserDefaults.standard.string(forKey: "modelStoragePath"), !selected.isEmpty { return URL(fileURLWithPath: selected, isDirectory: true) }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let legacy = support.appendingPathComponent("Storyboard/Models", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return support.appendingPathComponent("SceneSketch/Models", isDirectory: true)
    }
    static func require(_ group: ModelGroup) throws {
        guard try ModelCatalog.bundled().isReady(group, at: root()) else { throw ModelError.notInstalled(group) }
    }
}

@MainActor @Observable final class RuntimeActivity {
    static let shared = RuntimeActivity()
    var isRendering = false
    private var activeBatches = 0
    var isBusy: Bool { isRendering || activeBatches > 0 }
    func beginBatch() { activeBatches += 1 }
    func endBatch() { activeBatches = max(0, activeBatches - 1) }
}

@MainActor @Observable final class ModelManager {
    static let shared = ModelManager()
    private(set) var catalog = ModelCatalog(version: 1, files: [])
    private(set) var installed = Set<ModelGroup>()
    private(set) var isWorking = false
    private(set) var progress = 0.0
    private(set) var status = ""
    private(set) var message = ""
    private(set) var folder = ""
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var repairNeeded = Set<ModelGroup>()
    var canManage: Bool { !isWorking && !RuntimeActivity.shared.isBusy }
    var allReady: Bool { installed.count == ModelGroup.allCases.count }
    var drawingReady: Bool { installed.contains(.drawing) }

    private init() { refresh() }
    func refresh() {
        do {
            catalog = try ModelCatalog.bundled()
            let root = try ModelPaths.root(); folder = root.path
            installed = Set(ModelGroup.allCases.filter { catalog.isReady($0, at: root) }).subtracting(repairNeeded)
        } catch { message = ModelError.message(error) }
    }
    func bytes(_ groups: Set<ModelGroup>) -> Int64 { catalog.files(for: groups).reduce(0) { $0 + $1.bytes } }
    func missingBytes(_ groups: Set<ModelGroup>) -> Int64 {
        guard let root = try? ModelPaths.root() else { return bytes(groups) }
        return catalog.files(for: groups).filter { !ModelCatalog.hasExpectedSize($0, at: root) }.reduce(0) { $0 + $1.bytes }
    }
    func install(_ groups: Set<ModelGroup>) {
        guard canManage, !catalog.files.isEmpty else { return }
        isWorking = true; message = ""; progress = 0; status = L("Preparing download…")
        let catalog = catalog
        operation = Task {
            do {
                let root = try ModelPaths.root()
                try await ModelInstaller.shared.install(files: catalog.files(for: groups), at: root) { fraction, text in
                    Task { @MainActor in self.progress = fraction; self.status = text }
                }
                repairNeeded.subtract(groups); status = L("Models ready"); progress = 1
            } catch is CancellationError { status = L("Download paused.  Resume when you’re ready.") }
            catch { message = ModelError.message(error); status = L("Download incomplete") }
            isWorking = false; operation = nil; refresh()
        }
    }
    func verify() {
        guard canManage else { return }
        isWorking = true; message = ""; progress = 0; status = L("Checking model files…")
        let files = catalog.files
        operation = Task {
            do {
                let root = try ModelPaths.root()
                let check = Task.detached { () throws -> [ModelGroup] in
                    var failed: [ModelGroup] = []
                    for file in files {
                        try Task.checkCancellation()
                        if try !ModelCatalog.isVerified(file, at: root) { failed.append(file.group) }
                    }
                    return failed
                }
                let invalid = try await withTaskCancellationHandler { try await check.value } onCancel: { check.cancel() }
                repairNeeded = Set(invalid)
                message = invalid.isEmpty ? L("All model files passed verification.") : L("Model files needing repair: %@. Download the affected models again.", String(invalid.count))
                status = invalid.isEmpty ? L("Verified") : L("Repair needed")
            } catch { message = ModelError.message(error) }
            isWorking = false; operation = nil; refresh()
        }
    }
    func pause() { operation?.cancel() }
    func useFolder(_ url: URL) {
        guard canManage else { return }
        UserDefaults.standard.set(url.path, forKey: "modelStoragePath"); refresh(); status = ""; message = ""
    }
    func remove(_ group: ModelGroup) {
        guard canManage, let root = try? ModelPaths.root() else { return }
        do {
            for file in catalog.files(for: [group]) {
                let url = root.appendingPathComponent(file.path)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                let partial = url.appendingPathExtension("partial")
                if FileManager.default.fileExists(atPath: partial.path) { try FileManager.default.removeItem(at: partial) }
            }
            status = L("Models removed: %@", L(group.title)); refresh()
        } catch { message = L("Some model files couldn’t be removed.  Check the folder’s permissions.") }
    }
}

actor ModelInstaller {
    static let shared = ModelInstaller()
    private var active = false
    func install(files: [ModelFile], at root: URL, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        guard !active else { throw ModelError.busy }
        active = true; defer { active = false }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var pending: [ModelFile] = []
        for file in files {
            try Task.checkCancellation()
            progress(0, L("Checking %@…", L(file.group.title)))
            if try !ModelCatalog.isVerified(file, at: root) { pending.append(file) }
        }
        let required = pending.reduce(Int64(0)) { total, file in
            let partial = root.appendingPathComponent(file.path).appendingPathExtension("partial")
            let size = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            return total + max(0, file.bytes - min(size, file.bytes))
        }
        let available = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? Int64.max
        guard available > required + 536_870_912 else { throw ModelError.diskSpace(required) }
        let total = max(1, files.reduce(Int64(0)) { $0 + $1.bytes })
        var completed: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let target = root.appendingPathComponent(file.path)
            if !pending.contains(where: { $0.path == file.path }) { completed += file.bytes; continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let partial = target.appendingPathExtension("partial")
            let before = completed
            progress(Double(completed) / Double(total), L("Downloading %@…", L(file.group.title)))
            let partialSize = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let partialVerified = partialSize == file.bytes ? try ModelCatalog.digest(partial) == file.sha256 : false
            if !partialVerified {
                try await ModelFileTransfer(file: file, partial: partial) { count in
                    progress(Double(before + count) / Double(total), L("Downloading %@…", L(file.group.title)))
                }.run()
            }
            progress(Double(completed) / Double(total), L("Verifying %@…", L(file.group.title)))
            guard try ModelCatalog.digest(partial) == file.sha256 else {
                try? fm.removeItem(at: partial); throw ModelError.integrity
            }
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: partial, to: target)
            completed += file.bytes
        }
        progress(1, L("Models ready"))
    }
}

private final class ModelFileTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let file: ModelFile
    private let partial: URL
    private let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var count: Int64 = 0
    private var canceled = false
    private var lastProgress = Date.distantPast

    init(file: ModelFile, partial: URL, progress: @escaping @Sendable (Int64) -> Void) { self.file = file; self.partial = partial; self.progress = progress }
    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock(); self.continuation = continuation
                count = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                if count >= file.bytes { try? FileManager.default.removeItem(at: partial); count = 0 }
                var request = URLRequest(url: file.url); request.timeoutInterval = 60
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                if count > 0 { request.setValue("bytes=\(count)-", forHTTPHeaderField: "Range") }
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForResource = 86_400
                session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                task = session!.dataTask(with: request)
                let shouldCancel = canceled; task!.resume(); if shouldCancel { task!.cancel() }
                lock.unlock()
            }
        } onCancel: {
            self.lock.lock(); self.canceled = true; self.task?.cancel(); self.lock.unlock()
        }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else { completionHandler(.cancel); finish(ModelError.network); return }
        if http.statusCode == 206 && !(http.value(forHTTPHeaderField: "Content-Range") ?? "").hasPrefix("bytes \(count)-") { completionHandler(.cancel); finish(ModelError.network); return }
        do {
            if http.statusCode == 200 { count = 0; FileManager.default.createFile(atPath: partial.path, contents: nil) }
            handle = try FileHandle(forWritingTo: partial); try handle?.seek(toOffset: UInt64(count))
            completionHandler(.allow)
        } catch { completionHandler(.cancel); finish(error) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            guard count + Int64(data.count) <= file.bytes else { throw ModelError.integrity }
            try handle?.write(contentsOf: data); count += Int64(data.count)
            if Date().timeIntervalSince(lastProgress) > 0.1 { progress(count); lastProgress = Date() }
        } catch { dataTask.cancel(); finish(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish((error as? URLError)?.code == .cancelled ? CancellationError() : error) }
        else { finish(count == file.bytes ? nil : ModelError.network) }
    }
    private func finish(_ error: Error?) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        guard let pending else { return }
        try? handle?.close(); handle = nil; session?.finishTasksAndInvalidate(); session = nil
        if let error { pending.resume(throwing: error) } else { pending.resume() }
    }
}

enum ModelError: LocalizedError {
    case catalog, network, integrity, busy, diskSpace(Int64), notInstalled(ModelGroup)
    var errorDescription: String? {
        switch self {
        case .catalog: L("The model catalog is missing or invalid.  Reinstall SceneSketch.")
        case .network: L("The download stopped before it finished.  Check your connection and resume.")
        case .integrity: L("A model file failed verification.  Download it again.")
        case .busy: L("Wait for the current operation to finish.")
        case .diskSpace(let bytes): L("Free at least %@ on the model drive, then retry.", ByteCountFormatter.string(fromByteCount: bytes + 536_870_912, countStyle: .file))
        case .notInstalled(let group): L("Install the %@ models in SceneSketch Settings, then retry.", L(group.title))
        }
    }
    static func message(_ error: Error) -> String {
        if let error = error as? ModelError { return error.localizedDescription }
        if error is CancellationError { return L("Download paused.  Resume when you’re ready.") }
        return L("The model files couldn’t be prepared.  Check your connection and folder permissions, then retry.")
    }
}
