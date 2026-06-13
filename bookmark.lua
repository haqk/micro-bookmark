VERSION = "2.3.11"

local micro    = import("micro")
local buffer   = import("micro/buffer")
local config   = import("micro/config")
local fmt      = import("fmt")
local goos     = import("os")
local ioutil   = import("io/ioutil")
local filepath = import("path/filepath")

-- per-buffer state
-- bd[bn] = {
--   lists     = { ["default"] = {marks={}, names={}}, ["mylist"] = {marks={}, names={}}, ... },
--   active    = "default",   -- name of the active list
--   mnemonics = {},          -- letter → line (shared across lists)
--   curpos    = {X=0, Y=0},
--   sel       = {{Y=0},{Y=0}},
--   onmark    = false,
--   oldl      = 0,
--   buf       = b
-- }
local bd          = {}
local _pickers    = {}  -- picker pane name → {source_bp, source_bn, entries}
local _picker_seq = 0

-- ── helpers ───────────────────────────────────────────────────────────────────

local function _bdir()
    local scope = config.GetGlobalOption("bookmark.scope")
    if scope == "project" then
        local cwd, err = goos.Getwd()
        if err == nil then return cwd .. "/.bookmarks" end
    end
    return config.ConfigDir .. "/plug/bookmark"
end

local function _bfile(bn)
    return _bdir() .. "/" .. string.gsub(filepath.Abs(bn), "/", "%%")
end

-- file for a named list: default uses the base path (backward compat), others get a suffix
local function _lfile(bn, listname)
    if listname == "default" then return _bfile(bn) end
    return _bfile(bn) .. ".list." .. listname
end

local function _mt()
    local s = config.GetGlobalOption("bookmark.gutter_style")
    if s == "warning" then return buffer.MTWarning
    elseif s == "error" then return buffer.MTError
    else return buffer.MTInfo end
end

local function _gutter(bp, msg, line)
    bp.Buf:AddMessage(buffer.NewMessageAtLine("bookmark", msg, line, _mt()))
end

-- returns the active list table {marks={}, names={}} for the given buffer name
local function _active(bn)
    return bd[bn].lists[bd[bn].active]
end

