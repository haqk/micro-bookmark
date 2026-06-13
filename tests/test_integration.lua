-- End-to-end persistence test: drives the REAL bookmark.lua event handlers and
-- commands through a stubbed micro API backed by a real temp directory, so the
-- save → reopen → relocate cycle actually round-trips through disk.
--
-- Unlike test_persistence.lua (which exercises only the pure helpers), this
-- catches integration bugs — e.g. persisting from the wrong lifecycle hook.
-- micro runs the post-action `onQuit` callback only AFTER the Quit action, but
-- quitting the last pane calls runtime.Goexit() inside that action and never
-- returns, so onQuit never fires on the quit that exits the editor. Persistence
-- therefore runs from `preQuit` (before the action); this test models that exact
-- dispatch order and would fail if the save moved back into onQuit.
--
-- Run from the repository root:  lua5.4 tests/test_integration.lua
-- (CI runs it alongside test_persistence.lua.)

local TMP = "/tmp/micro_bookmark_itest"
os.execute("rm -rf " .. TMP .. " && mkdir -p " .. TMP)

-- ── micro API stubs ─────────────────────────────────────────────────────────────
local CMDS, OPTS = {}, {}
local GUTTER = {}            -- captured AddMessage line numbers (1-indexed gutter)
local CURPANE

-- micro's luar uses unary-minus to dereference Go pointers (e.g. -cursor.Loc);
-- give such tables an identity __unm so the plugin's `-x` idioms work here.
local function deref(t) return setmetatable(t, { __unm = function(s) return s end }) end

local function newcursor()
    return {
        Loc            = deref({ X = 0, Y = 0 }),
        HasSelection   = function() return false end,
        ResetSelection = function() end,
        CurSelection   = deref({ deref({ Y = 0, X = 0 }), deref({ Y = 0, X = 0 }) }),
    }
end

local BTDefault = "BTDefault"

local function newbuf(name, lines)
    local cur = newcursor()
    local buf
    buf = {
        _lines = lines, _modified = false, _cur = cur,
        Type            = { Kind = BTDefault, Readonly = false, Scratch = false },
        GetName         = function() return name end,
        Line            = function(_, i) return lines[i + 1] end,
        LinesNum        = function() return #lines end,
        Modified        = function() return buf._modified end,
        GetActiveCursor = function() return cur end,
        AddMessage      = function(_, m) if m and m.line then table.insert(GUTTER, m.line) end end,
        ClearMessages   = function() end,
    }
    return buf
end

local function newpane(buf) return { Buf = buf, Cursor = buf._cur } end

local function readfile(p)
    local f = io.open(p, "rb"); if not f then return nil, "no such file" end
    local d = f:read("*a"); f:close(); return d, nil
end
local function writefile(p, c) local f = assert(io.open(p, "wb")); f:write(c); f:close() end
local function exists(p) local f = io.open(p, "rb"); if f then f:close(); return true end; return nil end

local STUBS = {
    micro = {
        CurPane         = function() return CURPANE end,
        InfoBar         = function() return { Message = function() end } end,
        SetStatusInfoFn = function() end,
        Tabs            = function() return setmetatable({}, { __index = function() return function() end end }) end,
    },
    ["micro/buffer"] = {
        BTDefault        = BTDefault, MTInfo = "info", MTWarning = "warn", MTError = "err",
        NewMessageAtLine = function(_, msg, line) return { line = line, msg = msg } end,
        NewBuffer        = function(_, n) return newbuf(n or "scratch", {}) end,
    },
    ["micro/config"] = {
        ConfigDir            = TMP,
        OptionComplete       = "optcomplete", RTHelp = "rthelp",
        MakeCommand          = function(name, fn) CMDS[name] = fn end,
        RegisterGlobalOption = function(pl, opt, default) OPTS[pl .. "." .. opt] = default end,
        GetGlobalOption      = function(name) return OPTS[name] end,
        TryBindKey           = function() end,
        AddRuntimeFile       = function() end,
    },
    fmt = { Sprintf = function(f, ...) return string.format(f, ...) end },
    os = {
        MkdirAll = function(p) os.execute('mkdir -p "' .. p .. '"'); return nil end,
        Stat     = function(p) return exists(p) end,
        Remove   = function(p) os.remove(p); return nil end,
        Getwd    = function() return TMP, nil end,
    },
    ["io/ioutil"] = {
        WriteFile = function(name, content) writefile(name, content); return nil end,
        ReadFile  = function(name) return readfile(name) end,
        ReadDir   = function(dir)
            local out = {}
            local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
            if p then
                for line in p:lines() do table.insert(out, { Name = function() return line end }) end
                p:close()
            end
            return out, nil
        end,
    },
    ["path/filepath"] = {
        Abs = function(n) if string.sub(n, 1, 1) == "/" then return n else return TMP .. "/" .. n end end,
    },
}

