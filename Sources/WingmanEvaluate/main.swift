import Foundation
import AVFoundation
import WingmanCore

@main
struct EvaluateCommand {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 6 || args.count == 7 else {
            print("Usage: wingman-evaluate TEXT_WORKER ASR_WORKER MODEL_DIRECTORY AUDIO_FILE POLICY_FILE [--realtime]")
            Foundation.exit(2)
        }
        let backend = LocalTextBackend(), asr = SpeechStream()
        do {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[4]))
            guard file.length > 0, file.length <= AVAudioFramePosition(file.processingFormat.sampleRate * 300),
                  let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: file.processingFormat, to: format),
                  let destination = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 64) else {
                throw WingmanError.unavailable("音频必须为 0–300 秒的可读本地文件")
            }
            try file.read(into: source)
            var supplied = false, error: NSError?
            converter.convert(to: destination, error: &error) { _, status in
                if supplied { status.pointee = .endOfStream; return nil }
                supplied = true; status.pointee = .haveData; return source
            }
            if let error { throw error }
            var samples = Array(UnsafeBufferPointer(start: destination.floatChannelData![0], count: Int(destination.frameLength)))
            let audioSeconds = Double(samples.count) / 16_000
            samples += Array(repeating: 0, count: 32_000)
            let policy = try String(contentsOfFile: args[5], encoding: .utf8)
            let models = URL(fileURLWithPath: args[3])
            try await backend.load(paths: BackendPaths(worker: URL(fileURLWithPath: args[1]), model: models.appendingPathComponent(LocalModel.defaultModel.weightsFilename)))
            var finals: [String] = [], firstText: Double?, finalTime: Double?, failure: String?
            var started = Date()
            try await asr.start(worker: URL(fileURLWithPath: args[2]), models: models, onText: { text, _, final, _ in
                if firstText == nil { firstText = Date().timeIntervalSince(started) }
                if final { finals.append(text); finalTime = Date().timeIntervalSince(started) }
            }, onFailure: { failure = $0 })
            started = Date()
            let realtime = args.last == "--realtime"
            for offset in stride(from: 0, to: samples.count, by: 1600) {
                if let failure { throw WingmanError.worker(failure) }
                try asr.append(Array(samples[offset..<min(offset + 1600, samples.count)]))
                // Yield even for offline replay so the bounded pipe can drain.
                try await Task.sleep(for: .milliseconds(realtime ? 100 : 10))
            }
            try await asr.finish()
            if let failure { throw WingmanError.worker(failure) }
            let asrSeconds = Date().timeIntervalSince(started)
            let evaluation = try await backend.evaluate(text: finals.joined(separator: "\n"), configuration: SessionConfiguration(prompt: policy), context: [])
            struct Report: Encodable {
                let result: VoiceResult; let classificationSeconds: Double; let audioSeconds: Double
                let asrWallSeconds: Double; let firstTextSeconds: Double?; let finalTextSeconds: Double?; let realtime: Bool
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let report = Report(result: evaluation.result, classificationSeconds: evaluation.elapsedSeconds,
                audioSeconds: audioSeconds, asrWallSeconds: asrSeconds, firstTextSeconds: firstText, finalTextSeconds: finalTime, realtime: realtime)
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
            asr.stop(); await backend.shutdown()
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            asr.stop(); await backend.shutdown(); Foundation.exit(1)
        }
    }
}
