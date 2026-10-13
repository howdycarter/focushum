import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \TimerSession.startDate, order: .reverse) private var sessions: [TimerSession]

    private var completedWork: [TimerSession] {
        sessions.filter { $0.completed && $0.sessionKindRaw == SessionKind.work.rawValue }
    }

    private var currentStreak: Int {
        var streak = 0
        let calendar = Calendar.current
        var checkDate = calendar.startOfDay(for: .now)
        let dayStrings = Set(completedWork.map { $0.dayString })
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        while true {
            let key = fmt.string(from: checkDate)
            if dayStrings.contains(key) {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else { break }
        }
        return streak
    }

    private var totalFocusMinutes: Int {
        Int(completedWork.reduce(0) { $0 + $1.elapsedSeconds } / 60)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        statsLayout {
                            FHStatCard(value: "\(currentStreak)", label: "Day Streak", icon: "flame.fill")
                            FHStatCard(value: "\(completedWork.count)", label: "Sessions", icon: "checkmark.circle.fill")
                            FHStatCard(value: "\(totalFocusMinutes)m", label: "Focus Time", icon: "timer")
                        }
                        .padding(.horizontal, 20)

                        FHWeekBarChart(sessions: completedWork)
                            .padding(.horizontal, 20)

                        if sessions.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.white.opacity(0.2))
                                Text("No sessions yet")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .padding(.top, 40)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(sessions.prefix(30)) { session in
                                    FHSessionRow(session: session)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "#8B5E3C") ?? .orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var statsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
    }
}

struct FHStatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color(hex: "#8B5E3C") ?? .orange)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct FHWeekBarChart: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let sessions: [TimerSession]

    private struct DayData: Identifiable {
        let id = UUID()
        let label: String
        let minutes: Int
    }

    private var weekData: [DayData] {
        let calendar = Calendar.current
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let dayFormatter = DateFormatter(); dayFormatter.dateFormat = "EEE"
        return (0..<7).reversed().map { offset -> DayData in
            let date = calendar.date(byAdding: .day, value: -offset, to: .now)!
            let key = formatter.string(from: date)
            let total = sessions.filter { $0.dayString == key }.reduce(0) { $0 + $1.elapsedSeconds }
            return DayData(label: dayFormatter.string(from: date), minutes: Int(total / 60))
        }
    }

    private var maxMinutes: Int { max(weekData.map(\.minutes).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(weekData) { day in
                        Text("\(day.label): \(day.minutes) minutes")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(weekData) { day in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(day.minutes > 0 ? (Color(hex: "#8B5E3C") ?? .orange) : Color.white.opacity(0.08))
                                .frame(height: CGFloat(day.minutes) / CGFloat(maxMinutes) * 80 + 4)
                            Text(day.label).font(.caption2).foregroundStyle(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.label), \(day.minutes) focus minutes")
                    }
                }
                .frame(minHeight: 110, alignment: .bottom)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct FHSessionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: TimerSession
    var body: some View {
        rowLayout {
            Image(systemName: session.completed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(session.completed ? (Color(hex: "#8B5E3C") ?? .orange) : .white.opacity(0.3))
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(session.sessionKind.label) · \(session.noiseType.rawValue)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.white.opacity(0.35))
            }
            .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Text("\(Int(session.elapsedSeconds / 60))m")
                .font(.system(.subheadline, design: .monospaced, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                .fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
    }
}
