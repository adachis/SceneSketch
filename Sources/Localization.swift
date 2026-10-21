import Foundation

struct InterfaceLanguage: Codable, Identifiable, Sendable {
    var code: String
    var name: String
    var nativeName: String?
    var id: String { code }
    var displayName: String { nativeName ?? Locale(identifier: code).localizedString(forIdentifier: code) ?? name }
}

enum Localization {
    static let resourceRoot: URL = ProcessInfo.processInfo.environment["SCENESKETCH_RESOURCE_DIR"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.resourceURL ?? Bundle.main.bundleURL
    static let languages: [InterfaceLanguage] = {
        let url = resourceRoot.appendingPathComponent("Languages.json")
        guard let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([InterfaceLanguage].self, from: data) else {
            return [InterfaceLanguage(code: "en", name: "English")]
        }
        return values
    }()
    private static let systemCode = Bundle.preferredLocalizations(from: languages.map(\.code), forPreferences: Locale.preferredLanguages).first ?? "en"
    static var code: String {
        let selected = ProcessInfo.processInfo.environment["SCENESKETCH_INTERFACE_LANGUAGE"] ?? UserDefaults.standard.string(forKey: "interfaceLanguage") ?? ""
        if languages.contains(where: { $0.code == selected }) { return selected }
        return systemCode
    }
    static var isRightToLeft: Bool { ["ar", "ars", "apc", "arz", "ary", "acm", "acq", "aeb", "he", "fa", "prs", "ur", "sd", "yi"].contains(code) }
    static func string(_ key: String, language: String? = nil) -> String {
        let selected = language ?? code
        guard selected != "en", let bundle = Bundle(path: resourceRoot.appendingPathComponent(selected + ".lproj").path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    var value = Localization.string(key)
    guard !arguments.isEmpty else { return value }
    if formatTokens(value) != formatTokens(key) || !validPositions(value, count: arguments.count) { value = key }
    return String(format: value, locale: Locale(identifier: Localization.code), arguments: arguments)
}

private func formatTokens(_ value: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: #"%(?:[1-9]\d*\$)?[-+ #0]*(?:\d+|\*)?(?:\.\d+|\.\*)?(?:hh|ll|h|l|L|z|t|j)?[@a-zA-Z%]|%"#)
    let text = value as NSString
    return regex.matches(in: value, range: NSRange(location: 0, length: text.length)).map {
        text.substring(with: $0.range).replacingOccurrences(of: #"%\d+\$"#, with: "%", options: .regularExpression)
    }.sorted()
}

private func validPositions(_ value: String, count: Int) -> Bool {
    let regex = try! NSRegularExpression(pattern: #"%(\d+)\$"#)
    let text = value as NSString
    return regex.matches(in: value, range: NSRange(location: 0, length: text.length)).allSatisfy {
        guard let position = Int(text.substring(with: $0.range(at: 1))) else { return false }
        return (1...max(1, count)).contains(position)
    }
}
