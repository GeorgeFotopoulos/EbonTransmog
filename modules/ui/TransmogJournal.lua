-- EbonTransmog: modules/ui/TransmogJournal.lua

EbonTransmog = EbonTransmog or {}
local Journal = {}
EbonTransmog.TransmogJournal = Journal

local Service = EbonTransmog.AppearanceService
local Preview = EbonTransmog.PreviewModel
local Loadouts = EbonTransmog.LoadoutService
local Applier = EbonTransmog.LoadoutApplier
local Catalog = EbonTransmog.SlotCatalog

local WHITE8x8 = "Interface\\Buttons\\WHITE8x8"
local C_BG = { 0.05, 0.05, 0.07, 0.97 }
local C_BORDER = { 0.15, 0.15, 0.18, 1 }
local C_GOLD = { 1, 0.82, 0, 1 }
local C_HOVER = { 0.25, 0.78, 0.92, 1 }

local ICON_SIZE = 40
local ICON_PAD = 4
local ICONS_PER_ROW = 7
local FRAME_WIDTH = 920
local FRAME_HEIGHT = 660
local PREVIEW_WIDTH = 280
local SCROLLBAR_W = 8

local qualityFallback = {
    [0] = { 0.62, 0.62, 0.62 },
    [1] = { 1.0, 1.0, 1.0 },
    [2] = { 0.12, 1.0, 0.12 },
    [3] = { 0.0, 0.44, 1.0 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1.0, 0.5, 0.0 },
    [6] = { 1.0, 0.8, 0.0 },
}

local function GetQualityColor(quality)
    quality = quality or 0
    if GetItemQualityColor then
        local r, g, b = GetItemQualityColor(quality)
        if r and g and b then
            return { r, g, b }
        end
    end
    return qualityFallback[quality] or qualityFallback[0]
end

local SUB_TAB_COLS = 6
local SUB_TAB_ROW_H = 22
local SUB_TAB_GAP = 4

local RARITY_OPTIONS = {
    { quality = 1, label = "Common" },
    { quality = 2, label = "Uncommon" },
    { quality = 3, label = "Rare" },
    { quality = 4, label = "Epic" },
    { quality = 5, label = "Legendary" },
}

local journalFrame
local browseCategory = "armor"
local weaponGroup = "one_handed"
local activeDraftSub = "head"
local currentSearch = ""
local rarityFilter = {}
local rarityFilterBar
local rarityFilterButtons = {}
local armorTypeFilter = {}
local armorFilterBar
local armorFilterButtons = {}
local categoryFilterBar
local categoryFilterButtons = {}
local weaponGroupFilterBar
local weaponGroupFilterButtons = {}
local selectedItemId = nil
local gridButtons = {}
local subTabButtons = {}
local subTabBar
local scrollFrame
local scrollBar
local scrollChild
local countLabel
local searchBox
local previewHolder
local previewName
local microButton
local emptyStateLabel
local loadoutPanel
local loadoutNameBox
local loadoutSlotRows = {}
local loadoutSlotScrollFrame
local loadoutSlotScrollChild
local loadoutSlotScrollBar
local loadoutPanelTitle
local savedLoadoutMenuBtn
local savedLoadoutMenuPopup
local savedLoadoutMenuCatcher
local savedLoadoutMenuContent
local savedLoadoutMenuRows = {}
local loadoutHintLabel
local searchPlaceholder
local draftSlots = {}
local inspectSlots = {}
local selectedLoadoutName = nil

local JOURNAL_FRAME_STRATA = "HIGH"
local JOURNAL_FRAME_LEVEL = 25

-- Forward declare so callbacks capture local upvalues (not globals).
local LoadDraftFromLoadout

local function ApplyBackdrop(frame, bg, border, edgeSize)
    if not frame.SetBackdrop then return end
    edgeSize = edgeSize or 2
    frame:SetBackdrop({
        bgFile = WHITE8x8,
        edgeFile = WHITE8x8,
        tile = true,
        tileSize = 16,
        edgeSize = edgeSize,
        insets = { left = edgeSize, right = edgeSize, top = edgeSize, bottom = edgeSize },
    })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function IsBagPanelFrame(frame)
    if not frame or not frame.GetName then return false end
    local name = frame:GetName() or ""
    if name:find("DragonUI_CombuctorFrame", 1, true) then return true end
    if name:find("ContainerFrame", 1, true) then return true end
    return false
end

local function RaiseFrame(frame)
    if frame and frame.Raise then frame:Raise() end
end

local function PromoteOpenBagFramesAboveJournal()
    for id = 1, 20 do
        local bagFrame = _G["DragonUI_CombuctorFrame" .. id]
        if bagFrame and bagFrame.IsShown and bagFrame:IsShown() then
            RaiseFrame(bagFrame)
        end
    end
    for id = 1, 13 do
        local bagFrame = _G["ContainerFrame" .. id]
        if bagFrame and bagFrame.IsShown and bagFrame:IsShown() then
            RaiseFrame(bagFrame)
        end
    end
end

local function InstallBagPanelHook()
    if EbonTransmog._bagPanelHooked or not hooksecurefunc then return end
    EbonTransmog._bagPanelHooked = true
    hooksecurefunc("ShowUIPanel", function(frame)
        if not journalFrame or not journalFrame:IsShown() or not IsBagPanelFrame(frame) then return end
        local function promote()
            if frame and frame.IsShown and frame:IsShown() then
                RaiseFrame(frame)
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, promote)
        else
            promote()
        end
    end)
end

local function WireButtonHover(btn, onEnter, onLeave)
    if not btn then return end
    btn:EnableMouse(true)
    if onEnter then btn:SetScript("OnEnter", onEnter) end
    if onLeave then btn:SetScript("OnLeave", onLeave) end
end

local function WireFilterTabHover(btn, refreshAppearance)
    WireButtonHover(btn, function(self)
        self:SetBackdropColor(0.14, 0.14, 0.16, 1)
        self:SetBackdropBorderColor(C_GOLD[1] * 0.55, C_GOLD[2] * 0.55, C_GOLD[3] * 0.35, 1)
    end, function()
        if refreshAppearance then refreshAppearance() end
    end)
end

local function WireRarityFilterHover(btn, refreshAppearance)
    WireButtonHover(btn, function(self)
        self:SetBackdropColor(0.12, 0.12, 0.14, 1)
        self:SetBackdropBorderColor(C_GOLD[1] * 0.45, C_GOLD[2] * 0.45, C_GOLD[3] * 0.25, 1)
        if self.label and self.quality then
            local qc = GetQualityColor(self.quality)
            self.label:SetTextColor(qc[1], qc[2], qc[3])
        end
    end, function()
        if refreshAppearance then refreshAppearance() end
    end)
end

local function WireToolbarButtonHover(btn)
    WireButtonHover(btn, function(self)
        self:SetBackdropColor(0.14, 0.14, 0.16, 1)
        self:SetBackdropBorderColor(C_GOLD[1] * 0.55, C_GOLD[2] * 0.55, C_GOLD[3] * 0.3, 1)
        if self.label then
            self.label:SetTextColor(0.95, 0.95, 0.95)
        end
    end, function(self)
        self:SetBackdropColor(0.08, 0.08, 0.1, 1)
        self:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], C_BORDER[4] or 1)
        if self.label then
            self.label:SetTextColor(0.78, 0.78, 0.78)
        end
    end)
end

local function CreateStyledCloseButton(parent, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(22, 22)
    ApplyBackdrop(btn, { 0.08, 0.08, 0.1, 1 }, C_BORDER, 1)
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn.label:SetPoint("CENTER", 0, 0)
    btn.label:SetText("×")
    btn.label:SetTextColor(0.78, 0.78, 0.78)
    WireButtonHover(btn, function(self)
        self:SetBackdropColor(0.16, 0.06, 0.06, 1)
        self:SetBackdropBorderColor(0.85, 0.28, 0.28, 1)
        self.label:SetTextColor(1, 0.4, 0.4)
    end, function(self)
        self:SetBackdropColor(0.08, 0.08, 0.1, 1)
        self:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], C_BORDER[4] or 1)
        self.label:SetTextColor(0.78, 0.78, 0.78)
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function SetShown(frame, show)
    if not frame then return end
    if show then frame:Show() else frame:Hide() end
end

local function SetTabSelected(btn, selected)
    if selected then
        btn:SetBackdropColor(C_GOLD[1] * 0.25, C_GOLD[2] * 0.25, C_GOLD[3] * 0.1, 1)
        btn:SetBackdropBorderColor(C_GOLD[1] * 0.75, C_GOLD[2] * 0.75, C_GOLD[3] * 0.45, 1)
        btn.label:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
    else
        btn:SetBackdropColor(0.08, 0.08, 0.1, 1)
        btn:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], C_BORDER[4] or 1)
        btn.label:SetTextColor(0.75, 0.75, 0.75)
    end
end

local function RefreshSubTabAppearance()
    for _, btn in ipairs(subTabButtons) do
        SetTabSelected(btn, btn.subId == activeDraftSub)
    end
end

local function HideFramePart(frame)
    if not frame then return end
    frame:Hide()
    if frame.SetAlpha then frame:SetAlpha(0) end
    if frame.EnableMouse then frame:EnableMouse(false) end
end

local function HideScrollBarTemplateParts(bar)
    if not bar then return end
    local barName = bar.GetName and bar:GetName()
    if barName then
        for _, suffix in ipairs({ "ScrollUpButton", "ScrollDownButton", "Border" }) do
            HideFramePart(_G[barName .. suffix])
        end
    end
    HideFramePart(bar.ScrollUpButton)
    HideFramePart(bar.ScrollDownButton)
