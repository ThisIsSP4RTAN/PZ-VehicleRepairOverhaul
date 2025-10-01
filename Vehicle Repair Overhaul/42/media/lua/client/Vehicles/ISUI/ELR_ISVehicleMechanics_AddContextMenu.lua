---@diagnostic disable: param-type-mismatch
-- Mod options table (replace this with actual settings loader if needed)
local VRO = require("VRO_modOptions")

require "Vehicles/ISUI/ISVehicleMechanics"

-- Full override of ISVehicleMechanics:doPartContextMenu with vanilla Lightbar repair block removed
local _Original_doPartContextMenu = ISVehicleMechanics.doPartContextMenu
local old_ISVehicleMechanics_doPartContextMenu = ISVehicleMechanics.doPartContextMenu

function ISVehicleMechanics:doPartContextMenu(part, x, y, context)
    if not self.context then
        self.context = ISContextMenu.get(self.playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY())
    end
    if not context then
        self.context = ISContextMenu.get(self.playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY())
    else
        self.context = context
    end

    if self.context then
        self.context:clear()
    end

    local option = nil

    	-- SKIPPING: Vanilla Lightbar Repair block intentionally
    if part and part:getId() and string.lower(part:getId():trim()) == "lightbar" then
        -- Custom mod logic (ContextMenu_EHR) will run separately
    else
        -- Let vanilla logic handle all other parts
        _Original_doPartContextMenu(self, part, x, y)
    end

	-- If the game is paused we should skip creating our context menu
	if UIManager.getSpeedControls():getCurrentGameSpeed() == 0 then return end

	if VRO.Options.HideVanillaRepair then
		if old_ISVehicleMechanics_doPartContextMenu then
			old_ISVehicleMechanics_doPartContextMenu(self, part, x, y)
		end
	end
	-- It's most likely that the old version of this function has already created an instance of the context menu, but for robustness 
	--   we should check to ensure it exists, and if it doesn't we create a new one.
	local playerObj = getSpecificPlayer(self.playerNum)

	local option


	-- Add the option for repairing the lightbar to the context menu.

    if part:getId() == "lightbar" then
		-- Get the Mechanics skill level that is required to perform engine repair actions on this vehicle type and interpret that 
		--   as one higher than the Electricity skill level that will be required to repair the lightbar. We do this so we keep things simple and 
		--   don't have to worry about adding additional information to vehicle scripts to support different skill levels for 
		--   different vehicle types.
		-- Set the maximum skill level needed for repairs where condition > 0 at 5. We set the maximum skill level needed to repair the lightbar from condition 0 
		--   to be 6, so the skill level needed for all other repairs should be lower than that.
		local requiredSkillLevel = math.min(5, part:getVehicle():getScript():getEngineRepairLevel() - 1)
		local currentCondition = math.max(0, part:getCondition())

		local requiredParts = { ["Base.ElectronicsScrap"] = 5, ["Base.ElectricWire"] =  1, ["Base.LightBulb"] = 0, ["Base.Amplifier"] = 0 }

		if currentCondition <= 0 then
			requiredParts["Base.LightBulb"] = 2
			requiredParts["Base.Amplifier"] = 1
			requiredSkillLevel = math.min(requiredSkillLevel + 1, 6)

		end

		local numberOfScrapElectronics = self.chr:getInventory():getNumberOfItem("Base.ElectronicsScrap", false, true)
		local numberOfElectricWire = self.chr:getInventory():getNumberOfItem("Base.ElectricWire", false, true)

		local repairBlocksPossibleByParts = math.min(math.floor(numberOfScrapElectronics / 5.0), numberOfElectricWire)
		local repairBlocksPossibleByCondition = math.ceil(math.max(0.0, (100.0 - currentCondition)) / 10.0)

		local repairBlocksPossible = math.min(repairBlocksPossibleByParts, repairBlocksPossibleByCondition)

		local targetCondition = currentCondition

		if repairBlocksPossible > 0 then
			requiredParts["Base.ElectronicsScrap"] = repairBlocksPossible * 5
			requiredParts["Base.ElectricWire"] = repairBlocksPossible
			targetCondition = math.min(100, targetCondition + (repairBlocksPossible * 10))
		end

		local allPartsPresent = true

		for neededPart,numberNeeded in pairs(requiredParts) do
			if self.chr:getInventory():getNumberOfItem(neededPart, false, true) < numberNeeded then
				allPartsPresent = false
                    break
			end
		end

		if currentCondition < 100 and allPartsPresent and self.chr:getPerkLevel(Perks.Electricity) >= requiredSkillLevel and self.chr:getInventory():containsTag("Screwdriver") then
			option = self.context:addOption(getText("ContextMenu_Repair"), playerObj, ISVehicleMechanics.ELR_onRepairLightbar, part, repairBlocksPossible, requiredParts, targetCondition, requiredSkillLevel)
			self:ELR_doMenuTooltip(part, option, "ELR_repairlightbar", requiredParts, requiredSkillLevel, targetCondition)
		else
			option = self.context:addOption(getText("ContextMenu_Repair"), nil, nil)
			option.notAvailable = true
			self:ELR_doMenuTooltip(part, option, "ELR_repairlightbar", requiredParts, requiredSkillLevel, targetCondition)
		end
	end

	-- Since the old version of this function may have set the context menu to not be visible we must handle the case where 
	--   we have added an option to the menu and now have to make the menu visible.
	if self.context.numOptions == 1 then
		self.context:setVisible(false)
	else
		self.context:setVisible(true)
	end

	if JoypadState.players[self.playerNum+1] and self.context:getIsVisible() then
		self.context.mouseOver = 1
		self.context.origin = self
		JoypadState.players[self.playerNum+1].focus = self.context
		updateJoypadFocus(JoypadState.players[self.playerNum+1])
	end
