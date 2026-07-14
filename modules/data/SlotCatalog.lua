-- EbonTransmog: equipment slot metadata shared by journal, scraper, and loadout applier.

EbonTransmog = EbonTransmog or {}
local Catalog = {}
EbonTransmog.SlotCatalog = Catalog

Catalog.LEGACY_WEAPON_SUBS = {
    mainhand = true,
    offhand = true,
    ranged = true,
}

Catalog.WEAPON_TYPES = {
    { id = "one_handed_axes", label = "1H Axes", itemSubType = "One-Handed Axes", gossip = "Main hand" },
    { id = "two_handed_axes", label = "2H Axes", itemSubType = "Two-Handed Axes", gossip = "Main hand" },
    { id = "one_handed_swords", label = "1H Swords", itemSubType = "One-Handed Swords", gossip = "Main hand" },
    { id = "two_handed_swords", label = "2H Swords", itemSubType = "Two-Handed Swords", gossip = "Main hand" },
    { id = "one_handed_maces", label = "1H Maces", itemSubType = "One-Handed Maces", gossip = "Main hand" },
    { id = "two_handed_maces", label = "2H Maces", itemSubType = "Two-Handed Maces", gossip = "Main hand" },
    { id = "daggers", label = "Daggers", itemSubType = "Daggers", gossip = "Main hand" },
    { id = "fist_weapons", label = "Fist Weapons", itemSubType = "Fist Weapons", gossip = "Main hand" },
    { id = "polearms", label = "Polearms", itemSubType = "Polearms", gossip = "Main hand" },
    { id = "staves", label = "Staves", itemSubType = "Staves", gossip = "Main hand" },
    { id = "wands", label = "Wands", itemSubType = "Wands", gossip = "Ranged" },
    { id = "bows", label = "Bows", itemSubType = "Bows", gossip = "Ranged" },
    { id = "guns", label = "Guns", itemSubType = "Guns", gossip = "Ranged" },
    { id = "crossbows", label = "Crossbows", itemSubType = "Crossbows", gossip = "Ranged" },
}

Catalog.WEAPON_SLOT_KEYS = {
    main = "weapon_main",
    off = "weapon_off",
    ranged = "weapon_ranged",
}

Catalog.WEAPON_LOADOUT_SLOTS = {
    { id = "weapon_main", label = "Main Hand" },
    { id = "weapon_off", label = "Off Hand" },
    { id = "weapon_ranged", label = "Ranged" },
}

function Catalog.IsWeaponSlotKey(subId)
    return subId == Catalog.WEAPON_SLOT_KEYS.main
        or subId == Catalog.WEAPON_SLOT_KEYS.off
        or subId == Catalog.WEAPON_SLOT_KEYS.ranged
end

function Catalog.GetWeaponBucketForMeta(meta, preferOffHand)
    if not meta or meta.category ~= "weapons" then return nil end
    local group = Catalog.GetWeaponGroupForSub(meta.sub)
    if group == "ranged" then return "ranged" end
    if preferOffHand and group == "one_handed" then return "off" end
    return "main"
end

function Catalog.WeaponBucketToSlotKey(bucket)
    return bucket and Catalog.WEAPON_SLOT_KEYS[bucket] or nil
end

function Catalog.GetLabelForWeaponSlotKey(slotKey)
    if slotKey == Catalog.WEAPON_SLOT_KEYS.main then return "Main Hand" end
    if slotKey == Catalog.WEAPON_SLOT_KEYS.off then return "Off Hand" end
    if slotKey == Catalog.WEAPON_SLOT_KEYS.ranged then return "Ranged" end
    return slotKey
end

function Catalog.GetGossipForWeaponSlotKey(slotKey, itemId)
    if slotKey == Catalog.WEAPON_SLOT_KEYS.ranged then return "Ranged" end
    if slotKey == Catalog.WEAPON_SLOT_KEYS.off then return "Off hand" end
    if itemId then
        local meta = Catalog.ResolveItemMeta(itemId)
        if meta and meta.gossip then return meta.gossip end
    end
    return "Main hand"
end

function Catalog.ClearLegacyWeaponTypeKeys(slots)
    if not slots then return end
    for subId in pairs(slots) do
        if Catalog.GetWeaponTypeById(subId) then
            slots[subId] = nil
        end
    end
end

