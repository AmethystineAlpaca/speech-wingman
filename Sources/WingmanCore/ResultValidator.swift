import Foundation

public enum ResultValidator {
    public static func decodeDecision(_ raw: String, transcript: String) throws -> VoiceResult {
        guard let data = raw.data(using: .utf8), data.count <= 4096,
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let decision = object["decision"],
              Set(object.keys) == (decision == "alert" ? Set(["decision", "quote", "suggestion"]) : Set(["decision"])) else {
            throw WingmanError.invalidResult("判断字段或类型错误")
        }
        object["transcript"] = transcript
        if decision != "alert" { object["quote"] = ""; object["suggestion"] = "" }
        let full = try JSONSerialization.data(withJSONObject: object)
        let result = try decode(String(decoding: full, as: UTF8.self))
        if result.decision == .alert {
            let wantsChinese = SpeechLanguage.detect(transcript) == .chinese
            guard (SpeechLanguage.detect(result.suggestion) == .chinese) == wantsChinese else {
                throw WingmanError.invalidResult("提醒语言与当前发言不符")
            }
        }
        return result
    }
    public static func decode(_ raw: String) throws -> VoiceResult {
        guard let data = raw.data(using: .utf8), data.count <= 32_768,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["transcript", "decision", "quote", "suggestion"]),
              object.values.allSatisfy({ $0 is String }) else {
            throw WingmanError.invalidResult("JSON 字段或类型错误")
        }
        let result: VoiceResult
        do { result = try JSONDecoder().decode(VoiceResult.self, from: data) }
        catch { throw WingmanError.invalidResult("无效的判断状态") }
        guard result.transcript.count <= 4_000, result.quote.count <= 500,
              result.suggestion.count <= 160 else {
            throw WingmanError.invalidResult("输出过长")
        }
        if result.decision == .alert {
            guard !result.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !result.suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  result.transcript.contains(result.quote) else {
                throw WingmanError.invalidResult("提醒缺少原话或建议，或原话不是转写子串")
            }
            guard !result.suggestion.contains("\n") else {
                throw WingmanError.invalidResult("建议只能是一行")
            }
        } else if !result.quote.isEmpty || !result.suggestion.isEmpty {
            throw WingmanError.invalidResult("安静状态必须使用空原话和建议")
        }
        return result
    }
}
