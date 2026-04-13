# Bookmarks for micro

A plugin for the micro text editor. Bookmark lines to quickly jump between saved positions.

## Installation

```
# option 1: bash
$ micro -plugin install bookmark

# option 2: micro
> plugin install bookmark
```

## Usage

```
# mark/unmark current line (Ctrl-F2)
> toggleBookmark

# clear all bookmarks (CtrlShift-F2)
> clearBookmarks

# jump to next bookmark (F2)
> nextBookmark

# jump to previous bookmark (Shift-F2)
> prevBookmark

# name the bookmark on the current line
> nameBookmark

# jump to a bookmark by number
> gotoBookmark

# open bookmark picker for current buffer (Alt-F2)
> listBookmarks

# open bookmark picker across all open buffers
> listAllBookmarks

# create a named bookmark list and switch to it
> createList

# switch the active bookmark list
> switchList

# delete the current (non-default) list
> deleteList

# show all lists with bookmark counts
> listLists
```

## Bookmark picker

`listBookmarks` opens a split pane listing all bookmarks with their line number and a content preview. Press **Enter** to jump to the selected bookmark, **Ctrl-Q** to close the picker.

`listAllBookmarks` does the same across every open buffer.

## Bookmark lists

Each buffer has a `default` bookmark list. Create additional named lists to group bookmarks by concern (e.g. `todo`, `review`, `debug`):

```
> createList    — prompt for a name, create and switch to it
> switchList    — switch the active list
> deleteList    — delete the current list (default is protected)
> listLists     — show all lists with bookmark counts
```

All navigation (`nextBookmark`, `prevBookmark`), `toggleBookmark`, `clearBookmarks`, and `listBookmarks` operate on the **active** list. `listAllBookmarks` shows bookmarks from every list in every open buffer.

Lists are persisted per-file: the default list uses the standard bookmark file; additional lists use a `.list.<name>` sidecar file in the same directory.

## Named bookmarks

Use `nameBookmark` on any bookmarked line to attach a label. The label appears in the gutter alongside the bookmark indicator and in the picker.

## Status line

Add `$(bookmarkpos)` to your `statusformatl` or `statusformatr` setting to show the current bookmark position, e.g. `[BM 2/5]`:

```
> set statusformatr "$(bookmarkpos) $(filename) $(line):$(col)"
```

## Options

| Option                   | Values                       | Default | Description                                   |
|--------------------------|------------------------------|---------|-----------------------------------------------|
| `bookmark.gutter_style`  | `info`, `warning`, `error`   | `info`  | Colour of the gutter indicator                |
| `bookmark.persist`       | `true`, `false`              | `true`  | Save and restore bookmarks across sessions    |

```
> set bookmark.gutter_style warning
> set bookmark.persist false
```

## Customising keyboard shortcuts

Default bindings can be overridden in `~/.config/micro/bindings.json`:

```json
{
    "Ctrl-F2":      "command:toggleBookmark",
    "CtrlShift-F2": "command:clearBookmarks",
    "F2":           "command:nextBookmark",
    "Shift-F2":     "command:prevBookmark",
    "Alt-F2":       "command:listBookmarks"
}
```
