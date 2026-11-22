local ADDON, ns = ...
local L = ns.L
local Q = ns.Q

-- Self-diagnostics: `/englishpeek status` lists what is working; on login it only speaks up in
-- chat if something essential failed (failures are silent by design: pcall everywhere).

local OK = "|cff00ff00" .. "OK" .. "|r"
local WARN = "|cffffff00" .. "!" .. "|r"
local FAIL = "|cffff4444" .. "X" .. "|r"

local function SourceText(source)
    if source == "normal" then return L.DIAG_SRC_NORMAL end
    if source == "alternative" then return L.DIAG_SRC_ALT end
    return L.DIAG_SRC_NONE
end

-- Returns the list of lines {status, text} and whether an essential part failed.
function ns.RunDiagnostics()
    local lines, critical = {}, false
    local function Add(status, text) lines[#lines + 1] = { status, text } end

    if ns.IsEnglishClient() then
        Add(WARN, L.DIAG_ENGLISH)
    end

    -- QuestieDB (quests, NPCs, items, objects)
    local hasDB, contractOk, sample = Q.QuestieDBStatus()
    if hasDB and sample then
        Add(contractOk == false and WARN or OK,
            contractOk == false and L.DIAG_QDB_CONTRACT or L.DIAG_QDB_OK)
    else
        Add(FAIL, L.DIAG_QDB_FAIL)
        critical = true
    end

    -- Indexes
    local stats = ns.DictionaryStats()
    local zonesSrc = Q.sources.zones
    if zonesSrc and stats.zones > 0 then
        Add(zonesSrc == "normal" and OK or WARN, L.DIAG_ZONES:format(stats.zones, SourceText(zonesSrc)))
    else
        Add(FAIL, L.DIAG_ZONES_FAIL)
        critical = true
    end

    local trSrc = Q.sources.translations
    Add(trSrc == "normal" and OK or (trSrc and WARN or FAIL),
        L.DIAG_TERMS:format(stats.terms, SourceText(trSrc)))
    Add(Q.sources.continents == "normal" and OK or WARN, L.DIAG_CONTINENTS:format(SourceText(Q.sources.continents)))
    Add(Q.sources.zoneDB and OK or WARN, L.DIAG_ZONEDB:format(SourceText(Q.sources.zoneDB)))

    if stats.objectsTotal > 0 and stats.objectsDone >= stats.objectsTotal then
        Add(OK, L.DIAG_OBJECTS:format(stats.objects))
    else
        Add(WARN, L.DIAG_OBJECTS_BUILDING:format(stats.objectsDone, stats.objectsTotal))
    end

    -- Key
    local key = ns.GetKeyText()
    Add(key and OK or WARN, key and L.DIAG_KEY:format(key) or L.DIAG_NOKEY)

    -- Map art (optional)
    if not ns.MapArtInstalled() then
        Add(WARN, L.DIAG_MAPS_MISSING)
    elseif ns.MapArtAddonEnabled() then
        Add(WARN, L.DIAG_MAPS_ENABLED)
    else
        Add(OK, L.DIAG_MAPS_OK)
    end

    return lines, critical
end

function ns.PrintDiagnostics()
    local lines = ns.RunDiagnostics()
    ns.Print(L.DIAG_TITLE)
    for _, line in ipairs(lines) do
        print("   " .. line[1] .. " " .. line[2])
    end
end

-- On login (after Questie and the object index had time to initialize):
-- only speaks up if something essential failed.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    C_Timer.After(20, function()
        if ns.IsEnglishClient() then return end
        local ok, _, critical = pcall(ns.RunDiagnostics)
        if ok and critical then ns.Print(L.DIAG_LOGIN_WARN) end
    end)
end)
