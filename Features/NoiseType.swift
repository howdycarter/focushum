import Foundation

enum NoiseType: String, CaseIterable, Codable, Identifiable {
    case brown = "Brown"
    case pink = "Pink"
    case white = "White"
    case rain = "Rain"
    case cafe = "Cafe"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .brown: return "waveform"
        case .pink: return "waveform.path"
        case .white: return "waveform.path.ecg"
        case .rain: return "cloud.rain.fill"
        case .cafe: return "cup.and.saucer.fill"
        }
    }

    var tagline: String {
        switch self {
        case .brown: return "Deep rumble for focus"
        case .pink: return "Natural, balanced noise"
        case .white: return "Pure static mask"
        case .rain: return "Gentle rainfall"
        case .cafe: return "Coffee shop buzz"
        }
    }

    var isPremium: Bool {
        switch self {
        case .brown, .white: return false
        case .pink, .rain, .cafe: return true
        }
    }

    var accentHex: String {
        switch self {
        case .brown: return "#8B5E3C"
        case .pink: return "#C47AB3"
        case .white: return "#A0A0A0"
        case .rain: return "#5B9BD5"
        case .cafe: return "#C8A96E"
        }
    }
}
