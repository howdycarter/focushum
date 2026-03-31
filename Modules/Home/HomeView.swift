//
//  HomeView.swift
//  FocusHum
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var pomodoroVM = PomodoroViewModel()
    @State private var audioVM    = AudioViewModel()

    @State private var showHistory  = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [backgroundAccent.opacity(0.25), Color.black],
                center: .top,
                startRadius: 0,
                endRadius: 600
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.2), value: pomodoroVM.phase)

            VStack(spacing: 0) {
                topBar
                Spacer()

                Text(pomodoroVM.phase.label.uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(3)
                    .animation(.easeInOut, value: pomodoroVM.phase)

                FHTimerRingView(
                    progress: pomodoroVM.progress,
                    timeString: pomodoroVM.timeString,
                    accentColor: ringColor
                )
                .padding(.vertical, 24)

                FHSessionDotsView(
                    completed: pomodoroVM.completedSessions,
                    total: pomodoroVM.sessionsBeforeLongBreak
                )
                .padding(.bottom, 32)

                controlRow
                Spacer()
                noiseSection.padding(.bottom, 48)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHistory)  { HistoryView() }
        .sheet(isPresented: $showSettings) { FocusSettingsView(pomodoroVM: pomodoroVM) }
        .onAppear { pomodoroVM.setModelContext(modelContext) }
        .onChange(of: pomodoroVM.phase) { _, newPhase in
            audioVM.isBreakPhase = newPhase.isBreak
        }
    }

    private var topBar: some View {
        HStack {
            Button { showHistory = true } label: {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Text("FocusHum")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var controlRow: some View {
        HStack(spacing: 40) {
            Button {
                pomodoroVM.skip()
                if audioVM.isPlaying { audioVM.play() }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Button {
                if pomodoroVM.isRunning {
                    pomodoroVM.pause()
                } else {
                    pomodoroVM.startOrResume(noiseType: audioVM.selectedNoise)
                    if !audioVM.isPlaying { audioVM.play() }
                }
            } label: {
                Image(systemName: pomodoroVM.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.black)
                    .frame(width: 72, height: 72)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .white.opacity(0.15), radius: 20)
            }

            Button {
                pomodoroVM.reset()
                audioVM.stop()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var noiseSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                Slider(value: $audioVM.volume, in: 0...1)
                    .tint(Color(hex: "#8B5E3C") ?? .orange)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(NoiseType.allCases) { noise in
                        FHNoisePill(
                            noise: noise,
                            isSelected: audioVM.selectedNoise == noise,
                            isPremiumLocked: false
                        ) {
                            audioVM.selectedNoise = noise
                            if !audioVM.isPlaying && pomodoroVM.isRunning { audioVM.play() }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var backgroundAccent: Color {
        switch pomodoroVM.phase {
        case .idle, .work: return Color(hex: "#8B5E3C") ?? .orange
        case .shortBreak, .longBreak: return Color(hex: "#5B9BD5") ?? .blue
        }
    }

    private var ringColor: Color {
        pomodoroVM.phase.isBreak ? (Color(hex: "#5B9BD5") ?? .blue) : (Color(hex: "#8B5E3C") ?? .orange)
    }
}

struct FHTimerRingView: View {
    let progress: Double
    let timeString: String
    let accentColor: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            Text(timeString)
                .font(.system(size: 68, weight: .thin, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(width: 270, height: 270)
    }
}

struct FHSessionDotsView: View {
    let completed: Int
    let total: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < completed % total ? (Color(hex: "#8B5E3C") ?? .orange) : Color.white.opacity(0.18))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut, value: completed)
            }
        }
    }
}

struct FHNoisePill: View {
    let noise: NoiseType
    let isSelected: Bool
    let isPremiumLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isPremiumLocked ? "lock.fill" : noise.icon)
                    .font(.system(size: 13))
                Text(noise.rawValue)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(isSelected ? .black : .white.opacity(isPremiumLocked ? 0.4 : 0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(isSelected ? (Color(hex: "#8B5E3C") ?? .orange) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
