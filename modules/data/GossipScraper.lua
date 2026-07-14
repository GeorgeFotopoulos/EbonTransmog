-- EbonTransmog: modules/data/GossipScraper.lua
-- Harvests collected appearances from the transmogrifier NPC gossip tree.
-- Passive: records item links whenever transmog gossip is visible.
-- Active: /etmog scan walks slots and pages automatically (gossip must be open).

EbonTransmog = EbonTransmog or {}
local Scraper = {}
EbonTransmog.GossipScraper = Scraper

local Service = EbonTransmog.AppearanceService
local Catalog = EbonTransmog.SlotCatalog

local SCAN_DELAY = 0.25
local SCAN_DELAY_FAST = 0.08
local scanActive = false
local scanDelayFrame = nil
local scanState = nil

-- Warpweaver slot menu uses a mix of "Head [transmog]" and plain "Legs" labels.
local SLOT_LABELS = {
    "Head", "Shoulders", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrists", "Hands",
    "Back", "Main hand", "Off hand", "Ranged", "Tabard",
}

local NAV_NEXT_PAGE = "Next page"
local NAV_PREVIOUS_PAGE = "Previous page"
local NAV_MAIN_MENU = "Show main menu"

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

local function GetGossipOptionList()
    local opts = {}
    if type(GetGossipOptions) ~= "function" then return opts end
    local data = { GetGossipOptions() }
    for i = 1, #data, 2 do
        table.insert(opts, {
            index = (#opts + 1),
            name = data[i] or "",
            gossipType = data[i + 1],
        })
    end
    return opts
end

local function ExtractItemIds(text)
    local ids = {}
    if not text then return ids end
    for id in text:gmatch("item:(%d+)") do
        ids[tonumber(id)] = true
    end
    return ids
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

local FindPageInfo
local FindOptionExact

FindOptionExact = function(opts, text)
    for _, opt in ipairs(opts) do
        if StripGossipText(opt.name) == text then
            return opt.index
        end
    end
    return nil
end

local function IsTransmogGossip(opts)
    if FindPageInfo(opts) then return true end
    if FindOptionExact(opts, NAV_NEXT_PAGE) or FindOptionExact(opts, NAV_PREVIOUS_PAGE)
        or FindOptionExact(opts, NAV_MAIN_MENU) then
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

local function FindSlotEntries(opts)
    local entries = {}
    for _, opt in ipairs(opts) do
        local plain = StripGossipText(opt.name)
        if IsKnownSlotLabel(plain) then
            table.insert(entries, { index = opt.index, label = PlainSlotLabel(plain) })
        end
    end
    return entries
end

FindPageInfo = function(opts)
    for _, opt in ipairs(opts) do
        local plain = StripGossipText(opt.name)
        local slot, cur, max = plain:match("^(.-) %- Page (%d+)/(%d+)$")
        if cur and max then
            return {
                index = opt.index,
                slot = slot:gsub("^%s+", ""):gsub("%s+$", ""),
                current = tonumber(cur),
                max = tonumber(max),
            }
        end
    end
    return nil
end

local function IsNavigationOption(plain)
    if plain == NAV_NEXT_PAGE or plain == NAV_PREVIOUS_PAGE or plain == NAV_MAIN_MENU then return true end
    if plain == "< Back" or plain == "Back" then return true end
    if plain:find("Page %d+/%d+") then return true end
    if plain:find("Restore original", 1, true) then return true end
    if plain:find("Hide item", 1, true) then return true end
    if plain:find("Remove pending", 1, true) then return true end
    if plain:find("Save pending", 1, true) then return true end
    if plain:find("Cancel pending", 1, true) then return true end
    return false
end

local function HarvestVisible(opts)
    if not Service then return 0 end
    local slotMeta = nil
    local pageInfo = FindPageInfo(opts)
    if pageInfo and pageInfo.slot then
        slotMeta = Catalog.GetMetaForGossipSlot(pageInfo.slot)
    end

    local added = 0
    for _, opt in ipairs(opts) do
        local plain = StripGossipText(opt.name)
        if not IsNavigationOption(plain) and not IsKnownSlotLabel(plain) then
            if Service.IngestGossipText(opt.name, slotMeta) then
                added = added + 1
            end
        end
    end
    return added
end

local function EnsureDelayFrame()
    if not scanDelayFrame then
        scanDelayFrame = CreateFrame("Frame")
        scanDelayFrame:Hide()
    end
    return scanDelayFrame
end

local function CancelScanTimer()
    if scanDelayFrame then
        scanDelayFrame:SetScript("OnUpdate", nil)
        scanDelayFrame:Hide()
    end
end

local function GetScanDelay()
    if scanState and scanState.fast then return SCAN_DELAY_FAST end
    return SCAN_DELAY
end

local function MatchSlotLabel(input)
    if not input or input == "" then return nil end
    local needle = input:lower():gsub("^%s+", ""):gsub("%s+$", "")
    for _, slot in ipairs(SLOT_LABELS) do
        if slot:lower() == needle then return slot end
    end
    for _, slot in ipairs(SLOT_LABELS) do
        if slot:lower():find(needle, 1, true) then return slot end
    end
    return nil
end

local function FilterSlotQueue(queue, slotFilter)
    if not slotFilter or #slotFilter == 0 then return queue end
    local wanted = {}
    for _, label in ipairs(slotFilter) do
        wanted[label] = true
    end
    local filtered = {}
    for _, entry in ipairs(queue) do
        if wanted[entry.label] then
            table.insert(filtered, entry)
        end
    end
    return filtered
end

-- Forward declare so earlier helpers capture it as a local upvalue (not _G.SelectOption).
local SelectOption

local function TryReturnToSlotMenu(opts, pageInfo)
    local menuIdx = FindOptionExact(opts, NAV_MAIN_MENU)
        or FindOptionExact(opts, "< Back")
        or FindOptionExact(opts, "Back")
    if menuIdx then
        scanState.phase = "slots"
        scanState.currentSlot = nil
        scanState.waitingForGossip = true
        SelectOption(menuIdx)
        return true
    end
    -- Even in fast scan, fall back to paging backwards if we can't leave from this page.
    if pageInfo and pageInfo.current > 1 then
        scanState.phase = "return_to_menu"
        local prevIdx = FindOptionExact(opts, NAV_PREVIOUS_PAGE)
        if prevIdx then
            scanState.waitingForGossip = true
            SelectOption(prevIdx)
            return true
        end
    end
    return false
end

local function ScheduleScanStep(fn)
    CancelScanTimer()
    local frame = EnsureDelayFrame()
    local elapsed = 0
    frame:Show()
    frame:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed >= GetScanDelay() then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            fn()
        end
    end)
