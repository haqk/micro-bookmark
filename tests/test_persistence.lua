-- Unit tests for the pure persistence helpers in bookmark.lua.
--
-- These cover the JSON encode/decode round-trip and string escaping — the parts
-- that touch on-disk data and have no dependency on micro's runtime. They do NOT
-- exercise the command handlers, which are welded to micro's editor API.
--
-- Run from the repository root:  lua5.4 tests/test_persistence.lua
-- (CI runs it in the `lua` job after luacheck.)

-- Load bookmark.lua outside micro: stub the `import` global it calls at the top
-- of the file, and flip the test seam so the pure helpers are exported.
_G._BOOKMARK_TEST = true
function import(_name)
    -- a permissive object: indexing yields a no-op function, enough for the
    -- top-level `local x = import(...)` bindings to succeed at load time.
    return setmetatable({}, { __index = function() return function() end end })
end

dofile("bookmark.lua")

local M = _G._bookmark_test_exports
assert(M, "bookmark.lua did not export _bookmark_test_exports (test seam missing?)")

-- ── tiny test runner ──────────────────────────────────────────────────────────
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.write("  FAIL: " .. name)
        if detail then io.write("  (" .. tostring(detail) .. ")") end
        io.write("\n")
    end
end
local function eq(name, got, want)
    check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end

-- ── string escaping round-trips through decode ─────────────────────────────────
-- _jstr produces a JSON string literal; wrapping it in an array and decoding
-- should give back exactly the original string.
local function roundtrip_str(s)
    return M.json_decode("[" .. M.jstr(s) .. "]")[1]
end
eq("jstr/decode: plain",        roundtrip_str("hello"),                "hello")
eq("jstr/decode: quote",        roundtrip_str('a"b'),                  'a"b')
eq("jstr/decode: backslash",    roundtrip_str([[a\b]]),                [[a\b]])
eq("jstr/decode: comma+colon",  roundtrip_str("weird,name: value"),    "weird,name: value")
eq("jstr/decode: newline+tab",  roundtrip_str("line1\nline2\ttab"),    "line1\nline2\ttab")
eq("jstr/decode: cr",           roundtrip_str("a\rb"),                 "a\rb")
eq("jstr/decode: empty",        roundtrip_str(""),                     "")