end

local function StyleVerticalScrollBar(bar)
    if not bar or bar._ebonStyled then return end
    bar._ebonStyled = true
    bar:SetWidth(SCROLLBAR_W)
    if bar.SetOrientation then
        bar:SetOrientation("VERTICAL")
    end
    HideScrollBarTemplateParts(bar)

    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(WHITE8x8)
    track:SetVertexColor(0.03, 0.03, 0.05, 1)
    track:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, 0)
    track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 0)
    bar._ebonTrack = track

    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture(WHITE8x8)
    thumb:SetVertexColor(C_BORDER[1] + 0.12, C_BORDER[2] + 0.12, C_BORDER[3] + 0.14, 1)
    thumb:SetWidth(math.max(4, SCROLLBAR_W - 2))
    bar:SetThumbTexture(thumb)
    bar._ebonThumb = thumb

    if bar.HookScript then
        bar:HookScript("OnShow", function()
            HideScrollBarTemplateParts(bar)
            if bar._ebonThumb then
                bar._ebonThumb:SetVertexColor(C_GOLD[1] * 0.45, C_GOLD[2] * 0.45, C_GOLD[3] * 0.25, 1)
            end
            if bar._ebonTrack then
                bar._ebonTrack:SetVertexColor(0.03, 0.03, 0.05, 1)
            end
        end)
    end
end

local function CreateStyledVerticalScrollBar(parent, name)
    local bar = CreateFrame("Slider", name, parent, "UIPanelScrollBarTemplate")
    StyleVerticalScrollBar(bar)
    return bar
end

local function SelectActiveSub(subId)
    if not subId then return end
    if Catalog.IsWeaponSlotKey(subId) then
        browseCategory = "weapons"
        local itemId = GetEffectiveSlotItem(subId)
        if itemId then
            local meta = Service.GetItemMeta(itemId)
            if meta and meta.sub then
                activeDraftSub = meta.sub
                weaponGroup = Catalog.GetWeaponGroupForSub(meta.sub) or weaponGroup
                return
            end
        end
        if subId == Catalog.WEAPON_SLOT_KEYS.ranged then
            weaponGroup = "ranged"
        else
            weaponGroup = "one_handed"
        end
        local subs = Catalog.GetWeaponSubsForGroup(weaponGroup)
        activeDraftSub = subs[1] and subs[1].id or activeDraftSub
        return
    end
    activeDraftSub = subId
    local cat = Catalog.GetCategoryForSub(subId)
    if cat == "armor" then
        browseCategory = "armor"
    elseif cat == "weapons" then
        browseCategory = "weapons"
        weaponGroup = Catalog.GetWeaponGroupForSub(subId) or weaponGroup
    end
end

local function GetSubTabsList()
    if browseCategory == "armor" then
        return Catalog.GetSubcategories("armor")
    end
    return Catalog.GetWeaponSubsForGroup(weaponGroup)
end

local function EnsureValidWeaponGroup()
    if not Catalog.PlayerCanUseTwoHandedWeapons() and weaponGroup == "two_handed" then
        weaponGroup = "one_handed"
    end
end

local function EnsureValidActiveSub()
    EnsureValidWeaponGroup()
    local subs = GetSubTabsList()
    for _, sub in ipairs(subs) do
        if sub.id == activeDraftSub then return end
    end
    if subs[1] then
        activeDraftSub = subs[1].id
    end
end

local function ShouldShowArmorTypeFilters()
    return browseCategory == "armor" and Catalog.UsesArmorTypeFilter(activeDraftSub)
end

local function ShouldShowArmorTypeFilterBar()
    return browseCategory == "armor"
end

local function ArmorTypeFiltersEnabled()
    return ShouldShowArmorTypeFilters()
end

local function ShouldShowWeaponGroupFilters()
    return browseCategory == "weapons"
end

local function GetRarityFilterArg()
    if not next(rarityFilter) then return nil end
    return rarityFilter
end

local function GetArmorTypeFilterArg()
    if not ShouldShowArmorTypeFilters() or not next(armorTypeFilter) then return nil end
    return armorTypeFilter
end

local function GetGridItems()
    local rarityArg = GetRarityFilterArg()
    local armorArg = GetArmorTypeFilterArg()
    local category = Catalog.GetCategoryForSub(activeDraftSub)
    if category then
        return Service.GetItemsForSubcategory(category, activeDraftSub, currentSearch, rarityArg, armorArg)
    end
    return {}
end

local function GetGridContentWidth()
    if not scrollFrame then return 400 end
    local w = scrollFrame:GetWidth() or 400
    if scrollBar and scrollBar:IsShown() then
        return w - SCROLLBAR_W - 8
    end
    return w - 8
end

local function SetGridScroll(value)
    if not scrollFrame then return end
    value = math.max(0, value or 0)
    scrollFrame._syncingScroll = true
    scrollFrame:SetVerticalScroll(value)
    if scrollBar then
        scrollBar:SetValue(value)
    end
    scrollFrame._syncingScroll = nil
end

local function ResetGridScroll()
    SetGridScroll(0)
end

local function ScrollGridToItem(itemId)
    if not itemId or not scrollFrame or not scrollChild then return end
    local items = GetGridItems()
    local index
    for i, id in ipairs(items) do
        if id == itemId then
            index = i
            break
        end
    end
    if not index then return end

    local row = math.floor((index - 1) / ICONS_PER_ROW)
    local itemTop = 8 + row * (ICON_SIZE + ICON_PAD)
    local frameH = scrollFrame:GetHeight() or 300
    local maxScroll = scrollFrame:GetVerticalScrollRange() or 0
    local target = math.max(0, math.min(maxScroll, itemTop - frameH / 2 + ICON_SIZE / 2))
    SetGridScroll(target)
end

local function GetPreviewOutfit()
    local outfit = {}
    for subId, id in pairs(draftSlots) do
        outfit[subId] = id
    end
    for subId, id in pairs(inspectSlots) do
        outfit[subId] = id
    end
    Catalog.SanitizeWeaponOutfit(outfit)
    return outfit
end

local function GetEffectiveSlotItem(subId)
    if not subId then return nil end
    return inspectSlots[subId] or draftSlots[subId]
end

local function IsItemInDraftOrInspect(itemId)
    if not itemId then return false end
    itemId = tonumber(itemId)
    local slots = {}
    for subId in pairs(draftSlots) do slots[subId] = true end
    for subId in pairs(inspectSlots) do slots[subId] = true end
    for subId in pairs(slots) do
        if tonumber(GetEffectiveSlotItem(subId)) == itemId then
            return true
        end
    end
    return false
end

local function IsItemSelected(itemId)
    if not itemId or not selectedItemId then return false end
    return tonumber(selectedItemId) == tonumber(itemId)
end

local function ClearItemFromSlotTables(itemId)
    if not itemId then return false end
    itemId = tonumber(itemId)
    local removed = false
    for key, id in pairs(draftSlots) do
        if tonumber(id) == itemId then
            draftSlots[key] = nil
            removed = true
        end
    end
    for key, id in pairs(inspectSlots) do
        if tonumber(id) == itemId then
            inspectSlots[key] = nil
            removed = true
        end
    end
    Catalog.ClearLegacyWeaponTypeKeys(draftSlots)
    Catalog.ClearLegacyWeaponTypeKeys(inspectSlots)
    return removed
end

local function ApplyGridButtonDraftState(btn)
    if not btn or not btn.itemId then return end
    local info = Service.GetItemDisplayInfo(btn.itemId)
    local qc = GetQualityColor(info.quality)
    local inOutfit = IsItemInDraftOrInspect(btn.itemId)
    local isSelected = IsItemSelected(btn.itemId)
    if isSelected then
        btn:SetBackdropBorderColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)
        if btn.selected then btn.selected:Show() end
    else
        btn:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
        if btn.selected then btn.selected:Hide() end
    end
    if btn.draftMark then
        if inOutfit then btn.draftMark:Show()
        else btn.draftMark:Hide() end
    end
end

local function RefreshGridHighlights()
    for _, btn in ipairs(gridButtons) do
        if btn.itemId then
            ApplyGridButtonDraftState(btn)
        end
    end
end

function Journal.UpdateGridScrollRange()
    if not scrollFrame or not scrollChild then return end

    local frameHeight = scrollFrame:GetHeight() or 300
    local childHeight = scrollChild:GetHeight() or frameHeight
    local maxScroll = math.max(0, childHeight - frameHeight)

    if scrollBar then
        if maxScroll > 0 then
            scrollBar:Show()
            scrollBar:SetMinMaxValues(0, maxScroll)
            local cur = scrollFrame:GetVerticalScroll()
            if cur > maxScroll then
                cur = maxScroll
                scrollFrame:SetVerticalScroll(cur)
            end
            scrollFrame._syncingScroll = true
            scrollBar:SetValue(cur)
            scrollFrame._syncingScroll = nil
        else
            scrollBar:Hide()
            scrollBar:SetValue(0)
            scrollFrame:SetVerticalScroll(0)
        end
    end

    scrollChild:SetWidth(GetGridContentWidth())
end

local function ScrollGridBy(delta)
    if not scrollFrame then return end
    local step = (ICON_SIZE + ICON_PAD) * 2
    local cur = scrollFrame:GetVerticalScroll()
    local max = scrollFrame:GetVerticalScrollRange()
    if delta > 0 then
        SetGridScroll(math.max(0, cur - step))
    else
        SetGridScroll(math.min(max, cur + step))
    end
