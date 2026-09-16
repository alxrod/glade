# Glade

A macOS app for viewing and exploring JSONL (JSON Lines) and Markdown files. Line-by-line parsing with collapsible JSON trees, markdown rendering with header navigation, a file sidebar, record table, search, and pretty-print export.

## Tech Stack

- **UI:** SwiftUI with MVVM architecture
- **Language:** Swift 5.0+
- **Patterns:** @Observable macro, async/await (no Combine)
- **Target:** macOS 14.0+
- **Testing:** XCTest model and update-channel tests via `swift test`
- **Distribution:** Direct download (DMG), not App Store
- **Updates:** Sparkle, with release / beta / alpha channels

## Project Structure

```
app/Glade/
  Glade.xcodeproj/
  Glade/
    App/
      GladeApp.swift          # App entry point + AppDelegate (NSAppleEventManager
                                # intercept for file opens, per-Space window creation),
                                # menu commands, keyboard shortcuts
      UpdateController.swift    # Retained Sparkle controller/delegate, observable menu state
    Models/
      JSONLDocument.swift        # File parsing, line collection, table schema
      JSONLColumnOrdering.swift  # Document-wide timestamp/content/sparsity ranking
      JSONLColumnLayoutStore.swift # App-wide order, widths and visibility for exact JSON key sets
      JSONLQuery.swift           # AND column predicates and full-record text search
      JSONLSavedQueryStore.swift # Named local queries scoped to the same column key identity
      LocalFileMetadataStore.swift # Per-file aliases and persistent row color tags
      JSONSearchResults.swift   # Cached background search with cancellation and stale-result guards
      JSONLLine.swift            # Individual line with parsed JSON
      JSONValue.swift            # Recursive JSON value enum
      MarkdownDocument.swift     # Markdown file parsing, heading extraction, block parser
      MarkdownHeading.swift      # Heading tree model (level, title, children)
      UpdateChannel.swift        # Channel subscriptions, persistence, stability policy
    ViewModels/
      GladeViewModel.swift     # Per-tab state: document, selection, search, export
      TabManager.swift           # Tab collection management (one instance per window)
    Views/
      Screens/
        TabbedRootView.swift     # Root view: file sidebar + record table + inspector +
                                 # zoom; inlined WindowAccessor for NSWindow tracking
        JSONLTableView.swift     # Native spreadsheet table with inline search (JSONL)
        DetailView.swift         # JSON detail renderer
        MarkdownSidebarView.swift # Collapsible heading tree (Markdown)
        MarkdownDetailView.swift  # Rendered markdown with scroll-to-heading
        ContentView.swift        # UTType extension only
        UpdateSettingsView.swift # Update channel picker and automatic-check preference
      Components/
        JSONLQueryBar.swift      # Saved-query buttons and column-filter editor
        FileAliasEditor.swift   # Shared filename context menu and nickname prompt
        JSONSearchField.swift   # Isolated draft text; Return submits the JSON query
        JSONValueView.swift      # Recursive JSON tree with collapse/expand
        FileSidebarView.swift    # Open files, close actions, and Markdown outline
        JumpToLineView.swift     # Jump-to-line modal
```

**Note:** This Xcode project uses the legacy (non-synchronized) group model. New `.swift` files are NOT auto-picked up — they must be added to `project.pbxproj` via Xcode. When an automated edit can't do that safely, INLINE small helper types (e.g., `WindowAccessor`) into an existing file in the same module.

## Building

Open `app/Glade/Glade.xcodeproj`, select **Glade**, and run in Xcode. For distribution, archive the Release configuration and export with Developer ID signing.

Avoid CLI verification builds in Xcode's shared DerivedData: they register duplicate apps with LaunchServices. When a CLI build is necessary, use a temporary `-derivedDataPath`, unregister every resulting app with `lsregister -u`, and delete the temporary build directory in the same operation. Never run app-hosted tests in the development app's DerivedData.

Model regression tests (no app registration):

```bash
swift test
```

