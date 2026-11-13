import AssistantBrowser
import SwiftUI

@MainActor
struct BrowserSearchSettingsView: View {
    @Environment(\.appLocalizer) private var localizer
    @ObservedObject var workspace: BrowserWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var template = ""
    private enum Field { case name, template }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section(localizer.text(.searchTitle)) {
                        ForEach(workspace.library.searchSettings.all) { engine in
                            HStack {
                                Button { workspace.selectSearchEngine(engine.id) } label: {
                                    HStack {
                                        Text(engine.name)
                                        Spacer()
                                        if workspace.library.searchSettings.selectedID == engine.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }.accessibilityIdentifier("browser.searchEngine.select.\(engine.id)")
                                    .accessibilityValue(workspace.library.searchSettings.selectedID == engine.id ? localizer.text(.commonSelected) : localizer.text(.commonUnselected))
                                if engine.id.hasPrefix("custom:") {
                                    Button(localizer.text(.commonDelete), role: .destructive) { workspace.removeSearchEngine(engine.id) }
                                        .accessibilityLabel(localizer.text(.commonDeleteName(name: engine.name)))
                                        .accessibilityIdentifier("browser.searchEngine.remove.\(engine.id)")
                                }
                            }.buttonStyle(.borderless)
                        }
                    }
                    Section(localizer.text(.searchCustom)) {
                        TextField(localizer.text(.commonName), text: $name).autocorrectionDisabled()
                            .focused($focusedField, equals: .name).submitLabel(.next)
                            .onSubmit { focusedField = .template }
                            .accessibilityIdentifier("browser.searchEngine.name")
                            .id(Field.name)
                        TextField(localizer.text(.searchTemplate), text: $template)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .focused($focusedField, equals: .template).submitLabel(.done)
                            .onSubmit { focusedField = nil }
                            .accessibilityIdentifier("browser.searchEngine.template")
                            .id(Field.template)
                        Text(localizer.text(.searchHelp))
                            .font(.caption)
                        Button(localizer.text(.searchAdd)) {
                            focusedField = nil
                            if workspace.addSearchEngine(name: name, template: template) { name = ""; template = "" }
                        }.accessibilityIdentifier("browser.searchEngine.add")
                    }
                    if let error = workspace.errorText {
                        Text(localizer.text(error)).foregroundStyle(.red).accessibilityIdentifier("browser.searchEngine.error")
                    }
                    Text(localizer.text(.searchChanges))
                        .font(.caption)
                }
                .scrollDismissesKeyboard(.interactively)
                // The Form does not always lift a focused row above the
                // keyboard: on iPhone SE (iOS 18.5 CI) the name field stayed
                // at 419.5-463.5 pt for about 5 s while the keyboard began at
                // 451 pt. Bring the focused field to the upper quarter when
                // focus moves, and again once the keyboard is up and its inset
                // lets the Form scroll that far.
                .onChange(of: focusedField) { _, field in reveal(field, with: proxy) }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    reveal(focusedField, with: proxy)
                }
                .disabled(!workspace.available || workspace.isClearingWebsiteData)
                .navigationTitle(localizer.text(.searchTitle))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }.accessibilityIdentifier("browser.searchEngine.close")
                    }
                }
            }
        }
    }

    private func reveal(_ field: Field?, with proxy: ScrollViewProxy) {
        guard let field else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(field, anchor: UnitPoint(x: 0.5, y: 0.25))
        }
    }
}
