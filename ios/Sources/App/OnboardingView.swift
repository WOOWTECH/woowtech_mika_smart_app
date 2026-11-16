#if os(iOS)
import SwiftUI

extension View {
    /// Root integration (ContentView): Android MainActivity checks once, when
    /// the App opens, whether to start the first-launch flow; the flow covers
    /// the chat until 下一步 or 稍後再說.
    @MainActor func firstLaunchOnboarding(session: ChatSession, languages: AppLanguageStore, accent: Color) -> some View {
        modifier(FirstLaunchOnboarding(session: session, languages: languages, accent: accent))
    }
}

@MainActor
private struct FirstLaunchOnboarding: ViewModifier {
    let session: ChatSession
    let languages: AppLanguageStore
    let accent: Color
    @State private var checked = false
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !checked else { return }
                checked = true
                guard startsNow else { return }
                // The welcome page is the first screen, as on Android, rather
                // than a cover sliding up over the chat.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { presented = true }
            }
            .fullScreenCover(isPresented: $presented) {
                // 稍後再說 finishes nothing, so the next launch without a main
                // model starts the flow again, as on Android.
                OnboardingFlowView(session: session, languages: languages, finish: finish,
                                   later: { presented = false })
                    .tint(accent)
            }
    }

    /// A model setting that could not be read is not "no model", so an
    /// unreadable one starts nothing.
    private var startsNow: Bool {
        guard !Onboarding.skippedForUITests, let state = OnboardingState.application,
              session.settingsError == nil else { return false }
        return Onboarding.starts(hasMainModel: session.savedSettings != nil, modelSetupDone: state.modelSetupDone)
    }

    private func finish() {
        OnboardingState.application?.markModelSetupDone()
        presented = false
    }
}

/// Android's store-build onboarding: 歡迎, then 設定模型 (the model page in
/// its onboarding mode). Back on the model page returns to the welcome page.
@MainActor
private struct OnboardingFlowView: View {
    let session: ChatSession
    let languages: AppLanguageStore
    let finish: () -> Void
    let later: () -> Void
    @State private var settingUpModel = false

    var body: some View {
        NavigationStack {
            OnboardingWelcomeView(languages: languages, start: { settingUpModel = true }, later: later)
                .navigationDestination(isPresented: $settingUpModel) {
                    MikaModelSettingsDetailView(session: session, languages: languages, onboardingNext: finish)
                        // Android's top bar there has the back arrow only.
                        .toolbarRole(.editor)
                }
        }
    }
}

/// Android WelcomeScreen, store build: the logo, who the assistant is, what
/// it does, the note about the model service, the first of two dots and
/// 開始設定, with 稍後再說 below it.
@MainActor
private struct OnboardingWelcomeView: View {
    @ObservedObject var languages: AppLanguageStore
    let start: () -> Void
    let later: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }

    private struct Feature: Identifiable {
        let id: String
        let icon: MikaSettingsIcon
        let title: AppText
        let detail: AppText
    }

    /// Android WelcomeCopy.FEATURES.
    private static let features = [
        Feature(id: "chat", icon: .message, title: .welcomeChat, detail: .welcomeChatBody),
        Feature(id: "voice", icon: .mic, title: .welcomeVoice, detail: .welcomeVoiceBody),
        Feature(id: "web", icon: .globe, title: .welcomeWeb, detail: .welcomeWebBody),
        Feature(id: "memory", icon: .spark, title: .welcomeMemory, detail: .welcomeMemoryBody),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        ForEach(Self.features) { feature in
                            if feature.id != Self.features.first?.id { Divider() }
                            featureRow(feature)
                        }
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(palette.page)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            Image("AboutBrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.16), radius: 12, y: 6)
                .accessibilityHidden(true)
            Text(verbatim: localizer.text(.welcomeTitle))
                .font(.title.bold()).foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("welcome.title")
            Text(verbatim: localizer.text(.welcomeLead))
                .font(.subheadline).foregroundStyle(palette.secondary)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .accessibilityIdentifier("welcome.lead")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40).padding(.horizontal, 8).padding(.bottom, 8)
    }

    /// Android Feature: the icon tile, the name and one line on what it does.
    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            MikaSettingsIconTile(icon: feature.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: localizer.text(feature.title))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(palette.ink)
                Text(verbatim: localizer.text(feature.detail))
                    .font(.footnote).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcome.feature." + feature.id)
    }

    /// Stays at the bottom while the page scrolls, as on Android.
    private var footer: some View {
        VStack(spacing: 0) {
            OnboardingDots(current: 0)
                .padding(.top, 4)
            Text(verbatim: localizer.text(.welcomeNote))
                .font(.caption).foregroundStyle(palette.hint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
                .accessibilityIdentifier("welcome.note")
            Button(action: start) {
                Text(verbatim: localizer.text(.welcomeStart))
            }
            .buttonStyle(OnboardingButtonStyle())
            .accessibilityIdentifier("welcome.start")
            // Android leaves this page with Back; iOS has no such key, so the
            // way to the chat is here, under the main action as in iOS setup.
            Button(action: later) {
                Text(verbatim: localizer.text(.welcomeLater))
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
            .accessibilityIdentifier("welcome.later")
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(palette.page)
    }
}

/// The model page's foot on first launch (Android ModelSetupContent): the
/// second dot and 下一步, which waits for a main model.
struct OnboardingNextBar: View {
    let localizer: AppLocalizer
    let enabled: Bool
    let next: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            OnboardingDots(current: 1)
                .padding(.bottom, 14)
            Button(action: next) {
                Text(verbatim: localizer.text(.commonNext))
            }
            .buttonStyle(OnboardingButtonStyle())
            .disabled(!enabled)
            .accessibilityIdentifier("setup.next")
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .background(MikaSettingsPalette(scheme: colorScheme).page)
    }
}

/// Android ProgressDots: the current step is an 18 point bar in the brand
/// tint, the other a 6 point dot. Decorative, as on Android.
private struct OnboardingDots: View {
    let current: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<Onboarding.steps, id: \.self) { step in
                if step == current {
                    Capsule().fill(.tint).frame(width: 18, height: 6)
                } else {
                    Capsule().fill(MikaSettingsPalette(scheme: colorScheme).hair).frame(width: 6, height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// Android MikaButton (Primary, Large): 52 points high in the brand tint,
/// faded while it cannot be pressed.
private struct OnboardingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.tint, in: RoundedRectangle(cornerRadius: 14))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
#endif
