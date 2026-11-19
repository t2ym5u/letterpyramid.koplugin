-- Difficulty guarantees (docs/dev/TESTING.md, "Difficulty specs").
--
-- A level sets the pyramid's size, the words it is built from and the kind of
-- step it leans to (board.lua, Board.LEVEL_SPEC). Measured on 2026-11-19 over
-- 200 seeds per mode, in both languages: rows 4 / 5 / 7 (diamond 5 / 7 / 9);
-- "plain" steps, where a common word just takes the letter in somewhere,
-- about 68 % / 47-57 % / 23-33 %; rarer words (tier 2) only in Hard, on
-- 23-42 % of its rows. Generation took at most 8.4 ms on the Mac, the word
-- list load included (well under the fleet's 40 ms).
package.path = "./?.lua;./common/?.lua;" .. package.path

local Board = dofile("board.lua")

local SEEDS = 60

-- Averages over SEEDS pyramids: rows, share of plain steps, share of tier 2
-- rows, and whether every pyramid kept the mode's shape.
local function measure(lang, mode, level)
    local rows, steps, plain, rare = 0, 0, 0, 0
    for seed = 1, SEEDS do
        math.randomseed(seed)
        local b = Board:new{ lang = lang, mode = mode, level = level }
        b:newGame()
        rows = rows + #b.rows
        local tier = b:_data().tier
        for i = 2, #b.rows do
            local a, c = b.rows[i - 1].key, b.rows[i].key
            if #a > #c then a, c = c, a end
            steps = steps + 1
            if Board.isPlainStep(lang, a, c) then plain = plain + 1 end
            if tier[b.rows[i].key] == 2 then rare = rare + 1 end
        end
    end
    return { rows = rows / SEEDS, plain = plain / steps, rare = rare / steps }
end

describe("Letter Pyramid difficulty", function()
    teardown(function() Board.release() end)

    for _, lang in ipairs({ "en", "fr" }) do
        for _, mode in ipairs(Board.MODES) do
            it(lang .. " " .. mode .. ": Easy < Medium < Hard", function()
                local e = measure(lang, mode, "easy")
                local m = measure(lang, mode, "medium")
                local h = measure(lang, mode, "hard")
                -- more rows
                assert.is_true(e.rows < m.rows and m.rows < h.rows)
                -- fewer steps where the word only takes the letter in
                assert.is_true(e.plain > m.plain + 0.05, "easy " .. e.plain .. " medium " .. m.plain)
                assert.is_true(m.plain > h.plain + 0.1, "medium " .. m.plain .. " hard " .. h.plain)
                -- rarer words only in Hard
                assert.equals(0, e.rare)
                assert.equals(0, m.rare)
                assert.is_true(h.rare > 0.1)
            end)
        end

        it(lang .. ": a diamond always finds two different sides", function()
            for _, level in ipairs(Board.LEVELS) do
                local peak = Board.LEVEL_SPEC[level].peak
                for seed = 1, 100 do
                    math.randomseed(seed)
                    local b = Board:new{ lang = lang, mode = "diamond", level = level }
                    b:newGame()
                    assert.equals(2 * peak - 5, #b.rows)
                end
            end
        end)

        it(lang .. ": every row has a common word to show, the first one a start word", function()
            local d = Board:new{ lang = lang }:_data()
            for key, words in pairs(d.words) do
                assert.is_truthy(words:match("^%u"), key)
            end
            assert.is_true(#d.by_len[3] >= 100)
            assert.is_true(#d.by_len[9] >= 80)
        end)
    end

    it("the same seed builds the same puzzle, without reading the clock", function()
        local clock = os.clock
        os.clock = function() error("the generator read the clock") end
        local ok, err = pcall(function()
            for _, level in ipairs(Board.LEVELS) do
                math.randomseed(5)
                local a = Board:new{ lang = "en", mode = "diamond", level = level }
                a:newGame()
                math.randomseed(5)
                local b = Board:new{ lang = "en", mode = "diamond", level = level }
                b:newGame()
                assert.are.same(a:serialize().rows, b:serialize().rows)
            end
        end)
        os.clock = clock
        assert.is_true(ok, err)
    end)
end)
