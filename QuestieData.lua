local ADDON, ns = ...

-- Single access point to Questie/QuestieDB. Everything is wrapped in pcall: if Questie
-- changes, the addon just stops translating that part, without raising errors.
--
-- QuestieDB: Entity.GetRaw(id, field) = ENGLISH base data; Entity.Get = community translation.
-- Entities: "Quest", "Npc", "Item", "Object".
--
-- Resilience to Questie updates (the addon may end up unmaintained):
--  * QuestieDB: public API (LibQuestieDB.<Entity>), falling back to the globals
--    QuestDB/NpcDB/ItemDB/ObjectDB, plus a contract check (RequireContract).
--  * Questie INTERNALS (l10n.zoneLookup, l10n.translations, continentLookup): the known
--    path first; if it disappears, search every Questie module for the table by
--    "fingerprint" (known content), surviving renames/moves.
--  * Q.sources records where each source came from ("normal", "alternative", nil) for /englishpeek status.
local Q = {}
ns.Q = Q
Q.sources = {}

-- QuestieDB contract version this addon was written against (see QuestieDB/src/config.lua).
local QUESTIEDB_CONTRACT = 4

local function Entity(name)
    local lib = _G.LibQuestieDB
    local entity = lib and lib[name]
    if type(entity) == "table" then return entity end
    entity = _G[name .. "DB"] -- QuestDB, NpcDB, ItemDB, ObjectDB
    if type(entity) == "table" then return entity end
end

local function Import(module)
    local loader = _G.QuestieLoader
    if type(loader) ~= "table" then return nil end
    if loader.ImportModule then
        local ok, mod = pcall(loader.ImportModule, loader, module)
        if ok and type(mod) == "table" then return mod end
    end
    local mods = loader._modules
    if type(mods) == "table" and type(mods[module]) == "table" then return mods[module] end
end

-- Searches every Questie module (and its .private) for a table field satisfying `test`.
-- Shallow (1 level) and only called when the known path fails.
local function FindTable(test)
    local loader = _G.QuestieLoader
    local mods = type(loader) == "table" and loader._modules
    if type(mods) ~= "table" then return nil end
    for _, mod in pairs(mods) do
        if type(mod) == "table" then
            for _, holder in ipairs({ mod, type(mod.private) == "table" and mod.private or nil }) do
                for _, v in pairs(holder) do
                    if type(v) == "table" then
                        local ok, match = pcall(test, v)
                        if ok and match then return v end
                    end
                end
            end
        end
    end
end

-- Resolves a source once (normal -> alternative) and caches it.
local cache = {}
local function Resolve(key, normal, test)
    if cache[key] ~= nil then return cache[key] or nil end
    local t = normal()
    local ok, match = false, false
    if type(t) == "table" then ok, match = pcall(test, t) end
    if ok and match then
        Q.sources[key] = "normal"
    else
        t = FindTable(test)
        Q.sources[key] = t and "alternative" or nil
    end
    cache[key] = t or false
    return t
end

-- Fingerprints (stable, well-known content of each table).
local function IsZoneLookup(t) -- [continent][areaId] = "English"; area 12 = Elwynn Forest
    for _, zones in pairs(t) do
        if type(zones) == "table" and zones[12] == "Elwynn Forest" then return true end
    end
end

local function IsTranslations(t) -- ["English"] = { enUS = true, ptBR = "...", ... }
    local e = t["Warrior"] or t["Elwynn Forest"]
    return type(e) == "table" and e.enUS ~= nil
end

local function IsContinents(t)
    return t[1] == "Eastern Kingdoms" and t[2] == "Kalimdor"
end

local function ZoneLookup()
    return Resolve("zones", function() local l = Import("l10n") return l and l.zoneLookup end, IsZoneLookup)
end

local function Translations()
    return Resolve("translations", function() local l = Import("l10n") return l and l.translations end,
        IsTranslations)
end

-- Does QuestieDB respond, and is its contract compatible?
function Q.QuestieDBStatus()
    local lib = _G.LibQuestieDB
    local contractOk = nil
    if type(lib) == "table" and lib.RequireContract then
        local ok, res = pcall(lib.RequireContract, QUESTIEDB_CONTRACT)
        contractOk = ok and res and true or false
    end
    local sample = nil
    local quest = Entity("Quest")
    if quest and quest.GetRaw then
        local ok, v = pcall(quest.GetRaw, 176, "name") -- "WANTED: \"Hogger\""
        sample = ok and type(v) == "string" and v ~= ""
    end
    return Entity("Quest") ~= nil, contractOk, sample
end

local function Call(entityName, method, id, field)
    local entity = Entity(entityName)
    local fn = entity and entity[method]
    if not fn or type(id) ~= "number" then return nil end
    local ok, v = pcall(fn, id, field)
    if ok then return v end
end

local function NonEmpty(v)
    if type(v) == "string" and v ~= "" then return v end
