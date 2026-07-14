# EbonTransmog API Reference

> **Verified in-game:** 2026-07-13 (Dissipline / Rogue-Lite Live)  
> **Runtime APIs:** probed at login via `EbonTransmog.AppearanceService.ProbeAPIs()` — run `/etmog apis`.

---

## Live probe results (Ebonhold client)

| API | Available |
|-----|-----------|
| `CollectionsJournal` | **no** |
| `CollectionsMicroButton` | **no** |
| `C_TransmogCollection` | **no** |
| `GetCollectedItemAppearance` | **no** |
| `GetItemAppearanceInfo` | **no** |
| `HasTransmog` | **no** |
| `DressUpModel:TryOn` | **yes** |
| `DressUpModel:Undress` | **yes** |

**Collection mode:** gossip + chat cache (no native query API on this client).

---

## Known client behavior (Ebonhold)

| Signal | Source |
|--------|--------|
| Unlock chat | `"has been added to your appearance collection."` (system message with item link) |
| Transmogrifier NPC | Gossip slots per equipment slot with paginated appearance lists (TurnIn macros) |
| Server opcodes | No appearance opcodes in ProjectEbonholdEnhanced CS/SS (unlike echo discovery 330/530) |

---

## Populating the collection (no native API)

1. **Passive:** browsing transmog gossip records item links automatically
2. **Active scan:** open Transmogrifier gossip → `/etmog scan` (walks all slots/pages)
3. **Single page:** `/etmog harvest` imports the currently visible gossip page
4. **Chat:** new unlock system messages add items automatically

---

## EbonTransmog data stores

### `EbonTransmogDB.collectedAppearances`

Per-character collected item IDs (primary cache when no native query API exists).

```lua
EbonTransmogDB.collectedAppearances["Unknown\tCharName"][itemId] = true
```

Character key: `"Unknown\t" .. UnitName("player")` (matches ProjectEbonhold echo discovery convention).

### `EbonTransmogDB.apiProbe`

Written once per session when APIs are probed. Inspect with `/etmog apis`.

---

## Runtime API probe checklist

Run in-game after login:

```
/etmog apis
```

Or manually:

```lua
/dump CollectionsJournal
/dump CollectionsMicroButton
/dump C_TransmogCollection
/dump GetItemAppearanceInfo
/dump GetCollectedItemAppearance
/dump HasTransmog
```

---

## `EbonTransmog.AppearanceService`

| Function | Notes |
|----------|-------|
| `GetCharacterKey()` | `"Unknown\t" .. UnitName("player")` |
| `IsCollected(itemId)` | true if in live or cached collection |
| `GetCollectedItems()` | `{ [itemId] = true }` |
| `AddCollected(itemId)` | Optimistic add (chat unlock, manual) |
| `RequestSync()` | Tries native APIs; falls back to cache |
| `GetItemSlotCategory(itemId)` | `"armor"`, `"weapons"`, `"other"`, or nil |
| `GetItemsForCategory(category, searchText)` | Sorted list of collected item IDs |
| `ProbeAPIs()` | Returns availability table; prints to chat |
| `Invalidate()` | Clears in-memory cache |

### Collection source priority

1. Native `C_TransmogCollection` / `GetCollectedItemAppearance` / `HasTransmog` (if present — **not on current client**)
2. Transmogrifier gossip harvest (`GossipScraper` — passive + `/etmog scan`)
3. `EbonTransmogDB.collectedAppearances` SavedVariables cache
4. `CHAT_MSG_SYSTEM` unlock messages (optimistic add)

---

## `EbonTransmog.GossipScraper`

| Function | Notes |
|----------|-------|
| `StartScan()` | Auto-walk transmog gossip; gossip window must be open |
| `StopScan()` | Cancel active scan |
| `HarvestCurrentGossip()` | Import item links from current gossip page |
| `IsScanActive()` | Whether scan is running |

### Slash commands

| Command | Action |
|---------|--------|
| `/transmog` | Toggle journal |
| `/tmog` | Alias for `/transmog` |
| `/etmog apis` | Print API probe results |
| `/etmog scan` | Full gossip collection scan |
| `/etmog harvest` | Import current gossip page |
| `/etmog scan stop` | Cancel scan |

---

## Future server integration

If ProjectEbonhold adds appearance opcodes, register in `AppearanceService`:

```lua
-- Example (not implemented on server yet):
-- CS.REQUEST_APPEARANCE_DISCOVERY = 340
-- SS.SEND_APPEARANCE_DISCOVERY = "itemId,itemId,..."
```

Hook via `ProjectEbonhold.onEventReceived` when `ProjectEbonhold` is loaded.
