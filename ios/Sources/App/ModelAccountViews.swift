#if os(iOS)
import AssistantModels
import SwiftUI

/// Which sign-in sheet is open.
struct ModelAccountSheetTarget: Identifiable, Equatable {
    let kind: ModelAccountKind
    var id: String { kind.rawValue }
}

/// A provider page to push after a sign-in.
struct ModelProviderRoute: Identifiable, Hashable {
    let id: UUID
}

extension ModelAccountKind {
    /// Android ModelsCopy.signInRowLine, signInTitle, signInBody, signInStart and signInWaiting.
    var rowLine: AppText { self == .chatGPT ? .signinRowChatGPT : .signinRowXAI }
    var signInTitle: AppText { self == .chatGPT ? .chatgptTitle : .signinXAITitle }
    var signInBody: AppText { self == .chatGPT ? .chatgptBody : .signinXAIBody }
    var signInStart: AppText { self == .chatGPT ? .chatgptContinue : .signinContinue }
    var signInWaiting: AppText { self == .chatGPT ? .chatgptWaiting : .signinXAIStarting }
    /// The account page people manage usage or grants on.
    var managePage: URL { self == .chatGPT ? ChatGPTSignIn.usagePage : XAISignIn.accountPage }
    var manageTitle: AppText { self == .chatGPT ? .chatgptManageUsage : .accountManageXAI }

    /// The sign-ins 用帳號登入 offers. The App Store build offers ChatGPT only: the xAI sign-in
    /// borrows the public client of xAI's own command-line tool, which xAI did not set up for this
    /// App, and App Review asks for permission to use a third-party service (5.2.2). Debug builds
    /// keep it for the existing checks. A provider signed in before stays usable.
    static var offeredSignIns: [ModelAccountKind] {
        #if DEBUG
        return [.chatGPT, .xai]
        #else
        return [.chatGPT]
        #endif
    }
}