end

local function UpdateCountLabel()
    if not countLabel or not Service then return end
    local n = 0
    for _ in pairs(draftSlots) do n = n + 1 end
    local items = GetGridItems()
    local slotLabel = Catalog.GetGossipLabelForSub(activeDraftSub) or activeDraftSub
    countLabel:SetText(string.format("%d shown · %d in draft · %s", #items, n, slotLabel))
end

local function ClearGrid()
    for _, btn in ipairs(gridButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(gridButtons)
end

local function StyleIconButton(btn, quality)
    local qc = GetQualityColor(quality)
    ApplyBackdrop(btn, { 0.06, 0.06, 0.08, 1 }, C_BORDER, 2)
    btn:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
end

local function ShowJournalItemTooltip(itemId, info, qc)
    -- Match normal UI tooltips: default screen anchor (usually bottom-right),
    -- not anchored to grid icons or the preview pane.
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    else
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -13, 130)
    end

    local link = Service.GetItemHyperlink(itemId)
    if link then
        GameTooltip:SetHyperlink(link)
    elseif info and info.name then
        GameTooltip:SetText(info.name, qc[1], qc[2], qc[3])
    end
    GameTooltip:Show()
end

local function PurgeInvalidWeaponSlots()
    Catalog.SanitizeWeaponOutfit(draftSlots)
    Catalog.SanitizeWeaponOutfit(inspectSlots)
    if Catalog.PlayerCanUseTwoHandedWeapons() then return end
    local function purge(slots)
        if not slots then return end
        for _, key in pairs(Catalog.WEAPON_SLOT_KEYS) do
            local itemId = slots[key]
            if itemId and Catalog.IsTwoHandedWeaponItem(itemId) then
                slots[key] = nil
            end
        end
        Catalog.ClearLegacyWeaponTypeKeys(slots)
        for subId, itemId in pairs(slots) do
            if Catalog.IsTwoHandedWeaponSub(subId) or Catalog.IsTwoHandedWeaponItem(itemId) then
                slots[subId] = nil
            end
        end
    end
    purge(draftSlots)
    purge(inspectSlots)
end

local function NotifyWeaponRestriction()
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffff4444[EbonTransmog]|r Two-handed weapon transmogs are not available while dual-wielding."
    )
end

local function CanUseWeaponItemOrNotify(itemId)
    if Catalog.PlayerCanUseWeaponItem(itemId) then return true end
    NotifyWeaponRestriction()
    return false
end

local function RefreshPreview()
    if not previewHolder then return end
    previewHolder:PreviewOutfit(GetPreviewOutfit())
end

local function UpdatePreviewName(itemId)
    if previewName and itemId then
        local info = Service.GetItemDisplayInfo(itemId)
        local color = GetQualityColor(info.quality)
        previewName:SetTextColor(color[1], color[2], color[3])
        previewName:SetText(info.name or ("Item #" .. itemId))
    elseif previewName then
        previewName:SetText("Select an appearance")
        previewName:SetTextColor(0.6, 0.6, 0.6)
    end
end

local function ClearLoadoutSlot(subId)
    if not subId then return false end
    local removedItem = draftSlots[subId] or inspectSlots[subId]
    if not removedItem then return false end
    draftSlots[subId] = nil
    inspectSlots[subId] = nil
    if selectedItemId and tonumber(selectedItemId) == tonumber(removedItem) then
        selectedItemId = nil
    end
    Journal.RefreshLoadoutPanel()
    UpdateCountLabel()
    RefreshPreview()
    RefreshGridHighlights()
    UpdatePreviewName(selectedItemId)
    return true
end

local function RemoveItemFromDraftOrInspect(itemId)
    if not itemId then return end
    if not ClearItemFromSlotTables(itemId) then return end
    if selectedItemId and tonumber(selectedItemId) == tonumber(itemId) then
        selectedItemId = nil
    end
    Journal.RefreshLoadoutPanel()
    UpdateCountLabel()
    RefreshPreview()
    RefreshGridHighlights()
    UpdatePreviewName(selectedItemId)
end

local function SelectItem(itemId)
    selectedItemId = itemId
    RefreshGridHighlights()
    UpdatePreviewName(itemId)
end

local function PreviewOnCharacter(itemId, preferOffHand)
    if not itemId or not previewHolder then return end
    if not CanUseWeaponItemOrNotify(itemId) then return end

    local meta = Service.GetItemMeta(itemId)
    if not meta then return end
    if meta.category == "weapons" then
        if preferOffHand and Catalog.GetWeaponGroupForSub(meta.sub) ~= "one_handed" then
            preferOffHand = false
        end
        Catalog.AssignWeaponToSlots(inspectSlots, itemId, preferOffHand)
        Catalog.SanitizeWeaponOutfit(inspectSlots)
    else
        inspectSlots[meta.sub] = itemId
    end

    previewHolder:PreviewOutfit(GetPreviewOutfit())
    SelectItem(itemId)
    Journal.RefreshLoadoutPanel()
end

local function AssignToDraft(itemId, preferOffHand)
    if not CanUseWeaponItemOrNotify(itemId) then return end
    local meta = Service.GetItemMeta(itemId)
    if not meta then return end
    if meta.category == "weapons" then
        if preferOffHand and Catalog.GetWeaponGroupForSub(meta.sub) ~= "one_handed" then
            preferOffHand = false
        end
        local bucket = Catalog.GetWeaponBucketForMeta(meta, preferOffHand)
        local key = Catalog.WeaponBucketToSlotKey(bucket)
        if key then
            inspectSlots[key] = nil
        end
        Catalog.AssignWeaponToSlots(draftSlots, itemId, preferOffHand)
        Catalog.SanitizeWeaponOutfit(draftSlots)
    else
        draftSlots[meta.sub] = itemId
        inspectSlots[meta.sub] = nil
    end
    SelectActiveSub(meta.sub)
    Journal.RefreshLoadoutPanel()
    UpdateCountLabel()
    SelectItem(itemId)
    RefreshPreview()
end

local function CommitInspectToDraft()
    if not next(inspectSlots) then return end
    for subId, id in pairs(inspectSlots) do
        draftSlots[subId] = id
    end
    wipe(inspectSlots)
    Catalog.NormalizeWeaponSlots(draftSlots)
    Catalog.SanitizeWeaponOutfit(draftSlots)
    Journal.RefreshLoadoutPanel()
    UpdateCountLabel()
    RefreshPreview()
    RefreshGridHighlights()
end

local function BuildGrid()
    ClearGrid()
    if not scrollChild or not Service then return end

    local items = GetGridItems()
    Service.WarmItemCache(items)
    UpdateCountLabel()

    if emptyStateLabel then emptyStateLabel:Hide() end

    if #items == 0 then
        if not emptyStateLabel then
            emptyStateLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            emptyStateLabel:SetPoint("TOP", scrollChild, "TOP", 0, -40)
            emptyStateLabel:SetWordWrap(true)
            emptyStateLabel:SetJustifyH("CENTER")
        end
        emptyStateLabel:SetWidth(GetGridContentWidth() - 24)
        emptyStateLabel:SetText(
            "No collected appearances for this slot.\nRun /etmog scan at the Warpweaver first."
        )
        emptyStateLabel:Show()
        scrollChild:SetHeight(scrollFrame:GetHeight() or 300)
        return
    end

    local contentWidth = GetGridContentWidth() - 16
    local rowWidth = ICONS_PER_ROW * (ICON_SIZE + ICON_PAD)
    local startX = math.max(8, (contentWidth - rowWidth) / 2)

    for i, itemId in ipairs(items) do
        local col = (i - 1) % ICONS_PER_ROW
        local row = math.floor((i - 1) / ICONS_PER_ROW)
        local x = startX + col * (ICON_SIZE + ICON_PAD)
        local y = -8 - row * (ICON_SIZE + ICON_PAD)

        local info = Service.GetItemDisplayInfo(itemId)

        local btn = CreateFrame("Button", nil, scrollChild)
        btn:SetSize(ICON_SIZE, ICON_SIZE)
        btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, y)
        btn.itemId = itemId
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        StyleIconButton(btn, info.quality)

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(ICON_SIZE - 6, ICON_SIZE - 6)
        btn.icon:SetPoint("CENTER")
        btn.icon:SetTexture(info.icon)
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon:SetVertexColor(1, 1, 1, 1)

        btn.selected = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.selected:SetTexture(WHITE8x8)
        btn.selected:SetPoint("TOPLEFT", 1, -1)
        btn.selected:SetPoint("BOTTOMRIGHT", -1, 1)
        btn.selected:SetVertexColor(C_HOVER[1], C_HOVER[2], C_HOVER[3], 0.35)
        btn.selected:Hide()

        btn.draftMark = btn:CreateTexture(nil, "OVERLAY")
        btn.draftMark:SetTexture(WHITE8x8)
        btn.draftMark:SetPoint("TOPLEFT", -2, 2)
        btn.draftMark:SetPoint("BOTTOMRIGHT", 2, -2)
        btn.draftMark:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.55)
        btn.draftMark:Hide()

        local qc = GetQualityColor(info.quality)
        btn:SetScript("OnEnter", function(self)
            if not IsItemSelected(self.itemId) then self.selected:Show() end
            local id = self.itemId
            local display = Service.GetItemDisplayInfo(id)
            local itemQc = GetQualityColor(display.quality)
            ShowJournalItemTooltip(id, display, itemQc)
        end)
        btn:SetScript("OnLeave", function(self)
            ApplyGridButtonDraftState(self)
            GameTooltip:Hide()
        end)

        btn:SetScript("OnClick", function(self, button)
            local id = self.itemId
            if button == "RightButton" then
                RemoveItemFromDraftOrInspect(id)
                GameTooltip:Hide()
                return
            end
            if button ~= "LeftButton" then return end
            if IsShiftKeyDown() then
                local link = Service.GetItemHyperlink(id)
                if link and ChatEdit_InsertLink then
                    ChatEdit_InsertLink(link)
                end
            elseif IsControlKeyDown() then
                PreviewOnCharacter(id, IsAltKeyDown())
            else
                AssignToDraft(id, IsAltKeyDown())
            end
        end)

        ApplyGridButtonDraftState(btn)
        gridButtons[i] = btn
    end

    local rows = math.max(1, math.ceil(#items / ICONS_PER_ROW))
    scrollChild:SetHeight(math.max(16 + rows * (ICON_SIZE + ICON_PAD), scrollFrame:GetHeight() or 300))
    Journal.UpdateGridScrollRange()
end

local function GetSubTabBarHeight(numSubs)
    if numSubs <= 0 then return 0 end
    local rows = math.ceil(numSubs / SUB_TAB_COLS)
    return rows * SUB_TAB_ROW_H + math.max(0, rows - 1) * SUB_TAB_GAP
end

local function RefreshSubTabs()
    if not subTabBar then return end
    for _, child in ipairs(subTabButtons) do child:Hide() end
    wipe(subTabButtons)

    subTabBar:Show()
    EnsureValidActiveSub()
    local subs = GetSubTabsList()
    subTabBar:SetHeight(GetSubTabBarHeight(#subs))

    local barWidth = subTabBar:GetWidth() or 400
    local btnWidth = math.floor((barWidth - (SUB_TAB_COLS - 1) * SUB_TAB_GAP) / SUB_TAB_COLS)

    for i, sub in ipairs(subs) do
        local row = math.floor((i - 1) / SUB_TAB_COLS)
        local col = (i - 1) % SUB_TAB_COLS
        local x = col * (btnWidth + SUB_TAB_GAP)
        local y = -row * (SUB_TAB_ROW_H + SUB_TAB_GAP)

        local btn = CreateFrame("Button", nil, subTabBar)
        btn:SetSize(btnWidth, SUB_TAB_ROW_H)
        btn:SetPoint("TOPLEFT", subTabBar, "TOPLEFT", x, y)
        ApplyBackdrop(btn, { 0.07, 0.07, 0.09, 1 }, C_BORDER, 1)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("LEFT", 4, 0)
        btn.label:SetPoint("RIGHT", -4, 0)
        btn.label:SetJustifyH("CENTER")
        btn.label:SetWordWrap(false)
        btn.label:SetText(sub.label)
        btn.subId = sub.id
        btn:SetScript("OnClick", function(self)
            SelectActiveSub(self.subId)
            selectedItemId = nil
            ResetGridScroll()
            Journal.Refresh()
        end)
        WireFilterTabHover(btn, RefreshSubTabAppearance)
        SetTabSelected(btn, sub.id == activeDraftSub)
        subTabButtons[i] = btn
    end
end

function Journal.RefreshCategoryFilters()
    for _, btn in ipairs(categoryFilterButtons) do
        local selected = (btn.category == "armor" and browseCategory == "armor")
            or (btn.category == "weapons" and browseCategory == "weapons")
        SetTabSelected(btn, selected)
    end
end

function Journal.RefreshWeaponGroupFilters()
    local groups = Catalog.GetAvailableWeaponGroups()
    local visible = {}
    for _, groupId in ipairs(groups) do visible[groupId] = true end

    local gap = 4
    local barWidth = weaponGroupFilterBar and weaponGroupFilterBar:GetWidth() or 400
    local btnW = math.floor((barWidth - gap * (math.max(1, #groups) - 1)) / math.max(1, #groups))
    local x = 0

    for _, btn in ipairs(weaponGroupFilterButtons) do
        if visible[btn.groupId] then
            btn:Show()
            btn:SetWidth(btnW)
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", weaponGroupFilterBar, "LEFT", x, 0)
            x = x + btnW + gap
            SetTabSelected(btn, btn.groupId == weaponGroup)
        else
            btn:Hide()
        end
    end
end

local MENU_ROW_H = 20
local MENU_HDR_H = 18
local MENU_PAD = 4

local function ClearLoadoutMenuPopupChildren()
    if loadoutMenuContent then
        loadoutMenuContent:Hide()
        loadoutMenuContent:SetParent(nil)
        loadoutMenuContent = nil
    end
    wipe(savedLoadoutMenuRows)
end

local function HideLoadoutMenu()
    if savedLoadoutMenuPopup then savedLoadoutMenuPopup:Hide() end
    if savedLoadoutMenuCatcher then savedLoadoutMenuCatcher:Hide() end
    ClearLoadoutMenuPopupChildren()
end

local function GetLoadoutMenuLabel()
    if selectedLoadoutName and selectedLoadoutName ~= "" then
        return selectedLoadoutName
    end
    if loadoutNameBox then
        local name = loadoutNameBox:GetText() or ""
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then return name end
    end
    EbonTransmogDB = EbonTransmogDB or {}
    if EbonTransmogDB.lastLoadoutName and EbonTransmogDB.lastLoadoutName ~= "" then
        return EbonTransmogDB.lastLoadoutName
    end
    return "Load"
end

local function UpdateLoadoutMenuButtonLabel()
    if not savedLoadoutMenuBtn or not savedLoadoutMenuBtn.label then return end
    savedLoadoutMenuBtn.label:SetText(GetLoadoutMenuLabel())
end

function Journal.SetActiveLoadoutName(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    selectedLoadoutName = name
    EbonTransmogDB = EbonTransmogDB or {}
    EbonTransmogDB.lastLoadoutName = name
    if loadoutNameBox then loadoutNameBox:SetText(name) end
    UpdateLoadoutMenuButtonLabel()
end

function Journal.RestoreActiveLoadoutFromDB()
    EbonTransmogDB = EbonTransmogDB or {}
    local name = EbonTransmogDB.lastLoadoutName
    if (not name or name == "") and Loadouts and Loadouts.GetAll then
        local saved = Loadouts.GetAll()
        if #saved == 1 and saved[1].name and saved[1].name ~= "" then
            name = saved[1].name
            EbonTransmogDB.lastLoadoutName = name
        end
    end
    if not name or name == "" then return end

    if Loadouts and Loadouts.GetByName then
        local loadout = Loadouts.GetByName(name)
        if loadout then
            LoadDraftFromLoadout(loadout)
            return
        end
    end

    selectedLoadoutName = name
    if loadoutNameBox then loadoutNameBox:SetText(name) end
    UpdateLoadoutMenuButtonLabel()
end

local function AddLoadoutMenuHeader(parent, text, y)
    local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOPLEFT", MENU_PAD, y)
    hdr:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
    hdr:SetText(text)
    table.insert(savedLoadoutMenuRows, hdr)
    return y - MENU_HDR_H
end

local function AddLoadoutMenuItem(parent, text, onClick, y)
    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("TOPLEFT", 2, y)
    row:SetPoint("TOPRIGHT", -2, y)
    row:SetHeight(MENU_ROW_H)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp")

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetTexture(WHITE8x8)
    row.highlight:SetVertexColor(C_HOVER[1], C_HOVER[2], C_HOVER[3], 0.28)
    row.highlight:Hide()

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetPoint("RIGHT", -8, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetText(text)

    local activeName = GetLoadoutMenuLabel()
    local isActive = (text == activeName)
        or (activeName ~= "Load" and text == ("Apply: " .. activeName))
    local defaultColor = isActive and C_GOLD or { 0.78, 0.78, 0.78 }
    row.label:SetTextColor(defaultColor[1], defaultColor[2], defaultColor[3])
    if isActive then row.highlight:Show() end

    local function RestoreRowAppearance(self)
        if isActive then
            self.highlight:Show()
            self.highlight:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.18)
            self.label:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
        else
            self.highlight:Hide()
            self.label:SetTextColor(0.78, 0.78, 0.78)
        end
    end

    WireButtonHover(row, function(self)
        self.highlight:Show()
        self.highlight:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.22)
        self.label:SetTextColor(0.95, 0.95, 0.95)
    end, RestoreRowAppearance)
    row:SetScript("OnClick", function()
        HideLoadoutMenu()
        if onClick then onClick() end
    end)

    table.insert(savedLoadoutMenuRows, row)
    return y - MENU_ROW_H
end

local function ShowLoadoutMenu(anchor)
    if not savedLoadoutMenuPopup or not Loadouts or not anchor then return end
    UpdateLoadoutMenuButtonLabel()
    HideLoadoutMenu()
    ClearLoadoutMenuPopupChildren()

    loadoutMenuContent = CreateFrame("Frame", nil, savedLoadoutMenuPopup)
    loadoutMenuContent:EnableMouse(false)
    loadoutMenuContent:SetPoint("TOPLEFT", MENU_PAD, -MENU_PAD)
    loadoutMenuContent:SetPoint("TOPRIGHT", -MENU_PAD, -MENU_PAD)

    local saved = Loadouts.GetAll()
    local y = 0
    y = AddLoadoutMenuHeader(loadoutMenuContent, "Load into draft...", y)
    if #saved == 0 then
        y = AddLoadoutMenuItem(loadoutMenuContent, "(no saved loadouts)", nil, y)
    else
        for _, loadout in ipairs(saved) do
            local captured = loadout
            y = AddLoadoutMenuItem(loadoutMenuContent, loadout.name or "?", function()
                LoadDraftFromLoadout(captured)
                Journal.Refresh()
            end, y)
        end
        y = y - 4
        y = AddLoadoutMenuHeader(loadoutMenuContent, "Apply at Warpweaver...", y)
        for _, loadout in ipairs(saved) do
            local captured = loadout
            y = AddLoadoutMenuItem(loadoutMenuContent, "Apply: " .. (loadout.name or "?"), function()
                Journal.SetActiveLoadoutName(loadout.name)
                if EbonTransmog.LoadoutApplier then
                    EbonTransmog.LoadoutApplier.Apply(loadout.name)
                end
            end, y)
        end
    end

    local height = math.max(40, -y + MENU_PAD * 2)
    loadoutMenuContent:SetHeight(-y)
    savedLoadoutMenuPopup:SetWidth(168)
    savedLoadoutMenuPopup:SetHeight(height)
    savedLoadoutMenuPopup:ClearAllPoints()
    savedLoadoutMenuPopup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)

    if journalFrame then
        savedLoadoutMenuPopup:SetFrameLevel(journalFrame:GetFrameLevel() + 30)
    end
    if savedLoadoutMenuCatcher then
        savedLoadoutMenuCatcher:SetFrameLevel(savedLoadoutMenuPopup:GetFrameLevel() - 1)
        savedLoadoutMenuCatcher:Show()
    end
    savedLoadoutMenuPopup:Show()
end

local function CreateLoadoutMenu(parent, anchorBtn, journalRoot)
    savedLoadoutMenuBtn = CreateFrame("Button", nil, parent)
    savedLoadoutMenuBtn:SetSize(120, 22)
    savedLoadoutMenuBtn:SetPoint("LEFT", anchorBtn, "RIGHT", 4, 0)
    ApplyBackdrop(savedLoadoutMenuBtn, { 0.02, 0.02, 0.02, 1 }, C_BORDER, 1)

    savedLoadoutMenuBtn.label = savedLoadoutMenuBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    savedLoadoutMenuBtn.label:SetPoint("LEFT", 8, 0)
    savedLoadoutMenuBtn.label:SetPoint("RIGHT", -16, 0)
    savedLoadoutMenuBtn.label:SetJustifyH("LEFT")
    savedLoadoutMenuBtn.label:SetText("Load")

    local arrow = savedLoadoutMenuBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")
    arrow:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])

    savedLoadoutMenuBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.14, 1)
        self:SetBackdropBorderColor(C_GOLD[1] * 0.6, C_GOLD[2] * 0.6, C_GOLD[3] * 0.35, 1)
        self.label:SetTextColor(0.95, 0.95, 0.95)
    end)
    savedLoadoutMenuBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.02, 0.02, 0.02, 1)
        self:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], C_BORDER[4] or 1)
        self.label:SetTextColor(0.78, 0.78, 0.78)
    end)
    savedLoadoutMenuBtn:SetScript("OnClick", function(self)
        if savedLoadoutMenuPopup and savedLoadoutMenuPopup:IsShown() then
            HideLoadoutMenu()
        else
            ShowLoadoutMenu(self)
        end
    end)

    savedLoadoutMenuPopup = CreateFrame("Frame", "EbonTransmogLoadoutMenuPopup", journalRoot)
    savedLoadoutMenuPopup:Hide()
    savedLoadoutMenuPopup:EnableMouse(true)
    ApplyBackdrop(savedLoadoutMenuPopup, C_BG, C_BORDER)

    savedLoadoutMenuCatcher = CreateFrame("Button", nil, journalRoot)
    savedLoadoutMenuCatcher:SetAllPoints(journalRoot)
    savedLoadoutMenuCatcher:Hide()
    savedLoadoutMenuCatcher:EnableMouse(true)
    savedLoadoutMenuCatcher:SetScript("OnClick", HideLoadoutMenu)

    UpdateLoadoutMenuButtonLabel()
