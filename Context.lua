local ADDON, ns = ...
local Q = ns.Q

-- Discovers what is visible on screen (quests, NPCs, items) and registers the
-- "localized name -> English" pairs as candidates (ns.AddCandidate).
-- Rule: English always from QuestieDB (GetRaw); localized side from the client by ID when
-- an API exists, plus Questie's translated name (that is what Questie shows in its own UI).

local Add = function(loc, en) ns.AddCandidate(loc, en) end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
end

local function ItemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

---------------------------------------------------------------------------
-- Entities
---------------------------------------------------------------------------
function ns.AddItem(id, shownName)
    id = tonumber(id)
    if not id then return end
    local en = Q.EN("Item", id)
    if not en then return end
    Add(shownName, en)
    if C_Item and C_Item.GetItemNameByID then Add(SafeCall(C_Item.GetItemNameByID, id), en) end
    Add(Q.Local("Item", id), en)
end

function ns.AddItemLink(link)
    ns.AddItem(ItemIdFromLink(link))
end

function ns.AddNpc(id, shownName)
    id = tonumber(id)
    if not id then return end
    local en = Q.EN("Npc", id)
    if en then
        Add(shownName, en)
        Add(Q.Local("Npc", id), en)
    end
    local subEn = Q.EN("Npc", id, "subName") -- title: "Gryphon Master", "Banker"…
    if subEn then Add(Q.Local("Npc", id, "subName"), subEn) end
end

function ns.AddObject(id)
    id = tonumber(id)
    if not id then return end
    Add(Q.Local("Object", id), Q.EN("Object", id))
end

-- NPC ID of a unit (creatures only: players and pets are never translated).
local function NpcIdFromUnit(unit)
    local guid = SafeCall(UnitGUID, unit)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, npcId = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(npcId) end
end

function ns.AddUnit(unit)
    local id = NpcIdFromUnit(unit)
    if id then
        ns.AddNpc(id, SafeCall(UnitName, unit))
    elseif SafeCall(UnitIsPlayer, unit) then
        -- visible player: an NPC with the same name is not translated (swapping is text-based)
        ns.BlockCandidate(SafeCall(UnitName, unit))
    end
end

---------------------------------------------------------------------------
-- Quests and everything linked to them (objectives, quest givers/turn-ins, items)
---------------------------------------------------------------------------
local relations = {} -- [questID] = { npcs = {}, objects = {}, items = {} } (cache)

