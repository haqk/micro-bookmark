# Bookmarks for micro

[![version](https://img.shields.io/github/v/tag/haqk/micro-bookmark?label=version&sort=semver)](https://github.com/haqk/micro-bookmark/releases)
[![micro](https://img.shields.io/badge/micro-%E2%89%A5%202.0.0-blue)](https://micro-editor.github.io/)
[![license: MIT](https://img.shields.io/github/license/haqk/micro-bookmark)](LICENSE)

A plugin for the [micro](https://micro-editor.github.io/) text editor. Bookmark lines to quickly jump between saved positions — with named bookmarks, per-buffer lists, mnemonic letters, pattern marking, search, and export.

```text
  gutter           buffer
  ──────┬──────────────────────────────────────
   1    │ local function parse(input)
 ● 2    │   local tokens = {}            ← bookmarked, named "tokenizer entry"
   3    │   for line in input:lines() do
   4    │     ...
 ● 5    │   end                          ← bookmarked
  ──────┴──────────────────────────────────────
  status line:  [BM 1/2]  parser.lua  2:18
```

*(Illustration — markers appear in micro's gutter; `$(bookmarkpos)` shows position on the status line.)*

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Bookmark picker](#bookmark-picker)
- [Bookmark lists](#bookmark-lists)
- [Named bookmarks](#named-bookmarks)
- [Mnemonics](#mnemonics)
- [Pattern marking](#pattern-marking)
- [Search and export](#search-and-export)
- [Status line](#status-line)
- [Options](#options)
- [Customising keyboard shortcuts](#customising-keyboard-shortcuts)
- [Where bookmarks are stored](#where-bookmarks-are-stored)
- [Example workflow](#example-workflow)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Requirements

micro **2.0.0 or newer**.

## Installation

> **Note:** micro's built-in plugin channel currently ships an old release (2.2.3). To get the latest version with named lists, mnemonics, pattern marking, grep, export, and project scope, install manually until the channel catches up.

**Manual install (recommended — gets the latest):**

```sh
git clone https://github.com/haqk/micro-bookmark ~/.config/micro/plug/bookmark
```

Then restart micro. To update later, `git pull` in that directory.

**Via the plugin channel (older release):**

```sh
# bash
$ micro -plugin install bookmark

# or from inside micro
> plugin install bookmark
```

Confirm what you have with `> bookmarkVersion`. In-editor help is available with `> help bookmark`.

## Quick start

```text
> toggleBookmark      # mark the current line          (Ctrl-F2)
F2 / Shift-F2         # jump to next / previous bookmark
> listBookmarks       # open the picker                (Alt-F2)
```

That's enough to use it. Everything below is optional depth.

## Commands

| Command            | Default key      | Description                                            |
|--------------------|------------------|--------------------------------------------------------|
| `toggleBookmark`   | `Ctrl-F2`        | Mark/unmark the current line                           |
| `nextBookmark`     | `F2`             | Jump to the next bookmark in the active list           |
| `prevBookmark`     | `Shift-F2`       | Jump to the previous bookmark in the active list       |
| `clearBookmarks`   | `CtrlShift-F2`   | Clear all bookmarks in the active list (with confirm)  |
| `listBookmarks`    | `Alt-F2`         | Open the picker for the current buffer                 |
| `listAllBookmarks` | —                | Open the picker across all open buffers                |
| `nameBookmark`     | —                | Attach a label to the current line's bookmark          |
| `gotoBookmark`     | —                | Jump to a bookmark by number                           |
| `bookmarkPattern`  | —                | Bookmark every line matching a Lua pattern             |
| `grepBookmarks`    | —                | Open a searchable split of all bookmarks               |
| `exportBookmarks`  | —                | Open a Markdown table of bookmarks in a scratch buffer |
| `setMnemonic`      | —                | Assign a mnemonic letter `A`–`Z` to the current line   |
| `gotoMnemonic`     | —                | Jump to a mnemonic letter                              |
| `createList`       | —                | Create a named bookmark list and switch to it          |
| `switchList`       | —                | Switch the active bookmark list                        |
| `deleteList`       | —                | Delete the current (non-`default`) list                |
| `listLists`        | —                | Show all lists with bookmark counts                    |
| `bookmarkVersion`  | —                | Print the installed plugin version in the InfoBar      |

Commands without a default key can be bound yourself — see [Customising keyboard shortcuts](#customising-keyboard-shortcuts).

## Bookmark picker

`listBookmarks` opens a split pane listing all bookmarks with their line number and a content preview:

```text
 bookmarks — parser.lua (review) ─────────────────
 2    local tokens = {}            tokenizer entry
 5    end
 11   -- TODO: handle EOF
 ──────────────────────────────────────────────────
 Enter: jump    Ctrl-Q: close
```

Press **Enter** to jump to the selected bookmark, **Ctrl-Q** to close the picker. `listAllBookmarks` does the same across every open buffer.

## Bookmark lists

Each buffer has a `default` bookmark list. Create additional named lists to group bookmarks by concern (e.g. `todo`, `review`, `debug`):

```text
> createList    — prompt for a name, create and switch to it
> switchList    — switch the active list
> deleteList    — delete the current list (default is protected)
> listLists     — show all lists with bookmark counts
```

List names may contain letters, digits, `_` and `-`. All navigation (`nextBookmark`, `prevBookmark`), `toggleBookmark`, `clearBookmarks`, and `listBookmarks` operate on the **active** list. `listAllBookmarks` shows bookmarks from every list in every open buffer.

## Named bookmarks

Use `nameBookmark` on any bookmarked line to attach a label. The label appears in the gutter alongside the bookmark indicator and in the picker.

## Mnemonics

`setMnemonic` assigns a letter `A`–`Z` to the current line; `gotoMnemonic` jumps to a previously set letter. Mnemonics are shared across all of a buffer's lists and persist alongside bookmarks.

## Pattern marking

`bookmarkPattern` prompts for a [Lua pattern](https://www.lua.org/manual/5.4/manual.html#6.4.1) (not a regular expression) and bookmarks every line in the buffer that matches it. Invalid patterns are reported in the InfoBar.

## Search and export

- `grepBookmarks` opens a split pane listing every bookmark with its content; use micro's `Ctrl-F` to search within it.
- `exportBookmarks` opens a Markdown table in a scratch buffer — handy for copying or saving as a checklist.

## Status line

Add `$(bookmarkpos)` to your `statusformatl` or `statusformatr` setting to show the current bookmark position, e.g. `[BM 2/5]`:

```text
> set statusformatr "$(bookmarkpos) $(filename) $(line):$(col)"
```

## Options

| Option                   | Values                       | Default  | Description                                                  |
|--------------------------|------------------------------|----------|--------------------------------------------------------------|
| `bookmark.gutter_style`  | `info`, `warning`, `error`   | `info`   | Colour of the gutter indicator                               |
| `bookmark.persist`       | `true`, `false`              | `true`   | Save and restore bookmarks across sessions                   |
| `bookmark.scope`         | `global`, `project`          | `global` | `global` stores in `~/.config/micro/plug/bookmark/`; `project` stores in `<cwd>/.bookmarks/` |

```text
> set bookmark.gutter_style warning
> set bookmark.persist false
> set bookmark.scope project
```

## Customising keyboard shortcuts

Default bindings can be overridden — and the unbound commands bound — in `~/.config/micro/bindings.json`:

```json
{
    "Ctrl-F2":      "command:toggleBookmark",
    "CtrlShift-F2": "command:clearBookmarks",
    "F2":           "command:nextBookmark",
    "Shift-F2":     "command:prevBookmark",
    "Alt-F2":       "command:listBookmarks"
}
```

Any command in the [Commands](#commands) table can be bound this way, e.g. `"Alt-m": "command:setMnemonic"`.

## Where bookmarks are stored

When `bookmark.persist` is `true` (the default), bookmarks are written to disk so they survive restarts. The storage directory depends on `bookmark.scope`:

| Scope     | Directory                          |
|-----------|------------------------------------|
| `global`  | `~/.config/micro/plug/bookmark/`   |
| `project` | `<cwd>/.bookmarks/`                |

Within that directory, each edited file gets its own bookmark file (named after the file's absolute path). Additional named lists are stored as `<file>.list.<name>` sidecars, and mnemonics as a `<file>.mn` sidecar. Files use a small JSON format; older comma-separated files are read transparently and upgraded on the next save.

Each bookmark records its line's text and surrounding context, not just a line number. When you reopen a file that changed while it was closed — lines inserted above the mark, a function moved, the line lightly edited or reindented — the bookmark is relocated to its content rather than left pointing at a stale line. If no confident match is found it falls back to the stored line number, so it is never worse than a plain line reference.

## Example workflow

A code-review pass:

1. `> createList` and name it `review`.
2. Walk the diff; `> toggleBookmark` (`Ctrl-F2`) on each line worth revisiting, and `> nameBookmark` to note *why*.
3. `> grepBookmarks` to scan them, or `> exportBookmarks` to get a Markdown checklist you can paste into the PR.
4. `> deleteList` when the review is done.

## Troubleshooting

- **Bookmarks don't persist across sessions** — check `bookmark.persist` is `true`. In `project` scope they are saved under `<cwd>/.bookmarks/`, so they only reappear when micro is launched from the same directory.
- **`F2` / `Alt-F2` do nothing** — some terminals intercept function and Alt keys. Bind the commands to other keys in `bindings.json` (see above).
- **`bookmarkPattern` matches nothing** — it takes a *Lua pattern*, not a regular expression (`%d` not `\d`, no `\b`). Check the InfoBar for a pattern error.

## Contributing

Issues and pull requests are welcome. For code changes:

- Parse-check and lint: `lua5.4 -e 'loadfile("bookmark.lua")'` and `luacheck bookmark.lua`.
- Run the unit tests: `lua5.4 tests/test_persistence.lua` (covers the pure persistence helpers).
- Update `CHANGELOG.md` under `## [Unreleased]` for user-visible changes, and this README for new commands or options.
- CI runs the parse-check, luacheck, the unit tests, and a `repo.json`/`VERSION` consistency check on every pull request.

To report a security issue, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) · [Changelog](CHANGELOG.md) · [Security policy](SECURITY.md)
