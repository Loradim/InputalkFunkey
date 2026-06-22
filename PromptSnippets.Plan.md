# Prompt Snippets Plan

## Goal

Add configurable prompt snippets that can be inserted into the currently focused text field with quick Fn-based shortcuts.

For the MVP, snippets are inserted with `Fn + 1` through `Fn + 9`. The implementation should keep the model and lookup path open enough to support other Fn combinations later.

## Product Rules

- `Fn + number` inserts the configured snippet text at the current cursor focus.
- Snippet insertion must not submit, send, or press Enter.
- Snippet insertion must preserve and restore the clipboard using the same behavior as transcription insertion.
- Snippet shortcuts are quick Fn chords. Once recording starts, recording always wins over snippet insertion.
- Empty initial state: no default snippets are created.
- Snippets are managed inside the app, not by manually editing UserDefaults or files.

## Testing And Refactoring Rule

When an implementation slice needs to change existing behavior or refactor existing code, write characterization tests or behavioral tests before making that change.

The tests should capture the current expected behavior first. After the refactor or feature change:

- unchanged behavior must still pass
- intentionally changed behavior must fail only for the expected reason before being updated
- fixes must preserve the characterized behavior unless the plan explicitly changes it

This rule is especially important for the Fn state machine, existing hold-to-talk behavior, double-tap hands-free behavior, `Fn + V` paste-last behavior, and clipboard-preserving insertion.

## Shortcut Behavior

### Allowed Insertion State

Snippet shortcuts only fire while Fn is in the pending state, before recording starts.

Expected behavior:

- `Fn down` enters the existing pending state.
- If the user presses `1...9` before the hold threshold starts recording:
  - cancel the pending recording gesture
  - look up the snippet by configured trigger
  - insert the snippet if valid and enabled
  - show `No prompt assigned` if no matching usable snippet exists
  - wait for Fn release before returning to idle
- If hold-to-talk recording has already started, `Fn + number` must not insert a snippet and must not cancel recording.
- If hands-free recording is active, `Fn + number` must not insert a snippet and must not cancel recording.
- If transcription is processing, snippet shortcuts should not insert text.

The safety rule is:

```text
Never discard an active recording for snippet insertion.
```

### Empty Or Unusable Shortcut

When a shortcut has no usable assigned snippet, show the existing temporary overlay style with:

```text
No prompt assigned
```

A snippet is not usable for insertion when:

- no snippet exists for the trigger
- the snippet is disabled
- the snippet has no prompt text

The store/validator should prevent enabled snippets with empty prompt text, but lookup should still fail safely.

## Data Model

Use separate model, draft, validation, and persistence files so the business rules are easy to find.

Proposed source files:

- `PromptSnippet.swift`
- `PromptSnippetDraft.swift`
- `PromptSnippetValidator.swift`
- `PromptSnippetStore.swift`
- `PromptSnippetsWindow.swift` or `PromptSnippetsView.swift`

Proposed model shape:

```swift
struct PromptSnippet: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var text: String
    var trigger: SnippetTrigger?
    var displayOrder: Int
    var isEnabled: Bool
}

enum SnippetTrigger: Codable, Equatable, Hashable, Sendable {
    case fnKey(SnippetKey)
}

struct SnippetKey: Codable, Equatable, Hashable, Sendable {
    var keyCode: Int
}
```

Notes:

- `trigger` is optional so a snippet can exist without a shortcut.
- `displayOrder` controls the editor list order, not shortcut behavior.
- `SnippetTrigger` is the trigger identity. Labels such as `Fn + 1` should be computed from the key code, not stored as part of identity.
- The hotkey path should match key events against configured triggers rather than hard-coding `1...9` insertion logic.

## Persistence

Use `UserDefaults` for the MVP, but store snippets as one encoded collection rather than scattered keys.

Suggested key:

```swift
Defaults.promptSnippets = "promptSnippets"
```

Rules:

- Initial state is an empty array.
- If the `promptSnippets` key is missing, the app must continue normally and return an empty snippet list.
- If the `promptSnippets` value is present but cannot be decoded, the app must continue normally and return an empty snippet list.
- If loaded snippets decode but contain invalid enabled entries, the store should keep them visible but force those invalid entries to `isEnabled = false`.
- Store validates before saving.
- Store exposes lookup by trigger for the hotkey path.
- Store preserves snippet order with `displayOrder`.
- Future migration to an Application Support JSON file should be possible without changing the editor or hotkey logic.

## Validation

Validation must follow DRY strictly: the rule for whether a snippet draft can be saved lives in one validation component.

The editor may ask the validation layer for results, but it must not own validation rules.

The store must also use the same validation before persisting.

Validation rules:

