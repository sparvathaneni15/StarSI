// Microphone capture with energy VAD, WAV framing, and queued playback of
// the synthesized sentences coming back down the tunnel.

import Foundation

#if canImport(AVFoundation)
import AVFoundation

public final class AudioCapture: @unchecked Sendable {
    public enum Event: Sendable {
        case level(Float)
        /// One complete utterance as a 16 kHz mono 16-bit WAV.
        case utterance(Data)
    }

    private let engine = AVAudioEngine()
    private var pcm = Data()
    private var speechStarted = false
    private var silentFrames = 0

    /// RMS above this counts as speech; ~600 ms of silence ends the utterance.
    public var speechThreshold: Float = 0.015
    public var silenceHangover = 9        // taps of ~64 ms each

    public func start(onEvent: @escaping @Sendable (Event) -> Void) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else { throw NSError(domain: "starsi.voice", code: 1) }

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            AVAudioEngineTapBridge.shared.publish(buffer)   // feeds local captions
            let rms = Self.rms(buffer)
            onEvent(.level(rms))

            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                             frameCapacity: capacity) else { return }
            var fed = false
            converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            let bytes = Int(out.frameLength) * 2
            if bytes > 0, let samples = out.int16ChannelData?[0] {
                self.ingest(Data(bytes: samples, count: bytes), rms: rms, onEvent: onEvent)
            }
        }
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        pcm.removeAll()
        speechStarted = false
    }

    private func ingest(_ chunk: Data, rms: Float, onEvent: (Event) -> Void) {
        let isSpeech = rms >= speechThreshold
        if !speechStarted {
            if !isSpeech { return }
            speechStarted = true
            silentFrames = 0
        }
        pcm.append(chunk)
        silentFrames = isSpeech ? 0 : silentFrames + 1
        if silentFrames >= silenceHangover {
            let wav = Self.wav(fromPCM16: pcm, sampleRate: 16000)
            pcm.removeAll()
            speechStarted = false
            silentFrames = 0
            onEvent(.utterance(wav))
        }
    }

    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        return (sum / Float(buffer.frameLength)).squareRoot()
    }

    public static func wav(fromPCM16 pcm: Data, sampleRate: Int) -> Data {
        var data = Data()
        func str(_ s: String) { data.append(Data(s.utf8)) }
        func u32(_ v: UInt32) { var le = v.littleEndian; data.append(Data(bytes: &le, count: 4)) }
        func u16(_ v: UInt16) { var le = v.littleEndian; data.append(Data(bytes: &le, count: 2)) }
        str("RIFF"); u32(UInt32(36 + pcm.count)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        str("data"); u32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

/// Plays sentence-audio chunks strictly in order; drop-all on barge-in.
public final class SpeechPlayer: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private var queue: [Data] = []
    private var player: AVAudioPlayer?

    public func enqueue(_ wav: Data) {
        queue.append(wav)
        playNextIfIdle()
    }

    public func stopAll() {
        queue.removeAll()
        player?.stop()
        player = nil
    }

    private func playNextIfIdle() {
        guard player == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        guard let p = try? AVAudioPlayer(data: next) else { playNextIfIdle(); return }
        p.delegate = self
        player = p
        p.play()
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        playNextIfIdle()
    }
}
#endif