end

function Journal.RefreshSavedLoadoutDropdown()
    UpdateLoadoutMenuButtonLabel()
end

function Journal.HideLoadoutMenu()
    HideLoadoutMenu()
end

local function ApplyLoadoutSlotScrollOffset(value)
    if not loadoutSlotScrollFrame or not loadoutSlotScrollChild then return end
    loadoutSlotScrollChild:ClearAllPoints()
    loadoutSlotScrollChild:SetPoint("TOPLEFT", loadoutSlotScrollFrame, "TOPLEFT", 0, value or 0)
    if loadoutSlotScrollFrame.SetVerticalScroll then
        loadoutSlotScrollFrame:SetVerticalScroll(value or 0)
    end
end

local function SetLoadoutSlotScroll(value)
    if not loadoutSlotScrollFrame or not loadoutSlotScrollBar then return end
    local min, max = loadoutSlotScrollBar:GetMinMaxValues()
    value = math.max(min or 0, math.min(max or 0, value or 0))
    loadoutSlotScrollFrame._syncingScroll = true
    loadoutSlotScrollBar:SetValue(value)
    ApplyLoadoutSlotScrollOffset(value)
    loadoutSlotScrollFrame._syncingScroll = nil
end

local function OnLoadoutSlotMouseWheel(_, delta)
    if not loadoutSlotScrollBar or not loadoutSlotScrollBar:IsShown() then return end
    local cur = loadoutSlotScrollBar:GetValue() or 0
    local min, max = loadoutSlotScrollBar:GetMinMaxValues()
    if (max or 0) <= (min or 0) then return end
    local step = 24 * 2
    if delta > 0 then
        SetLoadoutSlotScroll(cur - step)
    else
        SetLoadoutSlotScroll(cur + step)
    end
