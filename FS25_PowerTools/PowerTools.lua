--[[
Power Tools for FS25

Author:     w33zl / WZL Modding (github.com/w33zl)
Version:    2.3
Modified:   2024-11-30

Changelog:
    2.2.1       Fix issues related to pallet spawning and flight mode
    2.2.0       New multistate buttons, refactored menu
    2.1.0       Re-added super strength and flight mode, and added super speed
    2.0.0       FS25 version
]]


local ENABLE_EXPERIMENTAL_FLIGHTMODE = true
local ENABLE_EXPERIMENTAL_HUDHIDE = true

local FEATURE_TOGGLE = {
    EXPERIMENTAL_FLIGHTMODE = true,
    EXPERIMENTAL_HUDHIDE = true,
    EXTENDED_TIMESCALE = true,
    SUPERSTRENGTH_HACK = true,
}

PowerTools = Mod:init()

-- PowerTools:enableDebugMode()

PowerTools:source("scripts/modLib/DialogHelper.lua")

if ENABLE_EXPERIMENTAL_HUDHIDE then
    PowerTools:source("scripts/modLib/GlobalHelper.lua")
    PowerTools:source("scripts/modLib/MultistateKeyHandler.lua")
end

local ACTION = {
    SPAWN_PALLET = 1,
    SPAWN_BALE = 2,
    SPAWN_LOG = 3,
    HIDE_HUD = 4,
    SUPERMAN_MODE = 5,
    TIP_TO_GROUND = 6,
    FLIGHT_MODE = 7,
    CHANGE_MONEY = 8,
    FILL_UNIT_ADD = 9,
    SUPER_SPEED = 10,
}

local RESTART_MODE = {
    UNKNOWN = 0,
    EXIT = 1,
    EXIT_FORCED = 2,
    RESTART = 3,
    RESTART_FORCED = 4,
    QUIT_TO_DESKTOP = 5,
}

local NOT_IMPLEMENTED = true

PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, function()
    local triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings = false, true, false, true, nil, true
    local success, actionEventId, otherEvents = g_inputBinding:registerActionEvent(InputAction.POWERTOOLSMENU, PowerTools, PowerTools.showMenu, triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings)

    if success then
        PowerTools.actionEventId = actionEventId
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_NORMAL)
    else
        --TODO: do we need to know this? or should we just silently ignore?
        -- Log:debug("Failed to register main key for PowerTools")
        -- Log:var("state", success)
        -- Log:var("actionId", actionEventId)
    end    

    local state, actionEventId, otherEvents = g_inputBinding:registerActionEvent(InputAction.POWERTOOLSMENU_ALTERNATIVE, PowerTools, PowerTools.showMenu, triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings)
    g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
    g_inputBinding:setActionEventTextVisibility(actionEventId, false) -- INFO: change "false" to "true" to show keybinding in help window

    local state, actionEventId, otherEvents = g_inputBinding:registerActionEvent(InputAction.POWERTOOLS_QUICKSAVE, PowerTools, PowerTools.saveGame, triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings)
    g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
    g_inputBinding:setActionEventTextVisibility(actionEventId, false) -- INFO: change "false" to "true" to show keybinding in help window
    local state, actionEventId, otherEvents = g_inputBinding:registerActionEvent(InputAction.POWERTOOLS_REPEAT_ACTION, PowerTools, PowerTools.repeatLastAction, triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings)
    g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
    g_inputBinding:setActionEventTextVisibility(actionEventId, false) -- INFO: change "false" to "true" to show keybinding in help window


end)

FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, function()
    if PowerTools ~= nil then
        if PowerTools.delete ~= nil then
            PowerTools:delete()
        end
        removeModEventListener(PowerTools)
        PowerTools = nil -- GC
    end
end)

local function commandBuilder(consoleCommand, ...)
    local arguments = { ... }
    return consoleCommand .. " " .. table.concat(arguments, " ")
end

local function getOrInitGlobalMod(name)
    g_globalMods[name] = g_globalMods[name] or {}
    return g_globalMods[name]
end

_G.g_powerTools = getOrInitGlobalMod("FS25_PowerTools")

function PowerTools:showSecondaryMenu(a)
    print("Second menu")
    self:showMenu(true)
end

local SUFFIX_ADVANCED = " [" .. g_i18n:getText("advancedMode") .. "]"

