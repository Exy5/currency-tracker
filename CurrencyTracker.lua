-- TODO's
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
    {id = 738, name= "Lesser Charm of Good Fortune", idIncrement = false},
    {id = 3350, name = "August Stone Fragment", idIncrement = false},
    {id = 752, name = "Mogu Rune of Fate", idIncrement = true},
    {id = 3414, name = "August Stone Shard", idIncrement = false}
}

-- global constants
Constants = {
    Events = {
        ADDON_LOADED = "ADDON_LOADED",
        PLAYER_LOGIN = "PLAYER_LOGIN",
        CURRENCY_DISPLAY_UPDATE = "CURRENCY_DISPLAY_UPDATE",
        PLAYER_ENTERING_WORLD = "PLAYER_ENTERING_WORLD",
        CHAT_MSG_CURRENCY = "CHAT_MSG_CURRENCY",
    },
    Commands = {
        HEADER_CT_MAIN = "CURRENCYTRACKER",
        COMMAND_CT_ABBR = "/ct",
        COMMAND_CT_FULLNAME = "/currencytracker",
        COMMAND_CT_SHOW = "show",
        COMMAND_CT_OPTIONS = "options",
        COMMAND_CT_HIDE = "hide",
        HEADER_CT_DEBUG = "CTDEBUG",
        COMMAND_CT_DEBUG = "/ctdebug",
    },
    General = {
        MIN_CHAR_LVL = 85
    },
    Text = {
        HELP_HEADER = "|cffffff00[CT]:|r Currency Tracker Commands:",
        HELP_SHOW = "  |cff00ff00/ct show|r - Toggle currency window",
        HELP_HIDE = "  |cff00ff00/ct hide|r - Close currency window",
        HELP_OPTIONS = "  |cff00ff00/ct options|r - Open options window",
        HELP_DEBUG = "  |cff00ff00/ctdebug|r - Debug currency API",
        HELP_UNKNOWN1 = "|cffffff00[CT]:|r Unknown command: ",
        HELP_UNKNOWN2 = "  Type |cff00ff00/ct|r for available commands",
        FLUSH = "|cffffff00[CT]:|r Database flushed and reset to original state.",
        INITIALIZE = "|cffffff00[CT]:|r Initializing Currency Tracker data.",
        REFRESH = "|cffffff00[CT]:|r Currency data refreshed for "
    }
}

-- Saved variables
CT.db = {}

-- Main frame
local mainFrame = nil
local optionsFrame = nil
local isFrameVisible = false
local isOptionsVisible = false

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
        CT:HandleChatCommand(msg)
    end

    -- Debug command to test currency APIs
    SLASH_CTDEBUG1 = Constants.Commands.COMMAND_CT_DEBUG
    SlashCmdList[Constants.Commands.HEADER_CT_DEBUG] = function(msg)
        CT:DebugCurrencyAPI()
    end

    -- Set up periodic update timer ( every 30 seconds)
    updateTimer = C_Timer.NewTicker(30, function()
        CT:UpdateCurrencyData()
    end)
end

-- Handle chat commands with subcommands
function CT:HandleChatCommand(msg)
    local command = string.lower(string.trim(msg or ""))
    
    if command == "" then
        -- Show help
        print(Constants.Text.HELP_HEADER)
        print(Constants.Text.HELP_SHOW)
        print(Constants.Text.HELP_HIDE)
        print(Constants.Text.HELP_OPTIONS)
        print(Constants.Text.HELP_DEBUG)
    elseif command == Constants.Commands.COMMAND_CT_SHOW then
        CT:ToggleFrame()
    elseif command == Constants.Commands.COMMAND_CT_HIDE then
        CT:HideFrame()
    elseif command == Constants.Commands.COMMAND_CT_OPTIONS then
        CT:ToggleOptionsFrame()
    else
        print(Constants.Text.HELP_UNKNOWN1 .. command)
        print(Constants.Text.HELP_UNKNOWN2)
    end
end

-- Debug purposes to show the info for Elder Charms (id: 697)
function CT:DebugCurrencyAPI()
    local currencyID = 752 -- Elder Charms of Good Fortune
    print("=== Debug for Mogu Rune of Fate - CurrencyID: " .. currencyID)
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
                CurrencyTrackerDB = {
                    enabledCurrencies = {} -- Track which currencies are enabled
                }
                -- Set all currencies enabled by default
                for _, currency in ipairs(CURRENCIES) do
                    CurrencyTrackerDB.enabledCurrencies[currency.id] = true
                end
            end
            CT.db = CurrencyTrackerDB
            
            -- Ensure enabledCurrencies exists for existing databases
            if not CT.db.enabledCurrencies then
                CT.db.enabledCurrencies = {}
                for _, currency in ipairs(CURRENCIES) do
                    CT.db.enabledCurrencies[currency.id] = true
                end
            end
        end
    elseif event == Constants.Events.PLAYER_LOGIN then
        -- Update currency data when player logs in
        print(Constants.Text.INITIALIZE)
        CT:UpdateCurrencyData()
        if not mainFrame then
            CT:CreateMainFrame()
        end
        if not optionsFrame then
            CT:CreateOptionsFrame()
        end
    elseif event == Constants.Events.PLAYER_ENTERING_WORLD then
        -- Update currency data when player enters world (silent)
        CT:UpdateCurrencyData()
        if not mainFrame then
            CT:CreateMainFrame()
        end
        if not optionsFrame then
            CT:CreateOptionsFrame()
        end
    elseif event == Constants.Events.CURRENCY_DISPLAY_UPDATE or event == Constants.Events.CHAT_MSG_CURRENCY then
        -- Update currencies change
        CT:UpdateCurrencyData()
        if mainFrame and mainFrame:IsVisible() then
            CT:UpdateDisplay()
        end
    end
