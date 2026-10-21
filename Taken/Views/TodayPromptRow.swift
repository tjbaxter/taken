import SwiftUI

/// Today's one quiet row under the progress line (SPEC 3.1, the 1.1 retention build): the evening nudge offered once,
/// the honest repair for yesterday, or the widget invite after the first All taken. One at a time, out of the stack's
/// way, in the look's own tokens.
struct TodayPromptRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let prompt: TodayPrompt

    init(prompt: TodayPrompt) {
        self.prompt = prompt
    }

    var body: some View {
        switch prompt {
        case .nudgeOffer(let minutes): nudgeOffer(minutes: minutes)
        case .repair(let day): repair(day)
        case .widgetInvite: widgetInvite
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
    }

    // MARK: Nudge offer

    private func nudgeOffer(minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "bell")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.signalInk)
                    .accessibilityHidden(true)
                Text(RetentionCopy.nudgeOffer(minutes: minutes))
                    .font(.sans(15, .sansMedium, relativeTo: .subheadline))
                    .foregroundStyle(theme.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Button {
                    model.answerNudgeOffer(turnOn: false)
                } label: {
                    Text(RetentionCopy.notNow)
                        .font(.sans(15, .sansMedium, relativeTo: .subheadline))
                        .foregroundStyle(theme.fgMuted)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                Button {
                    model.answerNudgeOffer(turnOn: true)
                } label: {
                    Text(RetentionCopy.turnOn)
                        .font(.sans(15, .sansSemibold, relativeTo: .subheadline))
                        .foregroundStyle(theme.signalInk)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(theme.signalWash, in: Capsule())
                        .overlay(Capsule().strokeBorder(theme.signalEdge, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Taken nudges you at \(Fmt.minutes(minutes)) when something is pending.")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 12)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgRaised, in: shape)
        .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    // MARK: Repair

    private func repair(_ day: DayKey) -> some View {
        Button {
            model.sheet = .day(day)
        } label: {
            HStack(spacing: 6) {
                Text(RetentionCopy.repairQuestion)
                    .foregroundStyle(theme.fg)
                Text(RetentionCopy.repairAction)
                    .foregroundStyle(theme.signalInk)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.fgSubtle)
            }
            .font(.sans(15, .sansMedium, relativeTo: .subheadline))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(theme.bgRaised, in: shape)
            .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RetentionCopy.repair)
        .accessibilityHint("Opens \(Fmt.longDay(day)).")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Widget invite

    private var widgetInvite: some View {
        HStack(spacing: 0) {
            Button {
                model.closeWidgetInvite(openHelp: true)
            } label: {
                Text(RetentionCopy.widgetInvite)
                    .font(.sans(15, .sansMedium, relativeTo: .subheadline))
                    .foregroundStyle(theme.fg)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHint("Shows how to add it.")
            Button {
                model.closeWidgetInvite(openHelp: false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.fgSubtle)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Close")
            .padding(.trailing, 4)
        }
        .background(theme.bgRaised, in: shape)
        .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .onAppear { model.noteWidgetInviteShown() }
    }
}

/// How to add the Taken widget to the Lock Screen, from the invite: the widget as it will look with this stack, and
/// Apple's three steps (https://support.apple.com/en-us/118610).
struct WidgetHelpSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: RetentionCopy.widgetTitle, subtitle: RetentionCopy.widgetSubtitle) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RectangularStackView(snapshot: WidgetSnapshot(state: model.state, now: model.now))
                        .foregroundStyle(theme.lockScreenInk)
                        .tint(theme.lockScreenInk)
                        .padding(.horizontal, 6)
                        .frame(width: 172, height: 76)
                        .background(theme.lockScreenPlate, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(theme.bgInset, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                        .accessibilityHidden(true)
                    Card {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(RetentionCopy.widgetSteps.enumerated()), id: \.offset) { index, step in
                                if index > 0 { RowDivider() }
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.mono(15, .monoMedium, relativeTo: .body))
                                        .foregroundStyle(theme.signalInk)
                                    Text(step)
                                        .font(.sans(16, .sans, relativeTo: .body))
                                        .foregroundStyle(theme.fg)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .padding(.top, 16)
                    Text(RetentionCopy.widgetFootnote)
                        .font(.sans(14, .sans, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }
}
