# EbonTransmog

Browse collected transmog appearances, build saved loadouts, preview gear on your character, and apply loadouts at the Warpweaver on **Ebonhold** (WotLK 3.3.5).

**Author:** Gooby (aka Diss)  
**Version:** 1.0.0

## Installation

Copy the `EbonTransmog` folder into:

```
World of Warcraft/Interface/AddOns/EbonTransmog/
```

Enable the addon on the character select screen, then `/reload` in game.

## Opening the journal

- `/transmog` or `/tmog`
- Minimap button (retail transmog wardrobe icon; drag to reposition)
- Transmog Journal micro button on the main menu bar (when available)

## Populating your collection

Ebonhold does not expose retail-style collection APIs. The addon builds your appearance list from:

1. **Passive harvest** — item links are recorded while you browse Warpweaver gossip
2. **Full scan** — open Warpweaver gossip, then `/etmog scan`
3. **Current page** — `/etmog harvest`
4. **Chat unlocks** — `"has been added to your appearance collection"` messages

### Scan commands

| Command | Description |
|---------|-------------|
| `/etmog scan` | Scan all slots and pages |
| `/etmog scan fast` | Faster scan (skips page rewind) |
| `/etmog scan slot` | Scan only the slot list currently open in gossip |
| `/etmog scan head chest` | Scan specific slots only |
| `/etmog scan stop` | Cancel an active scan |

## Using the journal

### Browse and assign

1. Pick **Armor** or **Weapons**, then a slot or weapon type from the filter rows
2. Narrow with search, rarity, and armor type (where applicable)
3. Click an icon to assign it to the active slot in your draft
4. **Ctrl+click** previews on the character model; **Shift+click** links the item in chat
5. **Right-click** a slot row in the left panel to clear that assignment

The left panel shows slots for the selected category only (**Armor Slots** or **Weapon Slots**).

### Saved loadouts

| Control | Action |
|---------|--------|
| **Save** | Save the current draft under the name in the text box |
| **New** | Clear the draft |
| **Load** dropdown | Load a saved profile into the draft, or pick **Apply: …** |
| **Apply** | Queue the named loadout (or current draft) for the Warpweaver |
| **Delete** | Delete the named loadout (confirmation required) |

## Applying at the Warpweaver

Because the journal window blocks clicking NPCs, **Apply closes the journal** and queues the loadout.

1. Click **Apply** (or choose **Apply: ProfileName** from the Load dropdown)
2. Talk to the Warpweaver
3. Keep the gossip window open while the addon walks slots automatically
4. Watch chat for progress (`Applying 3/8 — Chest`, etc.)

Slash alternative:

```
/etmog apply MyLoadout
/etmog apply cancel
```

## Slash commands

| Command | Description |
|---------|-------------|
| `/transmog`, `/tmog` | Toggle journal |
| `/etmog apis` | Print API probe results |
| `/etmog scan …` | Collection scan (see above) |
| `/etmog harvest` | Import current gossip page |
| `/etmog apply <name>` | Queue loadout apply at Warpweaver |
| `/etmog apply cancel` | Cancel queued apply |

## Saved data

Per-character data is stored in `EbonTransmogDB` (SavedVariables):

- `collectedAppearances` — collected item IDs
- `loadouts` — saved slot → item profiles
- `itemInfoCache` — cached item metadata for faster filtering
- `minimapAngle` — minimap button position (degrees)

## Developer notes

See [API.md](API.md) for module references and collection behavior.
