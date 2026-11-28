#if WOOWTECHBOT
import SwiftUI

/// The woowtechbot component family on iOS, mirroring Android's `BotUiPopovers.kt`, `BotUiSheet.kt` and
/// `components/Dialog.kt` (docs-woowtech/woowtechbot/SUBPAGES-ALIGNMENT.md): one popover, one sheet and one
/// dialog surface for every native sub-screen, so a later change is made once. Numbers are Android's own
/// (dp ≙ pt); icons are SF Symbols where Android draws its 1.7-stroke set.

/// Android's `app_name` for the woowtech brand: 渥屋助理 / woowtech agent.
enum BotBrand {
    static func appName(_ localizer: AppLocalizer) -> String { localizer.language == .english ? "woowtech agent" : "渥屋助理" }
}

enum BotMotion {
    /// `pop-in`: 0.2 s cubic-bezier(.22, 1, .36, 1).
    static let pop = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.2)
}

// MARK: Popover

enum BotPopoverPlacement {
    /// The four-grid menu opens upwards from its left edge, the account menu downwards from its left edge,
    /// plus and a row's "…" downwards from their right edge; eight points from the button.
    case belowLeading, belowTrailing, aboveLeading

    var scaleAnchor: UnitPoint {
        switch self {
        case .belowLeading: return .topLeading
        case .belowTrailing: return .topTrailing
        case .aboveLeading: return .bottomLeading
        }
    }
    /// pop-in rises 6 points into place (from below for a menu that hangs under its button).
    var rise: CGFloat { self == .aboveLeading ? -6 : 6 }
}

protocol BotPopoverID: Hashable {
    var anchorID: String { get }
    var placement: BotPopoverPlacement { get }
}

/// The global frames of the buttons popovers open from, by anchor id.
struct BotPopoverFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct BotPopoverMaxWidth: EnvironmentKey { static let defaultValue: CGFloat = 320 }
extension EnvironmentValues {
    fileprivate var botPopoverMaxWidth: CGFloat {
        get { self[BotPopoverMaxWidth.self] }
        set { self[BotPopoverMaxWidth.self] = newValue }
    }
}

extension View {
    /// Marks the button a popover opens from (its frame is kept in window coordinates, so the popover lands the same
    /// wherever the layer that shows it sits).
    func botPopoverAnchor(_ id: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: BotPopoverFrameKey.self, value: [id: proxy.frame(in: .global)])
        })
    }

    /// Shows `menu` for the active popover next to its anchor: no scrim, a tap anywhere else closes it.
    func botPopoverHost<ID: BotPopoverID, Menu: View>(active: Binding<ID?>, @ViewBuilder menu: @escaping (ID) -> Menu) -> some View {
        overlayPreferenceValue(BotPopoverFrameKey.self) { frames in
            BotPopoverLayer(active: active, frame: active.wrappedValue.flatMap { frames[$0.anchorID] }, menu: menu)
        }
    }
}

/// Android `PopoverPosition`: left edge (or right edge) of the button, 8 points away, kept 8 points inside the window.
private struct BotPopoverLayout: Layout {
    let anchor: CGRect
    let placement: BotPopoverPlacement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let menu = subviews.first else { return }
        let size = menu.sizeThatFits(.unspecified)
        let margin: CGFloat = 8, gap: CGFloat = 8
        let rawX = placement == .belowTrailing ? anchor.maxX - size.width : anchor.minX
        let rawY = placement == .aboveLeading ? anchor.minY - gap - size.height : anchor.maxY + gap
        let x = min(max(rawX, margin), max(margin, bounds.width - size.width - margin))
        let y = min(max(rawY, margin), max(margin, bounds.height - size.height - margin))
        menu.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
                   proposal: ProposedViewSize(width: size.width, height: size.height))
    }
}

