import AVFoundation
import Foundation

final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var installed = false
    func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        stop()
        let node = engine.inputNode
        let source = node.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "麦克风音频格式不可用"])
        }
        node.installTap(onBus: 0, bufferSize: 1024, format: source) { buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / source.sampleRate)) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var provided = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if provided { status.pointee = .noDataNow; return nil }
                provided = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, let channel = converted.floatChannelData?[0], converted.frameLength > 0 else { return }
            onSamples(Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))).map { min(1, max(-1, $0)) })
        }
        installed = true
        engine.prepare()
        do { try engine.start() } catch { stop(); throw error }
    }
    func stop() {
        engine.stop()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
    }
}
