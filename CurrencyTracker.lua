-- TODO's
-- * OPTIONS MENU
-- * change calls to /ct show, /ct options, /ct debug
-- * POSSIBLY MORE CURRENCIES TO TRACK

local addonName = "CurrencyTracker"
local CT = {}
_G[addonName] = CT

local CURRENCIES = {
    {id = 395, name = "Justice Points", idIncrement = false},
    {id = 396, name = "Valor Points", idIncrement = true},
    {id = 390, name = "Conquest Points", idIncrement = true},
    {id = 1901, name = "Honor Points", idIncrement = false},
    {id = 697, name= "Elder Charm of Good Fortune", idIncrement = true},
    {id = 738, name= "Lesser Charm of Good Fortune", idIncrement = false}
}

-- global constants
Constants = {
    Events = {
        ADDON_LOADED = "ADDON_LOADED",
        PLAYER_LOGIN = "PLAYER_LOGIN",
        CURRENCY_DISPLAY_UPDATE = "CURRENCY_DISPLAY_UPDATE",
        PLAYER_ENTERING_WORLD = "PLAYER_ENTERING_WORLD",
        CHAT_MSG_CURRENCY = "CHAT_MSG_CURRENCY"
    },
    Commands = {
        HEADER_CT_MAIN = "CURRENCYTRACKER",
        COMMAND_CT_ABBR = "/ct",
        COMMAND_CT_FULLNAME = "/currencytracker",
        HEADER_CT_DEBUG = "CTDEBUG",
        COMMAND_CT_DEBUG = "/ctdebug",
        HEADER_CT_OPTIONS = "CTOPTIONS",
        COMMAND_CT_OPTIONS = "/ctoptions",
    }
}

-- Saved variables
CT.db = {}

-- Main frame
local mainFrame = nil
local isFrameVisible = false

-- Event frame for handling events
local eventFrame = CreateFrame("Frame")
local updateTimer = nil

-- Initialize the addon
function CT:OnLoad()
    eventFrame:RegisterEvent(Constants.Events.ADDON_LOADED)
    eventFrame:RegisterEvent(Constants.Events.PLAYER_LOGIN)
    eventFrame:RegisterEvent(Constants.Events.CURRENCY_DISPLAY_UPDATE)
    eventFrame:RegisterEvent(Constants.Events.PLAYER_ENTERING_WORLD)
    eventFrame:RegisterEvent(Constants.Events.CHAT_MSG_CURRENCY)

    -- Create slash commands
    SLASH_CURRENCYTRACKER1 = Constants.Commands.COMMAND_CT_ABBR
    SLASH_CURRENCYTRACKER2 = Constants.Commands.COMMAND_CT_FULLNAME
    SlashCmdList[Constants.Commands.HEADER_CT_MAIN] = function(msg)
        CT:ToggleFrame()
    end

    -- Debug command to test currency APIs
    SLASH_CTDEBUG1 = Constants.Commands.COMMAND_CT_DEBUG
    SlashCmdList[Constants.Commands.HEADER_CT_DEBUG] = function(msg)
        CT:DebugCurrencyAPI()
    end

    SLASH_CTOPTIONS = Constants.Commands.COMMAND_CT_OPTIONS
    SlashCmdList[Constants.Commands.HEADER_CT_OPTIONS] = function(msg)
        -- currently not implemented - should open options window with clickable entries for currencies
    end

    -- Set up periodic update timer ( every 30 seconds)
    updateTimer = C_Timer.NewTicker(30, function()
        CT:UpdateCurrencyData()
    end)
end

-- Debug purposes to show the info for Valor Points (id: 396)
function CT:DebugCurrencyAPI()
    local currencyID = 697 -- Elder Charms of Good Fortune
    print("=== Debug for Valor Points - CurrencyID: " .. currencyID)
    local info = self:GetCurrencyInfoCompat(currencyID)
    if not info then
        print("GetCurrencyInfo failed")
        return
    end

    for k,v in pairs(info) do
        print("  "..tostring(k).." = "..tostring(v))
    end

    print("=== End Debug ===")
end