function Catalog.NormalizeWeaponSlots(slots)
    if not slots then return end
    local main = slots[Catalog.WEAPON_SLOT_KEYS.main]
    local off = slots[Catalog.WEAPON_SLOT_KEYS.off]
    local ranged = slots[Catalog.WEAPON_SLOT_KEYS.ranged]
    for subId, itemId in pairs(slots) do
        if Catalog.GetWeaponTypeById(subId) then
            local meta = Catalog.ResolveItemMeta(itemId)
            local preferOff = meta and meta.gossip == "Off hand"
            local bucket = Catalog.GetWeaponBucketForMeta(meta, preferOff)
            slots[subId] = nil
            if bucket == "main" then main = itemId
            elseif bucket == "off" then off = itemId
            elseif bucket == "ranged" then ranged = itemId
            end
        end
    end
    slots[Catalog.WEAPON_SLOT_KEYS.main] = main
    slots[Catalog.WEAPON_SLOT_KEYS.off] = off
    slots[Catalog.WEAPON_SLOT_KEYS.ranged] = ranged
    if not main then slots[Catalog.WEAPON_SLOT_KEYS.main] = nil end
    if not off then slots[Catalog.WEAPON_SLOT_KEYS.off] = nil end
    if not ranged then slots[Catalog.WEAPON_SLOT_KEYS.ranged] = nil end
end

function Catalog.AssignWeaponToSlots(slots, itemId, preferOffHand)
    if not slots or not itemId then return nil end
    if not Catalog.PlayerCanUseWeaponItem(itemId) then return nil end
    local meta = Catalog.ResolveItemMeta(itemId)
    local bucket = Catalog.GetWeaponBucketForMeta(meta, preferOffHand)
    if not bucket then return nil end
    Catalog.ClearLegacyWeaponTypeKeys(slots)
    Catalog.NormalizeWeaponSlots(slots)
    local key = Catalog.WeaponBucketToSlotKey(bucket)
    slots[key] = itemId
    if bucket == "main" then
        local group = Catalog.GetWeaponGroupForSub(meta and meta.sub)
        if group == "two_handed" then
            slots[Catalog.WEAPON_SLOT_KEYS.off] = nil
        end
    elseif bucket == "off" then
        local mainId = slots[Catalog.WEAPON_SLOT_KEYS.main]
        if mainId and Catalog.IsTwoHandedWeaponItem(mainId) then
            slots[Catalog.WEAPON_SLOT_KEYS.main] = nil
        end
    end
    return key
end

function Catalog.RemoveWeaponItemFromSlots(slots, itemId)
    if not slots or not itemId then return false end
    Catalog.NormalizeWeaponSlots(slots)
    local removed = false
    for _, key in pairs(Catalog.WEAPON_SLOT_KEYS) do
        if slots[key] == itemId then
            slots[key] = nil
            removed = true
        end
    end
    Catalog.ClearLegacyWeaponTypeKeys(slots)
    return removed
end

function Catalog.GetWeaponLoadoutSlots()
    return Catalog.WEAPON_LOADOUT_SLOTS
end

local WEAPON_TYPE_BY_SUBTYPE = {}
local WEAPON_TYPE_BY_ID = {}
for _, weapon in ipairs(Catalog.WEAPON_TYPES) do
    WEAPON_TYPE_BY_ID[weapon.id] = weapon
    WEAPON_TYPE_BY_SUBTYPE[weapon.itemSubType:lower()] = weapon
end

local GOSSIP_SLOT_CATEGORY = {
    ["Main hand"] = "weapons",
    ["Off hand"] = "weapons",
    ["Ranged"] = "weapons",
}

