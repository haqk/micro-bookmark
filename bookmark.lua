VERSION = "2.2.3"

local micro = import("micro")
local buffer = import("micro/buffer")
local config = import("micro/config")
local fmt = import("fmt")
local goos = import("os")
local ioutil = import("io/ioutil")
local filepath = import("path/filepath")

-- buffer count
local bc = 0
-- buffer bookmark data
local bd = {}

-- mark/unmark current line
function _toggle(bp)
	local bn = bp.Buf:GetName()

	local c = bp.Buf:GetActiveCursor()
	local newy = c.Loc.Y
	local oldy = false
	
	-- remove mark if already present
	for i,y in ipairs(bd[bn].marks) do
		if y == newy then
			oldy = true
			table.remove(bd[bn].marks, i)
			break
		end
	end

	-- add mark if not already present
	if oldy == false then	
		table.insert(bd[bn].marks, newy)
	end

	-- if there are marks, sort
	if #bd[bn].marks > 0 then
		table.sort(bd[bn].marks)
	end

	_redraw(bp)
end

-- clear all bookmarks
function _clear(bp)
	local bn = bp.Buf:GetName()

	bd[bn].marks = {}
	collectgarbage()

	bp.Buf:ClearMessages("bookmark")
	_gutter(bp, #bd[bn].marks.."", 0)
end

-- jump to next bookmark
function _next(bp)
	local bn = bp.Buf:GetName()

	-- no action if no marks
	if #bd[bn].marks == 0 then return; end

	local c = bp.Buf:GetActiveCursor()

	-- look to see if there are any marks lower in the buffer
	local noneBelow = true
	for i,y in ipairs(bd[bn].marks) do
		if y > c.Loc.Y then
			c:ResetSelection()
			c.Loc.X = 0
			c.Loc.Y = y
			noneBelow = false
			break
		end
	end

	-- if there's nothing lower, go to the first (highest) mark
	if noneBelow == true then
		c:ResetSelection()
		c.Loc.X = 0
		c.Loc.Y = bd[bn].marks[1]
	end

	bp:Relocate()
end

-- jump to previous bookmark
function _prev(bp)
	local bn = bp.Buf:GetName()

	-- no action if no marks
	if #bd[bn].marks == 0 then return; end

	local c = bp.Buf:GetActiveCursor()

	-- look to see if there are any marks higher in the buffer
	local noneAbove = true
	local i = #bd[bn].marks
	while (true) do

		local y = bd[bn].marks[i]

		if y < c.Loc.Y then
			c:ResetSelection()
			c.Loc.X = 0
			c.Loc.Y = y
			noneAbove = false
			i = 1
		end

	    i = i - 1
	    if i == 0 then break; end
	end
	
	-- if there's nothing higher, go to the last (lowest) mark
	if noneAbove == true then
		c:ResetSelection()
		c.Loc.X = 0
		c.Loc.Y = bd[bn].marks[#bd[bn].marks]
	end

	bp:Relocate()
end


-- handlers

function onBeforeTextEvent(b, t)
	local bp = micro.CurPane()

	--~ if t.EventType == 1 then
		--~ micro.InfoBar():Message('TextEventInsert')
	--~ elseif t.EventType == -1 then
		--~ micro.InfoBar():Message('TextEventRemove')
	--~ elseif t.EventType == 0 then
		--~ micro.InfoBar():Message('TextEventReplace')
	--~ end

	_save_pre_state(bp)
end

function onInsertNewline(bp)
	local bp = micro.CurPane()
	local bn = bp.Buf:GetName()

	-- if cursor is not at start of bookmarked line enter is pressed, don't move the bookmark 
	if bd[bn].curpos.X ~= 0 and bd[bn].onmark then
		bd[bn].oldl = bp.Buf:LinesNum()
	else
		_update(bp)
	end
end

function onDuplicateLine(bp)
	_update(bp)
end

function onDelete(bp)
	_update(bp)
end

function onCut(bp)
	_update(bp)
end

function onPaste(bp)
	_update(bp)
end

function onCutLine(bp)
	_update(bp)
end

function onBackspace(bp)
	_update(bp)
end

function onUndo(bp)
	_update(bp)
end

function onRedo(bp)
	_update(bp)
end

-- update bookmark positions
function _update(bp)
	local bn = bp.Buf:GetName()

	if bd[bn] == nil then return; end

	local newl = bp.Buf:LinesNum()
	local diff = math.abs(newl - bd[bn].oldl)

	-- only update if lines have been added or removed
	if diff then
		if newl < bd[bn].oldl then
			diff = -diff
		end
		bd[bn].oldl = newl

		local c = bp.Buf:GetActiveCursor()
		-- add or subtract lines for all marks below current line
		for i,y in ipairs(bd[bn].marks) do
			-- update bookmarks above cursor line when lines have been removed
			-- or update bookmarks at or below cursor line when lines have been added
			if diff > 0 and y >= bd[bn].curpos.Y or diff < 0 and y > c.Loc.Y then
				-- move bookmarks in text selection to first line of selection
				if bd[bn].sel[1].Y < y and bd[bn].sel[2].Y > y then
					bd[bn].marks[i] = bd[bn].sel[1].Y
				else
				-- otherwise just add the difference
					bd[bn].marks[i] = y + diff
				end
			end
		end

		-- after bookmarks have been moved, remove any overlapping ones
		_dedupe(bp)

		-- then redraw the lot
		_redraw(bp)
	end
end

-- remove duplicate using hash table
function _dedupe(bp)
	local bn = bp.Buf:GetName()

	local hash = {}
	local res = {}

	for k,v in ipairs(bd[bn].marks) do
	   if not hash[v] then
		   res[#res+1] = v
		   hash[v] = true
	   end
	end
	bd[bn].marks = res
end

-- clear gutter and redraw all marks
function _redraw(bp)
	local bn = bp.Buf:GetName()

	bp.Buf:ClearMessages("bookmark")

	if #bd[bn].marks > 0 then
		for i,y in ipairs(bd[bn].marks) do
			_gutter(bp, "bookmark ("..i.."/"..#bd[bn].marks..")", y + 1)
		end
	else
		-- prevent text shift caused by gutter open/close action by keeping it open
		_gutter(bp, "", 0)
	end
end

-- print gutter message
function _gutter(bp, msg, line)
	bp.Buf:AddMessage(buffer.NewMessageAtLine("bookmark", msg, line, buffer.MTInfo))
end

-- track cursor position, selected lines and whether current line is marked or not
-- this information will be used in the onAction handlers for bookmark positioning
function _save_pre_state(bp)
	-- at least in "raw" mode, bp is nil
	if bp ~= nil then
		local bn = bp.Buf:GetName()

		if bn and bd[bn] then
			-- save cursor position
			bd[bn].curpos = -bp.Cursor.Loc

			-- save mark state of current line
			bd[bn].onmark = false
			for i,y in ipairs(bd[bn].marks) do
				if y == bd[bn].curpos.Y then
					bd[bn].onmark = true
					break
				end
			end

			-- save text selection range
			if bp.Cursor:HasSelection() then
				bd[bn].sel = -bp.Cursor.CurSelection
			else
				bd[bn].sel = {
					{ Y = bd[bn].curpos.Y },
					{ Y = bd[bn].curpos.Y }
				}
			end
		end
	end
end

-- called whenever new buffer is opened
function onBufferOpen(b)
	local bn = b:GetName()

	-- skip system buffers
	-- if bn == "No name" or bn == "Log" then return; end

	-- keep count of opened buffers
	bc = bc + 1

	-- init data table
	bd[bn] = {
		-- table of bookmarks, where each bookmark is a line number
		marks = {},
		-- track cursor position
		curpos = {},
		-- track selected text
		sel = {},
		-- track bookmark state of current line
		onmark = false,
		-- track buffer lines
		oldl = 0
	}

	-- read saved bookmark locations
	name = os.getenv("HOME") .. "/.config/micro/plug/bookmark/" .. string.gsub(filepath.Abs(bn), "/", "%")
	local data, err = ioutil.ReadFile(name)

	if err == nil then
		local str = fmt.Sprintf("%s", data)
    
		for s in string.gmatch(str, "([^,]+)") do
			table.insert(bd[bn].marks, tonumber(s))
		end
	end
end

-- called when a buffer pane is ready
function onBufPaneOpen(bp)
	local bn = bp.Buf:GetName()

	-- init vars
	bd[bn].oldl = bp.Buf:LinesNum()
	_save_pre_state(bp)
	_redraw(bp)

	--~ printBufferNames()
end

-- called when buffer is closed
function onQuit(bp)
	-- decrement buffer count
	bc = bc - 1
	-- clear buffer bookmark data
	bd[bp.Buf:GetName()] = nil

	--~ printBufferNames()
end

--~ function printBufferNames()
	--~ local bufstr = ""
	--~ for bn,d in pairs(bd) do
		--~ bufstr = bufstr..(bufstr == "" and "" or " | ")..bn
	--~ end

	--~ micro.InfoBar():Message(bufstr)
--~ end

function onSave(bp)
	-- don't try to save bookmarks when it's no default buffer, but help etc.
	if bp.Buf.Type.Kind ~= buffer.BTDefault then
		return false
	end

	name = os.getenv("HOME") .. "/.config/micro/plug/bookmark/" .. string.gsub(filepath.Abs(bp.Buf:GetName()), "/", "%")

	if #bd[bp.Buf:GetName()].marks == 0 then
		-- Delete possibly existing bookmark file
		if goos.Stat(name) ~= nil then
			goos.Remove(name)
		end
		return false
	elseif #bd[bp.Buf:GetName()].marks == 1 then
		-- how to otherwise get the first element?
		for k in pairs(bd[bp.Buf:GetName()].marks) do
			data = tostring(bd[bp.Buf:GetName()].marks[k])
		end
	else
		data = table.concat(bd[bp.Buf:GetName()].marks, ",")
	end
  
	ioutil.WriteFile(name, data, 420)
	return false
end

function init()
	-- setup our commands for autocomplete
	config.MakeCommand("toggleBookmark", _toggle, config.OptionComplete)
	config.MakeCommand("nextBookmark", _next, config.OptionComplete)
	config.MakeCommand("prevBookmark", _prev, config.OptionComplete)
	config.MakeCommand("clearBookmarks", _clear, config.OptionComplete)

	-- setup default bindings
	config.TryBindKey("Ctrl-F2", "command:toggleBookmark", false)
	config.TryBindKey("CtrlShift-F2", "command:clearBookmarks", false)
	config.TryBindKey("F2", "command:nextBookmark", false)
	config.TryBindKey("Shift-F2", "command:prevBookmark", false)

	-- add our help topic
    config.AddRuntimeFile("bookmark", config.RTHelp, "help/bookmark.md")
end
