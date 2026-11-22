# English Peek — project guide for Claude Code

World of Warcraft addon **"English Peek"** for **World of Warcraft: Forever** (product `wowf`, build 1.60.1.71037, `## Interface: 16001`). Slash command: `/englishpeek`.
Original author: Conrado Saud. License: MIT (see `LICENSE`). Anyone may continue the project.

This file is the source of truth for design decisions. Read it fully before changing code. If a change contradicts a rule here, ask the user before doing it; if the user approves, update this file in the same change.

## Language
- All code, comments, identifiers, commit messages and documentation are in **English**.
- The only non-English text in the code is the localized string blocks in `Locale.lua` (e.g. `ptBR`).
- Reply to the user in the language they write in. But keep code comments in english.

## Requirements and setup
Needed to develop and test:
- **World of Warcraft: Forever** client, set to a **non-English language** (on an English client the addon does nothing).
- **Questie** and **QuestieDB** installed and enabled (required dependencies).
- This folder placed at `<WoW install>\_forever_\Interface\AddOns\EnglishPeek` (the folder name must be `EnglishPeek`).

### Map Fix Forever (optional dependency, but important)
- Addon by Pirson (MIT): https://github.com/Pirson-s-Addons/MapFixForever — CurseForge: https://www.curseforge.com/wow/addons/map-fix-forever
- It is the **only** source of English map art: the text painted on the world map images (zone labels on the map textures) cannot be changed any other way. Without it, everything else works, but the map images stay in the client language.
- Install it at `<WoW install>\_forever_\Interface\AddOns\MapFixForever` and **keep it disabled** in the AddOns list. English Peek only needs its folder (`Art\<folder>\<file>.blp`); the game loads those images even while the addon is disabled. If it is enabled, it shows English maps all the time (English Peek warns in chat).
- English Peek does **not** ship its images (Blizzard art, not redistributed); it only ships a copy of its fileID → file table (`MapArtData.lua`). That table must be re-copied when Map Fix Forever updates for a new game build (see "Map art" and "Maintenance").
- Needed to develop or test anything in `MapArt.lua` / `MapArtData.lua`.

### Other optional tools
- **Plater** — only to test nameplate translation with a third-party nameplate addon.
- **BugGrabber + BugSack** — not required; recommended to see Lua errors while developing (errors then go to BugSack instead of chat).
- An editor with WoW API annotations, e.g. VSCode with the "WoW API" extension (Ketho).

## What the addon does
While the player **holds a key** (keybind, press/release detected), names in the interface switch from the client language (e.g. ptBR) to **English in place** — the FontString text itself changes, it is not a tooltip on top. On release, the original text comes back. Chat and anything players type is **never** translated.

## Non-negotiable design decisions
These were discussed and settled. Do not propose alternatives unless the user asks.
- **Data source: Questie only** (Questie + QuestieDB, both required). Everything is instant, from Questie's data. No data collection/scanning, no switching the game language, no other databases. Whatever Questie does not cover is **not translated**.
- **Only approved exception:** English map art using the images of the optional **Map Fix Forever** addon (see "Map art").
- **Players are never translated.** NPCs only via `Creature`/`Vehicle` GUIDs; visible player names block same-named NPC candidates.
- **Combat:** the key does nothing in combat, and entering combat restores everything immediately.
- On an English client the key is ignored.
- **No custom window.** Only a welcome StaticPopup on first login ("hold F12 to try it" + "Change key" button opening Key Bindings, + "English maps" button when Map Fix Forever is missing). `/englishpeek` shows it again.
- **Default key F12**, applied once if the player has no key for the addon (in default WoW F12 = toggle backpack; the addon says in chat which action lost the key).
- **Nameplates are translated** (Blizzard and Plater). **Items are translated on every screen** where possible.
- **Never rename internal ids** (`EnglishPeek` folder/`.toc`, `EnglishPeekDB`, `ENGLISHPEEK_HOLD`, `EnglishPeek_OnKey`, `ENGLISHPEEK_*` popups): that would reset players' settings and key bindings.

