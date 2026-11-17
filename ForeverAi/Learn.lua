-- Learn: as you play, record where Forever quest givers, turn-ins and NPCs are (Questie lacks Forever's new content).
-- Stored in ForeverAiDB.learned; the engine uses it for pins, and the updater can merge it into the shipped data.
local _, FAI = ...
local L = {}
FAI.Learn = L

local function npcIdFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function here()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return map end
    local x, y = pos:GetXY()
    return map, x and math.floor(x * 1000 + 0.5) / 10, y and math.floor(y * 1000 + 0.5) / 10
end

local function store()
    local db = FAI.db
    db.learned = db.learned or {}
    db.learned.npcs = db.learned.npcs or {}
    db.learned.quests = db.learned.quests or {}
    return db.learned
end

local function recordUnit(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return end
    local id = npcIdFromGUID(guid)
    if not id then return end
    local map, x, y = here()
    if not (map and x) then return end
    local n = store().npcs
    local e = n[id] or {}
    e.name = UnitName(unit) or e.name
    e.lvl = UnitLevel(unit) or e.lvl
    e.map, e.x, e.y = map, x, y
    e.friend = UnitIsFriend("player", unit) and true or false
    n[id] = e
    return id, e
end

local function recordQuest(field)
    local qid = GetQuestID and GetQuestID()
    if not qid or qid == 0 then return end
    local id, npc = recordUnit("npc")
    local map, x, y = here()
    local q = store().quests
    q[qid] = q[qid] or {}
    q[qid][field] = { npc = npc and npc.name or UnitName("npc"), npcId = id, map = map, x = x, y = y }
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE", "GOSSIP_SHOW", "MERCHANT_SHOW", "PLAYER_TARGET_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if not FAI.db or InCombatLockdown() then return end
    if event == "QUEST_DETAIL" then recordQuest("start")
    elseif event == "QUEST_COMPLETE" then recordQuest("finish")
    elseif event == "GOSSIP_SHOW" or event == "MERCHANT_SHOW" then recordUnit("npc")
    elseif event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") and not UnitIsPlayer("target") then
            -- only remember NPCs you're standing near (interaction range ~ 10 yards)
            local okd, near = pcall(CheckInteractDistance, "target", 3)
            if okd and near then recordUnit("target") end
        end
    end
end)

-- Lookups used by the engine
function L:Quest(qid) return FAI.db and FAI.db.learned and FAI.db.learned.quests and FAI.db.learned.quests[qid] end
function L:Npc(id) return FAI.db and FAI.db.learned and FAI.db.learned.npcs and FAI.db.learned.npcs[id] end
function L:FindNpc(name)
    local n = FAI.db and FAI.db.learned and FAI.db.learned.npcs
    if not n then return end
    local want = FAI.Text.norm(name)
    for id, e in pairs(n) do
        if e.name and FAI.Text.norm(e.name) == want then return id, e end
    end
end