Signing is configured through `Developer.xcconfig`, which optionally includes gitignored `Local.xcconfig`. Copy the example and set `DEVELOPMENT_TEAM` before building.

Debug is **Glade Dev** (`net.alexbrodriguez.glade.development`); Release is **Glade** (`net.alexbrodriguez.glade`). `GLADE_DEVELOPMENT_BUNDLE_ID` can override the Debug identity without changing Release. Keep `CFBundleShortVersionString` and `CFBundleVersion` driven by `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.

## Publishing updates

Use the `push-update` skill and [docs/releasing.md](docs/releasing.md). Sparkle's keychain account is **Glade**, never the shared default account. The appcast lives on `gh-pages` at `https://alxrod.github.io/glade/appcast.xml`; release DMGs live in GitHub Releases. Maintain one increasing build number across all channels. Keep stable appcast items untagged; tag prereleases `beta` or `alpha`.

Retain both the updater controller and its delegate. Debug disables automatic checks and downloads before starting Sparkle. The app remains sandboxed: installer/downloader XPC services and the two bundle-specific Mach lookup entitlements are required. Archive/export must sign all embedded Sparkle helpers with Developer ID; verify nested signatures before notarizing.

## Quality Gates

| Gate | Requirement |
|-|-|
| **Build** | `xcodebuild` succeeds |
| **No Force Unwraps** | No `!` in production code |
| **No Print Statements** | Use `os.Logger`, not `print()` |
| **Accessibility** | Interactive elements have labels |

## Code Conventions

- **Naming:** PascalCase for types, camelCase for functions/variables
- **Files:** One primary type per file, named to match the type
- **ViewModels:** Use `@Observable` macro, not `@StateObject`/`@ObservedObject`
- **Async:** Use async/await, not Combine or completion handlers
- **Errors:** Typed errors with `LocalizedError`, no `try!` or `fatalError()` in production
- **Strings:** All user-visible strings use SwiftUI's automatic localization or `String(localized:)`

## Key Architecture Decisions