local function _dedupe(bp)
    local bn   = bp.Buf:GetName()
    local seen = {}
    local res  = {}
    for _, y in ipairs(_active(bn).marks) do
        if not seen[y] then res[#res+1] = y; seen[y] = true end
    end
    _active(bn).marks = res
end

local function _redraw(bp)
    local bn  = bp.Buf:GetName()
    local act = _active(bn)
    bp.Buf:ClearMessages("bookmark")
    if #act.marks > 0 then
        for i, y in ipairs(act.marks) do
            local name  = act.names[y]
            local label = "bookmark (" .. i .. "/" .. #act.marks .. ")"
            if name and name ~= "" then label = label .. " " .. name end
            _gutter(bp, label, y + 1)
        end
    else
        _gutter(bp, "", 0)
    end
end

-- ── core commands ─────────────────────────────────────────────────────────────

local function _toggle(bp)
    local bn  = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local act  = _active(bn)
    local c    = bp.Buf:GetActiveCursor()
    local newy = c.Loc.Y
    local found = false
    for i, y in ipairs(act.marks) do
        if y == newy then
            found = true
            table.remove(act.marks, i)
            act.names[newy] = nil
            break
        end
    end
    if not found then
        table.insert(act.marks, newy)
        table.sort(act.marks)
        -- auto-label from single-line selection if present
        if c:HasSelection() then
            local sel = -c.CurSelection
            local y1  = sel[1] and sel[1].Y
            local y2  = sel[2] and sel[2].Y
            if y1 == newy and y2 == newy then
                local x1    = math.min(sel[1].X, sel[2].X)
                local x2    = math.max(sel[1].X, sel[2].X)
                local label = string.sub(bp.Buf:Line(newy), x1 + 1, x2)
                if label ~= "" then act.names[newy] = label end
            end
        end
    end
    _redraw(bp)
end

local function _clear(bp)
    local bn  = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local act = _active(bn)
    local n   = #act.marks
    if n == 0 then return end
    local plural = n == 1 and "bookmark" or "bookmarks"
    micro.InfoBar():Prompt("Clear " .. n .. " " .. plural .. "? (y/n): ", "", "Bookmark", nil,
        function(input, cancelled)
            if not cancelled and (input == "y" or input == "Y") then
                if bd[bn] == nil then return end
                local a = _active(bn)
                a.marks = {}
                a.names = {}
                _redraw(bp)
            end
        end
    )
end

local function _next(bp)
    local bn  = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local act = _active(bn)
    if #act.marks == 0 then return end
    local c      = bp.Buf:GetActiveCursor()
    local jumped = false
    for _, y in ipairs(act.marks) do
        if y > c.Loc.Y then
            c:ResetSelection(); c.Loc.X = 0; c.Loc.Y = y
            jumped = true; break
        end
    end
    if not jumped then
        c:ResetSelection(); c.Loc.X = 0; c.Loc.Y = act.marks[1]
    end
    bp:Relocate()
end

local function _prev(bp)
    local bn  = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local act = _active(bn)
    if #act.marks == 0 then return end
    local c         = bp.Buf:GetActiveCursor()
    local noneAbove = true
    local i         = #act.marks
    while true do
        local y = act.marks[i]
        if y < c.Loc.Y then
            c:ResetSelection(); c.Loc.X = 0; c.Loc.Y = y
            noneAbove = false; i = 1
        end
        i = i - 1
        if i == 0 then break end
    end
    if noneAbove then
        c:ResetSelection(); c.Loc.X = 0; c.Loc.Y = act.marks[#act.marks]
    end
    bp:Relocate()
end

local function _name_bookmark(bp)
    local bn  = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local act = _active(bn)
    local y   = bp.Buf:GetActiveCursor().Loc.Y
    local found = false
    for _, my in ipairs(act.marks) do
        if my == y then found = true; break end
    end
    if not found then
        micro.InfoBar():Message("No bookmark on current line")
        return
    end
    local current = act.names[y] or ""
    micro.InfoBar():Prompt("Bookmark name: ", current, "Bookmark", nil, function(input, cancelled)
        if not cancelled then
            if bd[bn] == nil then return end
            _active(bn).names[y] = (input ~= "" and input or nil)
            _redraw(bp)
        end
    end)
end

local function _goto_bookmark(bp)
    local bn  = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local act = _active(bn)
    if #act.marks == 0 then
        micro.InfoBar():Message("No bookmarks")
        return
    end
    micro.InfoBar():Prompt("Bookmark #: ", "", "Bookmark",
        function(input)
            if bd[bn] == nil then return end
            local a = _active(bn)
            local n = tonumber(input)
            if n and a.marks[n] then
                local y    = a.marks[n]
                local name = a.names[y] or ""
                local msg  = "→ " .. n .. ": line " .. (y + 1)
                if name ~= "" then msg = msg .. "  " .. name end
                micro.InfoBar():Message(msg)
            end
        end,
        function(input, cancelled)
            if not cancelled then
                if bd[bn] == nil then return end
                local a = _active(bn)
                local n = tonumber(input)
                if n and a.marks[n] then
                    local c = bp.Buf:GetActiveCursor()
                    c:ResetSelection(); c.Loc.X = 0; c.Loc.Y = a.marks[n]
                    bp:Relocate()
                end
            end
        end
    )
end

-- build a scratch buffer listing bookmark entries
local function _build_picker_lines(entries)
    local lines = {}
    for i, e in ipairs(entries) do
        local name    = e.names[e.y] or ""
        local content = ""
        if e.buf then
            content = string.gsub(e.buf:Line(e.y), "^%s+", "")
            if #content > 50 then content = string.sub(content, 1, 50) .. "…" end
        end
        local label = name ~= "" and ("  [" .. name .. "]") or ""
        if e.bufname then
            local short = e.bufname:match("([^/]+)$") or e.bufname
            table.insert(lines, fmt.Sprintf(" %2d  %-20s  line %-5d%s  %s", i, short, e.y + 1, label, content))
        else
            table.insert(lines, fmt.Sprintf(" %2d  line %-5d%s  %s", i, e.y + 1, label, content))
        end
    end
    return table.concat(lines, "\n")
end

local function _open_picker(bp, entries, source_bn)
    _picker_seq = _picker_seq + 1
    local pname = "Bookmarks-" .. _picker_seq
    _pickers[pname] = {source_bp = bp, source_bn = source_bn, entries = entries}
    local listbuf = buffer.NewBuffer(_build_picker_lines(entries), pname)
    listbuf.Type.Readonly = true
    listbuf.Type.Scratch  = true
    bp:HSplitBuf(listbuf)
    micro.InfoBar():Message("Enter: jump  Ctrl-Q: close")
end

local function _list(bp)
    local bn  = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local act = _active(bn)
    if #act.marks == 0 then
        micro.InfoBar():Message("No bookmarks")
        return
    end
    local entries = {}
    for _, y in ipairs(act.marks) do
        table.insert(entries, {y = y, names = act.names, buf = bd[bn].buf, bufname = nil})
    end
    _open_picker(bp, entries, bn)
end

local function _set_mnemonic(bp)
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local y = bp.Buf:GetActiveCursor().Loc.Y
    micro.InfoBar():Prompt("Set mnemonic (A-Z): ", "", "Bookmark", nil,
        function(input, cancelled)
            if cancelled or input == "" then return end
            if bd[bn] == nil then return end
            local letter = string.upper(string.sub(input, 1, 1))
            if not string.match(letter, "^[A-Z]$") then
                micro.InfoBar():Message("Mnemonic must be a letter A-Z")
                return
            end
            bd[bn].mnemonics[letter] = y
            micro.InfoBar():Message("Mnemonic " .. letter .. " → line " .. (y + 1))
        end
    )
end

local function _goto_mnemonic(bp)
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return end
    micro.InfoBar():Prompt("Go to mnemonic (A-Z): ", "", "Bookmark", nil,
        function(input, cancelled)
            if cancelled or input == "" then return end
            if bd[bn] == nil then return end
            local letter = string.upper(string.sub(input, 1, 1))
            local y      = bd[bn].mnemonics[letter]
            if y == nil then
                micro.InfoBar():Message("No mnemonic " .. letter)
                return
            end
            local c = bp.Buf:GetActiveCursor()
            c:ResetSelection(); c.Loc.X = 0; c.Loc.Y = y
            bp:Relocate()
            micro.InfoBar():Message("→ " .. letter .. ": line " .. (y + 1))
        end
    )
end

local function _grep_bookmarks(bp)
    local bn  = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local act = _active(bn)
    if #act.marks == 0 then
        micro.InfoBar():Message("No bookmarks to search")
        return
    end
    local lines = {}
    for i, y in ipairs(act.marks) do
        local name    = act.names[y] or ""
        local content = bp.Buf:Line(y)
        local prefix  = fmt.Sprintf("%3d  line %-5d  ", i, y + 1)
        if name ~= "" then prefix = prefix .. "[" .. name .. "]  " end
        table.insert(lines, prefix .. content)
    end
    local grepbuf = buffer.NewBuffer(table.concat(lines, "\n"), "bookmark-search")
    grepbuf.Type.Readonly = true
    grepbuf.Type.Scratch  = true
    bp:HSplitBuf(grepbuf)
    micro.InfoBar():Message("Ctrl-F to search  Ctrl-Q to close")
end

local function _export(bp)
    local bn  = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local act = _active(bn)
    if #act.marks == 0 then
        micro.InfoBar():Message("No bookmarks to export")
        return
    end
    local short   = bn:match("([^/]+)$") or bn
    local header  = "# Bookmarks — " .. short .. "  [list: " .. bd[bn].active .. "]\n\n"
    header = header .. fmt.Sprintf("| %-4s | %-6s | %-20s | %s |\n", "#", "Line", "Name", "Content")
    header = header .. fmt.Sprintf("|%s|%s|%s|%s|\n", string.rep("-", 6), string.rep("-", 8),
                                   string.rep("-", 22), string.rep("-", 54))
    local rows = {}
    for i, y in ipairs(act.marks) do
        local name    = act.names[y] or ""
        local content = string.gsub(bp.Buf:Line(y), "^%s+", "")
        if #content > 50 then content = string.sub(content, 1, 50) .. "…" end
        table.insert(rows, fmt.Sprintf("| %-4d | %-6d | %-20s | %s |", i, y + 1, name, content))
    end
    local text   = header .. table.concat(rows, "\n") .. "\n"
    local expbuf = buffer.NewBuffer(text, "bookmark-export")
    expbuf.Type.Scratch  = true
    expbuf.Type.Readonly = true
    bp:HSplitBuf(expbuf)
end

local function _bookmark_pattern(bp)
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return end
    micro.InfoBar():Prompt("Bookmark Lua pattern: ", "", "Bookmark", nil,
        function(input, cancelled)
            if cancelled or input == "" then return end
            if bd[bn] == nil then return end
            local act     = _active(bn)
            local matched = 0
            local total   = bp.Buf:LinesNum()
            local ok, err = pcall(function()
                for i = 0, total - 1 do
                    local line = bp.Buf:Line(i)
                    if string.find(line, input) then
                        local already = false
                        for _, y in ipairs(act.marks) do
                            if y == i then already = true; break end
                        end
                        if not already then
                            table.insert(act.marks, i)
                            matched = matched + 1
                        end
                    end
                end
            end)
            if not ok then
                micro.InfoBar():Message("Invalid pattern: " .. tostring(err))
                return
            end
            if matched > 0 then
                table.sort(act.marks)
                _redraw(bp)
                micro.InfoBar():Message("Bookmarked " .. matched .. " line" .. (matched == 1 and "" or "s"))
            else
                micro.InfoBar():Message("No lines matched")
            end
        end
    )
end

local function _list_all(bp)
    local entries = {}
    for bn, data in pairs(bd) do
        for listname, lst in pairs(data.lists) do
            if #lst.marks > 0 then
                for _, y in ipairs(lst.marks) do
                    local display = bn
                    if listname ~= "default" then display = bn .. " [" .. listname .. "]" end
                    -- actual_bn is the real buffer name used for pane lookup;
                    -- bufname is the display name shown in the picker
                    table.insert(entries, {y = y, names = lst.names, buf = data.buf,
                                           bufname = display, actual_bn = bn})
                end
            end
        end
    end
    if #entries == 0 then
        micro.InfoBar():Message("No bookmarks in any open buffer")
        return
    end
    _open_picker(bp, entries, bp.Buf:GetName())
end

-- ── list management ───────────────────────────────────────────────────────────

local function _create_list(bp)
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return end
    micro.InfoBar():Prompt("New list name: ", "", "Bookmark", nil,
        function(input, cancelled)
            if cancelled or input == "" then return end
            if bd[bn] == nil then return end
            local name = string.lower(string.gsub(input, "%s+", "_"))
            if string.find(name, "[^%w_-]") then
                micro.InfoBar():Message("List names may only contain letters, digits, _ and -")
                return
            end
            if name == "default" or bd[bn].lists[name] then
                micro.InfoBar():Message("List '" .. name .. "' already exists")
                return
            end
            bd[bn].lists[name] = {marks = {}, names = {}}
            bd[bn].active = name
            _redraw(bp)
            micro.InfoBar():Message("Created and switched to list '" .. name .. "'")
        end
    )
end

local function _switch_list(bp)
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return end
    -- build a list of available names for the prompt hint
    local names = {}
    for k in pairs(bd[bn].lists) do table.insert(names, k) end
    table.sort(names)
    micro.InfoBar():Prompt("Switch to list [" .. table.concat(names, ", ") .. "]: ",
        bd[bn].active, "Bookmark", nil,
        function(input, cancelled)
            if cancelled or input == "" then return end
            if bd[bn] == nil then return end
            if not bd[bn].lists[input] then
                micro.InfoBar():Message("No list named '" .. input .. "'")
                return
            end
            bd[bn].active = input
            _redraw(bp)
            local act = _active(bn)
            micro.InfoBar():Message("Switched to list '" .. input .. "'  (" .. #act.marks .. " bookmarks)")
        end
    )
end

local function _delete_list(bp)
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local cur = bd[bn].active
    if cur == "default" then
        micro.InfoBar():Message("Cannot delete the default list")
        return
    end
    local n = #_active(bn).marks
    local plural = n == 1 and "bookmark" or "bookmarks"
    micro.InfoBar():Prompt("Delete list '" .. cur .. "' (" .. n .. " " .. plural .. ")? (y/n): ",
        "", "Bookmark", nil,
        function(input, cancelled)
            if not cancelled and (input == "y" or input == "Y") then
                if bd[bn] == nil then return end
                bd[bn].lists[cur] = nil
                bd[bn].active = "default"
                local sidecar = _lfile(bn, cur)
                if goos.Stat(sidecar) ~= nil then goos.Remove(sidecar) end
                _redraw(bp)
                micro.InfoBar():Message("Deleted list '" .. cur .. "'")
            end
        end
    )
end

local function _list_lists(bp)
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local lines = {}
    local names = {}
    for k in pairs(bd[bn].lists) do table.insert(names, k) end
    table.sort(names)
    for _, name in ipairs(names) do
        local lst    = bd[bn].lists[name]
        local active = name == bd[bn].active and " ◀" or ""
        table.insert(lines, fmt.Sprintf("  %-20s  %d bookmarks%s", name, #lst.marks, active))
    end
    local text    = "Bookmark lists — " .. (bn:match("([^/]+)$") or bn) .. "\n\n" .. table.concat(lines, "\n") .. "\n"
    local listbuf = buffer.NewBuffer(text, "bookmark-lists")
    listbuf.Type.Readonly = true
    listbuf.Type.Scratch  = true
    bp:HSplitBuf(listbuf)
end

-- ── persistence ───────────────────────────────────────────────────────────────

-- minimal JSON for sidecar files (schema v1)
local function _jstr(s)
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, '"', '\\"')
    s = string.gsub(s, "\n", "\\n")
    s = string.gsub(s, "\r", "\\r")
    s = string.gsub(s, "\t", "\\t")
    return '"' .. s .. '"'
end

local function _json_decode(s)
    local pos = 1
    local function skip()
        while pos <= #s do
            local c = string.sub(s, pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then pos = pos + 1
            else break end
        end
    end
    local parse
    local function parse_str()
        if string.sub(s, pos, pos) ~= '"' then return nil end
        pos = pos + 1
        local buf = {}
        while pos <= #s do
            local c = string.sub(s, pos, pos)
            if c == '"' then pos = pos + 1; return table.concat(buf) end
            if c == "\\" then
                pos = pos + 1
                local nc = string.sub(s, pos, pos)
                if     nc == "n" then table.insert(buf, "\n")
                elseif nc == "r" then table.insert(buf, "\r")
                elseif nc == "t" then table.insert(buf, "\t")
                else                  table.insert(buf, nc) end
                pos = pos + 1
            else
                table.insert(buf, c); pos = pos + 1
            end
        end
        return nil
    end
    local function parse_num()
        local start = pos
        while pos <= #s do
            local c = string.sub(s, pos, pos)
            if string.match(c, "[%d%-%.eE+]") then pos = pos + 1 else break end
        end
        return tonumber(string.sub(s, start, pos - 1))
    end
    parse = function()
        skip()
        if pos > #s then return nil end
        local c = string.sub(s, pos, pos)
        if c == "{" then
            pos = pos + 1; local t = {}; skip()
            if string.sub(s, pos, pos) == "}" then pos = pos + 1; return t end
            while pos <= #s do
                skip(); local k = parse_str(); skip()
                if string.sub(s, pos, pos) == ":" then pos = pos + 1 end
                t[k] = parse(); skip()
                local nc = string.sub(s, pos, pos)
                if nc == "," then pos = pos + 1
                else if nc == "}" then pos = pos + 1 end; return t end
            end
            return t
        elseif c == "[" then
            pos = pos + 1; local t = {}; skip()
            if string.sub(s, pos, pos) == "]" then pos = pos + 1; return t end
            while pos <= #s do
                table.insert(t, parse()); skip()
                local nc = string.sub(s, pos, pos)
                if nc == "," then pos = pos + 1
                else if nc == "]" then pos = pos + 1 end; return t end
            end
            return t
        elseif c == '"' then return parse_str()
        elseif c == "t" then pos = pos + 4; return true
        elseif c == "f" then pos = pos + 5; return false
        elseif c == "n" then pos = pos + 4; return nil
        else return parse_num() end
    end
    local ok, result = pcall(parse)
    if ok then return result end
    return nil
end

-- ── content anchoring ──────────────────────────────────────────────────────────
-- A persisted bookmark (schema v2) stores not just a line number but the line's
-- text and its immediate neighbours. On load the mark is relocated by content so
-- it survives edits made while the file was closed — insertions above it, function
-- reordering, light edits to the line itself. The stored line number is only a
-- hint and the final fallback: relocation never lands on a worse-than-stored guess.

local ANCHOR_CTX_MAX = 200    -- cap stored before/after context length
local DICE_THRESHOLD = 0.6    -- min bigram-Dice similarity to accept a line as the mark
local DICE_RADIUS    = 2000   -- bound the (costly) fuzzy scan to ±this many lines

-- collapse internal whitespace and trim ends, for tolerant comparison
local function _norm(s)
    if s == nil then return "" end
    s = string.gsub(s, "%s+", " ")
    s = string.gsub(s, "^ ", "")
    s = string.gsub(s, " $", "")
    return s
end

-- Sørensen–Dice similarity over character bigrams (0..1). Pure arithmetic — no
-- bitwise ops, so it runs on micro's Lua 5.1 runtime.
local function _dice(a, b)
    if a == b then return 1.0 end
    if #a < 2 or #b < 2 then return 0.0 end
    local ga, tota = {}, 0
    for i = 1, #a - 1 do
        local g = string.sub(a, i, i + 1)
        ga[g] = (ga[g] or 0) + 1
        tota = tota + 1
    end
    local inter, totb = 0, 0
    local gb = {}
    for i = 1, #b - 1 do
        local g = string.sub(b, i, i + 1)
        gb[g] = (gb[g] or 0) + 1
        totb = totb + 1
    end
    for g, nb in pairs(gb) do
        local na = ga[g]
        if na then inter = inter + math.min(na, nb) end
    end
    if tota + totb == 0 then return 0.0 end
    return (2 * inter) / (tota + totb)
end

-- Relocate one anchor against the current buffer content.
--   getline(i): 0-indexed current line text (nil out of range)
--   nlines    : current line count
--   a         : anchor {y=, text=, before=, after=}
-- Returns the resolved 0-indexed line. Context and proximity only break ties
-- between lines that already clear the text bar; they never rescue a poor match.
local function _resolve_anchor(getline, nlines, a)
    local y = a.y or 0
    local function clamp(i)
        if nlines <= 0 then return 0 end
        if i < 0 then return 0 end
        if i > nlines - 1 then return nlines - 1 end
        return i
    end
    -- no usable anchor text (v0/v1 entry, or a blank line): trust the number
    if a.text == nil or _norm(a.text) == "" then return clamp(y) end
    -- A. position fast-path — the common case of an unchanged file
    if y >= 0 and y <= nlines - 1 and getline(y) == a.text then return y end

    local ntext   = _norm(a.text)
    local nbefore = a.before and _norm(a.before) or nil
    local nafter  = a.after  and _norm(a.after)  or nil

    local function ctx_prox(i, base)
        local s = base
        if nbefore and nbefore ~= "" and i > 0 and _norm(getline(i - 1)) == nbefore then s = s + 0.15 end
        if nafter  and nafter  ~= "" and i < nlines - 1 and _norm(getline(i + 1)) == nafter then s = s + 0.15 end
        local dist = i > y and (i - y) or (y - i)
        s = s + 0.1 / (1 + dist)   -- nearer the stored line wins ties
        return s
    end

    local best_i, best_s = nil, -1

    -- B. exact-text candidates
    for i = 0, nlines - 1 do
        if getline(i) == a.text then
            local s = ctx_prox(i, 2.0)
            if s > best_s then best_s, best_i = s, i end
        end
    end
    if best_i ~= nil then return best_i end

    -- C. normalized-text candidates (tolerates reindentation / trailing space)
    for i = 0, nlines - 1 do
        if _norm(getline(i)) == ntext then
            local s = ctx_prox(i, 1.5)
            if s > best_s then best_s, best_i = s, i end
        end
    end
    if best_i ~= nil then return best_i end

    -- D. fuzzy similarity — only reached when the line was edited and moved. The
    -- cheap exact/normalized tiers above are whole-file, so an unedited line that
    -- moved any distance is already found; fuzzy is bounded to a window around the
    -- stored line to keep open-time cost predictable on very large files.
    local lo = y - DICE_RADIUS; if lo < 0 then lo = 0 end
    local hi = y + DICE_RADIUS; if hi > nlines - 1 then hi = nlines - 1 end
    for i = lo, hi do
        local d = _dice(ntext, _norm(getline(i)))
        if d >= DICE_THRESHOLD then
            local s = ctx_prox(i, d)
            if s > best_s then best_s, best_i = s, i end
        end
    end
    if best_i ~= nil then return best_i end

    -- E. nothing credible: keep the stored line (never worse than today)
    return clamp(y)
end

local function _encode_list(lst, buf)
    local nlines = buf and buf:LinesNum() or 0
    -- capped context line, or nil if out of range / unavailable
    local function ctx(i)
        if not buf or i < 0 or i > nlines - 1 then return nil end
        local s = buf:Line(i)
        if s == nil then return nil end
        if #s > ANCHOR_CTX_MAX then s = string.sub(s, 1, ANCHOR_CTX_MAX) end
        return s
    end
    local marks = {}
    for _, y in ipairs(lst.marks) do
        local parts = {'"y":' .. y}
        local name  = lst.names[y]
        if name and name ~= "" then
            table.insert(parts, '"name":' .. _jstr(name))
        end
        -- anchor text is stored uncapped so the exact fast-path can match long lines
        if buf and y >= 0 and y <= nlines - 1 then
            local text = buf:Line(y)
            if text ~= nil then
                table.insert(parts, '"text":' .. _jstr(text))
                local b = ctx(y - 1)
                local a = ctx(y + 1)
                if b ~= nil then table.insert(parts, '"before":' .. _jstr(b)) end
                if a ~= nil then table.insert(parts, '"after":'  .. _jstr(a)) end
            end
        end
        table.insert(marks, "{" .. table.concat(parts, ",") .. "}")
    end
    return '{"v":2,"marks":[' .. table.concat(marks, ",") .. "]}"
end

local function _encode_mnemonics(mn)
    local parts = {}
    for letter, y in pairs(mn) do
        table.insert(parts, _jstr(letter) .. ":" .. tostring(y))
    end
    return '{"v":1,"mn":{' .. table.concat(parts, ",") .. "}}"
end

local function _load_list(bn, listname)
    local data, err = ioutil.ReadFile(_lfile(bn, listname))
    if err ~= nil then return end
    local lst = bd[bn].lists[listname]
    if lst == nil then
        lst = {marks = {}, names = {}}
        bd[bn].lists[listname] = lst
    end
    local str   = fmt.Sprintf("%s", data)
    local first = string.match(str, "^%s*(.)")
    local entries = {}   -- {y, name, text, before, after}
    if first == "{" then
        local obj = _json_decode(str)
        if obj and obj.marks then
            for i = 1, #obj.marks do
                local m = obj.marks[i]
                if m and m.y then
                    entries[#entries+1] = {
                        y = m.y, name = m.name,
                        text = m.text, before = m.before, after = m.after,
                    }
                end
            end
        end
    else
        -- legacy v0 CSV fallback (line numbers only)
        for entry in string.gmatch(str, "([^,]+)") do
            local colon = string.find(entry, ":", 1, true)
            if colon then
                local y     = tonumber(string.sub(entry, 1, colon - 1))
                local label = string.sub(entry, colon + 1)
                if y then entries[#entries+1] = {y = y, name = (label ~= "" and label or nil)} end
            else
                local y = tonumber(entry)
                if y then entries[#entries+1] = {y = y} end
            end
        end
    end
    -- relocate each mark by content (when an anchor is present), then commit the
    -- deduped, sorted result. Relocation can move and reorder marks.
    local buf     = bd[bn].buf
    local nlines  = buf and buf:LinesNum() or 0
    local getline = buf and function(i) return buf:Line(i) end or nil
    local seen    = {}
    for _, e in ipairs(entries) do
        local y = e.y
        if getline and e.text ~= nil then
            y = _resolve_anchor(getline, nlines, e)
        end
        if not seen[y] then
            seen[y] = true
            lst.marks[#lst.marks+1] = y
            if e.name and e.name ~= "" then lst.names[y] = e.name end
        elseif e.name and e.name ~= "" and not lst.names[y] then
            lst.names[y] = e.name
        end
    end
    table.sort(lst.marks)
end

local function _load(bn)
    -- Persist unless explicitly disabled. micro opens command-line files before
    -- running init() (where the option is registered), so onBufferOpen→_load sees
    -- the option as nil; gating on `not <nil>` would wrongly skip loading. Treat
    -- nil (unregistered, default-on) as enabled and only bail on an explicit false.
    if config.GetGlobalOption("bookmark.persist") == false then return end
    -- load default list (backward compat path)
    _load_list(bn, "default")
    -- discover additional lists by scanning for .list.* sidecar files
    local base  = _bfile(bn)
    local dir   = _bdir()
    local files, err = ioutil.ReadDir(dir)
    if err == nil then
        local prefix = base .. ".list."
        for i = 1, #files do
            local fi = files[i]
            local fname = dir .. "/" .. fi:Name()
            if string.sub(fname, 1, #prefix) == prefix then
                local listname = string.sub(fname, #prefix + 1)
                if listname ~= "" and not string.find(listname, "[^%w_-]") then
                    _load_list(bn, listname)
                end
            end
        end
    end
    -- load mnemonics (shared across all lists)
    local mdata, merr = ioutil.ReadFile(_bfile(bn) .. ".mn")
    if merr == nil then
        local str   = fmt.Sprintf("%s", mdata)
        local first = string.match(str, "^%s*(.)")
        if first == "{" then
            local obj = _json_decode(str)
            if obj and obj.mn then
                for letter, y in pairs(obj.mn) do
                    if string.match(letter, "^[A-Z]$") and type(y) == "number" then
                        bd[bn].mnemonics[letter] = y
                    end
                end
            end
        else
            for entry in string.gmatch(str, "([^,]+)") do
                local eq = string.find(entry, "=", 1, true)
                if eq then
                    local letter = string.sub(entry, 1, eq - 1)
                    local y      = tonumber(string.sub(entry, eq + 1))
                    if string.match(letter, "^[A-Z]$") and y then
                        bd[bn].mnemonics[letter] = y
                    end
                end
            end
        end
    end
end

local function _save_list(bn, listname)
    goos.MkdirAll(_bdir(), 493)  -- 0755
    local lst  = bd[bn].lists[listname]
    local name = _lfile(bn, listname)
    if lst == nil or #lst.marks == 0 then
        if goos.Stat(name) ~= nil then goos.Remove(name) end
        return
    end
    ioutil.WriteFile(name, _encode_list(lst, bd[bn].buf), 420)
end

local function _save(bn)
    -- see _load: persist unless explicitly disabled (option may be unregistered early)
    if config.GetGlobalOption("bookmark.persist") == false then return end
    for listname in pairs(bd[bn].lists) do
        _save_list(bn, listname)
    end
    local mname = _bfile(bn) .. ".mn"
    if next(bd[bn].mnemonics) ~= nil then
        ioutil.WriteFile(mname, _encode_mnemonics(bd[bn].mnemonics), 420)
    elseif goos.Stat(mname) ~= nil then
        goos.Remove(mname)
    end
end

-- ── position tracking ─────────────────────────────────────────────────────────

local function _save_pre_state(bp)
    if bp == nil then return end
    local bn = bp.Buf:GetName()
    if not (bn and bd[bn]) then return end
    bd[bn].curpos = -bp.Cursor.Loc
    bd[bn].onmark = false
    local act = _active(bn)
    for _, y in ipairs(act.marks) do
        if y == bd[bn].curpos.Y then bd[bn].onmark = true; break end
    end
    if bp.Cursor:HasSelection() then
        bd[bn].sel = -bp.Cursor.CurSelection
    else
        bd[bn].sel = {{Y = bd[bn].curpos.Y}, {Y = bd[bn].curpos.Y}}
    end
end

local function _update(bp)
    local bn  = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local newl = bp.Buf:LinesNum()
    local diff = math.abs(newl - bd[bn].oldl)
    if diff ~= 0 then
        if newl < bd[bn].oldl then diff = -diff end
        bd[bn].oldl = newl
        local c    = bp.Buf:GetActiveCursor()
        local curY = bd[bn].curpos and bd[bn].curpos.Y
        local s1   = bd[bn].sel and bd[bn].sel[1] and bd[bn].sel[1].Y
        local s2   = bd[bn].sel and bd[bn].sel[2] and bd[bn].sel[2].Y
        -- update all lists
        for _, lst in pairs(bd[bn].lists) do
            for i, y in ipairs(lst.marks) do
                if (diff > 0 and curY and y >= curY) or (diff < 0 and y > c.Loc.Y) then
                    local newy = (s1 and s2 and s1 < y and s2 > y)
                        and s1
                        or  math.max(0, y + diff)
                    if lst.names[y] and newy ~= y then
                        lst.names[newy] = lst.names[y]
                        lst.names[y]    = nil
                    end
                    lst.marks[i] = newy
                end
            end
        end
        _dedupe(bp)
        _redraw(bp)
    end
end

-- ── event handlers ────────────────────────────────────────────────────────────

-- show bookmark info in InfoBar when cursor moves onto a bookmarked line
local function _check_cursor_on_mark(bp)
    if bp == nil then return end
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local act = _active(bn)
    if #act.marks == 0 then return end
    local y = bp.Buf:GetActiveCursor().Loc.Y
    for i, my in ipairs(act.marks) do
        if my == y then
            local name = act.names[y] or ""
            local msg  = "Bookmark " .. i .. "/" .. #act.marks
            if name ~= "" then msg = msg .. "  " .. name end
            micro.InfoBar():Message(msg)
            return
        end
    end
end

for _, ev in ipairs({
    "onCursorUp", "onCursorDown", "onCursorLeft", "onCursorRight",
    "onPageUp", "onPageDown", "onHalfPageUp", "onHalfPageDown",
    "onCursorStart", "onCursorEnd", "onStartOfLine", "onEndOfLine",
    "onStartOfText", "onEndOfText",
    "onWordRight", "onWordLeft",
    "onParagraphPrevious", "onParagraphNext",
    "onMousePress",
    "onFind", "onFindNext", "onFindPrevious",
    "onSelectUp", "onSelectDown", "onSelectLeft", "onSelectRight",
    "onSelectWordRight", "onSelectWordLeft",
    "onSelectToStart", "onSelectToEnd",
    "onSelectToStartOfLine", "onSelectToEndOfLine",
    "onSelectLine",
}) do
    _G[ev] = function(bp) _check_cursor_on_mark(bp) end
end

function onBeforeTextEvent(_b, _t)
    _save_pre_state(micro.CurPane())
end

function onInsertNewline(_bp)
    local bp = micro.CurPane()
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return end
    local cx = bd[bn].curpos and bd[bn].curpos.X
    if cx and cx ~= 0 and bd[bn].onmark then
        bd[bn].oldl = bp.Buf:LinesNum()
    else
        _update(bp)
    end
end

function onDuplicateLine(bp) _update(bp) end
function onDelete(bp)        _update(bp) end
function onCut(bp)           _update(bp) end
function onPaste(bp)         _update(bp) end
function onCutLine(bp)       _update(bp) end
function onBackspace(bp)     _update(bp) end
function onUndo(bp)          _update(bp) end
function onRedo(bp)          _update(bp) end

-- intercept Enter in any open picker pane
function preInsertNewline(bp)
    local p = _pickers[bp.Buf:GetName()]
    if p == nil then return true end
    local row = bp.Buf:GetActiveCursor().Loc.Y
    local e   = p.entries[row + 1]
    if e then
        local tgt_bp = p.source_bp
        -- for global list, find the correct pane if it differs from source
        -- use actual_bn (real buffer name) for pane lookup, not the display name
        local lookup_bn = e.actual_bn or e.bufname
        if lookup_bn and lookup_bn ~= p.source_bn then
            local tabs = micro.Tabs()
            if tabs and tabs.List then
                for _, tab in ipairs(tabs.List) do
                    if tab and tab.Panes then
                        for _, pane in ipairs(tab.Panes) do
                            if pane and pane.Buf and pane.Buf:GetName() == lookup_bn then
                                tgt_bp = pane; break
                            end
                        end
                    end
                end
            end
        end
        local sc = tgt_bp.Buf:GetActiveCursor()
        sc:ResetSelection(); sc.Loc.X = 0; sc.Loc.Y = e.y
        tgt_bp:Relocate()
        micro.InfoBar():Message("line " .. (e.y + 1) .. "  Ctrl-Q to close")
    end
    return false
end

-- status line token $(bookmarkpos) → "[BM 2/5]"
function bookmarkpos(buf)
    local bn = buf:GetName()
    if bd[bn] == nil then return "" end
    local act = _active(bn)
    if #act.marks == 0 then return "" end
    local bp = micro.CurPane()
    if bp == nil then return "[BM ?/" .. #act.marks .. "]" end
    local y   = bp.Buf:GetActiveCursor().Loc.Y
    local pos = #act.marks
    for i, my in ipairs(act.marks) do
        if my == y then pos = i; break
        elseif my > y then pos = math.max(1, i - 1); break end
    end
    return "[BM " .. pos .. "/" .. #act.marks .. "]"
end

function onBufferOpen(b)
    local bn = b:GetName()
    bd[bn] = {
        lists     = {["default"] = {marks = {}, names = {}}},
        active    = "default",
        mnemonics = {},
        curpos    = {X=0, Y=0},
        sel       = {{Y=0},{Y=0}},
        onmark    = false,
        oldl      = 0,
        buf       = b,
        panes     = 0
    }
    _load(bn)
end

function onBufPaneOpen(bp)
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return end
    bd[bn].panes = (bd[bn].panes or 0) + 1
    bd[bn].oldl  = bp.Buf:LinesNum()
    _save_pre_state(bp)
    _redraw(bp)
end

-- Persist on quit, not only on file save: toggling a bookmark does not mark the
-- buffer modified, so bookmark-only changes (e.g. on a file you never edit) would
-- otherwise be lost. This must run in `preQuit`, NOT `onQuit`: micro runs the
-- post-action `onQuit` callback only after the Quit action, but quitting the last
-- pane calls runtime.Goexit() inside that action and never returns — so onQuit
-- never fires on the quit that exits the editor. `preQuit` runs before the action.
-- Returning nothing lets the quit proceed (a `false` return would cancel it).
local function _persist_if_clean(bp)
    local bn = bp.Buf:GetName()
    -- only persist a clean buffer: a modified buffer may be discarded on quit, and
    -- its line numbers would not match the on-disk file.
    if bd[bn] ~= nil and not bp.Buf:Modified() then _save(bn) end
end

function preQuit(bp)
    _persist_if_clean(bp)
end

-- closing the whole editor (QuitAll): persist every clean open buffer
function preQuitAll(_bp)
    for bn, data in pairs(bd) do
        if data and data.buf and not data.buf:Modified() then _save(bn) end
    end
end

function onQuit(bp)
    local bn = bp.Buf:GetName()
    if _pickers[bn] then _pickers[bn] = nil end
    for pname, p in pairs(_pickers) do
        if p.source_bn == bn then _pickers[pname] = nil end
    end
    if bd[bn] == nil then return end
    bd[bn].panes = (bd[bn].panes or 1) - 1
    if bd[bn].panes <= 0 then bd[bn] = nil end
end

function onSave(bp)
    if bp.Buf.Type.Kind ~= buffer.BTDefault then return false end
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return false end
    _save(bn)
    return false
end

function init()
    config.RegisterGlobalOption("bookmark", "gutter_style", "info")
    config.RegisterGlobalOption("bookmark", "persist",       true)
    config.RegisterGlobalOption("bookmark", "scope",         "global")

    config.MakeCommand("toggleBookmark",    _toggle,           config.OptionComplete)
    config.MakeCommand("nextBookmark",      _next,             config.OptionComplete)
    config.MakeCommand("prevBookmark",      _prev,             config.OptionComplete)
    config.MakeCommand("clearBookmarks",    _clear,            config.OptionComplete)
    config.MakeCommand("nameBookmark",      _name_bookmark,    config.OptionComplete)
    config.MakeCommand("gotoBookmark",      _goto_bookmark,    config.OptionComplete)
    config.MakeCommand("listBookmarks",     _list,             config.OptionComplete)
    config.MakeCommand("listAllBookmarks",  _list_all,         config.OptionComplete)
    config.MakeCommand("bookmarkPattern",   _bookmark_pattern, config.OptionComplete)
    config.MakeCommand("grepBookmarks",     _grep_bookmarks,   config.OptionComplete)
    config.MakeCommand("exportBookmarks",   _export,           config.OptionComplete)
    config.MakeCommand("setMnemonic",       _set_mnemonic,     config.OptionComplete)
    config.MakeCommand("gotoMnemonic",      _goto_mnemonic,    config.OptionComplete)
    config.MakeCommand("createList",        _create_list,      config.OptionComplete)
    config.MakeCommand("switchList",        _switch_list,      config.OptionComplete)
    config.MakeCommand("deleteList",        _delete_list,      config.OptionComplete)
    config.MakeCommand("listLists",         _list_lists,       config.OptionComplete)
    config.MakeCommand("bookmarkVersion",
        function() micro.InfoBar():Message("bookmark v" .. VERSION) end,
        config.OptionComplete)

    config.TryBindKey("Ctrl-F2",      "command:toggleBookmark",   true)
    config.TryBindKey("CtrlShift-F2", "command:clearBookmarks",   true)
    config.TryBindKey("F2",           "command:nextBookmark",      true)
    config.TryBindKey("Shift-F2",     "command:prevBookmark",      true)
    config.TryBindKey("Alt-F2",       "command:listBookmarks",     true)

    micro.SetStatusInfoFn("bookmarkpos")

    config.AddRuntimeFile("bookmark", config.RTHelp, "help/bookmark.md")
end

-- Test seam: the unit-test harness sets _BOOKMARK_TEST before loading this file
-- and reads the pure helpers back through this table. Inert inside micro, where
-- _BOOKMARK_TEST is never set, so it has no effect on the plugin at runtime.
if rawget(_G, "_BOOKMARK_TEST") then
    _G._bookmark_test_exports = {
        jstr             = _jstr,
        json_decode      = _json_decode,
        encode_list      = _encode_list,
        encode_mnemonics = _encode_mnemonics,
        norm             = _norm,
        dice             = _dice,
        resolve_anchor   = _resolve_anchor,
    }
end
