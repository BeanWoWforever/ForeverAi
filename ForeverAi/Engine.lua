-- Engine: works out what you're asking and builds the answer from live game state, installed addons'
-- data (Questie, RestedXP, Auctionator) and ForeverAi's own knowledge base.
local _, FAI = ...
local T, D = FAI.Text, FAI.Data
local E = { last = {} }
FAI.Engine = E
local c = T.c

---------------------------------------------------------------- player context
local function readProfessions()
    local profs = {}
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local ok, name, isHeader, _, rank = pcall(GetSkillLineInfo, i)
            if ok and name and not isHeader then
                local key = FAI.Text.professions[FAI.Text.norm(name)]
                if key then profs[key] = rank end
            end
        end
    end
    return profs
end

function E:Ctx()
    local className, classToken = UnitClass("player")
    return {
        profs = readProfessions(),
        name = UnitName("player"), class = classToken, className = className,
        level = UnitLevel("player"), race = UnitRace("player"),
        faction = UnitFactionGroup("player"), zone = GetZoneText(), subzone = GetSubZoneText(),
    }
end

local function fill(text, ctx)
    ctx.skill = ctx.skill or "?"
    return (text:gsub("{(%w+)}", function(k) return ctx[k] and tostring(ctx[k]) or "{" .. k .. "}" end))
end

local function factionOk(f, ctx)
    if f == "C" or not f then return true end
    return (f == "A" and ctx.faction == "Alliance") or (f == "H" and ctx.faction == "Horde")
end

---------------------------------------------------------------- knowledge base (TF-IDF match)
local kbIndex, kbPhr, kbAns, idf = {}, {}, {}, {}