end

local function WireLoadoutSlotMouseWheel(frame)
    if not frame or frame._loadoutWheelWired then return end
    frame._loadoutWheelWired = true
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", OnLoadoutSlotMouseWheel)
end

local function UpdateLoadoutSlotScrollBar()
    if not loadoutSlotScrollFrame or not loadoutSlotScrollBar then return end
    local w = loadoutSlotScrollFrame:GetWidth()
    if w and w > 1 and loadoutSlotScrollChild then
        loadoutSlotScrollChild:SetWidth(w)
    end
    local frameH = loadoutSlotScrollFrame:GetHeight() or 260
    local childH = loadoutSlotScrollChild and loadoutSlotScrollChild:GetHeight() or frameH
    local maxScroll = math.max(0, childH - frameH)
    if maxScroll > 0.5 then
        loadoutSlotScrollBar:Show()
        if loadoutSlotScrollBar.SetFrameLevel and loadoutSlotScrollFrame.GetFrameLevel then
            loadoutSlotScrollBar:SetFrameLevel((loadoutSlotScrollFrame:GetFrameLevel() or 0) + 10)
        end
        loadoutSlotScrollBar:SetMinMaxValues(0, maxScroll)
        local cur = loadoutSlotScrollBar:GetValue() or 0
        if cur > maxScroll then cur = maxScroll end
        loadoutSlotScrollFrame._syncingScroll = true
        loadoutSlotScrollBar:SetValue(cur)
        ApplyLoadoutSlotScrollOffset(cur)
        loadoutSlotScrollFrame._syncingScroll = nil
    else
        loadoutSlotScrollBar:Hide()
        loadoutSlotScrollBar:SetMinMaxValues(0, 0)
        loadoutSlotScrollFrame._syncingScroll = true
        loadoutSlotScrollBar:SetValue(0)
        ApplyLoadoutSlotScrollOffset(0)
        loadoutSlotScrollFrame._syncingScroll = nil
    end
end

local LOADOUT_ROW_PAD_TOP = 4
local LOADOUT_ROW_PAD_MID = 3
local LOADOUT_ROW_PAD_BOTTOM = 6
local LOADOUT_ROW_GAP = 6

local function GetLoadoutSlotListWidth()
    if loadoutSlotScrollFrame then
        local w = loadoutSlotScrollFrame:GetWidth()
        if w and w > 1 then return w end
    end
    return 160
end

local function MeasureLoadoutRowHeight(row, itemId)
    local listW = math.max(40, GetLoadoutSlotListWidth() - 8)
    local labelH = row.label:GetStringHeight() or 12
    if not itemId then
        return LOADOUT_ROW_PAD_TOP + labelH + LOADOUT_ROW_PAD_BOTTOM
    end
    row.value:SetWordWrap(true)
    row.value:SetWidth(listW)
    local valueH = row.value:GetStringHeight() or 12
    return LOADOUT_ROW_PAD_TOP + labelH + LOADOUT_ROW_PAD_MID + valueH + LOADOUT_ROW_PAD_BOTTOM
end

local function LayoutLoadoutSlotRows()
    local y = 0
    for _, row in ipairs(loadoutSlotRows) do
        if row.slotCategory == browseCategory then
            row:Show()
            local h = row.contentHeight or 24
            row:SetHeight(h)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", loadoutSlotScrollChild, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", loadoutSlotScrollChild, "TOPRIGHT", 0, y)
            y = y - h - LOADOUT_ROW_GAP
        else
            row:Hide()
        end
    end
    if loadoutSlotScrollChild then
        loadoutSlotScrollChild:SetHeight(math.max(10, -y))
    end
    UpdateLoadoutSlotScrollBar()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, UpdateLoadoutSlotScrollBar)
    end
