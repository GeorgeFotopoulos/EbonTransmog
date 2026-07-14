-- EbonTransmog: core/Init.lua
EbonTransmog = EbonTransmog or {}
EbonTransmog.VERSION = "1.0.0"

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        EbonTransmogDB = EbonTransmogDB or {}
        EbonTransmogDB.collectedAppearances = EbonTransmogDB.collectedAppearances or {}
        EbonTransmogDB.loadouts = EbonTransmogDB.loadouts or {}
        EbonTransmogDB.itemInfoCache = EbonTransmogDB.itemInfoCache or {}
        EbonTransmogDB.lastLoadoutName = EbonTransmogDB.lastLoadoutName or nil
        if EbonTransmogDB.minimapAngle == nil then
            EbonTransmogDB.minimapAngle = 220
        end

        if EbonTransmog.AppearanceService then
            EbonTransmog.AppearanceService.ProbeAPIs()
            EbonTransmog.AppearanceService.InstallChatHook()
            EbonTransmog.AppearanceService.InstallServerHook()
            EbonTransmog.AppearanceService.MigrateLegacyItemInfoCache()
            EbonTransmog.AppearanceService.RepairCacheEntries()
        end

        if EbonTransmog.LoadoutService then
            EbonTransmog.LoadoutService.MigrateLegacySlots()
        end

        if EbonTransmog.TransmogJournal and EbonTransmog.TransmogJournal.Init then
            EbonTransmog.TransmogJournal.Init()
        end

        if EbonTransmog.MinimapButton and EbonTransmog.MinimapButton.Init then
            EbonTransmog.MinimapButton.Init()
        end

        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

SLASH_EBONTRANSMOG1 = "/transmog"
SLASH_EBONTRANSMOG2 = "/tmog"
SlashCmdList["EBONTRANSMOG"] = function()
    if EbonTransmog.TransmogJournal then
        EbonTransmog.TransmogJournal.Toggle()
    end
end

SLASH_EBONTRANSMOGAPIS1 = "/etmog"
SlashCmdList["EBONTRANSMOGAPIS"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "apis" then
        if EbonTransmog.AppearanceService then
            EbonTransmog.AppearanceService.PrintProbeResults()
        end
    elseif msg == "scan" then
        if EbonTransmog.GossipScraper then
            EbonTransmog.GossipScraper.StartScan({})
        end
    elseif msg:match("^scan%s+") then
        local args = msg:match("^scan%s+(.+)$") or ""
        if args == "stop" then
            if EbonTransmog.GossipScraper then
                EbonTransmog.GossipScraper.StopScan()
            end
        elseif EbonTransmog.GossipScraper then
            local options = EbonTransmog.GossipScraper.ParseScanOptions(args)
            EbonTransmog.GossipScraper.StartScan(options)
        end
    elseif msg == "scan stop" or msg == "stop" then
        if EbonTransmog.GossipScraper then
            EbonTransmog.GossipScraper.StopScan()
        end
    elseif msg == "harvest" then
        if EbonTransmog.GossipScraper then
            EbonTransmog.GossipScraper.HarvestCurrentGossip()
        end
    elseif msg == "apply cancel" or msg == "cancel apply" then
        if EbonTransmog.LoadoutApplier then
            EbonTransmog.LoadoutApplier.CancelPending()
        end
    elseif msg:match("^apply%s+(.+)$") then
        local name = msg:match("^apply%s+(.+)$")
        if name and EbonTransmog.LoadoutApplier then
            EbonTransmog.LoadoutApplier.Apply(name)
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[EbonTransmog]|r Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /transmog, /tmog — open journal")
        DEFAULT_CHAT_FRAME:AddMessage("  /etmog apis — API probe")
        DEFAULT_CHAT_FRAME:AddMessage("  /etmog scan — full scan (all slots & pages)")
        DEFAULT_CHAT_FRAME:AddMessage("  /etmog scan fast — faster full scan (skips page rewind)")
        DEFAULT_CHAT_FRAME:AddMessage("  /etmog scan slot — scan only the open slot (open a slot list first)")
        DEFAULT_CHAT_FRAME:AddMessage("  /etmog scan head chest — scan specific slots only")
        DEFAULT_CHAT_FRAME:AddMessage("  /etmog harvest — import current gossip page only")
        DEFAULT_CHAT_FRAME:AddMessage("  /etmog apply <name> — queue apply at Warpweaver (journal closes)")
        DEFAULT_CHAT_FRAME:AddMessage("  /etmog apply cancel — cancel queued apply")
        DEFAULT_CHAT_FRAME:AddMessage("  /etmog scan stop — cancel scan")
    end
end
