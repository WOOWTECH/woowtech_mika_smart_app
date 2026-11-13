import SwiftUI
import UIKit
import WebKit
import AssistantBrowser

/// The chat's colors for the task card and preview.
struct ChatWebTaskColors {
    let ink: Color
    let secondaryInk: Color
    let accent: Color
    let fill: Color
    let background: Color
}

/// Words for a web task's card, steps and preview.
struct ChatWebTaskText {
    let localizer: AppLocalizer

    func activity(_ activity: ChatWebActivity, phase: ChatWebTaskSession.Phase) -> String {
        if phase == .paused { return localizer.text(.chatWebPaused) }
        switch activity {
        case .thinking: return localizer.text(.chatWebActivityThinking)
        case .opening(let site): return localizer.text(.chatWebActivityOpening(site: site))
        case .reading(let site): return localizer.text(.chatWebActivityReading(site: site))
        case .finding(let site): return localizer.text(.chatWebActivityFinding(site: site))
        case .scrolling(let site): return localizer.text(.chatWebActivityScrolling(site: site))
        case .goingBack: return localizer.text(.chatWebActivityBack)
        case .waiting(let site): return localizer.text(.chatWebActivityWaiting(site: site))
        case .pacing(let site): return localizer.text(.chatWebActivityPacing(site: site))
        case .acting(let site): return localizer.text(.chatWebActivityActing(site: site))
        case .waitingForYou: return localizer.text(.chatWebActivityWaitingForYou)
        case .summarizing: return localizer.text(.chatWebActivitySummarizing)
        }
    }

    func reason(_ reason: ChatWebHandover.Reason) -> String {
        switch reason {
        case .login: return localizer.text(.chatWebReasonLogin)
        case .captcha: return localizer.text(.chatWebReasonCaptcha)
        case .accessBlocked: return localizer.text(.chatWebReasonAccessBlocked)
        case .payment: return localizer.text(.chatWebReasonPayment)
        case .decision: return localizer.text(.chatWebReasonDecision)
        case .other: return localizer.text(.chatWebReasonOther)
        }
    }

    func step(_ step: ChatWebStep) -> String {
        let site = step.site.isEmpty ? "—" : step.site
        let label: String
        switch step.kind {
        case .open: label = localizer.text(.chatWebStepOpen(site: site))
        case .read: label = localizer.text(.chatWebStepRead(site: site))
        case .find: label = localizer.text(.chatWebStepFind(site: site))
        case .scroll: label = localizer.text(.chatWebStepScroll(site: site))
        case .back: label = localizer.text(.chatWebStepBack(site: site))
        case .wait: label = localizer.text(.chatWebStepWait(site: site))
        case .observe: label = localizer.text(.chatWebStepObserve(site: site))
        case .tap: label = localizer.text(.chatWebStepTap(site: site))
        case .type: label = localizer.text(.chatWebStepType(site: site))
        case .select: label = localizer.text(.chatWebStepSelect(site: site))
        case .confirm: label = localizer.text(.chatWebStepConfirm(site: site))
        case .handover: label = localizer.text(.chatWebStepHandover(site: site))
        case .ask: label = localizer.text(.chatWebStepAsk)
        }
        var text = label
        if step.outward { text += " · " + localizer.text(.chatWebStepOutward) }
        if !step.title.isEmpty && [.tap, .type, .select, .confirm, .handover, .ask].contains(step.kind) { text += "「" + step.title + "」" }
        return step.succeeded ? text : text + " · " + localizer.text(.chatWebStepFailed)
    }

    @MainActor func headline(_ task: ChatWebTaskSession) -> String {
        guard let site = task.steps.last(where: { !$0.site.isEmpty })?.site else { return localizer.text(.chatWebTitle) }
        return localizer.text(.chatWebWorkingOn(site: site))
    }

    /// The small view's default: not on small screens or accessibility text sizes.
    @MainActor static func automaticPreview(_ dynamicType: DynamicTypeSize) -> Bool {
        let height = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height ?? 800
        return !dynamicType.isAccessibilitySize && height >= 700
    }

