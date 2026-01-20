require "Vehicles/ISUI/ISVehicleMechanics"
local VRO = require "VRO/Core"
pcall(require, "VRO/VRO_Sandbox")
pcall(require, "VRO_Sandbox")

local function VRO_IsEngineRebuildEnabled()
  if VRO and VRO.IsEngineRebuildEnabled then
    return VRO.IsEngineRebuildEnabled()
  end
  local sv = SandboxVars
  if not sv then return false end
  return
    (sv.VRO_IsEngineRebuildEnabled == true)
    or (sv.VRO and sv.VRO.IsEngineRebuildEnabled == true)
    or (sv.VRO_EnableEngineRebuild == true)
    or (sv.VRO and sv.VRO.EnableEngineRebuild == true)
end

local old_ISVehicleMechanics_doPartContextMenu = ISVehicleMechanics.doPartContextMenu
	local function _getEquippedOrAnyWrenchLike(chr)
	if not chr then return nil end

	local function isMatch(it)
		if not it then return false end
		local ft = it.getFullType and it:getFullType() or ""
		return ft == "Base.Wrench" or ft == "Base.Ratchet"
	end

	-- Check hands first (fast path)
	local pri = chr:getPrimaryHandItem()
	if isMatch(pri) then return pri end
	local sec = chr:getSecondaryHandItem()
	if isMatch(sec) then return sec end

	-- Then search all containers (backpacks, etc.)
	local inv = chr:getInventory()
	if not inv then return nil end
	if inv.getFirstTypeRecurse then
		local it = inv:getFirstTypeRecurse("Base.Wrench")
		if it then return it end
		it = inv:getFirstTypeRecurse("Base.Ratchet")
		if it then return it end
	end
		return nil
	end

function ISVehicleMechanics:doPartContextMenu(part, x,y)
	if UIManager.getSpeedControls():getCurrentGameSpeed() == 0 then return; end

	local playerObj = getSpecificPlayer(self.playerNum);
	local option;

	-- Call the old version of this function to handle all other parts and actions
	old_ISVehicleMechanics_doPartContextMenu(self, part, x, y);


	-- Add the option for rebuilding the engine to the context menu if all of the conditions are met

	-- Conditions:
	--   1. The vehicle part we are looking at is the Engine
	--   2. We either have the vehicle key or it is not required to access the engine
	--   3. The Engine Quality is not already 100
	--   4. The Engine Condition is over 90%
	--   5. We have the required number of Spare Engine Parts, which is equal to 5 times the 
	--         Mechanics skill level required to work on this vehicle's engine (will vary 
	--         based on vehicle type as defined by the engineRepairLevel value)
	--   6. The player's Mechanics skill level is currently higher than the skill level required to 
	--         perform mechanics actions on the vehicle's engine (engineRepairLevel value)
	--   7. The player currently has a wrench

	if not VRO_IsEngineRebuildEnabled() then return end
	if part:getId() == "Engine" and not VehicleUtils.RequiredKeyNotFound(part, self.chr) then
		if part:getVehicle():getEngineQuality() < 100 then
			-- Get the Mechanics skill level that is required to perform engine repair actions on this vehicle type
			local engineRepairLevel = part:getVehicle():getScript():getEngineRepairLevel();

			-- Calculate the number of Spare Engine Parts required to perform our action of rebuilding the engine
			local requiredEngineParts = engineRepairLevel * 5;

			if part:getCondition() >= 90 and self.chr:getInventory():getNumberOfItem("EngineParts", false, true) >= requiredEngineParts and self.chr:getPerkLevel(Perks.Mechanics) >= engineRepairLevel and (_getEquippedOrAnyWrenchLike(self.chr) ~= nil) then
				option = self.context:addOption(getText("IGUI_EER_RebuildEngine"), playerObj, ISVehicleMechanics.EER_onRebuildEngine, part);
				self:EER_doMenuTooltip(part, option, "EER_rebuildengine");
			else
				option = self.context:addOption(getText("IGUI_EER_RebuildEngine"), nil, nil);
				self:EER_doMenuTooltip(part, option, "EER_rebuildengine");
				option.notAvailable = true;
			end
		end
	end
end

