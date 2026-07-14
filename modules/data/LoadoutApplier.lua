-- EbonTransmog: apply saved loadouts at the Warpweaver via gossip automation.

EbonTransmog = EbonTransmog or {}
local Applier = {}
EbonTransmog.LoadoutApplier = Applier

local Loadouts = EbonTransmog.LoadoutService
local Catalog = EbonTransmog.SlotCatalog

local SCAN_DELAY = 0.25
local MAX_STALL_STEPS = 80
local NAV_NEXT_PAGE = "Next page"
local NAV_PREVIOUS_PAGE = "Previous page"
local NAV_MAIN_MENU = "Show main menu"

local SLOT_LABELS = {
    "Head", "Shoulders", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrists", "Hands",
    "Back", "Main hand", "Off hand", "Ranged", "Tabard",
}

local applyActive = false
local applyDelayFrame = nil
local applyState = nil
local pendingApply = nil

local SelectOption

local function PrintMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[EbonTransmog]|r " .. msg)
end

local function StripGossipText(text)
    if not text then return "" end
    text = text:gsub("|T[^|]*|t", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H[^|]*|h", ""):gsub("|h", "")
    return text
end

local function PlainSlotLabel(plain)
    local label = plain:match("^(.-) %[transmog%]") or plain
    return label:gsub("^%s+", ""):gsub("%s+$", "")
end

local function IsKnownSlotLabel(plain)
    if plain:find("[pending]", 1, true) then return false end
    local label = PlainSlotLabel(plain)
    for _, slot in ipairs(SLOT_LABELS) do
        if label == slot then return true end
    end
    return false
end

local function GetGossipOptionList()
    local opts = {}
    if type(GetGossipOptions) ~= "function" then return opts end
    local data = { GetGossipOptions() }
    for i = 1, #data, 2 do
        table.insert(opts, {
            index = (#opts + 1),
            name = data[i] or "",
        })
    end
    return opts
end

local function FindOptionExact(opts, text)
    for _, opt in ipairs(opts) do
        if StripGossipText(opt.name) == text then return opt.index end
    end
    return nil
end

local function FindMainMenuIndex(opts)
    return FindOptionExact(opts, NAV_MAIN_MENU)
        or FindOptionExact(opts, "< Back")
        or FindOptionExact(opts, "Back")
end

local function FindPageInfo(opts)
    for _, opt in ipairs(opts) do
        local plain = StripGossipText(opt.name)
        local slot, cur, max = plain:match("^(.-) %- Page (%d+)/(%d+)$")
        if cur and max then
            return {
                slot = slot:gsub("^%s+", ""):gsub("%s+$", ""),
                current = tonumber(cur),
                max = tonumber(max),
            }
        end
    end
    return nil
end

local function IsTransmogGossip(opts)
    if FindPageInfo(opts) then return true end
    if FindOptionExact(opts, NAV_NEXT_PAGE) or FindOptionExact(opts, NAV_PREVIOUS_PAGE)
        or FindMainMenuIndex(opts) then
        return true
    end
    for _, opt in ipairs(opts) do
        local plain = StripGossipText(opt.name)
        if plain:find("[transmog]", 1, true) then return true end
        if plain:find("transmogr", 1, true) or plain:find("Save pending", 1, true) then
            return true
        end
        if IsKnownSlotLabel(plain) then return true end
    end
    return false
end

local function IsSlotRoot(opts)
    local count = 0
    for _, opt in ipairs(opts) do
        if IsKnownSlotLabel(StripGossipText(opt.name)) then
            count = count + 1
        end
    end
    return count >= 3
end

local function FindSlotIndex(opts, gossipLabel)
    if not gossipLabel then return nil end
    for _, opt in ipairs(opts) do
        local plain = PlainSlotLabel(StripGossipText(opt.name))
        if plain == gossipLabel then
            return opt.index
        end
    end
    return nil
end

local function FindTransmogEntryIndex(opts)
    for _, opt in ipairs(opts) do
        local plain = StripGossipText(opt.name)
        if plain:find("transmogr", 1, true) and not plain:find("Save pending", 1, true) then
            return opt.index
        end
    end
    return nil
end

local function FindSaveIndex(opts)
    for _, opt in ipairs(opts) do
        local plain = StripGossipText(opt.name)
        if plain:find("Save pending", 1, true) then
            return opt.index
        end
    end
    return nil
end

local function OptionMatchesItem(optName, itemId)
    if optName:find("item:" .. itemId, 1, true) then return true end
    local itemName = GetItemInfo(itemId)
    if not itemName then return false end
    local plain = StripGossipText(optName)
    if plain:find("%[" .. itemName:gsub("([%%%[%]%-%.%+%*%?%^%$])", "%%%1") .. "%]") then
        return true
    end
    return false
end

local function FindItemOption(opts, itemId)
    for _, opt in ipairs(opts) do
        if OptionMatchesItem(opt.name, itemId) then
            return opt.index, opt.name
        end
    end
    return nil
end

local function SlotOptionShowsItem(opts, gossipLabel, itemId)
    if not gossipLabel or not itemId then return false end
    for _, opt in ipairs(opts) do
        local plain = PlainSlotLabel(StripGossipText(opt.name))
        if plain == gossipLabel and OptionMatchesItem(opt.name, itemId) then
            return true
        end
    end
    return false
end

local function CompleteCurrentSlot(wasSkipped, reason)
    if wasSkipped then
        applyState.skipped = (applyState.skipped or 0) + 1
        if reason then
            PrintMsg("|cffff8800Skipped|r — " .. reason)
        end
    end
    applyState.ptr = (applyState.ptr or 1) + 1
    applyState.phase = "slots"
    applyState.slotAttempts = 0
    applyState.stallSteps = 0
    applyState.targetItemId = nil
    applyState.currentLabel = nil
end

local function CancelDelay()
    if applyDelayFrame then
        applyDelayFrame:SetScript("OnUpdate", nil)
        applyDelayFrame:Hide()
    end
end

local function ScheduleStep(fn)
    CancelDelay()
    if not applyDelayFrame then
        applyDelayFrame = CreateFrame("Frame")
        applyDelayFrame:Hide()
    end
    local elapsed = 0
    applyDelayFrame:Show()
    applyDelayFrame:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed >= SCAN_DELAY then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            fn()
        end
    end)
end

SelectOption = function(index)
    if index and SelectGossipOption then
        SelectGossipOption(index)
        return true
    end
    return false
end

local function BeginReturnToSlotMenu(opts, pageInfo)
    if pageInfo and pageInfo.current > 1 then
        local prevIdx = FindOptionExact(opts, NAV_PREVIOUS_PAGE)
        if prevIdx then
            applyState.phase = "return_to_menu"
            applyState.waitingForGossip = true
            SelectOption(prevIdx)
            return true
        end
    end
    local menuIdx = FindMainMenuIndex(opts)
    if menuIdx then
        applyState.phase = "return_to_menu"
        applyState.waitingForGossip = true
        SelectOption(menuIdx)
        return true
    end
    return false
end

local function BuildQueueFromLoadout(loadout)
    if loadout and loadout.slots then
        local entries = Loadouts.GetSlotEntries(loadout)
        local filtered = {}
        for _, entry in ipairs(entries) do
            if Catalog.PlayerCanUseWeaponItem(entry.itemId) then
                table.insert(filtered, entry)
            end
        end
        return filtered
    end
    return {}
end

local function BuildQueueFromDraft(slots)
    local entries = {}
    for subId, itemId in pairs(slots or {}) do
        itemId = tonumber(itemId)
        if itemId and itemId > 0 and Catalog.PlayerCanUseWeaponItem(itemId) then
            table.insert(entries, {
                subId = subId,
                gossip = Catalog.GetGossipForSub(subId, itemId),
                itemId = itemId,
                label = Catalog.GetGossipLabelForSub(subId) or subId,
            })
        end
    end
    table.sort(entries, function(a, b) return a.label < b.label end)
    return entries
end

local function ClearPending()
    pendingApply = nil
end

local function FinishApply(message, ok)
    local appliedName = applyState and applyState.loadoutName
    applyActive = false
    applyState = nil
    pendingApply = nil
    CancelDelay()
    if message then
        if ok then PrintMsg(message) else PrintMsg("|cffff4444" .. message .. "|r") end
    end
    if ok and appliedName and EbonTransmog.TransmogJournal then
        if EbonTransmog.TransmogJournal.SetActiveLoadoutName then
            EbonTransmog.TransmogJournal.SetActiveLoadoutName(appliedName)
        end
    end
end

local function ReportProgress(entry, index, total)
    if not entry then return end
    PrintMsg(string.format(
        "Applying |cffffff00%d/%d|r — %s",
        index,
        total,
        entry.label or entry.gossip or "?"
    ))
end

local ProcessApplyStep

local function StartApplyRun(displayName, queue)
    applyActive = true
    applyState = {
        phase = "prepare",
        loadoutName = displayName,
        queue = queue,
        ptr = 1,
        waitingForGossip = false,
        stallSteps = 0,
        skipped = 0,
        slotAttempts = 0,
    }
    PrintMsg("Applying |cffffff00" .. displayName .. "|r — keep the Warpweaver window open.")
    ScheduleStep(ProcessApplyStep)
end

ProcessApplyStep = function()
    if not applyActive or not GossipFrame or not GossipFrame:IsVisible() then
        FinishApply("Apply stopped — gossip window closed.", false)
        return
    end
    if applyState.waitingForGossip then return end

    applyState.stallSteps = (applyState.stallSteps or 0) + 1
    if applyState.stallSteps > MAX_STALL_STEPS then
        FinishApply("Apply stalled — could not navigate Warpweaver gossip. Stand at the slot menu and try again.", false)
        return
    end

    local opts = GetGossipOptionList()
    if #opts == 0 then
        FinishApply("Apply stopped — no gossip options.", false)
        return
    end

    if not IsTransmogGossip(opts) then
        FinishApply("This gossip is not the Warpweaver transmogrifier.", false)
        return
    end

    local pageInfo = FindPageInfo(opts)

    if applyState.phase == "prepare" then
        if pageInfo then
            applyState.phase = "return_to_menu"
            applyState.prepareReturn = true
            ScheduleStep(ProcessApplyStep)
            return
        end
        if IsSlotRoot(opts) then
            applyState.phase = "slots"
            ScheduleStep(ProcessApplyStep)
            return
        end
        local entryIdx = FindTransmogEntryIndex(opts)
        if entryIdx then
            applyState.waitingForGossip = true
            SelectOption(entryIdx)
            return
        end
        FinishApply("Open the Warpweaver slot menu, then click Apply again.", false)
        return
    end

    if applyState.phase == "return_to_menu" then
        if pageInfo then
            if pageInfo.current > 1 then
                local prevIdx = FindOptionExact(opts, NAV_PREVIOUS_PAGE)
                if prevIdx then
                    applyState.waitingForGossip = true
                    SelectOption(prevIdx)
                    return
                end
            end
            local menuIdx = FindMainMenuIndex(opts)
            if menuIdx then
                applyState.waitingForGossip = true
                SelectOption(menuIdx)
                return
            end
        end
        if IsSlotRoot(opts) then
            if applyState.prepareReturn then
                applyState.prepareReturn = nil
                applyState.phase = "slots"
                ScheduleStep(ProcessApplyStep)
                return
            end
            if applyState.markSkip then
                CompleteCurrentSlot(true, applyState.markSkip)
                applyState.markSkip = nil
            else
                CompleteCurrentSlot(false)
            end
            ScheduleStep(ProcessApplyStep)
            return
        end
        ScheduleStep(ProcessApplyStep)
        return
    end

    if applyState.phase == "find_item" then
        local entry = applyState.queue[applyState.ptr]
        if not pageInfo then
            if IsSlotRoot(opts) and entry then
                if SlotOptionShowsItem(opts, entry.gossip, applyState.targetItemId) then
                    CompleteCurrentSlot(false)
                    ScheduleStep(ProcessApplyStep)
                    return
                end
                applyState.slotAttempts = (applyState.slotAttempts or 0) + 1
                if applyState.slotAttempts >= 3 then
                    CompleteCurrentSlot(true, (entry.label or entry.gossip or "?") .. " — could not open appearance list")
                    ScheduleStep(ProcessApplyStep)
                    return
                end
            end
            ScheduleStep(ProcessApplyStep)
            return
        end

        local idx = FindItemOption(opts, applyState.targetItemId)
        if idx then
            applyState.waitingForGossip = true
            SelectOption(idx)
            applyState.phase = "return_from_item"
            return
        end
        if pageInfo.current < pageInfo.max then
            local nextIdx = FindOptionExact(opts, NAV_NEXT_PAGE)
            if nextIdx then
                applyState.waitingForGossip = true
                SelectOption(nextIdx)
                return
            end
        end
        applyState.markSkip = "item not found in gossip: " .. (applyState.currentLabel or "?")
        if BeginReturnToSlotMenu(opts, pageInfo) then
            return
        end
        CompleteCurrentSlot(true, applyState.markSkip)
        applyState.markSkip = nil
        ScheduleStep(ProcessApplyStep)
        return
    end

    if applyState.phase == "return_from_item" then
        if IsSlotRoot(opts) then
            CompleteCurrentSlot(false)
            ScheduleStep(ProcessApplyStep)
            return
        end
        if BeginReturnToSlotMenu(opts, pageInfo) then
            return
        end
        CompleteCurrentSlot(false)
        ScheduleStep(ProcessApplyStep)
        return
    end

    if applyState.phase == "save" then
        local saveIdx = FindSaveIndex(opts)
        if saveIdx then
            applyState.waitingForGossip = true
            SelectOption(saveIdx)
            local skipped = applyState.skipped or 0
            local suffix = skipped > 0 and (" (" .. skipped .. " slot(s) skipped)") or ""
            FinishApply("Loadout '" .. applyState.loadoutName .. "' applied and saved." .. suffix, true)
        else
            FinishApply("Applied slots but could not find 'Save pending transmogrifications'. Save manually.", false)
        end
        return
    end

    if applyState.phase == "slots" and IsSlotRoot(opts) then
        if applyState.ptr > #applyState.queue then
            applyState.phase = "save"
            ScheduleStep(ProcessApplyStep)
            return
        end
        local entry = applyState.queue[applyState.ptr]
        local slotIdx = FindSlotIndex(opts, entry.gossip)
        if not slotIdx then
            CompleteCurrentSlot(true, "slot not in gossip: " .. (entry.gossip or entry.label or "?"))
            ScheduleStep(ProcessApplyStep)
            return
        end

        if SlotOptionShowsItem(opts, entry.gossip, entry.itemId) then
            CompleteCurrentSlot(false)
            ScheduleStep(ProcessApplyStep)
            return
        end

        applyState.targetItemId = entry.itemId
        applyState.currentLabel = entry.label
        applyState.phase = "find_item"
        applyState.slotAttempts = 0
        applyState.waitingForGossip = true
        ReportProgress(entry, applyState.ptr, #applyState.queue)
        if EbonTransmog.AppearanceService and EbonTransmog.AppearanceService.WarmItemCache then
            EbonTransmog.AppearanceService.WarmItemCache({ entry.itemId })
        end
        SelectOption(slotIdx)
        return
    end

    ScheduleStep(ProcessApplyStep)
end

local function ResolveApplyTarget(loadoutName, draftSlots)
    if loadoutName and loadoutName ~= "" then
        local loadout = Loadouts.GetByName(loadoutName)
        if loadout then
            return loadoutName, BuildQueueFromLoadout(loadout)
        end
    end
    if draftSlots and next(draftSlots) then
        local display = (loadoutName and loadoutName ~= "") and loadoutName or "draft"
        return display, BuildQueueFromDraft(draftSlots)
    end
    return nil, {}
end

local function HideJournal()
    if EbonTransmog.TransmogJournal and EbonTransmog.TransmogJournal.Hide then
        EbonTransmog.TransmogJournal.Hide()
    end
end

local function BeginApply(displayName, queue)
    if applyActive then
        PrintMsg("|cffff8800Apply already running.|r")
        return false
    end
    if #queue == 0 then
        PrintMsg("Nothing to apply — save a loadout or assign items in the draft first.")
        return false
    end
    ClearPending()
    HideJournal()
    if EbonTransmog.TransmogJournal and EbonTransmog.TransmogJournal.SetActiveLoadoutName then
        EbonTransmog.TransmogJournal.SetActiveLoadoutName(displayName)
    end
    if GossipFrame and GossipFrame:IsVisible() and IsTransmogGossip(GetGossipOptionList()) then
        StartApplyRun(displayName, queue)
    else
        pendingApply = {
            displayName = displayName,
            queue = queue,
        }
        PrintMsg("Loadout |cffffff00" .. displayName .. "|r queued. Talk to the Warpweaver to apply.")
    end
    return true
end

function Applier.IsActive()
    return applyActive
end

function Applier.HasPending()
    return pendingApply ~= nil
end

function Applier.GetPendingName()
    return pendingApply and pendingApply.displayName or nil
end

function Applier.CancelPending()
    if pendingApply then
        pendingApply = nil
        PrintMsg("Queued apply cancelled.")
    end
end

function Applier.Apply(loadoutName, draftSlots)
    local displayName, queue = ResolveApplyTarget(loadoutName, draftSlots)
    if not displayName then
        PrintMsg("Loadout not found. Save the draft or pick a saved loadout first.")
        return false
    end
    return BeginApply(displayName, queue)
end

function Applier.TryStartPending()
    if not pendingApply or applyActive then return end
    if not GossipFrame or not GossipFrame:IsVisible() then return end
    local opts = GetGossipOptionList()
    if not IsTransmogGossip(opts) then return end

    local pending = pendingApply
    ClearPending()
    StartApplyRun(pending.displayName, pending.queue)
end

function Applier.Install()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GOSSIP_SHOW")
    frame:RegisterEvent("GOSSIP_CLOSED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "GOSSIP_CLOSED" then
            if applyActive then
                FinishApply("Apply stopped — gossip closed.", false)
            end
            return
        end
        if event == "GOSSIP_SHOW" then
            if applyActive and applyState then
                applyState.waitingForGossip = false
                ScheduleStep(ProcessApplyStep)
                return
            end
            if pendingApply then
                ScheduleStep(function()
                    Applier.TryStartPending()
                end)
            end
        end
    end)
end

Applier.Install()