    static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The running task in the conversation, like Android's progress block: what
/// it is doing, time, the latest steps, 「檢視過程」 and 「停止」.
struct ChatWebTaskCard: View {
    @ObservedObject var task: ChatWebTaskSession
    let localizer: AppLocalizer
    let colors: ChatWebTaskColors
    let onStop: () -> Void
    @State private var showsProcess = false
    @State private var answerDraft = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var text: ChatWebTaskText { ChatWebTaskText(localizer: localizer) }
    private var waitsForUser: Bool {
        task.pendingConsent != nil || task.pendingHandover != nil || task.pendingQuestion != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: task.startedAt, by: 1)) { context in
                status(now: context.date)
            }
            ForEach(task.steps.suffix(dynamicTypeSize.isAccessibilitySize ? 2 : 5)) { step in
                Text(verbatim: text.step(step))
                    .font(.caption).foregroundStyle(step.succeeded ? colors.secondaryInk : .red)
                    .lineLimit(2)
            }
            if let request = task.pendingConsent { consent(request) }
            if let handover = task.pendingHandover { handoverBox(handover) }
            if let question = task.pendingQuestion { questionBox(question.prompt, question.options) }
            Text(verbatim: localizer.text(.chatWebForegroundNote))
                .font(.caption2).foregroundStyle(colors.secondaryInk)
            buttons
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fill, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(task.phase == .paused || waitsForUser ? Color.orange : colors.accent.opacity(0.5),
                                                           lineWidth: waitsForUser ? 2 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.web.card")
        .sheet(isPresented: $showsProcess) {
            ChatWebTaskProcessSheet(task: task, localizer: localizer)
        }
    }

