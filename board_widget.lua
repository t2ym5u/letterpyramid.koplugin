local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local C_BG     = Blitbuffer.COLOR_WHITE
local C_GIVEN  = Blitbuffer.COLOR_GRAY_D
local C_FILLED = Blitbuffer.COLOR_GRAY_E
local C_TILE   = Blitbuffer.COLOR_GRAY_E
local C_USED   = Blitbuffer.COLOR_GRAY_B
local C_BORDER = Blitbuffer.COLOR_BLACK
local C_TEXT   = Blitbuffer.COLOR_BLACK
local C_DIM    = Blitbuffer.COLOR_GRAY_9

local Screen = Device.screen

-- Largest face whose ink for `sample` fits max_w x max_h. Measured unbounded
-- (a max_width limit cuts the text, so the width test could never fail), ink
-- height is y_top + y_bottom, and Font:getFace scales its size by the DPI, so
-- the pixel bound is converted back first.
local function fitFace(name, sample, max_w, max_h)
    local lo = 6
    local hi = math.max(lo, math.floor(max_h * 1000 / Screen:scaleBySize(1000)) * 2)
    local best = lo
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), Font:getFace(name, mid), sample, true, false)
        if m.x <= max_w and m.y_top + m.y_bottom <= max_h then
            best, lo = mid, mid + 1
        else
            hi = mid - 1
        end
    end
    return Font:getFace(name, best)
end

-- Centre `text` on (cx, cy): the baseline sits half the ink height below cy.
local function drawCentered(bb, face, text, cx, cy, color)
    local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text, true, false)
    RenderText:renderUtf8Text(bb, cx - math.floor(m.x / 2),
        cy + math.floor((m.y_top - m.y_bottom) / 2), face, text, true, false, color)
end

local function drawBox(bb, x, y, size, bg, border, thickness)
    bb:paintRect(x, y, size, size, border)
    bb:paintRect(x + thickness, y + thickness, size - 2 * thickness, size - 2 * thickness, bg)
end

-- ---------------------------------------------------------------------------
-- LetterPyramidBoardWidget
-- ---------------------------------------------------------------------------

local BoardWidget = InputContainer:extend{
    board       = nil,
    max_width   = 300,
    max_height  = 300,
    onRowTap    = nil,   -- function(i): a row was tapped
    onTileTap   = nil,   -- function(t): tile t of the active row
    onLetterTap = nil,   -- function(j): letter j of the word being built
}

-- Layout, top to bottom: the rows, each centred so the whole reads as a
-- pyramid (or a diamond), with the letter added (+E) or removed (-E) in a
-- column on the left; then, a little apart, the tiles of the row being
-- filled -- at the bottom, next to the buttons and under the thumb.
function BoardWidget:init()
    local board = self.board
    local rows = math.max(board:rowCount(), 1)
    local widest = 0
    for _i, r in ipairs(board.rows) do widest = math.max(widest, #r.key) end
    -- Width: a label column of 1.5 cells, the widest row, and the same 1.5
    -- cells on the right so the rows stay centred on the screen. Height: the
    -- rows a tenth of a cell apart, the tiles 0.6 cell below them.
    local cell = math.floor(math.min(self.max_width / (widest + 3),
        self.max_height / (rows + 1 + 0.1 * (rows - 1) + 0.6)))
    cell = math.max(cell, 14)
    self.cell     = cell
    self.label_w  = math.floor(cell * 1.5)
    self.row_gap  = math.max(2, math.floor(cell * 0.1))
    self.rows     = rows
    self.widest   = widest
    self.w        = 2 * self.label_w + widest * cell
    self.tiles_y  = rows * cell + (rows - 1) * self.row_gap + math.floor(cell * 0.6)
    self.h        = self.tiles_y + cell
    self.dimen = Geom:new{ w = self.w, h = self.h }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }

    self.letter_face = fitFace("smallinfofont", "W", math.floor(cell * 0.7), math.floor(cell * 0.55))
    self.label_face  = fitFace("smallinfofont", "+W", math.floor(self.label_w * 0.9), math.floor(cell * 0.45))

    self.ges_events = {
        BoardTap = { GestureRange:new{ ges = "tap", range = function() return self.paint_rect end } },
    }