/// The layer a popover lives in: always present, but it only takes touches while a popover is open (a tap anywhere outside
/// closes it). `frame` is the anchor's window frame; the layer fills the screen so those coordinates line up.
struct BotPopoverLayer<ID: BotPopoverID, Menu: View>: View {
    @Binding var active: ID?
    let frame: CGRect?
    let menu: (ID) -> Menu
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { close() }
                    .allowsHitTesting(active != nil)
                    .accessibilityHidden(true)
                if let id = active, let frame {
                    BotPopoverLayout(anchor: frame.offsetBy(dx: -origin.x, dy: -origin.y), placement: id.placement) {
                        menu(id)
                            .environment(\.botPopoverMaxWidth, min(proxy.size.width - 24, 320))
                            .transition(reduceMotion ? .opacity : .modifier(
                                active: BotPopTransition(progress: 0, anchor: id.placement.scaleAnchor, rise: id.placement.rise),
                                identity: BotPopTransition(progress: 1, anchor: id.placement.scaleAnchor, rise: id.placement.rise)))
                            .accessibilityAddTraits(.isModal)
                            .accessibilityAction(.escape) { close() }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(reduceMotion ? nil : BotMotion.pop, value: active)
        }
        .ignoresSafeArea()
    }
    private func close() { withAnimation(reduceMotion ? nil : BotMotion.pop) { active = nil } }
}

/// pop-in: opacity 0→1, scale .96→1 and a 6-point rise; pop-out is the reverse.
private struct BotPopTransition: ViewModifier {
    let progress: Double
    let anchor: UnitPoint
    let rise: CGFloat
    func body(content: Content) -> some View {
        content.opacity(progress)
            .scaleEffect(0.96 + 0.04 * progress, anchor: anchor)
            .offset(y: rise * (1 - progress))
    }
}

/// The popover surface: menu colour, 1 pt hairline at 50 %, `--radius-menu`, 6 points of padding, rows 4 apart,
/// at least `minWidth` and at most the screen less 24 (320 at the widest).
struct BotPopoverSurface<Content: View>: View {
    var minWidth: CGFloat = 200
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.botPopoverMaxWidth) private var maxWidth
    var body: some View {
        let palette = MikaVisualPalette(scheme)
        let shape = RoundedRectangle(cornerRadius: palette.menuRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 4) { content }
            .padding(6)
            .frame(minWidth: minWidth, maxWidth: max(minWidth, maxWidth), alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(palette.menu, in: shape)
            .overlay(shape.strokeBorder(palette.hair50, lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.1), radius: 6, y: 2)
            .shadow(color: .black.opacity(scheme == .dark ? 0.7 : 0.16), radius: 12, y: 8)
    }
}

/// One row: 30 minimum, 14/18 text, 16-point icon first in secondary ink, 8 apart, 6-point corners (`.ui-menu-row`).
struct BotPopoverRow: View {
    let symbol: String
    let title: String
    var destructive = false
    var enabled = true
    var identifier: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14.5, weight: .regular)).frame(width: 16, height: 16)
                    .foregroundStyle(destructive ? palette.destructive : palette.secondaryInk).accessibilityHidden(true)
                Text(title).scaledFont(size: 14).lineLimit(1)
                    .foregroundStyle(destructive ? palette.destructive : palette.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(minHeight: 30, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(BotPopoverRowStyle())
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }
}

private struct BotPopoverRowStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(MikaVisualPalette(scheme).ink.opacity(configuration.isPressed ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// 1 pt, 6 in from each side, hairline at 50 % (the website's `mx-1.5 h-px bg-hairline/50`).
struct BotPopoverDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle().fill(MikaVisualPalette(scheme).hair50).frame(height: 1).padding(.horizontal, 6)
    }
}

// MARK: Buttons and fields

/// `.icon-button`: a 40-point circle on the card colour with a hairline, inside a 48-point target.
struct BotRoundButton: View {
    let symbol: String
    let label: String
    var identifier: String
    var enabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme)
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.ink.opacity(enabled ? 1 : 0.4)).frame(width: 40, height: 40)
                .background(palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(palette.hair, lineWidth: 1))
                .frame(width: 48, height: 48).contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
}

/// `.ui-button`: a 40-point pill; primary is an ink fill with page-coloured text, otherwise a 5 % ink fill.
struct BotPillButton: View {
    let title: String
    var symbol: String?
    var primary = false
    var fill = true
    var enabled = true
    var look: MikaVisualPalette.Look = .sheet
    var identifier: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme, look: look)
        let foreground = primary ? palette.background : palette.ink
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 14, weight: .medium)) }
                Text(title).scaledFont(size: 14, weight: .medium).lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16).frame(maxWidth: fill ? .infinity : nil, minHeight: 40)
            .background(primary ? palette.ink : palette.ink.opacity(0.05), in: Capsule())
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }
}

