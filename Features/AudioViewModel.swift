import Foundation
import AVFoundation

@Observable
final class AudioViewModel {
    var selectedNoise: NoiseType = .brown {
        didSet {
            guard isPlaying else { return }
            generator.start(type: selectedNoise, volume: Float(volume))
        }
    }

    var volume: Double = 0.7 {
        didSet { generator.setVolume(Float(volume)) }
    }

    var isPlaying: Bool { generator.isPlaying }
    var isBreakPhase: Bool = false { didSet { applyAdaptiveVolume() } }

    private let generator = NoiseGenerator()
    private let workVolumeFactor: Float  = 1.0
    private let breakVolumeFactor: Float = 0.55

    func play()   { generator.start(type: selectedNoise, volume: Float(volume) * currentFactor) }
    func stop()   { generator.stop() }
    func toggle() { isPlaying ? stop() : play() }

    private var currentFactor: Float { isBreakPhase ? breakVolumeFactor : workVolumeFactor }
    private func applyAdaptiveVolume() {
        guard isPlaying else { return }
        generator.setVolume(Float(volume) * currentFactor)
    }
}
