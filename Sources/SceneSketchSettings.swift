import SwiftUI
import AppKit

struct SceneSketchSettings: View {
    @AppStorage("promptCleanupEnabled") private var promptCleanup = true
    @AppStorage("exportPaper") private var paper = ""
    @AppStorage("exportOrientation") private var orientation = ExportOrientation.landscape.rawValue
    @AppStorage("exportLayout") private var layout = ExportLayout.six.rawValue
    @AppStorage("interfaceLanguage") private var language = ""
    var body: some View {
        TabView {
            Form {
                Picker(L("Language"), selection: $language) {
                    Text(L("System language")).tag("")
                    ForEach(Localization.languages) { Text($0.displayName).tag($0.code) }
                }
                Toggle(L("Clean up short frame descriptions before rendering"), isOn: $promptCleanup)
                Section(L("Export defaults")) {
                    Picker(L("Paper"), selection: $paper) {
                        Text(L("Ask when exporting")).tag("")
                        ForEach(ExportPaper.allCases) { Text(L($0.rawValue)).tag($0.rawValue) }
                    }
                    Picker(L("Orientation"), selection: $orientation) { ForEach(ExportOrientation.allCases) { Text(L($0.rawValue)).tag($0.rawValue) } }
                    Picker(L("Layout"), selection: $layout) { ForEach(ExportLayout.allCases) { Text(L($0.label)).tag($0.rawValue) } }
                }
            }.formStyle(.grouped).tabItem { Label(L("General"), systemImage: "gearshape") }
            ModelManagementView().padding(22).tabItem { Label(L("Models"), systemImage: "externaldrive") }
        }.frame(width: 700, height: 590)
            .onChange(of: language) { _, value in
                if value.isEmpty { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
                else { UserDefaults.standard.set([value], forKey: "AppleLanguages") }
            }
            .environment(\.locale, Locale(identifier: Localization.code))
            .environment(\.layoutDirection, Localization.isRightToLeft ? .rightToLeft : .leftToRight)
            .id(language)
    }
}

struct ModelManagementView: View {
    @State private var models = ModelManager.shared
    @State private var removing: ModelGroup?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L("Local models")).font(.title2.bold())
                Spacer()
                Text(models.allReady ? L("Ready offline") : L("Setup needed")).foregroundStyle(.secondary)
            }
            ForEach(ModelGroup.allCases) { group in
                HStack(spacing: 14) {
                    Image(systemName: models.installed.contains(group) ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(models.installed.contains(group) ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L(group.title)).font(.headline)
                        Text(L(group.detail)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: models.bytes([group]), countStyle: .file)).font(.caption).monospacedDigit()
                    if models.installed.contains(group) {
                        Button { removing = group } label: { Image(systemName: "trash") }.help(L("Remove models: %@", L(group.title)))
                    } else { Button(L("Download")) { models.install([group]) } }
                }.disabled(!models.canManage)
            }
            Divider()
            Text(L("Sketch style included with the app")).font(.callout)
            HStack {
                Text(models.folder).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                Spacer()
                Button(L("Use Folder…"), action: chooseFolder).disabled(!models.canManage)
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: models.folder)) } label: { Image(systemName: "folder") }.help(L("Show model folder"))
            }
            if models.isWorking {
                ProgressView(value: models.progress)
                HStack { Text(models.status).font(.callout); Spacer(); Button(L("Pause")) { models.pause() } }
            } else {
                HStack {
                    if !models.allReady {
                        Button(L("Download all — %@", ByteCountFormatter.string(fromByteCount: models.missingBytes(Set(ModelGroup.allCases)), countStyle: .file))) {
                            models.install(Set(ModelGroup.allCases))
                        }.buttonStyle(.borderedProminent).disabled(!models.canManage)
                    }
                    Button(L("Verify files")) { models.verify() }.disabled(!models.canManage)
                    Spacer()
                }
                if !models.status.isEmpty { Text(models.status).font(.caption).foregroundStyle(.secondary) }
            }
            if !models.message.isEmpty { Text(models.message).font(.callout).textSelection(.enabled) }
            Spacer(minLength: 0)
        }
        .onAppear { models.refresh() }
        .confirmationDialog(L("Remove downloaded models: %@?", L(removing?.title ?? "")), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(L("Remove models"), role: .destructive) { if let group = removing { models.remove(group) }; removing = nil }
        } message: { Text(L("Story files and reference images are kept.  You can download these models again.")) }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = L("Use Folder")
        panel.begin { result in if result == .OK, let url = panel.url { models.useFolder(url) } }
    }
}

struct ModelSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var models = ModelManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage()).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading) {
                    Text(L("Set up SceneSketch")).font(.title.bold())
                    Text(L("Download once.  Create locally.")).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ModelManagementView()
            HStack { Text(L("Your stories and images stay on this Mac.")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(models.drawingReady ? L("Done") : L("Later")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 700, height: 620)
    }
}
