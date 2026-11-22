local ADDON, ns = ...
local originals = {}   -- [fontString] = original text
local applied = {}     -- [fontString] = English text we applied
local excludedCache = setmetatable({}, { __mode = "k" })
local ticker

-- Re-sweep interval while the key is held (catches windows opened afterwards).
local SWEEP_INTERVAL = 0.25

-- Frames (and their descendants) that are never translated: chat.
-- Nameplates ARE translated (only NPC names become candidates; players never do).
local EXCLUDED_PREFIXES = {
    "ChatFrame", "GeneralDockManager", "ChatConfig",
}

local issecret = issecretvalue or function() return false end

local function IsExcluded(frame)
    local cached = excludedCache[frame]
    if cached ~= nil then return cached end
    local result = false
    local f, depth = frame, 0
    while f and depth < 25 do
        if f:IsForbidden() then result = true break end
        local name = f:GetName()
        if name then
            for _, prefix in ipairs(EXCLUDED_PREFIXES) do
                if name:sub(1, #prefix) == prefix then result = true break end
            end
            if result then break end
        end
        f = f:GetParent()
        depth = depth + 1
    end
    excludedCache[frame] = result
    return result
end

-- Swaps the text of one FontString. Returns true if anything changed.
-- inTooltip: enables the world-object index (only meaningful inside tooltips).
local function SwapFontString(fs, inTooltip)
    if not fs:IsVisible() then return false end
    local text = fs:GetText()
    if not text or text == "" or issecret(text) then return false end
    if applied[fs] == text then return false end -- already swapped
    local en = ns.Translate(text, inTooltip)
    if en and en ~= text then
        originals[fs] = text
        applied[fs] = en
        fs:SetText(en)
        return true
    end
    return false
end

-- Walks the regions passed as varargs (avoids allocating a table per frame).
local function SwapRegions(inTooltip, ...)
    local changed = false
    for i = 1, select("#", ...) do
        local r = select(i, ...)
        if r:GetObjectType() == "FontString" and SwapFontString(r, inTooltip) then changed = true end
    end
    return changed
end

local function SwapFrame(frame, inTooltip)
    if frame:IsForbidden() or not frame:IsVisible() then return false end
    if frame:GetObjectType() == "EditBox" or IsExcluded(frame) then return false end
    return SwapRegions(inTooltip, frame:GetRegions())
end

-- Walks every visible frame, swapping the texts that have a translation.
local function SweepScreen()
    if InCombatLockdown() then ns.Deactivate() return end
    ns.BeginCandidates()
    ns.CollectContext()
    ns.FinishCandidates()
    -- tooltips first: if they changed, Show() recomputes their size
    for _, name in ipairs(ns.TOOLTIPS) do
        local tt = _G[name]
        if tt and tt:IsShown() then
            local ok, changed = pcall(SwapFrame, tt, true)
            if ok and changed then tt:Show() end
        end
    end
    local frame = EnumerateFrames()
    while frame do
        pcall(SwapFrame, frame)
        frame = EnumerateFrames(frame)
    end
    ns.MapArtSweep() -- map art (when Map Fix Forever is installed)
end

function ns.Activate()
    if ns.active then return end
    if ns.IsEnglishClient() or InCombatLockdown() then return end
    ns.active = true
    SweepScreen()
    ticker = C_Timer.NewTicker(SWEEP_INTERVAL, SweepScreen)
end

function ns.Deactivate()
    if not ns.active then return end
    ns.active = false
    if ticker then ticker:Cancel() ticker = nil end
    ns.MapArtRestore()
    for fs, orig in pairs(originals) do
        -- only restore if the game did not rewrite the text in the meantime
        if fs:GetText() == applied[fs] then fs:SetText(orig) end
    end
    wipe(originals)
    wipe(applied)
end

---------------------------------------------------------------------------
-- Tooltips: translate as soon as their content changes (no waiting for the sweep)
---------------------------------------------------------------------------
local inTooltipUpdate = false

local function OnTooltipChanged(tt)
    if not ns.active or inTooltipUpdate or InCombatLockdown() then return end
    inTooltipUpdate = true
    ns.CollectTooltip(tt)
    ns.FinishCandidates()
    local ok, changed = pcall(SwapFrame, tt, true)
    if ok and changed then tt:Show() end
    inTooltipUpdate = false
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
        TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tt)
            OnTooltipChanged(tt)
        end)
    end
    for _, name in ipairs(ns.TOOLTIPS) do
        local tt = _G[name]
        if tt then
            for _, script in ipairs({ "OnTooltipSetItem", "OnTooltipSetUnit", "OnShow" }) do
                if tt:HasScript(script) then tt:HookScript(script, OnTooltipChanged) end
            end
        end
    end
end

HookTooltips()

---------------------------------------------------------------------------
-- Nameplates: translate them as soon as they appear (while the key is held)
---------------------------------------------------------------------------
-- Swaps the texts of a frame and all of its descendants.
local function SwapTree(frame, depth)
    depth = depth or 0
    if depth > 8 or not frame then return end
    pcall(SwapFrame, frame)
    local children = { frame:GetChildren() }
    for i = 1, #children do SwapTree(children[i], depth + 1) end
end

local plateEvents = CreateFrame("Frame")
plateEvents:RegisterEvent("NAME_PLATE_UNIT_ADDED")
plateEvents:SetScript("OnEvent", function(_, _, unit)
    if not ns.active then return end
    -- wait one frame: Plater/Blizzard write the name during this same event
    C_Timer.After(0, function()
        if not ns.active or InCombatLockdown() then return end
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if not plate then return end
        ns.AddUnit(unit)
        ns.FinishCandidates()
        SwapTree(plate)
    end)
end)
