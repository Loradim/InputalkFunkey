import InputalkFunkeyCore
import SwiftUI

@MainActor
final class PromptSnippetsCloseCoordinator {
    var shouldClose: (() -> Bool)?
    var closeWindow: (() -> Void)?

    private var allowNextClose = false

    func requestClose() -> Bool {
        if allowNextClose {
            allowNextClose = false
            return true
        }

        return shouldClose?() ?? true
    }

    func closeAfterConfirmation() {
        allowNextClose = true
        closeWindow?()
    }
}

struct PromptSnippetsView: View {
    @ObservedObject var store: PromptSnippetStore
    let closeCoordinator: PromptSnippetsCloseCoordinator

    @State private var selectedSnippetID: PromptSnippet.ID?
    @State private var draft: PromptSnippetDraft?
    @State private var baselineDraft: PromptSnippetDraft?
    @State private var saveErrorMessage: String?
    @State private var pendingAction: PendingDraftAction?
    @State private var isShowingUnsavedChangesDialog = false
    @State private var snippetPendingDeletion: PromptSnippet?
    @State private var isShowingDeleteDialog = false

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)

            rightPane
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 460)
        .confirmationDialog(
            "Unsaved Changes",
            isPresented: $isShowingUnsavedChangesDialog,
            titleVisibility: .visible,
            actions: unsavedChangesDialogActions,
            message: {
                Text(unsavedChangesDialogMessage)
            }
        )
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: $isShowingDeleteDialog,
            titleVisibility: .visible,
            actions: {
                Button("Delete", role: .destructive, action: confirmDeleteSnippet)
                Button("Cancel", role: .cancel) {
                    snippetPendingDeletion = nil
                }
            },
            message: {
                Text("This removes the title, shortcut, and prompt text. This cannot be undone.")
            }
        )
        .onAppear(perform: updateCloseHandler)
        .onChange(of: draft) { _, _ in updateCloseHandler() }
        .onChange(of: baselineDraft) { _, _ in updateCloseHandler() }
        .onDisappear {
            closeCoordinator.shouldClose = nil
        }
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Snippets")
                    .font(.headline)
                Spacer()
                Button("New Snippet", action: attemptCreateDraft)
                    .controlSize(.small)
            }

            snippetListContainer
        }
        .padding(16)
    }

    @ViewBuilder
    private var snippetListContainer: some View {
        Group {
            if store.snippets.isEmpty {
                ContentUnavailableView(
                    "No prompt snippets yet",
                    systemImage: "text.badge.plus",
                    description: Text("Create a snippet to assign an Fn shortcut.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: snippetSelection) {
                    ForEach(store.snippets) { snippet in
                        PromptSnippetRow(snippet: snippet)
                            .tag(snippet.id)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var rightPane: some View {
        if draft != nil {
            PromptSnippetEditor(
                draft: Binding(
                    get: { draft ?? PromptSnippetDraft(displayOrder: store.nextDisplayOrder()) },
                    set: { draft = $0 }
                ),
                existingSnippets: store.snippets,
                saveErrorMessage: saveErrorMessage,
                onSave: saveDraft,
                onCancel: cancelDraft,
                onDelete: requestDeleteSnippet
            )
        } else {
            ContentUnavailableView(
                "No snippet selected",
                systemImage: "text.cursor",
                description: Text("Select a snippet or create a new one.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var snippetSelection: Binding<PromptSnippet.ID?> {
        Binding(
            get: { selectedSnippetID },
            set: { newValue in attemptAction(.select(newValue)) }
        )
    }

    private var hasUnsavedChanges: Bool {
        draft?.hasUnsavedChanges(comparedTo: baselineDraft) ?? false
    }

    private var currentValidation: PromptSnippetValidationResult {
        guard let draft else {
            return PromptSnippetValidationResult(issues: [])
        }
        return PromptSnippetValidator.validate(draft: draft, existing: store.snippets)
    }

    private var unsavedChangesDialogMessage: String {
        if currentValidation.isValid {
            return "Save changes before continuing?"
        }

        let explanation = currentValidation.issues.first?
            .saveUnavailableExplanation(trigger: draft?.trigger)
            ?? "the draft is invalid"
        return "This snippet cannot be saved because \(explanation)."
    }

    private var deleteDialogTitle: String {
        guard let snippetPendingDeletion else {
            return "Delete Snippet?"
        }
        return "Delete \"\(displayTitle(for: snippetPendingDeletion))\"?"
    }

    private func attemptCreateDraft() {
        attemptAction(.createNew)
    }

    private func createDraft() {
        let newDraft = PromptSnippetDraft(displayOrder: store.nextDisplayOrder())
        selectedSnippetID = nil
        saveErrorMessage = nil
        draft = newDraft
        baselineDraft = newDraft
    }

    private func attemptAction(_ action: PendingDraftAction) {
        if hasUnsavedChanges {
            pendingAction = action
            isShowingUnsavedChangesDialog = true
        } else {
            perform(action)
        }
    }

    private func perform(_ action: PendingDraftAction) {
        switch action {
        case .createNew:
            createDraft()
        case .select(let id):
            selectSnippet(id: id)
        case .closeWindow:
            closeCoordinator.closeAfterConfirmation()
        }
    }

    private func selectSnippet(id: PromptSnippet.ID?) {
        guard let id, let snippet = store.snippets.first(where: { $0.id == id }) else {
            return
        }
        saveErrorMessage = nil
        let selectedDraft = PromptSnippetDraft(snippet: snippet)
        selectedSnippetID = id
        draft = selectedDraft
        baselineDraft = selectedDraft
    }

    private func saveDraft() {
        _ = saveCurrentDraft()
    }

    @discardableResult
    private func saveCurrentDraft() -> Bool {
        guard let draft else { return false }

        do {
            let saved = try store.save(draft: draft)
            selectedSnippetID = saved.id
            let savedDraft = PromptSnippetDraft(snippet: saved)
            self.draft = savedDraft
            baselineDraft = savedDraft
            saveErrorMessage = nil
            return true
        } catch PromptSnippetStoreError.draftValidationFailed(let issues) {
            saveErrorMessage = issues
                .map { $0.message(trigger: draft.trigger) }
                .joined(separator: "\n")
        } catch {
            saveErrorMessage = "The snippet could not be saved."
        }

        return false
    }

    private func cancelDraft() {
        saveErrorMessage = nil

        guard let draft else { return }
        if let saved = store.snippets.first(where: { $0.id == draft.id }) {
            let savedDraft = PromptSnippetDraft(snippet: saved)
            self.draft = savedDraft
            baselineDraft = savedDraft
            selectedSnippetID = saved.id
        } else {
            self.draft = nil
            baselineDraft = nil
            selectedSnippetID = nil
        }
    }

    private func requestWindowClose() -> Bool {
        guard hasUnsavedChanges else { return true }

        pendingAction = .closeWindow
        isShowingUnsavedChangesDialog = true
        return false
    }

    private func updateCloseHandler() {
        closeCoordinator.shouldClose = {
            requestWindowClose()
        }
    }

    @ViewBuilder
    private func unsavedChangesDialogActions() -> some View {
        if currentValidation.isValid {
            Button("Save", action: savePendingChangesAndPerform)
        }
        Button("Keep Editing", role: .cancel) {
            pendingAction = nil
        }
        Button("Discard", role: .destructive, action: discardPendingChangesAndPerform)
    }

    private func savePendingChangesAndPerform() {
        guard let action = pendingAction else { return }
        if saveCurrentDraft() {
            pendingAction = nil
            perform(action)
        }
    }

    private func discardPendingChangesAndPerform() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        saveErrorMessage = nil
        perform(action)
    }

    private func requestDeleteSnippet() {
        guard let id = draft?.id,
            let snippet = store.snippets.first(where: { $0.id == id })
        else { return }

        snippetPendingDeletion = snippet
        isShowingDeleteDialog = true
    }

    private func confirmDeleteSnippet() {
        guard let snippet = snippetPendingDeletion else { return }

        do {
            try store.deleteSnippet(id: snippet.id)
            if draft?.id == snippet.id {
                draft = nil
                baselineDraft = nil
                selectedSnippetID = nil
            }
            snippetPendingDeletion = nil
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "The snippet could not be deleted."
        }
    }

    private func displayTitle(for snippet: PromptSnippet) -> String {
        snippet.title.isEmpty ? "Untitled Snippet" : snippet.title
    }
}

private enum PendingDraftAction: Equatable {
    case createNew
    case select(PromptSnippet.ID?)
    case closeWindow
}

private struct PromptSnippetRow: View {
    let snippet: PromptSnippet

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(snippet.isEnabled ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(snippet.title.isEmpty ? "Untitled Snippet" : snippet.title)
                    .font(.body)
                    .lineLimit(1)
                Text(snippet.trigger?.displayLabel ?? "No shortcut")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PromptSnippetEditor: View {
    @Binding var draft: PromptSnippetDraft

    let existingSnippets: [PromptSnippet]
    let saveErrorMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    private let formLabelWidth: CGFloat = 68

    private var validation: PromptSnippetValidationResult {
        PromptSnippetValidator.validate(draft: draft, existing: existingSnippets)
    }

    private var canDelete: Bool {
        existingSnippets.contains { $0.id == draft.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Title")
                        .frame(width: formLabelWidth, alignment: .leading)
                    TextField("Title", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(alignment: .center, spacing: 10) {
                    Text("Shortcut")
                        .frame(width: formLabelWidth, alignment: .leading)

                    Picker("Shortcut", selection: $draft.trigger) {
                        Text("No shortcut").tag(SnippetTrigger?.none)
                        ForEach(SnippetKey.fnNumberTriggers, id: \.self) { trigger in
                            shortcutOption(for: trigger)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260, alignment: .leading)

                    Spacer()

                    Toggle(isOn: $draft.isEnabled) {
                        AnimatedEnabledStateLabel(isEnabled: draft.isEnabled)
                    }
                        .toggleStyle(.switch)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt Text")
                        .font(.headline)
                    TextEditor(text: $draft.text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 190)
                        .padding(6)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        }
                }

                validationMessages

                HStack {
                    Button("Delete Snippet...", action: onDelete)
                        .disabled(!canDelete)
                    Spacer()
                    Button("Cancel", action: onCancel)
                    Button("Save", action: onSave)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!validation.isValid)
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var validationMessages: some View {
        if !validation.issues.isEmpty || saveErrorMessage != nil {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(validation.issues.enumerated()), id: \.offset) { _, issue in
                    Label(issue.message(trigger: draft.trigger), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if let saveErrorMessage {
                    Text(saveErrorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func shortcutOption(for trigger: SnippetTrigger) -> some View {
        if let conflict = conflictingSnippet(for: trigger) {
            Text("\(trigger.displayLabel) - used by \(displayTitle(for: conflict))")
                .foregroundStyle(.secondary)
                .tag(Optional(trigger))
                .disabled(true)
        } else {
            Text(trigger.displayLabel)
                .tag(Optional(trigger))
        }
    }

    private func conflictingSnippet(for trigger: SnippetTrigger) -> PromptSnippet? {
        existingSnippets.first {
            $0.id != draft.id && $0.isEnabled && $0.trigger == trigger
        }
    }

    private func displayTitle(for snippet: PromptSnippet) -> String {
        snippet.title.isEmpty ? "Untitled Snippet" : snippet.title
    }
}

private struct AnimatedEnabledStateLabel: View {
    let isEnabled: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Text("Enabled")
                .opacity(isEnabled ? 1 : 0)
                .offset(y: isEnabled ? 0 : -8)

            Text("Disabled")
                .opacity(isEnabled ? 0 : 1)
                .offset(y: isEnabled ? 8 : 0)
        }
        .frame(width: 64, height: 20, alignment: .leading)
        .clipped()
        .animation(.easeInOut(duration: 0.18), value: isEnabled)
        .accessibilityLabel(isEnabled ? "Enabled" : "Disabled")
    }
}
