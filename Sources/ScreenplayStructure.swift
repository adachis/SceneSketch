import Foundation

enum ScreenplayStructure {
    private static let transition = try! NSRegularExpression(pattern: #"^(?:(?:(?:SMASH |MATCH |JUMP |HARD )?CUT|SMASH|MATCH|JUMP|FLASH|(?:CROSS[- ]?)?DISSOLVES?|WIPES?|FADE) TO(?: BLACK| WHITE)?|FADE (?:IN|OUT))[:.]?$"#, options: .caseInsensitive)
    private static let shotHeading = try! NSRegularExpression(pattern: #"^(?:ON (?:THE |A |AN )?(?:TV|TELEVISION|MONITOR|PHONE|COMPUTER|VIDEO|CINEMA)(?: SCREEN)?|ON THE SCREEN|(?:CLOSE(?:[- ]UP)?|ANGLE|FOCUS|TIGHT|WIDE) (?:ON|OF) .+|INSERT(?: SHOT)?(?: - .+)?|(?:BACK TO|RETURN TO)(?: .+)?|.+['’]S P\.?O\.?V\.?|P\.?O\.?V\.?(?: OF .+)?|THROUGH (?:THE )?(?:BINOCULARS|VIEWFINDER|WINDOW)|(?:BEGIN |END |.+ )?MONTAGE|SERIES OF SHOTS)[:.]?$"#)

    static func isTransition(_ text: String) -> Bool {
        matches(transition, text)
    }

    static func isShotHeading(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 100, value == value.uppercased(), !isTransition(value) else { return false }
        if value.hasSuffix(":") { return true }
        // Recognize camera and insert labels, not arbitrary capitalized action or character names.
        return matches(shotHeading, value)
    }

    static func grouped(_ input: [ScriptParagraph]) -> [ScriptParagraph] {
        var result: [ScriptParagraph] = []
        var pendingHeading = false
        var continuesAction = false
        for var paragraph in input {
            paragraph.text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paragraph.text.isEmpty else { continue }
            if paragraph.kind == "Transition" || (paragraph.kind == "Action" && isTransition(paragraph.text)) {
                pendingHeading = false
                continuesAction = false
                continue
            }
            let explicitShot = paragraph.kind == "Shot"
            if explicitShot { paragraph.kind = "Action" }
            let heading = explicitShot || (paragraph.kind == "Action" && isShotHeading(paragraph.text))
            let continuesPage = paragraph.startsPage && paragraph.kind == "Action" && !heading &&
                continuesAction && result.last?.kind == "Action" && result.last.map { continues($0.text, with: paragraph.text) } == true
            if paragraph.kind == "Action", result.last?.kind == "Action", pendingHeading || continuesPage {
                let separator = pendingHeading ? "\n" : " "
                result[result.count - 1].text += separator + paragraph.text
                pendingHeading = heading
            } else {
                result.append(paragraph)
                pendingHeading = heading
            }
            continuesAction = paragraph.kind == "Action"
        }
        return result
    }

    private static func continues(_ text: String, with next: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = value.last else { return false }
        guard last.isLetter || last.isNumber || last == "," else { return false }
        let connective = Set(["a", "an", "the", "and", "or", "to", "of", "with", "in", "on", "from", "into", "as", "at", "by"])
        return next.first?.isLowercase == true || last == "," || connective.contains(value.split(separator: " ").last?.lowercased() ?? "")
    }

    private static func matches(_ pattern: NSRegularExpression, _ text: String) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