- **No `.searchable` modifier** — Replaced with inline `TextField` in sidebar to avoid a known AppKit layout recursion bug (FB13541783) with `NavigationSplitView`
- **No `DisclosureGroup`** — Replaced with custom chevron toggle to avoid recursive layout in `ScrollView` and to control indentation precisely
- **No `.animation()` on toolbar items** — Triggers AppKit layout recursion; use `withAnimation` in action handlers instead
- **`.toolbar(removing: .sidebarToggle)`** — Sidebar is always visible, no collapse
- **File sidebar + table + inspector** — `NavigationSplitView` owns the file list; `HSplitView` contains the JSONL table and optional resizable inspector. The inspector reuses `DetailView`; its visibility is stored per file. `NSTableView` owns selection, keyboard navigation, and double-click activation. The table schema is derived once from all document lines, never just search results.
- **Column ranking is local and deterministic** — Assess every object record while parsing off the main thread. Timestamp wins even when sparse; other columns populated in fewer than a quarter of records go last. Rank readable language by prevalence and approximate word count, then technical strings, numbers, and other values. Bounded recursive analysis includes text inside objects and arrays without copying it into table cells. Final ties use the field name, never dictionary iteration order.
- **User column layouts override defaults** — A shared observable `JSONLColumnLayoutStore` persists manual order, widths and hidden column identifiers in local UserDefaults. Its identity is a JSON-encoded sorted union of top-level keys across the entire document, independent of paths, values, filters, and incidental raw-content rows. Keep the existing `JSONColumnOrders` preference key so previously saved orders survive. Reads never save heuristic defaults; programmatic native moves and resizes do not write preferences. Keep hidden native columns in the table using `isHidden` so restoring them preserves order and width. The line gutter always stays visible; both synthetic columns stay fixed when reordering. Visibility affects only the spreadsheet, never the document, search, copy, or inspector. Reset Column Order preserves widths and visibility.
- **Queries use full values and the existing schema identity** — `JSONLQuery` combines the global text search and all column predicates with AND. Contains searches decoded strings and nested content case-insensitively; equals uses exact strings and typed JSON comparisons, preserving array order and ignoring object key order. Missing properties never match, including null equality. Per-tab active queries live in `GladeViewModel`; the filter popover edits a draft until Apply or Save. Shared observable `JSONLSavedQueryStore` persists named queries using `JSONLTableColumn.schemaKey`, the same key encoder used by column layouts. Reapplying replaces the current whole query; updating an existing name preserves its identity. Hidden fields remain available to filters. Query changes reconcile row selection without changing the document or inspector rendering.
- **Personal file annotations are separate from schemas and contents** — Shared observable `LocalFileMetadataStore` saves aliases and color tags under standardized file paths. `preferredName` decorates the original name without changing paths, export names, or file contents. The toolbar supplies its own filename text with the same alias editor as the sidebar; hide the native window title visually while retaining its navigation title. Tag identities use a SHA-256 digest of raw row content plus the occurrence among identical rows, computed at parse time. Never persist transient line UUIDs or attach tags solely to physical line numbers. The native table supports Shift ranges, Command-click toggles and Command-A across visible rows. Keep the selected ID set and the primary inspector row in sync, preserving native selection anchors unless the model changes selection. Context-clicking inside the selection captures all selected row IDs; clicking outside selects only that row. Apply or remove all captured tags in one preference write, and preserve only still-visible selections when filtering. Row tint and gutter dots update on tag changes. Tagged-only filtering is part of `JSONLQuery`; decode missing `taggedOnly` as false to preserve older saved searches. Reconcile selection whenever visible row IDs change, including removing a tag while filtering.
- **JSON text search submits on Return** — Keep draft typing inside `JSONSearchField`, isolated from the table and recursive inspector. The parent only observes submitted text. Cache table matches and inspector paths in `JSONSearchResults` helpers, evaluate immutable snapshots in detached tasks, cancel superseded work, and gate publication by request generation. SwiftUI tasks rerun on submitted query, parsed-document identity, or tagged-row membership, never on draft keystrokes. Show progress while retaining completed results. Clear, saved-query Apply, and tag-filter toggles remain explicit immediate actions. The toolbar filename needs an app-local context-click handler limited to the native label's bounds because NSToolbar otherwise intercepts right-clicks before child views receive them; remove the event monitor when detached or deallocated.
- **`@State` intermediary for search binding** — Direct `@Observable` binding to `.searchable` causes crashes on macOS 14.x
- **File-open events via `NSAppleEventManager`, not `.onOpenURL`** — `CFBundleDocumentTypes` is declared in Info.plist (so the app registers as a viewer for `.jsonl`/`.md` in Finder). On macOS 26 SDK, AppKit's `NSDocumentController` routes those file-open Apple Events and spawns empty "ghost" windows when the SwiftUI scene count doesn't match. `AppDelegate.applicationWillFinishLaunching` registers a custom `kAEOpenDocuments` handler that runs BEFORE `NSDocumentController`, extracts URLs, and posts them via `.openFileURL` notification. SwiftUI's `.onOpenURL` is NOT used.
- **Per-Space windows via programmatic `NSHostingController<TabbedRootView>`** — The first window is a SwiftUI `Window(id: "main")` scene. Subsequent windows (one per macOS Space) are created in AppKit when a file is opened on a Space that has no existing Glade window. Each window owns its own `TabManager`.
- **Serialize file-open routing** — `AppDelegate.route(urls:)` posts ONE `.openFileURL` notification with a `[URL]` payload; `TabbedRootView` processes them in a single `Task` with sequential `await manager.openFile(from:)` to avoid races on `TabManager.tabs` / `activeTabID`.

## Bundle Identifiers

- **Release app:** `net.alexbrodriguez.glade`
- **Development app:** `net.alexbrodriguez.glade.development`
- **UTType:** `net.alexbrodriguez.glade.jsonl`
- **Supported extensions:** `.jsonl`, `.ndjson`, `.md`, `.markdown`, `.mdown`, `.mkd`
