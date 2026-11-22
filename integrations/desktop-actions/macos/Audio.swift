import AVFoundation
import ScreenCaptureKit

// The worker only registers an audio output. No video buffers leave ScreenCaptureKit.
@available(macOS 13, *)
final class SystemAudioSink: NSObject, SCStreamOutput, SCStreamDelegate {
    private let target = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    private var converter: AVAudioConverter?
    private var started = false

    func stream(_ stream: SCStream, didStopWithError error: Error) { exit(1) }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sample.isValid, sample.numSamples > 0,
              let desc = sample.formatDescription,
              let input = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(cmAudioFormatDescription: desc),
                                           frameCapacity: AVAudioFrameCount(sample.numSamples)) else { return }
        input.frameLength = input.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(sample.numSamples),
                                                           into: input.mutableAudioBufferList) == noErr else { return }
        if converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: target)
        }
        let capacity = ceil(Double(input.frameLength) * target.sampleRate / input.format.sampleRate) + 16
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(capacity)) else { return }
        var delivered = false
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            if delivered { status.pointee = .noDataNow; return nil }
            delivered = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, output.frameLength > 0, let samples = output.floatChannelData?[0] else { return }
        if !started {
            FileHandle.standardOutput.write(Data("CAPRI-AUDIO-1\n".utf8))
            started = true
        }
        FileHandle.standardOutput.write(Data(bytes:samples, count:Int(output.frameLength) * MemoryLayout<Float>.size))
    }
}

@available(macOS 13, *)
func streamAudio() async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    guard let display = content.displays.first else { throw BridgeError.unavailable("No active display.") }
    let excluded = content.applications.filter { $0.processID == getppid() }
    let filter = SCContentFilter(display:display, excludingApplications:excluded, exceptingWindows:[])
    let config = SCStreamConfiguration()
    config.width = 2
    config.height = 2
    config.capturesAudio = true
    config.excludesCurrentProcessAudio = true
    config.channelCount = 1
    config.sampleRate = 48000
    let sink = SystemAudioSink()
    let stream = SCStream(filter:filter, configuration:config, delegate:sink)
    try stream.addStreamOutput(sink, type:.audio, sampleHandlerQueue:DispatchQueue(label:"capri.audio"))
    try await stream.startCapture()
    await withCheckedContinuation { (continuation: CheckedContinuation<Void,Never>) in
        DispatchQueue.global().async {
            _ = FileHandle.standardInput.readData(ofLength:1)
            continuation.resume()
        }
    }
    try await stream.stopCapture()
    withExtendedLifetime(sink) {}
}