Catalog.EQUIP = {
    INVTYPE_HEAD = { category = "armor", sub = "head", gossip = "Head", label = "Head" },
    INVTYPE_SHOULDER = { category = "armor", sub = "shoulder", gossip = "Shoulders", label = "Shoulders" },
    INVTYPE_BODY = { category = "armor", sub = "shirt", gossip = "Shirt", label = "Shirt" },
    INVTYPE_CHEST = { category = "armor", sub = "chest", gossip = "Chest", label = "Chest" },
    INVTYPE_ROBE = { category = "armor", sub = "chest", gossip = "Chest", label = "Chest" },
    INVTYPE_WAIST = { category = "armor", sub = "waist", gossip = "Waist", label = "Waist" },
    INVTYPE_LEGS = { category = "armor", sub = "legs", gossip = "Legs", label = "Legs" },
    INVTYPE_FEET = { category = "armor", sub = "feet", gossip = "Feet", label = "Feet" },
    INVTYPE_WRIST = { category = "armor", sub = "wrist", gossip = "Wrists", label = "Wrists" },
    INVTYPE_HAND = { category = "armor", sub = "hands", gossip = "Hands", label = "Hands" },
    INVTYPE_CLOAK = { category = "armor", sub = "back", gossip = "Back", label = "Back" },
    INVTYPE_TABARD = { category = "armor", sub = "tabard", gossip = "Tabard", label = "Tabard" },
    INVTYPE_SHIELD = { category = "armor", sub = "shield", gossip = "Off hand", label = "Shield" },
    INVTYPE_WEAPON = { category = "weapons", gossip = "Main hand" },
    INVTYPE_WEAPONMAINHAND = { category = "weapons", gossip = "Main hand" },
    INVTYPE_2HWEAPON = { category = "weapons", gossip = "Main hand" },
    INVTYPE_WEAPONOFFHAND = { category = "weapons", gossip = "Off hand" },
    INVTYPE_HOLDABLE = { category = "weapons", gossip = "Off hand" },
    INVTYPE_RANGED = { category = "weapons", gossip = "Ranged" },
    INVTYPE_RANGEDRIGHT = { category = "weapons", gossip = "Ranged" },
}

Catalog.SUBCATEGORIES = {
    armor = {
        { id = "head", label = "Head" },
        { id = "shoulder", label = "Shoulders" },
        { id = "shirt", label = "Shirt" },
        { id = "chest", label = "Chest" },
        { id = "waist", label = "Waist" },
        { id = "legs", label = "Legs" },
        { id = "feet", label = "Feet" },
        { id = "wrist", label = "Wrists" },
        { id = "hands", label = "Hands" },
        { id = "back", label = "Back" },
        { id = "tabard", label = "Tabard" },
        { id = "shield", label = "Shield" },
    },
    weapons = {},
}

for _, weapon in ipairs(Catalog.WEAPON_TYPES) do
    table.insert(Catalog.SUBCATEGORIES.weapons, { id = weapon.id, label = weapon.label })
end

Catalog.WEAPON_GROUPS = {
    one_handed = {
        label = "One-Handed",
        subs = { "one_handed_axes", "one_handed_swords", "one_handed_maces", "daggers", "fist_weapons" },
    },
    two_handed = {
        label = "Two-Handed",
        subs = { "two_handed_axes", "two_handed_swords", "two_handed_maces", "polearms", "staves" },
    },
    ranged = {
        label = "Ranged",
        subs = { "wands", "bows", "guns", "crossbows" },
    },
}

local WEAPON_SUB_TO_GROUP = {}
for groupId, group in pairs(Catalog.WEAPON_GROUPS) do
    for _, subId in ipairs(group.subs) do
        WEAPON_SUB_TO_GROUP[subId] = groupId
    end
end

function Catalog.GetWeaponGroupForSub(subId)
    return subId and WEAPON_SUB_TO_GROUP[subId] or nil
end

function Catalog.GetWeaponSubsForGroup(groupId)
    local group = groupId and Catalog.WEAPON_GROUPS[groupId]
    if not group then return {} end
    local subs = {}
    for _, subId in ipairs(group.subs) do
        local weapon = WEAPON_TYPE_BY_ID[subId]
        if weapon then
            table.insert(subs, { id = weapon.id, label = weapon.label })
        end
    end
    return subs
end

function Catalog.GetWeaponGroupOrder()
    return { "one_handed", "two_handed", "ranged" }
end

local TITANS_GRIP_SPELL_IDS = { 46917, 49152, 49149, 49150, 49151 }
local WARRIOR_DUAL_WIELD_SPELL_IDS = { 674 }

local function PlayerHasTitansGrip()
    local _, class = UnitClass("player")
    if class ~= "WARRIOR" then return false end
    if not IsSpellKnown then return false end
    for _, spellId in ipairs(TITANS_GRIP_SPELL_IDS) do
        if IsSpellKnown(spellId) then return true end
    end
    return false
end

local function PlayerKnowsAnySpell(spellIds)
    if not IsSpellKnown then return false end
    for _, spellId in ipairs(spellIds) do
        if IsSpellKnown(spellId) then return true end
    end
    return false