function import(name) return STUBS[name] or error("unstubbed import: " .. name) end

-- ── load the real plugin and register commands/options as micro would ───────────
dofile("bookmark.lua")
init()

-- ── tiny runner ─────────────────────────────────────────────────────────────────
local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then pass = pass + 1 else
        fail = fail + 1
        io.write("  FAIL: " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or "") .. "\n")
    end
end
local function gutter_has(line)
    for _, l in ipairs(GUTTER) do if l == line then return true end end
    return false
end

local FILE = "/tmp/micro_bookmark_itest_file.py"
local SRC  = { "import os", "def main():", "    return 0", "main()" }

local function open(lines)
    local buf = newbuf(FILE, lines)
    CURPANE = newpane(buf)
    onBufferOpen(buf)        -- loads any sidecar, relocating by content
    onBufPaneOpen(CURPANE)   -- refcount + redraw -> populates GUTTER
    return buf, CURPANE
end

-- model micro's last-pane quit: preQuit fires, then ForceQuit->Goexit skips onQuit
local function quit_editor(bp) preQuit(bp) end

local sidecar = TMP .. "/plug/bookmark/" .. string.gsub(FILE, "/", "%%")

-- ── scenario 1: bookmark + QUIT (no file save) persists via preQuit ─────────────
local buf, bp = open(SRC)
bp.Cursor.Loc.Y = 2
CMDS["toggleBookmark"](bp)        -- mark "    return 0"
buf._modified = false             -- bookmarking does not modify the buffer
quit_editor(bp)                   -- the user's exact repro: Ctrl-Q, never saved
check("quit (clean) writes sidecar via preQuit", exists(sidecar), sidecar)

GUTTER = {}
open(SRC)
check("reopen after quit restores mark at original line", gutter_has(3),
    "gutter=" .. table.concat(GUTTER, ","))

-- ── scenario 2: a MODIFIED buffer is NOT persisted on quit ──────────────────────
os.execute("rm -f '" .. sidecar .. "'")
local buf2, bp2 = open(SRC)
bp2.Cursor.Loc.Y = 1
CMDS["toggleBookmark"](bp2)
buf2._modified = true             -- unsaved edits in flight
quit_editor(bp2)
check("quit (modified) does NOT write sidecar", not exists(sidecar))

-- ── scenario 3: file save still persists (onSave path) ──────────────────────────
local _, bp3 = open(SRC)
bp3.Cursor.Loc.Y = 0
CMDS["toggleBookmark"](bp3)
onSave(bp3)
check("onSave writes sidecar", exists(sidecar))

-- ── scenario 4: content anchoring relocates across an external edit ─────────────
-- mark is on "import os" (line 0); insert two lines above it before reopening
GUTTER = {}
local SHIFTED = { "# a", "# b", "import os", "def main():", "    return 0", "main()" }
open(SHIFTED)                     -- "import os" now at index 2 -> gutter line 3
check("reopen after external edit relocates mark by content", gutter_has(3),
    "gutter=" .. table.concat(GUTTER, ","))

-- ── scenario 5: load works even before the persist option is registered ─────────
-- micro opens command-line files (onBufferOpen -> _load) BEFORE running init(),
-- so bookmark.persist is still nil at load time. Loading must not be gated on the
-- option being registered yet — only an explicit false disables it.
os.execute("rm -f '" .. sidecar .. "'")
local _, p5 = open(SRC)
p5.Cursor.Loc.Y = 1
CMDS["toggleBookmark"](p5)
onSave(p5)                          -- sidecar on disk with a mark at line 1
OPTS["bookmark.persist"] = nil      -- simulate "option not registered yet" (pre-init)
GUTTER = {}
open(SRC)                           -- _load runs with persist=nil
check("load runs even when persist option is unregistered (nil)", gutter_has(2),
    "gutter=" .. table.concat(GUTTER, ","))
OPTS["bookmark.persist"] = true

-- ── scenario 6: an explicit persist=false still disables saving ─────────────────
os.execute("rm -f '" .. sidecar .. "'")
OPTS["bookmark.persist"] = false
local _, p6 = open(SRC)
p6.Cursor.Loc.Y = 0
CMDS["toggleBookmark"](p6)
onSave(p6)
check("persist=false writes no sidecar", not exists(sidecar))
OPTS["bookmark.persist"] = true

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail > 0 and 1 or 0)
