# Glade

<img src="assets/glade-logo.png" alt="Glade logo: a blue river winding through green hills" width="128" height="128">

A native macOS workspace for exploring JSONL and Markdown files. Glade is a fork of [Parsely](https://github.com/productengineered/parsely), with a file sidebar, spreadsheet-style JSONL records, and a full-content inspector.

## Workspace

- **Files on the left:** open, switch, and close JSONL or Markdown files. Unsaved edits are marked beside the filename.
- **Records in the center:** each JSONL record occupies one spreadsheet row, with its physical line number and a column for each top-level JSON field. Resize columns or scroll horizontally to explore wide records. Nested objects and arrays show compact summaries; missing fields display `—`.
- **Full content on the right:** double-click a row or press Return to open its inspector. Expand nested JSON using the original syntax-highlighted renderer. Malformed rows display their parse error and raw content. Once open, the inspector follows row selection.

Columns are ranked when a document opens: timestamp first, then readable prose (longer text wins ties), commands and paths, numbers, and other values. Fields populated in fewer than a quarter of records move to the right, except timestamps. The heuristic examines nested content too, so a message object with readable text can take priority over technical metadata. The line-number gutter stays at the edge, and records retain their file order.

Timestamp cells omit leading date and time components shared across the file. A shared date disappears; a shared hour or minute reduces the display further, using `m` and `s` for clarity. Fractional seconds retain their original precision. Formatting stays stable while filtering, and the cell tooltip and line inspector show the original timestamp. Mixed timezones or timestamp precision keep their full context.

Search filters records without changing the table's columns. Markdown files have a rendered view and a searchable outline beneath the file list. Both formats support editing, saving, drag and drop, and zoom. Each macOS Space can have its own workspace.

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
| Cmd+S | Save while editing |
| Cmd+[ / Cmd+] | Previous / next file |
| Arrow keys | Navigate rows while the table is focused |
| Return | Open selected row in the inspector |
| Escape | Close inspector while the table is focused |
| Option+Up / Option+Down | Previous / next row |
| Cmd+G | Jump to a physical line number |
| Cmd+Shift+C | Copy selected line as formatted JSON |
| Cmd+Option+C | Copy selected line as raw JSON |
| Cmd+Plus / Cmd+Minus | Zoom in / out |
| Cmd+0 | Reset zoom |

You can also close the inspector using its × button or the toolbar inspector button.

## Supported files

JSON Lines: `.jsonl`, `.ndjson`. Markdown: `.md`, `.markdown`, `.mdown`, `.mkd`.

The `sample-files/` directory contains product, event, weather, malformed-JSON, and Markdown examples.

## Credits and license

Based on [Parsely by productengineered](https://github.com/productengineered/parsely). The original copyright and MIT license are preserved in [LICENSE](LICENSE).