--TODO: FIX DIALOG
function PowerTools:showMenu(actionName)
    self.lastAction = nil

    local VISIBLE, HIDDEN = false, true
    
    

    local useAltMode = actionName == InputAction.POWERTOOLSMENU_ALTERNATIVE
    local isPaused = g_currentMission.paused
    local isInMainMenu = g_gui.currentGui ~= nil
    local isInVehicle = g_localPlayer:getCurrentVehicle() ~= nil
    local isInField = g_fieldManager:getFieldIdAtPlayerPosition() ~= nil



    -- Log:var("useAltMode", useAltMode)
    -- Log:var("isPaused", isPaused)

    local actionFillVehicle = { g_i18n:getText("fillVehicle"), self.fillVehicle, (not isInVehicle) }
    local actionTipOnGround = { g_i18n:getText("tipOnGround"), self.tipToGround, (isInVehicle) }
    local actionShowFieldMenu = { g_i18n:getText("showFieldMenu"), self.showFieldMenu, (isInVehicle or not isInField) }
    local actionSpawnPallets = { g_i18n:getText("infohud_pallet"), self.spawnPallets, (isInVehicle) } --TODO: fix l10n
    local actionSpawnPalletsAdvanced = { g_i18n:getText("infohud_pallet") .. SUFFIX_ADVANCED, self.spawnPallets, (isInVehicle) } --TODO: fix l10n
    local actionSpawnBale = { g_i18n:getText("infohud_bale"), self.spawnBales, (isInVehicle) } --TODO: fix l10n
    local actionSpawnTreeTrunk = { g_i18n:getText("fillType_wood"), self.spawnLogs, (isInVehicle) } --TODO: fix l10n

    local actionSoftRestart = { g_i18n:getText("restartMode"), self.menuActionRestartGame }
    local actionSoftExit = { g_i18n:getText("exitMode"), self.menuActionExitSavegame }
    local actionForceRestart = { g_i18n:getText("forcedRestartMode"), self.menuActionForceRestartGame }
    local actionForceExit = { g_i18n:getText("forcedExitMode"), self.menuActionForceExitSavegame }
    local actionRestart = actionSoftRestart
    local actionExit = actionSoftExit

    local actionUIScaleMenu = { g_i18n:getText("showUIScaleMenu"), self.showUIScaleMenu, (not useAltMode) }

    local actionSaveGame = { g_i18n:getText("saveGame"), self.saveGame }
    local actionSpawnObjects = { g_i18n:getText("spawnObjectsActionTitle"), self.spawnObjects, (isInVehicle) }
    local actionClearTipArea = { g_i18n:getText("actionClearTipArea"), self.clearTipArea, HIDDEN }
    local actionAddRemoveMoney = { g_i18n:getText("changeMoneyMode"), self.addRemoveMoney }
    local actionToggleHUDMode = { g_i18n:getText("noHudMode"), self.toggleHUDMode, VISIBLE }
    local actionToggleSuperStrength = { g_i18n:getText("superStrengthMode"), self.toggleSuperStrength, VISIBLE }
    local actionToggleSuperSpeed = { g_i18n:getText("superSpeedMode"), self.toggleSuperSpeed, VISIBLE }
    local actionToggleFlightMode = { g_i18n:getText("flightMode"), self.toggleFlightMode, VISIBLE }

    if useAltMode then
        actionRestart = actionForceRestart
        actionExit = actionForceExit
    end 


    Log:table("actionShowFieldMenu", actionShowFieldMenu)

    -- -- Conditionally disable options
    -- if isInVehicle == true then
    --     actionSpawnBale = nil
    -- else
    --     actionFillVehicle = nil
    -- end

    local actions = {
        actionFillVehicle,
        actionSpawnObjects,
        actionShowFieldMenu,
        actionToggleSuperStrength,
        actionToggleFlightMode,
        actionToggleSuperSpeed,
        actionToggleHUDMode,
        actionUIScaleMenu,
        actionAddRemoveMoney,
        actionSaveGame,
        actionExit,
        actionRestart,
    }

    local menuLayout1 = {
        actionFillVehicle,
        actionSpawnObjects,
        -- actionSpawnPallets,
        -- actionSpawnBale,
        -- actionSpawnTreeTrunk,
        actionToggleSuperStrength,
        actionToggleFlightMode,
        actionToggleSuperSpeed,
        actionToggleHUDMode,
        actionAddRemoveMoney,
        actionSaveGame,
        actionExit,
        actionRestart,
    }

    -- Remove disabled actions
    for i = #actions, 1, -1 do
        if actions[i] == nil or actions[i][3] then
            table.remove(actions, i)
        end
    end

    -- --TODO: replace when TipOnGround works
    -- if self:getIsServer() then --NOTE: only allowed on the server host for now, maybe change in the future
    --     if isInVehicle == true then
    --         table.insert( actions, 1, actionFillVehicle )
    --     else
    --         table.insert( actions, 1, actionSpawnBale )
    --     end
    -- end

    if isPaused or isInMainMenu then
        actions = {
            actionSoftRestart,
            actionSoftExit,
            actionUIScaleMenu,
            actionSaveGame,
            actionForceExit,
            actionForceRestart,
        }
    end  

    local options = {}
    for index, value in ipairs(actions) do
        options[#options + 1] = index .. ") " .. value[1]
    end
    -- local options = {}
    -- local menuIndex = 0
    -- for index, value in ipairs(actions) do
    --     if not value[3] then -- Is hidden?
    --         menuIndex = menuIndex + 1
    --         options[#options + 1] = menuIndex .. ") " .. value[1]
    --     end 
    -- end

    local dialogArguments = {
        text = g_i18n:getText("chooseAction"),
        title = g_i18n:getText("powerTools"),
        options = options,
        target = self,
        args = { },
        callback = function(target, selectedOption, a)
            if type(selectedOption) ~= "number" or selectedOption == 0 then
                return
            end

            local delegate = actions[selectedOption][2]

            delegate(self, useAltMode)
        end,
    }

    --TODO: hack to reset the "remembered" option (i.e. solve a bug in the game engine)
    local dialog = g_gui.guis["OptionDialog"]
    if dialog ~= nil then
        dialog.target:setOptions({""}) -- Add fake option to force a "reset"
    end

    --TODO: FIX DIALOG
    DialogHelper.showOptionDialog(dialogArguments)
    

end

function PowerTools:showSubMenu(text, title, defaultOption, actions)
    local options = {}
    for index, value in ipairs(actions) do
        options[#options + 1] = index .. ") " .. value[1]
    end

    --TODO: FIX DIALOG
    self:showOptionDialog(
        text, 
        title, 
        options,
        function(target, selectedOption, a)
            if type(selectedOption) ~= "number" or selectedOption == 0 then
                return
            end

            local delegate = actions[selectedOption][2]
            local args = actions[selectedOption][3] or {}

            delegate(self, unpack(args))
        end,
        true
    )
end

--TODO: the saveTable, repeat action and execute should be refactored, too messy a t m
function PowerTools:repeatLastAction()
    Log:var("Repeat action", self.lastAction)
    if self.lastAction == nil then return end

    Log:var("Repeat action type", self.lastAction.actionType)

    local lastAction = self.lastAction
    local targetObject = lastAction.targetObject
    local targetCommand = lastAction.targetCommand
    local payload = lastAction.payload

    if type(targetCommand) == "string" then
        targetCommand = targetObject[targetCommand]
    end

    if targetObject ~= nil and targetCommand ~= nil and type(targetCommand) == "function" then
        Log:var("Executing repeating action on object", targetObject)

        if payload ~= nil and #payload > 0 and payload[1] == targetObject then
            targetCommand(unpack(payload)) -- No need to add targetObject
        else
            targetCommand(targetObject, unpack(payload))
        end
    end

end


function PowerTools:showUIScaleMenu()
    local currentScaleIndex = g_settingsModel:getValue(SettingsModel.SETTING.UI_SCALE)
    Log:var("currentScaleIndex", currentScaleIndex)

    local currentSetting = g_gameSettings:getValue(SettingsModel.SETTING.UI_SCALE) -- Persistent
    local currentSettingIndex = Utils.getUIScaleIndex(currentSetting)
    local currentSettingScale = Utils.getUIScaleFromIndex(currentSettingIndex)
    local actualUIScale = g_currentMission.hud.infoDisplay.uiScale or currentSettingScale
    local actualUIScaleIndex = Utils.getUIScaleIndex(actualUIScale)

    Log:var("currentSetting", currentSetting)
    Log:var("currentSettingIndex", currentSettingIndex)
    Log:var("currentSettingScale", currentSettingScale)
    Log:var("actualUIScale", actualUIScale)
    Log:var("actualUIScaleIndex", actualUIScaleIndex)

    -- for index, value in pairs(g_settingsModel.uiScaleValues) do
    --     Log:debug("Index: %d, Value: %d", index, value)
    -- end

    self:showOptionDialog(
        g_i18n:getText("uiScaleMenuInfo"), 
        g_i18n:getText("uiScaleMenuTitle"), 
        g_settingsModel.uiScaleTexts,
        function(target, selectedOption, a)
            if type(selectedOption) ~= "number" or selectedOption == 0 then
                return
            end

            -- local selectedValue = g_settingsModel.uiScaleTexts[selectedOption]
            -- Log:var("selectedValue", selectedValue)
            -- local cleanSelectedValue = string.gsub(selectedValue, "%%", "")
            -- local numericValue = tonumber(cleanSelectedValue)
            local numericValue = Utils.getUIScaleFromIndex(selectedOption)

            -- Log:var("cleanSelectedValue", cleanSelectedValue)
            Log:var("numericValue", numericValue)

            if numericValue ~= nil and type(numericValue) == "number" then
                
                Log:debug("Setting scale to %f", numericValue)
                g_currentMission.hud:setScale(numericValue)
                -- currentScaleIndex = g_settingsModel:getValue(SettingsModel.SETTING.UI_SCALE)
                Log:var("uiScale AFTER", g_currentMission.hud.infoDisplay.uiScale)
                Log:info("HUD scalet changed to %d%%", g_currentMission.hud.infoDisplay.uiScale * 100)
            else
                Log:warning("Could not set scale to %d [#]", numericValue, selectedOption)
            end
            
            -- self:showUIScaleMenu()
        end,
        true,
        actualUIScaleIndex
    )

    -- self:showSubMenu(
    --     g_i18n:getText("showFieldMenu"), --TODO: add text to display field and land number
    --     g_i18n:getText("fieldMenuTitle"), 
    --     1, 
    --     {
    --         { g_i18n:getText("actionSetFieldCrop"), function() FieldStateDialog.show(tostring(fieldId), "", "") end }, --TODO: show field menuVisible
    --         { g_i18n:getText("actionSetFieldGround"), function() FieldStateDialog.show(tostring(fieldId)) end }, --TODO: show field menuVisible
    --     }
        
    -- )
end

function PowerTools:showFieldMenu()
    local fieldId = g_fieldManager:getFieldIdAtPlayerPosition()
    local hasPlayerAccess = false

    if fieldId ~= nil then
        local playerX, _, playerZ = g_localPlayer:getPosition()
        -- local isFarmlandOwner = g_farmlandManager:getFarmlandOwner() -- can maybe be used to determine if the admin should have had access or not
        hasPlayerAccess = g_farmlandManager:getCanAccessLandAtWorldPosition(g_localPlayer.farmId, playerX, playerZ) --TODO: needs to be verified in MP as guest
    end

    Log:var("hasPlayerAccess", hasPlayerAccess)

    if not self:showWarningIfNoAccess(hasPlayerAccess) then
        return
    end

    --TODO: replace next line with uncommented block when we need a submenu
    FieldStateDialog.show(tostring(fieldId))
    -- self:showSubMenu(
    --     g_i18n:getText("showFieldMenu"), --TODO: add text to display field and land number
    --     g_i18n:getText("fieldMenuTitle"), 
    --     1, 
    --     {
    --         { g_i18n:getText("actionSetFieldCrop"), function() FieldStateDialog.show(tostring(fieldId), "", "") end }, --TODO: show field menuVisible
    --         { g_i18n:getText("actionSetFieldGround"), function() FieldStateDialog.show(tostring(fieldId)) end }, --TODO: show field menuVisible
    --     }
        
    -- )
    --TODO: add actions:
    -- FarmlandManager:consoleCommandBuyFarmland(id) / sell if you already own...
    -- FarmlandManager:consoleCommandBuyAllFarmlands() / sell all
end

function PowerTools:tipToGround()
    ---consoleCommandTipAnywhere...
end

function PowerTools:notImplemented()
    g_currentMission:showBlinkingWarning("Not implemented yet", 2000)
end



function PowerTools:toggleSuperSpeed()
    -- if NOT_IMPLEMENTED then return self:notImplemented() end --TODO: remove when working

    g_localPlayer.toggleSuperSpeedCommand = g_localPlayer.toggleSuperSpeedCommand or {}
    local toggleSuperSpeedCommand = g_localPlayer.toggleSuperSpeedCommand
    toggleSuperSpeedCommand.value = not (toggleSuperSpeedCommand.value or false)
    

    if toggleSuperSpeedCommand.value then
        g_currentMission:addGameNotification(g_i18n:getText("superSpeed"), g_i18n:getText("enabled"), "", nil, 1500)
    else
        g_currentMission:addGameNotification(g_i18n:getText("superSpeed"), g_i18n:getText("disabled"), "", nil, 1000)
    end

    self:saveAction(ACTION.SUPER_SPEED, self,PowerTools.toggleSuperSpeed, {} )
end

function PowerTools:toggleSuperStrength()
    -- if NOT_IMPLEMENTED then return self:notImplemented() end --TODO: remove when working

    local ssEnabled = g_localPlayer.hands:consoleCommandToggleSuperStrength()
    local ssIsEnabled = g_localPlayer.hands.spec_hands.hasSuperStrength
    Log:var("currentMaximumMass", g_localPlayer.hands.spec_hands.currentMaximumMass)
    Log:var("pickupDistance", g_localPlayer.hands.spec_hands.pickupDistance)
    
    -- if ssEnabled == "Enabled super strength" then
    --     ssIsEnabled = true
    -- elseif ssEnabled == "Disabled super strength" then
    --     ssIsEnabled = false
    -- end

    if ssIsEnabled == true then
        g_currentMission:addGameNotification(g_i18n:getText("superStrength"), g_i18n:getText("enabled"), "", nil, 1500)
    elseif ssIsEnabled == false then
        g_currentMission:addGameNotification(g_i18n:getText("superStrength"), g_i18n:getText("disabled"), "", nil, 1000)
    end

    self:saveAction(ACTION.SUPERMAN_MODE, self,PowerTools.toggleSuperStrength, {} )

end

function PowerTools:toggleHUDMode()
    g_currentMission.hud:consoleCommandToggleVisibility()
    -- g_currentMission.hud.isVisible = not (g_currentMission.hud.isVisible or false)  -- thirdPersonViewActive

    self:saveAction(ACTION.HIDE_HUD, self,PowerTools.toggleHUDMode, {} )
end

function PowerTools:toggleFlightActive()
    Log:var("g_localPlayer.mover.isFlightActive [BEFORE]", g_localPlayer.mover.isFlightActive)
    -- g_localPlayer.mover.isFlightActive = not g_localPlayer.mover.isFlightActive
    -- Log:var("g_localPlayer.mover.isFlightActive [BETWEEN]", g_localPlayer.mover.isFlightActive)
    -- g_localPlayer.mover:toggleFlightActive()
    PlayerInputComponent.onInputToggleFlightMode(g_localPlayer.inputComponent)
    Log:var("g_localPlayer.mover.isFlightActive [AFTER]", g_localPlayer.mover.isFlightActive)
end



function PowerTools:toggleFlightModeExperimental()

    g_localPlayer.toggleFlightModeCommand.value = not g_localPlayer.toggleFlightModeCommand.value
    if g_localPlayer.toggleFlightModeCommand.value then
        g_localPlayer.toggleFlightModeCommand.onEnabled()

        xpcall(function()
            self:toggleFlightActive()
        end, function(err) Log:warning("Failed to automatically activate flight mode. You need to manually enable it with J key. Reason was: "..tostring(err)) end)

        if g_localPlayer.mover.isFlightActive then
            --TODO: do we need to do anything?
        else
            g_currentMission:addGameNotification(g_i18n:getText("flightMode"), g_i18n:getText("enabled"), g_i18n:getText("flightModeUsage"), nil, 2500)
        end
    else
        g_localPlayer.toggleFlightModeCommand.onDisabled()
        g_currentMission:addGameNotification(g_i18n:getText("flightMode"), g_i18n:getText("disabled"), "", nil, 1500)
    end

    
    self:saveAction(ACTION.FLIGHT_MODE, self,PowerTools.toggleFlightModeExperimental, {} )    
end

function PowerTools:toggleFlightMode()
    if ENABLE_EXPERIMENTAL_FLIGHTMODE then
        Log:debug("Using experimental flight mode")
        self:toggleFlightModeExperimental()
        return
    end
    Log:debug("Using default flight mode")

    executeConsoleCommand(commandBuilder("gsPlayerFlightToggle"))

    if g_localPlayer.toggleFlightModeCommand.value then
        g_currentMission:addGameNotification(g_i18n:getText("flightMode"), g_i18n:getText("enabled"), g_i18n:getText("flightModeUsage"), nil, 2500)
    else
        g_currentMission:addGameNotification(g_i18n:getText("flightMode"), g_i18n:getText("disabled"), "", nil, 1500)
    end

    self:saveAction(ACTION.FLIGHT_MODE, self,PowerTools.toggleFlightMode, {} )
end

function PowerTools:addRemoveMoney()
    if not self:validateIsFarmFinanceManager() then return end

    local dialogArguments = {
        text = g_i18n:getText("changeMoneyMode"):upper() .. ":\n\n" .. g_i18n:getText("changeMoneyUsage"):gsub("\\\\n", "\n"),
        target = self, 
        defaultText = "", 
        maxCharacters = 10,
        args = {},
        disableFilter = false,
        okButtonText = g_i18n:getText("changeMoneyMode"),
        cancelButtonText = g_i18n:getText("buttonCancel"),
    }

    dialogArguments.callback = function(target, value, arguments)
        if value == nil or value == "" then return end

        local function addMoney(amount, isAbsolute)
            local moneyChange = amount

            if isAbsolute then
                local farm = g_farmManager:getFarmById(self:getCurrentPlayer().farmId)
                local refMoney = farm.money
                moneyChange = amount - refMoney
            end

            self:executeAction(ACTION.CHANGE_MONEY, g_currentMission, "consoleCommandCheatMoney", { g_currentMission, moneyChange }, true)
            -- g_currentMission:consoleCommandCheatMoney(moneyChange);

        end

        local numericValue, isExact = nil, false

        if value:find("=") == 1 then
            value = value:sub(2, -1)
            isExact = true
        end

        numericValue = tonumber(value)

        if numericValue ~= nil and type(numericValue) == "number" then
            addMoney(numericValue, isExact)
        else
            g_currentMission:showBlinkingWarning(g_i18n:getText("errorNotNumeric") .. tostring(value))
        end
    end

    DialogHelper.showTextInputDialog(dialogArguments)
end


-- function PowerTools:consoleCommandDumpTableToFile(tableName, filename)
--     local function printUsage()
--         PowerTools:printInfo("USAGE: ptSaveTable tableName filename [depth]")
--     end
--     if tableName == nil or type(tableName) ~= "string" then
--         PowerTools:printError("Parameter tableName can not be empty!\n")
--         printUsage()
--         return
--     end
-- local debugTable = loadstring("return " .. tableName)

--     local tableFile = getUserProfileAppPath() .. filename
-- 	local file = io.open(tableFile, "w")
--if file ~= nil then
--file:write(header .. "\n")
--file:close()
-- end

function PowerTools:consoleCommandPrintTable(tableName, depth)
    local function printUsage()
        Log:info("USAGE: ptTable tableName [depth]")
    end
    if tableName == nil or type(tableName) ~= "string" then
        PowerTools:printError("Parameter tableName can not be empty!\n")
        printUsage()
        return
    end

    depth = tonumber(depth) or 3

    if depth == nil or depth < 1 then
        PowerTools:printError("Optional parameter 'depth' must be a positive number!\n")
        printUsage()
        return
    end

    local debugTable = loadstring("return " .. tableName)

    if type(debugTable) == "function" then
        debugTable = debugTable()
    end

    if debugTable ~= nil and type(debugTable)== "table" then
        DebugUtil.printTableRecursively(debugTable, "debugTable:: ", 0, depth)
    else
        self:printError("Table '%s' could not be found", tableName)
    end
end



--TODO: FIX DIALOG
function PowerTools:showOptionDialog(text, title, options, callback, noReset, previousOption)
    --TODO: hack to reset the "remembered" option (i.e. solve a bug in the game engine)
    local dialog = g_gui.guis["OptionDialog"]
    if dialog ~= nil and not noReset then
        dialog.target:setOptions({""}) -- Add fake option to force a "reset"
    end

    --TODO: FIX DIALOG
    
    DialogHelper.showOptionDialog({
        text = text,
        title = title,
        defaultText = "",
        options = options,
        defaultOption = previousOption or 1,
        target = self,
        args = { },
        callback = callback,
    })
end

function PowerTools:fillFillUnit(selectedFillUnit)
    if selectedFillUnit == nil then
        g_currentMission:showBlinkingWarning("No/invalid fillunit index")
        return
    end

    local options = {}
    local optionToFilltypeIndex = {}
    options[#options + 1] = g_i18n:getText("filltypeNone") --:upper()
    optionToFilltypeIndex[#optionToFilltypeIndex + 1] = 0


    for fillTypeIndex, _ in pairs(selectedFillUnit.supportedFillTypes) do
        local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)
        local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)

        if fillType ~= nil and fillType.title ~= nil then
            fillTypeName = fillType.title
        end

        -- Log:table("FillType", g_fillTypeManager:getFillTypeByIndex(fillTypeIndex))

        if self.debugMode then fillTypeName = fillTypeName .. " [" .. tostring(fillTypeIndex) .. "]" end

        options[#options + 1] = fillTypeName
        optionToFilltypeIndex[#optionToFilltypeIndex + 1] = fillTypeIndex
    end

    if #options < 1 then
        g_currentMission:showBlinkingWarning(g_i18n:getText("errorNoValidFilltypes"))
        return
    end


    local dialogArguments = {
        text = g_i18n:getText("selectFillType"),
        title = g_i18n:getText("fillVehicle"),
        options = options,
        target = self,
        -- yesButtonText = g_i18n:getText("fill"),
        args = { },
        callback = function(target, selectedOption, a)

            if selectedOption > 0 then

                local selectedFillUnitIndex = selectedFillUnit.fillUnitIndex
                local selectedFillTypeIndex = optionToFilltypeIndex[selectedOption]
                local amount = selectedFillUnit.capacity or 1000
                
                local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(selectedFillTypeIndex)

                local function setFillUnitFillLevel(fillUnitIndex, fillType, amount)
                    g_currentMission.vehicleSystem:consoleCommandFillUnitAdd(fillUnitIndex, fillType, amount)
                end

                local controlledVehicle = g_localPlayer:getCurrentVehicle()
                local selectedVehicle = controlledVehicle ~= nil and controlledVehicle:getSelectedVehicle()
                local currentVehicle = selectedVehicle or controlledVehicle
                local spec_fillUnit = currentVehicle ~= nil and currentVehicle.spec_fillUnit

                if spec_fillUnit == nil then
                    return
                end

                local currentFillType = currentVehicle:getFillUnitFillType(selectedFillUnitIndex)
                local currentFillLevel = currentVehicle:getFillUnitFillLevel(selectedFillUnitIndex)
                local maxCapacity = currentVehicle:getFillUnitCapacity(selectedFillUnitIndex)

                -- Log:var("FillTypeName", fillTypeName)
                -- Log:var("selectedFillUnitIndex", selectedFillUnitIndex)
                -- Log:var("selectedFillTypeIndex", selectedFillTypeIndex)
                -- Log:var("selectedOption", selectedOption)
                -- Log:var("amount", amount)
                -- Log:var("currentFillType", currentFillType)
                -- Log:var("currentFillLevel", currentFillLevel)
                -- Log:var("maxCapacity", maxCapacity)
                -- Log:debug("clean")

                -- Need to clean first... othwerwise we cannot fill with a new type
                setFillUnitFillLevel(selectedFillUnitIndex, g_fillTypeManager:getFillTypeNameByIndex(currentFillType), -currentFillLevel)
                
                if selectedFillTypeIndex > 0 then
                    -- Log:debug("add")
                    setFillUnitFillLevel(selectedFillUnitIndex, fillTypeName, amount)
                end

            end
        end,
    }

    DialogHelper.showOptionDialog(dialogArguments)
end



function PowerTools:fillVehicle()

    local controlledVehicle = g_localPlayer:getCurrentVehicle()
    local selectedVehicle = controlledVehicle ~= nil and controlledVehicle:getSelectedVehicle()
    local currentVehicle = selectedVehicle or controlledVehicle
    local spec_fillUnit = currentVehicle ~= nil and currentVehicle.spec_fillUnit

    -- Pre scan
    local validFillUnits = {}
    local function checkFillUnitsForVehicle(vehicle)
        local spec_fillUnit = vehicle ~= nil and vehicle.spec_fillUnit
        local perVehicleIndex = 0

        if spec_fillUnit == nil then
            return
        end

        local function addFillUnitOption(index, fillUnit)
            perVehicleIndex = perVehicleIndex + 1
            local fillUnitOption = {
                index = index,
                fillType = fillUnit.fillType,
                fillLevel = fillUnit.fillLevel,
                capacity = fillUnit.capacity,
                unitText = fillUnit.unitText,
                vehiclePrefix = vehicle.typeDesc:upper() .. "[" .. tostring(perVehicleIndex) .. "]"
            }
            
            validFillUnits[#validFillUnits + 1] = fillUnitOption

        end
        
        
        for index, fillUnit in ipairs(spec_fillUnit.fillUnits) do
            if fillUnit.supportedFillTypes ~= nil and fillUnit.showOnInfoHud then
                if #fillUnit.supportedFillTypes > 0 then
                    addFillUnitOption(index, fillUnit)
                else-- Second chance
                    for k, v in pairs(fillUnit.supportedFillTypes) do
                        if type(k) == "number" and type(v) == "boolean" and v == true then
                            addFillUnitOption(index, fillUnit)
                            break
                        end
                    end
                end
            end
            
        end
    end
    
    checkFillUnitsForVehicle(currentVehicle)
    -- if currentVehicle ~= controlledVehicle then
    --     checkFillUnitsForVehicle(controlledVehicle)
    -- end


    local selectedFillUnitIndex
    if #validFillUnits == 0 then
        g_currentMission:showBlinkingWarning(g_i18n:getText("errorNoValidFillUnits"))
        return
    elseif #validFillUnits == 1 then
        selectedFillUnitIndex = 1
        self:fillFillUnit(spec_fillUnit.fillUnits[1])
    else
        local options = {}
        for index, value in ipairs(validFillUnits) do
            local name = value.fillType == 0 and "-" or g_fillTypeManager:getFillTypeNameByIndex(value.fillType)
            options[#options + 1] = string.format( "%s: %s (%d/%d)", value.vehiclePrefix, name, value.fillLevel, value.capacity)
        end

        --TODO: FIX DIALOG
        self:showOptionDialog(
            g_i18n:getText("chooseFillUnitDetailed"),
            g_i18n:getText("chooseFillUnit"),
            options,
            function(target, selectedOption)
                if selectedOption > 0 then
                    self:fillFillUnit(spec_fillUnit.fillUnits[validFillUnits[selectedOption].index])
                end
            end
        )
    end
end

function PowerTools:saveGame()
    if not self:validateMPHost() then return end
    self.isQuickSaving = true
    g_currentMission:startSaveCurrentGame()
end

SavegameController.onSaveComplete = Utils.appendedFunction(SavegameController.onSaveComplete, function(self, errorCode)
    if not PowerTools.isQuickSaving then return end

    if errorCode == Savegame.ERROR_OK then
        --TODO: check dialog
        g_gui:closeDialogByName("MessageDialog")
    else
        --TODO: check dialog
        g_gui:showInfoDialog({
            dialogType = DialogElement.TYPE_WARNING,
            text = g_currentMission.inGameMenu.l10n:getText(InGameMenu.L10N_SYMBOL.NOT_SAVED)
        })    
    end

    PowerTools.isQuickSaving = nil
end)

function PowerTools:spawnSquareBales()
end

function PowerTools:spawnSquareBales()
end


function PowerTools:saveAction(type, targetObject, targetCommand, payload)
    self.lastAction = {
        actionType= type,
        targetObject = targetObject,
        targetCommand = targetCommand,
        payload = payload,
    }
end

function PowerTools:spawnBales(baleType)
    local options = {}
    for index, baleSize in ipairs(baleType.sizes) do
        local title
        if baleSize.isRoundbale then
            title = g_i18n:getText("fillType_roundBale") .. " " .. tostring(baleSize.diameter) .. "x" .. tostring(baleSize.width) .. " (" .. tostring(baleSize.capacity) .. "L)"
        else
            title = g_i18n:getText("fillType_squareBale") .. " " .. tostring(baleSize.width) .. "x" .. tostring(baleSize.height) .. "x" .. tostring(baleSize.length) .. " (" .. tostring(baleSize.capacity) .. "L)"
        end
        options[#options + 1] = title
    end

    local function showBaleTypeOptions()
        --TODO: FIX DIALOG
        self:showOptionDialog(
            g_i18n:getText("spawnObjectsActionText"),
            g_i18n:getText("spawnObjectsActionTitle"),
            options,
            function(target, selectedOption)
                if type(selectedOption) == "number" and selectedOption > 0 then
                    local baleSize = baleType.sizes[tonumber(selectedOption)]
                    local wrapState = (baleSize.wrapState and 1) or nil
                    local payload = { baleType.fillTypeName, tostring(baleSize.isRoundbale), baleSize.width, (baleSize.isRoundbale and baleSize.diameter) or baleSize.height, baleSize.length, wrapState }
                    g_baleManager:consoleCommandAddBale(unpack(payload))
                    self:saveAction(ACTION.SPAWN_BALE, g_baleManager,g_baleManager.consoleCommandAddBale, payload )
                    showBaleTypeOptions()
                else
                    self:spawnObjects()
                end
            end,
            true
        )
            
    end

    showBaleTypeOptions()

end

-- _G.executeConsoleCommand = Utils.overwrittenFunction(_G.executeConsoleCommand, function(self, superFunc, consoleCommand, arguments)
--     Log:var("consoleCommand", consoleCommand)
--     Log:var("arguments", arguments)
--     return superFunc(self, consoleCommand, arguments)
-- end)

function PowerTools:executeConsoleAction(actionType, consoleCommand, arguments, saveAction)
    arguments = arguments or ""
    if type(arguments) == "table" then
        local newArguments = ""
        for index, value in ipairs(arguments) do
            newArguments = newArguments .. tostring(value) .. " "
        end
        -- arguments = table.concat(arguments, " ")
        arguments = newArguments

    end
    local newCommand = consoleCommand .. " " .. arguments
    Log:var("newCommand", newCommand)
    self:executeAction(actionType, _G, "executeConsoleCommand", { newCommand }, saveAction)
end

function PowerTools:executeAction(actionType, targetObject, targetCommand, payload, saveAction, appendTargetToPayload)
    local callback = targetObject[targetCommand]

    local function getPayload()
        if not appendTargetToPayload then return payload end

        local newPayload = { targetObject }
        for index, value in ipairs(payload) do
            newPayload[index + 1] = value
        end
        return newPayload
    end

    payload = getPayload()
    
    local returnValue = callback(unpack(payload))

    if saveAction then
        self:saveAction(actionType, targetObject, targetCommand, payload)
    end

    return returnValue
end


local DEFAULT_FILLABLE_PALLET_FILENAME = "data/objects/pallets/fillablePallet/fillablePallet.xml"
local DEFAULT_FILLABLE_VEGETABLE_PALLET_FILENAME = "data/objects/pallets/vegetablesPallet/vegetablesPallet.xml"
local DEFAULT_IBC_PALLET_FILENAME = "data/objects/pallets/liquidTank/fertilizerTank.xml" --TODO: fix

function PowerTools:preparePalletFillTypes()
    if self.palletTypesDefault and self.palletTypesExtended then
        return self.palletTypesDefault, self.palletTypesExtended
    end

    local function createPalletFilter(items)
        local filter = {}
        for index, fillType in ipairs(items) do
            filter[fillType] = true
        end
        return filter
    end

    --TODO: add more types
    --These would need special handling: TREESAPLINGS, METHANE
    local forcedFillablePallet = createPalletFilter({
        "PEA",
        "WHEAT_CUT",
        "BARLEY_CUT",
        "POAT_CUTEA",
        "CANOLA_CUT",
        "SOYBEAN_CUT",
    })
    local forcedFillableVegetablePallet = createPalletFilter({
        "SUGARBEET",
        "SUGARBEET_CUT",

    })
    local forcedIBCPallet = createPalletFilter({
        -- "DIESEL", --TODO: fix
        -- "DEF",
        -- "MILK",
        -- "BUFFALOMILK",
        -- "WATER",
        -- "DIGESTATE",
    })
    local function addFilltypeToPalletList(listTable, fillType, isExtended)
        listTable[#listTable + 1] = { fillType.index, fillType.name, fillType.title, fillType.palletFilename, isExtended }
    end

    local palletTypesDefault = {}
    local palletTypesExtended = {}

    for index, fillType in ipairs(g_fillTypeManager.fillTypes) do
        local palletFilename = fillType.palletFilename
        local hasPallet = palletFilename ~= nil 
        local isDefaultPallet = hasPallet and palletFilename:find("fillablePallet.xml") == nil

        if isDefaultPallet then
            addFilltypeToPalletList(palletTypesDefault, fillType)
            addFilltypeToPalletList(palletTypesExtended, fillType)
        elseif hasPallet then
            addFilltypeToPalletList(palletTypesExtended, fillType)
        elseif forcedFillablePallet[fillType.name] ~= nil then
            fillType.palletFilename = DEFAULT_FILLABLE_PALLET_FILENAME
            addFilltypeToPalletList(palletTypesExtended, fillType, true)
        elseif forcedFillableVegetablePallet[fillType.name] ~= nil then
            fillType.palletFilename = DEFAULT_FILLABLE_VEGETABLE_PALLET_FILENAME
            addFilltypeToPalletList(palletTypesExtended, fillType, true)
        elseif forcedIBCPallet[fillType.name] ~= nil then
            fillType.palletFilename = DEFAULT_IBC_PALLET_FILENAME
            addFilltypeToPalletList(palletTypesExtended, fillType, true)
        end
    end

    self.palletTypesDefault = palletTypesDefault
    self.palletTypesExtended = palletTypesExtended

    return palletTypesDefault, palletTypesExtended
end

function PowerTools:spawnPallet(palletType, amount)
    Log:table("spawnPallet", { self = self, palletType = palletType, amount = amount })
    local fillTypeName = palletType[2]
    local fillType = g_fillTypeManager.nameToFillType[fillTypeName]
    -- local origPalletFilename = fillType.palletFilename
    fillType.originalPalletFilename = fillType.originalPalletFilename or fillType.palletFilename

    if #palletType == 5 and palletType[5] then
        fillType.palletFilename = palletType[4]
    end
    -- g_currentMission.vehicleSystem:consoleCommandAddPallet(fillType.name, amount)
    xpcall(function() 
            g_currentMission.vehicleSystem:consoleCommandAddPallet(fillType.name, amount)
        end, 
        function(err) 
            Log:warning("Failed to add pallet %s", fillType.name .. " " .. err .. "")
        end
    )

    fillType.palletFilename = fillType.originalPalletFilename
end


function PowerTools:spawnPallets(advancedMode)
    Log:var("spawnObjects@altMode", advancedMode)
    local defaultPalletTypes, extendedPalletTypes = self:preparePalletFillTypes()
    local activePalletTypes = advancedMode and extendedPalletTypes or defaultPalletTypes
    -- local palletTypes = {}
    -- for index, fillType in ipairs(g_fillTypeManager.fillTypes) do
    --     if fillType.palletFilename ~= nil and fillType.palletFilename:find("fillablePallet.xml") == nil then
    --         palletTypes[#palletTypes + 1] = { fillType.index, fillType.name, fillType.title, fillType.palletFilename }
    --     end
    -- end

    local options = {}
    for index, value in ipairs(activePalletTypes) do
        options[#options + 1] = value[3]
    end

    local function showPalletOptions(lastOption)
        lastOption = lastOption or 1
        --TODO: add optional amount
        self:showOptionDialog(
            g_i18n:getText("spawnObjectsActionText"),
            g_i18n:getText("spawnObjectsActionTitle"),
            options,
            function(target, selectedOption)
                Log:var("selectedOption", selectedOption)
                if selectedOption > 0 then
                    -- g_currentMission:consoleCommandAddPallet(palletTypes[selectedOption][2])
                    local fillTypeName = activePalletTypes[selectedOption][2]

                    -- self:spawnPallet(activePalletTypes[selectedOption])--TODO: save action
                    self:executeAction(ACTION.SPAWN_PALLET, self, "spawnPallet", { activePalletTypes[selectedOption] }, true, true)


                    -- self:executeConsoleAction(ACTION.SPAWN_PALLET, "gsPalletAdd", fillTypeName, true)
                    -- self:executeAction(ACTION.SPAWN_PALLET, g_currentMission.vehicleSystem, "consoleCommandAddPallet", { fillTypeName }, true, true)
                    
                    -- g_currentMission.vehicleSystem:consoleCommandAddPallet("wheat", "500")
                    -- executeConsoleCommand("gsPalletAdd " .. palletTypes[selectedOption][2])

                    -- self:saveAction(ACTION.SPAWN_PALLET, g_currentMission, g_currentMission.consoleCommandAddPallet, { palletTypes[selectedOption][2] })
                    showPalletOptions(selectedOption)
                end
            end,
            true,
            lastOption
        )
            
    end

    showPalletOptions()
end


function PowerTools:spawnLogs()
    Log:debug("Spwaning logs")
    -- Log:table("g_treePlantManager", g_treePlantManager)
    Log:table("SPRUCE1", g_treePlantManager.nameToTreeType["SPRUCE1"])
    Log:var("Name of tree", g_i18n:getText("treeType_oak"))

    -- g_treePlantManager.nameToTreeType
	-- if treeType == nil then
	-- 	treeType = "SPRUCE1"
	-- end
    -- BIRCH
    -- PINE
    -- SPRUCE1

    -- nameToTreeType
    -- nameI18N :: treeType_oak
    -- treeFilenames

	-- local treeTypeDesc = g_treePlantManager:getTreeTypeDescFromName(treeType)

	-- if treeTypeDesc == nil then
	-- 	return "Invalid tree type. " .. usage
	-- end

	-- growthState = Utils.getNoNil(growthState, table.getn(treeTypeDesc.treeFilenames))    
    -- g_currentMission:consoleCommandLoadTree(MathUtil.clamp(6, 1, 8), "SPRUCE1", 6)


    local knowTreeTypesBlacklist = {
        APPLE = { },            
        BEECH = {},            
        LODGEPOLEPINE = {},    
        BOXELDER = { -1 },         
        CHERRY = { 3, 4, 5 },           
        JAPANESEZELKOVA = { 4, 5, 6, 7, 8},  
        TRANSPORT = {},        
        PINUSSYLVESTRIS = {},  
        CHINESEELM = { 3, 4 },       
        DEADWOOD = {},         
        AMERICANELM = { 6, 7, 8 },      
        RAVAGED = {},          
        SHAGBARKHICKORY = { 6, 7 },  
        BETULAERMANII = { 3, 4, 5, 6, 7 },    
        DOWNYSERVICEBERRY = { 4, 5, 6, 7},
        ASPEN = {},            
        PINUSTABULIFORMIS = {},
        OAK = { 5, 6, 7, 8},              
        GOLDENRAIN = { 3, 5 },       
        TILIAAMURENSIS = { 4, 5, 6, 7, 8 },   
        NORTHERNCATALPA = { -1 },              
    } 




    local logTypes = {}
    local function addLogType(treeType, length)
        if knowTreeTypesBlacklist[treeType.name] ~= nil then
            if knowTreeTypesBlacklist[treeType.name][1] == -1 then
                Log:var("Skip tree", treeType.name)
                return
            end
            for index, value in ipairs(knowTreeTypesBlacklist[treeType.name]) do
                if value == length then
                    Log:var("Skip length " .. treeType.name, length)
                    return
                end
            end
        end
        logTypes[#logTypes + 1] = { treeType.index, treeType.name, treeType.title .. " [" .. length .. "m]", length }
    end
    for name, treeType in pairs(g_treePlantManager.nameToTreeType) do
        -- if name == "SPRUCE1" or name == "BIRCH" or name == "PINE" then
            local maxLength = (name == "PINE" and 8) or 8
            -- addLogType(treeType, 1)
            for i = 3, maxLength, 1 do
                -- check modulo
                -- if i % 2 == 0 or i == 7 then
                    addLogType(treeType, i)
                -- end
                -- addLogType(treeType, i)
            end
            -- logTypes[#logTypes + 1] = { treeType.index, treeType.name, g_i18n:getText(treeType.nameI18N), #treeType.treeFilenames, maxLength }
        -- end
    end
    
    local options = {}
    for index, value in ipairs(logTypes) do
        options[#options + 1] = value[3]
    end

    local function showLogOptions(preventReset, previousOption)
        --TODO: FIX DIALOG
        self:showOptionDialog(
            g_i18n:getText("spawnObjectsActionText"),
            g_i18n:getText("spawnObjectsActionTitle"),
            options,
            function(target, selectedOption)
                if selectedOption > 0 then
                    local selectedLogType = logTypes[selectedOption]
                    -- g_currentMission:consoleCommandLoadTree(selectedLogType[5], selectedLogType[2], selectedLogType[4])
                    -- g_treePlantManager:consoleCommandLoadTree(selectedLogType[5], selectedLogType[2], selectedLogType[4])

                    local treeLength = selectedLogType[4]
                    local treeType = selectedLogType[2]
                    -- local cmd = string.format( "gsTreeAdd %d %s 24 true", treeLength, treeType )
                    -- executeConsoleCommand(cmd)                  
                    g_treePlantManager:consoleCommandLoadTree(treeLength, treeType, 24)
                    
                    self:saveAction(ACTION.SPAWN_LOG, g_treePlantManager, g_treePlantManager.consoleCommandLoadTree, { treeLength, treeType, 24 })

                    showLogOptions(true, selectedOption)
                end
            end,
            preventReset,
            previousOption or 1
        )
            
    end

    showLogOptions(false)
end

function PowerTools:unwrapBaleTypes()
    local baleTypes = { }
    
    for index, baleType in ipairs(g_baleManager.bales) do
        if baleType.isAvailable then
            for index, baleFillType in ipairs(baleType.fillTypes) do
                local fillType = g_fillTypeManager:getFillTypeByIndex(baleFillType.fillTypeIndex)
                local fillTypeName = fillType.name
                
                baleTypes[fillTypeName] = baleTypes[fillTypeName] or {
                    fillTypeIndex = baleFillType.fillTypeIndex,
                    fillTypeTitle = fillType.title,
                    fillTypeName = fillTypeName,
                    sizes = {},
                }

                local baleSizes = baleTypes[fillTypeName].sizes

                baleSizes[#baleSizes + 1] = {
                    isRoundbale = baleType.isRoundbale,
                    diameter = baleType.diameter,
                    width = baleType.width,
                    height = baleType.height,
                    length = baleType.length,
                    capacity = baleFillType.capacity,
                    wrapState = true and (fillTypeName:upper() == "SILAGE")
                }
            end
        end
    end
    self.baleTypes = baleTypes
end

function PowerTools:showWarningIfNoAccess(hasAccess, custoMessage)
    if not hasAccess then
        g_currentMission:showBlinkingWarning(custoMessage or g_i18n:getText("warning_youDontHaveAccessToThis"))
    end
    return hasAccess
end

function PowerTools:canTransferMoney()
    return self:getHasAdminAccess() or g_currentMission:getHasPlayerPermission(Farm.PERMISSION.TRANSFER_MONEY)
end

function PowerTools:validateIsFarmFinanceManager()
    return PowerTools:showWarningIfNoAccess(self:canTransferMoney())
end

-- function PowerTools:validateMPFarmAdmin()
--     return PowerTools:showWarningIfNoAccess(self:getIsValidFarmManager())
-- end

-- function PowerTools:validateMPServerAdmin()
--     return PowerTools:showWarningIfNoAccess(self:getIsMasterUser())
-- end

function PowerTools:validateFarm()
    return PowerTools:showWarningIfNoAccess(not self:getIsSpectatorFarm()) --TODO: add custom error message
end

---Ensure the current player has relevant admin access. If the first argument is true, only server admins are given access.
---@param requireServerAdmin boolean 'Only allow server admins access, i.e. regular farm admins are not allowed'
---@return boolean 'True if the player has admin access, false otherwise'
function PowerTools:validateMPAdmin(requireServerAdmin)
    return PowerTools:showWarningIfNoAccess((requireServerAdmin and self:getIsServerAdmin()) or self:getHasAdminAccess())

    -- if not requireFarmAdmin and g_currentMission.getIsServer() == true then
    --     return true
    -- end

    -- --currentMission:getHasPlayerPermission(Farm.PERMISSION.SELL_VEHICLE)
    -- if not self:getIsMasterUser() or not self:getIsValidFarmManager() then --not self:getIsValidFarmManager() then
    --     g_currentMission:showBlinkingWarning(g_i18n:getText("warning_youDontHaveAccessToThis"))
    --     return false
    -- end    
    -- return true
end

function PowerTools:validateMPHost()
    if not self:getIsServer() then
        g_currentMission:showBlinkingWarning(g_i18n:getText("warning_youDontHaveAccessToThis"))
        return false
    end    
    return true
end

function PowerTools:spawnObjects(altMode)
    Log:var("spawnObjects@altMode", altMode)

    --TODO: this is a temporary solution, should be changed to allow all farm admins when working
    if not self:validateMPHost() or not self:validateFarm() then return end
    -- if not self:validateMPAdmin() or not self:validateFarm() then return end

    if self.baleTypes == nil then
        self:unwrapBaleTypes()
    end

    local actions = {}

    for key, value in pairs(self.baleTypes) do
        actions[#actions + 1] = {
            g_i18n:getText("infohud_bale") .. " [" .. value.fillTypeTitle .. "]",
            self.spawnBales,
            { value }
        }
    end

    table.insert( actions, 1 , { g_i18n:getText("infohud_pallet") .. (altMode and SUFFIX_ADVANCED or ""), self.spawnPallets, {altMode } } )--infohud_pallet 
    table.insert( actions, 2 , { g_i18n:getText("fillType_wood"), self.spawnLogs, { altMode } } )

    self:showSubMenu(
        g_i18n:getText("spawnObjectsActionText"),
        g_i18n:getText("spawnObjectsActionTitle"),
        nil,
        actions
    )

    if true then
        return
    end

end

local function clearLogFile()
    --! No longer works in v1.12

    local profilePath = getUserProfileAppPath()
    if profilePath == nil or profilePath == "" then
        return
    end

    local fileName = profilePath .. "log.txt"
    if fileExists(fileName) then
        copyFile(fileName, fileName .. ".bak", true)

        local success = pcall(function()
            os.remove(fileName)
        end)

        if not success then
            Logging.warning("Failed to clear log file (backup method)")
        end

        local success = pcall(function()
            local logFile = io.open(fileName, "w")
            logFile:write("** Log cleared and backed up by PowerTools **")
            logFile:close()
        end)

        if not success then
            Logging.warning("Failed to clear log file (main method)")
        end

    end
end

local function quitGame(restart, hardReset)
    restart = restart or false
    hardReset = hardReset or false

    local success = pcall(function()
        if not hardReset and g_currentMission ~= nil then
            OnInGameMenuMenu()
            
        end

        RestartManager:setStartScreen(RestartManager.START_SCREEN_MAIN)

        local gameID = ""
        if restart and g_careerScreen ~= nil and g_careerScreen.currentSavegame ~= nil then
            gameID = g_careerScreen.currentSavegame.savegameIndex
        end

        doRestart(hardReset, "-autoStartSavegameId " .. gameID)
        
    end)

    if not success then
        PowerTools:printError("Failed to exit/restart game")
    end
end

local function exitToMenu(force)
    Log:info("Exiting to menu")
    
    quitGame(false, force)
end

local function restartGame(force)
    local savegameName = "unknown"
    local saveGameIndex = "?"

    pcall(function()
        savegameName = g_careerScreen.currentSavegame.savegameName
        saveGameIndex = g_careerScreen.currentSavegame.savegameIndex
    end)

    Log:info("Restarting current savegame '%s' [%d]", savegameName, saveGameIndex)
    quitGame(true, force)
end



function PowerTools:confirmExitRestartGame(confirmCallback, ...)
    local callbackArgs = { ... }
    DialogHelper.showYesNoDialog({
        title = g_i18n:getText("confirmExit"),
        text = g_i18n:getText("exitRestartWarning"),
        callback =  function(self, yes)
            -- PowerTools:printDebugVar("doExit?", yes)
            if yes == true then
                confirmCallback(unpack(callbackArgs))
            end
        end,
        target = self
    })
end

function PowerTools:menuActionRestartGame()
    self:confirmExitRestartGame(function()
        restartGame(false)
    end)
end

function PowerTools:menuActionForceRestartGame()
    self:confirmExitRestartGame(function()
        restartGame(true)
    end)
end

function PowerTools:menuActionExitSavegame()
    self:confirmExitRestartGame(function()
        exitToMenu(false)
    end)
end

function PowerTools:menuActionForceExitSavegame()
    self:confirmExitRestartGame(function()
        exitToMenu(true)
    end)

end

function PowerTools:onHelpTextKey_doublePress()
    g_currentMission:showBlinkingWarning("onHelpTextKey_doublePress")
end

function PowerTools:onHelpTextKey_longPress()
    g_currentMission.hud:consoleCommandToggleVisibility()
end

function PowerTools:hookIntoGlobalKeys(dt)
    if self.globalKeysInitiated == true then
        Log:trace("SKIP hookIntoGlobalKeys")
        return
    end
    Log:trace("hookIntoGlobalKeys")

    local helpTextActionEvent = GlobalHelper.GetActionEvent(InputAction.TOGGLE_HELP_TEXT, nil, true)
    -- Log:table("helpTextActionEvent4", helpTextActionEvent, 2)


    if helpTextActionEvent ~= nil then
        local helpTextKeyMSKH = MultistateKeyHandler.new()
        helpTextKeyMSKH:injectIntoAction(helpTextActionEvent, nil, false)
        -- helpTextKeyMSKH:setCallback(MULTISTATEKEY_TRIGGER.DOUBLE_PRESS, self.onHelpTextKey_doublePress, self)
        helpTextKeyMSKH:setCallback(MULTISTATEKEY_TRIGGER.LONG_PRESS, self.onHelpTextKey_longPress, self)

        self.helpTextKeyMSKH = helpTextKeyMSKH

    end

    self.globalKeysInitiated = (helpTextActionEvent ~= nil)
end

-- Player.load = Utils.overwrittenFunction(Player.load, function (self, superFunc, ...)
--     Log:debug("Player.load")
--     local retVal = superFunc(self, ...)
--     Log:var("Player.load g_localPlayer", g_localPlayer)
--     Log:var("Player.load TOGGLE_HELP_TEXT", GlobalHelper.GetActionEvent(InputAction.TOGGLE_HELP_TEXT, nil, true))
--     return retVal
-- end)

if ENABLE_EXPERIMENTAL_HUDHIDE then
    Log:info("Experiment HUD hide enabled")

    Player.onStartMission = Utils.overwrittenFunction(Player.onStartMission, function (self, superFunc, ...)
        -- Log:debug("Player.onStartMission")
        local retVal = superFunc(self, ...)
        -- Log:var("Player.onStartMission g_localPlayer", g_localPlayer)
        -- Log:var("Player.onStartMission TOGGLE_HELP_TEXT", GlobalHelper.GetActionEvent(InputAction.TOGGLE_HELP_TEXT, nil, true))
        PowerTools:hookIntoGlobalKeys()
        return retVal
    end)
end
-- PlayerInputComponent.onPlayerLoad = Utils.overwrittenFunction(PlayerInputComponent.onPlayerLoad, function (self, superFunc, ...)
--     -- Log:debug("PlayerInputComponent.onPlayerLoad")
--     local retVal = superFunc(self, ...)
--     Log:var("PlayerInputComponent.onPlayerLoad g_localPlayer", g_localPlayer)
--     Log:var("PlayerInputComponent.onPlayerLoad TOGGLE_HELP_TEXT", GlobalHelper.GetActionEvent(InputAction.TOGGLE_HELP_TEXT, nil, true))
--     -- Log:table("PlayerInputComponent.onPlayerLoad():player.toggleFlightModeCommand", self.player.toggleFlightModeCommand, 2)
--     return retVal
-- end)


function PowerTools:update(dt)
    if self.pendingRestartMode == RESTART_MODE.EXIT then
        exitToMenu(false)
    elseif self.pendingRestartMode == RESTART_MODE.EXIT_FORCED then
        exitToMenu(true)
    elseif self.pendingRestartMode == RESTART_MODE.RESTART then
        restartGame(false)
    elseif self.pendingRestartMode == RESTART_MODE.RESTART_FORCED then
        restartGame(true)
    end


    -- if not self.globalKeysInitiated then
    --     self:hookIntoGlobalKeys(dt)
    -- end
end

function PowerTools:commandQuitGame()
    doExit()
end

function PowerTools:consoleCommandRestartGame(softRestart)
    restartGame(not (softRestart or false))
end

function PowerTools:consoleCommandExitGame(softExit)
    exitToMenu(not (softExit or false))
end

function PowerTools:consoleCommandClearLog()
    clearLogFile()
end

function PowerTools:keyEvent(unicode, sym, modifier, isDown)
    if not self.settings.allowRestartWhenPaused and not self.settings.allowRestartInMenus then
        return -- No need to check the below if we won't show the menu anyway
    end
    
    local inputActionName = InputAction.POWERTOOLSMENU --InputAction.POWERTOOLSMENU -- InputAction.POWERTOOLS_REPEAT_ACTION
    local actionName = g_inputBinding.nameActions[inputActionName]
    local firstBinding = actionName.activeBindings ~= nil and actionName.activeBindings[1] or nil
    local unmodifiedAxis = firstBinding ~= nil and firstBinding.unmodifiedAxis or nil
    local inputKey = unmodifiedAxis ~= nil and Input[unmodifiedAxis] or nil
    local isKeyPressed = not isDown and sym == inputKey
    local modifierAxisSet = firstBinding ~= nil and firstBinding.modifierAxisSet

    local allModKeysDown = true
    if modifierAxisSet ~= nil then
        for _, modifierAxis in pairs(modifierAxisSet) do
            local modKey = Input[modifierAxis]
            local modKeyDown = Utils.getNoNil(Input.isKeyPressed(modKey), false)
            -- local modKeyData = {
            --     axis = modifierAxis,
            --     key = modKey, 
            --     keyDown = modKeyDown,
            -- }

            allModKeysDown = allModKeysDown and modKeyDown
        end
    else
        allModKeysDown = (modifier == 0)
    end

    if isKeyPressed and allModKeysDown then
        local isGuiVisible = g_gui:getIsGuiVisible()
        -- local noDialogsIsOpen = g_gui.currentGui == nil and not g_gui:getIsDialogVisible()
        -- local isOnlyMenuOpen = g_gui.currentGui ~= nil and not g_gui:getIsDialogVisible()
        local numOpenDialogs = (g_gui.dialogs ~= nil and #g_gui.dialogs) or 0
        local isMainMenuOpen = isGuiVisible and (g_gui.currentGuiName == "InGameMenu")
        local isOtherMenuOpen = isGuiVisible and not isMainMenuOpen --(g_gui.currentGuiName ~= "" and g_gui.currentGuiName ~= "InGameMenu")
        local isPaused = g_currentMission.paused == true
        local isMenuAllowed = (isPaused and self.settings.allowRestartWhenPaused) or not isPaused -- We only allow in non-paused mode or when explictly allowed

        isMenuAllowed = isMenuAllowed and self.settings.allowRestartInMenus
        isMenuAllowed = isMenuAllowed and not isOtherMenuOpen and (numOpenDialogs == 0)

        -- Log:var("isPaused", isPaused)
        -- Log:var("isMenuAllowed", isMenuAllowed)
        -- Log:var("isMainMenuOpen", isMainMenuOpen)
        -- Log:var("isOtherMenuOpen", isOtherMenuOpen)

        if isMenuAllowed then
            self:showMenu()
        end
    end
end

function PowerTools:loadMap()
    if self:getIsMultiplayer() then
        Log:info("Running in multiplayer mode, some features will be disabled [isMaster=%s, isServer=%s, isServerAdmin=%s, isFarmAdmin=%s]", self:getIsMasterUser(), self:getIsServer(), self:getIsServerAdmin(), self:getHasAdminAccess())
    else
        Log:debug("PowerTools is running in singleplayer mode [isMaster=%s, isServer=%s, isServerAdmin=%s, isFarmAdmin=%s]", self:getIsMasterUser(), self:getIsServer(), self:getIsServerAdmin(), self:getHasAdminAccess())
    end

    -- local helpTextActionEvent = GlobalHelper.GetActionEvent(InputAction.TOGGLE_HELP_TEXT, nil, true)
    -- Log:table("helpTextActionEvent1", helpTextActionEvent, 2)
end

-- function PowerTools:startMission()
--     local helpTextActionEvent = GlobalHelper.GetActionEvent(InputAction.TOGGLE_HELP_TEXT, nil, true)
--     Log:table("helpTextActionEvent3", helpTextActionEvent, 2)
-- end


function PowerTools:load()
    --TODO should use addSafe version from DevTools
    addConsoleCommand("ee", "Exit to the menu", "consoleCommandExitGame", self)
    addConsoleCommand("rr", "Force restart savegame", "consoleCommandRestartGame", self)
    addConsoleCommand("qq", "Quit the game", "commandQuitGame", self)
    addConsoleCommand("ptTable", "Print table", "consoleCommandPrintTable", self)
    addConsoleCommand("ptClearLog", "Clear log file", "consoleCommandClearLog", self)

    --TODO should be read from config
    self.settings = {}
    self.settings.allowRestartInMenus = true
    self.settings.allowRestartWhenPaused = true
    self.settings.defaultToForceCommands = false
end

function PowerTools:delete()
    -- self:printDebug("Unloading mod Power Tools")
    removeConsoleCommand("ee")
    removeConsoleCommand("rr")
    removeConsoleCommand("qq")
    removeConsoleCommand("ptTable")
    
end

function PowerTools:featureToggle(feature, delegate)
    if feature == true then
        if delegate ~= nil and type(delegate) == "function" then
            delegate(self)
        else
            Log:error("Feature toggle delegate is not a function")
        end
    end
end



PlayerMover.toggleFlightActive = Utils.appendedFunction(PlayerMover.toggleFlightActive, function(self, superFunc, ...)
    if g_localPlayer.toggleFlightModeCommand.value then

        if self.isFlightActive then
            g_currentMission:addGameNotification("", g_i18n:getText("flightActivated"), g_i18n:getText("flightActivatedExtra"), nil, 1000)
        else
            g_currentMission:addGameNotification("", g_i18n:getText("flightDeactivated"), g_i18n:getText("flightDeactivatedExtra"), nil, 1000)
        end
    end
    --HACK: probably not needed
    if superFunc ~= nil then
        return superFunc(self, ...)
    end
end)



-- if FEATURE_TOGGLE.EXTENDED_TIMESCALE then
--     Log:var("FS25_UniversalGameTweaks", g_modIsLoaded.FS25_UniversalGameTweaks)
--     -- Log:var("__g.FS25_UniversalGameTweaks", PowerTools.__g["FS25_UniversalGameTweaks"])
--     PowerTools:source("PowerTools_ExtendedTimeScales.lua")
--     Log:var("ExtendedTimeScales", ExtendedTimeScales)
--     if ExtendedTimeScales == nil then
--         Log:warning("Failed to load Extended Time Scales module from PowerTools")        
--     else
--         ExtendedTimeScales.init(PowerTools)
--         Log:info("Extended time scales enabled")
--     end
-- end

--*** FEATURE TOGGLE: EXTENDED TIMESCALES ***
PowerTools:featureToggle(FEATURE_TOGGLE.EXTENDED_TIMESCALE, function(self)
    if g_modIsLoaded.FS25_UniversalGameTweaks then
        Log:info("FS25_UniversalGameTweaks is already loaded, the extended time scales module of PowerTools will not be loaded")
        return
    end
    -- Log:var("FS25_UniversalGameTweaks", g_modIsLoaded.FS25_UniversalGameTweaks)
    -- Log:var("__g.FS25_UniversalGameTweaks", PowerTools.__g["FS25_UniversalGameTweaks"])
    self:source("PowerTools_ExtendedTimeScales.lua")
    -- Log:var("ExtendedTimeScales", ExtendedTimeScales)
    if ExtendedTimeScales == nil then
        Log:warning("Failed to load Extended Time Scales module from PowerTools")        
    else
        ExtendedTimeScales.init(self)
        Log:info("Extended time scales enabled")
    end    
end)


--*** FEATURE TOGGLE: SUPERSTRENGTH HACK ***
PowerTools:featureToggle(FEATURE_TOGGLE.SUPERSTRENGTH_HACK, function(self)

    Log:debug("Init super strength hack")

    FSBaseMission.sendInitialClientState = Utils.overwrittenFunction(FSBaseMission.sendInitialClientState, function(self, originalFunc, conn, usr, ...)
        originalFunc(self, conn, usr, ...)
        Log:debug("sendInitialClientState")
    
        local player = conn and g_currentMission:getPlayerByConnection(conn)
    
        if player and player.hands.consoleCommandToggleSuperStrength ~= nil then
            local name = usr and usr.nickname or "[UNKNOWN PLAYER]"
    
            
            Log:var("mass before", player.hands.spec_hands.currentMaximumMass)
            
            -- player.hands.spec_hands.currentMaximumMass = HandToolHands.SUPER_STRENGTH_PICKUP_MASS
            
            player.hands:consoleCommandToggleSuperStrength()
            -- player.hands.spec_hands.currentMaximumMass = HandToolHands.MAXIMUM_PICKUP_MASS
            Log:var("mass after", player.hands.spec_hands.currentMaximumMass)
    
            Log:info("SuperStrength MP hack enabled for %s", name)
        end
    
    end)

end)