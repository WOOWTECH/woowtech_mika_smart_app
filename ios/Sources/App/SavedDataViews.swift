import AssistantBrowser
import SwiftUI
import WebKit

/// Play's 網站登入 page (WebSitesSection): the sites you signed in to in the
/// built-in browser, signed-in ones first, each with its state and last visit;
/// open its sign-in, sign out of one, or sign out of all and clear web data.
/// The list is App data; it is shown over the browser because removing
/// WebKit's records needs a live web view.
@MainActor
struct WebsiteSignInsView: View {
    @ObservedObject var workspace: BrowserWorkspace
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.dismiss) private var dismiss
    @State private var picked: BrowserSignInSite?
    @State private var confirmAll = false
    @State private var notice: String?

    private var copy: MemoryDataCopy { MemoryDataCopy(language: localizer.language) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if workspace.signInSites.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(copy.text(.signInsNone))
                            Text(copy.text(.signInsNoneDetail)).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("signIns.empty")
                    }
                    ForEach(workspace.signInSites) { site in
                        Button { picked = site } label: {
                            HStack {
                                Image(systemName: "globe").foregroundStyle(.secondary).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: site.host).foregroundStyle(.primary)
                                    Text(subtitle(site)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(copy.text(.signInsManage)).font(.subheadline)
                            }
                        }
                        .disabled(workspace.isClearingWebsiteData)
                        .accessibilityIdentifier("signIns.site." + site.host)
                    }
                    Button(role: .destructive) { confirmAll = true } label: {
                        Text(copy.text(.signInsAllTitle))
                    }
                    .disabled(workspace.isClearingWebsiteData)
                    .accessibilityIdentifier("signIns.signOutAll")
                } footer: {
                    Text(copy.text(.signInsNote)).accessibilityIdentifier("signIns.note")
                }
                if workspace.isClearingWebsiteData {
                    ProgressView().accessibilityIdentifier("signIns.clearing")
                }
            }
            .navigationTitle(copy.text(.webLogins))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.text(.done)) { dismiss() }.accessibilityIdentifier("signIns.close")
                }
            }
            .confirmationDialog(picked?.host ?? "", isPresented: Binding(
                get: { picked != nil }, set: { if !$0 { picked = nil } }
            ), titleVisibility: .visible, presenting: picked) { site in
                Button(copy.text(.signInsOpenLogin)) {
                    picked = nil
                    openSignIn(site)
                }
                .accessibilityIdentifier("signIns.openLogin")
                Button(copy.text(.signInsSignOutSite), role: .destructive) {
                    workspace.signOut(site: site)
                    notice = copy.text(.signInsSignedOut, site.host)
                    picked = nil
                }
                .accessibilityIdentifier("signIns.signOutSite")
                Button(copy.text(.cancel), role: .cancel) { picked = nil }
            } message: { site in
                Text(copy.text(site.signedIn ? .signInsYouSignedIn : .signInsWasSignedIn))
            }
            .alert(copy.text(.signInsAllQuestion), isPresented: $confirmAll) {
                Button(copy.text(.signInsAll), role: .destructive) {
                    workspace.signOutAll()
                    notice = copy.text(.signInsAllDone)
                }
                .accessibilityIdentifier("signIns.confirmSignOutAll")
                Button(copy.text(.cancel), role: .cancel) {}
            } message: {
                Text(copy.text(.signInsAllBody))
            }
            .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button(copy.text(.done)) { notice = nil }.accessibilityIdentifier("signIns.notice.done")
            }
        }
    }

    /// Play's row subtitle: 在渥屋助理裡登入過 · 最近造訪 11/14.
    private func subtitle(_ site: BrowserSignInSite) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: copy.language.rawValue)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        let state = copy.text(site.signedIn ? .signInsSignedInByYou : .signInsLooksSignedOut)
        return state + " · " + copy.text(.signInsLastVisit, formatter.string(from: site.lastVisit))
    }

    /// Play's 開啟登入: open the site in the browser to sign in again.
    private func openSignIn(_ site: BrowserSignInSite) {
        guard let url = URL(string: "https://" + site.host + "/") else { return }
        dismiss()
        workspace.open(url)
    }
}

/// Play's 記住的操作路線 page (RoutesScreen): how many routes are saved, and clear all.
@MainActor
struct SavedRoutesView: View {
    @ObservedObject var store: LearningStore
    @Environment(\.appLocalizer) private var localizer
    @State private var confirmClear = false

    private var copy: MemoryDataCopy { MemoryDataCopy(language: localizer.language) }
    private var count: Int { store.routes.routes.count }

    var body: some View {
        List {
            HStack {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.text(.routesSaved))
                    Text(copy.text(.routeCountDetail, Int64(count))).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("routes.count")
                }
                Spacer(minLength: 8)
                if count > 0 {
                    Button(copy.text(.routesClearAll), role: .destructive) { confirmClear = true }
                        .buttonStyle(.borderless)
                        .disabled(!store.available)
                        .accessibilityIdentifier("routes.clearAll")
                }
            }
        }
        .navigationTitle(copy.text(.routeTitle))
        .navigationBarTitleDisplayMode(.inline)
        .alert(copy.text(.routesClearTitle), isPresented: $confirmClear) {
            Button(copy.text(.clear), role: .destructive) {
                store.mutateWeb { _, routes in routes.clear() }
            }
            .accessibilityIdentifier("routes.confirmClear")
            Button(copy.text(.cancel), role: .cancel) {}
        } message: {
            Text(copy.text(.routesClearBody))
        }
    }
}
