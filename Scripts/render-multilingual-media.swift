import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

@main struct RenderMedia {
    /// Keep image/color data byte-for-byte; omit textual and EXIF metadata before publication.
    static func stripPNGMetadata(at url: URL) throws {
        let data = try Data(contentsOf: url)
        var result = Data(data.prefix(8)), cursor = 8
        while cursor + 12 <= data.count {
            let length = data[cursor..<(cursor + 4)].reduce(0) { ($0 << 8) | Int($1) }
            let end = cursor + length + 12
            guard end <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            let kind = String(decoding: data[(cursor + 4)..<(cursor + 8)], as: UTF8.self)
            if !["tEXt", "zTXt", "iTXt", "eXIf"].contains(kind) { result.append(data[cursor..<end]) }
            cursor = end
        }
        try result.write(to: url)
    }
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let work = root.appendingPathComponent("local-evaluation/multilingual-demo")
        let output = root.appendingPathComponent("docs/assets")
        let input = try JSONSerialization.jsonObject(with: Data(contentsOf: work.appendingPathComponent("input.json"))) as! [String: Any]
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: work.appendingPathComponent("report.json"))) as! [String: Any]
        let count = report["frames"] as! Int
        let timeline = input["timeline"] as! [[String: Any]]
        let split = Int((timeline.last!["start"] as! Double) * 2)
        func frame(_ index: Int) -> CGImage {
            let url = work.appendingPathComponent(String(format: "frames/%05d.png", index))
            return CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
        }
        for (name, indices) in [("multilingual-five-languages", Array(0..<split)), ("multilingual-mixed", Array(split..<count))] {
            let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name + ".gif") as CFURL, UTType.gif.identifier as CFString, indices.count, nil)!
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for index in indices {
                CGImageDestinationAddImage(destination, frame(index), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.5]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { fatalError("GIF export failed") }
        }
        for (index, segment) in timeline.enumerated() where index < 5 {
            let frameIndex = min(count-1, Int(((segment["end"] as! Double) + 1.3)*2))
            let name = "multilingual-" + (segment["code"] as! String) + ".png"
            let dest = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, frame(frameIndex), nil); guard CGImageDestinationFinalize(dest) else { fatalError("PNG export failed") }
            try stripPNGMetadata(at: output.appendingPathComponent(name))
        }
        let silent = work.appendingPathComponent("silent.mp4")
        try? FileManager.default.removeItem(at: silent)
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1040, AVVideoHeightKey: 820, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_200_000, AVVideoExpectedSourceFrameRateKey: 2, AVVideoMaxKeyFrameIntervalKey: 10]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 1040, kCVPixelBufferHeightKey as String: 820, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(video); guard writer.startWriting() else { throw writer.error! }; writer.startSession(atSourceTime: .zero)
        for index in 0..<count {
            while !video.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pixel: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixel)
            CVPixelBufferLockBaseAddress(pixel!, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel!), width: 1040, height: 820, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel!), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            context.draw(frame(index), in: CGRect(x: 0, y: 0, width: 1040, height: 820))
            CVPixelBufferUnlockBaseAddress(pixel!, [])
            guard adaptor.append(pixel!, withPresentationTime: CMTime(value: Int64(index), timescale: 2)) else { throw writer.error! }
        }
        video.markAsFinished(); await writer.finishWriting(); guard writer.status == .completed else { throw writer.error! }
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silent); let audioAsset = AVURLAsset(url: work.appendingPathComponent("continuous.wav"))
        let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first!
        let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first!
        let videoDuration = try await videoAsset.load(.duration); let audioDuration = try await audioAsset.load(.duration)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration), of: audioTrack, at: .zero)
        let destination = output.appendingPathComponent("multilingual-continuous.mp4"); try? FileManager.default.removeItem(at: destination)
        let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        export.outputURL = destination; export.outputFileType = .mp4; export.shouldOptimizeForNetworkUse = true
        await export.export(); guard export.status == .completed else { throw export.error! }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination)); generator.appliesPreferredTrackTransform = true
        let image = try generator.copyCGImage(at: CMTime(seconds: 12, preferredTimescale: 600), actualTime: nil)
        let check = CGImageDestinationCreateWithURL(work.appendingPathComponent("video-check.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(check, image, nil); CGImageDestinationFinalize(check)
        print("Exported two realtime GIFs, five screenshots, and a full video with original synthetic audio.")
    }
}
