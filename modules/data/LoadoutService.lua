-- EbonTransmog: saved transmog loadouts (slot -> itemId).

EbonTransmog = EbonTransmog or {}
local Loadouts = {}
EbonTransmog.LoadoutService = Loadouts

local Catalog = EbonTransmog.SlotCatalog

local function GetStore()
    EbonTransmogDB = EbonTransmogDB or {}
    EbonTransmogDB.loadouts = EbonTransmogDB.loadouts or {}
    return EbonTransmogDB.loadouts
end

local function SanitizeName(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name:sub(1, 32)
end

function Loadouts.GetAll()
    return GetStore()
end

function Loadouts.GetByName(name)
    name = SanitizeName(name)
    for _, loadout in ipairs(GetStore()) do
        if loadout.name == name then return loadout end
    end
    return nil
end

function Loadouts.Save(name, slots)
    name = SanitizeName(name)
    if name == "" then return false, "Name required." end

    local working = {}
    for subId, itemId in pairs(slots or {}) do
        working[subId] = itemId
    end
    Catalog.NormalizeWeaponSlots(working)

    local clean = {}
    for subId, itemId in pairs(working) do
        itemId = tonumber(itemId)
        if itemId and itemId > 0 then
            clean[subId] = itemId
        end
    end
    if not next(clean) then return false, "Loadout is empty." end

    local store = GetStore()
    local existing = Loadouts.GetByName(name)
    if existing then
        existing.slots = clean
    else
        table.insert(store, { name = name, slots = clean })
    end
    return true
end

function Loadouts.Delete(name)
    name = SanitizeName(name)
    local store = GetStore()
    for i, loadout in ipairs(store) do
        if loadout.name == name then
            table.remove(store, i)
            return true
        end
    end
    return false
end

function Loadouts.MigrateLegacySlots()
    local store = GetStore()
    local migrated = false
    for _, loadout in ipairs(store) do
        if loadout.slots then
            local before = 0
            for _ in pairs(loadout.slots) do before = before + 1 end
            Catalog.NormalizeWeaponSlots(loadout.slots)
            for subId, itemId in pairs(loadout.slots) do
                if Catalog.IsLegacyWeaponSub(subId) then
                    local meta = Catalog.ResolveItemMeta(itemId)
                    if meta and meta.sub then
                        loadout.slots[meta.sub] = itemId
                        loadout.slots[subId] = nil
                        migrated = true
                    end
                end
            end
            Catalog.NormalizeWeaponSlots(loadout.slots)
            local after = 0
            for _ in pairs(loadout.slots) do after = after + 1 end
            if after ~= before then migrated = true end
        end
    end
    return migrated
end

function Loadouts.GetSlotEntries(loadout)
    local entries = {}
    if not loadout or not loadout.slots then return entries end
    for subId, itemId in pairs(loadout.slots) do
        table.insert(entries, {
            subId = subId,
            gossip = Catalog.GetGossipForSub(subId, itemId),
            itemId = itemId,
            label = Catalog.GetGossipLabelForSub(subId) or subId,
        })
    end
    table.sort(entries, function(a, b) return a.label < b.label end)
    return entries
end