end

-- Check if a currency is enabled in options
function CT:IsCurrencyEnabled(currencyId)
    return CT.db.enabledCurrencies and CT.db.enabledCurrencies[currencyId]
end

-- Set currency enabled/disabled state
function CT:SetCurrencyEnabled(currencyId, enabled)
    if not CT.db.enabledCurrencies then
        CT.db.enabledCurrencies = {}
    end
    CT.db.enabledCurrencies[currencyId] = enabled
    
    -- Update main display if visible
    if mainFrame and mainFrame:IsVisible() then
        CT:UpdateDisplay()
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
    -- Ensure currency and currency.id exist
    if not currency or not currency.id then
        return nil
    end

    local currencyInfo = self:GetCurrencyInfo(currency.id)
    if currencyInfo and currencyInfo.maxQuantity and currencyInfo.maxQuantity > 0 then
        return currencyInfo.maxQuantity
    end
    return nil
end

-- Flush database and reset to original state
function CT:FlushDatabase()
    -- Clear the database but preserve enabled currencies
    local enabledCurrencies = CT.db.enabledCurrencies
    CT.db = { enabledCurrencies = enabledCurrencies }
    CurrencyTrackerDB = CT.db
    print(Constants.Text.FLUSH)
    -- Update display
    if mainFrame and mainFrame:IsVisible() then
        self:UpdateDisplay()
    end
end

-- Get the Character key for current character
function CT:GetCharacterKey()
    local realm = GetRealmName()
    local player = UnitName("player")

    -- Return nil if either realm or player is nil
    if not realm or not player then
        return nil
    end

    return realm .. "-" .. player
end

-- Update currency data for current character
function CT:UpdateCurrencyData()
    local charKey = self:GetCharacterKey()

    -- Exit early if we can't get character key
    if not charKey then
        return
    end

    -- Get character info with nil checks
    local _, playerClass = UnitClass("player")
    local playerLevel = UnitLevel("player")

    -- Exit early if essential character info is missing
    if not playerClass or not playerLevel then
        return
    end

    -- Ensure database exists
    if not self.db then
        return
    end

    for _, currency in ipairs(CURRENCIES) do
        -- Skip if currency is nil or missing ID
        if not currency or not currency.id then
            break
        end

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

