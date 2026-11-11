import AssistantBrowser
import SwiftUI

/// Matches Mika's browser start-page structure while showing only the data this
/// iOS browser actually stores: encrypted bookmarks and public recent pages.
@MainActor
struct BrowserStartPageView: View {
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var workspace: BrowserWorkspace
    let query: String
    let onSubmit: () -> Void
    let onOpen: (URL) -> Void
    let onManageBookmarks: () -> Void
    @State private var editing = false
    @State private var confirmClearHistory = false
    @State private var showAddHint = false

    private var palette: BrowserPalette { BrowserPalette(colorScheme) }
    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matchingHistory: [BrowserSavedPage] {
        Array(workspace.library.history.lazy.filter {
            $0.title.localizedCaseInsensitiveContains(cleanQuery)
                || $0.url.absoluteString.localizedCaseInsensitiveContains(cleanQuery)
        }.prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if cleanQuery.isEmpty {
                    sectionHeader(localizer.text(.browserBookmarks),
                                  action: localizer.text(editing ? .browserStartDone : .browserStartEdit),
                                  actionID: "browser.favorites.edit") {
                        editing.toggle()
                    }
                    favorites
                    sectionHeader(localizer.text(.browserStartRecent),
                                  action: workspace.library.history.isEmpty ? nil : localizer.text(.browserStartClear),
                                  actionID: "browser.start.history.clear") {
                        confirmClearHistory = true
                    }
                    recent
                } else {
                    suggestions
                    Text(localizer.text(.browserStartSuggestionHelp))
                        .font(.caption).foregroundStyle(palette.tertiary)
                        .frame(maxWidth: .infinity).padding(.top, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(palette.background)
        .accessibilityIdentifier("browser.start")
        .confirmationDialog(localizer.text(.browserClearHistoryQuestion), isPresented: $confirmClearHistory,
                            titleVisibility: .visible) {
            Button(localizer.text(.browserClearHistory), role: .destructive) { workspace.clearHistory() }
                .accessibilityIdentifier("browser.start.history.confirmClear")
        }
        .alert(localizer.text(.browserStartAddBookmark), isPresented: $showAddHint) {
            Button(localizer.text(.browserStartViewBookmarks)) { onManageBookmarks() }
            Button(localizer.text(.browserStartOK), role: .cancel) {}
        } message: {
            Text(localizer.text(.browserStartAddBookmarkHelp))
        }
    }

    private func sectionHeader(_ title: String, action: String?, actionID: String,
                               perform: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.secondary)
            Spacer()
            if let action {
                Button(action, action: perform)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier(actionID)
            }
        }
        .padding(.top, 18).padding(.bottom, 10)
    }

    private var favorites: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
            ForEach(workspace.library.bookmarks) { page in
                ZStack(alignment: .topLeading) {
                    Button {
                        if !editing { onOpen(page.url) }
                    } label: {
                        VStack(spacing: 7) {
                            siteTile(page.url.host ?? "", size: 54)
                            Text(page.title).font(.caption).foregroundStyle(palette.secondary)
                                .lineLimit(1).frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("browser.favorite.open.\(page.id)")
                    if editing {
                        Button(role: .destructive) { workspace.removeBookmark(page.id) } label: {
                            Image(systemName: "xmark").font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 23, height: 23).background(palette.secondary, in: Circle())
                        }
                        .accessibilityLabel(localizer.text(.browserStartRemoveBookmark(name: page.title)))
                        .accessibilityIdentifier("browser.favorite.remove.\(page.id)")
                        .offset(x: -5, y: -5)
                    }
                }
            }
            if !editing {
                Button { showAddHint = true } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "plus").font(.title3)
                            .frame(width: 54, height: 54)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.edge, lineWidth: 0.5))
                        Text(localizer.text(.browserStartAdd)).font(.caption).foregroundStyle(palette.secondary)
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain).accessibilityIdentifier("browser.favorites.add")
            }
        }
        .accessibilityIdentifier("browser.favorites")
    }

    // Keep identifiers on the content rows: iOS 26 exposes the empty Text as
    // this container's element when a container identifier is set here.
    private var recent: some View {
        VStack(spacing: 0) {
            if workspace.library.history.isEmpty {
                Text(localizer.text(.browserNoHistory))
                    .font(.subheadline).foregroundStyle(palette.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .accessibilityIdentifier("browser.start.history.empty")
            }
            ForEach(Array(workspace.library.history.prefix(20))) { page in
                if page.id != workspace.library.history.first?.id { Divider().padding(.leading, 56) }
                historyRow(page)
            }
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.edge, lineWidth: 0.5))
    }

    private var suggestions: some View {
        VStack(spacing: 0) {
            Button(action: onSubmit) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cleanQuery).lineLimit(1).foregroundStyle(palette.primary)
                        Text(localizer.text(.browserStartSuggestionSubtitle)).font(.caption).foregroundStyle(palette.tertiary)
                    }
                    Spacer()
                }.padding(.horizontal, 16).frame(minHeight: 56)
            }
            .buttonStyle(.plain).accessibilityIdentifier("browser.suggestion.submit")
            ForEach(matchingHistory) { page in
                Divider().padding(.leading, 56)
                historyRow(page)
            }
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.edge, lineWidth: 0.5))
        .padding(.top, 10)
        .accessibilityIdentifier("browser.suggestions")
    }

    private func historyRow(_ page: BrowserSavedPage) -> some View {
        Button { onOpen(page.url) } label: {
            HStack(spacing: 12) {
                if workspace.library.searchSettings.match(page.url) != nil {
                    Image(systemName: "magnifyingglass").font(.caption)
                        .frame(width: 28, height: 28).background(palette.neutral, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    siteTile(page.url.host ?? "", size: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let match = workspace.library.searchSettings.match(page.url) {
                        Text(localizer.text(.browserHistorySearch(query: match.query))).lineLimit(1)
                        Text(match.engineName).font(.caption).foregroundStyle(palette.tertiary)
                    } else {
                        Text(page.title).lineLimit(1)
                        Text(page.url.host ?? "").font(.caption).foregroundStyle(palette.tertiary).lineLimit(1)
                    }
                }
                .foregroundStyle(palette.primary)
                Spacer(minLength: 4)
                Text(page.date, style: .relative).font(.caption2)
                    .foregroundStyle(palette.tertiary).lineLimit(1)
            }
            .padding(.horizontal, 16).frame(minHeight: 56)
        }
        .buttonStyle(.plain).accessibilityIdentifier("browser.start.history.open.\(page.id)")
    }

    private func siteTile(_ host: String, size: CGFloat) -> some View {
        let colors: [Color] = [.blue, .teal, .indigo, .orange, .purple, .green]
        let index = host.utf8.reduce(0) { ($0 * 31 + Int($1)) % colors.count }
        return Text(String(host.prefix(1)).uppercased())
            .font(.system(size: size > 40 ? 20 : 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(colors[index], in: RoundedRectangle(cornerRadius: size > 40 ? 16 : 8))
    }
}

struct BrowserPalette {
    let background: Color
    let surface: Color
    let neutral: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let edge: Color

    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        background = dark ? Color(red: 14.0/255, green: 14.0/255, blue: 16.0/255)
                          : Color(red: 247.0/255, green: 247.0/255, blue: 248.0/255)
        surface = dark ? Color(red: 26.0/255, green: 26.0/255, blue: 29.0/255) : .white
        neutral = dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
        primary = dark ? Color(red: 242.0/255, green: 242.0/255, blue: 244.0/255)
                       : Color(red: 28.0/255, green: 28.0/255, blue: 30.0/255)
        secondary = dark ? Color(red: 164.0/255, green: 165.0/255, blue: 173.0/255)
                         : Color(red: 95.0/255, green: 96.0/255, blue: 104.0/255)
        tertiary = dark ? Color(red: 108.0/255, green: 109.0/255, blue: 117.0/255)
                        : Color(red: 154.0/255, green: 155.0/255, blue: 163.0/255)
        edge = dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }
}