end

SelectOption = function(index)
    if not index or type(SelectGossipOption) ~= "function" then return false end
    SelectGossipOption(index)
    return true
end

local function FinishScan(message)
    scanActive = false
    scanState = nil
    CancelScanTimer()
    if message then PrintMsg(message) end
    if Service and Service.NotifyCollectionChangedNow then
        Service.NotifyCollectionChangedNow()
    end
end

local function ProcessScanStep()
    if not scanActive or not GossipFrame or not GossipFrame:IsVisible() then
        FinishScan("|cffff4444Scan stopped.|r Gossip window closed.")
        return
    end
    if scanState and scanState.waitingForGossip then
        return
    end

    local opts = GetGossipOptionList()
    if #opts == 0 then
        FinishScan("|cffff4444Scan stopped.|r No gossip options.")
        return
    end

    HarvestVisible(opts)

    local pageInfo = FindPageInfo(opts)

    -- Item list for a slot (e.g. Head - Page 1/12)
    if pageInfo then
        scanState.currentSlot = pageInfo.slot

        -- Walk back to page 1, then "Show main menu" (only on page 1)
        if scanState.phase == "return_to_menu" then
            if pageInfo.current > 1 then
                local prevIdx = FindOptionExact(opts, NAV_PREVIOUS_PAGE)
                if prevIdx then
                    scanState.waitingForGossip = true
                    SelectOption(prevIdx)
                    return
                end
            end

            local menuIdx = FindOptionExact(opts, NAV_MAIN_MENU)
                or FindOptionExact(opts, "< Back")
                or FindOptionExact(opts, "Back")
            scanState.phase = "slots"
            scanState.currentSlot = nil
            if menuIdx then
                scanState.waitingForGossip = true
                SelectOption(menuIdx)
            else
                FinishScan("|cffff8800Scan stalled.|r Could not find 'Show main menu' on page 1.")
            end
            return
        end

        -- Forward through pages, harvesting each
        scanState.phase = "pages"
        if pageInfo.current < pageInfo.max then
            local nextIdx = FindOptionExact(opts, NAV_NEXT_PAGE)
            if nextIdx then
                scanState.waitingForGossip = true
                SelectOption(nextIdx)
                return
            end
        end

        -- Last page reached — return to slot menu (or finish slot-only scan)
        if scanState.slotOnly then
            FinishScan("|cff00ff00Slot scan complete.|r")
            return
        end

        if TryReturnToSlotMenu(opts, pageInfo) then
            return
        end

        FinishScan("|cffff8800Scan stalled.|r Could not leave slot pages.")
        return
    end

    -- Main slot menu
    if IsSlotRoot(opts) then
        scanState.phase = "slots"
        if not scanState.slotQueue or #scanState.slotQueue == 0 then
            local queue = FindSlotEntries(opts)
            scanState.slotQueue = FilterSlotQueue(queue, scanState.slotFilter)
            scanState.slotPtr = 1
            if #scanState.slotQueue == 0 then
                if scanState.slotFilter and #scanState.slotFilter > 0 then
                    FinishScan("|cffff4444Scan stopped.|r Requested slot(s) not found in gossip.")
                else
                    FinishScan("|cffff4444Scan stopped.|r No equipment slots found in gossip.")
                end
                return
            end
            if scanState.slotFilter and #scanState.slotFilter > 0 then
                PrintMsg(string.format(
                    "Scanning %d slot(s): |cffffff00%s|r",
                    #scanState.slotQueue,
                    scanState.slotQueue[1] and scanState.slotQueue[1].label or ""
                ))
            end
        end

        if scanState.slotPtr > #scanState.slotQueue then
            FinishScan("|cff00ff00Scan complete.|r Collected appearances saved to journal cache.")
            return
        end

        local entry = scanState.slotQueue[scanState.slotPtr]
        scanState.slotPtr = scanState.slotPtr + 1
        scanState.waitingForGossip = true
        SelectOption(entry.index)
        return
    end

    FinishScan("|cffff8800Scan finished with partial results.|r Could not parse gossip layout.")