- Title is required for enabled snippets.
- Prompt text is required for enabled snippets.
- No shortcut is allowed.
- Duplicate shortcut triggers are not allowed among enabled snippets.
- A snippet may keep its own current shortcut.
- A snippet may change to a shortcut that is not used by another enabled snippet.
- A snippet may clear its shortcut.
- A disabled snippet does not reserve its shortcut.
- Two disabled snippets may have the same shortcut.
- One enabled snippet and one or more disabled snippets may have the same shortcut.
- Two enabled snippets may not have the same shortcut.
- Enabling a snippet validates that no other enabled snippet already uses the same shortcut.
- Disabled snippets may be saved even if title or prompt text would otherwise be invalid, but they are never usable for insertion.

Validation should return enough detail for UI messages.

Example issue cases:

```swift
enum PromptSnippetValidationIssue: Equatable, Sendable {
    case emptyTitle
    case emptyText
    case duplicateEnabledTrigger(conflictingTitle: String)
}
```

Example user-facing messages:

- `Title is required before this snippet can be enabled.`
- `Prompt text is required before this snippet can be enabled.`
- `Fn + 1 is already used by enabled snippet "Code Review".`

## Prompt Snippets Window

Add a menu item:

```text
Prompt Snippets...
```

This opens a separate resizable window titled:

```text
Prompt Snippets
```

Do not put the editor inside the existing Settings window.

### Layout

Use a two-pane layout.

Left pane:

- list of snippets by title
- currently assigned shortcut, such as `Fn + 1` or `No shortcut`
- enabled/disabled status indicator, for example a small green check indicator for enabled snippets
- `New Snippet` button
- empty state when no snippets exist

Optional later:

- one-line prompt preview

Right pane:

- title field
- shortcut picker
- enabled toggle
- large scrollable prompt text editor
- inline validation messages
- `Remove Shortcut` button
- `Delete Snippet...` button
- `Save` button
- `Cancel` button

### Shortcut Picker

For MVP, use a constrained picker:

- `No shortcut`
- `Fn + 1`
- `Fn + 2`
- `Fn + 3`
- `Fn + 4`
- `Fn + 5`
- `Fn + 6`
- `Fn + 7`
- `Fn + 8`
- `Fn + 9`

Do not implement a free shortcut recorder in the MVP.

The picker should show all supported shortcuts. Shortcuts used by another enabled snippet should be visible but disabled/grayed out, with enough context to identify the active snippet that owns the shortcut.

Shortcuts used only by disabled snippets remain selectable.

The data model and lookup path should still support adding other Fn-key combinations later.

## Editing Behavior

Use a draft model for editing.

Rules:

- The saved snippet is not mutated while the user edits.
- The editor modifies a `PromptSnippetDraft`.
- Save validates the draft, converts it to `PromptSnippet`, and persists.
- Cancel discards the draft and returns to the saved state.
- Remove Shortcut clears the draft trigger immediately and does not require confirmation.
- Delete Snippet requires confirmation.

### Required Fields

Saving is disabled or blocked when:

- an enabled snippet has an empty title
- an enabled snippet has empty prompt text
- an enabled snippet's shortcut trigger duplicates another enabled snippet

No shortcut is valid.

## Unsaved Changes Behavior

When the user selects a different snippet while the current draft has unsaved changes:

If the draft is valid, show a confirmation dialog with:

- `Save`
- `Keep Editing` with cancel role
- `Discard` with destructive role

If the draft is invalid, show a confirmation dialog with:

- `Keep Editing` with cancel role
- `Discard` with destructive role

The same flow applies when the user tries to close the Prompt Snippets window with unsaved changes.

The invalid dialog must explain why Save is not available.

Example:

```text
This snippet cannot be saved because Fn + 1 is already used by "Code Review".
```

or:

```text
This snippet cannot be saved because the prompt text is empty.
```

## Destructive Actions

Delete snippet requires confirmation and must use SwiftUI's destructive role.

Example:

```text
Delete "Code Review"?
This removes the title, shortcut, and prompt text. This cannot be undone.
```

Buttons:

- `Delete` with destructive role
- `Cancel` with cancel role

Remove Shortcut does not require confirmation.

## Vertical Implementation Slices

### Slice 1: Model, Store, And Validation

Goal:

Create the snippet model, draft model, validator, and persistent store without UI or hotkey behavior.

Acceptance criteria:

- Snippets encode/decode through Codable.
- Store starts empty on first launch.
- Store returns an empty array when the `promptSnippets` UserDefaults key is missing.
- Store returns an empty array when the `promptSnippets` UserDefaults value cannot be decoded.
- Store loads decodable-but-invalid snippets but forces invalid enabled snippets to disabled.
- Store saves and reloads snippets.
- Validator rejects enabled snippets with empty title.
- Validator rejects enabled snippets with empty prompt text.
- Validator rejects duplicate enabled triggers while allowing a snippet to keep its own trigger.
- Validator allows no shortcut.
- Validator allows disabled snippets to share a shortcut with other disabled snippets or one enabled snippet.
- Validator blocks enabling a snippet when another enabled snippet already uses the same shortcut.

Tests:

- unit tests for validation issues
- unit tests for duplicate trigger conflict title
- unit tests for persistence round trip

### Slice 2: Hotkey Lookup And Snippet Insertion