/// The website's search dock: a 44-point pill on the card colour with a hairline; focus draws a 2-point accent ring.
struct BotSearchPill: View {
    @Binding var text: String
    let placeholder: String
    let clearLabel: String
    var identifier: String
    var focused: FocusState<Bool>.Binding
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme)
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .regular)).foregroundStyle(palette.secondaryInk).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(palette.secondaryInk))
                .scaledFont(size: 16).foregroundStyle(palette.ink).tint(palette.accent)
                .focused(focused).submitLabel(.search).onSubmit { focused.wrappedValue = false }
                .accessibilityLabel(placeholder).accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).foregroundStyle(palette.secondaryInk)
                        .frame(width: 28, height: 28).contentShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(focused.wrappedValue ? palette.accent : palette.hair, lineWidth: focused.wrappedValue ? 2 : 1))
    }
}

/// `.field`: a 13-point label over a 16-point input on the inset colour with a hairline and 9-point corners.
struct BotTextField: View {
    let label: String
    @Binding var text: String
    var identifier: String
    var keyboard: UIKeyboardType = .default
    var look: MikaVisualPalette.Look = .sheet
    /// A one-time code (a pairing link) is typed into a secure field and kept out of screenshots.
    var secure = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme, look: look)
        VStack(alignment: .leading, spacing: 7) {
            Text(label).scaledFont(size: 13).foregroundStyle(palette.secondaryInk)
            Group {
                if secure { SecureField("", text: $text).privacySensitive() } else { TextField("", text: $text) }
            }
                .scaledFont(size: 16).foregroundStyle(palette.ink).tint(palette.accent)
                .keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(palette.inset, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(focused ? palette.accent : palette.hair, lineWidth: 1))
                .accessibilityLabel(label).accessibilityIdentifier(identifier)
        }
    }
}

/// The settings switch: a 32 × 20 track, a 16-point knob 2 points in; on = an ink track with a page-coloured knob.
struct BotSwitch: View {
    @Binding var isOn: Bool
    var enabled = true
    let label: String
    var identifier: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme, look: .sheet)
        Button { isOn.toggle() } label: {
            ZStack(alignment: .leading) {
                Capsule().fill(isOn ? palette.ink : palette.ink.opacity(0.22))
                if !isOn { Capsule().strokeBorder(palette.ink.opacity(scheme == .dark ? 0.4 : 0.5), lineWidth: 1) }
                Circle().fill(isOn ? palette.background : Color.white).frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .offset(x: isOn ? 14 : 2)
            }
            .frame(width: 32, height: 20).animation(.easeOut(duration: 0.15), value: isOn)
            .frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityRepresentation {
            Toggle(label, isOn: $isOn).disabled(!enabled).accessibilityIdentifier(identifier)
        }
    }
}

// MARK: Cards and rows

/// `px-2 pb-1 pt-2 text-[12px] font-medium text-ink-secondary`.
struct BotSectionLabel: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text).scaledFont(size: 12, weight: .medium).foregroundStyle(MikaVisualPalette(scheme, look: .sheet).secondaryInk)
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }
}

/// Settings card: 12-point corners on the card colour with the 0.5-point settings edge, rows separated by an edge line.
struct BotCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme, look: .sheet)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity).background(palette.surface, in: shape).clipShape(shape)
            .overlay(shape.strokeBorder(palette.edge, lineWidth: 0.5))
    }
}

struct BotCardDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle().fill(MikaVisualPalette(scheme, look: .sheet).edge).frame(height: 1).padding(.leading, 16)
    }
}