end

function ISVehicleMechanics:ELR_doMenuTooltip(part, option, lua, requiredParts, requiredSkillLevel, targetCondition)
	local vehicle = part:getVehicle()
	local tooltip = ISToolTip:new()
	tooltip:initialise()
	tooltip:setVisible(false)
	tooltip.description = getText("Tooltip_craft_Needs") .. ": <LINE> <LINE>"
	option.toolTip = tooltip
	local keyvalues = part:getTable(lua)

	-- Repair lightbar tooltip
	if lua == "ELR_repairlightbar" then
		local rgb = " <RGB:0,1,0>"

		if self.chr:getPerkLevel(Perks.Electricity) < requiredSkillLevel then
			rgb = " <RGB:1,0,0>"
		end
		tooltip.description = tooltip.description .. rgb .. getText("IGUI_perks_Electricity") .. " " .. self.chr:getPerkLevel(Perks.Electricity) .. "/" .. requiredSkillLevel .. " <LINE>"
		rgb = " <RGB:0,1,0>"

        local scriptItem = ScriptManager.instance:getItem("Base.Screwdriver")
        local screwdriverItem = self.chr:getInventory():getFirstTagRecurse("Screwdriver")
        local displayName = screwdriverItem and screwdriverItem:getDisplayName() or "Screwdriver"
		if not self.chr:getInventory():containsTag("Screwdriver") then
			tooltip.description = tooltip.description .. " <RGB:1,0,0>" .. displayName .. " 0/1 <LINE>"
		else
			tooltip.description = tooltip.description .. " <RGB:0,1,0>" .. displayName .. " 1/1 <LINE>"
		end

		for neededPart,numberNeeded in pairs(requiredParts) do
			local scriptItem = ScriptManager.instance:getItem(neededPart)
			local displayName = getItemDisplayName(neededPart)
			local numberOfPart = self.chr:getInventory():getNumberOfItem(neededPart, false, true)

			if numberNeeded > 0 then
				if numberOfPart < numberNeeded then
					tooltip.description = tooltip.description .. " <RGB:1,0,0>" .. displayName .. " " .. numberOfPart .. "/" .. numberNeeded .. " <LINE>"
				else
					tooltip.description = tooltip.description .. " <RGB:0,1,0>" .. displayName .. " " .. numberOfPart .. "/" .. numberNeeded .. " <LINE>"
				end
			end
		end

		if option.notAvailable then
			tooltip.description = tooltip.description .. " <LINE><RGB:1,0,0>" .. getText("Tooltip_ELR_NewCondition") .. ": " .. targetCondition .. "%"
		else
			tooltip.description = tooltip.description .. " <LINE><RGB:0,1,0>" .. getText("Tooltip_ELR_NewCondition") .. ": " .. targetCondition .. "%"
		end
	end
end

