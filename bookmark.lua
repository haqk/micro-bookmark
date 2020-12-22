VERSION = "2.0.0"

local micro = import("micro")
local buffer = import("micro/buffer")
local config = import("micro/config")

-- table of bookmarks, where each bookmark is a line number
local _marks = {}

-- mark/unmark current line
function _toggle(bp)
	local c = bp.Buf:GetActiveCursor()
	local newMark = c.Loc.Y
	local oldMark = false
	
	-- if there's already a mark here, remove it from the table
	-- and clear the gutter prior to redrawing all marks later
	for i,v in ipairs(_marks) do
		if (v == newMark) then
			oldMark = true
			table.remove(_marks, i)
			bp.Buf:ClearMessages("bookmark")
			break
		end
	end
	
	-- if there wasn't already a mark here, add one to the table
	if (oldMark == false) then	
		table.insert(_marks, newMark)
	end

	-- if there are any bookmarks left in the table, sort and redraw
	if #_marks > 0 then
		table.sort(_marks)
		-- redraw all marks in table
		for i,v in ipairs(_marks) do
			bp.Buf:AddMessage(buffer.NewMessageAtLine("bookmark", "", v + 1, buffer.MTInfo))
		end
	end
end

-- jump to next bookmark
function _next(bp)
	if #_marks == 0 then return; end

	local c = bp.Buf:GetActiveCursor()

	-- look to see if there are any marks lower in the buffer
	local noMoreBelow = true
	for i,y in ipairs(_marks) do
		if (y > c.Loc.Y) then
			c.Loc.Y = y
			noMoreBelow = false
			break
		end
	end

	-- if there's nothing lower, go to the first (highest) mark
	if (noMoreBelow == true) then
		c.Loc.Y = _marks[1]
	end

	bp:Relocate()
end

-- jump to previous bookmark
function _prev(bp)
	if #_marks == 0 then return; end

	local c = bp.Buf:GetActiveCursor()

	-- look to see if there are any marks higher in the buffer
	local noMoreAbove = true
	local i = #_marks
	while (true) do

		local y = _marks[i]

		if (y < c.Loc.Y) then
			c.Loc.Y = y
			noMoreAbove = false
			i = 1
		end

	    i = i - 1
	    if (i == 0) then break; end
	end
	
	-- if there's nothing higher, go to the last (lowest) mark
	if (noMoreAbove == true) then
		c.Loc.Y = _marks[#_marks]
	end

	bp:Relocate()
end

function init()
	-- setup our commands with autocomplete
	config.MakeCommand("toggleBookmark", _toggle, config.OptionComplete)
	config.MakeCommand("nextBookmark", _next, config.OptionComplete)
	config.MakeCommand("prevBookmark", _prev, config.OptionComplete)

	-- setup default bindings
	config.TryBindKey("Ctrl-F2", "command:toggleBookmark", false)
	config.TryBindKey("F2", "command:nextBookmark", false)
	config.TryBindKey("Shift-F2", "command:prevBookmark", false)

	-- add our help topic
    config.AddRuntimeFile("bookmark", config.RTHelp, "help/bookmark.md")
end
