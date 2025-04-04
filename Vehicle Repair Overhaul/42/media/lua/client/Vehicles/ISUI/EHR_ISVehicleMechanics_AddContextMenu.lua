require "Vehicles/ISUI/ISVehicleMechanics"

local old_ISVehicleMechanics_doPartContextMenu = ISVehicleMechanics.doPartContextMenu

-- Copied from ISUI/ISWorldObjectContextMenu for finding a blowtorch with enough propane and modified for desired uses
local function EHR_predicateBlowTorch(item)
    return (item ~= nil) and
            (item:hasTag("BlowTorch") or item:getType() == "BlowTorch") and
            (item:getCurrentUses() >= 10)
end
-- Used to find a blowtorch that is not empty
local function predicateNotEmptyBlowtorch(item)
    return (item ~= nil) and
            (item:hasTag("BlowTorch") or item:getType() == "BlowTorch") and
            (item:getCurrentUses() >= 10)
end

-- Used to find the drainable that has the most uses
local function predicateFullestDrainable(item1, item2)
	return item1:getDrainableUsesInt() - item2:getDrainableUsesInt()
end


function ISVehicleMechanics:doPartContextMenu(part, x,y)
	-- Everything needed to have a recipe to repair the vehicle GloveBox is in vanilla, but the vanilla vehicle templates don't 
	--   mark the GloveBox as repairable. The following lines will programatically mark a GloveBox as repairable in a non-permanent 
	--   way. This allows for GloveBoxes to be repaired successfully via the vanilla context menu call below. We turn this back off 
	--   when the part is fully repaired because the vanilla code doesn't stop you from repairing the glove box even though the 
	--   condition is at maximum.
	-- Note that for modded vehicles this requires that the mod uses the vanilla glove box inventory items in their vehicle scripts.
	local partInventoryItem = part:getInventoryItem()
	
	local currentCondition = part:getCondition()
	
	local fixingList = nil
	
	if partInventoryItem ~= nil then fixingList = FixingManager.getFixes(partInventoryItem) end
	
	if (part:getId() == "GloveBox" and fixingList ~= nil and not fixingList:isEmpty())then
		local repairMechanicIsOn = part:getScriptPart():isRepairMechanic()
		
		if not repairMechanicIsOn and currentCondition < 100 then
			part:getScriptPart():setRepairMechanic(true)
		elseif currentCondition >= 100 and repairMechanicIsOn then
			part:getScriptPart():setRepairMechanic(false)
		end
	end

	-- Call the old version of this function to handle other actions and items. Note that we must call this before we do our 
	--   code because the vanilla version of this function handles creating the context menu and has no code to handle the case 
	--   where we create the context menu instead. So it will always destroy our context menu and create a new one. So we 
	--   have the old version of this function create the context menu, and then we add to that.
	old_ISVehicleMechanics_doPartContextMenu(self, part, x, y)
	
	-- If the game is paused we should skip creating our context menu
	if UIManager.getSpeedControls():getCurrentGameSpeed() == 0 then return end
	
	-- It's most likely that the old version of this function has already created an instance of the context menu, but for robustness 
	--   we should check to ensure it exists, and if it doesn't we create a new one.
	local playerObj = getSpecificPlayer(self.playerNum)
	if not self.context then self.context = ISContextMenu.get(self.playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY()) end
	
	local option

	-- Add the option for repairing the heater to the context menu.

	if part:getId() == "Heater" then
		-- 
		local requiredMechanicsSkillLevel = 1
		local requiredMetalworkingSkillLevel = 2

		local requiredParts = { ["Base.SmallSheetMetal"] = 3 }

		local targetCondition = math.min(100, currentCondition + 34)
		
		local allPartsPresent = true
		
		for neededPart,numberNeeded in pairs(requiredParts) do
			if self.chr:getInventory():getNumberOfItem(neededPart, false, true) < numberNeeded then
				allPartsPresent = false
				break
			end
		end
		
		local blowtorch = nil
		
		local primaryHandItem = playerObj:getPrimaryHandItem()
		
		if primaryHandItem ~= nil and primaryHandItem:getType() == "Base.BlowTorch" and primaryHandItem:getCurrentUses() >= 10 then
			blowtorch = primaryHandItem
		else
			blowtorch = playerObj:getInventory():getFirstEvalRecurse(EHR_predicateBlowTorch)
			
			if blowtorch == nil then
				blowtorch = playerObj:getInventory():getBestEvalRecurse(predicateNotEmptyBlowtorch, predicateFullestDrainable)
			end
		end
		
		local mask = playerObj:getInventory():getFirstTagRecurse("WeldingMask")

		if currentCondition < 100 and allPartsPresent and self.chr:getPerkLevel(Perks.Mechanics) >= requiredMechanicsSkillLevel and self.chr:getPerkLevel(Perks.MetalWelding) >= requiredMetalworkingSkillLevel and blowtorch ~= nil and mask ~= nil then
			option = self.context:addOption(getText("ContextMenu_Repair"), playerObj, ISVehicleMechanics.EHR_onRepairHeater, part, requiredParts, blowtorch, mask, targetCondition, requiredMechanicsSkillLevel, requiredMetalworkingSkillLevel)
			self:EHR_doMenuTooltip(part, option, "EHR_repairheater", requiredParts, blowtorch, mask, requiredMechanicsSkillLevel, requiredMetalworkingSkillLevel, targetCondition)
		else
			option = self.context:addOption(getText("ContextMenu_Repair"), nil, nil)
			option.notAvailable = true
			self:EHR_doMenuTooltip(part, option, "EHR_repairheater", requiredParts, blowtorch, mask, requiredMechanicsSkillLevel, requiredMetalworkingSkillLevel, targetCondition)
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

