local ADDON, ns = ...
local L = ns.L

local BINDING = "ENGLISHPEEK_HOLD"
local DEFAULT_KEY = "F12"

-- SavedVariables (account-wide):
--   welcomeShown      = welcome popup already displayed
--   defaultKeyApplied = default key (F12) already applied once
local KNOWN_DB_KEYS = { welcomeShown = true, defaultKeyApplied = true }

BINDING_NAME_ENGLISHPEEK_HOLD = L.KEYBIND_NAME

function ns.Print(...)
    print("|cff33ccff[English Peek]|r", ...)
end

function ns.IsEnglishClient()
    return GetLocale():sub(1, 2) == "en"
end

-- Display text of the bound key (e.g. "F12"), or nil.
function ns.GetKeyText()
    local key = GetBindingKey(BINDING)
    if not key then return nil end
    return GetBindingText and GetBindingText(key) or key
end

---------------------------------------------------------------------------
-- Key (Bindings.xml calls this with keystate "down"/"up")
---------------------------------------------------------------------------
function EnglishPeek_OnKey(keystate)
    if keystate == "down" then ns.Activate() else ns.Deactivate() end
end

-- First run only: bind F12 as the default key (unless the player already chose one).
local function ApplyDefaultKey()
    local db = EnglishPeekDB
    if db.defaultKeyApplied or InCombatLockdown() then return end -- in combat: retry next login
    db.defaultKeyApplied = true
    if GetBindingKey(BINDING) then return end

    local previous = GetBindingAction(DEFAULT_KEY)
    SetBinding(DEFAULT_KEY, BINDING)
    SaveBindings(GetCurrentBindingSet())

    if previous and previous ~= "" and previous ~= BINDING then
        ns.Print(L.MSG_KEY_REPLACED:format(_G["BINDING_NAME_" .. previous] or previous))
    end
end

---------------------------------------------------------------------------
-- Welcome popup (shown once; /englishpeek shows it again)
---------------------------------------------------------------------------
local function OpenKeybindings()
    local ok = false
    if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
        ok = pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID)
    end
    if not ok and KeyBindingFrame_LoadUI then
        pcall(KeyBindingFrame_LoadUI)
        if KeyBindingFrame then ShowUIPanel(KeyBindingFrame) end
    end
end

-- Map Fix Forever link in an edit box, ready to copy (addons cannot open a browser).
StaticPopupDialogs["ENGLISHPEEK_MAPS"] = {
    text = L.MAPS_OFFER,
    button1 = L.BTN_OK,
    hasEditBox = true,
    editBoxWidth = 320,
    OnShow = function(self)
        local box = self.editBox or self.EditBox
        if box then
            box:SetText(ns.MAP_ADDON_URL)
            box:HighlightText()
            box:SetFocus()
        end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["ENGLISHPEEK_WELCOME"] = {
    text = "%s",
    button1 = L.BTN_OK,
    button2 = L.BTN_CHANGE,
    OnCancel = function(_, _, reason)
        if reason == "clicked" then OpenKeybindings() end
    end,
    -- "English maps" button: only shown when Map Fix Forever is not installed
    OnAlt = function()
        C_Timer.After(0, function() StaticPopup_Show("ENGLISHPEEK_MAPS") end)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns.ShowWelcome()
    local key = ns.GetKeyText()
    local text = key and L.WELCOME:format(key) or L.WELCOME_NOKEY
    StaticPopupDialogs["ENGLISHPEEK_WELCOME"].button3 =
        (not ns.MapArtInstalled()) and L.BTN_MAPS or nil
    StaticPopup_Show("ENGLISHPEEK_WELCOME", text)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        EnglishPeekDB = EnglishPeekDB or {}
        -- keep only known keys (drops stale data from previous versions)
        for key in pairs(EnglishPeekDB) do
            if not KNOWN_DB_KEYS[key] then EnglishPeekDB[key] = nil end
        end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(2, function()
            ApplyDefaultKey()
            if not EnglishPeekDB.welcomeShown then
                EnglishPeekDB.welcomeShown = true
                ns.ShowWelcome()
            end
        end)
        -- build the indexes in the background (after Questie has initialized)
        C_Timer.After(15, function()
            if not ns.IsEnglishClient() then ns.StartBackgroundIndex() end
        end)

    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.Deactivate() -- nothing is translated during combat
    end
end)

---------------------------------------------------------------------------
-- /englishpeek
---------------------------------------------------------------------------
SLASH_ENGLISHPEEK1 = "/englishpeek"
SlashCmdList.ENGLISHPEEK = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "test" then
        if ns.active then ns.Deactivate() else ns.Activate() end -- toggle without the key (development)
    elseif msg == "status" then
        ns.PrintDiagnostics()
    else
        ns.ShowWelcome()
    end
end