end

local function PlayerCanDualWieldFallback()
    local _, class = UnitClass("player")
    if class == "ROGUE" then return true end
    if class == "WARRIOR" then
        if PlayerHasTitansGrip() then return true end
        return PlayerKnowsAnySpell(WARRIOR_DUAL_WIELD_SPELL_IDS)
    end
    if class == "SHAMAN" then
        return PlayerKnowsAnySpell(WARRIOR_DUAL_WIELD_SPELL_IDS)
    end
    return false
end

function Catalog.PlayerCanDualWield()
    if type(CanDualWield) == "function" then
        local ok, canDual = pcall(CanDualWield)
        if ok and canDual then return true end
    end
    return PlayerCanDualWieldFallback()
end

function Catalog.PlayerCanUseTwoHandedWeapons()
    if Catalog.PlayerCanDualWield() then
        return PlayerHasTitansGrip()
    end
    return true
end

function Catalog.SanitizeWeaponOutfit(outfit)
    if not outfit then return end
    Catalog.NormalizeWeaponSlots(outfit)

    for key, itemId in pairs(outfit) do
        if itemId and Catalog.IsTwoHandedWeaponItem(itemId) and not Catalog.PlayerCanUseWeaponItem(itemId) then
            outfit[key] = nil
        end
    end

    local mainKey = Catalog.WEAPON_SLOT_KEYS.main
    local offKey = Catalog.WEAPON_SLOT_KEYS.off
    local mainId = outfit[mainKey]
    if mainId and Catalog.IsTwoHandedWeaponItem(mainId) then
        outfit[offKey] = nil
    end
end

function Catalog.IsTwoHandedWeaponSub(subId)
    return Catalog.GetWeaponGroupForSub(subId) == "two_handed"
end

function Catalog.IsTwoHandedWeaponItem(itemId)
    local meta = Catalog.ResolveItemMeta(itemId)
    return meta and Catalog.IsTwoHandedWeaponSub(meta.sub) or false
end

function Catalog.PlayerCanUseWeaponItem(itemId)
    if not itemId then return true end
    if Catalog.IsTwoHandedWeaponItem(itemId) then
        return Catalog.PlayerCanUseTwoHandedWeapons()
    end
    return true
end

function Catalog.GetAvailableWeaponGroups()
    if Catalog.PlayerCanUseTwoHandedWeapons() then
        return Catalog.GetWeaponGroupOrder()
    end
    return { "one_handed", "ranged" }
end

function Catalog.GetWeaponTypeBySubType(itemSubType)
    if not itemSubType or type(itemSubType) ~= "string" then return nil end
    return WEAPON_TYPE_BY_SUBTYPE[itemSubType:lower()]
end

function Catalog.GetWeaponTypeById(subId)
    return subId and WEAPON_TYPE_BY_ID[subId] or nil
end

function Catalog.IsLegacyWeaponSub(subId)
    return subId and Catalog.LEGACY_WEAPON_SUBS[subId] or false
end

function Catalog.UsesArmorTypeFilter(subId)
    if not subId then return false end
    if subId == "shirt" or subId == "tabard" or subId == "shield" or subId == "back" then return false end
    for _, sub in ipairs(Catalog.SUBCATEGORIES.armor) do
        if sub.id == subId then return true end
    end
    return false
end

local function BuildWeaponMeta(weaponType, gossipOverride)
    return {
        category = "weapons",
        sub = weaponType.id,
        gossip = gossipOverride or weaponType.gossip,
        label = weaponType.label,
    }
end

