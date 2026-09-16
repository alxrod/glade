# Glade

<img src="assets/glade-logo.png" alt="Glade logo: a blue river winding through green hills" width="128" height="128">

A native macOS workspace for exploring JSONL and Markdown files. Glade is a fork of [Parsely](https://github.com/productengineered/parsely), with a file sidebar, spreadsheet-style JSONL records, and a full-content inspector.

## Workspace

- **Files on the left:** open, switch, and close JSONL or Markdown files. Unsaved edits are marked beside the filename.
- **Records in the center:** each JSONL record occupies one spreadsheet row, with its physical line number and a column for each top-level JSON field. Resize columns or scroll horizontally to explore wide records. Nested objects and arrays show compact summaries; missing fields display `—`.
- **Full content on the right:** double-click a row or press Return to open its inspector. Expand nested JSON using the original syntax-highlighted renderer. Malformed rows display their parse error and raw content. Once open, the inspector follows row selection.

Columns are ranked when a document opens: timestamp first, then readable prose (longer text wins ties), commands and paths, numbers, and other values. Fields populated in fewer than a quarter of records move to the right, except timestamps. The heuristic examines nested content too, so a message object with readable text can take priority over technical metadata. The line-number gutter stays at the edge, and records retain their file order.

Drag JSON property headers to rearrange columns. Glade saves that order in its local app preferences and applies it to every file with the exact same set of top-level keys, across windows and app launches. Matching uses all rows in the file and ignores filenames, values, and filters. Your saved order takes precedence over automatic ranking; right-click a header and choose **Reset Column Order** to restore automatic ranking for that key set. The line-number gutter and optional raw-content column stay at the edges.

Column widths and hidden columns are remembered for that same key set. Right-click a cell and choose **Hide Column** to remove its column from the spreadsheet. Use **Show Hidden Columns** above the table to restore one column or all of them, with their saved widths and positions. Hidden fields still appear in the full-line inspector and remain searchable. The line-number gutter always stays visible, even if every data column is hidden.

Column headers also offer **Hide Column** on right-click. Right-click a filename in the title bar or file sidebar and choose **Assign Alias…** to give that file a local nickname. The alias appears in both places without renaming the file; **Remove Alias** restores its filename.

Right-click any row to assign one of eight color tags, shown as a gutter dot and light row tint. Shift-click selects a range, Command-click adds or removes individual rows, and Command-A selects all visible rows when the table has focus. Right-click within the selection to tag or clear those rows together; right-clicking an unselected row targets only that row. Choose the circle with an X (**Remove Tag**) to clear it. **Tagged only** above the table combines with text and column filters, and can be included in saved queries. Aliases and tags persist locally per file path. Tags follow exact row content when unrelated lines are inserted or reordered; identical rows are distinguished by occurrence. Editing a record's content gives it a new tag identity. File contents, copy, export, and the inspector remain unchanged.

Use **Filters** above the table to combine column conditions: for example, `message contains register` and `type equals user`. Every condition must match the same row. **Contains** ignores letter case and searches full values, including nested keys and text; **equals** matches whole, case-sensitive strings or typed numbers, booleans, null, objects, and arrays. Missing fields do not match. Add a query name and choose **Save Query** to keep the conditions and the main text search together. Saved queries appear as buttons at the top of the table for every file with exactly the same top-level keys, even after relaunch. Right-click a saved query to edit or delete it; **Clear** removes the current search and filters without deleting the saved query.

Timestamp cells omit shared leading parts only in complete groups: the entire date, then hour and minute together, then whole seconds. Hours and minutes always stay together; differing dates remain fully visible. Fractional seconds retain their original precision. Formatting stays stable while filtering, and the cell tooltip and line inspector show the original timestamp. Mixed timezones or timestamp precision keep their full context.

Press **Return** to submit text searches in the JSON table or line inspector; typing keeps the current results visible. Searches run in the background with a loading indicator, and newer submissions cancel older work. Clearing a search, applying a saved query, and toggling **Tagged only** are explicit actions that apply immediately. Search filters records without changing the table's columns. Markdown files have a rendered view and a searchable outline beneath the file list. Both formats support drag and drop. Markdown files also support editing and saving. JSONL files are read-only, with Copy and the inspector toggle at the right of the toolbar; the filename is plain text and still supports assigning an alias. Each macOS Space can have its own workspace.

Use **Search this line** at the top of the inspector to search that record independently. Matches are highlighted and counted; unrelated fields are hidden while parent keys and original array indices remain visible. Matching a container key reveals its full value. Clear the search (or press Escape in the field) to restore the full record. The inspector query stays with each file as you select different rows.

## Build

Requires macOS 14 or later and Xcode with the macOS SDK.

1. Copy `app/Glade/Local.xcconfig.example` to `app/Glade/Local.xcconfig` and set your Apple development team.
2. Open `app/Glade/Glade.xcodeproj` in Xcode.
3. Select the **Glade** scheme and run the app.

Debug builds run as **Glade Dev**, with a separate bundle ID and automatic updates disabled. Release builds run as **Glade**. You can override `GLADE_DEVELOPMENT_BUNDLE_ID` in `Local.xcconfig` for an additional development checkout. Local signing settings are gitignored.

Run model regression tests from the repository root:

```sh
swift test
```

## Updates

Choose **Glade → Check for Updates…** to check manually. **Glade → Settings…** selects an update channel:

- **Release:** stable updates only (the default).
- **Beta:** beta and stable updates.
- **Alpha:** alpha, beta, and stable updates.

Switching to a more stable channel waits for a newer eligible build; it does not downgrade the installed app. Distribution builds can check automatically; development builds only check when requested.

Updates use Sparkle with an app-specific signing key and a [GitHub Pages appcast](https://alxrod.github.io/glade/appcast.xml). See [Releasing Glade](docs/releasing.md) for signing, notarization, and publishing.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Cmd+O | Open files |
| Cmd+W | Close active file |
| Cmd+S | Save Markdown while editing |
| Cmd+[ / Cmd+] | Previous / next file |
| Arrow keys | Navigate rows while the table is focused |
| Return | Open selected row in the inspector |
| Escape | Close inspector while the table is focused |
| Option+Up / Option+Down | Previous / next row |
| Cmd+G | Jump to a physical line number |
| Cmd+Shift+C | Copy selected line as formatted JSON |
| Cmd+Option+C | Copy selected line as raw JSON |

You can also close the inspector using its × button or the toolbar inspector button.

## Supported files

JSON Lines: `.jsonl`, `.ndjson`. Markdown: `.md`, `.markdown`, `.mdown`, `.mkd`.

The `sample-files/` directory contains product, event, weather, malformed-JSON, and Markdown examples.

## Credits and license

Based on [Parsely by productengineered](https://github.com/productengineered/parsely). The original copyright and MIT license are preserved in [LICENSE](LICENSE).
