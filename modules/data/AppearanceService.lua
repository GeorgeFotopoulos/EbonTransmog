-- EbonTransmog: modules/data/AppearanceService.lua
-- Tracks collected transmog appearances via native APIs (when available), SavedVariables,
-- and CHAT_MSG_SYSTEM unlock messages.

EbonTransmog = EbonTransmog or {}
local Service = {}
EbonTransmog.AppearanceService = Service

local Catalog = EbonTransmog.SlotCatalog

local UNLOCK_PATTERN = "has been added to your appearance collection"

Service.ARMOR_SUBCLASS = {
    CLOTH = 1,
    LEATHER = 2,
    MAIL = 3,
    PLATE = 4,
}

Service.ARMOR_TYPE_OPTIONS = {
    { subclass = 1, label = "Cloth" },
    { subclass = 2, label = "Leather" },
    { subclass = 3, label = "Mail" },
    { subclass = 4, label = "Plate" },
}

local ARMOR_SUBTYPE_KEYS = {
    cloth = 1,
    leather = 2,
    mail = 3,
    plate = 4,
}

local function NormalizeArmorSubclass(value)
    if value == nil then return nil end
    if type(value) == "number" then
        if value >= 1 and value <= 4 then return value end
        return nil
    end
    if type(value) == "string" then
        return ARMOR_SUBTYPE_KEYS[value:lower()]
    end
    return nil
end

local function IsArmorItemType(itemType)
    if itemType == 4 then return true end
    if type(itemType) == "string" and itemType:lower() == "armor" then return true end
    return false
end

local function IsWeaponItemType(itemType)
    if itemType == 2 then return true end
    if type(itemType) == "string" and itemType:lower() == "weapon" then return true end
    return false
end

local function ParseItemTypesFromGetItemInfo(itemId)
    local name, link, quality, _, _, itemType, itemSubType, _, equipSlot, icon = GetItemInfo(itemId)

    local armorSubclass = NormalizeArmorSubclass(itemSubType)
    local isArmor = IsArmorItemType(itemType)

    return {
        name = name,
        link = link,
        quality = quality,
        equipSlot = equipSlot,
        icon = icon,
        itemType = itemType,
        itemSubType = itemSubType,
        armorSubclass = armorSubclass,
        isArmor = isArmor,
        isWeapon = IsWeaponItemType(itemType),
    }
end

local liveCollection = nil
local apiProbe = nil
local chatHookInstalled = false
local serverHookInstalled = false
local syncFrame = nil
local notifyFrame = nil
local notifyScheduled = false
local resolveFrame = nil
local pendingResolve = {}
local RESOLVE_MAX_FRAMES = 60
local RESOLVE_BATCH = 4
local NOTIFY_DEBOUNCE = 0.35

local QUALITY_FROM_COLOR = {
    ["ff9d9d9d"] = 0, ["9d9d9d"] = 0,
    ["ffffffff"] = 1, ["ffffff"] = 1,
    ["ff1eff00"] = 2, ["1eff00"] = 2,
    ["ff0070dd"] = 3, ["0070dd"] = 3,
    ["ffa335ee"] = 4, ["a335ee"] = 4,
    ["ffff8000"] = 5, ["ff8000"] = 5,
}

local QUALITY_TO_HEX = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00",
    [3] = "0070dd", [4] = "a335ee", [5] = "ff8000",
}

local function GetItemInfoCache()
    EbonTransmogDB = EbonTransmogDB or {}
    EbonTransmogDB.itemInfoCache = EbonTransmogDB.itemInfoCache or {}
    return EbonTransmogDB.itemInfoCache
end

function Service.GetStoredItemInfo(itemId)
    itemId = tonumber(itemId)
    if not itemId then return nil end
    return GetItemInfoCache()[itemId]
end