end

function Scraper.IsScanActive()
    return scanActive
end

function Scraper.ParseScanOptions(args)
    args = (args or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local options = { fast = false, slotOnly = false, slots = {} }
    if args == "" then return options end

    for token in args:gmatch("%S+") do
        if token == "fast" or token == "quick" or token == "turbo" then
            options.fast = true
        elseif token == "slot" or token == "here" or token == "page" then
            options.slotOnly = true
        else
            local slot = MatchSlotLabel(token)
            if slot then
                table.insert(options.slots, slot)
            end
        end
    end
    return options
end

function Scraper.StartScan(options)
    options = options or {}
    if scanActive then
        PrintMsg("|cffff8800Scan already running.|r")
        return false
    end
    if not GossipFrame or not GossipFrame:IsVisible() then
        PrintMsg("|cffff4444Open the Transmogrifier gossip window first, then run /etmog scan|r")
        return false
    end
    local opts = GetGossipOptionList()
    if not IsTransmogGossip(opts) then
        PrintMsg("|cffff4444This NPC does not look like a transmogrifier.|r")
        return false
    end

    local pageInfo = FindPageInfo(opts)
    if options.slotOnly and not pageInfo then
        PrintMsg("|cffff4444Open a slot appearance list first|r (e.g. Head - Page 1/N), then |cff66ccff/etmog scan slot|r")
        return false
    end

    scanActive = true
    scanState = {
        phase = pageInfo and "pages" or "slots",
        slotQueue = {},
        slotPtr = 1,
        currentSlot = nil,
        waitingForGossip = false,
        fast = options.fast == true,
        skipPageReset = options.fast == true,
        slotOnly = options.slotOnly == true,
        slotFilter = options.slots or {},
    }

    local startPage = pageInfo
    if startPage and startPage.current == startPage.max and startPage.max > 1 and not scanState.skipPageReset then
        scanState.phase = "return_to_menu"
    end

    if scanState.slotOnly then
        PrintMsg(string.format(
            "Scanning current slot (%s)… keep gossip open.",
            pageInfo and pageInfo.slot or "?"
        ))
    elseif scanState.fast then
        PrintMsg("Fast scan — keep the gossip window open.")
    elseif scanState.slotFilter and #scanState.slotFilter > 0 then
        PrintMsg(string.format(
            "Scanning slot(s): |cffffff00%s|r — keep gossip open.",
            table.concat(scanState.slotFilter, ", ")
        ))
    else
        PrintMsg("Scanning transmog collection… keep the gossip window open.")
    end

    HarvestVisible(opts)
    ScheduleScanStep(ProcessScanStep)
    return true
end

function Scraper.StopScan()
    if scanActive then
        FinishScan("|cffff8800Scan cancelled.|r")
    end
end

function Scraper.HarvestCurrentGossip()
    if not GossipFrame or not GossipFrame:IsVisible() then
        PrintMsg("|cffff4444Gossip window is not open.|r")
        return 0
    end
    local opts = GetGossipOptionList()
    if not IsTransmogGossip(opts) then
        PrintMsg("|cffff4444No transmog gossip visible.|r")
        return 0
    end
    local added = HarvestVisible(opts)
    PrintMsg(string.format("Harvested |cffffff00%d|r new appearances from current gossip page.", added))
    if Service and Service.NotifyCollectionChanged then
        Service.NotifyCollectionChanged()
    end
    return added
end

function Scraper.Install()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GOSSIP_SHOW")
    frame:RegisterEvent("GOSSIP_CLOSED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "GOSSIP_CLOSED" then
            if scanActive then
                FinishScan("|cffff4444Scan stopped.|r Gossip closed.")
            end
            return
        end
        if event == "GOSSIP_SHOW" then
            if not GossipFrame or not GossipFrame:IsVisible() then return end
            local opts = GetGossipOptionList()
            if IsTransmogGossip(opts) then
                HarvestVisible(opts)
            end
            if scanActive and scanState then
                scanState.waitingForGossip = false
                ScheduleScanStep(ProcessScanStep)
            end
        end
    end)
end

Scraper.Install()