function Catalog.ResolveItemMeta(itemId, gossipOverride)
    itemId = tonumber(itemId)
    if not itemId then return nil end

    local _, _, _, _, _, itemType, itemSubType, _, equipSlot = GetItemInfo(itemId)
    local stored = EbonTransmog.AppearanceService and EbonTransmog.AppearanceService.GetStoredItemInfo(itemId)
    if stored then
        if not itemSubType or itemSubType == "" then itemSubType = stored.itemSubType or stored.subclassID end
        if not itemType or itemType == "" then itemType = stored.itemType or stored.classID end
        if not equipSlot or equipSlot == "" then equipSlot = stored.equipSlot end
    end

    if equipSlot == "INVTYPE_SHIELD" or (itemSubType and itemSubType:lower() == "shields") then
        local meta = Catalog.EQUIP.INVTYPE_SHIELD
        return {
            category = meta.category,
            sub = meta.sub,
            gossip = gossipOverride or meta.gossip,
            label = meta.label,
        }
    end

    local isWeapon = itemType == 2 or itemType == "Weapon"
        or equipSlot == "INVTYPE_WEAPON" or equipSlot == "INVTYPE_WEAPONMAINHAND"
        or equipSlot == "INVTYPE_2HWEAPON" or equipSlot == "INVTYPE_WEAPONOFFHAND"
        or equipSlot == "INVTYPE_HOLDABLE" or equipSlot == "INVTYPE_RANGED"
        or equipSlot == "INVTYPE_RANGEDRIGHT"

    if isWeapon then
        local weaponType = Catalog.GetWeaponTypeBySubType(itemSubType)
        if weaponType then
            local gossip = gossipOverride or weaponType.gossip
            if equipSlot == "INVTYPE_WEAPONOFFHAND" or equipSlot == "INVTYPE_HOLDABLE" then
                if gossipOverride then
                    gossip = gossipOverride
                elseif weaponType.id == "daggers" or weaponType.id == "one_handed_swords"
                    or weaponType.id == "one_handed_axes" or weaponType.id == "one_handed_maces" then
                    gossip = "Off hand"
                end
            end
            return BuildWeaponMeta(weaponType, gossip)
        end
    end

    if equipSlot and Catalog.EQUIP[equipSlot] and Catalog.EQUIP[equipSlot].sub then
        local meta = Catalog.EQUIP[equipSlot]
        return {
            category = meta.category,
            sub = meta.sub,
            gossip = gossipOverride or meta.gossip,
            label = meta.label,
        }
    end

    return nil
end

function Catalog.GetMetaForGossipSlot(gossipLabel)
    if not gossipLabel then return nil end
    gossipLabel = gossipLabel:gsub("^%s+", ""):gsub("%s+$", "")

    for _, meta in pairs(Catalog.EQUIP) do
        if meta.gossip == gossipLabel and meta.sub then
            return meta
        end
    end

    if GOSSIP_SLOT_CATEGORY[gossipLabel] then
        return { category = GOSSIP_SLOT_CATEGORY[gossipLabel], gossip = gossipLabel }
    end

    return nil
end

function Catalog.GetMetaForEquipSlot(equipSlot)
    return equipSlot and Catalog.EQUIP[equipSlot] or nil
end

function Catalog.GetMetaForItem(itemId)
    return Catalog.ResolveItemMeta(itemId)
end

function Catalog.GetSubcategories(category)
    return Catalog.SUBCATEGORIES[category] or {}
end

function Catalog.GetCategoryForSub(subId)
    if Catalog.IsWeaponSlotKey(subId) then return "weapons" end
    if Catalog.GetWeaponTypeById(subId) then return "weapons" end
    for _, sub in ipairs(Catalog.SUBCATEGORIES.armor) do
        if sub.id == subId then return "armor" end
    end
    return nil
end

function Catalog.GetGossipLabelForSub(subId)
    if Catalog.IsWeaponSlotKey(subId) then
        return Catalog.GetLabelForWeaponSlotKey(subId)
    end
    for _, sub in ipairs(Catalog.SUBCATEGORIES.armor) do
        if sub.id == subId then return sub.label end
    end
    local weapon = Catalog.GetWeaponTypeById(subId)
    if weapon then return weapon.label end
    return nil
end

function Catalog.GetGossipForSub(subId, itemId)
    if Catalog.IsWeaponSlotKey(subId) then
        return Catalog.GetGossipForWeaponSlotKey(subId, itemId)
    end
    if itemId and EbonTransmog.AppearanceService then
        local meta = EbonTransmog.AppearanceService.GetItemMeta(itemId)
        if meta and meta.gossip then return meta.gossip end
    end
    local weapon = Catalog.GetWeaponTypeById(subId)
    if weapon then return weapon.gossip end
    for _, meta in pairs(Catalog.EQUIP) do
        if meta.sub == subId then return meta.gossip end
    end
    return nil
end

function Catalog.GetAllGossipSlots()
    local seen, list = {}, {}
    for _, meta in pairs(Catalog.EQUIP) do
        if meta.gossip and not seen[meta.gossip] then
            seen[meta.gossip] = true
            table.insert(list, meta.gossip)
        end
    end
    table.sort(list)
    return list
end