function Service.StoreItemInfo(itemId, info)
    itemId = tonumber(itemId)
    if not itemId or not info then return end
    local cache = GetItemInfoCache()
    local existing = cache[itemId] or {}
    local merged = {
        name = info.name or existing.name,
        link = info.link or existing.link,
        quality = info.quality ~= nil and info.quality or existing.quality,
        icon = info.icon or existing.icon,
        equipSlot = info.equipSlot or existing.equipSlot,
        itemType = info.itemType or existing.itemType,
        itemSubType = info.itemSubType or existing.itemSubType,
        armorSubclass = info.armorSubclass or existing.armorSubclass,
        isArmor = info.isArmor ~= nil and info.isArmor or existing.isArmor,
    }
    if merged.name or merged.icon or merged.link then
        cache[itemId] = merged
    end
end

function Service.ParseGossipItemText(text)
    if not text or not text:find("item:", 1, true) then return nil end
    local itemId = tonumber(text:match("item:(%d+)"))
    if not itemId then return nil end

    local name = text:match("|h%[([^%]]+)%]|h") or text:match("%[([^%]]+)%]")
    local link = text:match("(|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r)")
    local iconPath = text:match("|T([^:]+)")
    if iconPath then
        iconPath = iconPath:gsub("/", "\\")
    end

    local quality = 1
    local colorHex = text:match("|c(%x%x%x%x%x%x%x%x)")
    if colorHex then
        local lower = colorHex:lower()
        quality = QUALITY_FROM_COLOR[lower] or QUALITY_FROM_COLOR[lower:sub(3)] or 1
    end

    return {
        itemId = itemId,
        name = name,
        link = link,
        quality = quality,
        icon = iconPath,
    }
end

function Service.IngestGossipText(text, slotMeta)
    local parsed = Service.ParseGossipItemText(text)
    if not parsed then return false end
    Service.StoreItemInfo(parsed.itemId, parsed)
    local gossip = slotMeta and slotMeta.gossip
    local meta = Catalog.ResolveItemMeta(parsed.itemId, gossip)
    if not meta and slotMeta then
        meta = {
            category = slotMeta.category,
            sub = slotMeta.sub,
            gossip = gossip,
            label = slotMeta.label,
        }
    end
    return Service.AddCollected(parsed.itemId, true, meta)
end

local function BuildItemLink(itemId, name, quality)
    if not itemId or not name or name == "" then return nil end
    local hex = QUALITY_TO_HEX[quality or 1] or "ffffff"
    local safeName = name:gsub("%[", ""):gsub("%]", "")
    return string.format("|cff%s|Hitem:%d:0:0:0:0:0:0:0|h[%s]|h|r", hex, itemId, safeName)
end

function Service.GetItemHyperlink(itemId)
    itemId = tonumber(itemId)
    if not itemId then return nil end
    local stored = Service.GetStoredItemInfo(itemId)
    if stored and stored.link then return stored.link end
    local _, link, _, _, _, _, _, _, _, _ = GetItemInfo(itemId)
    if link then return link end
    if stored and stored.name then
        return BuildItemLink(itemId, stored.name, stored.quality)
    end
    return "item:" .. itemId
end

local function FlushNotify()
    notifyScheduled = false
    if EbonTransmog.TransmogJournal and EbonTransmog.TransmogJournal.OnDataChanged then
        EbonTransmog.TransmogJournal.OnDataChanged()
    end
end

local notifyElapsed = 0
local function NotifyChanged()
    notifyElapsed = 0
    notifyScheduled = true
    if not notifyFrame then
        notifyFrame = CreateFrame("Frame")
        notifyFrame:SetScript("OnUpdate", function(self, dt)
            if not notifyScheduled then return end
            notifyElapsed = notifyElapsed + dt
            if notifyElapsed >= NOTIFY_DEBOUNCE then
                notifyScheduled = false
                FlushNotify()
            end
        end)
    end
end

function Service.NotifyCollectionChangedNow()
    notifyScheduled = false
    notifyElapsed = NOTIFY_DEBOUNCE
    FlushNotify()
end

function Service.NotifyCollectionChanged()
    NotifyChanged()
end

local function GetCharKey()
    local name = UnitName and UnitName("player")
    if not name then return nil end
    return "Unknown\t" .. name
end