function ISVehicleMechanics:EER_doMenuTooltip(part, option, lua, name)
	local vehicle = part:getVehicle();
	local tooltip = ISToolTip:new();
	tooltip:initialise();
	tooltip:setVisible(false);
	tooltip.description = getText("Tooltip_craft_Needs") .. ": <LINE>";
	option.toolTip = tooltip;
	local keyvalues = part:getTable(lua);

	-- Get the Mechanics skill level that is required to perform engine repair actions on this vehicle type
	local engineRepairLevel = part:getVehicle():getScript():getEngineRepairLevel();

	-- Calculate the number of Spare Engine Parts required to perform our action of rebuilding the engine
	local requiredEngineParts = engineRepairLevel * 5;

	-- Rebuild engines tooltip
	if lua == "EER_rebuildengine" then
		local rgb = " <RGB:0,1,0>";
		local addedTxt = "";

		if part:getCondition() < 90 then
			rgb = " <RGB:1,0,0>";
			addedTxt = "/90%";
			tooltip.description = tooltip.description .. rgb .. " " .. getText("Tooltip_Vehicle_EngineCondition", part:getCondition() .. addedTxt) .. " <LINE>";
		end

		rgb = " <RGB:0,1,0>";
		if self.chr:getPerkLevel(Perks.Mechanics) < engineRepairLevel then
			rgb = " <RGB:1,0,0>";
		end
		tooltip.description = tooltip.description .. rgb .. getText("IGUI_perks_Mechanics") .. " " .. self.chr:getPerkLevel(Perks.Mechanics) .. "/" .. engineRepairLevel .. " <LINE>";
		rgb = " <RGB:0,1,0>";
		local hasWrenchLike = _getEquippedOrAnyWrenchLike(self.chr) ~= nil
		local wrenchName   = ScriptManager.instance:getItem("Base.Wrench"):getDisplayName()
		local ratchetName  = ScriptManager.instance:getItem("Base.Ratchet") and ScriptManager.instance:getItem("Base.Ratchet"):getDisplayName() or "Ratchet"
		local label = string.format("%s / %s", wrenchName, ratchetName)

		if hasWrenchLike then
		tooltip.description = tooltip.description .. " <RGB:0,1,0>" .. label .. " 1/1 <LINE>"
		else
		tooltip.description = tooltip.description .. " <RGB:1,0,0>" .. label .. " 0/1 <LINE>"
		end

		local item = ScriptManager.instance:getItem("Base.EngineParts");
		local numberOfEngineParts = self.chr:getInventory():getNumberOfItem("EngineParts", false, true);

		if numberOfEngineParts < requiredEngineParts then
			tooltip.description = tooltip.description .. " <RGB:1,0,0>" .. item:getDisplayName() .. " " .. numberOfEngineParts .. "/" .. requiredEngineParts .. " <LINE>";
		else
			tooltip.description = tooltip.description .. " <RGB:0,1,0>" .. item:getDisplayName() .. " " .. numberOfEngineParts .. "/" .. requiredEngineParts .. " <LINE>";
			tooltip.description = tooltip.description .. " <RGB:0,1,0> " .. " <LINE>" .. getText("Tooltip_eer_RebuildEngine");
		end
	end

	-- do you need the key to operate
	if VehicleUtils.RequiredKeyNotFound(part, self.chr) then
		tooltip.description = tooltip.description .. " <RGB:1,0,0> " .. getText("Tooltip_vehicle_keyRequired") .. " <LINE>";
	end
end

function ISVehicleMechanics.EER_onRebuildEngine(playerObj, part)
	if not VRO.IsEngineRebuildEnabled() then return end
	if playerObj:getVehicle() then
		ISVehicleMenu.onExit(playerObj)
	end

	local item = _getEquippedOrAnyWrenchLike(playerObj)
	if not item then return end
	ISVehiclePartMenu.toPlayerInventory(playerObj, item)

	ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, part:getVehicle(), part:getArea()))

	local engineCover = nil
	local doorPart = part:getVehicle():getPartById("EngineDoor")
	if doorPart and doorPart:getDoor() and doorPart:getInventoryItem() and not doorPart:getDoor():isOpen() then
		engineCover = doorPart
	end

	local time = (part:getVehicle():getScript():getEngineRepairLevel() * 200) - math.max(0, (50 * (playerObj:getPerkLevel(Perks.Mechanics) - part:getVehicle():getScript():getEngineRepairLevel())));
	if engineCover then
		-- The hood is magically unlocked if any door/window is broken/open/uninstalled.
		-- If the player can get in the vehicle, they can pop the hood, no key required.
		if engineCover:getDoor():isLocked() and VehicleUtils.RequiredKeyNotFound(engineCover, playerObj) then
			ISTimedActionQueue.add(ISUnlockVehicleDoor:new(playerObj, engineCover))
		end
		ISTimedActionQueue.add(ISOpenVehicleDoor:new(playerObj, part:getVehicle(), engineCover))

		-- Queue our custom TimedAction to perform the task of rebuilding the engine
		ISTimedActionQueue.add(ISRebuildEngine:new(playerObj, part, item, time))

		ISTimedActionQueue.add(ISCloseVehicleDoor:new(playerObj, part:getVehicle(), engineCover))
	else
		-- Queue our custom TimedAction to perform the task of rebuilding the engine
		ISTimedActionQueue.add(ISRebuildEngine:new(playerObj, part, item, time))
	end
end