/// The content of a settings row: an optional 20-point icon, a 15 medium title with an optional 13 secondary line, a trailing view.
struct BotRowLabel<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var destructive = false
    @ViewBuilder var trailing: Trailing
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = MikaVisualPalette(scheme, look: .sheet)
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 17, weight: .regular)).frame(width: 20, height: 20)
                    .foregroundStyle(destructive ? palette.destructive : palette.secondaryInk).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).scaledFont(size: 15, weight: .medium).foregroundStyle(destructive ? palette.destructive : palette.ink)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle).scaledFont(size: 13).foregroundStyle(palette.secondaryInk).multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.leading, 16).padding(.trailing, 16).padding(.vertical, 12)
    }
}

extension BotRowLabel where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String? = nil, destructive: Bool = false) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, destructive: destructive, trailing: { EmptyView() })
    }
}

/// A settings row whose text part is the target; `accessory` sits outside the target (a "…" button of its own).
struct BotSettingsRow<Trailing: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var enabled = true
    var destructive = false
    var identifier: String
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 0) {
            let label = BotRowLabel(title: title, subtitle: subtitle, symbol: symbol, destructive: destructive) { trailing }
            if let action {
                Button(action: action) { label.contentShape(Rectangle()) }.buttonStyle(.plain).disabled(!enabled)
                    .accessibilityIdentifier(identifier)
            } else {
                label.accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
            }
            accessory
        }
        .opacity(enabled ? 1 : 0.5)
    }
}

extension BotSettingsRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String? = nil, enabled: Bool = true, destructive: Bool = false,
         identifier: String, action: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, enabled: enabled, destructive: destructive,
                  identifier: identifier, action: action, trailing: trailing, accessory: { EmptyView() })
    }
}
extension BotSettingsRow where Trailing == EmptyView, Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String? = nil, enabled: Bool = true, destructive: Bool = false,
         identifier: String, action: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, enabled: enabled, destructive: destructive,
                  identifier: identifier, action: action, trailing: { EmptyView() }, accessory: { EmptyView() })
    }
}

struct BotChevron: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 14, weight: .regular))
            .foregroundStyle(MikaVisualPalette(scheme, look: .sheet).hintInk).accessibilityHidden(true)
    }
}

// MARK: Progress

/// Android's LinearProgressIndicator (4 dp, full width, accent): the share received, or a bar moving across while the
/// amount is unknown (still with Reduce Motion). Downloads, the service page while it loads, the name and icon page while
/// it saves.
struct BotLinearProgress: View {
    var fraction: Double? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let accent = MikaVisualPalette(scheme).accent
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(accent.opacity(0.2))
                if let fraction {
                    Rectangle().fill(accent).frame(width: proxy.size.width * min(1, max(0, fraction)))
                } else if reduceMotion {
                    Rectangle().fill(accent).frame(width: proxy.size.width * 0.3)
                } else {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        Rectangle().fill(accent).frame(width: proxy.size.width * 0.3)
                            .offset(x: proxy.size.width * (1.3 * phase - 0.3))
                    }
                }
            }
            .clipped()
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: Dialog

/// The popover surface as a modal dialog (Android `MikaDialog`, Direct): menu colour and `--radius-menu` with no outline and
/// no shadow (tonal elevation 0), a 20/26 title, a 14.5/23 body in secondary ink, two pill buttons at 6 % / 10 % ink,
/// destructive in red.
struct BotDialogHost<Dialog: View>: ViewModifier {
    let isPresented: Bool
    let dismiss: () -> Void
    @ViewBuilder let dialog: () -> Dialog
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    // Android's platform dialog dim, 60 % black in both themes (measured on its evidence screenshots:
                    // #FCFCFC behind the delete dialog shows as #656565, #141414 as #080808).
                    Color.black.opacity(0.6).ignoresSafeArea()
                        .onTapGesture(perform: dismiss).accessibilityHidden(true)
                    // A dialog that does not fit (keyboard up, large text) scrolls instead of truncating its text.
                    ViewThatFits(in: .vertical) {
                        dialog().frame(maxWidth: 420)
                        ScrollView { dialog().frame(maxWidth: 420) }.scrollBounceBehavior(.basedOnSize)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape, dismiss)
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isPresented)
    }
}

extension View {
    func botDialog<Dialog: View>(isPresented: Bool, dismiss: @escaping () -> Void, @ViewBuilder dialog: @escaping () -> Dialog) -> some View {
        modifier(BotDialogHost(isPresented: isPresented, dismiss: dismiss, dialog: dialog))
    }
}