local function GetCacheTable()
    EbonTransmogDB = EbonTransmogDB or {}
    EbonTransmogDB.collectedAppearances = EbonTransmogDB.collectedAppearances or {}
    local key = GetCharKey()
    if not key then return {} end
    EbonTransmogDB.collectedAppearances[key] = EbonTransmogDB.collectedAppearances[key] or {}
    return EbonTransmogDB.collectedAppearances[key]
end

local function ParseItemIdFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

local function ParseItemIdFromMessage(msg)
    if not msg then return nil end
    local link = msg:match("|H(item:[^|]+)|h")
    if link then
        return ParseItemIdFromLink(link)
    end
    return ParseItemIdFromLink(msg)
end

local function SlotMetaFromItem(itemId)
    return Catalog.ResolveItemMeta(itemId)
end

function Service.HandleAppearanceUnlockMessage(msg)
    if not msg or not msg:find(UNLOCK_PATTERN, 1, true) then return false end

    local itemId = ParseItemIdFromMessage(msg)
    if not itemId then return false end

    local parsed = Service.ParseGossipItemText(msg)
    if parsed then
        Service.StoreItemInfo(parsed.itemId, parsed)
    end

    local slotMeta = SlotMetaFromItem(itemId)
    local isNew = Service.AddCollected(itemId, true, slotMeta)
    Service.QueueItemResolve({ itemId })
    return isNew
end

local function IsTransmoggableItem(itemId)
    if not itemId then return false end
    local parsed = ParseItemTypesFromGetItemInfo(itemId)
    if not parsed.name then
        return true
    end
    if not parsed.equipSlot or parsed.equipSlot == "" or parsed.equipSlot == "INVTYPE_NON_EQUIP" then
        return false
    end
    if parsed.isArmor or parsed.isWeapon then
        return true
    end
    local meta = Catalog.GetMetaForEquipSlot(parsed.equipSlot)
    return meta ~= nil
end

local function SortKeyForItem(itemId)
    local stored = Service.GetStoredItemInfo(itemId)
    if stored and stored.name and stored.name ~= "" then
        return stored.name:lower()
    end
    local name = GetItemInfo(itemId)
    if name and name ~= "" then
        return name:lower()
    end
    return string.format("zzzz%08d", itemId)
end

local function ItemInfoResolved(itemId)
    local parsed = ParseItemTypesFromGetItemInfo(itemId)
    if parsed.name and parsed.name ~= "" then
        Service.StoreItemInfo(itemId, parsed)
        return true
    end
    local stored = Service.GetStoredItemInfo(itemId)
    return stored and stored.name and stored.name ~= ""
end

local function EnsureResolveWorker()
    if resolveFrame then return end
    resolveFrame = CreateFrame("Frame")
    local tick = 0
    resolveFrame:SetScript("OnUpdate", function(self, dt)
        if not next(pendingResolve) then return end
        tick = tick + 1
        local resolvedAny = false
        local primed = 0
        for itemId, state in pairs(pendingResolve) do
            if ItemInfoResolved(itemId) then
                pendingResolve[itemId] = nil
                resolvedAny = true
            else
                state.frames = (state.frames or 0) + 1
                if primed < RESOLVE_BATCH and (tick % 2 == 0) then
                    Service.EnsureItemCached(itemId)
                    primed = primed + 1
                end
                if state.frames >= RESOLVE_MAX_FRAMES then
                    pendingResolve[itemId] = nil
                end
            end
        end
        if resolvedAny then
            NotifyChanged()
        end
    end)
end

function Service.QueueItemResolve(itemIds)
    local queued = false
    for _, itemId in ipairs(itemIds or {}) do
        itemId = tonumber(itemId)
        if itemId and not ItemInfoResolved(itemId) then
            if not pendingResolve[itemId] then
                pendingResolve[itemId] = { frames = 0 }
                Service.EnsureItemCached(itemId)
                queued = true
            end
        end
    end
    if queued then
        EnsureResolveWorker()
    end
end

function Service.EnsureItemCached(itemId)
    if not itemId then return end
    if GetItemInfo(itemId) then return end
    local tip = _G.EbonTransmogCacheTip
    if not tip then
        tip = CreateFrame("GameTooltip", "EbonTransmogCacheTip", nil, "GameTooltipTemplate")
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        _G.EbonTransmogCacheTip = tip
    end
    tip:ClearLines()
    tip:SetHyperlink("item:" .. itemId)