## Confirmed limitations (do not reopen)
- Content Questie does not have (spells, generic UI texts, achievements, etc.) is not translated.
- Floating names above heads (when nameplates are off) cannot be translated: drawn by the 3D engine, no addon access.
- Text painted on map images has no API (`C_Map.GetMapArtLayerTextures` returns the same fileIDs on every locale) — only solvable with the Map Fix Forever images.
- Profession ranks (Apprentice, Master…) are not fixed terms: too common as words, they would cause false matches.

## Development workflow
- **Claude cannot run the game.** The user tests in-game and reports back: `/dump` output, screenshots, error messages (from chat or BugSack, if installed). When you need facts about the client API, ask the user for a specific `/dump` command instead of guessing.
- `/reload` is enough for changes to existing `.lua` files. **New files or `.toc` changes require exiting to character select** (or restarting the game).
- `/englishpeek test` toggles the translation without holding the key (handy for screenshots and debugging). `/englishpeek status` prints the diagnostics.
- The addon must coexist with other addons; never modify other addons' files.
- Everything that touches Questie or game APIs goes through `pcall` (directly or via `ns.Q` / `SafeCall`). Failures must be silent; `/englishpeek status` is where problems surface.

## Forever API (verified in-game)
- Modern API: `C_Container`, `C_Spell`, `C_Map`, `C_Item`, `C_QuestLog`, `C_LFGList`, `C_AddOns` exist. The globals `GetSpellInfo`/`GetItemInfo` do **not** exist.
- `C_Map.GetAreaInfo(id)`, `C_Map.GetMapInfo(id)`, `C_QuestLog.GetTitleForQuestID`, `EJ_GetInstanceInfo`, `GetLFGDungeonInfo` exist.
- Modern Bindings.xml: `<Binding name="..." category="ADDONS" runOnUp="true">` with `keystate`.

## English sources in Questie
1. **QuestieDB** — `Entity.GetRaw(id, field)` = **English** base data; `Entity.Get` = community translation. Entities via `LibQuestieDB.Quest/Npc/Item/Object` or the globals `QuestDB`, `NpcDB`, `ItemDB`, `ObjectDB`. Examples (same result on any locale):
   `NpcDB.GetRaw(352,"name")`="Dungar Longdrink", `subName`="Gryphon Master"; `QuestDB.GetRaw(176,"name")`="WANTED: \"Hogger\""; `ItemDB.GetRaw(6948,"name")`="Hearthstone"; `ObjectDB.GetRaw(1731,"name")`="Copper Vein".
   Text fields: Quest `name`, `objectivesText`; Npc `name`, `subName`; Item `name`; Object `name`.
2. **Questie `l10n.zoneLookup[continent][areaId]` = English name** (~2,600 areas, including subzones: Goldshire, Moonbrook…). Localized side: the client's own `C_Map.GetAreaInfo(areaId)`.
3. **Questie `l10n.translations[englishKey][locale]`** (`true` = same as English): zones, dungeons, raids, continents, classes, races, professions, weapons. The localized side comes from the table itself.
- Module access: `QuestieLoader:ImportModule("l10n")`, `QuestieLoader:ImportModule("QuestieDB")`, `ZoneDB`.

## Translation rules
- **QuestieDB provides the English side only.** The localized side comes from the client by ID whenever possible (`UnitName` + npcID from `UnitGUID`, `C_Item.GetItemNameByID`, `C_QuestLog.GetTitleForQuestID`, `C_Map.GetAreaInfo`), because the community translation may differ from the game's name.
- Exceptions where the localized side comes from Questie: Questie's own tracker (shows QuestieDB names), world objects (no client API by ID), `l10n.translations` tables.
- Matching types:
  - **Exact index** (whole text, ignoring color codes): zones/subzones, objects (tooltips only).
  - **Context candidates** (the localized name is searched INSIDE the text, preserving level/color/state): quests, NPCs, items visible right now; plus the always-on fixed terms (classes, races, professions, weapons).
  - **By parts**: comma-separated compound names (flight points "City, Zone"), up to 3 short parts.
