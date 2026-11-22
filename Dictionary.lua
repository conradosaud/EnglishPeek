local ADDON, ns = ...
local Q = ns.Q

-- Converts localized text -> English, in three layers:
--  1) Exact index `names` (whole text, ignoring color codes): zones, subzones, maps,
--     continents. World objects have their own index (`objectNames`), consulted ONLY
--     inside tooltips (the localized name comes from the community translation and could
--     match generic interface texts).
--  2) Per-text result cache (avoids repeating the search on every sweep).
--  3) Context candidates (quests, NPCs and items visible right now): the localized name
--     is searched INSIDE the text and replaced, preserving level, colors and state.

local names            -- ["localized name"] = "English"
local objectNames = {} -- ["localized object name"] = "English" (tooltips only)
local terms            -- ["localized term"] = "English" (classes, races, professions, weapons; always on)
local candMap = {}     -- ["localized name"] = "English" (current context)
local candList = {}    -- candMap sorted longest first
local prevCandMap = {} -- previous set, to detect exact changes
local blocked = {}     -- visible player names: never become candidates
local cache = {}       -- [text] = translation or false
local cacheSize = 0
local CACHE_LIMIT = 5000

local function AddName(loc, en)
    if type(loc) == "string" and loc ~= "" and type(en) == "string" and loc ~= en
        and not names[loc] then
        names[loc] = en
    end
end

---------------------------------------------------------------------------
-- Exact index: zones (synchronous, ~2,600 areas)
---------------------------------------------------------------------------
function ns.BuildDictionary()
    names = {}
    Q.ForEachZone(function(areaId, en)
        AddName(C_Map.GetAreaInfo(areaId), en)
        local uiMapId = Q.UiMapIdForArea(areaId)
        if uiMapId and uiMapId > 0 then
            local info = C_Map.GetMapInfo(uiMapId)
            if info then AddName(info.name, en) end
        end
        AddName(Q.TranslationLocal(en), en) -- dungeons/raids with a ready-made translation
    end)
    local continents = Q.Continents()
    if type(continents) == "table" then
        for _, en in pairs(continents) do AddName(Q.TranslationLocal(en), en) end
    end
    ns.BuildTerms()
end

---------------------------------------------------------------------------
-- Fixed terms: classes, races, professions, weapons (searched inside texts)
---------------------------------------------------------------------------
local function AddTerm(loc, en)
    if type(loc) == "string" and loc ~= "" and type(en) == "string" and loc ~= en
        and not terms[loc] then
        terms[loc] = en
    end
end

function ns.BuildTerms()
    terms = {}
    -- Classes: male and female forms come from the client itself; English = Questie key
    for en, token in pairs(Q.CLASS_TOKENS) do
        AddTerm(Q.TranslationLocal(en), en)
        if LOCALIZED_CLASS_NAMES_MALE then AddTerm(LOCALIZED_CLASS_NAMES_MALE[token], en) end
        if LOCALIZED_CLASS_NAMES_FEMALE then AddTerm(LOCALIZED_CLASS_NAMES_FEMALE[token], en) end
    end
    for _, en in ipairs(Q.TERM_KEYS) do AddTerm(Q.TranslationLocal(en), en) end
end

---------------------------------------------------------------------------
-- World-object index (background, out of combat; used in tooltips only)
-- The client has no API for object names by ID: the localized side comes from Questie.
-- NPCs/items are NOT indexed: context only (avoids translating player names).
---------------------------------------------------------------------------
local BUILD_BUDGET_MS = 3
local objectIds, objectCursor
local builder = CreateFrame("Frame")
builder:Hide()
builder:SetScript("OnUpdate", function(self)
    if InCombatLockdown() then return end
    if not names then ns.BuildDictionary() end
    if not objectIds then
        objectIds = Q.AllIds("Object") or {}
        objectCursor = 1
    end
    local deadline = debugprofilestop() + BUILD_BUDGET_MS
    while objectCursor <= #objectIds do
        local id = objectIds[objectCursor]
        objectCursor = objectCursor + 1
        local loc, en = Q.Local("Object", id), Q.EN("Object", id)
        if loc and en and loc ~= en and not objectNames[loc] then objectNames[loc] = en end
        if debugprofilestop() > deadline then return end
    end
    self:Hide()
end)

-- Numbers for /englishpeek status.
function ns.DictionaryStats()
    if not names then ns.BuildDictionary() end
    local function Count(t)
        local n = 0
        for _ in pairs(t or {}) do n = n + 1 end
        return n
    end
    local objTotal = objectIds and #objectIds or 0
    local objDone = objectIds and math.min(objectCursor - 1, objTotal) or 0
    return {
        zones = Count(names),
        terms = Count(terms),
        objects = Count(objectNames),
        objectsDone = objDone,
        objectsTotal = objTotal,
    }
end

function ns.StartBackgroundIndex()
    if not objectIds or objectCursor <= #objectIds then builder:Show() end
end

