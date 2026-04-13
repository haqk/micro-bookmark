# Bookmark Plugin

Bookmark lines to quickly jump between saved positions.

## Commands

| Command | Default binding | Action |
|---------|----------------|--------|
| `toggleBookmark` | Ctrl-F2 | Mark/unmark current line |
| `nextBookmark` | F2 | Jump to next bookmark |
| `prevBookmark` | Shift-F2 | Jump to previous bookmark |
| `clearBookmarks` | CtrlShift-F2 | Clear all bookmarks in current buffer |
| `nameBookmark` | — | Attach a label to the bookmark on the current line |
| `gotoBookmark` | — | Jump to a bookmark by number |
| `listBookmarks` | Alt-F2 | Open picker for current buffer |
| `listAllBookmarks` | — | Open picker across all open buffers |

## Bookmark picker

Press **Enter** on a row to jump to that bookmark. Press **Ctrl-Q** to close the picker.

## Named bookmarks

Run `nameBookmark` on a bookmarked line to attach a label. The label shows in the gutter and in the picker.

## Status line

Add `$(bookmarkpos)` to `statusformatl` or `statusformatr` to show `[BM 2/5]` in the status bar.

## Options

- `bookmark.gutter_style` — `info` (default), `warning`, or `error`
- `bookmark.persist` — `true` (default) or `false`

Set with: `> set bookmark.gutter_style warning`

## Customising bindings

Default bindings can be overridden in `~/.config/micro/bindings.json`.