Goal:

Extend the existing Fn hotkey handling so configured snippet shortcuts insert text.

Acceptance criteria:

- `Fn + 1...9` is matched through configured triggers, not hard-coded insertion branches.
- A configured enabled snippet inserts its prompt text.
- Insertion reuses the existing clipboard-preserving `TextInserter.insertText` path.
- Empty/unassigned shortcuts show `No prompt assigned`.
- Snippet insertion only fires from the pending Fn state before recording starts.
- Snippet shortcuts do not fire during hold recording.
- Snippet shortcuts do not fire during hands-free recording.
- Snippet shortcuts do not fire during processing.
- Existing hold-to-talk, double-tap hands-free, and `Fn + V` paste-last behavior remain intact.

Tests:

- characterization tests for existing hold-to-talk, double-tap hands-free, and `Fn + V` paste-last behavior before refactoring the hotkey logic
- unit tests for the shortcut decision layer, decoupled from raw `CGEvent` as much as practical
- unit tests around trigger lookup
- manual QA checklist for the real global keyboard behavior

### Slice 3: Menu Item And Window Shell

Goal:

Add `Prompt Snippets...` to the menu and open a dedicated window.

Acceptance criteria:

- Menu item appears in the status menu.
- Selecting it opens a separate `Prompt Snippets` window.
- Re-selecting the menu item focuses the existing window instead of creating duplicates.
- Window has a two-pane structure.
- Empty state is visible when no snippets exist.
- `New Snippet` creates a draft in the editor.

Tests:

- manual check for menu behavior
- manual check for window reuse/focus

### Slice 4: Editor Save, Cancel, And Validation UI

Goal:

Implement editing with explicit Save/Cancel and shared validation.

Acceptance criteria:

- User can create a snippet with title, prompt text, optional shortcut, and enabled state.
- Save is blocked when enabling or saving an enabled snippet with empty title.
- Save is blocked when enabling or saving an enabled snippet with empty prompt text.
- Save is blocked when enabling or saving an enabled snippet with a shortcut already used by another enabled snippet.
- Duplicate shortcut errors show the conflicting enabled snippet title.
- The shortcut picker shows in-use enabled shortcuts as disabled/grayed out options.
- No shortcut is allowed.
- Cancel discards draft changes.
- Saved snippets appear in the left list.
- List uses snippet title as the primary display value and also shows shortcut plus enabled/disabled state.

Tests:

- validator tests remain the source of business-rule coverage
- manual UI checks for inline errors and disabled Save state

### Slice 5: Unsaved Changes And Destructive Actions

Goal:

Add the final editor safety behavior.

Acceptance criteria:

- Switching snippets with no unsaved changes switches immediately.
- Switching snippets with valid unsaved changes offers `Save`, `Keep Editing`, and destructive `Discard`.
- Switching snippets with invalid unsaved changes offers `Keep Editing` and destructive `Discard`.
- Closing the window with valid unsaved changes offers `Save`, `Keep Editing`, and destructive `Discard`.
- Closing the window with invalid unsaved changes offers `Keep Editing` and destructive `Discard`.
- Invalid unsaved-change dialog explains why Save is unavailable.
- `Remove Shortcut` clears the shortcut without confirmation.
- `Delete Snippet...` shows a destructive confirmation dialog.
- Confirmed delete removes the snippet.
- Canceled delete keeps the snippet untouched.

Tests:

- manual dialog behavior checks
- unit tests for draft dirty-state helpers

## Manual QA Checklist

Shortcut behavior:

- `Fn + 1` inserts a configured snippet.
- `Fn + 9` inserts a configured snippet.
- Unassigned `Fn + number` shows `No prompt assigned`.
- Disabled snippet shortcut shows `No prompt assigned`.
- Existing `Fn + V` still pastes last transcription.
- Hold Fn still starts hold-to-talk after the threshold.
- Double-tap Fn still starts hands-free recording.
- Pressing a number during hold recording does not insert a snippet and does not cancel recording.
- Pressing a number during hands-free recording does not insert a snippet and does not cancel recording.
- Pressing a number during processing does not insert a snippet.

Insertion targets:

- Apple Notes text field
- browser text field
- chat-style app text field
- code editor text field

Clipboard:

- clipboard content is restored after snippet insertion
- rich clipboard content is not unexpectedly flattened when possible

Editor:

- create snippet
- edit title
- edit prompt text
- assign shortcut
- clear shortcut
- reject duplicate shortcut
- show conflicting snippet title
- delete snippet with confirmation
- switch snippets with unsaved valid draft
- switch snippets with unsaved invalid draft
- close window with unsaved valid draft
- close window with unsaved invalid draft

## Open Questions For Later

- Should the list show prompt previews?
- Should snippets support drag-and-drop reordering?
- Should snippets support import/export through a JSON file?
- Should there be default prompt templates later?
- Should we support a free shortcut recorder later?
- Should snippets eventually support actions beyond plain insertion, such as insert-and-dictate?
