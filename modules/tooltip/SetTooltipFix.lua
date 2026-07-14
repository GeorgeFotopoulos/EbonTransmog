-- EbonTransmog: modules/tooltip/SetTooltipFix.lua
-- Tooltip post-processing for Ebonhold:
-- 1) Recompute tier-set piece counts from actual equipped item links.
-- 2) Normalize affix proc lines on comparison tooltips (ShoppingTooltip*).

EbonTransmog = EbonTransmog or {}
EbonTransmog.SetTooltipFix = EbonTransmog.SetTooltipFix or {}

local Fix = EbonTransmog.SetTooltipFix

local EQUIP_SLOTS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- Blizzard-style: set header is gold; many UIs also color equipped pieces gold-ish.
local COLOR_EQUIPPED = { 1, 0.82, 0 }
local COLOR_MISSING = { 0.5, 0.5, 0.5 }
local COLOR_HEADER = { 1, 0.82, 0 }
local COLOR_BONUS_ACTIVE = { 0, 1, 0 }
local COLOR_BONUS_INACTIVE = { 0.5, 0.5, 0.5 }

local AFFIX_TAG = "@affix@"
local AFFIX_COLOR = "|cffb048f8"
local AFFIX_TEXT_COLOR = { 0.69, 0.28, 0.97 }
local AFFIX_TOOLTIP_WIDTH = 300

local hookedTooltips = {}
local pendingApply = {}