-- Event Handler
function CT:OnEvent(event, ...)
    if event == Constants.Events.ADDON_LOADED then
        local loadedAddon = ...
        if loadedAddon == addonName then
            -- Initialize saved variables
            if not CurrencyTrackerDB then
                CurrencyTrackerDB = {}
            end
            CT.db = CurrencyTrackerDB
        end
    elseif event == Constants.Events.PLAYER_LOGIN then
        -- Update currency data when player logs in
        print("|cffffff00[CT]:|r Initializing Currency Tracker data.")
        CT:UpdateCurrencyData()
        if not mainFrame then
            CT:CreateMainFrame()
        end
    elseif event == Constants.Events.PLAYER_ENTERING_WORLD then
        -- Update currency data when player enters world (silent)
        CT:UpdateCurrencyData()
        if not mainFrame then
            CT:CreateMainFrame()
        end
    elseif event == Constants.Events.CURRENCY_DISPLAY_UPDATE or event == Constants.Events.CHAT_MSG_CURRENCY then
        -- Update currencies change
        CT:UpdateCurrencyData()
        if mainFrame and mainFrame:IsVisible() then
            CT:UpdateDisplay()
        end
    end
end

-- Wrapper to get Currency information for currencyId
-- Necessary fields from that table:
-- * quantity: current amount you have
-- * maxQuantity: max amount you can have: correctly ID based, so Valor Points e.g. has 6400 (17.08.2025)
-- * totalEarned: amount you currently have farmed in total
-- * iconFileID: maybe possible to use this iconID instead of icon image
function CT:GetCurrencyInfoCompat(currencyId)
    local info

    -- Try the C_ API first (usually returns a table)
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, v = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyId)
        if ok and v then
            info = v
        end
    end
    
    return info
end

function CT:GetCurrencyInfo(currencyId)
    local info = self:GetCurrencyInfoCompat(currencyId)

    local ok, a, b, c, d, e, f, g, h = pcall(GetCurrencyInfo, currencyId)
    if ok and a then
        if type(a) == "table" then
            -- Newer behavior: already a table
            info = a
        else
            -- Legacy behavior: build a table from multiple returns
            info = {
                name = a,
                quantity = b,
                icon = c,
                earnedThisWeek = d,     -- aka weeklyMax
                maxWeeklyQuantity = e,  -- aka totalMax
                maxQuantity = f,
                discovered = g,
                rarity = h,
            }
        end
    end

    if info then
        -- Normalize a few alias fields so printing is consistent
        info.weeklyMax = info.weeklyMax or info.maxWeeklyQuantity
        info.totalMax = info.totalMax or info.maxQuantity
        info.isDiscovered = (info.isDiscovered ~= nil) and info.isDiscovered or info.discovered
    end

    return info
end

-- Get global currency cap from API (not calculated)
function CT:GetGlobalCurrencyCap(currency)
    local currencyInfo = self:GetCurrencyInfo(currency.id)
    if currencyInfo and currencyInfo.maxQuantity and currencyInfo.maxQuantity > 0 then
        return currencyInfo.maxQuantity
    end
    return nil
end

-- Flush database and reset to original state
function CT:FlushDatabase()
    -- Clear the database
    CT.db = {}
    CurrencyTrackerDB = {}
    
    -- Update display
    if mainFrame and mainFrame:IsVisible() then
        self:UpdateDisplay()
    end
    
    print("|cffffff00[CT]:|r Database flushed and reset to original state.")
end

-- Get the Character key for current character
function CT:GetCharacterKey()
    local realm = GetRealmName()
    local player = UnitName("player")
    return realm .. "-" .. player
end

-- Update currency data for current character
function CT:UpdateCurrencyData()
    local charKey = self:GetCharacterKey()
    
    -- Get character info
    local playerClass = select(2, UnitClass("player"))
    local playerLevel = UnitLevel("player")
    
    for _, currency in ipairs(CURRENCIES) do
        local currencyInfo = self:GetCurrencyInfo(currency.id)
        
        if currencyInfo and currencyInfo.quantity then
            -- Initialize currency structure if it doesn't exist
            if not self.db[currency.id] then
                self.db[currency.id] = {}
            end
            
            -- Store character data under currency ID
            self.db[currency.id][charKey] = {
                amount = currencyInfo.quantity or 0,
                totalEarned = currencyInfo.totalEarned or 0,
                class = playerClass,
                level = playerLevel,
                lastUpdate = time()
            }
        end
    end
    
    -- Force display update if frame is visible
    if mainFrame and mainFrame:IsVisible() then
        self:UpdateDisplay()
    end
