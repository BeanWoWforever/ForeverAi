-- ForeverAi: core namespace, saved data, slash commands, keybinding.
local ADDON, FAI = ...
_G.ForeverAi = FAI

FAI.version = "0.1.0"
FAI.KB, FAI.Zones, FAI.Dungeons = {}, {}, {}

BINDING_HEADER_FOREVERAI = "ForeverAi"
BINDING_NAME_FOREVERAI_TOGGLE = "Open / close ForeverAi"

function ForeverAi_Toggle()
    FAI.UI:Toggle()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ForeverAiDB = ForeverAiDB or {}
        local db = ForeverAiDB
        db.unanswered = db.unanswered or {}   -- questions the updater will learn from
        db.history = db.history or {}         -- your last questions (up-arrow recall)
        FAI.db = db
    elseif event == "PLAYER_LOGIN" then
        FAI.Engine:BuildKBIndex()
        FAI.Data:StartIndexing()
    end
end)

SLASH_FOREVERAI1 = "/fai"
SLASH_FOREVERAI2 = "/foreverai"
SlashCmdList.FOREVERAI = function(msg)
    msg = strtrim(msg or "")
    if msg == "" then
        FAI.UI:Toggle()

    else
        FAI.UI:Show()
        FAI.UI:Ask(msg)
    end
end
