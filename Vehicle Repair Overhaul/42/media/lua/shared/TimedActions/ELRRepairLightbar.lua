---@diagnostic disable: undefined-field, param-type-mismatch
--***********************************************************
--**                    Based on code by                   **
--**                                                       **
--**                    THE INDIE STONE                    **
--***********************************************************

require "TimedActions/ISBaseTimedAction"

ELRRepairLightbar = ISBaseTimedAction:derive("ELRRepairLightbar")

-- Face the part's actual world square (engine-resolved from the vehicle's
-- position and rotation) so the character turns toward the real part, not the
-- vehicle origin. Falls back to the part's area square, then the vehicle.
local function _faceRepairPart(self)
	local part = self.part
	local veh  = self.vehicle or (part and part.getVehicle and part:getVehicle()) or nil
	local sq   = part and part.getSquare and part:getSquare() or nil
	if sq and sq.getX then
		self.character:faceLocation(sq:getX() + 0.5, sq:getY() + 0.5)
		return
	end
	local area = part and part.getArea and part:getArea() or nil
	if area and area ~= "" and veh and veh.getSquareForArea then
		local ok, asq = pcall(function() return veh:getSquareForArea(area) end)
		if ok and asq and asq.getX then
			self.character:faceLocation(asq:getX() + 0.5, asq:getY() + 0.5)
			return
		end
	end
	if veh then self.character:faceThisObject(veh) end
end

function ELRRepairLightbar:isValid()
--	return self.vehicle:isInArea(self.part:getArea(), self.character)
	return true
end

function ELRRepairLightbar:waitToStart()
	_faceRepairPart(self)
	return self.character:shouldBeTurning()
end

function ELRRepairLightbar:update()
	_faceRepairPart(self)
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

	if self.setOverrideHandModels then
		self:setOverrideHandModels(self.item or self.character:getPrimaryHandItem(), nil)
		self._didOverride = true
	end
	self:setActionAnim("VehicleWorkOnMid")
end

function ELRRepairLightbar:stop()
	if self.item then self.item:setJobDelta(0) end
	if self._didOverride and self.setOverrideHandModels then
		self:setOverrideHandModels(nil, nil)
		self._didOverride = nil
	end
	ISBaseTimedAction.stop(self)
end

function ELRRepairLightbar:perform()
	if self.item then
		self.item:setJobDelta(0)
	end
	if self._didOverride and self.setOverrideHandModels then
		self:setOverrideHandModels(nil, nil)
		self._didOverride = nil
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

	o.jobType = getText("ContextMenu_Repair")..' '..getText("IGUI_VehiclePartlightbar")
	return o
end