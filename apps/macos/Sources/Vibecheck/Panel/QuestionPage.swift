import AppKit
import CompanionCore
import SwiftUI

@MainActor
enum QuestionMetrics {
    static let pagePadding: CGFloat = 10
    static let cardPadding: CGFloat = 12
    static let cardSpacing: CGFloat = 8
    static let cardHeader: CGFloat = 22
    static let headerGap: CGFloat = 10
    static let chipHeight: CGFloat = 18
    static let chipGap: CGFloat = 6
    static let optionsGap: CGFloat = 8
    static let optionSpacing: CGFloat = 5
    static let optionPadding: CGFloat = 8
    static let optionTextGap: CGFloat = 2
    static let captionHeight: CGFloat = 14
    static let questionGap: CGFloat = 14
    static let footerGap: CGFloat = 12
    static let footer: CGFloat = 24
    static let maxHeight: CGFloat = 620

    static let questionFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let labelFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let descriptionFont = NSFont.systemFont(ofSize: 11, weight: .regular)

    static var textWidth: CGFloat { PanelMetrics.expandedWidth - 2 * (pagePadding + cardPadding) }
    static var optionTextWidth: CGFloat { textWidth - 2 * optionPadding }

    static func questions(of session: AgentSession) -> [AgentSession.Question] {
        let questions = session.attention?.questions ?? []
        return questions.isEmpty ? [.init(question: StatusPresentation.headline(session))] : questions
    }

    static func cardHeight(_ session: AgentSession) -> CGFloat {
        let body = questions(of: session).map(questionHeight).reduce(0, +)
            + CGFloat(max(questions(of: session).count - 1, 0)) * questionGap
        return cardPadding * 2 + cardHeader + headerGap + body + footerGap + footer
    }

    static func questionHeight(_ question: AgentSession.Question) -> CGFloat {
        var height = textHeight(question.question, font: questionFont, width: textWidth)
        if question.header != nil { height += chipHeight + chipGap }
        if question.multiSelect { height += captionHeight + chipGap }
        if !question.options.isEmpty {
            height += optionsGap + CGFloat(question.options.count - 1) * optionSpacing
            height += question.options.map(optionHeight).reduce(0, +)
        }
        return height
    }

    static func optionHeight(_ option: AgentSession.Question.Option) -> CGFloat {
        var height = optionPadding * 2 + textHeight(option.label, font: labelFont, width: optionTextWidth)
        if let description = option.description {
            height += optionTextGap + textHeight(description, font: descriptionFont, width: optionTextWidth)
        }
        return height
    }

    static func contentHeight(_ sessions: [AgentSession]) -> CGFloat {
        sessions.map(cardHeight).reduce(0, +) + CGFloat(max(sessions.count - 1, 0)) * cardSpacing
    }

    private static let chrome = PanelMetrics.flare * 2 + PanelMetrics.headerHeight + pagePadding + 6

    static func pageHeight(_ sessions: [AgentSession]) -> CGFloat {
        min(chrome + contentHeight(sessions), maxHeight)
    }

    static func overflows(_ sessions: [AgentSession]) -> Bool {
        chrome + contentHeight(sessions) > maxHeight
    }

    private static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        return ceil(rect.height) + 1
    }
}

struct QuestionPage: View {
    let sessions: [AgentSession]
    let isShown: Bool
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if QuestionMetrics.overflows(sessions) {
                ScrollView(.vertical) { cards }
                    .scrollIndicators(.never)
            } else {
                cards
            }
            Spacer(minLength: 0)
        }
        .padding(.top, PanelMetrics.flare)
        .padding(.bottom, PanelMetrics.flare + 6)
        .opacity(isShown ? 1 : 0)
        .animation(isShown ? .easeOut(duration: 0.25).delay(0.1) : .easeOut(duration: 0.1), value: isShown)
    }

    private var cards: some View {
        VStack(spacing: QuestionMetrics.cardSpacing) {
            ForEach(sessions) { session in
                QuestionCard(session: session)
                    .frame(height: QuestionMetrics.cardHeight(session), alignment: .top)
            }
        }
        .padding(.horizontal, QuestionMetrics.pagePadding)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Needs you")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            if sessions.count > 1 {
                Text("\(sessions.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
            }
            Spacer()
            Button("Show all", action: onShowAll)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .help("Show every agent session")
        }
        .frame(height: PanelMetrics.headerHeight)
        .padding(.horizontal, 16)
    }
}

private struct QuestionCard: View {
    let session: AgentSession
    @State private var hovering = false
    @State private var target: JumpTarget?

    var body: some View {
        let project = ProjectIcons.shared.project(for: session.cwd)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProjectBadge(project: project, size: 18)
                Text(project.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 6)
                AgentGlyph(agentID: session.agent.id, size: 12)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(ElapsedFormat.short(since: session.statusSince ?? session.updatedAt, now: context.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .frame(height: QuestionMetrics.cardHeader)
            .padding(.bottom, QuestionMetrics.headerGap)

            VStack(alignment: .leading, spacing: QuestionMetrics.questionGap) {
                ForEach(Array(QuestionMetrics.questions(of: session).enumerated()), id: \.offset) { _, question in
                    QuestionBlock(question: question)
                }
            }

            Spacer(minLength: QuestionMetrics.footerGap)

            HStack(spacing: 6) {
                Text(StatusPresentation.task(session))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Text("Answer in \(target?.appName ?? session.agent.name)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(hovering ? 1 : 0.8))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.orange.opacity(hovering ? 1 : 0.8))
            }
            .frame(height: QuestionMetrics.footer)
        }
        .padding(QuestionMetrics.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(hovering ? 0.1 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { target = SessionJumper.target(for: session) }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture { SessionJumper.jump(to: session) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the app this session is running in to answer")
        .accessibilityAction { SessionJumper.jump(to: session) }
    }
}

private struct QuestionBlock: View {
    let question: AgentSession.Question

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header = question.header {
                Text(header.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 6)
                    .frame(height: QuestionMetrics.chipHeight)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
                    .padding(.bottom, QuestionMetrics.chipGap)
            }
            Text(question.question)
                .font(Font(QuestionMetrics.questionFont))
                .foregroundStyle(Color(red: 1, green: 0.88, blue: 0.7))
                .fixedSize(horizontal: false, vertical: true)
            if question.multiSelect {
                Text("Choose one or more")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(height: QuestionMetrics.captionHeight)
                    .padding(.top, QuestionMetrics.chipGap)
            }
            if !question.options.isEmpty {
                VStack(alignment: .leading, spacing: QuestionMetrics.optionSpacing) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                        OptionRow(option: option)
                    }
                }
                .padding(.top, QuestionMetrics.optionsGap)
            }
        }
    }
}

private struct OptionRow: View {
    let option: AgentSession.Question.Option

    var body: some View {
        VStack(alignment: .leading, spacing: QuestionMetrics.optionTextGap) {
            Text(option.label)
                .font(Font(QuestionMetrics.labelFont))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            if let description = option.description {
                Text(description)
                    .font(Font(QuestionMetrics.descriptionFont))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(QuestionMetrics.optionPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}
