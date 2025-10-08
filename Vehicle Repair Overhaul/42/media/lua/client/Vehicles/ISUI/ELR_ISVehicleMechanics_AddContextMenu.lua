---@diagnostic disable: param-type-mismatch

require "Vehicles/ISUI/ISVehicleMechanics"

local _Original_doPartContextMenu = ISVehicleMechanics.doPartContextMenu

local function _findRepairOption(ctx)
	if not (ctx and ctx.options) then return nil end
	local label = getText("ContextMenu_Repair")
	for i = 1, #ctx.options do
		local opt = ctx.options[i]
		if opt and opt.name == label then
			return opt
		end
	end
	return nil
end

local function _clearSubMenu(opt)
	if not opt then return end
	if opt.subOption and opt.subOption.options then
		for i = #opt.subOption.options, 1, -1 do
			table.remove(opt.subOption.options, i)
		end
	end
	opt.subOption = nil
end

function ISVehicleMechanics:doPartContextMenu(part, x, y, context)
	_Original_doPartContextMenu(self, part, x, y, context)

	if not (part and part.getId and part:getId()) then return end
	if string.lower(part:getId():trim()) ~= "lightbar" then return end

	local ctx = context or self.context
	if not ctx then return end

	local parent = _findRepairOption(ctx)
	if not parent then
		parent = ctx:addOption(getText("ContextMenu_Repair"), nil, nil)
	end

	_clearSubMenu(parent)
	parent.toolTip = nil

	if UIManager.getSpeedControls():getCurrentGameSpeed() == 0 then return end

	local playerObj = getSpecificPlayer(self.playerNum)
	local requiredSkillLevel = math.min(5, part:getVehicle():getScript():getEngineRepairLevel() - 1)
	local currentCondition = math.max(0, part:getCondition())

	local requiredParts = { ["Base.ElectronicsScrap"] = 5, ["Base.ElectricWire"] = 1, ["Base.LightBulb"] = 0, ["Base.Amplifier"] = 0 }

	if currentCondition <= 0 then
		requiredParts["Base.LightBulb"] = 2
		requiredParts["Base.Amplifier"] = 1
		requiredSkillLevel = math.min(requiredSkillLevel + 1, 6)
	end

	local inv = self.chr:getInventory()
	local numberOfScrapElectronics = inv:getNumberOfItem("Base.ElectronicsScrap", false, true)
	local numberOfElectricWire     = inv:getNumberOfItem("Base.ElectricWire", false, true)

	local repairBlocksPossibleByParts     = math.min(math.floor(numberOfScrapElectronics / 5.0), numberOfElectricWire)
	local repairBlocksPossibleByCondition = math.ceil(math.max(0.0, (100.0 - currentCondition)) / 10.0)
	local repairBlocksPossible            = math.min(repairBlocksPossibleByParts, repairBlocksPossibleByCondition)

	local targetCondition = currentCondition
	if repairBlocksPossible > 0 then
		requiredParts["Base.ElectronicsScrap"] = repairBlocksPossible * 5
		requiredParts["Base.ElectricWire"]     = repairBlocksPossible
		targetCondition = math.min(100, targetCondition + (repairBlocksPossible * 10))
	end

	local allPartsPresent = true
	for neededPart, numberNeeded in pairs(requiredParts) do
		if inv:getNumberOfItem(neededPart, false, true) < numberNeeded then
			allPartsPresent = false
			break
		end
	end

	-- Set availability first so tooltip colors are correct
	if currentCondition >= 100
		or not allPartsPresent
		or (self.chr:getPerkLevel(Perks.Electricity) < requiredSkillLevel)
		or not inv:containsTag("Screwdriver") then
		parent.notAvailable = true
	else
		parent.notAvailable = false
	end

	-- Attach our tooltip to the parent "Repair" option
	self:ELR_doMenuTooltip(part, parent, "ELR_repairlightbar", requiredParts, requiredSkillLevel, targetCondition)

	-- Replace handler with our start function; pass minimal parameters
    parent.target   = playerObj
    parent.onSelect = ISVehicleMechanics.ELR_onRepairLightbar
    parent.param1   = part
    parent.param2   = repairBlocksPossible
    parent.param3   = requiredParts
    parent.param4   = targetCondition
    parent.param5   = requiredSkillLevel

	if self.context and self.context.numOptions == 1 then
		self.context:setVisible(false)
	elseif self.context then
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
	local tooltip = ISToolTip:new()
	tooltip:initialise()
	tooltip:setVisible(false)
	tooltip.description = getText("Tooltip_craft_Needs") .. ": <LINE> <LINE>"
	option.toolTip = tooltip

	if lua == "ELR_repairlightbar" then
		local rgb = " <RGB:0,1,0>"
		if self.chr:getPerkLevel(Perks.Electricity) < requiredSkillLevel then
			rgb = " <RGB:1,0,0>"
		end
		tooltip.description = tooltip.description .. rgb .. getText("IGUI_perks_Electricity") .. " " .. self.chr:getPerkLevel(Perks.Electricity) .. "/" .. requiredSkillLevel .. " <LINE>"
		rgb = " <RGB:0,1,0>"

        local screwdriverItem = self.chr:getInventory():getFirstTagRecurse("Screwdriver")
        local displayName = screwdriverItem and screwdriverItem:getDisplayName() or "Screwdriver"
		if not self.chr:getInventory():containsTag("Screwdriver") then
			tooltip.description = tooltip.description .. " <RGB:1,0,0>" .. displayName .. " 0/1 <LINE>"
		else
			tooltip.description = tooltip.description .. " <RGB:0,1,0>" .. displayName .. " 1/1 <LINE>"
		end

		for neededPart,numberNeeded in pairs(requiredParts) do

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
		ISTimedActionQueue.add(ELRTurnOffLightbar:new(playerObj, true, part:getVehicle():getId()))
	end

	-- Choose the item we’ll pass to the timed action: the screwdriver the player will actually use
	local screwdriver = playerObj:getInventory():getFirstTagRecurse("Screwdriver")

	-- Ensure it’s in inventory and equipped (equip action is harmless if already equipped)
	if screwdriver then
		ISVehiclePartMenu.toPlayerInventory(playerObj, screwdriver)
		if playerObj:getPrimaryHandItem() ~= screwdriver then
			ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, screwdriver, 50, true, false))
		end
	end

	ISTimedActionQueue.add(ELRRepairLightbar:new(playerObj, part, screwdriver, timeToRepair, repairBlocks, requiredParts, targetCondition))
end