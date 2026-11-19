-- Run from the plugin dir: busted
package.path = "./?.lua;./common/?.lua;" .. package.path

local Board = dofile("board.lua")

local function fresh(opts)
    local b = Board:new(opts)
    b:newGame()
    return b
end

-- Fills the active row by tapping the tiles that spell `word`.
local function spell(b, word)
    local tiles = b:tilesFor(b.active)
    local taken, result = {}, nil
    for k = 1, #word do
        local c = word:sub(k, k)
        for t, tile in ipairs(tiles) do
            if not taken[t] and tile.letter == c then
                taken[t] = true
                result = b:tapTile(t)
                break
            end
        end
    end
    return result
end

local function solveAll(b)
    while b.active do
        assert.equals("string", type(b:solution(b.active)))
        spell(b, b:solution(b.active))
    end
end

describe("pyramid shape", function()
    teardown(function() Board.release() end)

    for _, lang in ipairs({ "en", "fr" }) do
        for _, mode in ipairs(Board.MODES) do
            for _, level in ipairs(Board.LEVELS) do
                it(lang .. " " .. mode .. " " .. level .. ": one letter in or out per row", function()
                    local spec = Board.LEVEL_SPEC[level]
                    for seed = 1, 10 do
                        math.randomseed(seed)
                        local b = fresh{ lang = lang, mode = mode, level = level }
                        local rows = b.rows
                        local lens = {}
                        for i, r in ipairs(rows) do lens[i] = #r.key end
                        if mode == "pyramid" then
                            assert.equals(spec.base - 2, #rows)
                            assert.equals(3, lens[1])
                        elseif mode == "inverted" then
                            assert.equals(spec.base - 2, #rows)
                            assert.equals(spec.base, lens[1])
                        else
                            assert.equals(2 * spec.peak - 5, #rows)
                            assert.equals(3, lens[1])
                            assert.equals(3, lens[#rows])
                            assert.equals(spec.peak, math.max(table.unpack(lens)))
                        end
                        assert.is_true(rows[1].given)
                        local seen = {}
                        for i, r in ipairs(rows) do
                            assert.is_nil(seen[r.key], "a letter set comes back")
                            seen[r.key] = true
                            assert.equals(Board.sortedLetters(r.key), r.key)
                            if i > 1 then
                                local prev = rows[i - 1].key
                                local big, small = r.key, prev
                                if r.op == "-" then big, small = prev, r.key end
                                assert.equals(#small + 1, #big)
                                local i0 = big:find(r.letter, 1, true)
                                assert.equals(small, big:sub(1, i0 - 1) .. big:sub(i0 + 1))
                                assert.is_true(b:isAnswer(i, b:solution(i)))
                            end
                        end
                        assert.is_true(b:isAnswer(1, b.entries[1]))
                    end
                end)
            end
        end
    end
end)

describe("playing", function()
    teardown(function() Board.release() end)

    it("tiles start from the word above plus the new letter", function()
        math.randomseed(3)
        local b = fresh{ lang = "en", mode = "pyramid", level = "easy" }
        local tiles = b:tilesFor(2)
        assert.equals(#b.rows[2].key, #tiles)
        local s = {}
        for k = 1, #tiles - 1 do s[k] = tiles[k].letter end
        assert.equals(b.entries[1], table.concat(s))
        assert.is_true(tiles[#tiles].new)
        assert.equals(b.rows[2].letter, tiles[#tiles].letter)
    end)

    it("tiles leave out the removed letter in an upside-down pyramid", function()
        math.randomseed(3)
        local b = fresh{ lang = "en", mode = "inverted", level = "medium" }
        local tiles = b:tilesFor(2)
        local s = {}
        for k, t in ipairs(tiles) do s[k] = t.letter end
        assert.equals(b.rows[2].key, Board.sortedLetters(table.concat(s)))
    end)

    it("a row with no word above offers its letters in order", function()
        math.randomseed(4)
        local b = fresh{ lang = "en", mode = "pyramid", level = "medium" }
        assert.is_true(b:select(4))
        local s = {}
        for k, t in ipairs(b:tilesFor(4)) do s[k] = t.letter end
        assert.equals(b.rows[4].key, table.concat(s))
    end)

    it("a wrong word stays in the row; Clear and taps take letters back", function()
        math.randomseed(5)
        local b = fresh{ lang = "en", mode = "pyramid", level = "easy" }
        local tiles = b:tilesFor(2)
        local result
        for t = #tiles, 1, -1 do result = b:tapTile(t) end
        local word = b:currentWord()
        if not b:isAnswer(2, word) then
            assert.equals("wrong", result)
            assert.is_nil(b.entries[2])
            assert.equals(#tiles, #b.current)
            assert.is_true(b:untapLetter(1))
            assert.equals(#tiles - 1, #b.current)
            b:clearCurrent()
            assert.equals(0, #b.current)
        end
    end)

    it("tapping a used tile gives it back", function()
        math.randomseed(6)
        local b = fresh{ lang = "fr", mode = "pyramid", level = "easy" }
        assert.is_nil(b:tapTile(1))
        assert.equals(1, #b.current)
        assert.is_nil(b:tapTile(1))
        assert.equals(0, #b.current)
    end)

    it("any dictionary word with the letters fills a row, not only the shown one", function()
        local b = Board:new{ lang = "en" }
        b:_setRows({ "AET", "AEST" })
        assert.equals("EAT", b.entries[1])
        for _, w in ipairs({ "EAST", "SEAT", "EATS", "TEAS", "SATE", "ETAS" }) do
            assert.is_true(b:isAnswer(2, w), w)
        end
        assert.is_false(b:isAnswer(2, "TSAE"))
        assert.is_false(b:isAnswer(2, "SEATS"))
        assert.equals("win", spell(b, "ETAS"))
    end)

    it("filling every row wins and counts a win", function()
        for _, mode in ipairs(Board.MODES) do
            math.randomseed(11)
            local b = fresh{ lang = "fr", mode = mode, level = "hard" }
            solveAll(b)
            assert.equals("win", b.result)
            assert.equals(1, b.wins)
            local done, total = b:progress()
            assert.equals(total, done)
        end
    end)

    it("rows can be filled in any order", function()
        math.randomseed(12)
        local b = fresh{ lang = "en", mode = "diamond", level = "medium" }
        for i = #b.rows, 2, -1 do
            assert.is_true(b:select(i))
            spell(b, b:solution(i))
        end
        assert.equals("win", b.result)
        assert.is_false(b:select(1))
    end)

    it("hint: names the active row, then fills it", function()
        math.randomseed(13)
        local b = fresh{ lang = "en", mode = "pyramid", level = "hard" }
        b:select(3)
        local step = b:findHint()
        assert.equals(3, step.r)
        assert.equals(b:solution(3), step.word)
        assert.is_true(b:applyHint(step))
        b:noteHintUsed()
        assert.equals(step.word, b.entries[3])
        assert.is_true(b.hinted[3])
        assert.equals(1, b:getHintsUsed())
        assert.is_false(b:applyHint(step))
    end)

    it("reveal ends the game without a win", function()
        math.randomseed(14)
        local b = fresh{ lang = "en" }
        b:reveal()
        assert.equals("revealed", b.result)
        assert.is_nil(b.active)
        assert.equals(0, b.wins)
        assert.is_nil(b:tapTile(1))
        assert.is_nil(b:findHint())
    end)
end)

describe("determinism", function()
    teardown(function() Board.release() end)

    local function keys(b)
        local out = {}
        for i, r in ipairs(b.rows) do out[i] = r.key end
        return table.concat(out, " ")
    end

    it("the same seed builds the same pyramid", function()
        for _, mode in ipairs(Board.MODES) do
            math.randomseed(99)
            local a = keys(fresh{ lang = "fr", mode = mode, level = "hard" })
            math.randomseed(99)
            assert.equals(a, keys(fresh{ lang = "fr", mode = mode, level = "hard" }))
        end
    end)

    it("the daily pyramid depends on the day and the language only", function()
        local a = Board:new{ lang = "en", mode = "diamond", level = "hard" }
        a:newDailyGame()
        local b = Board:new{ lang = "en" }
        b:newDailyGame()
        assert.equals(keys(a), keys(b))
        assert.equals("pyramid", a.mode)
        assert.equals("medium", a.level)
        assert.is_not_nil(a.daily)
        local c = Board:new{ lang = "fr" }
        c:newDailyGame()
        assert.are_not.equal(keys(a), keys(c))
    end)
end)

describe("saves", function()
    teardown(function() Board.release() end)

    it("round-trips a game in progress", function()
        math.randomseed(21)
        local b = fresh{ lang = "fr", mode = "diamond", level = "medium" }
        spell(b, b:solution(2))
        b:select(5)
        b:tapTile(1)
        b:applyHint(b:findHint())
        b:noteHintUsed()
        local copy = Board:new{}
        assert.is_true(copy:load(b:serialize()))
        assert.are.same(b:serialize(), copy:serialize())
        assert.equals("fr", copy.lang)
        assert.equals(b.entries[2], copy.entries[2])
        assert.equals(1, copy:getHintsUsed())
    end)

    it("round-trips a finished game", function()
        math.randomseed(22)
        local b = fresh{ lang = "en", mode = "inverted", level = "easy" }
        solveAll(b)
        local copy = Board:new{}
        assert.is_true(copy:load(b:serialize()))
        assert.equals("win", copy.result)
        assert.is_nil(copy.active)
        assert.equals(1, copy.wins)
    end)

    it("refuses what it cannot read", function()
        local b = Board:new{}
        assert.is_false(b:load(nil))
        assert.is_false(b:load({}))
        assert.is_false(b:load({ v = 99, rows = { { "AET" }, { "AEST" } } }))
        assert.is_false(b:load({ v = 1, lang = "en", rows = { { "AET", "", "" }, { "QQQQ", "+", "Q" } } }))
    end)

    it("drops out-of-range tiles from a damaged save", function()
        math.randomseed(23)
        local b = fresh{ lang = "en" }
        local s = b:serialize()
        s.current = { 1, 99, "x" }
        local copy = Board:new{}
        assert.is_true(copy:load(s))
        assert.are.same({ 1 }, copy.current)
    end)
end)

describe("speed and memory", function()
    it("builds 100 pyramids of every kind well under the Kobo budget", function()
        Board.release()
        local t0 = os.clock()
        for _, lang in ipairs({ "en", "fr" }) do
            for _, mode in ipairs(Board.MODES) do
                for _, level in ipairs(Board.LEVELS) do
                    for seed = 1, 100 do
                        math.randomseed(seed)
                        fresh{ lang = lang, mode = mode, level = level }
                    end
                end
            end
        end
        -- 1800 pyramids plus both word lists: about 0.2 s on a 2025 Mac.
        assert.is_true(os.clock() - t0 < 5)
    end)

    it("loads one language at a time and releases it", function()
        Board.release()
        fresh{ lang = "fr" }
        assert.are.same({ "fr" }, Board.loadedLanguages())
        Board.release()
        assert.are.same({}, Board.loadedLanguages())
    end)
end)