end

function Journal.RefreshLoadoutPanel()
    if not loadoutPanel then return end
    if loadoutPanelTitle then
        loadoutPanelTitle:SetText(browseCategory == "armor" and "Armor Slots" or "Weapon Slots")
    end
    for _, row in ipairs(loadoutSlotRows) do
        if row.slotCategory == browseCategory then
            local itemId = GetEffectiveSlotItem(row.subId)
            if itemId then
                local info = Service.GetItemDisplayInfo(itemId)
                local qc = GetQualityColor(info.quality)
                row.value:Show()
                row.value:SetTextColor(qc[1], qc[2], qc[3])
                row.value:SetText(info.name or ("#" .. itemId))
            else
                row.value:Hide()
                row.value:SetText("—")
            end
            row.contentHeight = MeasureLoadoutRowHeight(row, itemId)
            local selected = row.subId == activeDraftSub
            SetShown(row.highlight, selected)
            if selected then
                row.label:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
            else
                row.label:SetTextColor(0.78, 0.78, 0.78)
            end
        end
    end
    LayoutLoadoutSlotRows()
end

LoadDraftFromLoadout = function(loadout)
    wipe(draftSlots)
    wipe(inspectSlots)
    selectedItemId = nil
    if loadout and loadout.slots then
        for subId, itemId in pairs(loadout.slots) do
            draftSlots[subId] = itemId
        end
        Catalog.NormalizeWeaponSlots(draftSlots)
        Catalog.SanitizeWeaponOutfit(draftSlots)
        Journal.SetActiveLoadoutName(loadout.name or "")
    end
    Journal.RefreshLoadoutPanel()
    RefreshPreview()
end

local function BuildLoadoutPanel(parent)
    loadoutPanel = CreateFrame("Frame", nil, parent)
    loadoutPanel:SetWidth(210)
    ApplyBackdrop(loadoutPanel, { 0.03, 0.03, 0.05, 1 }, C_BORDER)

    local title = loadoutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Armor Slots")
    loadoutPanelTitle = title

    loadoutSlotScrollFrame = CreateFrame("ScrollFrame", "EbonTransmogLoadoutSlotsScrollFrame", loadoutPanel)
    loadoutSlotScrollFrame:SetPoint("TOPLEFT", 4, -24)
    loadoutSlotScrollFrame:SetPoint("BOTTOMRIGHT", -18, 4)

    loadoutSlotScrollChild = CreateFrame("Frame", nil, loadoutSlotScrollFrame)
    do
        local w = loadoutSlotScrollFrame:GetWidth()
        if not w or w < 1 then w = 110 end
        loadoutSlotScrollChild:SetWidth(w)
    end
    loadoutSlotScrollChild:SetHeight(10)
    loadoutSlotScrollChild:SetPoint("TOPLEFT", loadoutSlotScrollFrame, "TOPLEFT", 0, 0)
    loadoutSlotScrollFrame:SetScrollChild(loadoutSlotScrollChild)

    loadoutSlotScrollBar = CreateStyledVerticalScrollBar(loadoutSlotScrollFrame, "EbonTransmogLoadoutSlotsScrollBar")
    loadoutSlotScrollBar:SetPoint("TOPLEFT", loadoutSlotScrollFrame, "TOPRIGHT", 2, -16)
    loadoutSlotScrollBar:SetPoint("BOTTOMLEFT", loadoutSlotScrollFrame, "BOTTOMRIGHT", 2, 16)
    loadoutSlotScrollBar:SetValueStep(24)
    loadoutSlotScrollBar:SetValue(0)
    loadoutSlotScrollBar:Hide()

    loadoutSlotScrollBar:SetScript("OnValueChanged", function(self, value)
        if loadoutSlotScrollFrame._syncingScroll then return end
        value = value or self:GetValue() or 0
        ApplyLoadoutSlotScrollOffset(value)
    end)

    WireLoadoutSlotMouseWheel(loadoutSlotScrollFrame)
    WireLoadoutSlotMouseWheel(loadoutSlotScrollChild)

    local function AddLoadoutRow(sub, category, y)
        local row = CreateFrame("Button", nil, loadoutSlotScrollChild)
        row:SetPoint("TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", 0, y)
        row:SetHeight(24)
        row.subId = sub.id
        row.slotCategory = category
        row.contentHeight = 24
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetTexture(WHITE8x8)
        row.highlight:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.15)
        row.highlight:Hide()

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("TOPLEFT", 4, -LOADOUT_ROW_PAD_TOP)
        row.label:SetPoint("TOPRIGHT", -4, -LOADOUT_ROW_PAD_TOP)
        row.label:SetJustifyH("LEFT")
        row.label:SetText(sub.label)

        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.value:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -LOADOUT_ROW_PAD_MID)
        row.value:SetJustifyH("LEFT")
        row.value:SetWordWrap(true)
        row.value:SetNonSpaceWrap(false)
        row.value:SetText("—")

        local function RestoreSlotRowAppearance(self)
            local selected = self.subId == activeDraftSub
            if selected then
                self.highlight:Show()
                self.highlight:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.15)
                self.label:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
            else
                self.highlight:Hide()
                self.label:SetTextColor(0.78, 0.78, 0.78)
            end
        end

        WireButtonHover(row, function(self)
            self.highlight:Show()
            self.highlight:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.22)
            self.label:SetTextColor(0.95, 0.95, 0.95)
        end, RestoreSlotRowAppearance)

        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                ClearLoadoutSlot(self.subId)
                return
            end
            SelectActiveSub(self.subId)
            local slotItemId = GetEffectiveSlotItem(self.subId)
            if slotItemId then
                Journal.RefreshLoadoutPanel()
                Journal.Refresh()
                SelectItem(slotItemId)
                ScrollGridToItem(slotItemId)
            else
                ResetGridScroll()
                Journal.RefreshLoadoutPanel()
                Journal.Refresh()
                SelectItem(nil)
            end
        end)

        WireLoadoutSlotMouseWheel(row)

        table.insert(loadoutSlotRows, row)
        return y - 24
    end

    local y = 0
    for _, sub in ipairs(Catalog.GetSubcategories("armor")) do
        y = AddLoadoutRow(sub, "armor", y)
    end
    for _, slot in ipairs(Catalog.GetWeaponLoadoutSlots()) do
        y = AddLoadoutRow(slot, "weapons", y)
    end
    loadoutSlotScrollChild:SetHeight(math.max(10, -y))

    loadoutSlotScrollFrame:SetScript("OnSizeChanged", UpdateLoadoutSlotScrollBar)
    loadoutSlotScrollFrame:SetScript("OnShow", function()
        UpdateLoadoutSlotScrollBar()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, UpdateLoadoutSlotScrollBar)
        end
    end)
    LayoutLoadoutSlotRows()
end

function Journal.Refresh()
    if not journalFrame then return end
    PurgeInvalidWeaponSlots()
    if searchPlaceholder then
        searchPlaceholder:SetText("Filter slot items...")
    end
    Journal.RefreshCategoryFilters()
    Journal.RefreshWeaponGroupFilters()
    RefreshSubTabs()
    Journal.SyncFilterLayout()
    Journal.RefreshRarityFilters()
    Journal.RefreshArmorTypeFilters()
    if scrollFrame and loadoutPanel then
        loadoutPanel:ClearAllPoints()
        loadoutPanel:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", -4, -8)
        loadoutPanel:SetPoint("BOTTOMLEFT", journalFrame, "BOTTOMLEFT", 12, 12)
        scrollFrame:SetPoint("TOPLEFT", loadoutPanel, "TOPRIGHT", 8, 0)
        scrollFrame:SetPoint("BOTTOMRIGHT", journalFrame, "BOTTOMRIGHT", -(PREVIEW_WIDTH + 24), 12)
    end
    BuildGrid()
    Journal.RefreshLoadoutPanel()
    Journal.RefreshSavedLoadoutDropdown()
end

function Journal.RefreshRarityFilters()
    for i, opt in ipairs(RARITY_OPTIONS) do
        local btn = rarityFilterButtons[i]
        if not btn then break end
        local active = rarityFilter[opt.quality] == true
        local qc = GetQualityColor(opt.quality)
        if active then
            btn:SetBackdropColor(qc[1] * 0.22, qc[2] * 0.22, qc[3] * 0.22, 1)
            btn:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
            btn.label:SetTextColor(qc[1], qc[2], qc[3])
        else
            btn:SetBackdropColor(0.07, 0.07, 0.09, 1)
            btn:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
            btn.label:SetTextColor(qc[1] * 0.55, qc[2] * 0.55, qc[3] * 0.55)
        end
    end
end

function Journal.RefreshArmorTypeFilters()
    local options = Service.ARMOR_TYPE_OPTIONS or {}
    local enabled = ArmorTypeFiltersEnabled()
    for i, opt in ipairs(options) do
        local btn = armorFilterButtons[i]
        if not btn then break end
        if enabled then
            btn:EnableMouse(true)
            btn:SetAlpha(1)
            SetTabSelected(btn, armorTypeFilter[opt.subclass] == true)
        else
            btn:EnableMouse(false)
            btn:SetAlpha(0.5)
            btn:SetBackdropColor(0.06, 0.06, 0.08, 1)
            btn:SetBackdropBorderColor(0.14, 0.14, 0.16, 1)
            btn.label:SetTextColor(0.38, 0.38, 0.38)
        end
    end
end

