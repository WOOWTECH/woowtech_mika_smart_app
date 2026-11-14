import Foundation

/// The Play build's money rule for web tasks (core action/Approval,
/// gate/IrreversibleDetector, gate/ConfirmationGate), with Traditional Chinese
/// and Taiwanese wording: paying is never done by the task; ordering, and
/// submitting or deleting while the page shows an amount to pay, need the
/// user's 允許這一次 for that one next step; every other action runs.
public enum ChatWebSpending {
    public enum Action: String, Equatable, Sendable { case pay, order, submit, delete, send }

    public enum Decision: Equatable, Sendable {
        /// Not an action that changes anything outside the page.
        case allow
        /// Sending, submitting or deleting without money: runs, recorded and paced.
        case outward(Action)
        /// Ordering, or submitting/deleting with an amount to pay: one-time consent.
        case needsConsent(Action, amount: String?)
        /// Paying is always left to the user (hand_to_user payment).
        case payment
    }

    /// Words that pay (Android STRONG pay and EXACT_PAY, in Taiwanese wording).
    static let payWords = ["付款", "支付", "轉帳", "匯款", "儲值", "加值", "繳費", "捐款", "結清", "確認付款", "立即付款", "前往付款", "去付款"]
    static let orderWords = ["下單", "下訂單", "送出訂單", "提交訂單", "確認訂單", "購買", "立即購買", "直接購買", "結帳", "前往結帳",
                             "立即結帳", "確認結帳", "去結帳", "結算", "訂購", "立即訂購", "取消訂單", "退款", "確認收貨"]
    static let submitWords = ["提交", "確認提交", "送出", "確認送出", "投遞", "投履歷", "應徵", "立即應徵", "我要應徵", "立即申請",
                              "一鍵申請", "申請職位", "預約", "立即預約", "確認預約", "報名", "立即報名", "確認報名"]
    static let deleteWords = ["刪除", "撤回", "移除", "清空", "註銷"]
    static let sendWords = ["發送", "傳送", "發布", "發表", "留言", "回覆", "評論", "轉發"]
    static let englishPay = ["pay", "pay now", "donate", "complete payment", "confirm payment"]
    static let englishOrder = ["place order", "buy now", "checkout", "check out", "purchase", "order now", "complete purchase"]
    static let englishSubmit = ["submit", "apply now", "easy apply", "quick apply", "submit application", "book now", "register now"]
    static let englishDelete = ["delete", "remove", "clear all"]
    static let englishSend = ["send", "post", "reply", "comment"]
    /// Entrances and states, not actions (待付款、付款紀錄、購買紀錄、加入購物車).
    static let notActions = ["待", "已", "紀錄", "記錄", "成功", "方式", "明細", "列表", "中心", "說明", "加入購物車", "購物車", "add to cart", "history"]
    /// Labels that make an amount on the page an amount to pay (Android TOTAL_LABELS).
    static let totalLabels = ["合計", "總計", "總金額", "實付", "應付", "付款金額", "結帳金額", "訂單金額", "total", "amount due", "order total"]

    /// What the control's own label does. Generic labels (確認、確定、OK)
    /// count as submitting only when the page shows an amount to pay.
    public static func action(of label: String) -> Action? {
        let text = label.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 40 else { return nil }
        let lower = text.lowercased()
        if notActions.contains(where: { lower.contains($0) }) && !lower.hasPrefix("確認") { return nil }
        func starts(_ words: [String]) -> Bool { words.contains { text.hasPrefix($0) && text.count <= $0.count + 4 } }
        func english(_ words: [String]) -> Bool {
            let clean = lower.trimmingCharacters(in: .punctuationCharacters).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return words.contains { clean == $0 || clean.hasPrefix($0 + " ") }
        }
        if starts(payWords) || english(englishPay) { return .pay }
        if starts(orderWords) || english(englishOrder) { return .order }
        if starts(deleteWords) || english(englishDelete) { return .delete }
        if starts(submitWords) || english(englishSubmit) { return .submit }
        if starts(sendWords) || english(englishSend) { return .send }
        if ["確認", "確定", "完成", "ok", "confirm"].contains(lower) { return .submit }
        return nil
    }