/// Android AccountSignInGroup: 用帳號登入 · 不用填 Key with the offered sign-ins
/// (offeredSignIns). A signed-in row opens its provider; any other opens the
/// explanation sheet, where the sign-in starts only after the person continues.
struct ModelAccountSignInGroup: View {
    @ObservedObject var signIn: ModelAccountSignIn
    let document: ModelProvidersDocument
    let localizer: AppLocalizer
    let open: (ModelAccountKind) -> Void
    let openProvider: (UUID) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MikaSettingsGroupLabel(title: localizer.text(.signinGroup))
                .accessibilityIdentifier("signin.group")
            MikaSettingsCard {
                VStack(spacing: 0) {
                    ForEach(ModelAccountKind.offeredSignIns, id: \.self) { kind in
                        if kind != ModelAccountKind.offeredSignIns.first { Divider().padding(.leading, 60) }
                        row(kind)
                    }
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func row(_ kind: ModelAccountKind) -> some View {
        let colors = MikaSettingsPalette(scheme: scheme)
        let signedIn = signIn.signedInProvider(kind, in: document)
        return Button {
            if let signedIn { openProvider(signedIn) } else { open(kind) }
        } label: {
            HStack(spacing: 14) {
                Text(verbatim: String(kind.providerName.prefix(1)))
                    .scaledFont(size: 13, weight: .bold).dynamicTypeSize(...DynamicTypeSize.xxxLarge).foregroundStyle(colors.ink)
                    .frame(width: 30, height: 30)
                    .background(colors.tile, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: kind.providerName).font(.body).foregroundStyle(colors.ink)
                    Text(verbatim: localizer.text(kind.rowLine)).font(.caption).foregroundStyle(colors.hint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if signIn.running == kind {
                    Text(verbatim: localizer.text(.signinRunning)).font(.subheadline).foregroundStyle(colors.hint)
                } else if signedIn != nil {
                    Text(verbatim: localizer.text(.signinSignedIn)).font(.subheadline).foregroundStyle(colors.ok)
                        .accessibilityIdentifier("signin." + kind.rawValue + ".signedIn")
                } else {
                    Image(systemName: "chevron.right").scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(colors.hint).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("signin." + kind.rawValue)
    }
}

/// Android SignInSheet: what will happen first (and, for xAI, the risk), then
/// 繼續 starts the sign-in. While it runs: ChatGPT waits for OpenAI's page,
/// xAI shows its code with copy and reopen; both can be cancelled. A failure
/// says why and the sheet stays for another try; a success closes it.
struct ModelAccountSignInSheet: View {
    @ObservedObject var signIn: ModelAccountSignIn
    @ObservedObject var session: ChatSession
    let kind: ModelAccountKind
    let localizer: AppLocalizer
    /// xAI only: the xAI API-key preset instead (Android SignInSheetActions.useApiKey).
    let useAPIKey: (() -> Void)?
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: scheme) }
    private var running: Bool { signIn.running == kind }
    /// Another sign-in is running: this one cannot start (Android signin_busy).
    private var busy: Bool { signIn.running != nil && !running }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if running, kind == .xai, let code = signIn.deviceCode {
                    deviceCodeBody(code)
                } else {
                    introBody
                }
                #if DEBUG
                if let fixture = signIn.fixture { ModelAccountFixtureControls(fixture: fixture).padding(.top, 16) }
                #endif
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 20)
        }
        .background(palette.surface)
        .presentationDetents([.large])
        .interactiveDismissDisabled(running)
        .sheet(item: $signIn.browserPage) { page in
            ModelAccountSafariView(url: page.url).ignoresSafeArea()
        }
        .onChange(of: signIn.finished) { _, finished in
            if finished?.kind == kind { close() }
        }
    }

    private var introBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: localizer.text(kind.signInTitle))
                .font(.title3.weight(.semibold)).foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("signin.title")
            Text(verbatim: localizer.text(kind.signInBody))
                .font(.subheadline).foregroundStyle(palette.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .accessibilityIdentifier("signin.body")
            if kind == .xai {
                note(localizer.text(.signinXAIRisk), background: palette.softColor(for: .warn), color: palette.warn)
                    .accessibilityIdentifier("signin.risk")
                note(localizer.text(.signinStoredNote), background: palette.fill, color: palette.secondary)
                    .accessibilityIdentifier("signin.storedNote")
            }
            Button {
                signIn.start(kind, session: session, localizer: localizer)
            } label: {
                Text(verbatim: localizer.text(kind.signInStart)).frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(running || busy)
            .padding(.top, 16)
            .accessibilityIdentifier("signin.start")
            if busy {
                line(localizer.text(.signinBusy), color: palette.secondary).accessibilityIdentifier("signin.busy")
            }
            if running {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: localizer.text(kind.signInWaiting))
                        .font(.footnote).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("signin.waiting")
                    Spacer(minLength: 0)
                    Button(localizer.text(.commonCancel)) { signIn.cancel() }
                        .font(.footnote.weight(.medium))
                        .accessibilityIdentifier("signin.cancel")
                }
                .padding(.top, 12)
            }
            if let failure = signIn.failures[kind] {
                line(localizer.text(failure), color: palette.bad).accessibilityIdentifier("signin.failed")
            }
            if let useAPIKey, kind == .xai, !running {
                Button(localizer.text(.signinUseKey), action: useAPIKey)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .accessibilityIdentifier("signin.useKey")
            }
        }
    }

    /// Android DeviceCodeBody: the same code as on xAI's page, how long it
    /// lasts, copy and reopen, and cancel while it waits.
    private func deviceCodeBody(_ code: ModelAccountSignIn.DeviceCode) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: localizer.text(.signinXAICodeTitle))
                .font(.title3.weight(.semibold)).foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("signin.codeTitle")
            Text(verbatim: localizer.text(.signinXAICodeBody))
                .font(.subheadline).foregroundStyle(palette.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text(verbatim: code.userCode)
                .scaledFont(size: 30, weight: .semibold, design: .monospaced).kerning(4)
                .foregroundStyle(palette.ink)
                .padding(.top, 16)
                .accessibilityIdentifier("signin.code")
            let minutes = max(1, Int(code.expiresAt.timeIntervalSinceNow / 60))
            Text(verbatim: localizer.text(.signinXAICodeValid(minutes: minutes)))
                .font(.caption).foregroundStyle(palette.hint).padding(.top, 4)
            Button { signIn.copyCodeAndReopen() } label: {
                Text(verbatim: localizer.text(.signinXAICopyReopen)).frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .padding(.top, 16)
            .accessibilityIdentifier("signin.copyReopen")
            if signIn.copiedCode {
                Text(verbatim: localizer.text(.signinCopied)).font(.caption).foregroundStyle(palette.ok).padding(.top, 6)
                    .accessibilityIdentifier("signin.copied")
            }
            Text(verbatim: localizer.text(.signinXAIWaiting))
                .font(.footnote).foregroundStyle(palette.secondary).padding(.top, 14)
                .accessibilityIdentifier("signin.waiting")
            Button(localizer.text(.commonCancel)) { signIn.cancel() }
                .font(.subheadline.weight(.medium)).padding(.top, 8)
                .accessibilityIdentifier("signin.cancel")
        }
        .frame(maxWidth: .infinity)
    }

    private func note(_ text: String, background: Color, color: Color) -> some View {
        Text(verbatim: text)
            .font(.footnote).foregroundStyle(color).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 12)
    }

    private func line(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.footnote).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }
}