end

function BoardWidget:_rowY(i)
    return (i - 1) * (self.cell + self.row_gap)
end

-- Left edge of row i's first box, from the widget's left.
function BoardWidget:_rowX(i)
    local n = #self.board.rows[i].key
    return self.label_w + math.floor((self.widest - n) * self.cell / 2)
end

function BoardWidget:_tilesX(n)
    return self.label_w + math.floor((self.widest - n) * self.cell / 2)
end

function BoardWidget:onBoardTap(_, ges)
    if not (ges and ges.pos) or not self.paint_rect then return true end
    local lx = ges.pos.x - self.paint_rect.x
    local ly = ges.pos.y - self.paint_rect.y
    if lx < 0 or ly < 0 or lx >= self.w then return true end
    local board, cell = self.board, self.cell
    if ly >= self.tiles_y then
        local tiles = board.active and board:tilesFor(board.active) or {}
        local t = math.floor((lx - self:_tilesX(#tiles)) / cell) + 1
        if t >= 1 and t <= #tiles and self.onTileTap then self.onTileTap(t) end
        return true
    end
    local i = math.floor(ly / (cell + self.row_gap)) + 1
    if i < 1 or i > self.rows then return true end
    if i == board.active then
        -- A letter of the word being built goes back to the tiles.
        local j = math.floor((lx - self:_rowX(i)) / cell) + 1
        if j >= 1 and j <= #board.current and self.onLetterTap then
            self.onLetterTap(j)
            return true
        end
    end
    if self.onRowTap then self.onRowTap(i) end
    return true
end

function BoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local board = self.board
    local cell  = self.cell
    local half  = math.floor(cell / 2)
    local thick = math.max(2, math.floor(cell / 16))

    bb:paintRect(x, y, self.w, self.h, C_BG)

    local building = board.active and board:currentWord() or ""
    for i, row in ipairs(board.rows) do
        local ry = y + self:_rowY(i)
        local word, bg, border, color, t
        if row.given then
            word, bg, border, color, t = board.entries[i], C_GIVEN, C_BORDER, C_TEXT, 1
        elseif board.entries[i] then
            word, bg, border, t = board.entries[i], C_FILLED, C_BORDER, 1
            color = board.hinted[i] and C_DIM or C_TEXT
        elseif i == board.active then
            word, bg, border, color, t = building, C_BG, C_BORDER, C_TEXT, thick
        elseif board.result == "revealed" then
            word, bg, border, color, t = board:solution(i), C_BG, C_DIM, C_DIM, 1
        else
            word, bg, border, color, t = "", C_BG, C_DIM, C_TEXT, 1
        end
        if i == board.active and board.entries[i] then
            -- A filled row picked again: what is typed replaces the word.
            word, bg, t = building, C_BG, thick
        end
        if row.op then
            drawCentered(bb, self.label_face, row.op .. row.letter,
                x + math.floor(self.label_w / 2), ry + half, C_TEXT)
        end
        local rx = x + self:_rowX(i)
        for k = 1, #row.key do
            local bx = rx + (k - 1) * cell
            drawBox(bb, bx, ry, cell, bg, border, t)
            local ch = (word or ""):sub(k, k)
            if ch ~= "" then
                drawCentered(bb, self.letter_face, ch, bx + half, ry + half, color)
            end
        end
    end

    -- The active row's tiles; the added letter has a thick border.
    if not board.active then return end
    local tiles = board:tilesFor(board.active)
    local used  = board:usedTiles()
    local tx, ty = x + self:_tilesX(#tiles), y + self.tiles_y
    for k, tile in ipairs(tiles) do
        local bx = tx + (k - 1) * cell
        drawBox(bb, bx, ty, cell, used[k] and C_USED or C_TILE, C_BORDER, tile.new and thick or 1)
        drawCentered(bb, self.letter_face, tile.letter, bx + half, ty + half,
            used[k] and C_DIM or C_TEXT)
    end
end

-- `parent` is the screen: UIManager only repaints top-level widgets, so
-- marking the board itself dirty would refresh the old pixels.
function BoardWidget:refresh(parent)
    UIManager:setDirty(parent or self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

return BoardWidget