function Journal.SyncFilterLayout()
    if not countLabel then return end
    local anchor = loadoutHintLabel or loadoutToolbar
    if not anchor then return end

    if categoryFilterBar then
        categoryFilterBar:ClearAllPoints()
        categoryFilterBar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        categoryFilterBar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
        anchor = categoryFilterBar
    end

    if weaponGroupFilterBar then
        SetShown(weaponGroupFilterBar, ShouldShowWeaponGroupFilters())
        weaponGroupFilterBar:ClearAllPoints()
        if ShouldShowWeaponGroupFilters() then
            weaponGroupFilterBar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
            weaponGroupFilterBar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
            anchor = weaponGroupFilterBar
        end
    end

    if subTabBar then
        subTabBar:ClearAllPoints()
        subTabBar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        subTabBar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
        anchor = subTabBar
    end

    if searchBox then
        searchBox:ClearAllPoints()
        searchBox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        searchBox:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -8)
        anchor = searchBox
    end

    if rarityFilterBar then
        rarityFilterBar:ClearAllPoints()
        rarityFilterBar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        rarityFilterBar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
        anchor = rarityFilterBar
    end

    if armorFilterBar then
        if ShouldShowArmorTypeFilterBar() then
            SetShown(armorFilterBar, true)
            armorFilterBar:ClearAllPoints()
            armorFilterBar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
            armorFilterBar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
            anchor = armorFilterBar
        else
            SetShown(armorFilterBar, false)
        end
    end

    countLabel:ClearAllPoints()
    countLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -4)
end

local function CreateCategoryFilterBar(parent)
    local options = {
        { category = "armor", label = "Armor" },
        { category = "weapons", label = "Weapons" },
    }
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(24)

    local function LayoutButtons()
        local barWidth = bar:GetWidth() or 400
        local gap = 6
        local btnW = math.floor((barWidth - gap * (#options - 1)) / #options)
        for i, opt in ipairs(options) do
            local btn = categoryFilterButtons[i]
            if btn then
                btn:SetWidth(btnW)
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", bar, "LEFT", (i - 1) * (btnW + gap), 0)
            end
        end
    end

    bar:SetScript("OnSizeChanged", LayoutButtons)

    for i, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, bar)
        btn:SetHeight(22)
        ApplyBackdrop(btn, { 0.08, 0.08, 0.1, 1 }, C_BORDER, 1)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(opt.label)
        btn.category = opt.category
        btn:SetScript("OnClick", function(self)
            browseCategory = self.category
            if browseCategory == "armor" then
                if Catalog.GetCategoryForSub(activeDraftSub) ~= "armor" then
                    activeDraftSub = "head"
                end
            else
                if Catalog.GetCategoryForSub(activeDraftSub) ~= "weapons" then
                    weaponGroup = "one_handed"
                    local subs = Catalog.GetWeaponSubsForGroup(weaponGroup)
                    activeDraftSub = subs[1] and subs[1].id or "one_handed_swords"
                end
                EnsureValidActiveSub()
            end
            selectedItemId = nil
            ResetGridScroll()
            Journal.Refresh()
        end)
        WireFilterTabHover(btn, function()
            Journal.RefreshCategoryFilters()
        end)
        categoryFilterButtons[i] = btn
    end

    LayoutButtons()
    return bar
end

local function CreateWeaponGroupFilterBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(24)
    weaponGroupFilterBar = bar

    bar:SetScript("OnSizeChanged", function()
        Journal.RefreshWeaponGroupFilters()
    end)

    for i, groupId in ipairs(Catalog.GetWeaponGroupOrder()) do
        local group = Catalog.WEAPON_GROUPS[groupId]
        local btn = CreateFrame("Button", nil, bar)
        btn:SetHeight(22)
        ApplyBackdrop(btn, { 0.08, 0.08, 0.1, 1 }, C_BORDER, 1)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(group and group.label or groupId)
        btn.groupId = groupId
        btn:SetScript("OnClick", function(self)
            weaponGroup = self.groupId
            EnsureValidActiveSub()
            selectedItemId = nil
            ResetGridScroll()
            Journal.Refresh()
        end)
        WireFilterTabHover(btn, function()
            Journal.RefreshWeaponGroupFilters()
        end)
        weaponGroupFilterButtons[i] = btn
    end

    bar:Hide()
    return bar
end

local function CreateRarityFilterBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(20)

    local function LayoutButtons()
        local barWidth = bar:GetWidth() or 400
        local gap = 3
        local btnW = math.floor((barWidth - gap * (#RARITY_OPTIONS - 1)) / #RARITY_OPTIONS)
        for i, opt in ipairs(RARITY_OPTIONS) do
            local btn = rarityFilterButtons[i]
            if btn then
                btn:SetWidth(btnW)
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", bar, "LEFT", (i - 1) * (btnW + gap), 0)
            end
        end
    end

    bar:SetScript("OnSizeChanged", LayoutButtons)

    for i, opt in ipairs(RARITY_OPTIONS) do
        local btn = CreateFrame("Button", nil, bar)
        btn:SetHeight(18)
        ApplyBackdrop(btn, { 0.07, 0.07, 0.09, 1 }, C_BORDER, 1)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(opt.label)
        btn.quality = opt.quality
        btn:SetScript("OnClick", function()
            if rarityFilter[opt.quality] then
                rarityFilter[opt.quality] = nil
            else
                rarityFilter[opt.quality] = true
            end
            Journal.RefreshRarityFilters()
            Journal.Refresh()
        end)
        WireRarityFilterHover(btn, function()
            Journal.RefreshRarityFilters()
        end)
        rarityFilterButtons[i] = btn
    end

    LayoutButtons()
    return bar
end

local function CreateArmorTypeFilterBar(parent)
    local options = Service.ARMOR_TYPE_OPTIONS or {}
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(20)

    local function LayoutButtons()
        local barWidth = bar:GetWidth() or 400
        local gap = 3
        local btnW = math.floor((barWidth - gap * (#options - 1)) / math.max(1, #options))
        for i, opt in ipairs(options) do
            local btn = armorFilterButtons[i]
            if btn then
                btn:SetWidth(btnW)
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", bar, "LEFT", (i - 1) * (btnW + gap), 0)
            end
        end
    end

    bar:SetScript("OnSizeChanged", LayoutButtons)

    for i, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, bar)
        btn:SetHeight(18)
        ApplyBackdrop(btn, { 0.07, 0.07, 0.09, 1 }, C_BORDER, 1)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(opt.label)
        btn.subclass = opt.subclass
        btn:SetScript("OnClick", function()
            if not ArmorTypeFiltersEnabled() then return end
            if armorTypeFilter[opt.subclass] then
                armorTypeFilter[opt.subclass] = nil
            else
                armorTypeFilter[opt.subclass] = true
            end
            Journal.RefreshArmorTypeFilters()
            ResetGridScroll()
            Journal.Refresh()
        end)
        WireFilterTabHover(btn, function()
            Journal.RefreshArmorTypeFilters()
        end)
        armorFilterButtons[i] = btn
    end

    LayoutButtons()
    return bar
end

local function CreateSearchBox(parent)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlight)
    box:SetHeight(22)
    box:SetTextInsets(8, 8, 0, 0)
    ApplyBackdrop(box, { 0.02, 0.02, 0.02, 1 }, C_BORDER)

    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        currentSearch = self:GetText() or ""
        Journal.Refresh()
    end)

    local placeholder = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    placeholder:SetPoint("LEFT", box, "LEFT", 8, 0)
    placeholder:SetText("Search by name...")
    placeholder:SetTextColor(0.45, 0.45, 0.45)
    box.placeholder = placeholder
    searchPlaceholder = placeholder
    box:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    box:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self.placeholder:Show() end
    end)
    return box
end

local function CreateLoadoutToolbar(parent)
    StaticPopupDialogs["EBONTRANSMOG_DELETE_LOADOUT"] = {
        text = "Delete loadout \"%s\"?",
        button1 = "Delete",
        button2 = "Cancel",
        OnAccept = function(self)
            local name = self.data
            if not name or name == "" then return end
            if Loadouts.Delete(name) then
                wipe(draftSlots)
                wipe(inspectSlots)
                selectedItemId = nil
                if loadoutNameBox then loadoutNameBox:SetText("") end
                selectedLoadoutName = nil
                EbonTransmogDB = EbonTransmogDB or {}
                if EbonTransmogDB.lastLoadoutName == name then
                    EbonTransmogDB.lastLoadoutName = nil
                end
                Journal.RefreshLoadoutPanel()
                Journal.RefreshSavedLoadoutDropdown()
                RefreshPreview()
                Journal.Refresh()
                DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[EbonTransmog]|r Deleted loadout: " .. name)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -36)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(PREVIEW_WIDTH + 24), -36)
    bar:SetHeight(36)
    ApplyBackdrop(bar, { 0.03, 0.03, 0.05, 1 }, C_BORDER)

    loadoutNameBox = CreateFrame("EditBox", nil, bar)
    loadoutNameBox:SetAutoFocus(false)
    loadoutNameBox:SetFontObject(GameFontHighlight)
    loadoutNameBox:SetPoint("TOPLEFT", 8, -8)
    loadoutNameBox:SetSize(140, 20)
    loadoutNameBox:SetTextInsets(6, 6, 0, 0)
    ApplyBackdrop(loadoutNameBox, { 0.02, 0.02, 0.02, 1 }, C_BORDER)
    loadoutNameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local function MakeBtn(text, x, onClick)
        local btn = CreateFrame("Button", nil, bar)
        btn:SetSize(72, 22)
        btn:SetPoint("TOPLEFT", x, -8)
        ApplyBackdrop(btn, { 0.08, 0.08, 0.1, 1 }, C_BORDER, 1)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(text)
        btn.label:SetTextColor(0.78, 0.78, 0.78)
        WireToolbarButtonHover(btn)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    MakeBtn("Save", 156, function()
        CommitInspectToDraft()
        Catalog.NormalizeWeaponSlots(draftSlots)
        local ok, err = Loadouts.Save(loadoutNameBox:GetText(), draftSlots)
        if ok then
            Journal.SetActiveLoadoutName(loadoutNameBox:GetText())
            DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[EbonTransmog]|r Loadout saved: " .. selectedLoadoutName)
            Journal.RefreshSavedLoadoutDropdown()
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[EbonTransmog]|r " .. (err or "Save failed"))
        end
    end)

    MakeBtn("New", 234, function()
        wipe(draftSlots)
        wipe(inspectSlots)
        selectedItemId = nil
        loadoutNameBox:SetText("")
        selectedLoadoutName = nil
        Journal.RefreshLoadoutPanel()
        Journal.RefreshSavedLoadoutDropdown()
        RefreshPreview()
        Journal.Refresh()
    end)

    MakeBtn("Apply", 312, function()
        CommitInspectToDraft()
        local name = loadoutNameBox:GetText()
        if name and name ~= "" then
            Journal.SetActiveLoadoutName(name)
        end
        Applier.Apply(name, draftSlots)
    end)

    local deleteBtn = MakeBtn("Delete", 390, function()
        local name = loadoutNameBox:GetText()
        if not name or name == "" then return end
        StaticPopup_Show("EBONTRANSMOG_DELETE_LOADOUT", name, nil, name)
    end)

    CreateLoadoutMenu(bar, deleteBtn, parent)

    return bar
end

local loadoutToolbar

local function EnsureFrame()
    if journalFrame then return journalFrame end

    journalFrame = CreateFrame("Frame", "EbonTransmogJournalFrame", UIParent)
    journalFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    journalFrame:SetPoint("CENTER")
    -- DragonUI Combuctor bags use HIGH + topLevel. Match HIGH (above action bars) but
    -- leave topLevel off and re-raise bag panels when they open so inventory stays on top.
    journalFrame:SetFrameStrata(JOURNAL_FRAME_STRATA)
    journalFrame:SetFrameLevel(JOURNAL_FRAME_LEVEL)
    InstallBagPanelHook()
    journalFrame:EnableMouse(true)
    journalFrame:SetMovable(true)
    journalFrame:RegisterForDrag("LeftButton")
    journalFrame:SetScript("OnDragStart", journalFrame.StartMoving)
    journalFrame:SetScript("OnDragStop", journalFrame.StopMovingOrSizing)
    ApplyBackdrop(journalFrame, C_BG, C_BORDER)
    journalFrame:Hide()
    tinsert(UISpecialFrames, journalFrame:GetName())

    local title = journalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
    title:SetText("Transmog Journal")

    local closeBtn = CreateStyledCloseButton(journalFrame, function() Journal.Hide() end)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)

    loadoutToolbar = CreateLoadoutToolbar(journalFrame)
    Journal.RestoreActiveLoadoutFromDB()

    loadoutHintLabel = journalFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    loadoutHintLabel:SetPoint("TOPLEFT", loadoutToolbar, "BOTTOMLEFT", 0, -6)
    loadoutHintLabel:SetPoint("TOPRIGHT", loadoutToolbar, "BOTTOMRIGHT", 0, -6)
    loadoutHintLabel:SetJustifyH("LEFT")
    loadoutHintLabel:SetText("Apply closes this window and queues the loadout — then talk to the Warpweaver.")

    categoryFilterBar = CreateCategoryFilterBar(journalFrame)
    weaponGroupFilterBar = CreateWeaponGroupFilterBar(journalFrame)

    subTabBar = CreateFrame("Frame", nil, journalFrame)
    subTabBar:SetHeight(50)

    searchBox = CreateSearchBox(journalFrame)

    rarityFilterBar = CreateRarityFilterBar(journalFrame)

    armorFilterBar = CreateArmorTypeFilterBar(journalFrame)

    countLabel = journalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countLabel:SetTextColor(0.65, 0.65, 0.65)

    BuildLoadoutPanel(journalFrame)

    local previewPanel = CreateFrame("Frame", nil, journalFrame)
    previewPanel:SetPoint("TOPRIGHT", -12, -40)
    previewPanel:SetPoint("BOTTOMRIGHT", -12, 12)
    previewPanel:SetWidth(PREVIEW_WIDTH)
    ApplyBackdrop(previewPanel, { 0.03, 0.03, 0.05, 1 }, C_BORDER)

    previewName = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewName:SetPoint("TOP", previewPanel, "TOP", 0, -10)
    previewName:SetWidth(PREVIEW_WIDTH - 16)
    previewName:SetWordWrap(true)
    previewName:SetText("Select an appearance")
    previewName:SetTextColor(0.6, 0.6, 0.6)

    previewHolder = Preview.Attach(previewPanel, PREVIEW_WIDTH - 20, FRAME_HEIGHT - 160)
    previewHolder:SetPoint("TOP", previewPanel, "TOP", 0, -44)

    local hint = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", previewPanel, "BOTTOM", 0, 8)
    hint:SetWidth(PREVIEW_WIDTH - 12)
    hint:SetWordWrap(true)
    hint:SetText("Drag to rotate · Wheel to zoom · Alt+click off-hand · Right-click remove")

    scrollFrame = CreateFrame("ScrollFrame", nil, journalFrame)
    scrollFrame:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", -4, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", previewPanel, "BOTTOMLEFT", -12, 0)
    scrollFrame:EnableMouseWheel(true)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth() or 400)
    scrollChild:SetHeight(400)
    scrollFrame:SetScrollChild(scrollChild)

    scrollBar = CreateStyledVerticalScrollBar(scrollFrame, "EbonTransmogJournalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", -(SCROLLBAR_W - 2), -18)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", -(SCROLLBAR_W - 2), 18)
    scrollBar:SetValueStep(ICON_SIZE + ICON_PAD)
    scrollBar:SetValue(0)
    scrollBar:Hide()

    scrollBar:SetScript("OnValueChanged", function(self, value)
        if scrollFrame._syncingScroll then return end
        value = value or self:GetValue() or 0
        scrollFrame:SetVerticalScroll(value)
    end)

    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        ScrollGridBy(delta)
    end)

    scrollFrame:SetScript("OnSizeChanged", function()
        Journal.UpdateGridScrollRange()
    end)

    journalFrame:SetScript("OnShow", function()
        Service.RequestSync()
        Service.WarmAllCachedItems()
        Journal.Refresh()
        RefreshPreview()
    end)

    Journal.RefreshCategoryFilters()
    Journal.RefreshWeaponGroupFilters()
    RefreshSubTabs()
    Journal.SyncFilterLayout()
    Journal.RefreshRarityFilters()
    Journal.RefreshArmorTypeFilters()
    return journalFrame
end

function Journal.Init()
    EnsureFrame()
    Journal.InstallMicroButton()
end

function Journal.Show()
    EnsureFrame()
    Journal.RestoreActiveLoadoutFromDB()
    UpdateLoadoutMenuButtonLabel()
    journalFrame:Show()
    RaiseFrame(journalFrame)
    PromoteOpenBagFramesAboveJournal()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, PromoteOpenBagFramesAboveJournal)
    end
    if UpdateMicroButtons then UpdateMicroButtons() end
