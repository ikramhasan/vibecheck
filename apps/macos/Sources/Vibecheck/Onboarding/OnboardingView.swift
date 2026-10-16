import AppKit
import CompanionCore
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, agents, indicator, machines, finish
}

struct OnboardingView: View {
    static let size = CGSize(width: 920, height: 640)
    private static let sidebarWidth: CGFloat = 400

    @Bindable var settings: AppSettings
    let launchAtLogin: LaunchAtLogin?
    let onFinish: () -> Void
    @State private var step = OnboardingStep.welcome
    @State private var forward = true

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                StepIndicator(step: step)
                    .padding(.top, 52)
                    .padding(.bottom, 26)
                ZStack(alignment: .topLeading) {
                    page
                        .id(step)
                        .transition(.asymmetric(insertion: .offset(x: forward ? 40 : -40).combined(with: .opacity),
                                                removal: .offset(x: forward ? -40 : 40).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                navigation
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 26)
            .frame(width: Self.sidebarWidth)

            OnboardingPreview(settings: settings)
                .padding([.top, .bottom, .trailing], 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowBackdrop().ignoresSafeArea())
        .ignoresSafeArea()
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome:
            WelcomePage()
        case .agents:
            StepPage(title: "Which agents do you use?",
                     subtitle: "vibecheck shows their sessions and plan limits. Agents found on this Mac are already on.") {
                AgentChoices(settings: settings)
            }
        case .indicator:
            StepPage(title: "Pick your orbs",
                     subtitle: "Each session gets an orb that moves while the agent works. The preview updates as you pick.") {
                ScrollView(.vertical) {
                    IndicatorPicker(settings: settings)
                        .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
            }
        case .machines:
            StepPage(title: "Any other machines?",
                     subtitle: "Watch Claude, Codex and pi sessions on Linux machines you reach with ssh. "
                        + "vibecheck only reads there. Key-based login is required. You can skip this.") {
                GlassCard { MachinesList(settings: settings) }
            }
        case .finish:
            FinishPage(launchAtLogin: launchAtLogin)
        }
    }

    private var navigation: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if step != .welcome {
                    Button("Back") { move(by: -1) }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                if step == .finish {
                    Button("Start using vibecheck", action: onFinish)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                } else if step == .machines {
                    Button(settings.remoteHosts.isEmpty ? "Skip" : "Continue") { move(by: 1) }
                        .buttonStyle(.glassProminent)
                } else {
                    Button(step == .welcome ? "Get Started" : "Continue") { move(by: 1) }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
    }

    private func move(by offset: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + offset) else { return }
        forward = offset > 0
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.86)) {
            step = next
        }
    }
}

private struct StepIndicator: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                    .frame(width: item == step ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }
}

private struct StepPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 22)
            content
        }
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .padding(.bottom, 18)
                .accessibilityHidden(true)
            StepPage(title: "Welcome to vibecheck",
                     subtitle: "Your coding agents, on the edge of your screen. A quick setup and you're ready.") {
                GlassEffectContainer(spacing: 10) {
                    VStack(alignment: .leading, spacing: 14) {
                        Feature(symbol: "circle.dotted.circle", title: "Every session at a glance",
                                text: "See which agents are working, done, or stuck, across all your projects.")
                        Feature(symbol: "bell.badge", title: "Know when you're needed",
                                text: "Questions and permission prompts come forward so agents never wait on you.")
                        Feature(symbol: "gauge.with.dots.needle.33percent", title: "Plan limits in reach",
                                text: "Session and weekly usage, read with each agent's own sign-in.")
                    }
                }
            }
        }
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .glassEffect(.regular, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AgentChoices: View {
    @Bindable var settings: AppSettings

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                ForEach(OnboardingAgent.all) { agent in
                    AgentChoice(agent: agent, selected: settings.agents.observes(agent)) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            settings.agents.observe(agent, !settings.agents.observes(agent))
                        }
                    }
                }
            }
        }
    }
}

private struct AgentChoice: View {
    let agent: OnboardingAgent
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AgentGlyph(agentID: agent.id, size: 22)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(agent.name)
                            .font(.system(size: 13, weight: .semibold))
                        if agent.isInstalled {
                            Text("On this Mac")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                    Text(agent.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("\(agent.name), \(agent.detail)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct FinishPage: View {
    let launchAtLogin: LaunchAtLogin?

    var body: some View {
        StepPage(title: "You're all set",
                 subtitle: "vibecheck tucks into the right edge of your screen. Move the pointer there to open the "
                    + "panel, and find everything from this setup under the gear.") {
            VStack(alignment: .leading, spacing: 14) {
                Feature(symbol: "rectangle.righthalf.inset.filled.arrow.right", title: "Hover the right edge",
                        text: "The tab shows one orb per session. Hover it to see the details.")
                Feature(symbol: "hand.tap", title: "Click a session",
                        text: "Jumps to the terminal or app the agent is running in.")
                if let launchAtLogin {
                    GlassCard { LaunchAtLoginRow(launchAtLogin: launchAtLogin) }
                        .padding(.top, 8)
                }
            }
        }
    }
}

private struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
