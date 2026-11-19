-- Family-friendly words: the game is also played at a family table, so the
-- words it shows by itself (the first row, a hint, a revealed answer) must
-- never be one of blocklist.lua's vulgar, sexual, scatological, slur or
-- drug-related words. tools/build_words.py keeps them out of the common
-- words; they stay accepted when a player types them.
package.path = "./?.lua;./common/?.lua;" .. package.path

local Board = dofile("board.lua")
local Blocklist = dofile("blocklist.lua")

describe("family-friendly pyramids", function()
    teardown(function() Board.release() end)

    for _, lang in ipairs({ "en", "fr" }) do
        it(lang .. ": no blocklisted word among the words a pyramid can show", function()
            local d = Board:new{ lang = lang }:_data()
            local rare = 0
            for _key, words in pairs(d.words) do
                local common, others = words:match("^([^|]*)|(.*)$")
                for w in common:gmatch("%u+") do
                    assert.is_false(Blocklist.isBlocked(w, lang), w)
                end
                for w in others:gmatch("%u+") do
                    if Blocklist.isBlocked(w, lang) then rare = rare + 1 end
                end
            end
            -- The filter is exercised: blocked words are still accepted.
            assert.is_true(rare > 0)
        end)
    end
end)