    private func status(now: Date) -> some View {
        let elapsed = ChatWebTaskText.elapsed(since: task.startedAt, now: now)
        let activity = text.activity(task.activity, phase: task.phase)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if task.phase == .running { ProgressView().controlSize(.small) }
                else { Image(systemName: task.phase == .paused ? "pause.circle" : "checkmark.circle").foregroundStyle(colors.accent) }
                Text(verbatim: text.headline(task)).font(.subheadline.weight(.semibold)).foregroundStyle(colors.ink)
            }
            Text(verbatim: activity).font(.callout).foregroundStyle(colors.ink)
                .accessibilityIdentifier("chat.web.activity")
            Text(verbatim: localizer.text(.chatWebElapsed(time: elapsed)) + " · " + localizer.text(.chatWebStepNumber(number: task.steps.count)))
                .font(.caption).foregroundStyle(colors.secondaryInk).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizer.text(.chatWebCardAccessibility(activity: activity, step: task.steps.count, elapsed: elapsed)))
        .accessibilityIdentifier("chat.web.status")
    }

    /// Android's 要你同意 card: allowing works only here, never from a notification.
    private func consent(_ request: ChatWebConsentGate.Request) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: request.amount.map { localizer.text(.chatWebAskTitleAmount(target: request.target, amount: $0)) }
                 ?? localizer.text(.chatWebAskTitle(target: request.target)))
                .font(.subheadline.weight(.semibold)).foregroundStyle(colors.ink)
                .accessibilityIdentifier("chat.web.consent.title")
            Text(verbatim: localizer.text(.chatWebAskNote)).font(.caption).foregroundStyle(colors.secondaryInk)
            HStack(spacing: 12) {
                Button(localizer.text(.chatWebAskRefuse)) { task.answerConsent(false) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("chat.web.consent.refuse")
                Button(localizer.text(.chatWebAskAllowOnce)) { task.answerConsent(true) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("chat.web.consent.allow")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.web.consent")
    }

    /// Android's takeover card: 需要你處理：… with 跳過, 我來處理 and 取消任務;
    /// once the user has the page, 處理好了 and 我自己做完了.
    private func handoverBox(_ handover: ChatWebHandover) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: localizer.text(.chatWebHandoverTitle(reason: text.reason(handover.reason))))
                .font(.subheadline.weight(.semibold)).foregroundStyle(colors.ink)
                .accessibilityIdentifier("chat.web.handover.title")
            Text(verbatim: handover.message).font(.callout).foregroundStyle(colors.ink)
            ForEach(Array([handover.item.map { localizer.text(.chatWebPaymentItem(item: $0)) },
                           handover.amount.map { localizer.text(.chatWebPaymentAmount(amount: $0)) },
                           handover.address.map { localizer.text(.chatWebPaymentAddress(address: $0)) }].compactMap { $0 }.enumerated()),
                    id: \.offset) { _, line in
                Text(verbatim: line).font(.caption).foregroundStyle(colors.secondaryInk)
            }
            if task.isUserControlled {
                Text(verbatim: localizer.text(.chatWebUserHasPage)).font(.caption).foregroundStyle(colors.secondaryInk)
                HStack(spacing: 12) {
                    Button(localizer.text(.chatWebHandBack)) { task.endHandover(.handedBack) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("chat.web.handBack")
                    Button(localizer.text(.chatWebFinishedMyself)) { task.endHandover(.finishedByUser) }
                        .buttonStyle(.bordered).accessibilityIdentifier("chat.web.finishedMyself")
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { handoverButtons }
                    VStack(alignment: .leading, spacing: 8) { handoverButtons }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.web.handover")
    }

    @ViewBuilder private var handoverButtons: some View {
        Button(localizer.text(.chatWebTakeOver)) { task.takeOver() }
            .buttonStyle(.borderedProminent).accessibilityIdentifier("chat.web.takeOver")
        Button(localizer.text(.chatWebSkip)) { task.endHandover(.skipped) }
            .buttonStyle(.bordered).accessibilityIdentifier("chat.web.skip")
        Button(localizer.text(.chatWebCancelTask), role: .destructive, action: onStop)
            .accessibilityIdentifier("chat.web.cancelTask")
    }

    /// Android's 需要你回答: a choice or the user's own words.
    private func questionBox(_ prompt: String, _ options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: localizer.text(.chatWebQuestionTitle)).font(.subheadline.weight(.semibold)).foregroundStyle(colors.ink)
            Text(verbatim: prompt).font(.callout).foregroundStyle(colors.ink)
                .accessibilityIdentifier("chat.web.question.prompt")
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button(option) { task.answer(option) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("chat.web.question.option.\(index)")
            }
            HStack {
                TextField(localizer.text(.chatWebAnswerPlaceholder), text: $answerDraft)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("chat.web.question.answer")
                Button(localizer.text(.chatWebAnswerSend)) { let answer = answerDraft; answerDraft = ""; task.answer(answer) }
                    .disabled(answerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("chat.web.question.send")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.web.question")
    }

    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { buttonRow }
            VStack(alignment: .leading, spacing: 8) { buttonRow }
        }
        .font(.callout)
    }

    @ViewBuilder private var buttonRow: some View {
        Button(localizer.text(.chatWebViewProcess)) { showsProcess = true }
            .accessibilityIdentifier("chat.web.viewProcess")
        let shown = task.showsPreview ?? ChatWebTaskText.automaticPreview(dynamicTypeSize)
        Button(shown ? localizer.text(.chatWebHideScreen) : localizer.text(.chatWebShowScreen)) {
            task.showsPreview = !shown
        }
        .accessibilityIdentifier("chat.web.togglePreview")
        Button(localizer.text(.chatWebViewPage)) { task.showsPreview = true; task.isExpanded = true }
            .accessibilityIdentifier("chat.web.viewPage")
        if task.isRunning {
            Button(localizer.text(.chatWebStop), role: .destructive, action: onStop)
                .accessibilityIdentifier("chat.web.stop")
        }
    }
}

/// Every step with its page title and address. No page text is kept.
struct ChatWebTaskProcessSheet: View {
    @ObservedObject var task: ChatWebTaskSession
    let localizer: AppLocalizer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if task.steps.isEmpty { Text(verbatim: localizer.text(.chatWebProcessEmpty)).foregroundStyle(.secondary) }
                ForEach(task.steps) { step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(step.id). " + ChatWebTaskText(localizer: localizer).step(step))
                            .foregroundStyle(step.succeeded ? Color.primary : Color.red)
                        if !step.title.isEmpty { Text(verbatim: step.title).font(.caption) }
                        if let url = step.url { Text(verbatim: url.absoluteString).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
            }
            .accessibilityIdentifier("chat.web.process")
            .navigationTitle(localizer.text(.chatWebProcessTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizer.text(.chatWebProcessDone)) { dismiss() }
                        .accessibilityIdentifier("chat.web.process.done")
                }
            }
        }
    }
}

