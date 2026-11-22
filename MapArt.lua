local ADDON, ns = ...

-- English map art (optional module).
-- The text painted on the map images follows the client language and has no API. We use
-- the original English-client images shipped with the Map Fix Forever addon (Pirson):
-- only its FOLDER needs to exist — that addon can (and should) stay disabled, otherwise it
-- swaps the maps all the time. The fileID -> file table lives in MapArtData.lua (MIT).
--
-- While the key is held with the map open: every map tile (detailTilePool) and every
-- explored area (overlayTexturePool) with a known fileID gets the English image.
-- On release: the original fileID comes back.

local MAP_ADDON = "MapFixForever"
local ART_PATH = "Interface\\AddOns\\MapFixForever\\Art\\"
local FILTER = "TRILINEAR"
local EXPLORATION_TEMPLATE = "MapExplorationPinTemplate"
ns.MAP_ADDON_URL = "https://www.curseforge.com/wow/addons/map-fix-forever"

local swapped = {} -- [texture] = { orig = original fileID, id = ..., tex = ... (state right after the swap) }

---------------------------------------------------------------------------
-- Availability
---------------------------------------------------------------------------
-- Does the Map Fix Forever folder exist (enabled or not)?
function ns.MapArtInstalled()
    if not C_AddOns or not C_AddOns.GetAddOnInfo then return false end
    local ok, name, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, MAP_ADDON)
    return ok and name ~= nil and reason ~= "MISSING"
end

-- Is that addon enabled (and therefore swapping the maps all the time)?
function ns.MapArtAddonEnabled()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(MAP_ADDON) or false
end

local function Usable()
    return ns.MAP_ART and ns.MapArtInstalled() and not ns.IsEnglishClient()
end

---------------------------------------------------------------------------
-- Swap / restore
---------------------------------------------------------------------------
local function FileID(texture)
    return texture:GetTextureFileID() or tonumber(texture:GetTexture())
end

local function SwapTexture(texture)
    local id = FileID(texture)
    local art = id and ns.MAP_ART[id]
    if not art then return end -- not a known tile (or already our image)
    texture:SetTexture(ART_PATH .. art, nil, nil, FILTER)
    -- remember how the game reports the texture now, to recognize "still ours" later
    swapped[texture] = { orig = id, id = texture:GetTextureFileID(), tex = texture:GetTexture() }
end

local function SwapPool(pool)
    if not pool then return end
    for texture in pool:EnumerateActive() do SwapTexture(texture) end
end

local function SwapMap(map)
    if not map or not map:IsShown() or not map.detailLayerPool then return end
    for layer in map.detailLayerPool:EnumerateActive() do SwapPool(layer.detailTilePool) end
    if map.EnumeratePinsByTemplate then
        for pin in map:EnumeratePinsByTemplate(EXPLORATION_TEMPLATE) do
            SwapPool(pin.overlayTexturePool)
        end
    end
end

local function Maps()
    return WorldMapFrame, BattlefieldMapFrame
end

-- Called when the key is pressed and on every sweep (0.25 s) while it is held.
function ns.MapArtSweep()
    if not Usable() then return end
    local a, b = Maps()
    pcall(SwapMap, a)
    pcall(SwapMap, b)
end

-- On key release: put the original image back wherever ours is still shown.
-- Do NOT ask the map to redraw (layer:RefreshDetailTiles() etc.): called from outside
-- Blizzard's own flow it releases every tile and then errors (nil 'mapCanvas'), leaving
-- the map empty until the player switches maps.
function ns.MapArtRestore()
    if not next(swapped) then return end
    for texture, s in pairs(swapped) do
        if texture:GetTextureFileID() == s.id and texture:GetTexture() == s.tex then
            pcall(texture.SetTexture, texture, s.orig, nil, nil, FILTER)
        end
    end
    wipe(swapped)
end

---------------------------------------------------------------------------
-- Hooks: map redrawn while the key is held (zone change, explored areas)
---------------------------------------------------------------------------
local hooked = {}

local function HookAll()
    if not hooked.detail and MapCanvasDetailLayerMixin then
        hooked.detail = true
        hooksecurefunc(MapCanvasDetailLayerMixin, "RefreshDetailTiles", function(self)
            if ns.active and Usable() then pcall(SwapPool, self.detailTilePool) end
        end)
    end
    if not hooked.exploration and MapExplorationPinMixin then
        hooked.exploration = true
        hooksecurefunc(MapExplorationPinMixin, "RefreshOverlays", function(self)
            if ns.active and Usable() then pcall(SwapPool, self.overlayTexturePool) end
        end)
    end
    for _, map in ipairs({ Maps() }) do
        if map and not hooked[map] and map.OnMapChanged then
            hooked[map] = true
            hooksecurefunc(map, "OnMapChanged", function(self)
                if ns.active and Usable() then pcall(SwapMap, self) end
            end)
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED") -- the battlefield map is load-on-demand
events:SetScript("OnEvent", function(_, event)
    HookAll()
    if event == "PLAYER_LOGIN" and ns.MapArtAddonEnabled() and not ns.IsEnglishClient() then
        C_Timer.After(3, function() ns.Print(ns.L.MSG_MAPFIX_ENABLED) end)
    end
end)
