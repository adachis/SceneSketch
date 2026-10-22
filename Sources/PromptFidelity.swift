import Foundation

enum PromptFidelity {
    // A small language model may tidy a fragment, but cannot drop its concrete content.
    static func preservesContent(original: String, candidate: String) -> Bool {
        let ignored: Set<String> = ["a", "an", "the", "and", "of", "to", "is", "are", "please", "draw", "show", "me", "image", "frame", "shot"]
        func words(_ value: String) -> Set<String> {
            Set(value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !ignored.contains($0) })
        }
        let source = words(original), output = words(candidate)
        return !candidate.isEmpty && candidate.count <= max(original.count * 3, 120) && source == output
    }
}

enum ShotStaging {
    static func prepare(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"\bglancing\s+(?:over\s+)?(?:to|toward)\s+"#, with: "turning their head and looking at ", options: [.regularExpression, .caseInsensitive])
        // Translate motion into its visible end state without replacing the user's action.
        let negated = text.range(of: #"\b(?:not|never|don't|doesn't)\s+lower(?:s|ing|ed)?\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        if !negated, text.range(of: #"\blower(?:s|ing|ed)?\s+(?:the\s+|her\s+|his\s+|their\s+)?binoculars\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            for (motion, pose) in [("lowers", "holds"), ("lowering", "holding"), ("lowered", "held"), ("lower", "hold")] {
                result = result.replacingOccurrences(of: "\\b" + motion + #"(\s+(?:(?:the|her|his|their)\s+)?binoculars)\b"#, with: pose + "$1 down at waist level", options: [.regularExpression, .caseInsensitive])
            }
            result += " The hands and binoculars are near the hips, far below the uncovered face."
        }
        return result
    }
}
