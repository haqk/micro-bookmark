# Bookmark Plugin

Bookmark lines to quickly jump between saved positions.

## Commands

| Command              | Default binding  | Action                                             |
|----------------------|------------------|----------------------------------------------------|
| `toggleBookmark`     | Ctrl-F2          | Mark/unmark current line                           |
| `nextBookmark`       | F2               | Jump to next bookmark                              |
| `prevBookmark`       | Shift-F2         | Jump to previous bookmark                          |
| `clearBookmarks`     | CtrlShift-F2     | Clear all bookmarks in current buffer              |
| `nameBookmark`       | —                | Attach a label to the bookmark on the current line |
| `gotoBookmark`       | —                | Jump to a bookmark by number                       |
| `listBookmarks`      | Alt-F2           | Open picker for current buffer                     |
| `listAllBookmarks`   | —                | Open picker across all open buffers                |
| `createList`         | —                | Create a new named bookmark list and switch to it  |
| `switchList`         | —                | Switch the active bookmark list                    |
| `deleteList`         | —                | Delete the current list (not allowed for default)  |
| `listLists`          | —                | Open a pane showing all lists and bookmark counts  |

## Bookmark picker

Press **Enter** on a row to jump to that bookmark. Press **Ctrl-Q** to close the picker.

## Named bookmarks

Run `nameBookmark` on a bookmarked line to attach a label. The label shows in the gutter and in the picker.

## Status line

Add `$(bookmarkpos)` to `statusformatl` or `statusformatr` to show `[BM 2/5]` in the status bar.

## Bookmark lists

Each buffer starts with a single `default` list. Create additional lists to group bookmarks by concern:

```
> createList   — prompt for a name, create and switch to it
> switchList   — switch active list (picker shows all lists)
> deleteList   — delete the current non-default list
> listLists    — show all lists with bookmark counts
```

Navigation, toggle, clear, and the picker all operate on the **active** list only. `listAllBookmarks` shows bookmarks from all lists across all buffers.

Lists are persisted separately: the default list uses the standard bookmark file; additional lists use a `.list.<name>` sidecar file alongside it.

## Options

- `bookmark.gutter_style` — `info` (default), `warning`, or `error`
- `bookmark.persist` — `true` (default) or `false`

Set with: `> set bookmark.gutter_style warning`

## Customising bindings

Default bindings can be overridden in `~/.config/micro/bindings.json`.