end

-- Create the main tracking frame
function CT:CreateMainFrame()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "CurrencyTrackerFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(350, 400)
    mainFrame:SetPoint("CENTER", 0, 0)
    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:Hide()

    -- Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Currency Tracker v1.0.0")

    -- Close button
    local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        CT:ToggleFrame()
    end)

    -- Refresh button
    local refreshButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    refreshButton:SetSize(80, 20)
    refreshButton:SetPoint("TOPRIGHT", closeButton, "BOTTOMRIGHT", -15, 0)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        CT:UpdateCurrencyData()
        CT:UpdateDisplay()
        print("|cffffff00[CT]:|r Currency data refreshed for " .. charKey)
    end)

    -- Content frame
    local contentFrame = CreateFrame("ScrollFrame", nil, mainFrame)
    contentFrame:SetPoint("TOPLEFT", 15, -65)  -- Adjusted for refresh button
    contentFrame:SetPoint("BOTTOMRIGHT", -35, 15)
    
    local scrollChild = CreateFrame("Frame", nil, contentFrame)
    scrollChild:SetSize(300, 1)
    contentFrame:SetScrollChild(scrollChild)
    
    mainFrame.contentFrame = contentFrame
    mainFrame.scrollChild = scrollChild

    -- Flush button
    local flushButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    flushButton:SetSize(80, 20)
    flushButton:SetPoint("TOPRIGHT", refreshButton, "TOPLEFT", -10, 0)
    flushButton:SetText("Flush")
    flushButton:SetScript("OnClick", function()
        CT:FlushDatabase()
        CT:UpdateDisplay()
        print("|cffffff00[CT]:|r Currency data flushed.")
    end)
    
    -- Scrollbar
    local scrollBar = CreateFrame("Slider", nil, contentFrame, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPLEFT", contentFrame, "TOPRIGHT", 0, -16)
    scrollBar:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMRIGHT", 0, 16)
    scrollBar:SetMinMaxValues(0, 100)
    scrollBar:SetValue(0)
    scrollBar:SetValueStep(10)
    scrollBar.scrollStep = 10
    scrollBar:SetScript("OnValueChanged", function(self, value)
        contentFrame:SetVerticalScroll(value)
    end)
    
    mainFrame.scrollBar = scrollBar
    
    self:UpdateDisplay()
end

-- Clear all content from the display
function CT:ClearDisplay()
    if not mainFrame or not mainFrame.scrollChild then return end

    -- Clear all children frames
    local children = {mainFrame.scrollChild:GetChildren()}
    for i = 1, #children do
        children[i]:SetParent(nil)
        children[i]:Hide()
    end

    -- Clear all font strings
    local regions = {mainFrame.scrollChild:GetRegions()}
    for i = 1, #regions do
        if regions[i]:GetObjectType() == "FontString" then
            regions[i]:SetParent(nil)
            regions[i]:Hide()
        end
    end
end

-- Updates the display content
function CT:UpdateDisplay()
    if not mainFrame or not mainFrame.scrollChild then return end

    -- Clear all existing content
    self:ClearDisplay()

    local yOffset = 0

    -- Display currencies
    for _, currency in ipairs(CURRENCIES) do
        -- Get currency info for icon
        local currencyInfo = self:GetCurrencyInfo(currency.id)
        local iconFileID = currencyInfo and currencyInfo.iconFileID
        
        -- Currency header with icon
        local headerFrame = CreateFrame("Frame", nil, mainFrame.scrollChild)
        headerFrame:SetPoint("TOPLEFT", 5, yOffset)
        headerFrame:SetSize(300, 16)
        
        -- Currency icon (try iconFileID first, fallback to hardcoded paths)
        local icon = headerFrame:CreateTexture(nil, "OVERLAY")
        if iconFileID then
            icon:SetTexture(iconFileID)
        else
            -- Fallback icons
            if currency.name == "Justice Points" then
                icon:SetTexture("Interface\\Icons\\spell_holy_championsbond")
            elseif currency.name == "Valor Points" then
                icon:SetTexture("Interface\\Icons\\spell_holy_proclaimchampion_02")
            elseif currency.name == "Conquest Points" then
                icon:SetTexture("Interface\\Icons\\ability_pvp_gladiatormedallion")
            elseif currency.name == "Honor Points" then
                icon:SetTexture("Interface\\Icons\\ability_warrior_victoryrush")
            end
        end
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 0, 0)
        
        -- Currency name
        local header = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        header:SetText("|cffffcc00" .. currency.name .. "|r")
        
        yOffset = yOffset - 20
        
        -- Character data for this currency
        local sortedChars = {}
        if self.db[currency.id] then
            for charKey, data in pairs(self.db[currency.id]) do
                local realm, name = charKey:match("(.+)-(.+)")
                if realm and name then
                    table.insert(sortedChars, {
                        name = name,
                        realm = realm,
                        amount = data.amount or 0,
                        totalEarned = data.totalEarned or 0,
                        class = data.class,
                        level = data.level
                    })
                end
            end
        end
        
        -- Sort alphabetically by character name
        table.sort(sortedChars, function(a, b) return a.name < b.name end)
        
        if #sortedChars == 0 then
            local noData = mainFrame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noData:SetPoint("TOPLEFT", 15, yOffset)
            noData:SetText("|cff999999No characters with this currency|r")
            yOffset = yOffset - 15
        else
            for _, char in ipairs(sortedChars) do
                local classColor = RAID_CLASS_COLORS[char.class] or {r = 1, g = 1, b = 1}
                local colorHex = string.format("%02x%02x%02x", 
                    classColor.r * 255, classColor.g * 255, classColor.b * 255)
                
                -- Calculate global cap for this currency
                local globalCap = self:GetGlobalCurrencyCap(currency)
                
                local charInfo = mainFrame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                charInfo:SetPoint("TOPLEFT", 15, yOffset)
                
                local displayText
                if currency.idIncrement then
                    -- For Valor/Conquest Points, show: Character (Level) quantity (totalEarned/maxQuantity)
                    if globalCap and globalCap > 0 then
                        displayText = string.format("|cff%s%s|r (%d): |cffffffff%s|r (|cffffff00%s|r/|cff00ff00%s|r)", 
                            colorHex, char.name, char.level, char.amount, char.totalEarned, globalCap)
                    else
                        displayText = string.format("|cff%s%s|r (%d): |cffffffff%s|r (|cffffff00%s|r)", 
                            colorHex, char.name, char.level, char.amount, char.totalEarned)
                    end
                else
                    -- For Justice/Honor Points, show only: Character (Level) quantity
                    displayText = string.format("|cff%s%s|r (%d): |cffffffff%s|r", 
                        colorHex, char.name, char.level, char.amount)
                end
                charInfo:SetText(displayText)
                yOffset = yOffset - 15
            end
        end
        
        yOffset = yOffset - 10 -- Extra space between currency sections
    end

    -- Add timestamp at bottom
    local timestamp = mainFrame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timestamp:SetPoint("TOPLEFT", 5, yOffset - 10)
    timestamp:SetText("|cff888888Last updated: " .. date("%H:%M:%S") .. "|r")
    yOffset = yOffset - 25

    -- Update scroll range
    local contentHeight = math.abs(yOffset)
    mainFrame.scrollChild:SetHeight(math.max(contentHeight, 1))
    if mainFrame.scrollBar then
        mainFrame.scrollBar:SetMinMaxValues(0, math.max(0, contentHeight - mainFrame.contentFrame:GetHeight()))
    end
end

-- Toggle frame visibility
function CT:ToggleFrame()
    if not mainFrame then
        self:CreateMainFrame()
    end

    if mainFrame:IsVisible() then
        self:ClearDisplay() -- Clear content when hiding
        mainFrame:Hide()
        isFrameVisible = false
    else
        self:UpdateCurrencyData()
        self:UpdateDisplay()
        mainFrame:Show()
        isFrameVisible = true
    end
end

-- Set up event handling and initialize
eventFrame:SetScript("OnEvent", function(self, event, ...)
    CT:OnEvent(event, ...)
end)

-- Initialize
CT:OnLoad()