end

function Service.WarmItemCache(itemIds)
    for _, itemId in ipairs(itemIds or {}) do
        Service.EnsureItemCached(itemId)
    end
    Service.QueueItemResolve(itemIds)
end

-- ── Native API probes ────────────────────────────────────────────────────────

local function ProbeNativeCollected(itemId)
    if C_TransmogCollection and C_TransmogCollection.GetCollectedItemAppearance then
        local ok, result = pcall(C_TransmogCollection.GetCollectedItemAppearance, itemId)
        if ok and result then return true end
    end
    if type(GetCollectedItemAppearance) == "function" then
        local ok, result = pcall(GetCollectedItemAppearance, itemId)
        if ok and result then return true end
    end
    if type(HasTransmog) == "function" then
        local ok, result = pcall(HasTransmog, itemId)
        if ok and result then return true end
    end
    return false
end

local function TryEnumerateNativeCollection()
    local collected = {}

    if C_TransmogCollection then
        if C_TransmogCollection.GetNumTransmogSources then
            local ok, numSources = pcall(C_TransmogCollection.GetNumTransmogSources)
            if ok and numSources and numSources > 0 and C_TransmogCollection.GetSourceInfo then
                for i = 1, numSources do
                    local ok2, info = pcall(C_TransmogCollection.GetSourceInfo, i)
                    if ok2 and info and info.isCollected and info.itemID then
                        collected[info.itemID] = true
                    end
                end
                if next(collected) then return collected end
            end
        end

        if C_TransmogCollection.GetNumAppearances then
            local ok, numApp = pcall(C_TransmogCollection.GetNumAppearances)
            if ok and numApp and numApp > 0 and C_TransmogCollection.GetAppearanceInfoByIndex then
                for i = 1, numApp do
                    local ok2, info = pcall(C_TransmogCollection.GetAppearanceInfoByIndex, i)
                    if ok2 and info and info.isCollected and info.sourceID and C_TransmogCollection.GetSourceInfo then
                        local ok3, src = pcall(C_TransmogCollection.GetSourceInfo, info.sourceID)
                        if ok3 and src and src.itemID then
                            collected[src.itemID] = true
                        end
                    end
                end
                if next(collected) then return collected end
            end
        end
    end

    return nil
end

function Service.ProbeAPIs()
    if apiProbe then return apiProbe end

    apiProbe = {
        CollectionsJournal = _G.CollectionsJournal ~= nil,
        CollectionsMicroButton = _G.CollectionsMicroButton ~= nil,
        C_TransmogCollection = C_TransmogCollection ~= nil,
        GetCollectedItemAppearance = type(GetCollectedItemAppearance) == "function",
        GetItemAppearanceInfo = type(GetItemAppearanceInfo) == "function",
        HasTransmog = type(HasTransmog) == "function",
        DressUpModel_TryOn = false,
        DressUpModel_Undress = false,
    }

    local probeModel = CreateFrame("DressUpModel")
    if probeModel then
        apiProbe.DressUpModel_TryOn = type(probeModel.TryOn) == "function"
        apiProbe.DressUpModel_Undress = type(probeModel.Undress) == "function"
        probeModel:Hide()
        probeModel:SetParent(nil)
    end

    EbonTransmogDB = EbonTransmogDB or {}
    EbonTransmogDB.apiProbe = apiProbe

    return apiProbe
end

function Service.PrintProbeResults()
    local p = Service.ProbeAPIs()
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[EbonTransmog]|r API probe:")
    for k, v in pairs(p) do
        local status = v and "|cff00ff00yes|r" or "|cffff4444no|r"
        DEFAULT_CHAT_FRAME:AddMessage("  " .. k .. ": " .. status)
    end
    local cache = GetCacheTable()
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    DEFAULT_CHAT_FRAME:AddMessage("  cached collected items: |cffffff00" .. count .. "|r")
    if not p.C_TransmogCollection and not p.GetCollectedItemAppearance and not p.HasTransmog then
        DEFAULT_CHAT_FRAME:AddMessage("  collection mode: |cffffff00gossip + chat cache|r (visit Transmogrifier, run |cff66ccff/etmog scan|r)")
    end