    /// The amount to pay the page shows next to a total label, if any.
    public static func payableAmount(in pageText: String) -> String? {
        let pattern = #"(?:NT\$|NTD|\$|＄|USD|元)\s*[0-9][0-9,]*(?:\.[0-9]+)?|[0-9][0-9,]*(?:\.[0-9]+)?\s*元"#
        guard let amount = try? NSRegularExpression(pattern: pattern) else { return nil }
        for line in pageText.components(separatedBy: .newlines) where line.count <= 200 {
            let lower = line.lowercased()
            guard totalLabels.contains(where: { lower.contains($0) }),
                  let match = amount.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range, in: line) else { continue }
            return String(line[range]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    public static func decide(label: String, pageText: String) -> Decision {
        guard let action = action(of: label) else { return .allow }
        switch action {
        case .pay: return .payment
        case .order: return .needsConsent(.order, amount: payableAmount(in: pageText))
        case .submit, .delete:
            if let amount = payableAmount(in: pageText) { return .needsConsent(action, amount: amount) }
            return .outward(action)
        case .send: return .outward(.send)
        }
    }
}

/// One user consent for one spending step (Android ConfirmationGate): only the
/// next matching step on the same site, within three steps, with no other
/// action in between except typing; ordering and submitting cover each other.
/// A refusal stops asking for that action on that site for the rest of the task.
public struct ChatWebConsentGate: Sendable {
    public struct Request: Equatable, Sendable {
        public let action: ChatWebSpending.Action
        public let site: String
        public let target: String
        public let amount: String?
        public init(action: ChatWebSpending.Action, site: String, target: String, amount: String?) {
            self.action = action; self.site = site; self.target = target; self.amount = amount
        }
    }
    public enum Permit: Equatable, Sendable { case allowed, noConsent, mismatch }
    public static let maximumSteps = 3
    private var grant: (request: Request, step: Int)?
    private var declined: Set<String> = []
    public init() {}

    public func wasDeclined(_ action: ChatWebSpending.Action, site: String) -> Bool {
        declined.contains(Self.key(action, site))
    }

    public mutating func record(_ request: Request, allowed: Bool, step: Int) {
        if allowed { grant = (request, step) } else { grant = nil; declined.insert(Self.key(request.action, request.site)) }
    }

    /// Any action other than typing ends an unused consent.
    public mutating func noteOtherAction() { grant = nil }

    /// Uses the consent up, whatever the outcome; paying is never allowed.
    public mutating func permit(_ action: ChatWebSpending.Action, site: String, target: String,
                                pageAmount: String?, step: Int) -> Permit {
        guard let current = grant else { return .noConsent }
        grant = nil
        let request = current.request
        let kinds: Set<ChatWebSpending.Action> = [.order, .submit]
        guard action != .pay, step - current.step <= Self.maximumSteps, site == request.site,
              action == request.action || (kinds.contains(action) && kinds.contains(request.action)),
              Self.normalized(target).contains(Self.normalized(request.target)) || Self.normalized(request.target).contains(Self.normalized(target)),
              request.amount == nil || pageAmount.map(Self.digits) == request.amount.map(Self.digits) else { return .mismatch }
        return .allowed
    }

    private static func key(_ action: ChatWebSpending.Action, _ site: String) -> String {
        let kind = [.order, .submit].contains(action) ? "spend" : action.rawValue
        return kind + "|" + site
    }
    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }
    private static func digits(_ text: String) -> String { text.filter(\.isNumber) }
}

/// Android OutwardPacing: on one site, the second outward action waits 8–20 s,
/// each later one 0.5–1 s more, at most 30 s.
public struct ChatWebOutwardPacing: Sendable {
    private var counts: [String: Int] = [:]
    public init() {}
    public mutating func delay(site: String, jitter: () -> Double) -> Double {
        let count = counts[site, default: 0] + 1
        counts[site] = count
        guard count >= 2 else { return 0 }
        let extra = (0..<(count - 2)).reduce(0.0) { sum, _ in sum + 0.5 + 0.5 * jitter() }
        return min(30, 8 + 12 * jitter() + extra)
    }
}
