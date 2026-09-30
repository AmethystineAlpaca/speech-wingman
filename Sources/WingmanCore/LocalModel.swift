import Foundation

public enum LocalModel: String, CaseIterable, Identifiable, Sendable {
    case qwen3 = "qwen3-4b-instruct-2507"
    public static let defaultModel: LocalModel = .qwen3
    public var id: String { rawValue }
    public var sizeLabel: String { "4B" }
    public var name: String { "Qwen3-4B-Instruct-2507" }
    public var displayName: String { "Qwen3 4B · Q4 · 本地文本判断" }
    public var weightsFilename: String { "Qwen3-4B-Instruct-2507-Q4_K_M.gguf" }
    // Migrate saved Omni selections; the audio models are no longer shipped.
    public static func restored(from storedValue: String?) -> LocalModel { .qwen3 }
}
