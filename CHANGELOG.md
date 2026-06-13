# Changelog

All notable changes to this project are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Select text between bookmarks ([#5](https://github.com/haqk/micro-bookmark/issues/5)): `selectBetweenBookmarks` selects the whole lines between the two bookmarks bracketing the cursor; `selectToNextBookmark` and `selectToPrevBookmark` select from the current line to the nearest bookmark below/above. All operate on the active list, select whole lines, and are unbound by default.

## [2.4.0] - 2026-06-13

### Added
- Content-anchored bookmarks (persistence schema `v2`): each saved bookmark now records its line text and the adjacent lines, so on reload the mark is relocated by content. Bookmarks survive edits made while a file was closed — insertions above the mark, function reordering, reindentation, and light edits to the line itself — instead of pointing at a stale line number. Relocation is staged (exact line → exact text → whitespace-normalized text → bounded fuzzy match) and always falls back to the stored line number, so it is never worse than before. Older `v0`/`v1` sidecar files load unchanged.

### Fixed
- Bookmarks saved for a command-line-opened file (`micro file`) are now restored on reopen. micro opens such files before running the plugin's `init()`, so the `bookmark.persist` option was still unregistered (`nil`) when the loader ran and bookmarks were silently skipped. Loading and saving now treat an unregistered option as enabled and only bail on an explicit `false`.
- Bookmarks now persist when you quit micro, not only on file save. Toggling a bookmark does not mark the buffer modified, so bookmark-only changes (e.g. on a file you never edit) were lost on quit. Saving runs from the `preQuit`/`preQuitAll` hooks because micro skips the post-quit `onQuit` callback when the last pane exits the editor. Persisting is skipped for a modified buffer, where line numbers would not match the on-disk file.

## [2.3.11] - 2026-06-13

### Added
- `bookmarkVersion` command — prints the installed plugin version in the InfoBar.
- README sections covering `setMnemonic`/`gotoMnemonic`, `bookmarkPattern`, `grepBookmarks`, `exportBookmarks`, and the `bookmark.scope` option.
- JSON persistence format (schema `v1`) for bookmark and mnemonic sidecar files, with transparent v0 (CSV) fallback on load.
- Validation of list names (letters, digits, `_`, `-` only); creation of `default` is now rejected explicitly.

### Changed
- Picker state is now per-pane: opening multiple pickers no longer overwrites the active one.
- Buffer state survives until the last pane on a buffer closes (pane refcount), instead of being wiped when any pane quits.
- Cursor-on-mark detection now fires on a broader set of motion/search/select events.
- `bookmarkPattern` prompt is labelled "Lua pattern" to set the right expectation.

### Fixed
- `deleteList` no longer crashes on confirmation; the helper that locates the sidecar file is now in scope at the call site.
- `_update` line-shift predicate now uses explicit parentheses; previous precedence was correct but easy to misread.
- `_bfile` no longer relies on undefined Lua `gsub` replacement behaviour (`"%"` → `"%%"`).
- `deleteList` now removes the on-disk sidecar instead of leaving an orphan file.
- Sidecar names containing `,` or `:` are preserved correctly (JSON format).

## [2.3.10] - 2026-06-13

### Fixed
- `ipairs`/`pairs` on Go slices (userdata) replaced with numeric for-loop in `_load` so additional lists are discovered correctly.

## [2.3.9] - 2026-04-13

### Added
- Named bookmark lists per buffer (`createList`, `switchList`, `deleteList`, `listLists`).

## [2.3.8] - 2026-04-13

### Added
- `grepBookmarks` — searchable split listing of bookmarks in the active list.

## [2.3.7] - 2026-04-13

### Added
- Mnemonic bookmarks `A`-`Z` (`setMnemonic`, `gotoMnemonic`).

## [2.3.6] - 2026-04-13

### Added
- `bookmark.scope` option for per-project bookmark storage in `<cwd>/.bookmarks/`.

## [2.3.5] - 2026-04-13

### Added
- Cursor-on-mark InfoBar message when the cursor lands on a bookmarked line.

[Unreleased]: https://github.com/haqk/micro-bookmark/compare/v2.4.0...HEAD
[2.4.0]: https://github.com/haqk/micro-bookmark/releases/tag/v2.4.0
[2.3.11]: https://github.com/haqk/micro-bookmark/releases/tag/v2.3.11
[2.3.10]: https://github.com/haqk/micro-bookmark/releases/tag/v2.3.10
[2.3.9]: https://github.com/haqk/micro-bookmark/releases/tag/v2.3.9
[2.3.8]: https://github.com/haqk/micro-bookmark/releases/tag/v2.3.8
[2.3.7]: https://github.com/haqk/micro-bookmark/releases/tag/v2.3.7
[2.3.6]: https://github.com/haqk/micro-bookmark/releases/tag/v2.3.6
[2.3.5]: https://github.com/haqk/micro-bookmark/releases/tag/v2.3.5