---------------------------------------------------------------------------
-- Context candidates
---------------------------------------------------------------------------
function ns.BeginCandidates()
    wipe(candMap)
    wipe(blocked)
end

function ns.AddCandidate(loc, en)
    if type(loc) == "string" and loc ~= "" and type(en) == "string" and en ~= ""
        and loc ~= en and not candMap[loc] then
        candMap[loc] = en
    end
end

-- Visible player name: an NPC with the same name is not translated while that player is
-- on screen (swapping is text-based, so it would translate the player too).
function ns.BlockCandidate(name)
    if type(name) == "string" and name ~= "" then blocked[name] = true end
end

-- Did the candidate set change since last time? (exact comparison, no allocation)
local function CandidatesChanged()
    local n = 0
    for loc, en in pairs(candMap) do
        n = n + 1
        if prevCandMap[loc] ~= en then return true end
    end
    for _ in pairs(prevCandMap) do n = n - 1 end
    return n ~= 0
end

-- Merges fixed terms, applies blocks, sorts; if the set changed, invalidates the cache.
function ns.FinishCandidates()
    if not terms then ns.BuildTerms() end
    for loc, en in pairs(terms) do
        if not candMap[loc] then candMap[loc] = en end
    end
    for name in pairs(blocked) do candMap[name] = nil end

    if not CandidatesChanged() then return end

    wipe(prevCandMap)
    wipe(candList)
    local n = 0
    for loc, en in pairs(candMap) do
        prevCandMap[loc] = en
        n = n + 1
        candList[n] = { loc = loc, en = en }
    end
    table.sort(candList, function(a, b) return #a.loc > #b.loc end)
    wipe(cache)
    cacheSize = 0
end

---------------------------------------------------------------------------
-- Translation
---------------------------------------------------------------------------
local function ReplacePlain(text, find, repl)
    local s, e = text:find(find, 1, true)
    if not s then return nil end
    return text:sub(1, s - 1) .. repl .. text:sub(e + 1)
end

-- Letter/digit (ASCII) or a byte of an accented character (UTF-8 >= 128).
local function IsWordByte(b)
    return b and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

-- Replaces every occurrence of `find` as a whole word (no letters glued before/after).
-- When an occurrence is rejected, the search restarts one byte after its start (a valid
-- occurrence may begin inside the rejected one).
local function ReplaceAll(text, find, repl)
    local s, e = text:find(find, 1, true)
    if not s then return text end
    local parts, pos = {}, 1
    while s do
        local startOk = not IsWordByte(text:byte(s - 1))
            or (s > 10 and text:sub(s - 10, s - 1):find("^|c%x%x%x%x%x%x%x%x$") ~= nil)
        if startOk and not IsWordByte(text:byte(e + 1)) then
            parts[#parts + 1] = text:sub(pos, s - 1)
            parts[#parts + 1] = repl
            pos = e + 1
            s, e = text:find(find, pos, true)
        else
            s, e = text:find(find, s + 1, true)
        end
    end
    parts[#parts + 1] = text:sub(pos)
    return table.concat(parts)
end

local function StripCodes(text)
    return strtrim((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
end

-- Returns the English text, or nil when there is no translation.
-- inTooltip: the text is inside a tooltip (enables the world-object index).
function ns.Translate(text, inTooltip)
    if not names then ns.BuildDictionary() end

    -- 1) exact name
    local core = StripCodes(text)
    local en = names[core] or (inTooltip and objectNames[core])
    if en then return ReplacePlain(text, core, en) or en end

    -- 1b) comma-separated compound name (flight points: "City, Zone"): translate each part.
    --     Short texts only (up to 3 parts of up to 40 characters), not sentences.
    if #core <= 120 and core:find(",", 1, true) then
        local parts, any, valid = {}, false, true
        for part in (core .. ","):gmatch("%s*(.-)%s*,") do
            if #part > 40 or #parts >= 3 then valid = false break end
            local p = names[part]
            if p then any = true end
            parts[#parts + 1] = p or part
        end
        if valid and any then
            local joined = table.concat(parts, ", ")
            return ReplacePlain(text, core, joined) or joined
        end
    end

    -- 2) cache
    local cached = cache[text]
    if cached ~= nil then return cached or nil end

    -- 3) context candidates contained in the text (all of them; longest first).
    --    Each occurrence becomes a "\1<index>\2" marker and only gets its English at the
    --    end, so a candidate never matches inside English inserted by another one.
    local work = text
    for i = 1, #candList do
        local c = candList[i]
        if work:find(c.loc, 1, true) then
            work = ReplaceAll(work, c.loc, "\1" .. i .. "\2")
        end
    end
    local result
    if work ~= text then
        result = work:gsub("\1(%d+)\2", function(i) return candList[tonumber(i)].en end)
    end

    if cacheSize >= CACHE_LIMIT then wipe(cache) cacheSize = 0 end
    cache[text] = result or false
    cacheSize = cacheSize + 1
    return result
end