local function StripColor(text)
    if not text then
        return ""
    end
    return text:gsub("|c%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function Trim(text)
    return (text or ""):match("^%s*(.-)%s*$") or ""
end

local function NormalizeSetItemName(name)
    name = Trim(StripColor(name))
    name = name:gsub("^Sanctified ", "")
    name = name:gsub(" of .+$", "")
    return name
end

local function MatchesSetPiece(equippedName, pieceName)
    return NormalizeSetItemName(equippedName) == Trim(StripColor(pieceName))
end

local function GetEquipmentUnit(tooltip)
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    if owner and owner.unit and UnitExists(owner.unit) then
        return owner.unit
    end
    return "player"
end

local function GetEquippedItemNames(unit)
    local names = {}
    if not unit or not UnitExists(unit) or not GetInventoryItemLink then
        return names
    end

    for i = 1, #EQUIP_SLOTS do
        local slot = EQUIP_SLOTS[i]
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local name = GetItemInfo(link)
            if name and name ~= "" then
                names[#names + 1] = name
            end
        end
    end

    return names
end

local function IsSetBonusLine(text)
    -- Tolerate odd spacing and keep matching after color stripping.
    if text:match("^%(%s*%d+%s*%)%s*Set:") then
        return true
    end
    -- Some builds render without parentheses: "2 Set: ..."
    if text:match("^%s*%d+%s*Set:") then
        return true
    end
    return false
end

local function IsOutsideSetBlockLine(text)
    if text == "" then
        return false
    end
    if IsSetBonusLine(text) then
        return false
    end
    if text:find("^GearScore:", 1, true) then return true end
    if text:find("^HunterScore:", 1, true) then return true end
    if text:find("^Item ID:", 1, true) then return true end
    if text:find("^Requires ", 1, true) then return true end
    if text:find("^Equip:", 1, true) then return true end
    if text:find("^Use:", 1, true) then return true end
    if text:find("^%-%-", 1, true) then return true end
    if text:find("^%[EC%]", 1, true) then return true end
    if text:find("^Alt%+", 1, true) then return true end
    if text:find("^Equipment Sets:", 1, true) then return true end
    if text:find("^<Shift", 1, true) then return true end
    if text:find("^\".-\"$") then return true end
    if text:find("^<.->$") then return true end
    if text:match("^%+") then return true end
    if text:find("^Sell Price:", 1, true) then return true end
    if text:find("^Disenchant:", 1, true) then return true end
    if text:find("^Total owned:", 1, true) then return true end
    return false
end

local function ParseSetBonusThreshold(text)
    local n = text:match("^%(%s*(%d+)%s*%)%s*Set:")
    if not n then
        n = text:match("^%s*(%d+)%s*Set:")
    end
    return tonumber(n)
end

local function FixSetBlock(tooltip, lineIndex, headerLine, headerText)
    local tooltipName = tooltip:GetName()
    if not tooltipName then
        return false
    end

    local setName, _, totalCount = headerText:match("^(.+) %((%d+)/(%d+)%)$")
    totalCount = tonumber(totalCount)
    if not setName or not totalCount or totalCount <= 0 then
        return false
    end

    local equippedNames = GetEquippedItemNames(GetEquipmentUnit(tooltip))
    local pieces = {}
    local bonusBlocks = {} -- { threshold = n, lines = { FontString, ... } }
    local lineCount = tooltip:NumLines()

    for i = lineIndex + 1, lineCount do
        local pieceLine = _G[tooltipName .. "TextLeft" .. i]
        if not pieceLine then
            break
        end

        local pieceText = Trim(StripColor(pieceLine:GetText()))
        if pieceText == "" then
            -- Blizzard tooltips often include spacer blank lines inside the set block,
            -- especially between piece list and bonus headers. Ignore those unless
            -- we're already in the bonus section (then a blank line usually ends it).
            if #bonusBlocks > 0 then
                break
            end
        else
            if IsOutsideSetBlockLine(pieceText) then
                break
            end
            if IsSetBonusLine(pieceText) then
                local threshold = ParseSetBonusThreshold(pieceText)
                bonusBlocks[#bonusBlocks + 1] = { threshold = threshold, lines = { pieceLine } }
            elseif #bonusBlocks == 0 then
                -- Set piece list is always first.
                pieces[#pieces + 1] = { line = pieceLine, name = pieceText }
            else
                -- Bonus description lines belong to the most recent bonus header.
                local cur = bonusBlocks[#bonusBlocks]
                if cur then
                    cur.lines[#cur.lines + 1] = pieceLine
                end
            end
        end
    end

    if #pieces == 0 then
        return false
    end

    local equippedCount = 0
    for i = 1, #pieces do
        local piece = pieces[i]
        local isEquipped = false
        for j = 1, #equippedNames do
            if MatchesSetPiece(equippedNames[j], piece.name) then
                isEquipped = true
                break
            end
        end

        if isEquipped then
            equippedCount = equippedCount + 1
            piece.line:SetTextColor(COLOR_EQUIPPED[1], COLOR_EQUIPPED[2], COLOR_EQUIPPED[3])
        else
            piece.line:SetTextColor(COLOR_MISSING[1], COLOR_MISSING[2], COLOR_MISSING[3])
        end
    end

    headerLine:SetText(string.format("%s (%d/%d)", setName, equippedCount, totalCount))
    headerLine:SetTextColor(COLOR_HEADER[1], COLOR_HEADER[2], COLOR_HEADER[3])

    for i = 1, #bonusBlocks do
        local bonus = bonusBlocks[i]
        local threshold = bonus.threshold
        local active = threshold and equippedCount >= threshold
        local r, g, b = COLOR_BONUS_INACTIVE[1], COLOR_BONUS_INACTIVE[2], COLOR_BONUS_INACTIVE[3]
        if active then
            r, g, b = COLOR_BONUS_ACTIVE[1], COLOR_BONUS_ACTIVE[2], COLOR_BONUS_ACTIVE[3]
        end
        for j = 1, #bonus.lines do
            local line = bonus.lines[j]
            if line and line.SetTextColor then
                line:SetTextColor(r, g, b)
            end
        end
    end

    return true
end

local function CollapseWhitespace(text)
    return Trim((text or ""):gsub("%s+", " "))
end

local function IsAffixLabel(text)
    text = CollapseWhitespace(StripColor(text))
    if text == "" then
        return false
    end
    return text == "Affix:"
        or text == "(Affix):"
        or text == "(Affix)"
        or text == AFFIX_TAG
end

local function PickLongerSimilarText(a, b)
    a = CollapseWhitespace(a)
    b = CollapseWhitespace(b)
    if a == "" then return b end
    if b == "" then return a end
    local probeLen = math.min(48, #a, #b)
    if probeLen <= 0 then
        return #a >= #b and a or b
    end
    local aProbe = a:lower():sub(1, probeLen)
    local bProbe = b:lower():sub(1, probeLen)
    if aProbe == bProbe or a:lower():find(bProbe, 1, true) or b:lower():find(aProbe, 1, true) then
        return #a >= #b and a or b
    end
    return nil
end

local function ExtractAffixDescription(text)
    if not text or text == "" then
        return nil
    end

    local plain = StripColor(text)
    local inner = plain:match("@affix@(.-)@affix@")
    if inner and inner ~= "" then
        return CollapseWhitespace(inner)
    end

    plain = plain:gsub("^%s*(%(Affix%)|Affix)%s*:?%s*", "")
    plain = CollapseWhitespace(plain)

    local splitAt = plain:find("Affix:", 1, true)
    if not splitAt then
        splitAt = plain:find("(Affix):", 1, true)
    end
    if splitAt then
        local before = CollapseWhitespace(plain:sub(1, splitAt - 1))
        local after = CollapseWhitespace(plain:sub(splitAt):gsub("^%(Affix%):%s*", ""):gsub("^Affix:%s*", ""))
        if before ~= "" and after ~= "" then
            local merged = PickLongerSimilarText(before, after)
            if merged then
                return merged
            end
        end
        if before ~= "" then
            return before
        end
        if after ~= "" then
            return after
        end
    end

    plain = plain:gsub("%s*Affix:%s*$", "")
    plain = plain:gsub("%s*%(Affix%):%s*$", "")
    plain = CollapseWhitespace(plain)
    if plain == "" then
        return nil
    end
    return plain
end

local function LooksLikeAffixLine(text)
    if not text or text == "" then
        return false
    end
    local plain = StripColor(text)
    if plain:find(AFFIX_TAG, 1, true) then
        return true
    end
    if plain:find("%(Affix%)", 1, true) then
        return true
    end
    if plain:find("Affix:", 1, true) then
        return true
    end
    return false
end

local function ApplyAffixLineLayout(leftLine, rawText)
    if not leftLine or not rawText then
        return false
    end

    if IsAffixLabel(rawText) then
        leftLine:SetText("")
        if leftLine.Hide then
            leftLine:Hide()
        end
        return true
    end

    if not LooksLikeAffixLine(rawText) then
        return false
    end

    local description = ExtractAffixDescription(rawText)
    if not description or description == "" then
        return false
    end

    leftLine:SetText(AFFIX_COLOR .. description .. "|r")
    leftLine:SetTextColor(AFFIX_TEXT_COLOR[1], AFFIX_TEXT_COLOR[2], AFFIX_TEXT_COLOR[3])
    if leftLine.SetWordWrap then
        leftLine:SetWordWrap(true)
    end
    if leftLine.SetWidth then
        leftLine:SetWidth(AFFIX_TOOLTIP_WIDTH)
    end
    if leftLine.Show then
        leftLine:Show()
    end
    return true
end

local function FixAffixLines(tooltip)
    if not tooltip or not tooltip.GetName or not tooltip.NumLines then
        return false
    end

    local tooltipName = tooltip:GetName()
    if not tooltipName then
        return false
    end

    local changed = false
    local lineCount = tooltip:NumLines() or 0

    for i = 1, lineCount do
        local leftLine = _G[tooltipName .. "TextLeft" .. i]
        if leftLine and leftLine.GetText then
            if ApplyAffixLineLayout(leftLine, leftLine:GetText()) then
                changed = true
            end
        end

        local rightLine = _G[tooltipName .. "TextRight" .. i]
        if rightLine and rightLine.GetText and IsAffixLabel(rightLine:GetText()) then
            rightLine:SetText("")
            if rightLine.Hide then
                rightLine:Hide()
            end
            changed = true
        end
    end

    return changed
end

function Fix.Apply(tooltip)
    if not tooltip or not tooltip.GetName or not tooltip.NumLines then
        return
    end

    local tooltipName = tooltip:GetName()
    if not tooltipName then
        return
    end

    FixAffixLines(tooltip)
    local lineCount = tooltip:NumLines()

    for i = 1, lineCount do
        local line = _G[tooltipName .. "TextLeft" .. i]
        if line then
            local text = Trim(StripColor(line:GetText()))
            if text:match(" %(%d+/%d+%)$") then
                FixSetBlock(tooltip, i, line, text)
            end
        end
    end
end

local function ScheduleApply(tooltip)
    if not tooltip then
        return
    end

    Fix.Apply(tooltip)

    if not C_Timer or not C_Timer.After then
        return
    end

    if pendingApply[tooltip] then
        return
    end
    pendingApply[tooltip] = true

    C_Timer.After(0.05, function()
        pendingApply[tooltip] = nil
        if tooltip and tooltip.IsShown and tooltip:IsShown() then
            Fix.Apply(tooltip)
        end
    end)
end

local function HookTooltip(tooltip)
    if not tooltip or hookedTooltips[tooltip] then
        return
    end
    hookedTooltips[tooltip] = true

    if tooltip.HookScript then
        tooltip:HookScript("OnTooltipSetItem", function(self)
            ScheduleApply(self)
        end)
    end

    if tooltip.SetHyperlinkCompareItem then
        hooksecurefunc(tooltip, "SetHyperlinkCompareItem", function(tip)
            ScheduleApply(tip)
        end)
    end
end

function Fix.Init()
    HookTooltip(GameTooltip)
    HookTooltip(ItemRefTooltip)
    HookTooltip(ShoppingTooltip1)
    HookTooltip(ShoppingTooltip2)
    HookTooltip(ShoppingTooltip3)
    HookTooltip(ItemRefShoppingTooltip1)
    HookTooltip(ItemRefShoppingTooltip2)
    HookTooltip(ItemRefShoppingTooltip3)
end

Fix.Init()
