local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local DailySeed = require("daily_seed")

-- ---------------------------------------------------------------------------
-- Word data
--
-- A row of the pyramid is a set of letters, its "key" (the letters sorted):
-- every dictionary word made of exactly those letters fills it. Two rows next
-- to each other differ by one letter, added or removed. words_<lang>.lua
-- holds the keys the generator may use (format: tools/build_words.py):
--
--   tier[key]  1 or 2. From a tier 1 key, removing a letter at a time reaches
--              a start key through tier 1 keys only, all common words (Easy,
--              Medium); a tier 2 key needs rarer ones on the way (Hard).
--   words[key] "TEA,EAT,ATE|ETA": common words, most frequent first (what a
--              hint or a reveal shows), then the rare ones, only accepted.
--   by_len[n]  the keys of n letters, in file order (the draws must not
--              depend on pairs() order: the Daily Challenge is the same on
--              every device).
--
-- Loaded the first time a language is played, for that language only;
-- Board.release() (the screen closing) drops it.
-- ---------------------------------------------------------------------------

local DATA = {}

local function langData(lang)
    lang = lang == "fr" and "fr" or "en"
    local d = DATA[lang]
    if not d then
        local raw = assert(loadfile(_dir .. "words_" .. lang .. ".lua"))()
        d = { tier = {}, words = {}, by_len = {} }
        for tier, key, words in raw:gmatch("(%d)(%u+):([^\n]*)") do
            d.tier[key] = tonumber(tier)
            d.words[key] = words
            local n = #key
            d.by_len[n] = d.by_len[n] or {}
            local list = d.by_len[n]
            list[#list + 1] = key
        end
        DATA[lang] = d
    end
    return d
end

local function sortedLetters(word)
    local t = {}
    for i = 1, #word do t[i] = word:sub(i, i) end
    table.sort(t)
    return table.concat(t)
end

local function split(s)
    local out = {}
    for w in s:gmatch("%u+") do out[#out + 1] = w end
    return out
end

-- The common words of a key, most frequent first.
local function commonWords(d, key)
    return split((d.words[key] or ""):match("^([^|]*)") or "")
end

-- The letter in big that small lacks (big = small + one letter).
local function extraLetter(small, big)
    for i = 1, #big do
        if small:sub(i, i) ~= big:sub(i, i) then return big:sub(i, i) end
    end
end

-- True when long is short with one letter inserted somewhere, the others in
-- the same order (CAT -> CART).
local function isInsertion(short, long)
    if #long ~= #short + 1 then return false end
    for i = 1, #long do
        if long:sub(1, i - 1) .. long:sub(i + 1) == short then return true end
    end
    return false
end

-- A step between two keys is "plain" when a common word of one is a common
-- word of the other with a letter slipped in (CAT -> CART, CAT -> CATS): the
-- player keeps the word and only finds where the letter goes. Otherwise the
-- letters have to be shuffled into a new word.
local function isPlainStep(d, small, big)
    local smalls, bigs = commonWords(d, small), commonWords(d, big)
    for _i, s in ipairs(smalls) do
        for _j, b in ipairs(bigs) do
            if isInsertion(s, b) then return true end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Board
-- ---------------------------------------------------------------------------

local Board = {}
Board.__index = Board

Board.MODES  = { "pyramid", "inverted", "diamond" }
Board.LEVELS = { "easy", "medium", "hard" }

-- Per level: the base of a pyramid (its longest row), the peak of a diamond,
-- the word tier, and whether the steps lean towards plain insertions (Easy)
-- or towards real reshuffles (Hard). Hard also uses rarer words.
Board.LEVEL_SPEC = {
    easy   = { base = 6, peak = 5, tier = 1, steps = "plain" },
    medium = { base = 7, peak = 6, tier = 1 },
    hard   = { base = 9, peak = 7, tier = 2, steps = "shuffle" },
}

Board.DEFAULT_MODE  = "pyramid"
Board.DEFAULT_LEVEL = "medium"

local MIN_LEN = 3
-- Peaks a diamond tries before giving up on a draw (its two sides must use
-- different letter sets at every length; the first peak almost always works).
local DIAMOND_TRIES = 40

-- opts: lang, mode, level, wins
function Board:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        lang    = opts.lang  or "en",
        mode    = opts.mode  or Board.DEFAULT_MODE,
        level   = opts.level or Board.DEFAULT_LEVEL,
        wins    = opts.wins  or 0,
        rows    = {},
        entries = {},
        hinted  = {},
        current = {},
        active  = nil,
        result  = nil,     -- nil while playing, "win" or "revealed"
        hints_used = 0,
        daily   = nil,     -- DailySeed.today() of a daily puzzle
    }, self)
    return obj
