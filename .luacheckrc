-- luacheck config for the micro bookmark plugin.
-- micro exposes globals via `import("…")`; plugin entry points are also globals.

std = "lua54"
max_line_length = 140

globals = {
    "VERSION",
    "import",
    -- plugin event handlers
    "init",
    "onBufferOpen",
    "onBufPaneOpen",
    "onQuit",
    "preQuit",
    "preQuitAll",
    "onSave",
    "onBeforeTextEvent",
    "onInsertNewline",
    "onDuplicateLine", "onDelete", "onCut", "onPaste", "onCutLine",
    "onBackspace", "onUndo", "onRedo",
    "preInsertNewline",
    "bookmarkpos",
    -- cursor-motion event handlers are registered on _G in a loop
}
