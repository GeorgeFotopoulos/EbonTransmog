-- EbonTransmog: modules/ui/MinimapButton.lua
-- Draggable minimap button that toggles the Transmog Journal.

EbonTransmog = EbonTransmog or {}
EbonTransmog.MinimapButton = {}

local MinimapButton = EbonTransmog.MinimapButton

local BUTTON_NAME = "EbonTransmogMinimapButton"
local RADIUS = 80
-- Retail Transmog/Wardrobe frame portrait (Blizzard_Collections WardrobeFrame_OnLoad).
local ICON_TEXTURE = "Interface\\Icons\\INV_Arcane_Orb"
-- If the orb is missing on your client, try: Interface\\Icons\\INV_Misc_EngGizmos_19

local function UpdatePosition(button, angle)
    if not button or not Minimap then return end
    local rad = math.rad(angle or 0)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(rad), RADIUS * math.sin(rad))
end

local function GetCursorAngle()
    local cx, cy = Minimap:GetCenter()
    local mx, my = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    mx, my = mx / scale, my / scale
    return math.deg(math.atan2(my - cy, mx - cx))
end

local function GetSavedAngle()
    if EbonTransmogDB and EbonTransmogDB.minimapAngle then
        return EbonTransmogDB.minimapAngle
    end
    return 220
end

local function CreateButton()
    local button = CreateFrame("Button", BUTTON_NAME, Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON_TEXTURE)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")

    return button
end

function MinimapButton.Init()
    if not Minimap or _G[BUTTON_NAME] then return end

    local button = CreateButton()

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Transmog Journal", 1, 0.82, 0)
        GameTooltip:AddLine("Click to open the transmog journal.", 1, 1, 1, true)
        GameTooltip:AddLine("Drag to reposition.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local angle = GetCursorAngle()
            EbonTransmogDB.minimapAngle = angle
            UpdatePosition(self, angle)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        if EbonTransmog.TransmogJournal and EbonTransmog.TransmogJournal.Toggle then
            EbonTransmog.TransmogJournal.Toggle()
        end
    end)

    UpdatePosition(button, GetSavedAngle())
end