end

function Board:_data()
    return langData(self.lang)
end

-- Walk down from key to a 3-letter key, one letter removed per step, through
-- keys of the level's tier. avoid[n]: a key of length n the walk must not use
-- (the other side of a diamond). Returns the keys, longest first, or nil.
function Board:_walkDown(key, spec, avoid)
    local d = self:_data()
    local chain = { key }
    while #key > MIN_LEN do
        local seen, all, liked = {}, {}, {}
        for i = 1, #key do
            local child = key:sub(1, i - 1) .. key:sub(i + 1)
            local t = d.tier[child]
            if not seen[child] and t and t <= spec.tier
                    and not (avoid and avoid[#child] == child) then
                seen[child] = true
                all[#all + 1] = child
                if spec.steps then
                    local plain = isPlainStep(d, child, key)
                    if (spec.steps == "plain") == plain then liked[#liked + 1] = child end
                end
            end
        end
        local pool = #liked > 0 and liked or all
        if #pool == 0 then return nil end
        key = pool[math.random(#pool)]
        chain[#chain + 1] = key
    end
    return chain
end

-- A random key of n letters of the level's tier.
function Board:_drawKey(n, spec)
    local d = self:_data()
    local pool = {}
    for _i, k in ipairs(d.by_len[n] or {}) do
        if d.tier[k] <= spec.tier then pool[#pool + 1] = k end
    end
    return pool[math.random(#pool)]
end

-- The rows, top to bottom, as keys: the shape of the mode.
function Board:_drawKeys()
    local spec = Board.LEVEL_SPEC[self.level] or Board.LEVEL_SPEC.medium
    if self.mode == "diamond" then
        for _try = 1, DIAMOND_TRIES do
            local left = self:_walkDown(self:_drawKey(spec.peak, spec), spec)
            local avoid = {}
            for _i, k in ipairs(left) do avoid[#k] = k end
            avoid[spec.peak] = nil
            local right = self:_walkDown(left[1], spec, avoid)
            if right then
                local keys = {}
                for i = #left, 1, -1 do keys[#keys + 1] = left[i] end
                for i = 2, #right do keys[#keys + 1] = right[i] end
                return keys
            end
        end
        -- Never seen with the shipped word lists (see the specs): a plain
        -- pyramid rather than no puzzle at all.
    end
    local chain = self:_walkDown(self:_drawKey(spec.base, spec), spec)
    if self.mode == "inverted" then return chain end
    local keys = {}
    for i = #chain, 1, -1 do keys[#keys + 1] = chain[i] end
    return keys
end

-- rows[i] = { key, op = "+" | "-" | nil, letter, given }: the first row is
-- given (a common word), every other row adds (+) or removes (-) `letter`
-- from the row above it.
function Board:_setRows(keys)
    local d = self:_data()
    self.rows = {}
    for i, key in ipairs(keys) do
        local row = { key = key }
        local prev = keys[i - 1]
        if not prev then
            row.given = true
        elseif #key > #prev then
            row.op, row.letter = "+", extraLetter(prev, key)
        else
            row.op, row.letter = "-", extraLetter(key, prev)
        end
        self.rows[i] = row
    end
    self.entries = { commonWords(d, keys[1])[1] }
    self.hinted  = {}
    self.current = {}
    self.result  = nil
    self.hints_used = 0
    self.active  = 2
end

function Board:newGame()
    self.daily = nil
    self:_setRows(self:_drawKeys())
end

-- Today's pyramid: the same for everyone in a language, whatever the mode
-- and level chosen (always a Medium pyramid).
function Board:newDailyGame(day)
    self.mode, self.level = "pyramid", "medium"
    local keys
    DailySeed.run("letterpyramid_" .. self.lang, function() keys = self:_drawKeys() end)
    self:_setRows(keys)
    self.daily = day or DailySeed.today()
end

-- ---------------------------------------------------------------------------
-- Play
-- ---------------------------------------------------------------------------

function Board:isOver()
    return self.result ~= nil
end

function Board:rowCount()
    return #self.rows
end

-- Rows to find (all but the given one) and how many are filled.
function Board:progress()
    local done = 0
    for i = 2, #self.rows do
        if self.entries[i] then done = done + 1 end
    end
    return done, #self.rows - 1
end

-- Any dictionary word made of the row's letters fills it, not only the
-- common ones.
function Board:isAnswer(i, word)
    local row = self.rows[i]
    if not row or #word ~= #row.key or sortedLetters(word) ~= row.key then return false end
    local list = "," .. (self:_data().words[row.key] or ""):gsub("|", ",") .. ","
    return list:find("," .. word .. ",", 1, true) ~= nil
end

-- The tiles offered for row i: the word of the row above, letter for letter,
-- plus the added letter at the end (or minus the removed one), so the player
-- starts from that word. With the row above still empty, the row's letters
-- in alphabetical order. Returns a list of { letter, new }.
function Board:tilesFor(i)
    local row = self.rows[i]
    if not row then return {} end
    local above = self.entries[i - 1]
    local tiles = {}
    if above and row.op then
        local removed = false
        for c in above:gmatch(".") do
            if row.op == "-" and not removed and c == row.letter then
                removed = true
            else
                tiles[#tiles + 1] = { letter = c }
            end
        end
        if row.op == "+" then tiles[#tiles + 1] = { letter = row.letter, new = true } end
    else
        for c in row.key:gmatch(".") do tiles[#tiles + 1] = { letter = c } end
    end
    return tiles
end

function Board:select(i)
    if self.result or not self.rows[i] or self.rows[i].given then return false end
    if self.active ~= i then
        self.active  = i
        self.current = {}
    end
    return true
end

-- ScreenBase:onHint selects the hinted row through this.
function Board:setSelection(r)
    self:select(r)
end

-- The tile indexes of the active row's tiles in use.
function Board:usedTiles()
    local used = {}
    for _i, t in ipairs(self.current) do used[t] = true end
    return used
end

function Board:currentWord()
    local tiles = self:tilesFor(self.active)
    local out = {}
    for _i, t in ipairs(self.current) do out[#out + 1] = tiles[t].letter end
    return table.concat(out)
end

-- Tap on tile t of the active row: adds its letter, or takes it back if it
-- is already in the word. Returns nil, or once the row is full the result of
-- the check: "found", "win" or "wrong".
function Board:tapTile(t)
    if self.result or not self.active then return nil end
    local tiles = self:tilesFor(self.active)
    if not tiles[t] then return nil end
    for j, u in ipairs(self.current) do
        if u == t then
            table.remove(self.current, j)
            return nil
        end
    end
    self.current[#self.current + 1] = t
    if #self.current < #tiles then return nil end
    return self:_check()
end

-- Tap on letter j of the word being built: gives it back to the tiles.
function Board:untapLetter(j)
    if self.result or not self.current[j] then return false end
    table.remove(self.current, j)
    return true
end

function Board:clearCurrent()
    self.current = {}
end

function Board:_nextEmpty(from)
    local n = #self.rows
    for k = 0, n - 1 do
        local i = (from - 1 + k) % n + 1
        if not self.entries[i] then return i end
    end
end

function Board:_fill(i, word)
    self.entries[i] = word
    self.current = {}
    local nxt = self:_nextEmpty(i)
    if not nxt then
        self.result = "win"
        self.active = nil
        self.wins = self.wins + 1
        return "win"
    end
    self.active = nxt
    return "found"
end

function Board:_check()
    local word = self:currentWord()
    if not self:isAnswer(self.active, word) then return "wrong" end
    self.hinted[self.active] = nil
    return self:_fill(self.active, word)
end

-- The answer shown for row i: the most frequent common word.
function Board:solution(i)
    local row = self.rows[i]
    return row and commonWords(self:_data(), row.key)[1]
end

-- Ends the game and shows the answers of the rows left empty.
function Board:reveal()
    if self.result then return end
    self.result = "revealed"
    self.active = nil
    self.current = {}
end

-- ---------------------------------------------------------------------------
-- Hints -- the ScreenBase:onHint protocol (findHint / applyHint /
-- noteHintUsed / getHintsUsed). A hint names a row (step.r): the first tap
-- gives the answer's first letter, the second fills the row.
-- ---------------------------------------------------------------------------

function Board:findHint()
    if self.result then return nil, "complete" end
    local i = (self.active and not self.entries[self.active]) and self.active
        or self:_nextEmpty(self.active or 2)
    if not i then return nil, "complete" end
    return { r = i, c = 1, kind = "fill", word = self:solution(i) }
end

function Board:applyHint(step)
    if self.result or not step or not self.rows[step.r] or self.entries[step.r] then return false end
    self.hinted[step.r] = true
    self:_fill(step.r, step.word)
    return true
end

function Board:noteHintUsed()
    self.hints_used = self.hints_used + 1
end

function Board:getHintsUsed()
    return self.hints_used
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

local SAVE_VERSION = 1

function Board:serialize()
    local rows = {}
    for i, r in ipairs(self.rows) do
        rows[i] = { r.key, r.op or "", r.letter or "" }
    end
    local entries, hinted = {}, {}
    for i = 1, #self.rows do
        entries[i] = self.entries[i] or ""
        hinted[i]  = self.hinted[i] and true or false
    end
    return {
        v       = SAVE_VERSION,
        lang    = self.lang,
        mode    = self.mode,
        level   = self.level,
        rows    = rows,
        entries = entries,
        hinted  = hinted,
        active  = self.active,
        current = self.current,
        result  = self.result,
        wins    = self.wins,
        hints_used = self.hints_used,
        daily   = self.daily,
    }
end

-- Restores a saved game without drawing a new one. Anything unexpected (an
-- unknown format, a key the word list no longer has) is refused: the screen
-- then starts a new game.
function Board:load(state)
    if type(state) ~= "table" or state.v ~= SAVE_VERSION or type(state.rows) ~= "table"
            or #state.rows < 2 then
        return false
    end
    local lang = state.lang == "fr" and "fr" or "en"
    local d = langData(lang)
    local rows = {}
    for i, r in ipairs(state.rows) do
        if type(r) ~= "table" or not d.words[r[1]] then return false end
        rows[i] = { key = r[1], op = r[2] ~= "" and r[2] or nil,
                    letter = r[3] ~= "" and r[3] or nil, given = i == 1 }
    end
    self.lang, self.rows = lang, rows
    self.mode  = state.mode  or Board.DEFAULT_MODE
    self.level = state.level or Board.DEFAULT_LEVEL
    self.entries, self.hinted = {}, {}
    for i = 1, #rows do
        local e = (state.entries or {})[i]
        if type(e) == "string" and e ~= "" then self.entries[i] = e end
        if (state.hinted or {})[i] then self.hinted[i] = true end
    end
    if not self.entries[1] then self.entries[1] = self:solution(1) end
    self.result  = (state.result == "win" or state.result == "revealed") and state.result or nil
    self.active  = not self.result and tonumber(state.active) or nil
    if self.active and (not rows[self.active] or self.active == 1) then
        self.active = self:_nextEmpty(2)
    end
    self.current = {}
    local ntiles = self.active and #self:tilesFor(self.active) or 0
    for _i, t in ipairs(state.current or {}) do
        if type(t) == "number" and t >= 1 and t <= ntiles then self.current[#self.current + 1] = t end
    end
    self.wins       = tonumber(state.wins) or 0
    self.hints_used = tonumber(state.hints_used) or 0
    self.daily      = state.daily
    return true
end

-- Drops every loaded word list (called when the game screen closes).
function Board.release()
    DATA = {}
end

-- The languages whose word data is loaded now (for the specs).
function Board.loadedLanguages()
    local out = {}
    for lang in pairs(DATA) do out[#out + 1] = lang end
    table.sort(out)
    return out
end

Board.sortedLetters = sortedLetters
Board.isPlainStep = function(lang, small, big) return isPlainStep(langData(lang), small, big) end

return Board
