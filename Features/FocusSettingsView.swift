import SwiftUI

struct FocusSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var pomodoroVM: PomodoroViewModel

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Timer Durations") {
                        FHStepper(label: "Focus", value: $pomodoroVM.workMinutes, range: 5...90, step: 5)
                        FHStepper(label: "Short Break", value: $pomodoroVM.shortBreakMinutes, range: 1...30, step: 1)
                        FHStepper(label: "Long Break", value: $pomodoroVM.longBreakMinutes, range: 5...60, step: 5)
                        FHStepper(label: "Sessions before Long Break", value: $pomodoroVM.sessionsBeforeLongBreak, range: 2...8, step: 1)
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section("Behavior") {
                        Toggle("Auto-start Breaks", isOn: $pomodoroVM.autoStartBreaks)
                            .tint(Color(hex: "#8B5E3C") ?? .orange)
                        Toggle("Haptic Feedback", isOn: $pomodoroVM.hapticsEnabled)
                            .tint(Color(hex: "#8B5E3C") ?? .orange)
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Timer Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "#8B5E3C") ?? .orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct FHStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.white)
            Spacer()
            Stepper("\(value) min", value: $value, in: range, step: step)
                .foregroundStyle(.white)
                .tint(Color(hex: "#8B5E3C") ?? .orange)
        }
    }
}