/// The task tab itself, laid out at phone width and shown scaled down in the
/// corner (Android's small view), or full size when enlarged. It stays in the
/// window even when hidden, because WebKit pauses pages that are not.
struct ChatWebTaskPreview: View {
    @ObservedObject var task: ChatWebTaskSession
    let localizer: AppLocalizer
    let colors: ChatWebTaskColors
    /// False outside the chat: the page keeps running, unseen.
    let isOnScreen: Bool
    let onStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            let page = CGSize(width: min(430, max(320, geometry.size.width)), height: max(560, geometry.size.height))
            let expanded = task.isExpanded && isOnScreen
            let visible = isOnScreen && ((task.showsPreview ?? ChatWebTaskText.automaticPreview(dynamicTypeSize)) || expanded)
            let scale: CGFloat = expanded ? min(1, geometry.size.width / page.width) : (visible ? 0.3 : 0.05)
            ZStack(alignment: expanded ? .top : .bottomTrailing) {
                if expanded {
                    colors.background.ignoresSafeArea()
                        .accessibilityHidden(true)
                }
                VStack(alignment: .trailing, spacing: 8) {
                    if expanded { expandedBar }
                    ChatWebTaskWebView(tab: task.tab)
                        .frame(width: page.width, height: page.height)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: page.width * scale, height: page.height * scale, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : 10))
                        .overlay {
                            if !expanded {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(task.phase == .paused || task.pendingConsent != nil || task.pendingHandover != nil
                                            || task.pendingQuestion != nil ? Color.orange : Color.green, lineWidth: 2)
                            }
                        }
                        .allowsHitTesting(expanded && task.isUserControlled)
                        .overlay {
                            if visible && !expanded {
                                Color.clear.contentShape(Rectangle())
                                    .onTapGesture { task.isExpanded = true }
                            }
                        }
                        .accessibilityHidden(!(expanded && task.isUserControlled))
                }
                .padding(.trailing, expanded ? 0 : 12)
                .padding(.bottom, expanded ? 0 : 96)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: expanded ? .top : .bottomTrailing)
            .opacity(visible ? 1 : 0.01)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: expanded)
        }
        .allowsHitTesting(isOnScreen && ((task.showsPreview ?? ChatWebTaskText.automaticPreview(dynamicTypeSize)) || task.isExpanded))
    }

    @ViewBuilder private var expandedBar: some View {
        if let handover = task.pendingHandover, task.isUserControlled {
            // Android WebTakeoverPage: the same page, the user's to use.
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: localizer.text(.chatWebWaitingOnYou(reason: ChatWebTaskText(localizer: localizer).reason(handover.reason))))
                    .font(.callout.weight(.semibold))
                    .accessibilityIdentifier("chat.web.waitingOnYou")
                HStack(spacing: 12) {
                    Button(localizer.text(.chatWebHandBack)) { task.endHandover(.handedBack) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("chat.web.expanded.handBack")
                    Button(localizer.text(.chatWebFinishedMyself)) { task.endHandover(.finishedByUser) }
                        .buttonStyle(.bordered).accessibilityIdentifier("chat.web.expanded.finishedMyself")
                    Spacer()
                    Button(localizer.text(.chatWebCancelTask), role: .destructive, action: onStop)
                        .accessibilityIdentifier("chat.web.expanded.cancelTask")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        } else {
            HStack {
                Text(verbatim: ChatWebTaskText(localizer: localizer).activity(task.activity, phase: task.phase))
                    .font(.callout).lineLimit(1)
                Spacer()
                if task.isRunning {
                    Button(localizer.text(.chatWebStop), role: .destructive, action: onStop)
                        .accessibilityIdentifier("chat.web.expanded.stop")
                }
                Button(localizer.text(.chatWebShrink)) { task.isExpanded = false }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("chat.web.shrink")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }
}

struct ChatWebTaskWebView: UIViewRepresentable {
    let tab: ChatWebTaskTab
    func makeUIView(context: Context) -> WKWebView { tab.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
