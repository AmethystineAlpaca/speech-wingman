import Foundation
import NaturalLanguage

/// Alert language follows speech, independently of the interface and policy languages.
public enum SpeechLanguage: Sendable {
    case chinese, english

    public static func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0x20000...0x2FA1F).contains($0.value) }
    }

    public static func detect(_ text: String) -> Self {
        guard containsChinese(text) else { return .english }
        // Product names such as BigQuery must not turn a Chinese sentence into English.
        let chineseCount = text.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) || (0x20000...0x2FA1F).contains($0.value) }.count
        let englishWords = text.ranges(of: /[A-Za-z]+/).count
        if chineseCount >= max(1, englishWords) { return .chinese }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .simplifiedChinese, .traditionalChinese]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .english ? .english : .chinese
    }

    public var displayLanguage: DisplayLanguage { self == .chinese ? .chinese : .english }
}
