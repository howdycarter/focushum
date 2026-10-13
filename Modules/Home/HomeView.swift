//
//  HomeView.swift
//  FocusHum
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.container) private var container
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasPremium = false
    @State private var showUpgrade = false
    @Environment(\.scenePhase) private var scenePhase
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

            GeometryReader { geometry in
                ScrollView {
                    focusContent
                        .frame(maxWidth: 680)
                        .frame(minHeight: geometry.size.height)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHistory)  { HistoryView() }
        .sheet(isPresented: $showSettings) { FocusSettingsView(pomodoroVM: pomodoroVM) }
        .sheet(isPresented: $showUpgrade) { PaywallView() }
        .onAppear {
            pomodoroVM.setModelContext(modelContext)
            if !container.config.featureFlags.paywall {
                hasPremium = true
                pomodoroVM.hasPremiumAccess = true
            }
        }
        .task { await container.purchasesService.refreshSubscriptionStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .subscriptionDidChange)) { notification in
            hasPremium = PremiumAccess.resolve(current: hasPremium, notification: notification,
                                               paywallEnabled: container.config.featureFlags.paywall)
            pomodoroVM.hasPremiumAccess = hasPremium
            if !hasPremium && audioVM.selectedNoise.isPremium { audioVM.selectedNoise = .brown }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { pomodoroVM.refresh() }
            else { pomodoroVM.checkpoint() }
        }
        .alert("Sound", isPresented: Binding(get: { audioVM.errorMessage != nil }, set: { if !$0 { audioVM.errorMessage = nil } })) {
            Button("Retry Sound") { audioVM.play() }
            Button("Keep Silent", role: .cancel) { audioVM.errorMessage = nil }
        } message: { Text(audioVM.errorMessage ?? "") }
        .alert("Session History", isPresented: Binding(get: { pomodoroVM.errorMessage != nil }, set: { if !$0 { pomodoroVM.errorMessage = nil } })) {
            Button("Retry") { pomodoroVM.retryHistorySave() }
            Button("OK", role: .cancel) { pomodoroVM.errorMessage = nil }
        } message: { Text(pomodoroVM.errorMessage ?? "") }
        .onChange(of: pomodoroVM.phase) { _, newPhase in
            audioVM.isBreakPhase = newPhase.isBreak
        }
    }

    private var focusContent: some View {
        VStack(spacing: 0) {
            topBar
            if let recoveryMessage = pomodoroVM.recoveryMessage {
                Text(recoveryMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            Spacer(minLength: 24)

            Text(pomodoroVM.phase.label.uppercased())
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut, value: pomodoroVM.phase)

            FHTimerRingView(
                progress: pomodoroVM.progress,
                timeString: pomodoroVM.timeString,
                accentColor: ringColor
            )
            .padding(.vertical, 24)

            FHSessionDotsView(
                completed: pomodoroVM.completedSessions,
                total: pomodoroVM.sessionGoal
            )
            .padding(.bottom, 32)

            controlRow
            Spacer(minLength: 32)
            noiseSection.padding(.bottom, 48)
        }
        .padding(.horizontal, 24)
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize { appTitle }
            HStack {
                historyButton
                Spacer()
                if !dynamicTypeSize.isAccessibilitySize {
                    appTitle
                    Spacer()
                }
                settingsButton
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var appTitle: some View {
        Text("FocusHum")
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.white)
    }

    private var historyButton: some View {
        Button { if hasPremium { showHistory = true } else { showUpgrade = true } } label: {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Session history")
    }

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Timer settings")
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
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Skip current session")
            .disabled(pomodoroVM.phase == .idle)

            Button {
                if pomodoroVM.isRunning {
                    pomodoroVM.pause()
                    audioVM.stop()
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

            .accessibilityLabel(pomodoroVM.isRunning ? "Pause timer" : "Start timer")

            Button {
                pomodoroVM.reset()
                audioVM.stop()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Reset timer")
        }
    }

    private var noiseSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                Slider(value: $audioVM.volume, in: 0...1)
                    .accessibilityLabel("Sound volume")
                    .tint(Color(hex: "#C9976B") ?? .orange)
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
                            isPremiumLocked: noise.isPremium && !hasPremium
                        ) {
                            guard !noise.isPremium || hasPremium else { showUpgrade = true; return }
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
        case .idle, .work: return Color(hex: "#C9976B") ?? .orange
        case .shortBreak, .longBreak: return Color(hex: "#5B9BD5") ?? .blue
        }
    }

    private var ringColor: Color {
        pomodoroVM.phase.isBreak ? (Color(hex: "#5B9BD5") ?? .blue) : (Color(hex: "#C9976B") ?? .orange)
    }
}

struct FHTimerRingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var phoneFontSize = 68.0
    @ScaledMetric(relativeTo: .largeTitle) private var tabletFontSize = 92.0
    @ScaledMetric(relativeTo: .largeTitle) private var phoneRingSize = 270.0
    @ScaledMetric(relativeTo: .largeTitle) private var tabletRingSize = 400.0
    let progress: Double
    let timeString: String
    let accentColor: Color

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 16) {
                    ring.frame(width: 120, height: 120)
                    Text(timeString)
                        .font(.system(size: horizontalSizeClass == .regular ? tabletFontSize : phoneFontSize,
                                      weight: .regular, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                .frame(maxWidth: .infinity)
            } else {
                ring.overlay {
                    Text(timeString)
                        .font(.system(size: horizontalSizeClass == .regular ? tabletFontSize : phoneFontSize,
                                      weight: .thin, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white)
                        .padding(24)
                }
                .frame(maxWidth: horizontalSizeClass == .regular ? tabletRingSize : phoneRingSize)
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue(timeString)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

struct FHSessionDotsView: View {
    let completed: Int
    let total: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < completed % total ? (Color(hex: "#C9976B") ?? .orange) : Color.white.opacity(0.18))
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
                    .font(.caption)
                Text(noise.rawValue)
                    .font(.subheadline.weight(.medium))
            }
            .fixedSize()
            .foregroundStyle(isSelected ? .black : .white.opacity(isPremiumLocked ? 0.4 : 0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(isSelected ? (Color(hex: "#C9976B") ?? .orange) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(noise.rawValue)
        .accessibilityHint(isPremiumLocked ? "Requires FocusHum Pro" : "Select focus sound")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
