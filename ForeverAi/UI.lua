-- UI: a clean, Blizzard-styled chat window. Type, press Enter, and the answer appears.
-- Live answers: the question is shown to ForeverAi Companion as a tiny strip of colored cells in the title bar (the "bridge"),
-- and the companion draws Gemini's answer exactly over this window's answer panel. No extra keys.
local _, FAI = ...
local T = FAI.Text
local UI = {}
FAI.UI = UI

local frame, out, input, panel
local histPos

local function newId()
    local chars, id = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789", ""
    for _ = 1, 8 do local n = math.random(#chars); id = id .. chars:sub(n, n) end
    return id
end

---------------------------------------------------------------- the bridge (pure encoding: testable outside the game)
local Bridge = { W = 64, CELL = 3, state = 0, id = "", payload = "", scroll = 0 }
FAI.Bridge = Bridge

-- Cell values 0-7 = RGB bits (R=4, G=2, B=1). Row 0 starts with the finder: magenta, cyan, yellow.
function Bridge.Encode(state, dx, dy, w, h, id, payload)
    local bytes = { 1, state }
    local function u16(v)
        v = math.max(0, math.min(65535, math.floor(v + 0.5)))
        bytes[#bytes + 1] = math.floor(v / 256); bytes[#bytes + 1] = v % 256
    end
    u16(dx + 32768); u16(dy + 32768); u16(w); u16(h)
    id = (id or ""):sub(1, 8)
    for i = 1, 8 do bytes[#bytes + 1] = id:byte(i) or 0 end
    payload = payload or ""
    u16(#payload)
    for i = 1, #payload do bytes[#bytes + 1] = payload:byte(i) end
    local sum = 0
    for i = 1, #bytes do sum = (sum + bytes[i]) % 65536 end
    u16(sum)
    local cells = { 5, 3, 6 }
    local acc, n = 0, 0
    for i = 1, #bytes do
        local b = bytes[i]
        for k = 7, 0, -1 do
            acc = acc * 2 + math.floor(b / 2 ^ k) % 2
            n = n + 1
            if n == 3 then cells[#cells + 1] = acc; acc, n = 0, 0 end
        end
    end
    if n > 0 then cells[#cells + 1] = acc * 2 ^ (3 - n) end
    return cells
end

---------------------------------------------------------------- the bridge (in-game rendering)
local function round(v) return math.floor(v + 0.5) end

function Bridge:Init()
    local b = CreateFrame("Frame", nil, UIParent)
    b:SetFrameStrata("TOOLTIP")
    b:SetSize(1, 1)
    self.frame, self.tex, self.key = b, {}, nil
    b:SetScript("OnUpdate", function() Bridge:Update() end)
end

function Bridge:Set(state, id, payload)
    self.state, self.id, self.payload, self.scroll = state, id or "", payload or "", 0
end

function Bridge:Update()
    local b = self.frame
    if not (frame and frame:IsVisible() and UIParent:IsVisible()) then
        for _, t in ipairs(self.tex) do t:Hide() end
        return
    end
    local _, physH = GetPhysicalScreenSize()
    local k = physH / UIParent:GetHeight()                 -- physical pixels per UI unit
    b:SetScale(1 / k)                                     -- now 1 bridge unit = 1 physical pixel
    local right, top = frame:GetRight(), frame:GetTop()
    if not (right and top) then return end
    local width = self.W * self.CELL
    local bx, by = round((right - 36) * k) - width, round((top - 8) * k)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", bx, by)
    -- where the companion should draw: the answer panel, relative to the bridge's top-left
    local pl, pt = round(panel:GetLeft() * k), round(panel:GetTop() * k)
    local pw, ph = round(panel:GetWidth() * k), round(panel:GetHeight() * k)
    -- state byte: bit 0 = live panel shown, bits 1-7 = how far you've scrolled the answer (mouse wheel over the panel)
    local state = (self.state == 1 and panel:IsShown()) and (1 + 2 * (self.scroll or 0)) or 0
    local key = table.concat({ state, pl - bx, by - pt, pw, ph, self.id, self.payload }, "\31")
    if key == self.key then return end
    self.key = key
    local cells = Bridge.Encode(state, pl - bx, by - pt, pw, ph, state == 1 and self.id or "", state == 1 and self.payload or "")
    for i, v in ipairs(cells) do
        local t = self.tex[i]
        if not t then
            t = b:CreateTexture(nil, "OVERLAY")
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
            t:SetSize(self.CELL, self.CELL)
            self.tex[i] = t
        end
        local c = i - 1
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", b, "TOPLEFT", (c % self.W) * self.CELL, -math.floor(c / self.W) * self.CELL)
        t:SetColorTexture(v >= 4 and 1 or 0, math.floor(v / 2) % 2, v % 2, 1)
        t:Show()
    end
    for i = #cells + 1, #self.tex do self.tex[i]:Hide() end
end

---------------------------------------------------------------- window
local function build()
    frame = CreateFrame("Frame", "ForeverAiFrame", UIParent, "BackdropTemplate")
    frame:SetSize(480, 380)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(380, 240, 900, 800) end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        FAI.db.pos = { p, rp, x, y, self:GetWidth(), self:GetHeight() }
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    local pos = FAI.db and FAI.db.pos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        if pos[5] then frame:SetSize(pos[5], pos[6]) end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    tinsert(UISpecialFrames, "ForeverAiFrame") -- Esc closes it like any Blizzard window

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Forever|cffffffffAi|r")
    local notice = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    notice:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    notice:SetText("Live answers need WoW in Windowed or Borderless mode, with ForeverAi Companion running.")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    out = CreateFrame("ScrollingMessageFrame", nil, frame)
    out:SetPoint("TOPLEFT", 16, -52)
    out:SetPoint("BOTTOMRIGHT", -16, 46)
    out:SetFontObject(ChatFontNormal)
    out:SetJustifyH("LEFT")
    out:SetFading(false)
    out:SetMaxLines(600)
    out:SetInsertMode(SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM or "BOTTOM")
    out:SetHyperlinksEnabled(true)
    out:EnableMouseWheel(true)
    out:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp(); self:ScrollUp() else self:ScrollDown(); self:ScrollDown() end
    end)
    out:SetScript("OnHyperlinkClick", function(_, link, text, button)
        local kind, rest = link:match("^foreverai:(%a+):(.*)$")
        if kind == "pin" or kind == "pinm" then
            local area, x, y, ttl = rest:match("^(%d+):([%d%.]+):([%d%.]+):?(.*)$")
            if area and FAI.Data:SetWaypoint(tonumber(area), tonumber(x), tonumber(y), ttl, kind == "pinm") then
                UI:Say(T.c("ok", "Waypoint set" .. (ttl ~= "" and (": " .. ttl) or "") .. "."))
            else
                UI:Say(T.c("warn", "Couldn't place a waypoint for that zone."))
            end
        elseif kind == "ask" then
            UI:Ask(rest)
        elseif not kind then
            SetItemRef(link, text, button)
        end
    end)
    out:SetScript("OnHyperlinkEnter", function(self, link)
        if link:match("^item:") then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end
    end)
    out:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)

    -- live answer panel: covers the answer area while a live answer is shown; the companion draws on top of it
    panel = CreateFrame("Frame", nil, frame)
    panel:SetAllPoints(out)
    panel:SetFrameLevel(out:GetFrameLevel() + 5)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(10 / 255, 10 / 255, 13 / 255, 1)     -- same color the companion paints
    panel.q = panel:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    panel.q:SetPoint("TOPLEFT", 8, -8); panel.q:SetPoint("TOPRIGHT", -8, -8)
    panel.q:SetJustifyH("LEFT")
    panel.msg = panel:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    panel.msg:SetPoint("TOPLEFT", panel.q, "BOTTOMLEFT", 0, -8); panel.msg:SetPoint("RIGHT", -8, 0)
    panel.msg:SetJustifyH("LEFT"); panel.msg:SetJustifyV("TOP")
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        Bridge.scroll = math.max(0, math.min(127, (Bridge.scroll or 0) - delta))
    end)
    panel:Hide()

    local back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    back:SetSize(70, 20)
    back:SetPoint("TOPRIGHT", -34, -12)
    back:SetText("History")
    back:SetScript("OnClick", function()
        if panel:IsShown() then UI:ClosePanel() elseif UI.lastLive then UI:ReopenPanel() end
    end)
    UI.back = back
    back:Hide()

    -- New chat: the companion forgets the conversation so far (follow-ups otherwise use the last few questions)
    local newChat = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    newChat:SetSize(80, 20)
    newChat:SetPoint("RIGHT", back, "LEFT", -6, 0)
    newChat:SetText("New chat")
    newChat:SetScript("OnClick", function() UI:NewChat() end)

    input = CreateFrame("EditBox", "ForeverAiInput", frame, "InputBoxTemplate")
    input:SetPoint("BOTTOMLEFT", 22, 14)
    input:SetPoint("BOTTOMRIGHT", -36, 14)
    input:SetHeight(24)
    input:SetAutoFocus(false)
    input:SetMaxLetters(250)
    input:SetFontObject(ChatFontNormal)
    input:SetScript("OnEnterPressed", function(self)
        local text = strtrim(self:GetText())
        self:SetText("")
        if text ~= "" then UI:Ask(text) end
    end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Hide() end)
    input:SetScript("OnArrowPressed", function(self, key)
        local h = FAI.db.history
        if #h == 0 then return end
        if key == "UP" then histPos = math.max(1, (histPos or #h + 1) - 1)
        elseif key == "DOWN" then histPos = math.min(#h + 1, (histPos or #h + 1) + 1) end
        self:SetText(h[histPos] or "")
        self:SetCursorPosition(#self:GetText())
    end)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -6, 6)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        local p, _, rp, x, y = frame:GetPoint()
        FAI.db.pos = { p, rp, x, y, frame:GetWidth(), frame:GetHeight() }
    end)

    Bridge:Init()

    UI:Say(T.c("gold", "ForeverAi") .. " ready. Ask anything - try:")
    for _, ex in ipairs({ "where is Hogger", "best gold farm at 60", "how do I get to Mount Hyjal", "what should I do next" }) do
        UI:Say("  " .. FAI.Engine:AskLink(ex, ex))
    end
    frame:Hide()
end

function UI:Say(text)
    if not out then build() end
    out:AddMessage(text)
end

---------------------------------------------------------------- conversations
function UI:NewChat(quiet)
    FAI.db.chatId = newId()
    FAI.db.chatAt = time()
    UI:ClosePanel()
    UI.lastLive = nil
    if UI.back then UI.back:Hide() end
    if not quiet then UI:Say(T.c("gold", "New chat started") .. T.c("dim", " - ForeverAi won't connect your next question to earlier ones.")) end
end

function UI:ChatId()
    local db = FAI.db
    if not db.chatId then UI:NewChat(true) end -- only the New chat button starts over
    db.chatAt = time()
    return db.chatId
end

---------------------------------------------------------------- live panel
function UI:OpenPanel(question, id, quick)
    panel.q:SetText(T.c("you", "> " .. question))
    local msg = T.c("dim", "ForeverAi is thinking...")
    if quick and #quick > 0 then msg = msg .. "\n\n" .. T.c("dim", "Quick answer while you wait:") .. "\n" .. table.concat(quick, "\n") end
    panel.msg:SetText(msg)
    panel:Show()
    UI.back:SetText("History"); UI.back:Show()
    UI.lastLive = { id = id }
    Bridge:Set(1, id, FAI.Engine:LiveContext() .. ";chat=" .. UI:ChatId() .. "~" .. question:gsub("[~|]", " "))
    -- the full question only needs to be on screen briefly; afterwards keep just the header (window position + id)
    C_Timer.After(4, function() if Bridge.id == id then Bridge.payload = "" end end)
    C_Timer.After(30, function()
        if Bridge.id == id and panel:IsShown() then
            panel.msg:SetText(panel.msg:GetText() .. "\n\n" .. T.c("warn",
                "No live answer yet? Make sure ForeverAi Companion is running and WoW is in Windowed or Borderless mode."))
        end
    end)
end

function UI:ClosePanel()
    if not panel then return end
    panel:Hide()
    if UI.lastLive then UI.back:SetText("Live"); UI.back:Show() else UI.back:Hide() end
    Bridge:Set(0, "", "")
end

-- bring the last live answer back (the companion keeps it and redraws it)
function UI:ReopenPanel()
    panel:Show()
    UI.back:SetText("History")
    Bridge:Set(1, UI.lastLive.id, "")
end

---------------------------------------------------------------- asking
function UI:Ask(question)
    if not frame then build() end
    local h = FAI.db.history
    if h[#h] ~= question then h[#h + 1] = question end
    while #h > 50 do table.remove(h, 1) end
    histPos = nil

    FAI.Engine.lastKind = nil
    local ok, lines = pcall(FAI.Engine.Answer, FAI.Engine, question)
    if not ok then FAI.lastError = lines; lines = {} end
    local kind = FAI.Engine.lastKind

    out:AddMessage(" ")
    out:AddMessage(T.c("you", "> " .. question))
    if kind == "lookup" then
        -- exact database answers (NPCs, items, quests with pins) stay instant and in the history
        UI:ClosePanel()
        for _, line in ipairs(lines or {}) do out:AddMessage(line) end
    else
        local quick = (kind == "kb") and lines or nil
        pcall(FAI.Engine.BuildLiveExtra, FAI.Engine, question, quick)
        if quick then for _, line in ipairs(quick) do out:AddMessage(line) end end
        out:AddMessage(T.c("dim", "(asked ForeverAi live)"))
        UI:OpenPanel(question, newId(), quick)
    end
    out:ScrollToBottom()
end

function UI:ShowSuggestions(force)
    local zone = GetZoneText and GetZoneText() or ""
    local now = GetTime and GetTime() or 0
    if not force and UI.sugZone == zone and UI.sugAt and now - UI.sugAt < 180 then return end
    UI.sugZone, UI.sugAt = zone, now
    local ok, lines = pcall(FAI.Composer.Suggestions, FAI.Composer)
    if ok and lines then
        out:AddMessage(" ")
        for _, l in ipairs(lines) do out:AddMessage(l) end
        out:ScrollToBottom()
    elseif not ok then FAI.lastError = lines end
end

function UI:Show()
    if not frame then build() end
    frame:Show()
    input:SetFocus()
    if FAI.Data.ready and FAI.Composer then UI:ShowSuggestions() end
end

function UI:Toggle()
    if not frame then build() end
    if frame:IsShown() then frame:Hide() else UI:Show() end
end
