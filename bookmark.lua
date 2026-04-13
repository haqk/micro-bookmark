VERSION = "2.3.9"

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
local bd      = {}
local _picker = nil  -- active picker state

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
    return _bdir() .. "/" .. string.gsub(filepath.Abs(bn), "/", "%")
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
    _picker = {source_bp = bp, source_bn = source_bn, entries = entries}
    local listbuf = buffer.NewBuffer(_build_picker_lines(entries), "Bookmarks")
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
    micro.InfoBar():Prompt("Bookmark pattern: ", "", "Bookmark", nil,
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
            if bd[bn].lists[name] then
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

-- file for a named list: default uses the base path (backward compat), others get a suffix
local function _lfile(bn, listname)
    if listname == "default" then return _bfile(bn) end
    return _bfile(bn) .. ".list." .. listname
end

local function _load_list(bn, listname)
    local data, err = ioutil.ReadFile(_lfile(bn, listname))
    if err ~= nil then return end
    local lst = bd[bn].lists[listname]
    if lst == nil then
        lst = {marks = {}, names = {}}
        bd[bn].lists[listname] = lst
    end
    local str = fmt.Sprintf("%s", data)
    for entry in string.gmatch(str, "([^,]+)") do
        local colon = string.find(entry, ":", 1, true)
        if colon then
            local y     = tonumber(string.sub(entry, 1, colon - 1))
            local label = string.sub(entry, colon + 1)
            if y then
                table.insert(lst.marks, y)
                if label ~= "" then lst.names[y] = label end
            end
        else
            local y = tonumber(entry)
            if y then table.insert(lst.marks, y) end
        end
    end
end

local function _load(bn)
    if not config.GetGlobalOption("bookmark.persist") then return end
    -- load default list (backward compat path)
    _load_list(bn, "default")
    -- discover additional lists by scanning for .list.* sidecar files
    local base  = _bfile(bn)
    local dir   = _bdir()
    local files, err = ioutil.ReadDir(dir)
    if err == nil then
        local prefix = base .. ".list."
        for _, fi in ipairs(files) do
            local fname = dir .. "/" .. fi:Name()
            if string.sub(fname, 1, #prefix) == prefix then
                local listname = string.sub(fname, #prefix + 1)
                -- skip mnemonics and other known suffixes
                if listname ~= "" and not string.find(listname, ".", 1, true) then
                    _load_list(bn, listname)
                end
            end
        end
    end
    -- load mnemonics (shared across all lists)
    local mdata, merr = ioutil.ReadFile(_bfile(bn) .. ".mn")
    if merr == nil then
        local str = fmt.Sprintf("%s", mdata)
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

local function _save_list(bn, listname)
    goos.MkdirAll(_bdir(), 493)  -- 0755
    local lst  = bd[bn].lists[listname]
    local name = _lfile(bn, listname)
    if lst == nil or #lst.marks == 0 then
        if goos.Stat(name) ~= nil then goos.Remove(name) end
        return
    end
    local parts = {}
    for _, y in ipairs(lst.marks) do
        local label = lst.names[y] or ""
        table.insert(parts, label ~= "" and (y .. ":" .. label) or tostring(y))
    end
    ioutil.WriteFile(name, table.concat(parts, ","), 420)
end

local function _save(bn)
    if not config.GetGlobalOption("bookmark.persist") then return end
    for listname in pairs(bd[bn].lists) do
        _save_list(bn, listname)
    end
    -- save mnemonics
    local mname  = _bfile(bn) .. ".mn"
    local mparts = {}
    for letter, y in pairs(bd[bn].mnemonics) do
        table.insert(mparts, letter .. "=" .. tostring(y))
    end
    if #mparts > 0 then
        ioutil.WriteFile(mname, table.concat(mparts, ","), 420)
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
                if diff > 0 and curY and y >= curY or diff < 0 and y > c.Loc.Y then
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

function onCursorUp(bp)   _check_cursor_on_mark(bp) end
function onCursorDown(bp) _check_cursor_on_mark(bp) end
function onMousePress(bp) _check_cursor_on_mark(bp) end
function onPageUp(bp)     _check_cursor_on_mark(bp) end
function onPageDown(bp)   _check_cursor_on_mark(bp) end

function onBeforeTextEvent(b, t)
    _save_pre_state(micro.CurPane())
end

function onInsertNewline(bp)
    bp = micro.CurPane()
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

-- intercept Enter in the Bookmarks picker pane
function preInsertNewline(bp)
    if _picker == nil then return true end
    if bp.Buf:GetName() ~= "Bookmarks" then return true end
    local row = bp.Buf:GetActiveCursor().Loc.Y
    local e   = _picker.entries[row + 1]
    if e then
        local tgt_bp = _picker.source_bp
        -- for global list, find the correct pane if it differs from source
        -- use actual_bn (real buffer name) for pane lookup, not the display name
        local lookup_bn = e.actual_bn or e.bufname
        if lookup_bn and lookup_bn ~= _picker.source_bn then
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
        buf       = b
    }
    _load(bn)
end

function onBufPaneOpen(bp)
    local bn = bp.Buf:GetName()
    if bd[bn] == nil then return end
    bd[bn].oldl = bp.Buf:LinesNum()
    _save_pre_state(bp)
    _redraw(bp)
end

function onQuit(bp)
    local bn = bp.Buf:GetName()
    if bn == "Bookmarks" then _picker = nil end
    if _picker and _picker.source_bn == bn then _picker = nil end
    bd[bn] = nil
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

    config.TryBindKey("Ctrl-F2",      "command:toggleBookmark",   true)
    config.TryBindKey("CtrlShift-F2", "command:clearBookmarks",   true)
    config.TryBindKey("F2",           "command:nextBookmark",      true)
    config.TryBindKey("Shift-F2",     "command:prevBookmark",      true)
    config.TryBindKey("Alt-F2",       "command:listBookmarks",     true)

    micro.SetStatusInfoFn("bookmarkpos")

    config.AddRuntimeFile("bookmark", config.RTHelp, "help/bookmark.md")
end
