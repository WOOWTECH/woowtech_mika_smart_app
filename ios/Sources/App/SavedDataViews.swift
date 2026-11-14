import SwiftUI
import WebKit

/// Play's 網站登入 page (WebSitesSection): the sites the built-in browser has
/// data for, sign out of one, or sign out of all and clear web data. Shown over
/// the browser: WebKit only lists its records while a web view is on screen.
@MainActor
struct WebsiteSignInsView: View {
    @ObservedObject var workspace: BrowserWorkspace
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.dismiss) private var dismiss
    @State private var picked: WKWebsiteDataRecord?
    @State private var confirmAll = false
    @State private var notice: String?

    private var copy: MemoryDataCopy { MemoryDataCopy(language: localizer.language) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if workspace.websiteRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(copy.text(.signInsNone))
                            Text(copy.text(.signInsNoneDetail)).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("signIns.empty")
                    }
                    ForEach(workspace.websiteRecords, id: \.displayName) { record in
                        Button { picked = record } label: {
                            HStack {
                                Image(systemName: "globe").foregroundStyle(.secondary).accessibilityHidden(true)
                                Text(record.displayName).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                Text(copy.text(.signInsManage)).font(.subheadline)
                            }
                        }
                        .disabled(workspace.isClearingWebsiteData)
                        .accessibilityIdentifier("signIns.site." + record.displayName)
                    }
                    Button(role: .destructive) { confirmAll = true } label: {
                        Text(copy.text(.signInsAllTitle))
                    }
                    .disabled(workspace.websiteRecords.isEmpty || workspace.isClearingWebsiteData)
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
            .onAppear { workspace.refreshWebsiteRecords() }
            .confirmationDialog(picked?.displayName ?? "", isPresented: Binding(
                get: { picked != nil }, set: { if !$0 { picked = nil } }
            ), titleVisibility: .visible, presenting: picked) { record in
                Button(copy.text(.signInsSignOutSite), role: .destructive) {
                    workspace.removeWebsiteData([record])
                    notice = copy.text(.signInsSignedOut, record.displayName)
                    picked = nil
                }
                .accessibilityIdentifier("signIns.signOutSite")
                Button(copy.text(.cancel), role: .cancel) { picked = nil }
            } message: { _ in
                Text(copy.text(.signInsVisited))
            }
            .alert(copy.text(.signInsAllQuestion), isPresented: $confirmAll) {
                Button(copy.text(.signInsAll), role: .destructive) {
                    workspace.removeWebsiteData(workspace.websiteRecords)
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
