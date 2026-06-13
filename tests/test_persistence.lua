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
local dec = M.json_decode(M.encode_list(lst))
eq("encode_list: schema version", dec.v, 1)
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
eq("encode_list: empty version", empty.v, 1)
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

-- ── summary ─────────────────────────────────────────────────────────────────────
io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
