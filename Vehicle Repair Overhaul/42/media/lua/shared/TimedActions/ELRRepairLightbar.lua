---@diagnostic disable: undefined-field, param-type-mismatch
--***********************************************************
--**                    Based on code by                   **
--**                                                       **
--**                    THE INDIE STONE                    **
--***********************************************************

require "TimedActions/ISBaseTimedAction"

ELRRepairLightbar = ISBaseTimedAction:derive("ELRRepairLightbar")

function ELRRepairLightbar:isValid()
--	return self.vehicle:isInArea(self.part:getArea(), self.character)
	return true
end

function ELRRepairLightbar:waitToStart()
	self.character:faceThisObject(self.vehicle)
	return self.character:shouldBeTurning()
end

function ELRRepairLightbar:update()
	self.character:faceThisObject(self.vehicle)
	self.item:setJobDelta(self:getJobDelta())

    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function ELRRepairLightbar:start()
	-- Fallback if caller didn’t pass an item
	if not self.item then
		self.item = self.character:getPrimaryHandItem()
	end
	if self.item then
		self.item:setJobType(self.jobType)
	end

	-- Todo? - Find a better animation for working on a raised object
	self:setOverrideHandModels(self.character:getPrimaryHandItem(), nil)
	self:setActionAnim("VehicleWorkOnMid")
end

function ELRRepairLightbar:stop()
	self.item:setJobDelta(0)
	ISBaseTimedAction.stop(self)
end

function ELRRepairLightbar:perform()
	if self.item then
		self.item:setJobDelta(0)
	end

	local args = {
		vehicle         = self.part:getVehicle():getId(),
		part            = self.part:getId(),
		repairBlocks    = self.repairBlocks,
		targetCondition = self.targetCondition,
		repairParts     = {}
	}

	for k, v in pairs(self.requiredParts or {}) do
		local ft = tostring(k)
		if not ft:find("%.") then ft = "Base." .. ft end
		args.repairParts[ft] = (args.repairParts[ft] or 0) + (tonumber(v) or 0)
	end
	sendClientCommand(self.character, 'ELR_vehicle', 'repairLightbar', args)

	-- Do NOT consume locally; server removes items authoritatively.
	ISBaseTimedAction.perform(self)
end

function ELRRepairLightbar:new(character, part, item, timeToRepair, repairBlocks, requiredParts, targetCondition)
	local o = {}
	setmetatable(o, self)
	self.__index = self

	o.character       = character
	o.vehicle         = part:getVehicle()
	o.part            = part
	o.item            = item or (character and character:getPrimaryHandItem() or nil)
	o.maxTime         = timeToRepair

	o.repairBlocks    = repairBlocks
	o.requiredParts   = requiredParts
	o.targetCondition = targetCondition

	o.jobType = getText("ContextMenu_Repair")..''..getText("IGUI_VehiclePartlightbar")
	return o
end