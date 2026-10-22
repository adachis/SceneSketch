import Foundation

/// Conservative extraction: only concrete objects with explicit visual details become library entries.
enum ScreenplayProps {
    struct Mention {
        var name: String
        var noun: String
        var phrase: String
    }
    private static let nouns = [
        "pocket watch", "wrist watch", "wedding ring", "engagement ring", "police car", "pickup truck", "sports car", "space ship",
        "briefcase", "suitcase", "backpack", "handbag", "purse", "satchel", "duffel", "wallet", "locket", "pendant", "necklace", "bracelet", "medallion", "ring", "watch",
        "notebook", "journal", "diary", "book", "letter", "envelope", "photograph", "photo", "map", "scroll", "document", "key", "coin", "box", "chest", "case", "bottle", "flask", "cup", "mug", "goblet", "vase", "bowl", "plate",
        "sword", "dagger", "knife", "gun", "pistol", "revolver", "rifle", "shotgun", "shield", "helmet", "crown", "staff", "wand", "talisman", "amulet", "orb", "crystal", "statue", "figurine", "doll", "toy", "ball",
        "phone", "radio", "camera", "laptop", "computer", "tablet", "typewriter", "flashlight", "lantern", "lamp", "candle", "guitar", "violin", "trumpet", "drum",
        "car", "truck", "motorcycle", "bicycle", "van", "boat", "ship", "airplane", "helicopter", "vehicle", "robot", "device", "machine", "tool", "hammer", "axe", "shovel", "umbrella", "cane", "hat", "coat", "jacket", "scarf", "glove", "boot", "mask"
    ].sorted { $0.count > $1.count }
    private static let attributes: Set<String> = Set("red blue green yellow orange purple violet pink black white gray brown gold golden silver bronze brass copper cream ivory teal turquoise maroon crimson scarlet navy beige tan indigo amber wooden wood metal metallic steel iron leather glass plastic stone marble ceramic porcelain paper canvas velvet wool silk chrome aluminum rubber small large tiny huge long short narrow wide tall round square rectangular oval triangular curved straight flat thick thin heavy bulky slim compact antique ancient vintage modern futuristic ornate plain decorated engraved embossed carved etched polished shiny dull matte glossy cracked chipped scratched worn battered dented rusted rusty tarnished weathered faded torn tattered broken frayed jeweled beaded studded striped spotted checkered patterned transparent translucent opaque spherical cylindrical conical octagonal hexagonal triangular leather-bound hardback hardcover paperback folding folded jeweled jewel-encrusted".split(separator: " ").map(String.init))
    private static let nounPattern = nouns.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
    private static let matcher = try! NSRegularExpression(pattern: #"\b("# + nounPattern + #")\b"#, options: .caseInsensitive)

    static func mentions(in text: String) -> [Mention] {
        let source = text as NSString
        var result: [Mention] = []
        for match in matcher.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let before = source.substring(to: match.range.location)
            let words = before.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "." || $0 == ";" || $0 == ":" })
            var details: [String] = []
            for word in words.reversed().prefix(7) {
                let clean = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                guard attributes.contains(clean) || clean.hasSuffix("-shaped") else { break }
                details.insert(String(word), at: 0)
            }
            let preceding = words.dropLast(details.count).suffix(3).joined(separator: " ").lowercased()
            if preceding.contains("without") || preceding.split(separator: " ").contains("no") { continue }
            let noun = source.substring(with: match.range).lowercased()
            let after = source.substring(from: NSMaxRange(match.range))
            let end = after.firstIndex(where: { ".!?;\n".contains($0) }) ?? after.endIndex
            let clause = String(after[..<end]).trimmingCharacters(in: .whitespaces)
            let tail: String
            if clause.range(of: #"^,?\s*(?:with|is|has|covered in|made of)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
               clause.split(whereSeparator: { !$0.isLetter && $0 != "-" }).contains(where: { attributes.contains($0.lowercased()) }),
               clause.range(of: #"\b(?:man|woman|person|boy|girl|people|wearing)\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
                // Stop before a new action; retain only the stated appearance clause.
                let stop = clause.range(of: #"\b(?:then|while|before|after|opens?|walks?|runs?|lifts?|picks?|drops?|places?|hands?|grabs?|takes?|puts?|turns?|carries?|swings?|stabs?|shoots?|lies?|sits?|rests?)\b"#, options: [.regularExpression, .caseInsensitive])?.lowerBound ?? clause.endIndex
                tail = String(clause[..<stop]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else { tail = "" }
            guard !details.isEmpty || !tail.isEmpty else { continue }
            let phrase = ([details.joined(separator: " "), noun, tail].filter { !$0.isEmpty }).joined(separator: " ")
            guard phrase.count <= 240 else { continue }
            let name = (details + [noun]).joined(separator: " ").capitalized
            result.append(Mention(name: name, noun: noun, phrase: phrase))
        }
        return result
    }

    static func consolidated(_ mentions: [Mention]) -> [Mention] {
        mentions.compactMap { mention in
            guard mention.name.normalizedName == mention.noun.normalizedName else { return mention }
            let named = Set(mentions.filter { $0.noun == mention.noun && $0.name.normalizedName != $0.noun.normalizedName }.map(\.name))
            guard named.count <= 1 else { return nil }
            var value = mention
            if let name = named.first { value.name = name }
            return value
        }
    }

    struct Linker {
        private let rules: [(NSRegularExpression, String)]
        init(mentions: [Mention], entities: [StoryEntity]) {
            var aliases: [String: [UUID]] = [:]
            var entitiesByName: [String: UUID] = [:]
            for entity in entities where entity.kind == .prop { entitiesByName[entity.name.normalizedName] = entity.id }
            for mention in mentions {
                guard let id = entitiesByName[mention.name.normalizedName] else { continue }
                for alias in [mention.name, mention.noun, String(mention.noun.split(separator: " ").last ?? "")] {
                    if !(aliases[alias.lowercased()] ?? []).contains(id) { aliases[alias.lowercased(), default: []].append(id) }
                }
            }
            let bare = Set(mentions.flatMap { [$0.noun, String($0.noun.split(separator: " ").last ?? "")] })
            rules = aliases.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }.compactMap { alias in
                guard let ids = aliases[alias], ids.count == 1 else { return nil }
                let isBareNoun = bare.contains(alias)
                let prefix = isBareNoun ? #"(\b(?:the|a|an|her|his|their|its|my|your|our|this|that)\s+)"# : #"(?<![\p{L}\p{N}])"#
                let pattern = prefix + NSRegularExpression.escapedPattern(for: alias) + #"(?![\p{L}\p{N}])"#
                return (try! NSRegularExpression(pattern: pattern, options: .caseInsensitive), (isBareNoun ? "$1" : "") + EntityTokens.token(ids[0]))
            }
        }
        func link(_ text: String) -> String {
            rules.reduce(text) { value, rule in
                rule.0.stringByReplacingMatches(in: value, range: NSRange(location: 0, length: (value as NSString).length), withTemplate: rule.1)
            }
        }
    }

    static func link(_ text: String, mentions: [Mention], entities: [StoryEntity]) -> String {
        Linker(mentions: mentions, entities: entities).link(text)
    }
}
