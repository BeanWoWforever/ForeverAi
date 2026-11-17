-- Data layer: reads Questie's database (QuestDB/NpcDB/ItemDB/ObjectDB globals from QuestieDB),
-- builds a fast name index in the background, and resolves zones, waypoints and prices.
local _, FAI = ...
local T = FAI.Text
local D = { ready = false, progress = 0 }
FAI.Data = D

D.index = { quest = {}, npc = {}, item = {} }

local function dbFor(kind)
    if kind == "quest" then return _G.QuestDB
    elseif kind == "npc" then return _G.NpcDB
    elseif kind == "item" then return _G.ItemDB
    elseif kind == "object" then return _G.ObjectDB end
end

function D:Has() return _G.QuestDB and _G.NpcDB and _G.ItemDB and true or false end

function D:Get(kind, id, key)
    local db = dbFor(kind)
    if not db or not id then return nil end
    local ok, v = pcall(db.Get, id, key)
    if ok then return v end
end

---------------------------------------------------------------- background name index
D.fq = {} -- quest ids answered from ForeverAi's own Forever quest data (not in Questie)

D.fc, D.fcByName = {}, {}  -- researched Forever quests (giver, coords, chain) by id and by name

local function indexForeverQuests()
    local list = D.index.quest
    for _, q in ipairs(FAI.ForeverChains or {}) do
        D.fcByName[T.norm(q.t)] = q
        if q.id and not (q.id > 0 and D:Get("quest", q.id, "name")) then
            D.fc[q.id] = q
            if not (FAI.ForeverQuests or {})[q.id] then
                D.fq[q.id] = true
                list[#list + 1] = { q.id, T.norm(q.t), q.t }
            end
        end
    end
    for id, q in pairs(FAI.ForeverQuests or {}) do
        if not D:Get("quest", id, "name") then
            D.fq[id] = true
            list[#list + 1] = { id, T.norm(q.t), q.t }
            if not D.fc[id] then D.fc[id] = D.fcByName[T.norm(q.t)] end
        end
    end
end

-- area id for a zone name (for pins on researched coordinates)
function D:AreaByName(name)
    if not name then return nil end
    local z = _G.QuestieLoader and select(2, pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB"))
    if type(z) == "table" and z.GetAreaIdByName then
        local ok, id = pcall(z.GetAreaIdByName, z, name)
        if ok and id then return id end
    end
end

function D:StartIndexing()
    if not self:Has() then indexForeverQuests(); D.ready = true; return end
    local kinds = { "quest", "npc", "item" }
    local co = coroutine.create(function()
        for _, kind in ipairs(kinds) do
            local db = dbFor(kind)
            local ok, ids = pcall(db.GetAllIds, true)
            if ok and type(ids) == "table" then
                local list, n = D.index[kind], 0
                for k, v in pairs(ids) do
                    local id = type(v) == "number" and v or k
                    if type(id) == "number" then
                        local name = D:Get(kind, id, "name")
                        if type(name) == "string" and name ~= "" then
                            list[#list + 1] = { id, T.norm(name), name }
                        end
                        n = n + 1
                        if n % 1200 == 0 then coroutine.yield() end
                    end
                end
            end
        end
        indexForeverQuests()
        D.ready = true
    end)
    local runner = CreateFrame("Frame")
    runner:SetScript("OnUpdate", function(self)
        local ok, err = coroutine.resume(co)
        if not ok or coroutine.status(co) == "dead" then
            self:SetScript("OnUpdate", nil)
            if not ok then D.err = err end
        end
    end)
end

-- Fuzzy name search. Returns { {id=, name=, score=}, ... } best first.
function D:Find(kind, query, max)
    local q = T.norm(query)
    local res = {}
    if q == "" then return res end
    local list = self.index[kind]
    for i = 1, #list do
        local e = list[i]
        local n, s = e[2], nil
        if n == q then s = 100
        elseif n:sub(1, #q) == q then s = 80 - (#n - #q) * 0.1
        elseif n:find(q, 1, true) then s = 60 - (#n - #q) * 0.1 end
        if s then res[#res + 1] = { id = e[1], name = e[3], score = s } end
    end
    if #res == 0 then
        local words = T.words(q)
        if #words > 0 then
            for i = 1, #list do
                local e, all = list[i], true
                for _, w in ipairs(words) do
                    if not e[2]:find(w, 1, true) then all = false break end
                end
                if all then res[#res + 1] = { id = e[1], name = e[3], score = 40 - #e[2] * 0.05 } end
            end
        end
    end
    table.sort(res, function(a, b) return a.score > b.score end)
    if max and #res > max then for i = #res, max + 1, -1 do res[i] = nil end end
    return res
end

---------------------------------------------------------------- zones and waypoints
local zoneDB
local function ZoneDB()
    if zoneDB == nil then
        zoneDB = false
        if _G.QuestieLoader then
            local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
            if ok and m then zoneDB = m end
        end
    end
    return zoneDB or nil
end

function D:ZoneName(areaId)
    if not areaId then return "?" end
    if C_Map and C_Map.GetAreaInfo then
        local n = C_Map.GetAreaInfo(areaId)
        if n and n ~= "" then return n end
    end
    return "zone " .. areaId
end

function D:UiMap(areaId)
    local z = ZoneDB()
    if z then
        local ok, m = pcall(z.GetUiMapIdByAreaId, z, areaId)
        if ok and m then return m end
    end
end

-- Best spawn of an NPC: zone with most spawns, first point.
function D:NpcSpot(npcId)
    local spawns = self:Get("npc", npcId, "spawns")
    if type(spawns) ~= "table" then return end
    local bestZone, bestCount
    for zoneId, pts in pairs(spawns) do
        if type(pts) == "table" and (#pts > (bestCount or 0)) then bestZone, bestCount = zoneId, #pts end
    end
    if not bestZone then return end
    local p = spawns[bestZone][1]
    if type(p) ~= "table" or not p[1] or p[1] < 0 then return bestZone, nil, nil, bestCount end
    return bestZone, p[1], p[2], bestCount
end

function D:ObjectSpot(objId)
    local spawns = self:Get("object", objId, "spawns")
    if type(spawns) ~= "table" then return end
    for zoneId, pts in pairs(spawns) do
        local p = type(pts) == "table" and pts[1]
        if p and p[1] and p[1] >= 0 then return zoneId, p[1], p[2], #pts end
        return zoneId
    end
end

-- Clickable waypoint link for the answer window.
function D:Pin(areaId, x, y, title)
    if not (areaId and x and y) then return "" end
    title = (title or ""):gsub("[:|]", " ")
    return (" |Hforeverai:pin:%d:%.1f:%.1f:%s|h|cff66ccff[pin]|r|h"):format(areaId, x, y, title)
end

-- Same, but for a UI map id (what the learner records)
function D:PinMap(uiMap, x, y, title)
    if not (uiMap and x and y) then return "" end
    title = (title or ""):gsub("[:|]", " ")
    return (" |Hforeverai:pinm:%d:%.1f:%.1f:%s|h|cff66ccff[pin]|r|h"):format(uiMap, x, y, title)
end

function D:WhereMap(uiMap, x, y)
    local info = uiMap and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMap)
    local s = T.c("zone", info and info.name or "?")
    if x and y then s = s .. (" (%.0f, %.0f)"):format(x, y) end
    return s
end

function D:Where(areaId, x, y)
    if not areaId then return "unknown location" end
    local s = T.c("zone", self:ZoneName(areaId))
    if x and y then s = s .. (" (%.0f, %.0f)"):format(x, y) end
    return s
end

function D:SetWaypoint(areaId, x, y, title, isUiMap)
    local uiMap = isUiMap and areaId or self:UiMap(areaId)
    if not uiMap then return false end
    if _G.TomTom and TomTom.AddWaypoint then
        pcall(TomTom.AddWaypoint, TomTom, uiMap, x / 100, y / 100, { title = title, from = "ForeverAi" })
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        local ok = pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMap, x / 100, y / 100))
            if C_SuperTrack then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
        return ok
    end
    return true
end

---------------------------------------------------------------- items and prices
local function itemInfo(id)
    local f = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if f then return f(id) end
end

function D:ItemLink(id, fallbackName)
    local name, link = itemInfo(id)
    return link or T.c("item", "[" .. (name or fallbackName or ("item " .. id)) .. "]")
end

function D:VendorPrice(id)
    local sell = select(11, itemInfo(id))
    return sell
end

function D:AHPrice(id)
    local api = _G.Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetAuctionPriceByItemID then
        local ok, price = pcall(api.GetAuctionPriceByItemID, "ForeverAi", id)
        if ok then return price end
    end
end

function D:Money(copper)
    if not copper then return "?" end
    copper = math.floor(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end
