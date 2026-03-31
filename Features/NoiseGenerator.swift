import AVFoundation
import Foundation

private final class AudioRenderState: @unchecked Sendable {
    var brownB: Float = 0.0
    var pinkB0: Float = 0; var pinkB1: Float = 0; var pinkB2: Float = 0
    var pinkB3: Float = 0; var pinkB4: Float = 0; var pinkB5: Float = 0
    var pinkB6: Float = 0
    var rainBase: Float = 0.0
    var rainDropRemain: Int = 0
    var cafeBase: Float = 0.0
    var cafePhase: Float = 0.0
    var volume: Float = 0.7
}

@Observable
final class NoiseGenerator {
    private(set) var isPlaying = false
    private(set) var currentType: NoiseType = .brown

    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private let renderState = AudioRenderState()

    func start(type: NoiseType, volume: Float = 0.7) {
        stop()
        currentType = type
        renderState.volume = volume
        buildEngine(type: type)
    }

    func stop() {
        audioEngine?.stop()
        audioEngine = nil
        sourceNode = nil
        isPlaying = false
    }

    func setVolume(_ v: Float) {
        renderState.volume = max(0, min(1, v))
        audioEngine?.mainMixerNode.outputVolume = renderState.volume
    }

    private func buildEngine(type: NoiseType) {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let state = renderState
        let noiseType = type

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample: Float
                switch noiseType {
                case .brown: sample = NoiseGenerator.brownSample(state: state)
                case .pink:  sample = NoiseGenerator.pinkSample(state: state)
                case .white: sample = NoiseGenerator.whiteSample()
                case .rain:  sample = NoiseGenerator.rainSample(state: state)
                case .cafe:  sample = NoiseGenerator.cafeSample(state: state)
                }
                let out = sample * state.volume
                for buffer in abl {
                    buffer.mData!.assumingMemoryBound(to: Float.self)[frame] = out
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = renderState.volume

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            engine.prepare()
            try engine.start()
            audioEngine = engine
            sourceNode = node
            isPlaying = true
        } catch {
            print("NoiseGenerator error: \(error)")
        }
    }

    private static func whiteSample() -> Float { Float.random(in: -1...1) }

    private static func brownSample(state: AudioRenderState) -> Float {
        let white = Float.random(in: -1...1)
        state.brownB = (state.brownB + 0.02 * white) / 1.02
        return state.brownB * 3.5
    }

    private static func pinkSample(state: AudioRenderState) -> Float {
        let w = Float.random(in: -1...1)
        state.pinkB0 = 0.99886 * state.pinkB0 + w * 0.0555179
        state.pinkB1 = 0.99332 * state.pinkB1 + w * 0.0750759
        state.pinkB2 = 0.96900 * state.pinkB2 + w * 0.1538520
        state.pinkB3 = 0.86650 * state.pinkB3 + w * 0.3104856
        state.pinkB4 = 0.55000 * state.pinkB4 + w * 0.5329522
        state.pinkB5 = -0.7616 * state.pinkB5 - w * 0.0168980
        let pink = state.pinkB0 + state.pinkB1 + state.pinkB2 + state.pinkB3
                 + state.pinkB4 + state.pinkB5 + state.pinkB6 + w * 0.5362
        state.pinkB6 = w * 0.115926
        return pink * 0.11
    }

    private static func rainSample(state: AudioRenderState) -> Float {
        let white = Float.random(in: -1...1)
        state.rainBase = (state.rainBase + 0.008 * white) / 1.008
        var sample = state.rainBase * 2.0
        if state.rainDropRemain > 0 {
            state.rainDropRemain -= 1
            let fade = Float(state.rainDropRemain) / 250.0
            sample += Float.random(in: -0.4...0.4) * fade
        } else if Float.random(in: 0...1) < 0.0008 {
            state.rainDropRemain = Int.random(in: 150...350)
        }
        return sample * 0.75
    }

    private static func cafeSample(state: AudioRenderState) -> Float {
        let white = Float.random(in: -1...1)
        state.cafeBase = (state.cafeBase + 0.012 * white) / 1.012
        state.cafePhase += 0.00007
        let mod = (sin(state.cafePhase) * 0.35 + sin(state.cafePhase * 2.3) * 0.2 + 1.0) * 0.5
        let chatter = Float.random(in: -0.06...0.06) * mod
        return (state.cafeBase * 1.6 + chatter) * 0.9
    }
}