end

function Service.GetCharacterKey()
    return GetCharKey()
end

function Service.Invalidate()
    liveCollection = nil
end

function Service.IsCollected(itemId)
    itemId = tonumber(itemId)
    if not itemId then return false end

    if liveCollection and liveCollection[itemId] then
        return true
    end

    local cache = GetCacheTable()
    if cache[itemId] then return true end

    if ProbeNativeCollected(itemId) then
        cache[itemId] = true
        return true
    end

    return false
end

function Service.GetCollectedItems()
    if liveCollection then
        local merged = {}
        for id in pairs(liveCollection) do
            merged[id] = true
        end
        local cache = GetCacheTable()
        for id in pairs(cache) do
            merged[id] = true
        end
        return merged
    end

    local cache = GetCacheTable()
    local merged = {}
    for id in pairs(cache) do
        merged[id] = true
    end
    return merged
end

function Service.AddCollected(itemId, fromGossip, slotMeta)
    itemId = tonumber(itemId)
    if not itemId then return false end
    if not fromGossip and not IsTransmoggableItem(itemId) then return false end

    if slotMeta and (not slotMeta.sub or Catalog.IsLegacyWeaponSub(slotMeta.sub)) then
        local resolved = Catalog.ResolveItemMeta(itemId, slotMeta.gossip)
        if resolved then slotMeta = resolved end
    elseif not slotMeta or not slotMeta.sub then
        slotMeta = Catalog.ResolveItemMeta(itemId, slotMeta and slotMeta.gossip) or slotMeta
    end

    local cache = GetCacheTable()
    local existing = cache[itemId]
    local isNew = not existing
    local updated = false

    if slotMeta and slotMeta.sub then
        cache[itemId] = {
            sub = slotMeta.sub,
            category = slotMeta.category or "armor",
            gossip = slotMeta.gossip,
            label = slotMeta.label or Catalog.GetGossipLabelForSub(slotMeta.sub),
        }
        updated = true
    elseif not existing then
        cache[itemId] = true
        updated = true
    end

    if liveCollection then
        liveCollection[itemId] = true
    end
    if updated then
        NotifyChanged()
    end
    return isNew
end

local function NormalizeCacheEntry(entry)
    if not entry then return nil end
    if entry == true then return {} end
    if type(entry) == "table" then return entry end
    return {}
end

function Service.GetCollectedEntry(itemId)
    itemId = tonumber(itemId)
    if not itemId then return nil end
    local cache = GetCacheTable()
    if not cache[itemId] then return nil end
    return NormalizeCacheEntry(cache[itemId])
end

function Service.GetItemMeta(itemId)
    if not itemId then return nil end
    local entry = Service.GetCollectedEntry(itemId)
    local gossip = entry and entry.gossip
    local meta = Catalog.ResolveItemMeta(itemId, gossip)
    if meta then
        return {
            category = meta.category,
            sub = meta.sub,
            gossip = gossip or meta.gossip,
            label = meta.label or Catalog.GetGossipLabelForSub(meta.sub),
        }
    end
    if entry and entry.sub then
        return {
            category = entry.category or "armor",
            sub = entry.sub,
            gossip = entry.gossip,
            label = entry.label or Catalog.GetGossipLabelForSub(entry.sub),
        }
    end
    return nil
end

function Service.GetItemEquipSlot(itemId)
    if not itemId then return nil end
    local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(itemId)
    return equipSlot
end

function Service.GetItemSlotCategory(itemId)
    local meta = Service.GetItemMeta(itemId)
    return meta and meta.category or nil
end

function Service.GetItemSubcategory(itemId)
    local meta = Service.GetItemMeta(itemId)
    return meta and meta.sub or nil
end

function Service.GetSubcategories(category)
    return Catalog.GetSubcategories(category)
end

