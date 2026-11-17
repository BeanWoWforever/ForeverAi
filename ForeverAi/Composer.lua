-- Composer: answers built live from YOUR character - professions, bags, gear, quests, reputations, gold and your server's
-- auction prices (Auctionator scans). Nothing here needs the internet.
local _, FAI = ...
local T, D = FAI.Text, FAI.Data
local c = T.c
local C = { intents = {} }
FAI.Composer = C

---------------------------------------------------------------- reading your character
local function itemInfo(id)
    local f = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if f then return f(id) end
end

function C:Professions()
    local profs = {}
    if GetProfessions and GetProfessionInfo then
        for _, idx in ipairs({ GetProfessions() }) do
            if idx then
                local ok, name, _, rank, maxRank = pcall(GetProfessionInfo, idx)
                local key = ok and name and T.professions[T.norm(name)]
                if key then profs[key] = { rank = rank, max = maxRank } end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local ok, name, isHeader, _, rank, _, _, maxRank = pcall(GetSkillLineInfo, i)
            local key = ok and name and not isHeader and T.professions[T.norm(name)]
            if key and not profs[key] then profs[key] = { rank = rank, max = maxRank } end
        end
    end
    return profs
end

-- every item in your bags: { id, count, link, quality, bound }
function C:BagItems()
    local items = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return items end
    for bag = 0, 5 do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                items[#items + 1] = { id = info.itemID, count = info.stackCount or 1, link = info.hyperlink,
                    quality = info.quality, bound = info.isBound, bag = bag, slot = slot }
            end
        end
    end
    return items
end

function C:Price(id)
    local ah = D:AHPrice(id)
    local vendor = select(11, itemInfo(id)) or 0
    return ah, vendor
end

local function money(cp) return D:Money(math.floor(cp or 0)) end

---------------------------------------------------------------- 1. personal gold farm
local GATHER_LABEL = { herbalism = "Herbalism", mining = "Mining", skinning = "Skinning" }