/// Android ChatGptConnection and AccountConnection: the account, its status,
/// 設為主模型, the account's own page, and 退出登入 or signing in again.
/// Signing out clears this device only; the provider, its models and the roles
/// that use it stay.
struct ModelAccountConnectionSection: View {
    @ObservedObject var signIn: ModelAccountSignIn
    @ObservedObject var session: ChatSession
    let provider: ModelProvider
    let kind: ModelAccountKind
    let localizer: AppLocalizer
    let signInAgain: () -> Void
    let useAsMain: (String) -> Void
    @Environment(\.colorScheme) private var scheme

    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: scheme) }
    private var status: ModelAccountStatus? { signIn.status(provider.id) }
    private var signedIn: Bool { status?.signedIn == true }
    private var isMain: Bool { session.providerDocument.roles.main?.providerID == provider.id }
    private var defaultModel: String? { session.providerDocument.defaultModel(of: provider.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MikaSettingsGroupLabel(title: localizer.text(.modelsConnection))
            MikaSettingsCard {
                VStack(spacing: 0) {
                    if let label = status?.label, !label.isEmpty {
                        valueRow(localizer.text(.chatgptAccount), label, color: palette.hint, id: "provider.account.label")
                        Divider().padding(.leading, 16)
                    }
                    valueRow(localizer.text(.modelsStatus), statusText.text, color: statusText.color, id: "provider.account.status")
                }
            }
            MikaSettingsCard {
                VStack(spacing: 0) {
                    if signedIn, !isMain, let model = defaultModel {
                        Button { useAsMain(model) } label: {
                            actionRow(localizer.text(.signinSetMain), subtitle: localizer.text(.signinSetMainNote), tint: palette.ink, chevron: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(session.isSubmitting)
                        .accessibilityIdentifier("provider.account.setMain")
                        Divider().padding(.leading, 16)
                    }
                    Link(destination: kind.managePage) {
                        actionRow(localizer.text(kind.manageTitle), subtitle: nil, tint: .accentColor, chevron: true)
                    }
                    .accessibilityIdentifier("provider.account.manage")
                    Divider().padding(.leading, 16)
                    if signedIn {
                        Button { signIn.signOut(providerID: provider.id, session: session) } label: {
                            actionRow(localizer.text(.chatgptSignOut), subtitle: localizer.text(.signinSignOutNote), tint: palette.bad, chevron: false)
                        }
                        .buttonStyle(.plain)
                        .disabled(session.isSubmitting)
                        .accessibilityIdentifier("provider.account.signOut")
                    } else {
                        Button(action: signInAgain) {
                            actionRow(localizer.text(signIn.running == kind ? .signinRunning : kind.signInStart), subtitle: nil,
                                      tint: .accentColor, chevron: false)
                        }
                        .buttonStyle(.plain)
                        .disabled(signIn.running != nil)
                        .accessibilityIdentifier("provider.account.signIn")
                    }
                }
            }
            .padding(.top, 8)
            notes
        }
    }

    @ViewBuilder private var notes: some View {
        switch kind {
        case .chatGPT:
            note(localizer.text(signedIn ? .chatgptPlanNote : .chatgptSignedOutNote), color: palette.hint)
                .accessibilityIdentifier("provider.account.note")
            if signIn.revokeUnconfirmed {
                note(localizer.text(.chatgptRevokeUnconfirmed), color: palette.warn).accessibilityIdentifier("provider.account.revoke")
            }
        case .xai:
            note(localizer.text(signedIn ? .accountSignedInNoteXAI : .accountSignedOutNote), color: palette.hint)
                .accessibilityIdentifier("provider.account.note")
            if signedIn {
                note(localizer.text(.signinXAINote403), color: palette.warn).accessibilityIdentifier("provider.account.note403")
            }
        }
        if let failure = signIn.failures[kind] {
            note(localizer.text(failure), color: palette.bad).accessibilityIdentifier("provider.account.failed")
        }
    }

    private var statusText: (text: String, color: Color) {
        if !signedIn { return (localizer.text(.signinSignedOut), palette.warn) }
        switch signIn.listing[provider.id] {
        case .running?: return (localizer.text(.signinListing), palette.hint)
        case .failed?: return (localizer.text(.signinListFailed), palette.bad)
        case nil: return (localizer.text(.signinSignedIn), palette.ok)
        }
    }

    /// The value keeps its own identifier, like provider.keyStatus.
    private func valueRow(_ title: String, _ value: String, color: Color, id: String) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: title).font(.body).foregroundStyle(palette.ink)
            Spacer(minLength: 4)
            Text(verbatim: value).font(.subheadline).foregroundStyle(color)
                .lineLimit(2).multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id)
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }

    private func actionRow(_ title: String, subtitle: String?, tint: Color, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.body).foregroundStyle(tint)
                if let subtitle {
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(palette.hint)
                }
            }
            Spacer(minLength: 4)
            if chevron {
                Image(systemName: "chevron.right").scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(palette.hint).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.footnote).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.top, 8)
    }
}

#if DEBUG
/// UI-test controls for ModelAccountSignInFixture: how many sign-ins started
/// and pages were reopened, and the answer the fake account gives.
private struct ModelAccountFixtureControls: View {
    @ObservedObject var fixture: ModelAccountSignInFixture

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fixture: \(fixture.started),\(fixture.reopened)")
                .font(.caption)
                .accessibilityIdentifier("signin.fixture")
            HStack(spacing: 16) {
                Button("Approve fixture") { fixture.approve() }
                    .disabled(!fixture.waiting)
                    .accessibilityIdentifier("signin.fixture.approve")
                Button("Refuse fixture") { fixture.refuse() }
                    .disabled(!fixture.waiting)
                    .accessibilityIdentifier("signin.fixture.refuse")
            }
            .font(.caption)
        }
    }
}
#endif
#endif