end

-- English text (e.g. Q.EN("Npc", 352, "subName")). Default field = "name".
function Q.EN(entityName, id, field)
    return NonEmpty(Call(entityName, "GetRaw", id, field or "name"))
end

-- Localized text from Questie's community translation.
function Q.Local(entityName, id, field)
    return NonEmpty(Call(entityName, "Get", id, field or "name"))
end

-- Non-text field (ID tables etc.), with corrections applied.
function Q.Field(entityName, id, field)
    return Call(entityName, "Get", id, field)
end

-- Non-text field from the base data (for texts stored in tables, e.g. English objectivesText).
function Q.RawField(entityName, id, field)
    return Call(entityName, "GetRaw", id, field)
end

function Q.AllIds(entityName)
    local entity = Entity(entityName)
    if not entity or not entity.GetAllIds then return nil end
    local ok, ids = pcall(entity.GetAllIds)
    if ok and type(ids) == "table" then return ids end
end

---------------------------------------------------------------------------
-- Zones (Questie modules)
---------------------------------------------------------------------------
-- Walks Questie's zone table: callback(areaId, englishName)
function Q.ForEachZone(callback)
    local lookup = ZoneLookup()
    if type(lookup) ~= "table" then return end
    for _, zones in pairs(lookup) do
        if type(zones) == "table" then
            for areaId, en in pairs(zones) do
                if type(areaId) == "number" and NonEmpty(en) then callback(areaId, en) end
            end
        end
    end
end

-- uiMapID for an area (to get the localized map name). Optional: without it, map names
-- that match the area name are still covered.
function Q.UiMapIdForArea(areaId)
    local zoneDB = Import("ZoneDB")
    if not zoneDB or not zoneDB.GetUiMapIdByAreaId then
        Q.sources.zoneDB = nil
        return nil
    end
    Q.sources.zoneDB = "normal"
    local ok, id = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaId)
    return ok and id or nil
end

-- Ready-made translations: translations[englishKey][locale] -> localized text or nil.
function Q.TranslationLocal(englishKey)
    local translations = Translations()
    local entry = translations and translations[englishKey]
    if type(entry) ~= "table" then return nil end
    return NonEmpty(entry[GetLocale()])
end

---------------------------------------------------------------------------
-- Fixed terms (English keys of Questie's l10n.translations)
-- Sources: Questie/Localization/Translations/{Classes,Races,Professions,WeaponSkills}.lua
---------------------------------------------------------------------------
-- Class (Questie key) -> client token (to get the male/female forms from the client).
Q.CLASS_TOKENS = {
    ["Warrior"] = "WARRIOR", ["Paladin"] = "PALADIN", ["Shaman"] = "SHAMAN",
    ["Rogue"] = "ROGUE", ["Mage"] = "MAGE", ["Druid"] = "DRUID", ["Priest"] = "PRIEST",
    ["Hunter"] = "HUNTER", ["Warlock"] = "WARLOCK", ["Death Knight"] = "DEATHKNIGHT",
    ["Monk"] = "MONK",
}

Q.TERM_KEYS = {
    -- Races
    "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll", "Goblin",
    "Draenei", "Blood Elf", "Worgen", "Pandaren", "High Order Skyborne", "Windshaper Skyborne",
    -- Professions and trainers (ranks like Apprentice/Master are left out: too common as words)
    "First Aid", "First Aid Trainer", "Blacksmithing", "Blacksmithing Trainer",
    "Leatherworking", "Leatherworking Trainer", "Alchemy", "Alchemy Trainer",
    "Herbalism", "Herbalism Trainer", "Cooking", "Cooking Trainer", "Mining", "Mining Trainer",
    "Tailoring", "Tailoring Trainer", "Engineering", "Engineering Trainer",
    "Enchanting", "Enchanting Trainer", "Fishing", "Fishing Trainer", "Skinning", "Skinning Trainer",
    "Jewelcrafting", "Jewelcrafting Trainer", "Riding", "Riding Trainer",
    "Inscription", "Inscription Trainer", "Archaeology", "Archaeology Trainer",
    "Armorsmith", "Weaponsmith", "Elixir Master", "Potion Master", "Transmutation Master",
    "Gnomish Engineer", "Goblin Engineer", "Dragonscale Leatherworking",
    "Elemental Leatherworking", "Tribal Leatherworking", "Mooncloth Tailoring",
    "Shadoweave Tailoring", "Spellfire Tailoring",
    -- Weapon skills
    "One-Handed Swords", "One-Handed Maces", "One-Handed Axes", "Two-Handed Swords",
    "Two-Handed Maces", "Two-Handed Axes", "Fist Weapons", "Daggers", "Thrown", "Bows",
    "Crossbows", "Guns", "Staves", "Polearms",
}

function Q.Continents()
    return Resolve("continents", function() local l = Import("l10n") return l and l.continentLookup end,
        IsContinents)
end