local function AppendIds(list, ids)
    if type(ids) ~= "table" then return end
    for _, id in ipairs(ids) do
        if type(id) == "number" then list[#list + 1] = id end
    end
end

local function GetRelations(questId)
    local r = relations[questId]
    if r then return r end
    r = { npcs = {}, objects = {}, items = {} }

    -- startedBy/finishedBy: { npcIds?, objectIds?, itemIds? }
    for _, field in ipairs({ "startedBy", "finishedBy" }) do
        local givers = Q.Field("Quest", questId, field)
        if type(givers) == "table" then
            AppendIds(r.npcs, givers[1])
            AppendIds(r.objects, givers[2])
            AppendIds(r.items, givers[3])
        end
    end

    -- objectives: { creatures, objects, items, reputation, kill-credit, spell }
    local obj = Q.Field("Quest", questId, "objectives")
    if type(obj) == "table" then
        for _, e in ipairs(type(obj[1]) == "table" and obj[1] or {}) do AppendIds(r.npcs, { e[1] }) end
        for _, e in ipairs(type(obj[2]) == "table" and obj[2] or {}) do AppendIds(r.objects, { e[1] }) end
        for _, e in ipairs(type(obj[3]) == "table" and obj[3] or {}) do AppendIds(r.items, { e[1] }) end
        for _, e in ipairs(type(obj[5]) == "table" and obj[5] or {}) do
            AppendIds(r.npcs, e[1])
            AppendIds(r.npcs, { e[2] })
        end
    end

    AppendIds(r.items, { Q.Field("Quest", questId, "sourceItemId") })
    AppendIds(r.items, Q.Field("Quest", questId, "requiredSourceItems"))

    relations[questId] = r
    return r
end

function ns.AddQuest(id, shownTitle)
    id = tonumber(id)
    if not id or id == 0 then return end
    local en = Q.EN("Quest", id)
    if en then
        Add(shownTitle, en)
        Add(SafeCall(C_QuestLog.GetTitleForQuestID, id), en)
        Add(Q.Local("Quest", id), en) -- name shown by Questie's tracker
    end
    local r = GetRelations(id)
    for _, n in ipairs(r.npcs) do ns.AddNpc(n) end
    for _, o in ipairs(r.objects) do ns.AddObject(o) end
    for _, i in ipairs(r.items) do ns.AddItem(i) end
end

-- Objectives text (the "Kill 10 wolves and return…" paragraph): localized side as shown by the client.
local function AddObjectivesText(questId, shownText)
    questId = tonumber(questId)
    if not questId or type(shownText) ~= "string" or shownText == "" then return end
    local raw = Q.RawField("Quest", questId, "objectivesText")
    local en
    if type(raw) == "table" then
        en = table.concat(raw, " ")
    elseif type(raw) == "string" then
        en = raw
    end
    if en and en ~= "" then Add(shownText, en) end
end

local function SelectedLogQuestId()
    if C_QuestLog.GetSelectedQuest then
        local id = SafeCall(C_QuestLog.GetSelectedQuest)
        if id and id ~= 0 then return id end
    end
    if GetQuestLogSelection and GetQuestLogTitle then
        local index = SafeCall(GetQuestLogSelection)
        if index and index > 0 then
            return select(8, SafeCall(GetQuestLogTitle, index))
        end
    end
end

local function CollectQuests()
    -- Quest log
    if C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, (SafeCall(C_QuestLog.GetNumQuestLogEntries) or 0) do
            local info = SafeCall(C_QuestLog.GetInfo, i)
            if info and not info.isHeader then ns.AddQuest(info.questID, info.title) end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, (SafeCall(GetNumQuestLogEntries) or 0) do
            local title, _, _, isHeader, _, _, _, questID = SafeCall(GetQuestLogTitle, i)
            if not isHeader then ns.AddQuest(questID, title) end
        end
    end

    -- Objectives text of the quest selected in the log
    local selected = SelectedLogQuestId()
    if selected and GetQuestLogQuestText then
        local _, objectives = SafeCall(GetQuestLogQuestText)
        AddObjectivesText(selected, objectives)
    end

    -- NPC dialog (quest offered / in progress / reward)
    if QuestFrame and QuestFrame:IsShown() and GetQuestID then
        local id = SafeCall(GetQuestID)
        ns.AddQuest(id, SafeCall(GetTitleText))
        AddObjectivesText(id, SafeCall(GetObjectiveText))
    end

    -- Quest list in the gossip window
    if C_GossipInfo then
        for _, fn in ipairs({ C_GossipInfo.GetAvailableQuests, C_GossipInfo.GetActiveQuests }) do
            local list = SafeCall(fn)
            if type(list) == "table" then
                for _, q in ipairs(list) do ns.AddQuest(q.questID, q.title) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Visible NPCs
---------------------------------------------------------------------------
local UNITS = {
    "target", "mouseover", "focus", "targettarget", "npc", "questnpc",
    "softinteract", "softenemy", "softfriend",
    "party1target", "party2target", "party3target", "party4target",
}

-- Unit token of a nameplate (Blizzard or Plater).
function ns.NameplateUnit(plate)
    return plate and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        or (plate.unitFrame and plate.unitFrame.unit))
end

local function CollectUnits()
    for _, unit in ipairs(UNITS) do ns.AddUnit(unit) end
    -- NPCs with a visible nameplate
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = SafeCall(C_NamePlate.GetNamePlates)
        if type(plates) == "table" then
            for _, plate in ipairs(plates) do
                local unit = ns.NameplateUnit(plate)
                if unit then ns.AddUnit(unit) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Items on every screen
---------------------------------------------------------------------------
local function Shown(frame)
    return frame and frame.IsShown and frame:IsShown()
end

