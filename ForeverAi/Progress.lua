-- ForeverAi: your character's history. Quests you've finished, follow-ups you never picked up,
-- and items in your bags or bank that matter for a quest. The bank is remembered each time you open it.
local _, FAI = ...
local T, D, C = FAI.Text, FAI.Data, FAI.Composer
local P = {}
FAI.Progress = P
local c = T.c

local function listOf(v) return type(v) == "table" and v or {} end
local function qname(id) return D:Get("quest", id, "name") or ("Quest " .. id) end
local function iname(id) return D:Get("item", id, "name") or (GetItemInfo and GetItemInfo(id)) or ("Item " .. id) end
local function ask(label, q) return FAI.Engine:AskLink(label, q) end

local function charKey()
    return ((UnitName and UnitName("player")) or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
end

---------------------------------------------------------------- bank memory
local function bankBagIds()
    local ids, seen = {}, {}
    local function add(v) if type(v) == "number" and not seen[v] then seen[v] = true; ids[#ids + 1] = v end end
    add(-1)                       -- main bank slots
    for b = 5, 12 do add(b) end   -- bank bags (ids differ between client versions; empty ids just have 0 slots)
    if Enum and Enum.BagIndex then
        for k, v in pairs(Enum.BagIndex) do
            if type(k) == "string" and (k:find("Bank") or k:find("Reagent")) and not k:find("Account") then add(v) end
        end
    end
    return ids
end

function P:SnapshotBank()
    if not (C_Container and C_Container.GetContainerNumSlots) then return end
    local items, any = {}, false
    for _, bag in ipairs(bankBagIds()) do
        if bag < 0 or bag > 5 then
            local n = C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, n do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then items[info.itemID] = (items[info.itemID] or 0) + (info.stackCount or 1); any = true end
            end
        end
    end
    FAI.db.bank = FAI.db.bank or {}
    FAI.db.bank[charKey()] = { t = time(), items = items, any = any }
end

local bankOpen = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("BANKFRAME_CLOSED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
ev:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then bankOpen = true; C_Timer.After(0.5, function() P:SnapshotBank() end)
    elseif event == "BANKFRAME_CLOSED" then if bankOpen then P:SnapshotBank() end; bankOpen = false
    elseif bankOpen then P:SnapshotBank() end
end)

function P:Bank() return FAI.db.bank and FAI.db.bank[charKey()] end

-- everything you own: id -> { bags = n, bank = n }
function P:Owned()
    local own = {}
    for _, it in ipairs(C:BagItems()) do
        own[it.id] = own[it.id] or { bags = 0, bank = 0 }
        own[it.id].bags = own[it.id].bags + (it.count or 1)
    end
    local b = self:Bank()
    for id, n in pairs(b and b.items or {}) do
        own[id] = own[id] or { bags = 0, bank = 0 }
        own[id].bank = n
    end
    return own
end

---------------------------------------------------------------- lost progression
-- quests whose prerequisites you finished but you never picked up (any level, not just near yours)
function P:Missed(force)
    local now = GetTime and GetTime() or 0
    if not force and self._missed and now - (self._missedAt or 0) < 120 then return self._missed end
    local out = {}
    if not D.ready then return out end
    for _, e in ipairs(D.index.quest) do
        local id = e[1]
        if not D.fq[id] and not C:IsDone(id) then
            local pg, ps = listOf(D:Get("quest", id, "preQuestGroup")), listOf(D:Get("quest", id, "preQuestSingle"))
            if #pg > 0 or #ps > 0 then
                local ok = true
                for _, p in ipairs(pg) do if not C:IsDone(p) then ok = false break end end
                if ok and #ps > 0 then
                    local any = false
                    for _, p in ipairs(ps) do if C:IsDone(p) then any = true break end end
                    ok = any
                end
                if ok and C:QuestState(id) == "avail" then
                    out[#out + 1] = { id = id, name = e[3] or qname(id), lvl = D:Get("quest", id, "questLevel") or 0,
                        after = (#ps > 0 and ps[1]) or pg[#pg] }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.lvl > b.lvl end)
    self._missed, self._missedAt = out, now
    return out
end

function P:MissedLines(ctx)
    if not D:Has() then return C:NeedDB() end
    local list = self:Missed(true)
    local level = (ctx and ctx.level) or 1
    local out = { c("gold", "Follow-up quests you never picked up") .. c("dim", (" (%d)"):format(#list)) }
    if not D.ready then return { c("warn", "Questie's database is still loading - ask again in a few seconds.") } end
    if #list == 0 then out[#out + 1] = c("ok", "  None - every chain you started is either finished or in your log.") return out end
    local shown = 0
    for _, q in ipairs(list) do
        if shown >= 15 then break end
        shown = shown + 1
        local grey = q.lvl > 0 and q.lvl < level - 9
        local s = listOf(D:Get("quest", q.id, "startedBy"))
        local npc = type(s[1]) == "table" and s[1][1]
        local where = ""
        if npc then
            local z, x, y = D:NpcSpot(npc)
            local who = D:Get("npc", npc, "name")
            if z and who then where = c("dim", " - " .. who .. ", ") .. D:Where(z, x, y) .. D:Pin(z, x, y, who) end
        end
        out[#out + 1] = ("  %s %s%s%s"):format(ask(q.name, "checklist " .. q.name), c(grey and "9a9a9a" or "dim", "[" .. q.lvl .. "]"),
            c("dim", " after " .. qname(q.after)), where)
    end
    if #list > shown then out[#out + 1] = c("dim", ("  ...and %d more (lower level)."):format(#list - shown)) end
    out[#out + 1] = c("dim", "Grey levels still give the reward and reputation, just little XP. Click one for its checklist.")
    return out
end

---------------------------------------------------------------- items that matter
-- items needed by quests in your log or by follow-ups you can pick up
local function neededItems()
    local need = {}
    local function addQuest(id, why)
        local obj = listOf(D:Get("quest", id, "objectives"))
        for _, it in ipairs(listOf(obj[3])) do
            local iid = type(it) == "table" and it[1] or it
            if type(iid) == "number" then need[iid] = need[iid] or { quest = id, why = why } end
        end
        for _, iid in ipairs(listOf(D:Get("quest", id, "requiredSourceItems"))) do
            if type(iid) == "number" then need[iid] = need[iid] or { quest = id, why = why } end
        end
    end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then addQuest(info.questID, "log") end
        end
    end
    for _, q in ipairs(P:Missed()) do addQuest(q.id, "missed") end
    return need
end

function P:ImportantItems()
    local own = self:Owned()
    local need = neededItems()
    local rows = {}
    for id, n in pairs(own) do
        local where = (n.bags > 0 and n.bank > 0) and "bags + bank" or (n.bank > 0 and "bank" or "bags")
        local starts = D:Get("item", id, "startQuest")
        starts = type(starts) == "table" and starts[1] or starts
        if type(starts) == "number" and starts > 0 and not C:IsDone(starts) and C:QuestState(starts) ~= "log" then
            rows[#rows + 1] = { bank = n.bank > 0, text = ("  %s %s starts %s - you haven't done it."):format(
                D:ItemLink(id, iname(id)), c("dim", "(" .. where .. ")"), ask(qname(starts), "checklist " .. qname(starts))) }
        elseif need[id] then
            local nq = need[id]
            rows[#rows + 1] = { bank = n.bank > 0, text = ("  %s %s is needed for %s%s"):format(
                D:ItemLink(id, iname(id)), c("dim", "(" .. where .. ")"), ask(qname(nq.quest), "checklist " .. qname(nq.quest)),
                nq.why == "log" and c("dim", " (in your log)") or c("dim", " (follow-up you can pick up)")) }
        end
    end
    table.sort(rows, function(a, b) if a.bank ~= b.bank then return a.bank end return a.text < b.text end)
    local out = { c("gold", "Items you own that matter for a quest") }
    for k = 1, math.min(20, #rows) do out[#out + 1] = rows[k].text end
    if #rows == 0 then out[#out + 1] = c("dim", "  Nothing in your bags or bank starts or finishes an open quest.") end
    local b = self:Bank()
    if not b then out[#out + 1] = c("warn", "  I haven't seen your bank yet - open it once at any banker and I'll include it.")
    else out[#out + 1] = c("dim", "  Bank as of " .. date("%b %d %H:%M", b.t) .. " (updates whenever you open it).") end
    return out
end

---------------------------------------------------------------- "have i done X"
function P:DoneLines(name)
    if not D:Has() then return C:NeedDB() end
    local id = C.findQuestId and C.findQuestId(name)
    if not id then return nil end
    if C:IsDone(id) then return { c("ok", "Yes") .. " - you've completed " .. c("quest", qname(id)) .. " on this character.",
        "  " .. ask("What comes after it?", "checklist " .. qname(id)) } end
    local st = C:QuestState(id)
    local msg = st == "log" and "No - it's in your quest log right now." or st == "avail" and "No - and you can pick it up now."
        or "No - you haven't done it yet."
    return { c("warn", "Not yet: ") .. c("quest", qname(id)) .. ". " .. msg, "  " .. ask("Show its unlock checklist", "checklist " .. qname(id)) }
end

---------------------------------------------------------------- intents
local function has(q, ...) for _, w in ipairs({ ... }) do if q:find(w, 1, true) then return true end end end

table.insert(C.intents, 1, {
    test = function(q) return q:match("^have i done (.+)") or q:match("^did i do (.+)") or q:match("^did i complete (.+)")
        or q:match("^did i finish (.+)") or q:match("^have i completed (.+)") or q:match("^have i finished (.+)") end,
    run = function(q)
        local name = q:match("^have i done (.+)") or q:match("^did i do (.+)") or q:match("^did i complete (.+)")
            or q:match("^did i finish (.+)") or q:match("^have i completed (.+)") or q:match("^have i finished (.+)")
        return P:DoneLines((name:gsub("^the ", ""):gsub(" quest$", "")))
    end })
table.insert(C.intents, 1, {
    test = function(q) return has(q, "lost progress", "missed quest", "quests i missed", "did i miss", "never picked up", "forgot to pick up",
        "skipped quest", "unfinished chain", "chains i left", "left unfinished", "follow up quest", "followup quest", "breadcrumb") end,
    run = function(q, ctx) return P:MissedLines(ctx) end })
table.insert(C.intents, 1, {
    test = function(q) return has(q, "whats in my bank", "items in my bank", "anything important", "important items", "quest items i have",
        "items i need for quests", "should i keep", "items for quests", "keep in my bank", "my bank for quests", "do i have any quest items") end,
    run = function() return P:ImportantItems() end })

-- a line in "Suggested for you" when there's lost progress
local base = C.Suggestions
function C:Suggestions()
    local out = base(self)
    local ok, list = pcall(P.Missed, P)
    if ok and list and #list > 0 then
        out = out or { c("gold", "Suggested for you") }
        table.insert(out, 2, "  " .. ask(("%d follow-up quest%s you never picked up"):format(#list, #list > 1 and "s" or ""), "lost progress"))
    end
    return out
end