function C:GoldFarm(ctx, q)
    local profs = self:Professions()
    local out, any = { c("gold", "Best farms for you right now") .. c("dim", " (your skills + your server's AH prices)") }, false
    for key, label in pairs(GATHER_LABEL) do
        local p = profs[key]
        if p and FAI.Gathering[key] then
            any = true
            local rows = {}
            for _, g in ipairs(FAI.Gathering[key]) do
                if g.s <= p.rank then
                    local hit = D.ready and D:Find("item", g.n, 1)[1]
                    local id = hit and hit.score >= 80 and hit.id
                    local ah = id and D:AHPrice(id)
                    rows[#rows + 1] = { g = g, id = id, ah = ah or 0 }
                end
            end
            table.sort(rows, function(a, b)
                if a.ah ~= b.ah then return a.ah > b.ah end
                return a.g.s > b.g.s
            end)
            out[#out + 1] = c("gold", label .. " " .. p.rank) .. ":"
            local priced = rows[1] and rows[1].ah > 0
            for k = 1, math.min(3, #rows) do
                local r = rows[k]
                local name = r.id and D:ItemLink(r.id, r.g.n) or r.g.n
                out[#out + 1] = ("  %d. %s %s - %s"):format(k, name, r.ah > 0 and ("~" .. money(r.ah) .. " each") or "", c("zone", r.g.z))
            end
            if not priced then out[#out + 1] = c("dim", "  (no Auctionator prices yet - ranked by skill tier; scan the AH for real prices)") end
        end
    end
    if not any then
        out[#out + 1] = "You don't have a gathering profession, so your best gold is:"
        out[#out + 1] = "  - loot and sell all cloth, vendor greys, and skin/mine/herb if you pick one up (best raw gold while leveling)"
    end
    local level = ctx.level or 1
    if level >= 60 then
        out[#out + 1] = c("dim", "At 60 also: farm Runecloth + Scarlets at Tyr's Hand (EPL), elementals for Essences, Dire Maul runs.")
    end
    -- plus the best researched gold advice for this exact question
    local probe = (ctx.level or 1) >= 60 and "gold farming max level best gold farm at 60" or "how do i make gold while leveling"
    local best = FAI.Engine:MatchKB(probe, ctx, 1)[1]
    if best and best.s >= 0.4 and type(FAI.KB[best.i].a) == "string" then
        out[#out + 1] = c("gold", "More ways:")
        for line in FAI.KB[best.i].a:gmatch("[^\n]+") do out[#out + 1] = "  " .. line end
    end
    if (GetMoney and GetMoney() or 0) > 0 then out[#out + 1] = c("dim", "You have " .. money(GetMoney()) .. ".") end
    return out
end

---------------------------------------------------------------- 2. what to sell
function C:SellAdvice()
    local items = self:BagItems()
    local rule = "Rule of thumb: grey items always go to a vendor. Greens, blues, recipes and crafting mats usually earn more on the AH, as long as the price beats the vendor price plus the deposit. Ask 'price of <item>' to check one."
    if #items == 0 then return { rule } end
    local greys, greyCount, rows = 0, 0, {}
    for _, it in ipairs(items) do
        local name, _, quality, _, _, _, _, _, _, _, sell = itemInfo(it.id)
        sell = (sell or 0) * it.count
        if quality == 0 then
            greys = greys + sell; greyCount = greyCount + it.count
        elseif name then
            local ah = D:AHPrice(it.id)
            local ahTotal = ah and ah * it.count or 0
            rows[#rows + 1] = { it = it, name = name, sell = sell, ah = ahTotal, bound = it.bound }
        end
    end
    table.sort(rows, function(a, b) return math.max(a.ah, a.sell) > math.max(b.ah, b.sell) end)
    local out = { rule, c("gold", "Your bags:") }
    out[#out + 1] = ("  Junk (grey): %d items -> %s at any vendor"):format(greyCount, money(greys))
    local shown = 0
    for _, r in ipairs(rows) do
        if shown >= 8 then break end
        if r.ah > 0 or r.sell > 0 then
            shown = shown + 1
            local tip
            if r.bound then tip = "bound - vendor " .. money(r.sell)
            elseif r.ah > r.sell * 1.3 then tip = "AH ~" .. money(r.ah) .. c("dim", " (vendor " .. money(r.sell) .. ")")
            else tip = "vendor " .. money(r.sell) .. (r.ah > 0 and c("dim", " (AH ~" .. money(r.ah) .. ")") or "") end
            out[#out + 1] = ("  %s x%d: %s"):format(r.it.link or r.name, r.it.count, tip)
        end
    end
    if not (_G.Auctionator) then out[#out + 1] = c("dim", "Install Auctionator and scan once to see AH values here.") end
    return out
end

---------------------------------------------------------------- 3. gear upgrades
-- rough per-point stat values by class (default leveling/raid spec); good enough to spot clear upgrades
local W = {
    WARRIOR = { STR = 1, AGI = .6, STA = .35, AP = .5, CRIT = 8, HIT = 8, DPS = 3, ARMOR = .02 },
    PALADIN = { STR = 1, AGI = .5, STA = .35, INT = .3, AP = .5, CRIT = 8, HIT = 8, SP = .4, DPS = 3, ARMOR = .02 },
    HUNTER = { AGI = 1, STR = .2, STA = .35, INT = .25, AP = .5, CRIT = 8, HIT = 8, DPS = 2, ARMOR = .01 },
    ROGUE = { AGI = 1, STR = .5, STA = .35, AP = .5, CRIT = 8, HIT = 9, DPS = 3, ARMOR = .01 },
    DRUID = { AGI = .8, STR = .8, STA = .4, INT = .4, AP = .45, SP = .5, CRIT = 7, HIT = 7, ARMOR = .02 },
    SHAMAN = { STR = .8, AGI = .6, STA = .35, INT = .45, AP = .45, SP = .6, CRIT = 7, HIT = 7, DPS = 2.5, ARMOR = .01 },
    MAGE = { INT = 1, SPI = .5, STA = .35, SP = 1, CRIT = 8, HIT = 9, MP5 = 1.2 },
    WARLOCK = { INT = .8, SPI = .4, STA = .6, SP = 1, CRIT = 7, HIT = 9 },
    PRIEST = { INT = .9, SPI = .9, STA = .35, SP = 1, CRIT = 6, MP5 = 1.5 },
}
local STATKEY = {
    ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI", ITEM_MOD_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "AP", ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_HIT_RATING_SHORT = "HIT",
    ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "SP", ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS", RESISTANCE0_NAME = "ARMOR",
}
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

function C:Score(link, class)
    if not link then return 0 end
    local getStats = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
    if not getStats then return nil end
    local ok, stats = pcall(getStats, link)
    if not ok or type(stats) ~= "table" then return nil end
    local w, s = W[class] or W.WARRIOR, 0
    for k, v in pairs(stats) do
        local key = STATKEY[k]
        if key and w[key] then s = s + v * w[key] end
    end
    return s
end

local function canWear(link)
    if C_PlayerInfo and C_PlayerInfo.CanUseItem then
        local ok, r = pcall(C_PlayerInfo.CanUseItem, link)
        if ok and r ~= nil then return r end
    end
    local _, _, _, _, req = itemInfo(link)
    return not req or req <= (UnitLevel("player") or 60)
end

-- compare one item against what you wear in that slot
function C:CompareItem(link, ctx)
    local _, ilink, _, _, _, _, _, _, equipLoc = itemInfo(link)
    local slots = SLOTS[equipLoc or ""]
    if not slots then return { (ilink or link) .. " isn't something you equip." } end
    local new = self:Score(link, ctx.class)
    if not new then return { "Can't read item stats on this client." } end
    local best, bestSlot, bestLink
    for _, sl in ipairs(slots) do
        local cur = GetInventoryItemLink("player", sl)
        local sc = self:Score(cur, ctx.class) or 0
        if not best or sc < best then best, bestSlot, bestLink = sc, sl, cur end -- compare against your weakest matching slot
    end
    local delta = new - (best or 0)
    local verdict = delta > 0.5 and c("ok", "Upgrade") or (delta < -0.5 and c("warn", "Downgrade") or "About the same")
    local out = { verdict .. " for your " .. (ctx.className or "class") .. c("dim", (" (score %+.0f)"):format(delta)) }
    out[#out + 1] = "  " .. (ilink or link) .. "  vs  " .. (bestLink or c("dim", "empty slot"))
    if not canWear(link) then out[#out + 1] = c("warn", "  You can't use it yet (level or armor type).") end
    out[#out + 1] = c("dim", "  Rough stat-weight estimate for your class's usual spec.")
    return out
end

function C:BagUpgrades(ctx)
    local ups = {}
    for _, it in ipairs(self:BagItems()) do
        local _, _, _, _, _, _, _, _, equipLoc = itemInfo(it.id)
        local slots = SLOTS[equipLoc or ""]
        if slots and it.link and canWear(it.link) then
            local new = self:Score(it.link, ctx.class) or 0
            local worst
            for _, sl in ipairs(slots) do
                local sc = self:Score(GetInventoryItemLink("player", sl), ctx.class) or 0
                if not worst or sc < worst then worst = sc end
            end
            if new - (worst or 0) > 0.5 then ups[#ups + 1] = { link = it.link, d = new - worst } end
        end
    end
    table.sort(ups, function(a, b) return a.d > b.d end)
    if #ups == 0 then return { "Nothing in your bags beats what you're wearing." } end
    local out = { c("gold", "Upgrades sitting in your bags:") }
    for k = 1, math.min(6, #ups) do out[#out + 1] = ("  %s %s"):format(ups[k].link, c("ok", ("+%.0f"):format(ups[k].d))) end
    out[#out + 1] = c("dim", "  Rough stat-weight estimate. Tip: shift-click any item into this box and ask 'is this an upgrade'.")
    return out
end

---------------------------------------------------------------- 4. reputations
local REACTIONS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

function C:Factions()
    local list = {}
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        for i = 1, C_Reputation.GetNumFactions() do
            local f = C_Reputation.GetFactionDataByIndex(i)
            if f and f.name and not f.isHeader then
                list[#list + 1] = { name = f.name, reaction = f.reaction, cur = (f.currentStanding or 0) - (f.currentReactionThreshold or 0),
                    max = (f.nextReactionThreshold or 0) - (f.currentReactionThreshold or 0) }
            end
        end
    elseif GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() do
            local name, _, standing, bottom, top, earned, _, _, isHeader = GetFactionInfo(i)
            if name and not isHeader then list[#list + 1] = { name = name, reaction = standing, cur = earned - bottom, max = top - bottom } end
        end
    end
    return list
end

function C:Reputation(q)
    local list = self:Factions()
    if #list == 0 then return nil end
    local best
    for _, f in ipairs(list) do
        local n = T.norm(f.name)
        for w in q:gmatch("%a%a%a%a+") do
            if n:find(w, 1, true) and not ({ reputation = 1, standing = 1, much = 1, with = 1, need = 1 })[w] then best = f break end
        end
        if best then break end
    end
    if not best then
        local out = { c("gold", "Your reputations:") }
        table.sort(list, function(a, b) return (a.reaction or 0) > (b.reaction or 0) end)
        for k = 1, math.min(10, #list) do
            local f = list[k]
            out[#out + 1] = ("  %s - %s %s"):format(f.name, REACTIONS[f.reaction] or "?", c("dim", ("%d/%d"):format(f.cur, f.max)))
        end
        return out
    end
    local nextName = REACTIONS[(best.reaction or 0) + 1]
    local out = { ("%s: %s %s"):format(c("gold", best.name), REACTIONS[best.reaction] or "?", c("dim", ("(%d/%d)"):format(best.cur, best.max))) }
    if nextName then out[#out + 1] = ("  %d more rep to %s."):format(math.max(0, best.max - best.cur), nextName) end
    local tip = FAI.Engine:MatchKB(best.name .. " reputation", FAI.Engine:Ctx(), 1)[1]
    if tip and tip.s > 0.4 then
        local e = FAI.KB[tip.i]
        out[#out + 1] = c("dim", "  How to raise it: ") .. (type(e.a) == "string" and e.a or "")
    end
    return out
end

---------------------------------------------------------------- 5. your quests, by difficulty
function C:MyQuests(ctx)
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return nil end
    local lvl = ctx.level or 1
    local groups = { done = {}, red = {}, orange = {}, yellow = {}, green = {}, grey = {} }
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local q = C_QuestLog.GetInfo(i)
        if q and not q.isHeader then
            local d = (q.level or lvl) - lvl
            local key = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.questID)) and "done"
                or (d >= 5 and "red") or (d >= 3 and "orange") or (d >= -2 and "yellow") or (d >= -8 and "green") or "grey"
            table.insert(groups[key], ("%s [%d]"):format(q.title, q.level or 0))
        end
    end
    local out = { c("gold", "Your quest log:") }
    local labels = { { "done", "ok", "Ready to turn in" }, { "yellow", "ffff00", "Right for your level" }, { "green", "33ff33", "Easy (fast XP)" },
        { "orange", "ff8040", "Hard - group or wait" }, { "red", "ff2020", "Too hard for now" }, { "grey", "9a9a9a", "Grey - abandon or finish for gold" } }
    local any = false
    for _, l in ipairs(labels) do
        local g = groups[l[1]]
        if #g > 0 then
            any = true
            out[#out + 1] = c(l[2], l[3] .. ":") .. " " .. table.concat(g, ", ")
        end
    end
    if not any then return { "Your quest log is empty - ask 'what should I do next'." } end
    return out
end

---------------------------------------------------------------- 6. mount savings
function C:MountGoal(ctx)
    local gold = (GetMoney and GetMoney() or 0) / 10000
    local lvl = ctx.level or 1
    local target, label = 100, "riding at 40 (100g incl. first mount)"
    if lvl >= 40 then target, label = 1200, "epic riding at 60 (1,000g + 200g mount)" end
    local out = { ("You have %s. Goal: %s."):format(money(gold * 10000), label) }
    if gold >= target then out[#out + 1] = c("ok", "  You can afford it - go train!")
    else out[#out + 1] = ("  %s still to go. Honored with your home faction knocks 10%% off."):format(money((target - gold) * 10000)) end
    return out
end

---------------------------------------------------------------- intents (checked before the knowledge base)
local function has(q, ...) for _, w in ipairs({ ... }) do if q:find(w, 1, true) then return true end end end

C.intents = {
    { test = function(q, raw) return raw:find("|Hitem:", 1, true) or raw:find("item:%d+") end,
      run = function(q, ctx, raw) local link = raw:match("|c%x+|Hitem:.-|h.-|h|r") or raw:match("item:[%-%d:]+"); return link and C:CompareItem(link, ctx) end },
    { test = function(q) return has(q, "upgrade") and has(q, "bag", "my ", "any", "have") end,
      run = function(q, ctx) return C:BagUpgrades(ctx) end },
    { test = function(q) return has(q, "what should i sell", "what do i sell", "sell or vendor", "vendor or ah", "clean my bag", "my bags worth",
            "whats in my bag", "what to sell", "worth selling", "sell my junk", "junk in my bag") end,
      run = function() return C:SellAdvice() end },
    { test = function(q) return (has(q, "gold", "money") and has(q, "farm", "make", "earn", "best way", "how do i get", "for me", "should i"))
            and not has(q, "mount", "legacy", "perk", "camping", "campfire", "phone", "auction", " ah ", "deposit", "spend") end,
      run = function(q, ctx) return C:GoldFarm(ctx, q) end },
    { test = function(q) return has(q, "my rep", "my reputation", "reputation with", "rep with", "how far", "how much rep", "standing with") end,
      run = function(q) return C:Reputation(q) end },
    { test = function(q) return has(q, "my quests", "quest log", "which quests", "what quests should", "quests should i do") end,
      run = function(q, ctx) return C:MyQuests(ctx) end },
    { test = function(q) return has(q, "mount") and has(q, "afford", "save", "how much gold", "enough gold", "can i buy my", "how long until") end,
      run = function(q, ctx) return C:MountGoal(ctx) end },
}

function C:Try(q, ctx, raw)
    for _, it in ipairs(self.intents) do
        if it.test(q, raw) then
            local ok, out = pcall(it.run, q, ctx, raw)
            if ok and out then return out end
            if not ok then FAI.lastError = out end
        end
    end
end

-- shift-click items into the ForeverAi box
local function insertHook(link)
    local box = _G.ForeverAiInput
    if box and box:HasFocus() and link then box:Insert(link) end
end
if hooksecurefunc then
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", insertHook) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", insertHook) end
end

---------------------------------------------------------------- quest chains + "suggested for you"
local QDB
local function questieDB()
    if QDB == nil then
        QDB = false
        if _G.QuestieLoader then
            local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
            if ok and m then QDB = m end
        end
    end
    return QDB or nil
end

function C:QuestState(id)
    if self.Manual and self:Manual()[id] then return "done" end
    if C_QuestLog then
        if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) then return "done" end
        if C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) then return "log" end
    end
    local q = questieDB()
    if D.fq[id] then return "unknown" end -- Forever-only quest: Questie can't judge it
    if q and q.IsDoable then
        local ok, doable = pcall(q.IsDoable, id)
        if ok then return doable and "avail" or "locked" end
    end
    return "unknown"
end

local function firstOf(t) return type(t) == "table" and t[1] or nil end

function C:Chain(id)
    local back, seen, cur = {}, { [id] = true }, id
    for _ = 1, 20 do
        local pre = firstOf(D:Get("quest", cur, "preQuestSingle")) or firstOf(D:Get("quest", cur, "preQuestGroup"))
        if not pre or seen[pre] then break end
        seen[pre] = true; table.insert(back, 1, pre); cur = pre
    end
    local chain = back
    chain[#chain + 1] = id
    cur = id
    for _ = 1, 20 do
        local nxt = D:Get("quest", cur, "nextQuestInChain")
        if not nxt or nxt == 0 or seen[nxt] then break end
        seen[nxt] = true; chain[#chain + 1] = nxt; cur = nxt
    end
    return chain
end

local STATE_LABEL = { done = { "ok", "done" }, log = { "ffff00", "in your log" }, avail = { "66ccff", "available now" },
    locked = { "9a9a9a", "not yet" }, unknown = { "9a9a9a", "" } }

function C:ChainLines(id)
    local chain = self:Chain(id)
    local out = { c("gold", "Quest chain") .. c("dim", (" (%d steps)"):format(#chain)) }
    local nextShown = false
    for k, qid in ipairs(chain) do
        local name = D:Get("quest", qid, "name") or ("Quest " .. qid)
        local lvl = D:Get("quest", qid, "questLevel") or "?"
        local st = self:QuestState(qid)
        local lab = STATE_LABEL[st] or STATE_LABEL.unknown
        local marker = (qid == id) and c("gold", " <") or ""
        out[#out + 1] = ("  %d. %s %s %s%s"):format(k, FAI.Engine:AskLink(name, "quest " .. name), c("dim", "[" .. lvl .. "]"),
            c(lab[1], lab[2]), marker)
        if not nextShown and (st == "avail" or st == "log") then
            nextShown = true
            local s = D:Get("quest", qid, "startedBy")
            local npc = type(s) == "table" and firstOf(s[1])
            if npc and st == "avail" then
                local z, x, y = D:NpcSpot(npc)
                local nm = D:Get("npc", npc, "name") or "?"
                out[#out + 1] = "     " .. c("dim", "next: get it from ") .. c("npc", nm) .. " - " .. D:Where(z, x, y) .. D:Pin(z, x, y, nm)
            end
        end
    end
    return out
end

function C:ForeverChainLines(q)
    local steps, seen = {}, {}
    -- walk pre/next links when the research has them
    local cur = q
    for _ = 1, 15 do
        local pre = cur.pre and D.fcByName[T.norm(cur.pre)]
        if not pre or seen[pre] then break end
        seen[pre] = true; cur = pre
    end
    for _ = 1, 25 do
        if seen[cur] and #steps > 0 then break end
        seen[cur] = true; steps[#steps + 1] = cur
        local nx = cur.nx and D.fcByName[T.norm(cur.nx)]
        if not nx then break end
        cur = nx
    end
    -- otherwise show the whole storyline group, in level order
    if #steps <= 1 and q.ch then
        steps = {}
        for _, e in ipairs(FAI.ForeverChains or {}) do if e.ch == q.ch then steps[#steps + 1] = e end end
        table.sort(steps, function(a, b) return (a.l or 0) < (b.l or 0) end)
    end
    local out = { c("gold", "Forever chain: " .. (q.ch or q.t)) .. c("dim", (" (%d steps)"):format(#steps)) }
    for k, e in ipairs(steps) do
        local st = (e.id and e.id > 0) and self:QuestState(e.id) or "unknown"
        local lab = STATE_LABEL[st] or STATE_LABEL.unknown
        out[#out + 1] = ("  %d. %s %s %s%s"):format(k, FAI.Engine:AskLink(e.t, "quest " .. e.t), c("dim", "[" .. tostring(e.l or "?") .. "]"),
            c(lab[1], lab[2]), e == q and c("gold", " <") or "")
    end
    return out
end

-- your current zone as a Questie area id
function C:AreaId()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if map and _G.QuestieLoader then
        local ok, z = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
        if ok and z and z.GetAreaIdByUiMapId then
            local ok2, area = pcall(z.GetAreaIdByUiMapId, z, map)
            if ok2 and area then return area end
        end
    end
end

-- quests you can pick up (optionally only in one zone), and chains you've started but not finished
function C:ScanQuests(level, area)
    local here, cont = {}, {}
    if not D.ready then return here, cont end
    for _, e in ipairs(D.index.quest) do
        local id = e[1]
        if not D.fq[id] then
            local ql = D:Get("quest", id, "questLevel") or 0
            if ql >= level - 4 and ql <= level + 3 then
                local zone = D:Get("quest", id, "zoneOrSort")
                local pre = firstOf(D:Get("quest", id, "preQuestSingle"))
                local isHere = area and zone == area
                local isCont = pre and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(pre)
                if (isHere or isCont) and self:QuestState(id) == "avail" then
                    if isHere then here[#here + 1] = { id = id, lvl = ql, name = e[3] } end
                    if isCont then cont[#cont + 1] = { id = id, lvl = ql, name = e[3], here = isHere } end
                end
            end
        end
    end
    table.sort(here, function(a, b) return a.lvl < b.lvl end)
    table.sort(cont, function(a, b) if a.here ~= b.here then return a.here end return a.lvl < b.lvl end)
    return here, cont
end

function C:ForeverHere(ctx)
    local zone, lvl, fac, list = T.norm(ctx.zone or ""), ctx.level or 1, (ctx.faction == "Alliance" and "A" or "H"), {}
    for _, e in ipairs(FAI.ForeverChains or {}) do
        if e.z and T.norm(e.z) == zone and (e.l or lvl) >= lvl - 4 and (e.m or 0) <= lvl
            and (e.f == "both" or e.f == fac or e.f == (fac == "A" and "Alli" or "Hord")) then
            local st = (e.id and e.id > 0) and self:QuestState(e.id) or "unknown"
            if st ~= "done" and st ~= "log" then list[#list + 1] = e end
        end
    end
    table.sort(list, function(a, b) return (a.l or 0) < (b.l or 0) end)
    return list
end

function C:QuestsHere(ctx)
    local here = self:ScanQuests(ctx.level or 1, self:AreaId())
    for _, e in ipairs(self:ForeverHere(ctx)) do here[#here + 1] = { id = e.id, lvl = e.l or 0, name = e.t, forever = true } end
    local out = { c("gold", "Quests you can pick up in " .. (ctx.zone or "this zone") .. ":") }
    for k = 1, math.min(12, #here) do
        local q = here[k]
        out[#out + 1] = ("  %s %s%s"):format(FAI.Engine:AskLink(q.name, "quest " .. q.name), c("dim", "[" .. q.lvl .. "]"), q.forever and c("gold", " Forever") or "")
    end
    if #here == 0 then out[#out + 1] = c("dim", "  Nothing new for your level here - ask 'where should I level'.") end
    if #here > 12 then out[#out + 1] = c("dim", ("  ...and %d more."):format(#here - 12)) end
    return out
end

function C:ChainsToContinue(ctx)
    local _, cont = self:ScanQuests(ctx.level or 1, self:AreaId())
    local out = { c("gold", "Chains you can continue:") }
    for k = 1, math.min(10, #cont) do
        local q = cont[k]
        out[#out + 1] = ("  %s %s%s"):format(FAI.Engine:AskLink(q.name, "chain " .. q.name), c("dim", "[" .. q.lvl .. "]"),
            q.here and c("ok", " - here") or "")
    end
    if #cont == 0 then out[#out + 1] = c("dim", "  No open follow-ups for your level right now.") end
    return out
end

-- "Suggested for you": a few clickable questions based on where you are, your level and your quest progress
function C:Suggestions()
    local ctx = FAI.Engine:Ctx()
    local lvl, out = ctx.level or 1, {}
    local function add(label, question) out[#out + 1] = "  " .. FAI.Engine:AskLink(label, question) end
    -- quest log: ready to turn in
    local ready = 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local q = C_QuestLog.GetInfo(i)
            if q and not q.isHeader and C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.questID) then ready = ready + 1 end
        end
    end
    if ready > 0 then add(("You have %d quest%s ready to turn in"):format(ready, ready > 1 and "s" or ""), "which quests should i do") end
    -- chains and quests here
    local here, cont = self:ScanQuests(lvl, self:AreaId())
    for _, e in ipairs(self:ForeverHere(ctx)) do here[#here + 1] = e end
    for k = 1, math.min(2, #cont) do add("Continue chain: " .. cont[k].name, "chain " .. cont[k].name) end
    if #here > 0 then add(("%d quests to pick up in %s"):format(#here, ctx.zone or "this zone"), "quests near me") end
    if _G.RXPFrame and _G.RXPFrame.activeSteps and #RXPFrame.activeSteps > 0 then add("Your next RestedXP step", "what should I do next") end
    -- level-based
    local fac = ctx.faction == "Alliance" and "A" or "H"
    local pick
    for _, d in ipairs(FAI.Dungeons) do
        if not d.raid and not d.unreleased and lvl >= d.min and lvl <= d.max - 2 and (d.f == fac or (d.f == "C" and not pick)) then
            pick = d
            if d.f == fac then break end
        end
    end
    if pick then add("Dungeon for your level: " .. pick.n, pick.n) end
    local milestones = { [10] = "class quests at level 10", [20] = "class quests at level 20", [30] = "class quests at level 30",
        [40] = "how do i get my mount", [60] = "what do i do at 60" }
    for at, q in pairs(milestones) do if lvl >= at and lvl <= at + 2 then add("Level " .. at .. ": " .. q, q) end end
    -- zone FAQ: researched answers that mention where you are
    local zone = ctx.zone and T.norm(ctx.zone)
    if zone and #zone > 3 then
        local n = 0
        for _, e in ipairs(FAI.KB) do
            local q1 = e.q and e.q[1]
            if q1 and not e._lore and not q1:find("lore") and not q1:find("story") and T.norm(table.concat(e.q, " ")):find(zone, 1, true) then
                add(T.cap((q1:gsub("%s+forever$", ""))), q1); n = n + 1
                if n >= 3 then break end
            end
        end
    end
    if #out == 0 then return nil end
    table.insert(out, 1, c("gold", "Suggested for you") .. c("dim", (" - level %d, %s"):format(lvl, ctx.zone or "?")))
    return out
end

-- extra intents for chains and nearby quests
table.insert(C.intents, 1, { test = function(q) return q:match("^chain (.+)") or q:match("^quest chain (.+)") or q:match("^what comes after (.+)")
        or q:match("^whats next after (.+)") or q:match("^next quest after (.+)") end,
    run = function(q)
        local name = q:match("^chain (.+)") or q:match("^quest chain (.+)") or q:match("^what comes after (.+)") or q:match("^whats next after (.+)")
            or q:match("^next quest after (.+)")
        local hit = D.ready and D:Find("quest", name, 1)[1]
        if hit and hit.score >= 60 and not D.fq[hit.id] then return C:ChainLines(hit.id) end
        local fq = (hit and D.fc[hit.id]) or D.fcByName[T.norm(name)]
        if fq then return C:ForeverChainLines(fq) end
    end })
table.insert(C.intents, 1, { test = function(q) return has(q, "chains i can", "chains can i", "continue a chain", "unfinished chain", "quest chains")
        and not q:match("^chain ") end,
    run = function(q, ctx) return C:ChainsToContinue(ctx) end })
table.insert(C.intents, 1, { test = function(q) return has(q, "quests near me", "quests here", "quests in this zone", "quests around here",
        "what can i do here", "anything to do here") end,
    run = function(q, ctx) return C:QuestsHere(ctx) end })
table.insert(C.intents, 1, { test = function(q) return q == "suggest" or q == "suggestions" or has(q, "suggest something", "what should i ask") end,
    run = function() return C:Suggestions() or { "Nothing specific to suggest right now - ask me anything." } end })

---------------------------------------------------------------- unlock checklist: everything your character still needs before a quest
local ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"
local ICON_TODO = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12|t"
local ICON_OPEN = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12|t"

local function listOf(v) return type(v) == "table" and v or {} end

function C:Manual()
    FAI.db = FAI.db or {}; FAI.db.manualDone = FAI.db.manualDone or {}
    local key = ((UnitName and UnitName("player")) or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
    FAI.db.manualDone[key] = FAI.db.manualDone[key] or {}
    return FAI.db.manualDone[key]
end

function C:IsDone(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) then return true end
    return self:Manual()[id] and true or false
end

-- prerequisites first, the target last; "one of" groups pick the branch you already did
function C:Prereqs(target)
    local order, seen = {}, {}
    local function visit(id, depth, oneOf)
        if not id or seen[id] or depth > 30 then return end
        seen[id] = true
        for _, p in ipairs(listOf(D:Get("quest", id, "preQuestGroup"))) do visit(p, depth + 1) end
        local single = listOf(D:Get("quest", id, "preQuestSingle"))
        if #single > 0 then
            local pick
            for _, p in ipairs(single) do if self:IsDone(p) then pick = p break end end
            visit(pick or single[1], depth + 1, #single > 1 and single or nil)
        end
        order[#order + 1] = { id = id, oneOf = oneOf }
    end
    visit(target, 0)
    return order
end

local function qname(id) return D:Get("quest", id, "name") or ("Quest " .. id) end

function C:Checklist(target, ctx)
    if FAI.Engine.Focus then FAI.Engine:Focus(target) end
    local steps = self:Prereqs(target)
    local level = (ctx and ctx.level) or (UnitLevel and UnitLevel("player")) or 1
    local done, nextStep = 0, nil
    local rows = {}
    for k, st in ipairs(steps) do
        local id = st.id
        local isDone = self:IsDone(id)
        local state = isDone and "done" or self:QuestState(id)
        local reqL = D:Get("quest", id, "requiredLevel") or 0
        if isDone then done = done + 1 end
        local icon, note = ICON_TODO, ""
        if isDone then icon = ICON_DONE
        elseif state == "log" then icon, note = ICON_OPEN, c("ffff00", " in your log")
        elseif state == "avail" then icon, note = ICON_OPEN, c("66ccff", " available now")
        elseif reqL > level then note = c("9a9a9a", " needs level " .. reqL)
        elseif state == "unknown" then note = c("9a9a9a", " can't check - ") .. FAI.Engine:AskLink("mark done", "mark done " .. id)
        end
        if not isDone and not nextStep and (state == "log" or state == "avail") then nextStep = id end
        local line = ("  %s %s %s%s"):format(icon, FAI.Engine:AskLink(qname(id), "quest " .. qname(id)), c("dim", "[" .. tostring(D:Get("quest", id, "questLevel") or "?") .. "]"), note)
        if st.oneOf then
            local alts = {}
            for _, a in ipairs(st.oneOf) do if a ~= id then alts[#alts + 1] = qname(a) end end
            if #alts > 0 then line = line .. c("dim", " (or: " .. table.concat(alts, ", ") .. ")") end
        end
        if isDone and self:Manual()[id] and not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)) then
            line = line .. " " .. FAI.Engine:AskLink(c("dim", "undo"), "unmark " .. id)
        end
        rows[#rows + 1] = line
    end
    local out = { c("gold", qname(target) .. " - unlock checklist") .. c("dim", (" (%d of %d done)"):format(done, #steps)) }
    if self:IsDone(target) then out[#out + 1] = c("ok", "  You've already completed " .. qname(target) .. ".") end
    for _, r in ipairs(rows) do out[#out + 1] = r end
    -- what to do right now
    if nextStep then
        local nm = qname(nextStep)
        if self:QuestState(nextStep) == "log" then
            out[#out + 1] = c("gold", "Next: ") .. "finish " .. c("quest", nm) .. " (it's in your log)."
            local fin = listOf(D:Get("quest", nextStep, "finishedBy"))
            local npc = fin[1] and firstOf(fin[1])
            if npc then
                local z, x, y = D:NpcSpot(npc); local who = D:Get("npc", npc, "name") or "?"
                out[#out + 1] = "  turn in: " .. c("npc", who) .. " - " .. D:Where(z, x, y) .. D:Pin(z, x, y, who)
            end
        else
            out[#out + 1] = c("gold", "Next: ") .. "pick up " .. c("quest", nm) .. "."
            local npc = firstOf(listOf(D:Get("quest", nextStep, "startedBy"))[1])
            if npc then
                local z, x, y = D:NpcSpot(npc); local who = D:Get("npc", npc, "name") or "?"
                out[#out + 1] = "  from: " .. c("npc", who) .. " - " .. D:Where(z, x, y) .. D:Pin(z, x, y, who)
            end
        end
        local obj = listOf(D:Get("quest", nextStep, "objectivesText"))[1]
        if obj and obj ~= "" then out[#out + 1] = "  " .. c("dim", obj:sub(1, 220)) end
    elseif done < #steps then
        local reqL = D:Get("quest", steps[1].id, "requiredLevel") or 0
        out[#out + 1] = c("dim", "Nothing on this list is open for you yet" .. (reqL > level and (" - the first step needs level " .. reqL) or "") .. ".")
    end
    -- and what comes after it
    local after, cur, seen = {}, target, {}
    for _ = 1, 6 do
        local nx = D:Get("quest", cur, "nextQuestInChain")
        if not nx or nx == 0 or seen[nx] then break end
        seen[nx] = true; after[#after + 1] = FAI.Engine:AskLink(qname(nx), "quest " .. qname(nx)); cur = nx
    end
    if #after > 0 then out[#out + 1] = c("dim", "After it: ") .. table.concat(after, c("dim", " > ")) end
    out[#out + 1] = c("dim", "Ticks come from your character's quest history. Click a quest for its details and map pin.")
    return out
end

local function findQuestId(name)
    name = name:gsub("^the quest ", ""):gsub(" quest$", ""):gsub("^quest ", ""):gsub("[%?%.!]+$", "")
    if not D.ready then return nil end
    local hit = D:Find("quest", name, 1)[1]
    if hit and hit.score >= 60 and not D.fq[hit.id] then return hit.id end
end
C.findQuestId = findQuestId

-- "how do i get in dreams": only when the rest is exactly a quest's name
table.insert(C.intents, 1, {
    test = function(q) return q:match("^how do i get (.+)$") or q:match("^how to get (.+)$") or q:match("^where do i get (.+)$") end,
    run = function(q, ctx)
        local name = (q:match("^how do i get (.+)$") or q:match("^how to get (.+)$") or q:match("^where do i get (.+)$")):gsub("^the ", "")
        if not D.ready then return nil end
        local hit = D:Find("quest", name, 1)[1]
        if hit and not D.fq[hit.id] and T.norm(hit.name or "") == T.norm(name) then return C:Checklist(hit.id, ctx) end
    end })

local CHECK_PATTERNS = { "^checklist for (.+)", "^checklist (.+)", "^how do i get the (.+) quest$", "^how do i get (.+) quest$",
    "^how do i unlock (.+)", "^what do i need for (.+)", "^what do i need to do for (.+)", "^requirements for (.+)",
    "^prereqs? for (.+)", "^can i get (.+) quest", "^how do i start (.+)", "^what do i need to start (.+)",
    "^how do i get to the (.+) quest", "^where do i start (.+) chain", "^chain (.+)", "^quest chain (.+)" }

table.insert(C.intents, 1, {
    test = function(q) for _, p in ipairs(CHECK_PATTERNS) do if q:match(p) then return true end end end,
    run = function(q, ctx)
        for _, p in ipairs(CHECK_PATTERNS) do
            local name = q:match(p)
            if name then
                local id = findQuestId(name)
                if id then return C:Checklist(id, ctx) end
                local fq = D.fcByName[T.norm(name)]
                if fq then return C:ForeverChainLines(fq) end
                return nil
            end
        end
    end })

-- manual ticks for quests the game can't confirm (Forever-only ones Questie doesn't know)
table.insert(C.intents, 1, {
    test = function(q) return q:match("^mark done (%d+)$") or q:match("^unmark (%d+)$") end,
    run = function(q)
        local id = tonumber(q:match("(%d+)$"))
        if q:find("^unmark") then C:Manual()[id] = nil; return { "Unticked " .. qname(id) .. "." } end
        C:Manual()[id] = true
        return { c("ok", "Ticked " .. qname(id) .. " as done.") .. c("dim", " (saved for this character; 'unmark " .. id .. "' to undo)") }
    end })


---------------------------------------------------------------- the route: every stop left on a quest chain, in order, with pins
function C:RouteStops(target)
    local stops = {}
    local function npcStop(npc, label, qid)
        if not npc then return end
        local z, x, y = D:NpcSpot(npc)
        if z then stops[#stops + 1] = { z = z, x = x, y = y, who = D:Get("npc", npc, "name") or "?", what = label, q = qid } end
    end
    for _, st in ipairs(self:Prereqs(target)) do
        local id = st.id
        if not self:IsDone(id) then
            local inLog = self:QuestState(id) == "log"
            if not inLog then npcStop(firstOf(listOf(D:Get("quest", id, "startedBy"))[1]), "pick up", id) end
            local obj = listOf(D:Get("quest", id, "objectivesText"))[1]
            if obj and obj ~= "" then stops[#stops + 1] = { note = obj, q = id } end
            npcStop(firstOf(listOf(D:Get("quest", id, "finishedBy"))[1]), "turn in", id)
        end
    end
    return stops
end

function C:RouteLines(target)
    local stops = self:RouteStops(target)
    local out = { c("gold", "Route for " .. qname(target)) .. c("dim", " - every stop you have left, in order") }
    local n = 0
    for _, s in ipairs(stops) do
        if s.note then
            out[#out + 1] = "      " .. c("dim", s.note:sub(1, 160))
        else
            n = n + 1
            out[#out + 1] = ("  %d. %s %s: %s - %s%s"):format(n, s.what, c("quest", qname(s.q)), c("npc", s.who), D:Where(s.z, s.x, s.y), D:Pin(s.z, s.x, s.y, s.who))
        end
    end
    if n == 0 then out[#out + 1] = c("ok", "  Nothing left - you've done every step.") return out end
    out[#out + 1] = "  " .. FAI.Engine:AskLink("Pin every stop on my map", "pin route") .. c("dim", _G.TomTom and " (TomTom arrows)" or " (the map holds one pin at a time; TomTom shows them all)")
    return out
end

function C:PinRoute(target)
    local set = 0
    for _, s in ipairs(self:RouteStops(target)) do
        if s.z and D:SetWaypoint(s.z, s.x, s.y, s.who .. " (" .. qname(s.q) .. ")") then
            set = set + 1
            if not _G.TomTom then break end -- the built-in map takes one pin: the first stop
        end
    end
    if set == 0 then return { c("warn", "Couldn't place pins (no map location for these NPCs).") } end
    return { c("ok", _G.TomTom and ("Pinned all %d stops (TomTom)."):format(set) or "Pinned your first stop on the map. Install TomTom to see every stop at once.") }
end

local ROUTE_WORDS = { "in order", "route", "coordinates", "coords", "waypoint", "where i need to go", "where do i go", "path", "pin " }
table.insert(C.intents, 1, {
    test = function(q)
        if q == "pin route" then return true end
        for _, w in ipairs(ROUTE_WORDS) do if q:find(w, 1, true) then return FAI.Engine:Focus() ~= nil end end
    end,
    run = function(q)
        local id = FAI.Engine:Focus()
        if not id then return nil end
        if q == "pin route" or q:find("^pin") or q:find("waypoints? on") or q:find("set waypoint") then
            local out = C:PinRoute(id)
            for _, l in ipairs(C:RouteLines(id)) do out[#out + 1] = l end
            return out
        end
        return C:RouteLines(id)
    end })