function E:BuildKBIndex()
    kbIndex, kbPhr, kbAns, idf = {}, {}, {}, {}
    local df, N = {}, #FAI.KB
    for i, e in ipairs(FAI.KB) do
        local bag, phr = {}, {}
        for _, q in ipairs(e.q or {}) do
            local _, set = T.tokens(q)
            phr[#phr + 1] = set
            for w in pairs(set) do bag[w] = true end
        end
        kbIndex[i], kbPhr[i] = bag, phr
        local allFaction = #phr > 0
        for _, set in ipairs(phr) do if not (set.alliance or set.horde or set.faction) then allFaction = false end end
        e._factionTopic = allFaction or nil
        local q1 = (e.q and e.q[1] or ""):lower()
        e._lore = (e.topic == "lore_bosses" and not q1:find("boss") and not q1:find("list") and not q1:find("get")) or nil
        -- the answer's own words (first ~400 chars) also count, so a question phrased in a way nobody wrote down can still land
        if type(e.a) == "string" then
            local _, aset = T.tokens(e.a:sub(1, 400))
            kbAns[i] = aset
        end
        for w in pairs(bag) do df[w] = (df[w] or 0) + 1 end
        -- skill brackets mentioned in the entry ("225-300") so a player at skill 260 gets that bracket
        local ranges = {}
        local text = table.concat(e.q or {}, " ") .. " " .. (type(e.a) == "string" and e.a:sub(1, 200) or "")
        for sa, sb in text:gmatch("(%d+)%s*%-%s*(%d+)") do
            local a, b = tonumber(sa), tonumber(sb)
            if a and b and b > a and b > 60 then ranges[#ranges + 1] = { a, b } end
        end
        e._ranges = #ranges > 0 and ranges or nil
    end
    for w, n in pairs(df) do idf[w] = math.log((N + 1) / n) + 1 end
    E._idf, E._bag, E._ans = idf, kbIndex, kbAns
end

local TOPIC = { gold = 1, attunement = 1, reputation = 1, key = 1, mount = 1, raid = 1, talent = 1, transmog = 1,
    herbalism = 1, mining = 1, skinning = 1, fishing = 1, alchemy = 1, enchanting = 1, blacksmithing = 1, engineering = 1,
    tailoring = 1, leatherworking = 1, cooking = 1, camping = 1, pvp = 1, honor = 1, legacy = 1 }
-- words that personalize a question but don't define its topic ("as a level 60 ret pally")
local CONTEXTUAL = { level = 1, ret = 1, retribution = 1, prot = 1, holy = 1, arms = 1, fury = 1, feral = 1, resto = 1,
    enh = 1, enhancement = 1, ele = 1, elemental = 1, shadow = 1, disc = 1, frost = 1, fire = 1, arcane = 1, bm = 1, mm = 1,
    affliction = 1, demo = 1, destro = 1, combat = 1, sub = 1, assassination = 1, alliance = 1, horde = 1, new = 1, fresh = 1 }
-- words that, when asked about, the answer has to actually be about (else it's a near-miss on everything else)
local MUSTRAW = { "pet", "cat", "boss", "junk", "phone", "mobile", "app", "dkp", "stealth", "vendor", "color", "colors", "objective",
    "objectives", "solo", "prettiest", "grey", "gray", "dreadsteed", "epic" }
local MUST, GROUPS
local function buildGroups()
    MUST = {}
    for _, w in ipairs(MUSTRAW) do for _, t in ipairs(T.tokens(w)) do MUST[t] = true end end
    GROUPS = { faction = {}, prof = {}, zone = {}, race = {} }
    for _, w in ipairs({ "human", "dwarf", "gnome", "elf", "orc", "troll", "tauren", "undead", "forsaken", "skyborne" }) do
        for _, t in ipairs(T.tokens(w)) do if t ~= "race" then GROUPS.race[t] = (t == "forsaken") and "undead" or t end end
    end
    for _, w in ipairs({ "alliance", "horde" }) do GROUPS.faction[w] = w end
    for w, canon in pairs(T.professions) do for _, t in ipairs(T.tokens(w)) do GROUPS.prof[t] = canon end end

    local zl = {}
    for _, z in ipairs(FAI.Zones or {}) do zl[#zl + 1] = z.n end
    for _, n in ipairs({ "Mount Hyjal", "Zephras Isle", "Riverglades", "Shen'dralas", "Dalaran" }) do zl[#zl + 1] = n end
    local generic = { forest = 1, mountain = 1, mountains = 1, island = 1, isle = 1, glades = 1, marsh = 1, mount = 1, valley = 1, lands = 1, highlands = 1, hills = 1, plains = 1, eastern = 1, western = 1, northern = 1, southern = 1, crater = 1, peaks = 1 }
    for _, n in ipairs(zl) do
        local key
        for _, t in ipairs(T.tokens(n)) do if not generic[t] and (not key or #t > #key) then key = t end end
        if key then GROUPS.zone[key] = n end
    end
end
E._groups = function() if not GROUPS then buildGroups() end return GROUPS, MUST end

local CLASSES = { warrior = 1, mage = 1, hunter = 1, rogue = 1, priest = 1, warlock = 1, paladin = 1, druid = 1, shaman = 1 }

-- Score = closest single phrasing (weighted overlap) + how much of the question is covered + overall similarity.
function E:MatchKB(question, ctx, n)
    local all = T.tokens(question)
    local qtoks, ctxToks = {}, {}
    for _, w in ipairs(all) do
        if CONTEXTUAL[w] or w:match("^%d+$") then ctxToks[#ctxToks + 1] = w else qtoks[#qtoks + 1] = w end
    end
    if #qtoks <= 1 and #ctxToks > 0 then qtoks = all; ctxToks = {} end
    local qset, qnorm = {}, 0
    for _, w in ipairs(qtoks) do qset[w] = true; qnorm = qnorm + (idf[w] or 3) ^ 2 end
    for _, w in ipairs(ctxToks) do qset[w] = qset[w] or false end
    if qnorm == 0 then return {} end
    if not GROUPS then buildGroups() end
    -- which conflict-group values the question names
    local qg = {}
    for g, map in pairs(GROUPS) do
        for _, w in ipairs(all) do if map[w] then qg[g] = qg[g] or {}; qg[g][map[w]] = true end end
    end
    local mentionsClass, unknown = nil, 0
    for _, w in ipairs(all) do if CLASSES[w] then mentionsClass = w:upper() end end
    for _, w in ipairs(qtoks) do
        if not idf[w] then unknown = unknown + 1 end
    end
    local lq = T.norm(question)
    E._loreQ = lq:find("lore") or lq:find("story") or lq:find("who is") or lq:find("who are") or lq:find("who was") or lq:find("history")
        or lq:find("happened") or lq:find("behind") or lq:find("backstory") or lq:find("why is") or lq:find("why are") or lq:find("what is the") and false
    E.lastTokCount = #qtoks
    E.lastUnknown = unknown
    local scored = {}
    for i, bag in pairs(kbIndex) do
        local dot, enorm = 0, 0
        for w in pairs(bag) do enorm = enorm + idf[w] ^ 2 end
        for _, w in ipairs(qtoks) do if bag[w] then dot = dot + idf[w] ^ 2 end end
        if dot > 0 then
            local cos = dot / (math.sqrt(qnorm) * math.sqrt(enorm))
            local qcov = dot / qnorm
            local bestJ = 0
            for _, set in ipairs(kbPhr[i]) do
                local inter, uni = 0, qnorm
                for w in pairs(set) do
                    local wt = idf[w] ^ 2
                    if qset[w] then inter = inter + wt
                    elseif qset[w] == nil and not CONTEXTUAL[w] then uni = uni + wt end
                end
                local j = inter / uni
                if j > bestJ then bestJ = j end
            end
            -- how much of the question is covered by phrasings + answer text together
            local abag, dotAll = kbAns[i], 0
            for _, w in ipairs(qtoks) do if bag[w] or (abag and abag[w]) then dotAll = dotAll + (idf[w] or 3) ^ 2 end end
            local qcovAll = dotAll / qnorm
            local s = 0.45 * bestJ + 0.25 * qcov + 0.15 * cos + 0.15 * qcovAll
            local e = FAI.KB[i]
            -- a question about gold / attunements / keys / reps etc. must land on an entry about that topic
            for w in pairs(qset) do
                if TOPIC[w] and not bag[w] then s = s * 0.75 end
            end
            -- conflicts: the question names Alliance/skinning/Hyjal/hunter and the entry is about a *different* one
            local abag2 = kbAns[i] or {}
            for g, want in pairs(qg) do
                local has, other = false, false
                for w, v in pairs(GROUPS[g]) do
                    if bag[w] or (g ~= "class" and abag2[w]) then if want[v] then has = true else other = true end end
                    if g == "class" and abag2[w] and want[v] then has = true end
                end
                if not has and other then s = s * 0.55 end
            end
            for _, w in ipairs(all) do
                if MUST[w] and not bag[w] and not abag2[w] then s = s * 0.6 end
            end
            if e._lore and not E._loreQ then s = s * 0.75 end
            if e.topic and e.topic:find("^prof") and not qg.prof and not qset.profession and not qset.recipe and not qset.craft
                and not qset.disenchant and not qset.campfire and not qset.camping and not qset.wood and bestJ < 0.7 and false then s = s * 0.75 end
            if e._factionTopic and not qg.faction and not qset.faction then s = s * 0.6 end
            if e.class then
                local want = mentionsClass or ctx.class
                if e.class == want then s = s + 0.04 else s = s * 0.5 end
            end
            if ctx.profession and bag[ctx.profession] then s = s + 0.08 end
            if ctx.skill and e._ranges then
                for _, r in ipairs(e._ranges) do
                    if ctx.skill >= r[1] and ctx.skill <= r[2] then s = s + 0.1 break end
                end
            end
            if e.topic and e.src ~= "classic" then s = s + 0.03 elseif e.src == "classic" then s = s - 0.03 end
            scored[#scored + 1] = { i = i, s = s, qcov = qcov, j = bestJ, all = qcovAll }
        end
    end
    table.sort(scored, function(a, b) return a.s > b.s end)
    local out = {}
    for k = 1, math.min(n or 3, #scored) do out[k] = scored[k] end
    return out
end

local function kbAnswer(i, ctx)
    local e = FAI.KB[i]
    local a = type(e.a) == "function" and e.a(ctx) or e.a
    local lines = {}
    for line in fill(a, ctx):gmatch("[^\n]+") do lines[#lines + 1] = line end
    if e.src == "classic" then lines[#lines + 1] = c("dim", "(Classic info - ForeverAi updates this as Forever data comes in)") end
    return lines
end

---------------------------------------------------------------- entity answers
local function npcLines(npcId, header)
    local name = D:Get("npc", npcId, "name") or ("NPC " .. npcId)
    local sub = D:Get("npc", npcId, "subName")
    local minL, maxL = D:Get("npc", npcId, "minLevel"), D:Get("npc", npcId, "maxLevel")
    local friendly = D:Get("npc", npcId, "friendlyToFaction")
    local zone, x, y, count = D:NpcSpot(npcId)
    local who = c(friendly and "npc" or "enemy", name) .. (sub and sub ~= "" and (" <" .. sub .. ">") or "")
    local lvl = minL and ((minL == maxL or not maxL) and (" level " .. minL) or (" level " .. minL .. "-" .. maxL)) or ""
    local out = { (header or "") .. who .. lvl }
    if zone then
        out[#out + 1] = "  " .. D:Where(zone, x, y) .. ((count and count > 1) and c("dim", " (" .. count .. " spawn points)") or "") .. D:Pin(zone, x, y, name)
    else
        out[#out + 1] = "  " .. c("dim", "No spawn location in the database (may be an event or summoned NPC).")
    end
    local starts = D:Get("npc", npcId, "questStarts")
    if type(starts) == "table" and #starts > 0 then
        local names = {}
        for k = 1, math.min(4, #starts) do names[#names + 1] = c("quest", D:Get("quest", starts[k], "name") or "?") end
        out[#out + 1] = "  Gives: " .. table.concat(names, ", ") .. (#starts > 4 and c("dim", " +" .. (#starts - 4) .. " more") or "")
    end
    E.last = { kind = "npc", id = npcId, name = name }
    return out
end

local function starterText(startedBy)
    -- startedBy = { {npcIds}, {objectIds}, {itemIds} }
    if type(startedBy) ~= "table" then return nil end
    local npcs, objs, items = startedBy[1], startedBy[2], startedBy[3]
    if type(npcs) == "table" and npcs[1] then
        local id = npcs[1]
        local z, x, y = D:NpcSpot(id)
        local nm = D:Get("npc", id, "name") or "?"
        return c("npc", nm) .. " in " .. D:Where(z, x, y) .. D:Pin(z, x, y, nm)
    end
    if type(objs) == "table" and objs[1] then
        local nm = D:Get("object", objs[1], "name") or "an object"
        local z, x, y = D:ObjectSpot(objs[1])
        return c("gold", nm) .. (z and (" in " .. D:Where(z, x, y) .. D:Pin(z, x, y, nm)) or "")
    end
    if type(items) == "table" and items[1] then
        return "the item " .. D:ItemLink(items[1], D:Get("item", items[1], "name"))
    end
end

local function foreverQuestLines(qid)
    local cq = FAI.ForeverQuests and FAI.ForeverQuests[qid]   -- from your game client's cache
    local rq = D.fc[qid]                                        -- researched (giver, coords, chain)
    local title = (cq and cq.t) or (rq and rq.t) or ("Quest " .. qid)
    local lvl, minl = (cq and cq.l) or (rq and rq.l), (cq and cq.m) or (rq and rq.m)
    local out = { c("quest", title) .. c("dim", (" (level %s%s)"):format(tostring(lvl or "?"), minl and (", needs " .. minl) or "")) .. c("gold", "  [Forever]") }
    local zone = (rq and rq.z) or (cq and cq.z and cq.z > 0 and D:ZoneName(cq.z)) or nil
    if zone then out[#out + 1] = "  Zone: " .. c("zone", zone) end
    if rq and rq.g then
        local area = D:AreaByName(rq.z)
        local where = (rq.gl and (" - " .. rq.gl) or "") .. ((rq.x and rq.y) and (" (%.1f, %.1f)"):format(rq.x, rq.y) or "")
        out[#out + 1] = "  Starts: " .. c("npc", rq.g) .. where .. ((area and rq.x) and D:Pin(area, rq.x, rq.y, rq.g) or "")
    end
    local lq = FAI.Learn:Quest(qid)
    if lq and lq.start and not (rq and rq.g) then out[#out + 1] = "  Starts: " .. c("npc", lq.start.npc or "?") .. " - " .. D:WhereMap(lq.start.map, lq.start.x, lq.start.y) .. D:PinMap(lq.start.map, lq.start.x, lq.start.y, lq.start.npc) end
    if rq and rq.ti then out[#out + 1] = "  Turn in: " .. c("npc", rq.ti)
    elseif lq and lq.finish then out[#out + 1] = "  Turn in: " .. c("npc", lq.finish.npc or "?") .. " - " .. D:WhereMap(lq.finish.map, lq.finish.x, lq.finish.y) .. D:PinMap(lq.finish.map, lq.finish.x, lq.finish.y, lq.finish.npc) end
    local goal = (cq and cq.o ~= "" and cq.o) or (rq and rq.o)
    if goal then out[#out + 1] = "  Goal: " .. goal end
    if rq and (rq.pre or rq.nx or rq.ch) then
        local parts = {}
        if rq.pre then parts[#parts + 1] = "after " .. E:AskLink(rq.pre, "quest " .. rq.pre) end
        if rq.nx then parts[#parts + 1] = "leads to " .. E:AskLink(rq.nx, "quest " .. rq.nx) end
        if rq.ch then parts[#parts + 1] = "chain: " .. E:AskLink(rq.ch, "chain " .. title) end
        out[#out + 1] = "  " .. table.concat(parts, " - ")
    end
    if rq and rq.r then out[#out + 1] = "  Reward: " .. rq.r end
    if cq and cq.d and cq.d ~= "" then out[#out + 1] = c("dim", "  " .. cq.d:sub(1, 200) .. (#cq.d > 200 and "..." or "")) end
    if qid > 0 and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) then
        out[#out + 1] = "  " .. c("ok", "You've already completed this.")
    end
    E.last = { kind = "quest", id = qid, name = title }
    return out
end

local function questLines(qid)
    if D.fq[qid] then return foreverQuestLines(qid) end
    local name = D:Get("quest", qid, "name") or ("Quest " .. qid)
    local qlvl, rlvl = D:Get("quest", qid, "questLevel"), D:Get("quest", qid, "requiredLevel")
    local out = { c("quest", name) .. c("dim", (" (level %s, needs %s)"):format(tostring(qlvl or "?"), tostring(rlvl or "?"))) }
    local s = starterText(D:Get("quest", qid, "startedBy"))
    if s then out[#out + 1] = "  Starts: " .. s end
    local f = starterText(D:Get("quest", qid, "finishedBy"))
    if f then out[#out + 1] = "  Turn in: " .. f end
    local obj = D:Get("quest", qid, "objectivesText")
    if type(obj) == "table" and obj[1] then out[#out + 1] = "  Goal: " .. T.clean(table.concat(obj, " ")):sub(1, 300) end
    local pre = D:Get("quest", qid, "preQuestSingle") or D:Get("quest", qid, "preQuestGroup")
    if type(pre) == "table" and pre[1] then
        out[#out + 1] = "  Requires first: " .. c("quest", D:Get("quest", pre[1], "name") or "?")
    end
    local nxt = D:Get("quest", qid, "nextQuestInChain")
    if nxt and nxt ~= 0 then out[#out + 1] = "  Leads to: " .. c("quest", D:Get("quest", nxt, "name") or "?") end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) then
        out[#out + 1] = "  " .. c("ok", "You've already completed this.")
    end
    local pg, ps = D:Get("quest", qid, "preQuestGroup"), D:Get("quest", qid, "preQuestSingle")
    if (type(pg) == "table" and #pg > 0) or (type(ps) == "table" and #ps > 0) then
        out[#out + 1] = "  " .. E:AskLink("Unlock checklist (what you've done / still need)", "checklist " .. name)
    end
    E.last = { kind = "quest", id = qid, name = name }
    return out
end

local function itemLines(iid, ctx)
    local name = D:Get("item", iid, "name") or ("item " .. iid)
    local out = { D:ItemLink(iid, name) }
    local objs = D:Get("item", iid, "objectDrops")
    if type(objs) == "table" and #objs > 0 then
        for k = 1, math.min(2, #objs) do
            local nm = D:Get("object", objs[k], "name") or "an object"
            local z, x, y = D:ObjectSpot(objs[k])
            out[#out + 1] = "  Gathered from " .. c("gold", nm) .. (z and (" - e.g. " .. D:Where(z, x, y) .. D:Pin(z, x, y, nm)) or "")
        end
    end
    local drops = D:Get("item", iid, "npcDrops")
    if type(objs) == "table" and #objs > 0 and type(drops) == "table" and #drops > 2 then
        drops = { drops[1], drops[2], n = #drops }  -- a gathered material: mob drops are incidental
    end
    if type(drops) == "table" and #drops > 0 then
        local shown = {}
        for k = 1, math.min(4, #drops) do
            local id = drops[k]
            local nm = D:Get("npc", id, "name") or "?"
            local z, x, y = D:NpcSpot(id)
            local lv = D:Get("npc", id, "minLevel")
            shown[#shown + 1] = "  Drops from " .. c("enemy", nm) .. (lv and c("dim", " (lvl " .. lv .. ")") or "") .. " - " .. D:Where(z, x, y) .. D:Pin(z, x, y, nm)
        end
        for _, l in ipairs(shown) do out[#out + 1] = l end
        if #drops > 4 then out[#out + 1] = c("dim", "  ...and " .. (#drops - 4) .. " more mobs.") end
    end
    local vend = D:Get("item", iid, "vendors")
    if type(vend) == "table" and #vend > 0 then
        for k = 1, math.min(2, #vend) do
            local nm = D:Get("npc", vend[k], "name") or "?"
            local z, x, y = D:NpcSpot(vend[k])
            out[#out + 1] = "  Sold by " .. c("npc", nm) .. " - " .. D:Where(z, x, y) .. D:Pin(z, x, y, nm)
        end
    end
    local rewards = D:Get("item", iid, "questRewards")
    if type(rewards) == "table" and #rewards > 0 then
        out[#out + 1] = "  Quest reward from: " .. c("quest", D:Get("quest", rewards[1], "name") or "?")
    end
    local ah, vendor = D:AHPrice(iid), D:VendorPrice(iid)
    if ah then out[#out + 1] = "  Auction price: " .. D:Money(ah) end
    if vendor and vendor > 0 then out[#out + 1] = "  Vendors for: " .. D:Money(vendor) end
    if #out == 1 then out[#out + 1] = c("dim", "  No drop, vendor or quest source in the database - likely crafted or a world drop.") end
    E.last = { kind = "item", id = iid, name = name }
    return out
end

---------------------------------------------------------------- live-state answers
local function guideLines()
    local f = _G.RXPFrame
    if not (f and f.activeSteps) then return nil end
    local out = {}
    local gname = _G.RXPCData and RXPCData.currentGuideName
    if gname then out[1] = c("gold", "RestedXP: ") .. gname .. c("dim", " (step " .. tostring(RXPCData.currentStep or "?") .. ")") end
    for _, step in ipairs(f.activeSteps) do
        if type(step) == "table" and type(step.elements) == "table" then
            for _, el in ipairs(step.elements) do
                local txt = el.text or el.tooltipText
                if type(txt) == "string" and txt ~= "" then
                    local done = el.completed and c("ok", " (done)") or ""
                    out[#out + 1] = "- " .. T.clean(txt) .. done
                end
            end
        end
        if #out > 9 then break end
    end
    if #out <= 1 then return nil end
    return out
end

local function zonesFor(level, ctx)
    local fit = {}
    for _, z in ipairs(FAI.Zones) do
        if level >= z.min - 1 and level <= z.max - 2 and factionOk(z.f, ctx) then fit[#fit + 1] = z end
    end
    -- Forever's new zones win ties: they're the reason people play this version
    local function dist(z) return math.abs((z.min + z.max) / 2 - level) - (z.note and 3 or 0) end
    table.sort(fit, function(a, b) return dist(a) < dist(b) end)
    local out = { ("Good zones for level %d:"):format(level) }
    for k = 1, math.min(6, #fit) do
        local z = fit[k]
        out[#out + 1] = ("- %s %s%s"):format(c("zone", z.n), c("dim", ("(%d-%d)"):format(z.min, z.max)), z.note and c("dim", " - " .. z.note) or "")
    end
    if #fit == 0 then out[#out + 1] = "Nothing obvious - try 'what should I do next' for your RestedXP route." end
    return out
end

local function dungeonsFor(level, ctx)
    local out = { ("Dungeons around level %d:"):format(level) }
    local n = 0
    for _, d in ipairs(FAI.Dungeons) do
        if not d.raid and level >= d.min - 2 and level <= d.max and factionOk(d.f, ctx) then
            n = n + 1
            out[#out + 1] = ("- %s %s - %s"):format(c("gold", d.n), c("dim", ("(%d-%d)"):format(d.min, d.max)), c("zone", d.zone))
        end
    end
    if n == 0 then out[#out + 1] = "None in range - you're between brackets, keep questing." end
    out[#out + 1] = c("dim", "Ask about one by name for where it is and tips.")
    return out
end

local function findDungeon(text)
    local q = " " .. T.expand(text) .. " "
    local best, bestLen
    for _, d in ipairs(FAI.Dungeons) do
        local keys = { T.norm(d.n) }
        for a in (d.alias or ""):gmatch("[^,]+") do keys[#keys + 1] = T.norm(a) end
        for _, key in ipairs(keys) do
            local k2 = key:gsub("^the ", "")
            if q:find(" " .. k2 .. " ", 1, true) or q:find(" " .. key .. " ", 1, true) then
                if not bestLen or #k2 > bestLen then best, bestLen = d, #k2 end
            end
        end
    end
    return best
end

local function dungeonLines(d)
    E.last = { kind = "dungeon", name = d.n }
    return {
        c("gold", d.n) .. c("dim", (d.raid and " (%d-player raid)" or " (levels %d-%d)"):format(d.raid and d.size or d.min, d.max)),
        "  Location: " .. c("zone", d.zone),
        "  " .. (d.tip or ""),
        d.unreleased and c("warn", "  Not released in Forever yet - no date announced.") or nil,
    }
end

local function questLog()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return nil end
    local out, n = { "Your quest log:" }, 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader then
            n = n + 1
            local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
            out[#out + 1] = ("- %s %s%s"):format(c("quest", info.title), c("dim", "[" .. (info.level or "?") .. "]"), done and c("ok", " - ready to turn in") or "")
        end
    end
    if n == 0 then return { "Your quest log is empty - ask 'what should I do next'." } end
    return out
end

---------------------------------------------------------------- resolving "him / that / it"
local function resolveRef(target)
    local t = T.norm(target)
    local refs = { [""] = 1, he = 1, she = 1, him = 1, her = 1, it = 1, that = 1, them = 1, they = 1, there = 1, ["that guy"] = 1,
        ["that npc"] = 1, ["that quest"] = 1, ["that item"] = 1, ["this"] = 1, ["that one"] = 1 }
    if refs[t] then
        return E.last.name
    end
    return target
end

local function lookupAny(target, ctx, prefer)
    if not D.ready then return { c("warn", "Still loading the database (a few seconds after login) - ask again in a moment.") } end
    local order = prefer or { "npc", "quest", "item" }
    for _, kind in ipairs(order) do
        local hits = D:Find(kind, target, 5)
        if hits[1] and hits[1].score >= 60 then
            if kind == "npc" then
                -- prefer an NPC that actually has a spawn and is friendly to us
                local pick = hits[1]
                for _, h in ipairs(hits) do
                    if h.score == hits[1].score and D:NpcSpot(h.id) then pick = h break end
                end
                return npcLines(pick.id)
            elseif kind == "quest" then return questLines(hits[1].id)
            else return itemLines(hits[1].id, ctx) end
        end
    end
    -- an NPC ForeverAi has seen you near (Forever content Questie doesn't have)
    if order[1] ~= "item" then
        local id, e = FAI.Learn:FindNpc(target)
        if id then
            E.last = { kind = "npc", id = id, name = e.name }
            return { c(e.friend and "npc" or "enemy", e.name) .. (e.lvl and e.lvl > 0 and (" level " .. e.lvl) or "") .. c("gold", "  [seen by you]"),
                "  " .. D:WhereMap(e.map, e.x, e.y) .. D:PinMap(e.map, e.x, e.y, e.name) }
        end
    end
    -- weaker matches: offer what's close
    for _, kind in ipairs(order) do
        local hits = D:Find(kind, target, 3)
        if hits[1] then
            local out = { "Closest matches:" }
            for _, h in ipairs(hits) do out[#out + 1] = "- " .. E:AskLink(h.name, (kind == "item" and "who drops " or kind == "quest" and "quest " or "where is ") .. h.name) end
            return out
        end
    end
end

function E:AskLink(label, question)
    question = question:gsub("[:|]", " ")
    return "|Hforeverai:ask:" .. question .. "|h|cff66ccff" .. label .. "|r|h"
end

---------------------------------------------------------------- live game data: any spell or item, straight from the client
local function spellLines(name)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if not ok or type(info) ~= "table" or not info.spellID then return nil end
    local desc = C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(info.spellID) or ""
    if desc == "" then return nil end
    local out = { c("gold", info.name) .. c("dim", " (spell)") }
    for line in T.clean(desc):gmatch("[^\n]+") do out[#out + 1] = "  " .. line end
    return out
end

local function itemTooltipLines(name, ctx)
    if not D.ready then return nil end
    local hits = D:Find("item", name, 1)
    if not (hits[1] and hits[1].score >= 80) then return nil end
    local id = hits[1].id
    local out = { D:ItemLink(id, hits[1].name) }
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local ok, tip = pcall(C_TooltipInfo.GetItemByID, id)
        if ok and tip and tip.lines then
            for k = 2, math.min(#tip.lines, 14) do
                local l = tip.lines[k]
                local txt = l and l.leftText
                if txt and txt ~= "" then out[#out + 1] = "  " .. T.clean(txt) .. (l.rightText and l.rightText ~= "" and ("   " .. l.rightText) or "") end
            end
        end
    end
    -- plus where to get it
    local src = itemLines(id, ctx)
    for k = 2, #src do out[#out + 1] = src[k] end
    return out
end

---------------------------------------------------------------- intents
local intents = {
    { -- small talk
        test = function(q) return q == "thanks" or q == "thank you" or q == "ty" or q == "thx" or q:find("^lol") or q:find("^lmao") or q == "ok" or q == "cool" or q == "nice" end,
        run = function(q)
            if q:find("^th") or q == "ty" then return { "Anytime - good luck out there." } end
            return { "Ha - it's a grind, but you've got this. Ask me anything when you're stuck." }
        end },
    { -- help / greeting
        test = function(q) return q == "" or q == "help" or q == "hi" or q == "hello" or q == "hey" or q:find("^what can you") end,
        run = function(q, ctx) return kbAnswer(1, ctx) end },
    { -- "what does X do" / "what is X" for any spell or item in the game
        test = function(q) return q:match("^what does (.+) do$") or q:match("^what is (.+)$") or q:match("^whats (.+)$") or q:match("^(.+) tooltip$") end,
        run = function(q, ctx)
            local target = q:match("^what does (.+) do$") or q:match("^what is (.+)$") or q:match("^whats (.+)$") or q:match("^(.+) tooltip$")
            target = resolveRef(target):gsub("^the ", ""):gsub("^a ", "")
            return spellLines(target) or itemTooltipLines(target, ctx)
        end },
    { -- guide / what next
        skipForProfession = true,
        test = function(q) return (q:find("next step") or q:find("what next") or q:find("do next") or q:find("go next")
            or q:find("^what now") or q:find("^guide") or q:find("what should i do") or q:find("where do i go"))
            and not (q:find("died") or q:find("ghost") or q:find("dead") or q:find("corpse") or q:find("%d") or q:find("after")) end,
        run = function(q, ctx)
            local g = guideLines()
            if g then return g end
            local out = { "RestedXP isn't showing a step right now, so here's where to head:" }
            for _, l in ipairs(zonesFor(ctx.level, ctx)) do out[#out + 1] = l end
            return out
        end },
    { -- what level is <zone>
        test = function(q) return (q:find("what level") or q:find("what lvl") or q:find("level range") or q:find("how high"))
            and not findDungeon(q) end,
        run = function(q)
            local GZ = select(1, E._groups()).zone
            for _, w in ipairs(T.tokens(q)) do
                local zn = GZ[w]
                if zn then
                    for _, z in ipairs(FAI.Zones) do
                        if z.n == zn then
                            return { c("zone", z.n) .. (" is a level %d-%d zone"):format(z.min, z.max)
                                .. (z.f == "A" and " (Alliance)." or z.f == "H" and " (Horde)." or " (contested)."),
                                z.note and c("dim", z.note) or nil }
                        end
                    end
                end
            end
        end },
    { -- quest log
        test = function(q) return q:find("my quests") or q:find("quest log") or q:find("what quests do i have") end,
        run = function() return questLog() end },
    { -- where to level
        skipForProfession = true,
        test = function(q)
            if q:find("pretti") or q:find("pretty") or q:find("favorite") or q:find("coolest") or q:find("music") or q:find("looking") then return false end
            return q:find("where should i level") or q:find("where to level") or q:find("where should i quest") or q:find("where do i level")
            or q:find("where do i go after") or q:find("where should i go after") or q:find("where to go after")
            or q:find("what zone should") or q:find("what zone do i") or q:find("what zone next") or q:find("zone comes after") or q:find("zone after")
            or q:find("best zone") or q:find("leveling zone") or q:find("zones? for %d") or q:find("zones? %d") or q:find("where do i go at %d") end,
        run = function(q, ctx)
            local lv = ctx.askLevel or ctx.level
            local a = q:match("(%d+)%s*%-%s*%d+") or q:match("zones? (%d+)") or q:match("zones? for (%d+)")
            if a then lv = tonumber(a) end
            local after = q:match("after (.+)$")
            if after then
                for _, z in ipairs(FAI.Zones) do
                    if after:find(T.norm(z.n):gsub("^the ", ""), 1, true) then lv = z.max; break end
                end
            end
            local out = zonesFor(lv, ctx)
            -- "that aren't X": drop the zone they excluded
            local excl = q:match("arent (%a[%a ]*)") or q:match("not (%a[%a ]*)$") or q:match("besides (%a[%a ]*)")
            if excl then
                local keep = {}
                for _, l in ipairs(out) do if not T.norm(l):find(T.norm(excl):sub(1, 6), 1, true) then keep[#keep + 1] = l end end
                out = keep
            end
            return out
        end },
    { -- which dungeons
        test = function(q) return (q:find("dungeon") and (q:find("which") or q:find("what") or q:find("should") or q:find("for level") or q:find("at %d")))
            and not findDungeon(q) and not q:find("solo") and not q:find("farm") and not q:find("bis") end,
        run = function(q, ctx)
            -- "dungeons in riverglades": answer for that zone, or let the knowledge base handle it
            local GZ = select(1, E._groups()).zone
            for _, w in ipairs(T.tokens(q)) do
                if GZ[w] then
                    local out, zn = {}, GZ[w]
                    for _, d in ipairs(FAI.Dungeons) do
                        if T.norm(d.zone or ""):find(w, 1, true) then out[#out + 1] = "- " .. c("gold", d.n) .. c("dim", (" (%d-%d)"):format(d.min, d.max)) end
                    end
                    if #out == 0 then
                        local new = {}
                        for _, d in ipairs(FAI.Dungeons) do if d.forever and not d.raid then new[#new + 1] = d.n .. " (" .. d.zone .. ")" end end
                        return { "There's no dungeon in " .. c("zone", zn) .. " in ForeverAi's data.",
                            #new > 0 and ("Forever's new dungeons: " .. table.concat(new, ", ") .. ".") or nil }
                    end
                    table.insert(out, 1, "Dungeons in " .. c("zone", zn) .. ":")
                    return out
                end
            end
            return dungeonsFor(ctx.askLevel or ctx.level, ctx)
        end },
    { -- price
        test = function(q) return q:match("^price of (.+)") or q:match("^how much is (.+) worth") or q:match("^how much does (.+) sell for")
            or q:match("^what is (.+) worth") or q:match("^whats (.+) worth") or q:match("^(.+) price$") end,
        run = function(q, ctx)
            local target = q:match("^price of (.+)") or q:match("^how much is (.+) worth") or q:match("^how much does (.+) sell for")
                or q:match("^what is (.+) worth") or q:match("^whats (.+) worth") or q:match("^(.+) price$")
            return lookupAny(resolveRef(target), ctx, { "item" })
        end },
    { -- item source
        test = function(q) return q:match("^who drops (.+)") or q:match("^what drops (.+)") or q:match("^what boss drops (.+)") or q:match("^which boss drops (.+)") or q:match("^what mob drops (.+)") or q:match("^where does (.+) drop")
            or (q:match("^where %a+ i (%a+) ") and ({ get = 1, buy = 1 })[q:match("^where %a+ i (%a+) ")])
            or q:match("^how %a+ i get (.+)") or q:match("^where to get (.+)") or q:match("^where to buy (.+)") end,
        run = function(q, ctx)
            local target = q:match("^who drops (.+)") or q:match("^what drops (.+)") or q:match("^what boss drops (.+)") or q:match("^which boss drops (.+)") or q:match("^what mob drops (.+)") or q:match("^where does (.+) drop")
                or q:match("^where %a+ i %a+ (.+)") or q:match("^how %a+ i get (.+)") or q:match("^where to %a+ (.+)")
            target = resolveRef(target or "")
            if target:find("^into ") or target:find("attun") or target:find(" key") or target:find("^key") then return nil end -- "how do I get into X" = access question, KB handles it
            local d = findDungeon(target)
            if d then return dungeonLines(d) end
            return lookupAny(target, ctx, { "item", "npc", "quest" })
        end },
    { -- quests in a zone (Forever content)
        test = function(q) return q:match("^quests? in (.+)") or q:match("^what quests are in (.+)") or q:match("^(.+) quests$") end,
        run = function(q, ctx)
            local zq = T.norm(q:match("^quests? in (.+)") or q:match("^what quests are in (.+)") or q:match("^(.+) quests$")):gsub("^the ", "")
            local list = {}
            for id, fq in pairs(FAI.ForeverQuests or {}) do
                if fq.z and fq.z > 0 and T.norm(D:ZoneName(fq.z)):find(zq, 1, true) then list[#list + 1] = { id = id, q = fq } end
            end
            if #list == 0 then return nil end
            table.sort(list, function(a, b) return a.q.l < b.q.l end)
            local out = { ("Forever quests in %s (%d known):"):format(D:ZoneName(list[1].q.z), #list) }
            for k = 1, math.min(15, #list) do
                local e = list[k]
                out[#out + 1] = ("- %s %s"):format(E:AskLink(e.q.t, "quest " .. e.q.t), c("dim", "[" .. e.q.l .. "]"))
            end
            if #list > 15 then out[#out + 1] = c("dim", "...and " .. (#list - 15) .. " more.") end
            return out
        end },
    { -- quest lookup
        test = function(q) return q:match("^quest (.+)") or q:match("^how do i do (.+)") or q:match("^how do i finish (.+)")
            or q:match("^how do i complete (.+)") or q:match("^where do i turn in (.+)") end,
        run = function(q, ctx)
            local target = q:match("^quest (.+)") or q:match("^how do i %a+ (.+)") or q:match("^where do i turn in (.+)")
            return lookupAny(resolveRef(target), ctx, { "quest" })
        end },
    { -- where is / find
        test = function(q) return q:match("^where is (.+)") or q:match("^where are (.+)") or q:match("^wheres (.+)") or q:match("^where can i find (.+)")
            or q:match("^find (.+)") or q:match("^location of (.+)") or q:match("^who is (.+)") end,
        run = function(q, ctx)
            local target = q:match("^where is (.+)") or q:match("^where are (.+)") or q:match("^wheres (.+)") or q:match("^where can i find (.+)")
                or q:match("^find (.+)") or q:match("^location of (.+)") or q:match("^who is (.+)")
            if q:find("attun") or q:find(" key") or q:find("seal of") then return nil end -- let the knowledge base answer
            target = resolveRef(target)
            local d = findDungeon(target)
            if d then return dungeonLines(d) end
            return lookupAny(target, ctx, { "npc", "quest", "item" })
        end },
}

---------------------------------------------------------------- main entry
function E:Answer(raw)
    raw = T.dedupe(raw)
    local ctx = self:Ctx()
    local qi = T.context(raw)
    ctx.profession = qi.profession
    ctx.skill = qi.skill or (qi.profession and ctx.profs[qi.profession]) or nil
    if qi.level then ctx.askLevel = qi.level end
    local q = T.norm(raw)

    -- answers built from your own character and server come first
    if FAI.Composer then
        local mine = FAI.Composer:Try(q, ctx, raw)
        if mine then E.lastKind = "lookup"; return mine end
    end

    -- a quest named in a "help me with it" question: your checklist, straight away
    local HELPW = { "missing", "need", "help", "how", "stuck", "chain", "next", "finish", "get", "do ", "start", "doing", "where" }
    local named = self:FindQuestInText(q)
    if named and FAI.Composer and FAI.Composer.Checklist then
        local helpy = false
        for _, w in ipairs(HELPW) do if q:find(w, 1, true) then helpy = true break end end
        if helpy then
            self:Focus(named)
            local ok, lines = pcall(FAI.Composer.Checklist, FAI.Composer, named, ctx)
            if ok and lines then E.lastKind = "kb"; return lines end
        end
    end

    -- a near-exact knowledge-base hit beats the generic intents below
    local early = self:MatchKB(raw, ctx, 1)[1]
    local named = findDungeon(q)
    if named and named.unreleased then E.lastKind = "lookup"; return dungeonLines(named) end
    if early and early.j >= 0.9 and early.all >= 0.95 and early.s >= 0.8 and not (q:find("level") or q:find("lvl")) then
        E.lastKind = "kb"
        return kbAnswer(early.i, ctx)
    end

    for _, it in ipairs(intents) do
        if not (qi.profession and it.skipForProfession) and it.test(q) then
            local ok, out = pcall(it.run, q, ctx)
            if ok and out then E.lastKind = "lookup"; return out end
            if not ok then FAI.lastError = out end
        end
    end

    -- a dungeon named anywhere in the question, with no stronger KB hit
    local best = self:MatchKB(raw, ctx, 3)
    local d = findDungeon(q)
    local comparing = q:find(" like ") or q:find(" vs ") or q:find(" or ") or q:find("than")
    local basics = q:find("what level") or q:find("level for") or q:find("lvl for") or q:find("where is") or q:find("wheres")
        or q:find("how do i get to") or q:find("how to get to") or q:find("entrance")
    if d and basics and not comparing then
        E.lastKind = "lookup"
        local out = dungeonLines(d)
        if best[1] and best[1].s >= 0.6 and best[1].j >= 0.5 then
            for _, l in ipairs(kbAnswer(best[1].i, ctx)) do out[#out + 1] = l end
        end
        return out
    end
    if d and not (d.unreleased and comparing) and (d.unreleased or not (best[1] and best[1].s >= 0.5)) then E.lastKind = "lookup"; return dungeonLines(d) end

    -- confident only when one stored phrasing closely matches AND the question has no words the knowledge base has never seen
    -- unknown words only count against us when they're a real share of the question (not one filler word in a long one)
    local unknownHurts = (E.lastUnknown or 0) >= 2 or ((E.lastUnknown or 0) == 1 and (E.lastTokCount or 0) <= 3)
    local b1 = best[1]
    local confident = b1 and (b1.all >= 0.5 or b1.j >= 0.85) and ((b1.s >= 0.45 and b1.j >= 0.5 and (not unknownHurts or b1.j >= 0.8))
        or (b1.all >= 0.9 and b1.j >= 0.42 and b1.s >= 0.44 and not unknownHurts))
    if confident then
        E.lastKind = "kb"
        local out = kbAnswer(best[1].i, ctx)
        -- not a near-exact match: say what we understood, so a misread is obvious instead of looking authoritative
        if b1.j < 0.85 then table.insert(out, 1, c("dim", "Reading this as: " .. FAI.KB[b1.i].q[1])) end
        if best[2] and best[2].s >= 0.45 and best[2].j >= 0.4 then
            out[#out + 1] = c("dim", "Related: ") .. self:AskLink(FAI.KB[best[2].i].q[1], FAI.KB[best[2].i].q[1])
        end
        return out
    end

    -- maybe they just typed a name ("Hogger", "Arcanite Bar")
    if D.ready and #T.words(q) <= 5 then
        for _, kind in ipairs({ "npc", "item", "quest" }) do
            local hits = D:Find(kind, q, 1)
            if hits[1] and hits[1].score >= 80 then
                E.lastKind = "lookup"
                if kind == "npc" then return npcLines(hits[1].id) end
                if kind == "item" then return itemLines(hits[1].id, ctx) end
                return questLines(hits[1].id)
            end
        end
    end

    -- not known yet: log it so ForeverAi learns it, and offer the closest things it does know
    E.lastKind = "miss"
    self:LogUnanswered(raw, ctx)
    local out = { "I don't have a solid answer for that yet - I've logged it so ForeverAi learns it in the next update." }
    if best[1] and best[1].j >= 0.3 then
        out[#out + 1] = c("dim", "Closest things I know:")
        for k = 1, math.min(3, #best) do
            local qq = FAI.KB[best[k].i].q[1]
            out[#out + 1] = "- " .. self:AskLink(qq, qq)
        end
    end
    return out
end

-- Compact player context sent with live questions (level, class, professions, zone, gold)
function E:LiveContext()
    local ctx = self:Ctx()
    local profs = {}
    for k, v in pairs(ctx.profs or {}) do profs[#profs + 1] = k .. ":" .. v end
    local gold = GetMoney and math.floor(GetMoney() / 10000) or nil
    local parts = {
        "lvl=" .. tostring(ctx.level), "class=" .. tostring(ctx.className), "race=" .. tostring(ctx.race),
        "faction=" .. tostring(ctx.faction), "zone=" .. tostring(ctx.zone),
        "professions=" .. table.concat(profs, ","), "gold=" .. tostring(gold),
    }
    local g = _G.RXPCData and RXPCData.currentGuideName
    if g then parts[#parts + 1] = "guide=" .. g end
    for _, extra in ipairs(E._liveExtra or {}) do parts[#parts + 1] = extra end
    return (table.concat(parts, ";"):gsub("[~|]", " "))
end

-- plain text for the companion: no colors, links or textures, no separators it splits on
local function plain(s)
    s = tostring(s or ""):gsub("|T[^|]*ReadyCheck%-Ready[^|]*|t", "DONE"):gsub("|T[^|]*ReadyCheck%-NotReady[^|]*|t", "TODO")
        :gsub("|T[^|]*ReadyCheck%-Waiting[^|]*|t", "OPEN"):gsub("|Hforeverai:pin[^|]*|h.-|h", ""):gsub("|Hforeverai:ask:mark[^|]*|h.-|h", "")
        :gsub("|Hforeverai:ask:unmark[^|]*|h.-|h", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
    return (s:gsub("[;=~|]", ","):gsub("%s+", " "))
end

-- the longest run of words in a question that is exactly a quest's name ("look to do the in dreams quest" -> In Dreams)
function E:FindQuestInText(question)
    if not (D.ready and FAI.Composer) then return nil end
    local w = {}
    for x in T.norm(question):gmatch("%S+") do w[#w + 1] = x end
    for len = math.min(6, #w), 1, -1 do
        for i = 1, #w - len + 1 do
            local phrase = table.concat(w, " ", i, i + len - 1)
            if #phrase >= 6 then
                local hit = D:Find("quest", phrase, 1)[1]
                if hit and not D.fq[hit.id] and T.norm(hit.name or "") == phrase then return hit.id end
            end
        end
    end
end

-- the quest this conversation is about, so follow-ups ("give me the coords in order") stay on it
function E:Focus(id)
    local chat = FAI.db and FAI.db.chatId
    if id then FAI.db.focus = { id = id, chat = chat } return id end
    local f = FAI.db and FAI.db.focus
    if f and f.chat == chat then return f.id end
end

-- what ForeverAi knows about THIS character for a live question: quest log, progress on a named quest, its own offline answer
function E:BuildLiveExtra(question, offline)
    local extra = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local names = {}
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.title then names[#names + 1] = info.title end
            if #names >= 12 then break end
        end
        if #names > 0 then extra[#extra + 1] = "questlog=" .. plain(table.concat(names, ", ")):sub(1, 600) end
    end
    -- a quest named in the question: find the longest run of words that is exactly a quest's name
    local C = FAI.Composer
    if D.ready and C and C.Checklist then
        local found = self:FindQuestInText(question)
        if found then self:Focus(found) else found = self:Focus() end
        if found then
            local ok, lines = pcall(C.Checklist, C, found, self:Ctx())
            if ok and lines then
                local keep = {}
                for k, l in ipairs(lines) do if k <= 14 and not l:find("Ticks come from") then keep[#keep + 1] = plain(l) end end
                extra[#extra + 1] = "questcheck=" .. table.concat(keep, " / "):sub(1, 690)
            end
        end
    end
    if offline and #offline > 0 then
        local t = {}
        for _, l in ipairs(offline) do t[#t + 1] = plain(l) end
        extra[#extra + 1] = "facts=" .. table.concat(t, " / "):sub(1, 690)
    end
    E._liveExtra = extra
end

function E:LogUnanswered(raw, ctx)
    local list = FAI.db and FAI.db.unanswered
    if not list then return end
    for _, e in ipairs(list) do if e.q == raw then e.n = (e.n or 1) + 1 return end end
    list[#list + 1] = { q = raw, t = time(), level = ctx.level, class = ctx.class, zone = ctx.zone, n = 1 }
    while #list > 300 do table.remove(list, 1) end
end
