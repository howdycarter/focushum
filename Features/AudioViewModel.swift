import Foundation
import AVFoundation
import Combine

@MainActor
protocol AudioPlayback: AnyObject {
    var isPlaying: Bool { get }
    func start(type: NoiseType, volume: Float) throws
    func stop()
    func setVolume(_ volume: Float)
}

extension NoiseGenerator: AudioPlayback {}

@MainActor
@Observable
final class AudioViewModel {
    var selectedNoise: NoiseType = .brown {
        didSet { if isPlaying { play() } }
    }
    var volume: Double = 0.7 { didSet { applyAdaptiveVolume() } }
    private(set) var isPlaying = false
    var errorMessage: String?
    var isBreakPhase = false { didSet { applyAdaptiveVolume() } }

    private let generator: any AudioPlayback
    private var resumeAfterInterruption = false
    private var observers: [AnyCancellable] = []
    private var currentFactor: Float { isBreakPhase ? 0.55 : 1.0 }

    init(generator: (any AudioPlayback)? = nil, observeNotifications: Bool = true) {
        self.generator = generator ?? NoiseGenerator()
        guard observeNotifications else { return }
        let center = NotificationCenter.default
        observers.append(center.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] note in
                let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                Task { @MainActor [weak self] in
                    guard let type, let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
                    if interruption == .began { self?.interruptionBegan() }
                    else { self?.interruptionEnded(shouldResume: AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)) }
                }
            })
        observers.append(center.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] note in
                let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                Task { @MainActor [weak self] in
                    if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                        self?.routeDisconnected()
                    }
                }
            })
        observers.append(center.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.audioSystemReset() }
            })
        observers.append(center.publisher(for: .AVAudioEngineConfigurationChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.audioConfigurationChanged() }
            })
    }

    func play() {
        resumeAfterInterruption = false
        errorMessage = nil
        do {
            try generator.start(type: selectedNoise, volume: Float(volume) * currentFactor)
            isPlaying = generator.isPlaying
        } catch {
            generator.stop()
            isPlaying = false
            errorMessage = "Sound could not start. Check your audio connection and tap Retry Sound. Your timer is still available."
        }
    }

    func stop() {
        resumeAfterInterruption = false
        generator.stop()
        isPlaying = false
    }

    func toggle() { isPlaying ? stop() : play() }

    func interruptionBegan() {
        resumeAfterInterruption = resumeAfterInterruption || isPlaying
        generator.stop()
        isPlaying = false
    }

    func interruptionEnded(shouldResume: Bool) {
        let resume = resumeAfterInterruption && shouldResume
        let wasInterrupted = resumeAfterInterruption
        resumeAfterInterruption = false
        if resume { play() }
        else if wasInterrupted {
            errorMessage = "Sound was interrupted. Tap Retry Sound when you are ready."
        }
    }

    func routeDisconnected() {
        let needsNotice = isPlaying || resumeAfterInterruption
        stop()
        if needsNotice { errorMessage = "Your headphones disconnected. Sound is paused. Tap Retry Sound to use the current audio output." }
    }

    func audioSystemReset() {
        let needsNotice = isPlaying || resumeAfterInterruption
        stop()
        if needsNotice { errorMessage = "The audio system restarted. Tap Retry Sound to continue." }
    }

    func audioConfigurationChanged() {
        // A route/format change may stop the engine without an interruption notification.
        guard isPlaying, !generator.isPlaying else { return }
        stop()
        errorMessage = "The audio output changed. Tap Retry Sound to continue."
    }

    private func applyAdaptiveVolume() {
        guard isPlaying else { return }
        generator.setVolume(Float(volume) * currentFactor)
    }
}
