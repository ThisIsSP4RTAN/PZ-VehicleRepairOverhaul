---@diagnostic disable: undefined-field, param-type-mismatch
--***********************************************************
--**                    Based on code by                   **
--**                                                       **
--**                    THE INDIE STONE                    **
--***********************************************************

require "TimedActions/ISBaseTimedAction"
require "VRO/VRO_Sandbox"

ISRebuildEngine = ISBaseTimedAction:derive("ISRebuildEngine")

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

function ISRebuildEngine:isValid()
--	return self.vehicle:isInArea(self.part:getArea(), self.character)
	return true;
end

function ISRebuildEngine:waitToStart()
	_faceRepairPart(self)
	return self.character:shouldBeTurning()
end

function ISRebuildEngine:update()
	_faceRepairPart(self)
	self.item:setJobDelta(self:getJobDelta())

    self.character:setMetabolicTarget(Metabolics.MediumWork);
end

function ISRebuildEngine:start()
	if VRO and VRO.IsEngineRebuildEnabled and not VRO.IsEngineRebuildEnabled() then return end
	self.item:setJobType(getText("IGUI_EER_RebuildEngine"))

	if self.setOverrideHandModels then
		self:setOverrideHandModels(self.item or self.character:getPrimaryHandItem(), nil)
		self._didOverride = true
	end
	self:setActionAnim("VehicleWorkOnMid")
end

function ISRebuildEngine:stop()
	if self.item then self.item:setJobDelta(0) end
	if self._didOverride and self.setOverrideHandModels then
		self:setOverrideHandModels(nil, nil)
		self._didOverride = nil
	end
	ISBaseTimedAction.stop(self)
end

function ISRebuildEngine:perform()
    ISBaseTimedAction.perform(self)
    if self.item then self.item:setJobDelta(0) end
    if self._didOverride and self.setOverrideHandModels then
        self:setOverrideHandModels(nil, nil)
        self._didOverride = nil
    end

    local engineRepairLevel   = self.vehicle:getScript():getEngineRepairLevel()
    local requiredEngineParts = engineRepairLevel * 5

    -- Show the repair immediately (SP responsiveness)
    self.part:setCondition(100.0)

    -- Vanilla repairPart (keeps vanilla sync happy)
    sendClientCommand(self.character, "vehicle", "repairPart", {
        vehicle = self.part:getVehicle():getId(),
        part    = self.part:getId(),
    })

    -- Our server command (quality + consume EngineParts + sync)
    sendClientCommand(self.character, "EER_vehicle", "rebuildEngine", {
        vehicleId     = self.vehicle:getId(),
        targetQuality = 100,
        consumeParts  = requiredEngineParts,
    })
end

function ISRebuildEngine:new(character, part, item, time)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.character = character
	o.vehicle = part:getVehicle()
	o.part = part
	o.item = item
	o.maxTime = time
	o.jobType = getText("IGUI_EER_RebuildEngine")
	return o
end