function Service.GetItemDisplayInfo(itemId)
    itemId = tonumber(itemId)
    if not itemId then return {} end

    local stored = Service.GetStoredItemInfo(itemId) or {}
    Service.EnsureItemCached(itemId)

    local parsed = ParseItemTypesFromGetItemInfo(itemId)
    if parsed.name and parsed.name ~= "" then
        Service.StoreItemInfo(itemId, parsed)
        stored = Service.GetStoredItemInfo(itemId) or stored
    end

    local name = parsed.name or stored.name
    local link = parsed.link or stored.link
    local quality = parsed.quality or stored.quality
    local icon = parsed.icon or stored.icon
    local equipSlot = parsed.equipSlot or stored.equipSlot
    local armorSubclass = parsed.armorSubclass or stored.armorSubclass
    local isArmor = parsed.isArmor
    if isArmor == nil then isArmor = stored.isArmor end

    if not link and name then
        link = BuildItemLink(itemId, name, quality or 0)
    end
    quality = quality or 0
    icon = icon or stored.icon

    local meta = Service.GetItemMeta(itemId) or Catalog.GetMetaForEquipSlot(equipSlot)
    return {
        itemId = itemId,
        name = name,
        link = link,
        quality = quality,
        equipSlot = equipSlot,
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        armorSubclass = armorSubclass,
        isArmor = isArmor,
        category = meta and meta.category,
        subcategory = meta and meta.sub,
        pending = not name,
    }
end

function Service.RepairCacheEntries()
    local cache = GetCacheTable()
    local repaired = false
    for itemId, entry in pairs(cache) do
        local needsFix = entry == true
            or (type(entry) == "table" and (
                not entry.sub or Catalog.IsLegacyWeaponSub(entry.sub)
            ))
        if needsFix then
            local gossip = type(entry) == "table" and entry.gossip or nil
            local meta = Catalog.ResolveItemMeta(itemId, gossip)
            if meta and meta.sub then
                cache[itemId] = {
                    sub = meta.sub,
                    category = meta.category,
                    gossip = gossip or meta.gossip,
                    label = meta.label,
                }
                repaired = true
            end
        end
    end
    if repaired then
        NotifyChanged()
    end
end

function Service.MigrateLegacyItemInfoCache()
    local cache = GetItemInfoCache()
    for itemId, existing in pairs(cache) do
        if not existing.armorSubclass then
            local armorSubclass = NormalizeArmorSubclass(existing.subclassID)
                or NormalizeArmorSubclass(existing.itemSubType)
            local isArmor = existing.isArmor
            if isArmor == nil then
                isArmor = IsArmorItemType(existing.classID) or IsArmorItemType(existing.itemType)
            end
            if armorSubclass or isArmor then
                Service.StoreItemInfo(itemId, {
                    armorSubclass = armorSubclass,
                    isArmor = isArmor,
                    itemSubType = existing.itemSubType or existing.subclassID,
                    itemType = existing.itemType or existing.classID,
                })
            end
        end
    end
end

