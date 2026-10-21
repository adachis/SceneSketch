import Foundation
import Vision

enum RenderTextPolicy {
    static func letteringScore(_ image: CGImage) -> Int {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.012
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return 0 }
        return (request.results ?? []).reduce(0) { score, observation in
            guard let text = observation.topCandidates(1).first, text.confidence >= 0.4 else { return score }
            let characters = text.string.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
            return score + (characters >= 2 ? characters : 0)
        }
    }

    static func prepare(_ input: String) -> String {
        var result = input
        let replacements: [(String, String)] = [
            (#"(?i)\b(menu\s+boards?|chalkboards?|blackboards?)\b"#, "blank board"),
            (#"(?i)\b(menus?)\b"#, "blank card"),
            (#"(?i)(?<!hand )\b(signs?|signage|posters?|billboards?)\b(?!\s+(?:language|of\b))"#, "blank panel"),
            (#"(?i)\b(newspapers?)\b"#, "plain folded paper"),
            (#"(?i)\b(logos?|watermarks?|captions?|subtitles?)\b"#, "plain surface"),
            (#"(?i)\b(reading|saying|label(?:l)?ed|printed with|bearing the words|with the text|that reads|that says)\s*[\"“][^\"”]*[\"”]"#, "with a blank surface"),
            (#"(?i)\b(reading|saying|label(?:l)?ed|printed with|bearing the words|with the text|that reads|that says)\s*'[^']*'"#, "with a blank surface")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result
    }
}
