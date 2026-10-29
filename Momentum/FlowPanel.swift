import SwiftUI

/// Derived words and symbols, shared by the menu-bar label and the popover panel.
struct FlowPresentation {
    let phase: FlowPhase?
    let isPaused: Bool
    let minutes: Int?
    let breakHint: String?

    init(_ flow: FlowService, preferences: FlowPreferences) {
        phase = flow.phase
        isPaused = flow.isPaused
        minutes = flow.remainingMinutes
        breakHint = preferences.breaksEnabled ? "Then a \(preferences.breakDuration.minutes)-minute break." : nil
    }

    /// The SF Symbol before the countdown in the menu bar.
    var menuSymbol: String? {
        switch phase {
        case .session: isPaused ? "pause.fill" : "timer"
        case .break: "figure.walk"
        case nil: nil
        }
    }

    var countdown: String? { minutes.map { "\($0)m" } }

    /// The state in words, so it never rests on a symbol alone.
    var title: String {
        switch phase {
        case .session: isPaused ? "Flow paused" : "Flow session"
        case .break: "Break"
        case nil: "Flow"
        }
    }

    /// "24 minutes left": the countdown's VoiceOver value. It changes once a minute, never every second.
    var minutesLeft: String? {
        guard phase != nil, let minutes else { return nil }
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes") left"
    }

    /// "Flow session, 24 minutes left": for the menu-bar label and its tooltip.
    var spokenStatus: String? { minutesLeft.map { "\(title), \($0)" } }

    func caption(endingAt end: Date) -> String {
        let time = end.formatted(date: .omitted, time: .shortened)
        switch phase {
        case .session: return isPaused ? "Paused" : "Flow session · ends at \(time)"
        case .break: return "Break · ends at \(time)"
        case nil: return ""
        }
    }

    /// `24:13`, or `1:29:59` from one hour. Rounds up, so a new 25-minute session reads 25:00.
    static func clock(_ seconds: Double) -> String {
        let total = Int(ceil(max(0, seconds)))
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

/// The Flow panel at the top of the menu-bar popover.
struct FlowPanel: View {
    let flow: FlowService
    let configStore: ConfigStore

    var body: some View {
        let presentation = FlowPresentation(flow, preferences: configStore.config.flow)
        Panel {
            Label("Flow", systemImage: "timer")
                .font(.headline)
            if flow.isActive {
                countdown(presentation)
                controls
            } else {
                ready(presentation)
            }
        }
    }

    @ViewBuilder private func ready(_ presentation: FlowPresentation) -> some View {
        Picker("Duration", selection: Binding(
            get: { configStore.config.flow.duration },
            set: { flow.selectDuration($0) }
        )) {
            ForEach(FlowDuration.allCases, id: \.self) { duration in
                Text(duration.title).tag(duration)
            }
        }
        .pickerStyle(.menu)
        if let hint = presentation.breakHint {
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Button {
            flow.start()
        } label: {
            Text("Start Flow")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func countdown(_ presentation: FlowPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            // Seconds tick only while the popover is open; the menu bar shows whole minutes (FL-12).
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                // On the Text itself: around the TimelineView, VoiceOver loses the value.
                Text(FlowPresentation.clock(flow.liveRemaining() ?? 0))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityLabel(presentation.title)
                    .accessibilityValue(presentation.minutesLeft ?? "")
            }
            Text(presentation.caption(endingAt: .now.addingTimeInterval(flow.liveRemaining() ?? 0)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: Space.sm) {
            switch flow.phase {
            case .session:
                Button {
                    flow.isPaused ? flow.resume() : flow.pause()
                } label: {
                    Text(flow.isPaused ? "Resume" : "Pause")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    flow.endSession()
                } label: {
                    Text("End Flow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            case .break:
                Button {
                    flow.skipBreak()
                } label: {
                    Text("Skip Break")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            case nil:
                EmptyView()
            }
        }
        .controlSize(.large)
    }
}