-- Create the options frame
function CT:CreateOptionsFrame()
    if optionsFrame then return end

    -- Calculate dynamic height based on number of currencies
    local numCurrencies = #CURRENCIES
    local titleHeight = 40        -- Space for title and instructions
    local checkboxHeight = 30     -- Height per checkbox entry
    local padding = 30            -- Bottom padding
    
    local dynamicHeight = titleHeight + (numCurrencies * checkboxHeight) + padding
    
    optionsFrame = CreateFrame("Frame", "CurrencyTrackerOptionsFrame", UIParent, "BackdropTemplate")
    optionsFrame:SetSize(300, dynamicHeight)
    optionsFrame:SetPoint("CENTER", 0, 0)
    optionsFrame:SetFrameStrata("DIALOG")  -- Higher strata than main frame
    optionsFrame:SetFrameLevel(100)        -- High frame level within the strata
    optionsFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    optionsFrame:SetMovable(true)
    optionsFrame:EnableMouse(true)
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
    optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)
    optionsFrame:Hide()

    -- Title
    local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Currency Tracker Options")

    -- Close button
    local closeButton = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        CT:ToggleOptionsFrame()
    end)

    -- Instructions
    local instructions = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("TOP", title, "BOTTOM", 0, -10)
    instructions:SetText("Select currencies to track:")

    -- Create checkboxes for each currency
    local yOffset = -60
    optionsFrame.checkboxes = {}

    for i, currency in ipairs(CURRENCIES) do
        -- Skip if currency is nil or missing required fields
        if not currency or not currency.id or not currency.name then
            break
        end

        local checkbox = CreateFrame("CheckButton", "CTOptionsCheckbox" .. i, optionsFrame, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", 20, yOffset)
        checkbox:SetSize(20, 20)

        -- Set initial state
        checkbox:SetChecked(CT:IsCurrencyEnabled(currency.id))

        -- Currency icon
        local icon = checkbox:CreateTexture(nil, "OVERLAY")
        local currencyInfo = self:GetCurrencyInfo(currency.id)
        if currencyInfo and currencyInfo.iconFileID then
            icon:SetTexture(currencyInfo.iconFileID)
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
        icon:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)

        -- Currency label
        local label = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        label:SetText(currency.name)

        -- Store currency ID with checkbox for reference
        checkbox.currencyId = currency.id

        -- Set click handler
        checkbox:SetScript("OnClick", function(self)
            CT:SetCurrencyEnabled(self.currencyId, self:GetChecked())
        end)

        -- Store reference for later access
        optionsFrame.checkboxes[currency.id] = checkbox

        yOffset = yOffset - 30
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
    title:SetText("Currency Tracker v1.1.0")

    -- Close button
    local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        CT:HideFrame()
    end)

    -- Options button
    local optionsButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    optionsButton:SetSize(80, 20)
    optionsButton:SetPoint("TOPRIGHT", closeButton, "BOTTOMRIGHT", -15, 0)
    optionsButton:SetText("Options")
    optionsButton:SetScript("OnClick", function()
        CT:ToggleOptionsFrame()
    end)

    -- Refresh button
    local refreshButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    refreshButton:SetSize(80, 20)
    refreshButton:SetPoint("TOPRIGHT", optionsButton, "TOPLEFT", -10, 0)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        CT:UpdateCurrencyData()
        CT:UpdateDisplay()
        local charKey = CT:GetCharacterKey()
        print(Constants.Text.REFRESH .. charKey)
    end)

    -- Content frame
    local contentFrame = CreateFrame("ScrollFrame", nil, mainFrame)
    contentFrame:SetPoint("TOPLEFT", 15, -65)  -- Adjusted for buttons
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

    -- Display only enabled currencies
    for _, currency in ipairs(CURRENCIES) do
        -- Skip if currency is nil or missing required fields
        if not currency or not currency.id or not currency.name then
            break
        end

        -- Skip if currency is not enabled
        if self:IsCurrencyEnabled(currency.id) then
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
            if self.db and self.db[currency.id] then
                for charKey, data in pairs(self.db[currency.id]) do
                    -- Ensure data is not nil and has required fields
                    if data and type(data) == "table" and data.level then
                        local realm, name = charKey:match("(.+)-(.+)")
                        local level = data.level
                        if realm and name and level and level >= Constants.General.MIN_CHAR_LVL then
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
            end

            -- Sort alphabetically by character name
            table.sort(sortedChars, function(a, b)
                if not a or not a.name then return false end
                if not b or not b.name then return true end
                return a.name < b.name
            end)

            if #sortedChars == 0 then
                local noData = mainFrame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noData:SetPoint("TOPLEFT", 15, yOffset)
                noData:SetText("|cff999999No characters with this currency|r")
                yOffset = yOffset - 15
            else
                for _, char in ipairs(sortedChars) do
                    -- Ensure char is not nil and has required fields
                    if char and char.name and char.level and char.class then
                        local classColor = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.class]) or {r = 1, g = 1, b = 1}
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
            end

            yOffset = yOffset - 10 -- Extra space between currency sections
        end
    end

    -- Add timestamp at bottom
    local timestamp = mainFrame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timestamp:SetPoint("TOPLEFT", 5, yOffset - 10)
    timestamp:SetText("|cff888888Last updated: " .. date("%H:%M:%S") .. "|r")
    yOffset = yOffset - 25

    -- Update scroll range
    local contentHeight = math.abs(yOffset)
    mainFrame.scrollChild:SetHeight(math.max(contentHeight, 1))
    if mainFrame.scrollBar and mainFrame.contentFrame then
        local frameHeight = mainFrame.contentFrame:GetHeight()
        if frameHeight then
            mainFrame.scrollBar:SetMinMaxValues(0, math.max(0, contentHeight - frameHeight))
        end
    end
end

-- Toggle main frame visibility
function CT:ToggleFrame()
    if not mainFrame then
        self:CreateMainFrame()
    end

    if mainFrame:IsVisible() then
        self:HideFrame()
    else
        self:ShowFrame()
    end
end

-- Show main frame
function CT:ShowFrame()
    if not mainFrame then
        self:CreateMainFrame()
    end
    
    self:UpdateCurrencyData()
    self:UpdateDisplay()
    mainFrame:Show()
    isFrameVisible = true
end

-- Hide main frame
function CT:HideFrame()
    if mainFrame then
        self:ClearDisplay() -- Clear content when hiding
        mainFrame:Hide()
        isFrameVisible = false
    end
end

-- Toggle options frame visibility
function CT:ToggleOptionsFrame()
    if not optionsFrame then
        self:CreateOptionsFrame()
    end

    if optionsFrame:IsVisible() then
        optionsFrame:Hide()
        isOptionsVisible = false
    else
        -- Update checkbox states when opening
        for _, currency in ipairs(CURRENCIES) do
            local checkbox = optionsFrame.checkboxes[currency.id]
            if checkbox then
                checkbox:SetChecked(CT:IsCurrencyEnabled(currency.id))
            end
        end
        optionsFrame:Show()
        isOptionsVisible = true
    end
end

-- Set up event handling and initialize
eventFrame:SetScript("OnEvent", function(self, event, ...)
    CT:OnEvent(event, ...)
end)

-- Initialize
CT:OnLoad()