function ISVehicleMechanics:EHR_doMenuTooltip(part, option, lua, requiredParts, blowtorch, mask, requiredMechanicsSkillLevel, requiredMetalworkingSkillLevel, targetCondition)
	local vehicle = part:getVehicle()
	local tooltip = ISToolTip:new()
	tooltip:initialise()
	tooltip:setVisible(false)
	tooltip.description = getText("Tooltip_craft_Needs") .. " : <LINE> <LINE>"
	option.toolTip = tooltip

	-- Repair heater tooltip
	if lua == "EHR_repairheater" then
		local rgb = " <RGB:0,1,0>"
		local addedTxt = ""
		
		if self.chr:getPerkLevel(Perks.Mechanics) < requiredMechanicsSkillLevel then
			rgb = " <RGB:1,0,0>"
		end
		tooltip.description = tooltip.description .. rgb .. getText("IGUI_perks_Mechanics") .. " " .. self.chr:getPerkLevel(Perks.Mechanics) .. "/" .. requiredMechanicsSkillLevel .. " <LINE>"
		rgb = " <RGB:0,1,0>"

		if self.chr:getPerkLevel(Perks.MetalWelding) < requiredMetalworkingSkillLevel then
			rgb = " <RGB:1,0,0>"
		end
		tooltip.description = tooltip.description .. rgb .. getText("IGUI_perks_MetalWelding") .. " " .. self.chr:getPerkLevel(Perks.MetalWelding) .. "/" .. requiredMetalworkingSkillLevel .. " <LINE>"
		rgb = " <RGB:0,1,0>"
		
		for neededPart,numberNeeded in pairs(requiredParts) do
			local scriptItem = ScriptManager.instance:getItem(neededPart)
			local displayName = scriptItem and getItemDisplayName(neededPart)
			local numberOfPart = self.chr:getInventory():getNumberOfItem(neededPart, false, true)

			if numberNeeded > 0 then
				if numberOfPart < numberNeeded then
					tooltip.description = tooltip.description .. " <RGB:1,0,0>" .. displayName .. " " .. numberOfPart .. "/" .. numberNeeded .. " <LINE>"
				else
					tooltip.description = tooltip.description .. " <RGB:0,1,0>" .. displayName .. " " .. numberOfPart .. "/" .. numberNeeded .. " <LINE>"
				end
			end
		end
	end

	local weldingmaskItem = self.chr:getInventory():getFirstTagRecurse("WeldingMask")
	local displayName = weldingmaskItem and weldingmaskItem:getDisplayName() or "Welding Mask"
	
	if not self.chr:getInventory():containsTag("WeldingMask") then
		tooltip.description = tooltip.description .. " <RGB:1,0,0>" .. displayName .. " 0/0 <LINE>"
	else
		tooltip.description = tooltip.description .. " <RGB:0,1,0>" .. displayName .. " 1/1 <LINE>"
	end
	
		local scriptItem = ScriptManager.instance:getItem("Base.BlowTorch")
        local displayName = scriptItem and getItemDisplayName("BlowTorch")
		
		if blowtorch == nil then
			tooltip.description = tooltip.description .. " <RGB:0,1,0>" .. displayName .. " 0/10 <LINE>"
		else
			local blowtorchUseLeft = blowtorch:getCurrentUses();
            if blowtorchUseLeft >= 10 then

			if blowtorchUseLeft < 10 then
				tooltip.description = tooltip.description .. " <RGB:1,0,0>" .. displayName .. " " .. blowtorchUseLeft .. "/10 <LINE>"
			else
				tooltip.description = tooltip.description .. " <RGB:0,1,0>" .. displayName .. " " .. blowtorchUseLeft .. "/10 <LINE>"
			end
		end
		
		if option.notAvailable then
			tooltip.description = tooltip.description .. " <LINE><RGB:1,0,0>" .. getText("Tooltip_EHR_NewCondition") .. ": " .. targetCondition .. "%"
		else
			tooltip.description = tooltip.description .. " <LINE><RGB:0,1,0>" .. getText("Tooltip_EHR_NewCondition") .. ": " .. targetCondition .. "%"
		end
	end
end

function ISVehicleMechanics.EHR_onRepairHeater(playerObj, part, requiredParts, blowtorch, mask, targetCondition, requiredMechanicsSkillLevel, requiredMetalworkingSkillLevel)
	if playerObj:getVehicle() then
		ISVehicleMenu.onExit(playerObj)
	end

	-- Have the character walk to the engine
	ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, part:getVehicle(), "Engine"))

	-- If the blowtorch to be used isn't equipped in the primary hand, then equip it
	if playerObj:getPrimaryHandItem() ~= blowtorch then
		ISVehiclePartMenu.toPlayerInventory(playerObj, blowtorch)
		ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, blowtorch, 50, true, false))
	end

	-- Have the character wear the welder mask
	if mask then
		ISInventoryPaneContextMenu.wearItem(mask, playerObj:getPlayerNum());
	end
	
	local timeToRepair = math.max(50, 170 - math.max(0, (10 * (playerObj:getPerkLevel(Perks.MetalWelding) - requiredMetalworkingSkillLevel))))
	
	-- Queue our custom TimedAction to repair the heater
	ISTimedActionQueue.add(EHRRepairHeater:new(playerObj, part, blowtorch, mask, timeToRepair, requiredParts, targetCondition))
end