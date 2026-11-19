local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ConfirmBox      = require("ui/widget/confirmbox")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase  = require("screen_base")
local MenuHelper  = require("menu_helper")
local Board       = lrequire("board")
local BoardWidget = lrequire("board_widget")

local GAME_RULES_EN = _([[
Letter Pyramid — Rules

Each row is a word one letter longer (or shorter) than the row above it. The first row is given.

• Pyramid: from a short word to a long one, one letter added per row.
• Upside down: from a long word to a short one, one letter taken away per row.
• Diamond: up to a long word, then back down to a short one.

The letter added (+E) or taken away (−E) is shown to the left of each row. The letters may be rearranged: CAT + R gives CART, and ACT + R gives CART too.

Tap the tiles under the pyramid to spell the row's word; tap a letter of the row to give it back. The word is checked as soon as the row is full. Any real word made of those letters is accepted.

You can fill the rows in any order: tap a row to pick it. Its tiles start from the word above it when that one is found.

Hint: the first tap gives the first letter of a word, the second fills the row.

Difficulty: Easy has short pyramids of everyday words, where the new word often just slips the letter in; Hard goes up to 9 letters, with rarer words and more rearranging.
]])

local GAME_RULES_FR = [[
Pyramide de lettres — Règles

Chaque ligne est un mot d'une lettre de plus (ou de moins) que la ligne du dessus. La première ligne est donnée.

• Pyramide : d'un mot court à un mot long, une lettre ajoutée par ligne.
• Pyramide inversée : d'un mot long à un mot court, une lettre retirée par ligne.
• Losange : on monte jusqu'à un mot long, puis on redescend vers un mot court.

La lettre ajoutée (+E) ou retirée (−E) est indiquée à gauche de chaque ligne. On peut changer l'ordre des lettres : RAT + E donne TARE, et ART + E aussi.

Touchez les lettres sous la pyramide pour écrire le mot de la ligne ; touchez une lettre de la ligne pour la rendre. Le mot est vérifié dès que la ligne est pleine. Tout mot du dictionnaire formé de ces lettres est accepté. Les accents sont ignorés.

Les lignes se remplissent dans l'ordre que vous voulez : touchez une ligne pour la choisir. Ses lettres partent du mot du dessus quand celui-ci est trouvé.

Astuce : la première touche donne la première lettre d'un mot, la seconde remplit la ligne.

Difficulté : Facile propose de petites pyramides de mots courants, où il suffit souvent de glisser la lettre dans le mot ; Difficile monte jusqu'à 9 lettres, avec des mots plus rares et plus de lettres à déplacer.
]]

local MODE_LABELS  = { pyramid = _("Pyramid"), inverted = _("Upside down"), diamond = _("Diamond") }
local LEVEL_LABELS = { easy = _("Easy"), medium = _("Medium"), hard = _("Hard") }

-- ---------------------------------------------------------------------------
-- LetterPyramidScreen
-- ---------------------------------------------------------------------------

local LetterPyramidScreen = ScreenBase:extend{}

function LetterPyramidScreen:init()
    local state = self.plugin:loadState()
    self.board = Board:new{ lang = self:_lang() }
    if not self.board:load(state) then
        self:_applySettings()
        self.board:newGame()
    end
    ScreenBase.init(self)
end

function LetterPyramidScreen:_lang()
    return self.plugin:getLang({ "fr", "en" })
end

function LetterPyramidScreen:_applySettings()
    self.board.lang  = self:_lang()
    self.board.mode  = self.plugin:getSetting("mode", Board.DEFAULT_MODE)
    self.board.level = self.plugin:getSetting("level", Board.DEFAULT_LEVEL)
end

function LetterPyramidScreen:serializeState()
    return self.board:serialize()
end

function LetterPyramidScreen:isRoundOver()
    return self.board:isOver()
end

function LetterPyramidScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Letter Pyramid"), function()
        return {
            { text = _("New game"),        callback = function() self:onNewGame() end },
            { text = _("Daily Challenge"), callback = function() self:onDailyGame() end },
            { text = T(_("Difficulty: %1"), LEVEL_LABELS[self.plugin:getSetting("level", Board.DEFAULT_LEVEL)]),
              callback = function() self:openLevelMenu() end },
            { text = T(_("Mode: %1"), MODE_LABELS[self.plugin:getSetting("mode", Board.DEFAULT_MODE)]),
              callback = function() self:openModeMenu() end },
            { text = T(_("Language: %1"), self:_lang():upper()),
              callback = function() self:openLangMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(self:_actionRows(is_landscape)),
    }

    local frame_pad = Size.padding.default
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = BoardWidget:new{
        board       = self.board,
        max_width   = math.max(budget_w - 2 * frame_pad, 120),
        max_height  = math.max(budget_h - 2 * frame_pad, 160),
        onRowTap    = function(i) self:onRowTap(i) end,
        onTileTap   = function(t) self:onTileTap(t) end,
        onLetterTap = function(j) self:onLetterTap(j) end,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- The narrow landscape side panel gets two rows.
function LetterPyramidScreen:_actionRows(is_landscape)
    local clear  = { text = _("Clear"),          callback = function() self:onClear() end }
    local hint   = { text = _("Hint"),           callback = function() self:onHint() end }
    local reveal = { text = _("Reveal answers"), callback = function() self:onReveal() end }
    if is_landscape then
        return { { clear, hint }, { reveal } }
    end
    return { clear, hint, reveal }
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function LetterPyramidScreen:_save()
    self.plugin:saveState(self.board:serialize())
end

-- Typing only repaints the board; the status line is only touched when it
-- still shows a message, so a tap costs one small refresh.
function LetterPyramidScreen:_clearMessage()
    if self.showing_msg then self:updateStatus() end
end

function LetterPyramidScreen:onRowTap(i)
    if not self.board:select(i) then return end
    self.hint_cell = nil
    self.board_widget:refresh(self)
    self:_clearMessage()
    self:_save()
end

function LetterPyramidScreen:onLetterTap(j)
    if not self.board:untapLetter(j) then return end
    self.board_widget:refresh(self)
    self:_clearMessage()
end

function LetterPyramidScreen:onTileTap(t)
    local row = self.board.active
    local result = self.board:tapTile(t)
    if not result then
        self.board_widget:refresh(self)
        self:_clearMessage()
        return
    end
    self.hint_cell = nil
    if result == "wrong" then
        self.board_widget:refresh(self)
        self:updateStatus(T(_("%1 is not in the word list."), self.board:currentWord()))
        return
    end
    self:_save()
    self.board_widget:refresh(self)
    self:updateStatus(result == "found" and T(_("Word found: %1"), self.board.entries[row]) or nil)
    self:refreshActionBar()
end

function LetterPyramidScreen:onClear()
    self.board:clearCurrent()
    self.board_widget:refresh(self)
    self:_clearMessage()
end

function LetterPyramidScreen:onReveal()
    if self.board:isOver() then return end
    UIManager:show(ConfirmBox:new{
        text = _("Show every answer? This ends the puzzle."),
        ok_text = _("Reveal"),
        ok_callback = function()
            self.board:reveal()
            self.hint_cell = nil
            self:_save()
            self.board_widget:refresh(self)
            self:updateStatus()
            self:refreshActionBar()
        end,
    })
end

-- Hints name a row, not a cell (see ScreenBase:onHint for the two taps).
function LetterPyramidScreen:describeHintStep(step, level)
    local word = step.word or ""
    if level == 1 then
        return T(_("Row %1 can start with %2. Tap Hint again to fill it in."), step.r, word:sub(1, 1))
    end
    return T(_("Row %1: %2."), step.r, word)
end

function LetterPyramidScreen:_restart(daily)
    if daily then
        self.board.lang = self:_lang()
        self.board:newDailyGame()
    else
        self:_applySettings()
        self.board:newGame()
    end
    self.hint_cell = nil
    self:_save()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function LetterPyramidScreen:onNewGame()
    self:_restart(false)
end

-- Today's pyramid for the current language. One saved game at a time.
function LetterPyramidScreen:onDailyGame()
    self:_restart(true)
end

function LetterPyramidScreen:_openPicker(title, setting, default, order, labels)
    local items = {}
    for _i, id in ipairs(order) do items[#items + 1] = { id = id, text = labels[id] } end
    MenuHelper.openPickerMenu{
        title      = title,
        items      = items,
        current_id = self.plugin:getSetting(setting, default),
        parent     = self,
        on_select  = function(id)
            self.plugin:saveSetting(setting, id)
            self:onNewGame()
        end,
    }
end

function LetterPyramidScreen:openLevelMenu()
    self:_openPicker(_("Difficulty"), "level", Board.DEFAULT_LEVEL, Board.LEVELS, LEVEL_LABELS)
end

function LetterPyramidScreen:openModeMenu()
    self:_openPicker(_("Mode"), "mode", Board.DEFAULT_MODE, Board.MODES, MODE_LABELS)
end

function LetterPyramidScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title      = _("Language"),
        items      = { { id = "en", text = _("English") }, { id = "fr", text = "Français" } },
        current_id = self:_lang(),
        parent     = self,
        on_select  = function(lang)
            self.plugin:setLang(lang)
            self:onNewGame()
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------

function LetterPyramidScreen:updateStatus(msg)
    self.showing_msg = msg ~= nil
    local b = self.board
    local status = msg
    if not status then
        local done, total = b:progress()
        if b.result == "win" then
            status = b.hints_used > 0
                and T(_("Pyramid complete! Hints used: %1"), b.hints_used)
                or  T(_("Pyramid complete! Wins: %1"), b.wins)
        elseif b.result == "revealed" then
            status = T(_("Found %1 of %2."), done, total)
        else
            status = self:joinStatus(
                b.daily and _("Daily Challenge") or MODE_LABELS[b.mode],
                LEVEL_LABELS[b.level],
                T(_("Words: %1/%2"), done, total),
                b.hints_used > 0 and T(_("Hints used: %1"), b.hints_used) or nil)
        end
    end
    ScreenBase.updateStatus(self, status)
end

-- The word lists are only needed while a game is open.
function LetterPyramidScreen:onCloseWidget()
    Board.release()
end

return LetterPyramidScreen