-- ── encode_list → decode round-trip ─────────────────────────────────────────────
local lst = {
    marks = { 2, 5, 11 },
    names = { [2] = "tokenizer entry", [11] = 'weird,name: with"quote' },
}
-- called without a buffer (as here) the encoder omits anchor text but still
-- records line numbers and names; schema is v2.
local dec = M.json_decode(M.encode_list(lst))
eq("encode_list: schema version", dec.v, 2)
eq("encode_list: mark count",     #dec.marks, 3)
eq("encode_list: mark1 y",        dec.marks[1].y, 2)
eq("encode_list: mark1 name",     dec.marks[1].name, "tokenizer entry")
eq("encode_list: mark2 y",        dec.marks[2].y, 5)
eq("encode_list: mark2 unnamed",  dec.marks[2].name, nil)
eq("encode_list: mark3 y",        dec.marks[3].y, 11)
eq("encode_list: mark3 special",  dec.marks[3].name, 'weird,name: with"quote')

-- names containing a newline must survive (CSV format could not represent this)
local nl = M.json_decode(M.encode_list({ marks = { 7 }, names = { [7] = "a\nb" } }))
eq("encode_list: newline name", nl.marks[1].name, "a\nb")

-- empty list encodes and decodes to an empty marks array
local empty = M.json_decode(M.encode_list({ marks = {}, names = {} }))
eq("encode_list: empty version", empty.v, 2)
eq("encode_list: empty count",   #empty.marks, 0)

-- ── encode_mnemonics → decode round-trip ────────────────────────────────────────
local mn = M.json_decode(M.encode_mnemonics({ A = 2, Z = 100 }))
eq("encode_mnemonics: version", mn.v, 1)
eq("encode_mnemonics: A",       mn.mn.A, 2)
eq("encode_mnemonics: Z",       mn.mn.Z, 100)

local mn_empty = M.json_decode(M.encode_mnemonics({}))
eq("encode_mnemonics: empty version", mn_empty.v, 1)
check("encode_mnemonics: empty table", type(mn_empty.mn) == "table")

-- ── decoder robustness ──────────────────────────────────────────────────────────
eq("decode: number",  M.json_decode('{"y":42}').y, 42)
eq("decode: true",    M.json_decode('{"b":true}').b, true)
eq("decode: false",   M.json_decode('{"b":false}').b, false)
-- garbage must not throw — _json_decode pcall-wraps and returns nil on failure
local ok = pcall(function() return M.json_decode("@#$%^") end)
check("decode: garbage does not error", ok)

-- ── content anchoring (schema v2) ───────────────────────────────────────────────

-- _norm: collapse internal whitespace and trim ends
eq("norm: collapse+trim", M.norm("  a   b  "), "a b")
eq("norm: tabs/newlines", M.norm("\t x \n"),   "x")
eq("norm: all blank",     M.norm("   \t "),    "")
eq("norm: nil",           M.norm(nil),         "")

-- _dice: bigram similarity, 0..1
eq("dice: identical",   M.dice("abc", "abc"), 1.0)
eq("dice: disjoint",    M.dice("abc", "xyz"), 0.0)
check("dice: near is high",
    M.dice("function bar(a, b)", "function bar(a, b, c)") >= 0.6,
    M.dice("function bar(a, b)", "function bar(a, b, c)"))
check("dice: unrelated is low",
    M.dice("return total", "completely different text") < 0.6)

-- a fake micro buffer: 0-indexed Line(), LinesNum()
local function fakebuf(lines)
    return {
        Line     = function(_, i) return lines[i + 1] end,
        LinesNum = function(_)     return #lines end,
    }
end
-- a getline closure + line count, for resolver tests
local function liner(lines)
    return function(i) return lines[i + 1] end, #lines
end

-- encode_list WITH a buffer captures text + neighbour context (v2), and the
-- decoded anchor relocates back to the same line in the unchanged buffer.
local srcA = { "import os", "def main():", "    return 0", "main()" }
local bufA = fakebuf(srcA)
local encA = M.json_decode(M.encode_list({ marks = { 2 }, names = { [2] = "exit" } }, bufA))
eq("anchor encode: version",  encA.v, 2)
eq("anchor encode: y",        encA.marks[1].y, 2)
eq("anchor encode: name",     encA.marks[1].name, "exit")
eq("anchor encode: text",     encA.marks[1].text, "    return 0")
eq("anchor encode: before",   encA.marks[1].before, "def main():")
eq("anchor encode: after",    encA.marks[1].after, "main()")
do
    local g, n = liner(srcA)
    eq("anchor resolve: unchanged", M.resolve_anchor(g, n, encA.marks[1]), 2)
end

-- first line has no `before`; last line has no `after`
local edge = M.json_decode(M.encode_list({ marks = { 0, 3 }, names = {} }, bufA))
eq("anchor encode: first has no before", edge.marks[1].before, nil)
eq("anchor encode: first text",          edge.marks[1].text, "import os")
eq("anchor encode: last has no after",   edge.marks[2].after, nil)
eq("anchor encode: last text",           edge.marks[2].text, "main()")

-- context longer than the cap (200) is truncated when stored
local longline = string.rep("x", 300)
local capbuf = fakebuf({ "a", longline, "    return 0" })
local capped = M.json_decode(M.encode_list({ marks = { 2 }, names = {} }, capbuf))
check("anchor encode: before capped at 200", #capped.marks[1].before == 200,
    capped.marks[1].before and #capped.marks[1].before)

-- resolver ladder ----------------------------------------------------------------

-- B. exact text shifted DOWN (lines inserted above the mark)
do
    local g, n = liner({ "new1", "new2", "import os", "def main():", "    return 0", "main()" })
    eq("resolve: shifted down (exact)", M.resolve_anchor(g, n, encA.marks[1]), 4)
end

-- B. duplicate lines disambiguated by neighbour context + proximity
do
    local lines = { "x", "a", "open()", "end", "b", "open2()", "end" }
    local g, n  = liner(lines)
    local a     = { y = 2, text = "end", before = "open()", after = "b" }
    eq("resolve: duplicate line picks matching context", M.resolve_anchor(g, n, a), 3)
end

-- C. reindentation: exact fails, normalized matches
do
    local g, n = liner({ "foo", "        return 0", "bar" })
    local a    = { y = 0, text = "    return 0" }
    eq("resolve: reindented (normalized)", M.resolve_anchor(g, n, a), 1)
end

-- D. line edited in place + moved → fuzzy relocation
do
    local g, n = liner({ "foo", "bar", "function bar(a, b, c)", "baz" })
    local a    = { y = 0, text = "function bar(a, b)" }
    eq("resolve: edited line (fuzzy)", M.resolve_anchor(g, n, a), 2)
end

-- D. no credible match anywhere → fall back to the stored line
do
    local g, n = liner({ "aaa", "bbb", "ccc" })
    local a    = { y = 1, text = "totally unrelated content here" }
    eq("resolve: no match falls back to stored y", M.resolve_anchor(g, n, a), 1)
end

-- E. stored line past EOF with no match → clamp into range
do
    local g, n = liner({ "a", "b", "c" })
    local a    = { y = 10, text = "nowhere to be found zzz" }
    eq("resolve: out-of-range clamps", M.resolve_anchor(g, n, a), 2)
end

-- blank-line anchor: unusable text → trust the stored number
do
    local g, n = liner({ "a", "   ", "c" })
    eq("resolve: blank text trusts y", M.resolve_anchor(g, n, { y = 1, text = "   " }), 1)
end

-- v1-style entry (no text): trust the stored number, clamped
do
    local g, n = liner({ "a", "b", "c", "d", "e" })
    eq("resolve: no-text trusts y", M.resolve_anchor(g, n, { y = 3 }), 3)
end

-- ── selection range (issue #5) ──────────────────────────────────────────────────
-- marks are 0-indexed line numbers, sorted ascending; sel_range returns a,b (a<=b)
-- or nil. "next"/"prev" select from the cursor to the nearest mark below/above;
-- "between" selects the two marks bracketing the cursor.
local function rng(marks, cy, mode)
    local a, b = M.sel_range(marks, cy, mode)
    if a == nil then return "nil" end
    return a .. "," .. b
end
local MKS = { 2, 5, 9 }
eq("sel_range next: between marks",     rng(MKS, 3, "next"),    "3,5")
eq("sel_range prev: between marks",     rng(MKS, 3, "prev"),    "2,3")
eq("sel_range between: brackets",       rng(MKS, 3, "between"), "2,5")
eq("sel_range next: on a mark",         rng(MKS, 5, "next"),    "5,9")
eq("sel_range prev: on a mark",         rng(MKS, 5, "prev"),    "2,5")
eq("sel_range between: on a mark = nil",rng(MKS, 5, "between"), "nil")
eq("sel_range next: above all marks",   rng(MKS, 0, "next"),    "0,2")
eq("sel_range prev: above all = nil",   rng(MKS, 0, "prev"),    "nil")
eq("sel_range between: above all = nil",rng(MKS, 0, "between"), "nil")
eq("sel_range next: below all = nil",   rng(MKS, 10, "next"),   "nil")
eq("sel_range prev: below all",         rng(MKS, 10, "prev"),   "9,10")
eq("sel_range between: below all = nil",rng(MKS, 10, "between"),"nil")
eq("sel_range between: strictly inside",rng({ 2, 9 }, 5, "between"), "2,9")

-- ── summary ─────────────────────────────────────────────────────────────────────
io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