local ITEM_COLLECTORS = {
    -- Merchant and buyback
    function()
        if not Shown(MerchantFrame) then return end
        for i = 1, (SafeCall(GetMerchantNumItems) or 0) do
            local id = GetMerchantItemID and SafeCall(GetMerchantItemID, i)
            if id then ns.AddItem(id) else ns.AddItemLink(SafeCall(GetMerchantItemLink, i)) end
        end
        for i = 1, (SafeCall(GetNumBuybackItems) or 0) do
            ns.AddItemLink(SafeCall(GetBuybackItemLink, i))
        end
    end,

    -- Loot
    function()
        if not Shown(LootFrame) then return end
        for i = 1, (SafeCall(GetNumLootItems) or 0) do ns.AddItemLink(SafeCall(GetLootSlotLink, i)) end
    end,

    -- Group loot rolls
    function()
        for i = 1, 4 do
            local f = _G["GroupLootFrame" .. i]
            if Shown(f) and f.rollID then ns.AddItemLink(SafeCall(GetLootRollItemLink, f.rollID)) end
        end
    end,

    -- Rewards / required items in the quest window
    function()
        if not Shown(QuestFrame) then return end
        local kinds = {
            required = SafeCall(GetNumQuestItems),
            reward = SafeCall(GetNumQuestRewards),
            choice = SafeCall(GetNumQuestChoices),
        }
        for kind, n in pairs(kinds) do
            for i = 1, (n or 0) do ns.AddItemLink(SafeCall(GetQuestItemLink, kind, i)) end
        end
    end,

    -- Rewards of the quest selected in the log
    function()
        local kinds = {
            reward = SafeCall(GetNumQuestLogRewards),
            choice = SafeCall(GetNumQuestLogChoices),
        }
        for kind, n in pairs(kinds) do
            for i = 1, (n or 0) do ns.AddItemLink(SafeCall(GetQuestLogItemLink, kind, i)) end
        end
    end,

    -- Player trade
    function()
        if not Shown(TradeFrame) then return end
        for i = 1, 7 do
            ns.AddItemLink(SafeCall(GetTradePlayerItemLink, i))
            ns.AddItemLink(SafeCall(GetTradeTargetItemLink, i))
        end
    end,

    -- Auction house (browse list, my auctions, my bids)
    function()
        if not Shown(AuctionFrame) or not GetNumAuctionItems then return end
        for _, list in ipairs({ "list", "owner", "bidder" }) do
            for i = 1, (SafeCall(GetNumAuctionItems, list) or 0) do
                ns.AddItemLink(SafeCall(GetAuctionItemLink, list, i))
            end
        end
    end,

    -- Mail (inbox, opened mail, send)
    function()
        if not Shown(MailFrame) then return end
        local maxAttach = ATTACHMENTS_MAX_RECEIVE or 12
        for m = 1, (SafeCall(GetInboxNumItems) or 0) do
            for a = 1, maxAttach do ns.AddItemLink(SafeCall(GetInboxItemLink, m, a)) end
        end
        for a = 1, (ATTACHMENTS_MAX_SEND or 12) do ns.AddItemLink(SafeCall(GetSendMailItemLink, a)) end
    end,

    -- Professions (recipes and reagents of the selected recipe)
    function()
        if Shown(TradeSkillFrame) and GetNumTradeSkills then
            for i = 1, (SafeCall(GetNumTradeSkills) or 0) do
                ns.AddItemLink(SafeCall(GetTradeSkillItemLink, i))
            end
            local sel = SafeCall(GetTradeSkillSelectionIndex)
            if sel and sel > 0 then
                for r = 1, (SafeCall(GetTradeSkillNumReagents, sel) or 0) do
                    ns.AddItemLink(SafeCall(GetTradeSkillReagentItemLink, sel, r))
                end
            end
        end
        if Shown(CraftFrame) and GetNumCrafts then
            local sel = SafeCall(GetCraftSelectionIndex)
            if sel and sel > 0 then
                for r = 1, (SafeCall(GetCraftNumReagents, sel) or 0) do
                    ns.AddItemLink(SafeCall(GetCraftReagentItemLink, sel, r))
                end
            end
        end
    end,
}

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
ns.TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

function ns.CollectTooltip(tt)
    if not tt or not tt:IsShown() then return end
    if tt.GetItem then
        local _, link = SafeCall(tt.GetItem, tt)
        ns.AddItemLink(link)
    end
    if tt.GetUnit then
        local _, unit = SafeCall(tt.GetUnit, tt)
        if unit then ns.AddUnit(unit) end
    end
end

---------------------------------------------------------------------------
-- Full collection (called on every sweep)
---------------------------------------------------------------------------
function ns.CollectContext()
    CollectQuests()
    CollectUnits()
    for _, collect in ipairs(ITEM_COLLECTORS) do pcall(collect) end
    for _, name in ipairs(ns.TOOLTIPS) do ns.CollectTooltip(_G[name]) end
end