end

function Journal.Hide()
    HideLoadoutMenu()
    if journalFrame then journalFrame:Hide() end
    if UpdateMicroButtons then UpdateMicroButtons() end
end

function Journal.Toggle()
    EnsureFrame()
    if journalFrame:IsShown() then Journal.Hide() else Journal.Show() end
end

function Journal.OnDataChanged()
    if journalFrame and journalFrame:IsShown() then Journal.Refresh() end
end

local function SetMicroPressedVisual(pressed)
    if not microButton then return end
    microButton:SetButtonState(pressed and "PUSHED" or "NORMAL", pressed and 1 or 0)
end

function Journal.InstallMicroButton()
    if microButton then return end
    microButton = CreateFrame("Button", "TransmogJournalMicroButton", MainMenuBarArtFrame, "MainMenuBarMicroButton")
    LoadMicroButtonTextures(microButton, "Spellbook")
    microButton:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight")
    microButton.tooltipText = "Transmog Journal"
    microButton.newbieText = "Browse collected appearances, build loadouts, and preview gear."
    microButton:SetScript("OnClick", function()
        Journal.Toggle()
        SetMicroPressedVisual(journalFrame and journalFrame:IsShown())
    end)
    microButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, 1, 1, 1)
        GameTooltip:AddLine(self.newbieText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    microButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function PositionMicroButton()
        if not microButton then return end
        local anchor = _G.EchoJournalMicroButton or _G.SkillTreeMicroButton or _G.MainMenuMicroButton
        if anchor and anchor:IsShown() then
            microButton:ClearAllPoints()
            microButton:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
            microButton:Show()
        else microButton:Hide() end
    end

    if hooksecurefunc then
        hooksecurefunc("UpdateMicroButtons", function()
            PositionMicroButton()
            SetMicroPressedVisual(journalFrame and journalFrame:IsShown())
        end)
    end
    PositionMicroButton()
end