function ISVehicleMechanics.ELR_onRepairLightbar(playerObj, part, repairBlocks, requiredParts, targetCondition, requiredSkillLevel)
	if playerObj:getVehicle() then
		ISVehicleMenu.onExit(playerObj)
	end

	local typeToItem = VehicleUtils.getItems(playerObj:getPlayerNum())
	local screwdriverItems = typeToItem["Base.Screwdriver"]
	local item = screwdriverItems and screwdriverItems[1] or nil

	ISVehiclePartMenu.toPlayerInventory(playerObj, item)

	-- Have the character walk to the vehicle's driver door
	ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, part:getVehicle(), "SeatFrontLeft"))


--[[

	************************************************************************************************************************************ 
		The below code adds some additional animation to have the player character get into the vehicle to turn off the lightbar 
		   if it is on when beginning to repair it. This introduces a lot of potential edge cases of trying to determine which 
		   door the player can open to enter the vehicle. This is a fun exercise to learn more about PZ modding, but it's getting more 
		   complex than may be warranted for an "easy" vehicle repair mod. So I'll leave it commented out for the time being 
		   and possibly revisit it in the future. If you are reading this and would like to use this additional animation code 
		   be aware that it works if the driver's door can be opened by the player, but will potentially cause issues if the 
		   driver's door can not be unlocked (e.g. that door's lock is broken). It will also only attempt to have the player enter 
		   the driver's door. If that door is locked, but another door is unlocked it will not attempt to enter through that other 
		   door, it will simply try to open the driver's door, fail, and end the repair attempt.
	************************************************************************************************************************************ 
--]]

--[[		   
	-- If the lightbar is turned on, turn it off before beginning the repair
	if (part:getVehicle():getLightbarLightsMode() ~= 0) or (part:getVehicle():getLightbarSirenMode() ~= 0) then
		local vehicleDoorPart = part:getVehicle():getPartById("DoorFrontLeft")
		local vehicleDoor = nil
		
		if vehicleDoorPart then vehicleDoor = vehicleDoorPart:getDoor() end
		
		-- If the door is locked, attempt to unlock it. If the player is unable to unlock the door, then the door will remain locked.
		if vehicleDoor and vehicleDoor:isLocked() then
			ISTimedActionQueue.add(ISUnlockVehicleDoor:new(playerObj, vehicleDoorPart, nil))
		end
		
		-- If the door is unlocked, then enter the vehicle, turn off the lightbar, get back out, and then perform the repair. If the 
		--   door is locked then we stop here and do nothing further (the repair will not take place).
		if not vehicleDoor:isLocked() then
			-- Have the character enter the driver's seat
			ISTimedActionQueue.add(ISOpenVehicleDoor:new(playerObj, part:getVehicle(), vehicleDoorPart))
			ISTimedActionQueue.add(ISEnterVehicle:new(playerObj, part:getVehicle(), 0))
				
			-- Turn off the lightbar
			ISTimedActionQueue.add(ELRTurnOffLightbar:new(playerObj), false, vehicle)
		
			-- Have the character exit the vehicle
			--ISTimedActionQueue.add(ISOpenVehicleDoor:new(playerObj, part:getVehicle(), part:getVehicle():getPartById("DoorFrontLeft")))
			ISTimedActionQueue.add(ISExitVehicle:new(playerObj))
		
			
			-- Queue our custom TimedAction to repair the lightbar
			ISTimedActionQueue.add(ELRRepairLightbar:new(playerObj, part, item, timeToRepair, repairBlocks, requiredParts, targetCondition))
		end
		
		-- Return here just in case the commented out animation code becomes uncommented
		return
	end
--]]


	local timeToRepair = (repairBlocks * 100) - math.max(0, (20 * (playerObj:getPerkLevel(Perks.Electricity) - requiredSkillLevel)))

	if (part:getVehicle():getLightbarLightsMode() ~= 0) or (part:getVehicle():getLightbarSirenMode() ~= 0) then
		-- Turn off the lightbar from outside of the vehicle
		ISTimedActionQueue.add(ELRTurnOffLightbar:new(playerObj, true, part:getVehicle():getId()))
	end
	local screwdriver = playerObj:getInventory():getFirstTagRecurse("Screwdriver")

-- Equip screwdriver in primary hand if not already equipped
if playerObj:getPrimaryHandItem() ~= screwdriver then
    ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, screwdriver, 50, true, false))
end -- Queue our custom TimedAction to repair the lightbar
	ISTimedActionQueue.add(ELRRepairLightbar:new(playerObj, part, item, timeToRepair, repairBlocks, requiredParts, targetCondition))
end