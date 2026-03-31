import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
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
                        HStack(spacing: 16) {
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
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct FHWeekBarChart: View {
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
            Text("This Week").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(weekData) { day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day.minutes > 0 ? (Color(hex: "#8B5E3C") ?? .orange) : Color.white.opacity(0.08))
                            .frame(height: CGFloat(day.minutes) / CGFloat(maxMinutes) * 80 + 4)
                        Text(day.label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct FHSessionRow: View {
    let session: TimerSession
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: session.completed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(session.completed ? (Color(hex: "#8B5E3C") ?? .orange) : .white.opacity(0.3))
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(session.sessionKind.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text("·").foregroundStyle(.white.opacity(0.3))
                    Text(session.noiseType.rawValue).font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                }
                Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
            Text("\(Int(session.elapsedSeconds / 60))m")
                .font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