- Sweep exclusions: chat frames, edit boxes, forbidden frames.
- Nameplates: units from `C_NamePlate.GetNamePlates()` become candidates (creature GUIDs only); `NAME_PLATE_UNIT_ADDED` translates a new nameplate immediately. Plater rewrites the name with `SetText` on unit events; the 0.25 s re-sweep reapplies it.

## How it works (data flow)
1. Key down → `EnglishPeek_OnKey("down")` → `ns.Activate()`; key up → `ns.Deactivate()`.
2. Every sweep (immediately, then every 0.25 s while held): `BeginCandidates` → `CollectContext` (what is on screen) → `FinishCandidates` (merge fixed terms, apply player blocks, sort longest first, invalidate cache if the set changed) → translate tooltips → walk every visible frame (`EnumerateFrames`) → `MapArtSweep`.
3. For each visible FontString: `ns.Translate(text)`; if it returns English, store the original and `SetText(english)`.
4. Release (or combat): restore each FontString **only if** its text is still what we applied (the game may have rewritten it), then restore the map art.

## File structure (load order = `.toc` order)
- `EnglishPeek.toc` — `## Dependencies: Questie, QuestieDB`; `## OptionalDeps: MapFixForever`; SavedVariables `EnglishPeekDB`; `## Notes` + `## Notes-ptBR`.
- `Bindings.xml` — keybind `ENGLISHPEEK_HOLD` (AddOns category, `runOnUp`) → `EnglishPeek_OnKey(keystate)`.
- `Locale.lua` — user-facing strings (`ns.L`), picked by `GetLocale()`, enUS fallback. To add a language, copy the `enUS` block under the new locale code. **Every user-visible string goes here, in all locales.**
- `Core.lua` — SavedVariables (only `welcomeShown`, `defaultKeyApplied`; unknown keys are deleted on load — add new keys to `KNOWN_DB_KEYS`), default key, welcome popup, combat handling, slash command.
- `QuestieData.lua` — `ns.Q`: the **single access point** to Questie/QuestieDB. Never call Questie from other files. `Q.EN(entity, id, field)` (GetRaw), `Q.Local` (Get), `Q.Field`/`Q.RawField` (tables), `Q.AllIds`, zones, `Q.TERM_KEYS`, `Q.CLASS_TOKENS`. **Resilience** (the addon may end up unmaintained): entities via `LibQuestieDB.<X>` falling back to globals; contract checked with `LibQuestieDB.RequireContract(4)`; modules via `QuestieLoader:ImportModule` falling back to `QuestieLoader._modules`; internal tables (`zoneLookup`, `translations`, `continentLookup`) via the known path and, if missing, a **fingerprint search** across all modules (area 12 = "Elwynn Forest"; "Warrior"/"Elwynn Forest" with `enUS`; continents [1]="Eastern Kingdoms"). `Q.sources` records normal/alternative/nil.
- `Dictionary.lua` — `ns.Translate(text, inTooltip)` in 3 layers: exact index `names` (zones, built synchronously) + `objectNames` (objects, built in background 3 ms/frame out of combat, **consulted in tooltips only** — the localized name comes from the community translation and could match UI texts) → per-text cache (invalidated by exact comparison of the candidate set) → context candidates (all occurrences, whole word only; a glued color code counts as a boundary; replacement via `"\1" .. index .. "\2"` markers so a candidate never matches inside another's English).
- `Context.lua` — collects candidates from what is visible: quests from the log/dialog/gossip (+ linked NPCs/objects/items: startedBy, finishedBy, objectives, sourceItemId, requiredSourceItems), objectives text, NPCs from units (target, mouseover, focus, npc, soft targets, party targets, nameplates), items from merchant/buyback, loot, rolls, quest window, log rewards, trade, auction house, mail, professions, tooltips. **To support a new screen, add a collector to `ITEM_COLLECTORS` (or a similar function) — nothing else needs to change.**
- `MapArtData.lua` — `ns.MAP_ART[fileID] = "folder\\file"` (1554 textures, build 1.60.1.69913), copied from Map Fix Forever's `Data/Data.lua` with its MIT notice on top. Data only.
- `MapArt.lua` — map art swap: `ns.MapArtSweep()` (called by the sweep) and `ns.MapArtRestore()` (on release); hooks on `MapCanvasDetailLayerMixin.RefreshDetailTiles`, `MapExplorationPinMixin.RefreshOverlays` and `OnMapChanged`.
- `Swapper.lua` — `ns.Activate`/`ns.Deactivate`, the screen sweep, tooltip hooks (TooltipDataProcessor + OnTooltipSetItem/Unit/OnShow), nameplate event.
- `Diagnostics.lua` — `/englishpeek status`: QuestieDB (response + contract), zones, terms, continents, ZoneDB, objects (index progress), key, Map Fix Forever. On login (+20 s) it only warns in chat if something **essential** failed (QuestieDB or zones).

## Map art (optional module)
- Uses the original English images shipped by **Map Fix Forever** (Pirson, MIT, https://github.com/Pirson-s-Addons/MapFixForever): `Interface\AddOns\MapFixForever\Art\<folder>\<file>.blp`, 55 maps (`*_c60`, hyjal_camelot, zephrasisle).
- The game loads images from that folder even with Map Fix Forever **disabled** → players should keep it disabled (when enabled it swaps the maps all the time; the addon warns in chat).
- Its `ns.ART` table is private (addon namespace), so it is copied into `MapArtData.lua` (MIT requires keeping the notice). The images are **not** copied (Blizzard art; we do not redistribute it).
- Detection: `C_AddOns.GetAddOnInfo("MapFixForever")` (reason ~= "MISSING").
- Restore: on swap, store the original fileID and how the game reports the texture right after the swap (`GetTextureFileID`/`GetTexture`); on release, put the original back where that state is unchanged (if it changed, the game already reassigned that texture). **Never call `RefreshDetailTiles`/`RefreshOverlays` directly** to force a redraw: outside Blizzard's own flow `RefreshDetailTiles` releases every tile and then errors (nil `mapCanvas`), leaving the map empty. `GetTexture()` does not return the addon file path, so "is this our image?" must be answered by comparing that stored state, not by looking at the path.

## Maintenance after game/Questie patches
1. Update `## Interface` in the `.toc` to the client's value (`/dump select(4, GetBuildInfo())`). Otherwise the game flags the addon as out of date.
2. Run `/englishpeek status`:
   - "alternative location" = Questie moved a table (still works; update the known path in `QuestieData.lua`).
   - "not found" = that part stopped working; find where Questie moved it.
   - QuestieDB contract warning = check `QuestieDB/src/config.lua` and the API used in `QuestieData.lua`.
3. Map art: when Map Fix Forever updates its table, re-copy its `Data/Data.lua` into `MapArtData.lua` (rename `ns.ART` to `ns.MAP_ART`, keep the MIT header, update the build number in the header comment).

## Release process
- Bump `## Version` in `EnglishPeek.toc` and add an entry to `CHANGELOG.md`.
- The release zip must contain a single top-level folder `EnglishPeek/` with only the addon files: `.toc`, `Bindings.xml`, `*.lua`, `Textures/` (in-game icon, `## IconTexture`), `LICENSE`, `README.md`. `media/` holds source art (icon PNGs/TGA, README GIF) kept in git only. **Never ship** `.git/`, `.gitignore`, `.vscode/`, `CLAUDE.md`, `.claude/`, `.pkgmeta`, `.github/`, `media/` (README images/GIFs).
- Published on CurseForge (manual upload of that zip). Optional automation: BigWigs Packager (`.pkgmeta` + GitHub Actions + `CF_API_KEY` secret + `## X-Curse-Project-ID` in the `.toc`).
- Git: only commit/push when the user asks.

## Roadmap (ideas, not commitments)
- Options panel: modifier-key alternative (e.g. hold Alt), list of ignored windows.
- More locales in `Locale.lua` (only the addon's own messages; translation itself already works for any locale Questie supports).