function Service.RepairItemInfoCache()
    Service.MigrateLegacyItemInfoCache()
    local cache = GetItemInfoCache()
    local ids = {}
    for itemId in pairs(cache) do
        ids[#ids + 1] = itemId
    end
    Service.QueueItemResolve(ids)
end

function Service.WarmAllCachedItems()
    local collected = Service.GetCollectedItems()
    local ids = {}
    for itemId in pairs(collected) do
        ids[#ids + 1] = itemId
    end
    Service.WarmItemCache(ids)
    Service.RepairCacheEntries()
    Service.RepairItemInfoCache()
end

local function ItemMatchesSearch(itemId, searchText)
    if not searchText or searchText == "" then return true end
    local info = Service.GetItemDisplayInfo(itemId)
    if info.name and info.name:lower():find(searchText, 1, true) then
        return true
    end
    return tostring(itemId):find(searchText, 1, true) ~= nil
end

local function FilterSetIsActive(filterSet)
    if not filterSet then return false end
    for _ in pairs(filterSet) do return true end
    return false
end

local function RarityFilterIsActive(rarityFilter)
    return FilterSetIsActive(rarityFilter)
end

local function ItemMatchesRarity(itemId, rarityFilter)
    if not RarityFilterIsActive(rarityFilter) then return true end
    local info = Service.GetItemDisplayInfo(itemId)
    return rarityFilter[info.quality or 0] == true
end

local function ItemMatchesArmorType(itemId, armorTypeFilter, subcategory)
    if not FilterSetIsActive(armorTypeFilter) then return true end
    if subcategory and not Catalog.UsesArmorTypeFilter(subcategory) then return true end
    local info = Service.GetItemDisplayInfo(itemId)
    if not info.isArmor or not info.armorSubclass then return false end
    return armorTypeFilter[info.armorSubclass] == true
end

local function ItemMatchesPlayerWeaponRules(itemId, subcategory)
    if subcategory and Catalog.IsTwoHandedWeaponSub(subcategory) then
        if not Catalog.PlayerCanUseTwoHandedWeapons() then return false end
    end
    if itemId and not Catalog.PlayerCanUseWeaponItem(itemId) then return false end
    return true
end

local function CollectItems(category, subcategory, searchText, rarityFilter, armorTypeFilter)
    searchText = searchText and searchText:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    local items = {}
    local collected = Service.GetCollectedItems()

    for itemId in pairs(collected) do
        local meta = Service.GetItemMeta(itemId)
        if meta and meta.category == category then
            if not subcategory or meta.sub == subcategory then
                if ItemMatchesSearch(itemId, searchText)
                    and ItemMatchesRarity(itemId, rarityFilter)
                    and ItemMatchesArmorType(itemId, armorTypeFilter, subcategory)
                    and ItemMatchesPlayerWeaponRules(itemId, subcategory) then
                    table.insert(items, itemId)
                end
            end
        end
    end

    table.sort(items, function(a, b)
        local ka = SortKeyForItem(a)
        local kb = SortKeyForItem(b)
        if ka ~= kb then return ka < kb end
        return a < b
    end)

    return items
end

function Service.GetItemsForCategory(category, searchText, rarityFilter, armorTypeFilter)
    return CollectItems(category, nil, searchText, rarityFilter, armorTypeFilter)
end

function Service.GetItemsForSubcategory(category, subcategory, searchText, rarityFilter, armorTypeFilter)
    return CollectItems(category, subcategory, searchText, rarityFilter, armorTypeFilter)
end

function Service.GetCollectedCountForSubcategory(category, subcategory)
    return #CollectItems(category, subcategory, "")
end

function Service.RequestSync()
    local native = TryEnumerateNativeCollection()
    if native and next(native) then
        liveCollection = native
        local cache = GetCacheTable()
        for id in pairs(native) do
            cache[id] = true
        end
        NotifyChanged()
        return true
    end

    liveCollection = nil
    return false
end

function Service.InstallChatHook()
    if chatHookInstalled then return end
    chatHookInstalled = true

    local function OnUnlockMessage(_, _, msg)
        Service.HandleAppearanceUnlockMessage(msg)
    end

    local chatFrame = CreateFrame("Frame")
    chatFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    chatFrame:SetScript("OnEvent", OnUnlockMessage)
end

function Service.InstallServerHook()
    if serverHookInstalled then return end
    serverHookInstalled = true

    -- Future: hook ProjectEbonhold appearance discovery opcode when server adds it
    if not ProjectEbonhold or not ProjectEbonhold.onEventReceived then return end
    if not ProjectEbonhold.SS or not ProjectEbonhold.SS.SEND_APPEARANCE_DISCOVERY then return end

    ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_APPEARANCE_DISCOVERY, function(body)
        local collected = {}
        if body and body ~= "" then
            for entry in string.gmatch(body, "([^,]+)") do
                local id = tonumber(entry:match("^(%d+)"))
                if id then collected[id] = true end
            end
        end
        liveCollection = collected
        local cache = GetCacheTable()
        for id in pairs(collected) do
            cache[id] = true
        end
        NotifyChanged()
    end)

    if ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_APPEARANCE_DISCOVERY
        and ProjectEbonhold.sendToServer then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_APPEARANCE_DISCOVERY, "")
    end
end

-- Login sync
syncFrame = CreateFrame("Frame")
syncFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
syncFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        Service.RequestSync()
    end
end)