struct BotDialogSurface<Content: View>: View {
    var look: MikaVisualPalette.Look = .app
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme, look: look)
        let shape = RoundedRectangle(cornerRadius: palette.menuRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(24)
            .background(palette.menu, in: shape)
    }
}

struct BotDialogTitle: View {
    let text: String
    var size: CGFloat = 20
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text).scaledFont(size: size, weight: .semibold).foregroundStyle(MikaVisualPalette(scheme).ink)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }
}

struct BotDialogBody: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text).scaledFont(size: 14.5).lineSpacing(4).foregroundStyle(MikaVisualPalette(scheme).secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16)
    }
}

/// `DialogAction`: at least 44 tall, 14-point corners, ink at 6 % (dismiss) or 10 % (confirm); labels read in ink.
struct BotDialogButton: View {
    enum Kind { case dismiss, confirm, destructive }
    let title: String
    var kind: Kind = .dismiss
    var look: MikaVisualPalette.Look = .app
    var identifier: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme, look: look)
        Button(action: action) {
            Text(title).scaledFont(size: 14, weight: .medium)
                .foregroundStyle(kind == .destructive ? palette.destructive : palette.ink)
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 8)
                .background(palette.ink.opacity(kind == .dismiss ? 0.06 : 0.1), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }
}

// MARK: Sheet and page

/// A bottom sheet's own chrome (`BotUiSheet`): a 32 × 4 grabber 8 points from the top, a 44-point header with a centred
/// 16/600 title and a close button, then the scrolling content (16 / 6 / 16 / 24 padding, 10 apart), on the settings palette.
/// The system sheet supplies the rise, the 16-point top corners and the drag to dismiss.
struct BotSheetScaffold<Content: View>: View {
    let title: String
    let closeLabel: String
    var closeIdentifier = "bot.sheet.close"
    let close: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme, look: .sheet)
        VStack(spacing: 0) {
            Capsule().fill(palette.ink.opacity(0.15)).frame(width: 32, height: 4).padding(.top, 8)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                Color.clear.frame(width: 44, height: 44)
                Text(title).scaledFont(size: 16, weight: .semibold).foregroundStyle(palette.ink).lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1).frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .regular)).foregroundStyle(palette.ink)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel(closeLabel).accessibilityIdentifier(closeIdentifier)
            }.frame(height: 44).padding(.horizontal, 6)
            ScrollView {
                VStack(spacing: 10) { content }
                    .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.background.ignoresSafeArea())
        .presentationDetents([.large]).presentationDragIndicator(.hidden)
        .presentationCornerRadius(16).presentationBackground(palette.background)
    }
}

/// `BotUiPage`: a full-screen page on the page colour with a title and a round close button (more round buttons may come first).
struct BotPage<Actions: View, Content: View>: View {
    let title: String
    let closeLabel: String
    let close: () -> Void
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(title).scaledFont(size: 17, weight: .semibold).foregroundStyle(palette.ink).lineLimit(1)
                    .padding(.leading, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1).accessibilityAddTraits(.isHeader)
                actions
                BotRoundButton(symbol: "xmark", label: closeLabel, identifier: "bot.page.close", action: close)
            }.padding(.horizontal, 12).padding(.vertical, 8)
            content
        }
        .mikaReadableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.background.ignoresSafeArea())
    }
}

/// A message row: the child is proposed at most `fraction` of the row's width and sits at the trailing edge (Android's
/// `maxWidth * 0.8f` user bubble, right-aligned).
struct BotFractionWidth: Layout {
    let fraction: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let row = proposal.width ?? child.sizeThatFits(.unspecified).width
        let size = child.sizeThatFits(ProposedViewSize(width: row * fraction, height: proposal.height))
        return CGSize(width: row, height: size.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let size = child.sizeThatFits(ProposedViewSize(width: bounds.width * fraction, height: bounds.height))
        child.place(at: CGPoint(x: bounds.maxX - size.width, y: bounds.minY), anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height))
    }
}

extension View {
    /// Applies `transform` only when `condition` holds (a structural conditional, for modifiers that cannot take a flag).
    @ViewBuilder func botIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
#endif
