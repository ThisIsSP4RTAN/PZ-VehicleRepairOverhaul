---@diagnostic disable: undefined-field, param-type-mismatch
--***********************************************************
--**                    Based on code by                   **
--**                                                       **
--**                    THE INDIE STONE                    **
--***********************************************************

require "TimedActions/ISBaseTimedAction"

EHRRepairHeater = ISBaseTimedAction:derive("EHRRepairHeater")

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

function EHRRepairHeater:isValid()
	if not self.character:hasEquipped("BlowTorch") or self.vehicle == nil then
		return false
	end

	return true
end

function EHRRepairHeater:waitToStart()
	_faceRepairPart(self)
	return self.character:shouldBeTurning()
end

function EHRRepairHeater:update()
	_faceRepairPart(self)
	self.blowtorch:setJobDelta(self:getJobDelta())

    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function EHRRepairHeater:start()
	-- Set the progress bar text on the equipped blowtorch in the inventory menu to be the job description
	self.blowtorch:setJobType(self.jobType)

	-- Play the character animation of using the blowtorch
	self:setActionAnim("BlowTorchMid")
	if self.setOverrideHandModels then
		self:setOverrideHandModels(self.blowtorch or self.character:getPrimaryHandItem(), nil)
		self._didOverride = true
	end

	-- Play the sound of using the blowtorch and make it audible in the world so zombies can react to it
	-- Store the reference to the sound so we can stop it once the action is done
	self.sound = self.character:getEmitter():playSound("BlowTorch")
	local radius = 20 * self.character:getWeldingSoundMod()
	addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), radius, radius)
end

function EHRRepairHeater:stop()
	self.blowtorch:setJobDelta(0)

	-- Stop the sound of the blowtorch once the action is complete
	if self.sound then
		self.character:getEmitter():stopSound(self.sound)
		self.sound = nil
	end
	if self._didOverride and self.setOverrideHandModels then
		self:setOverrideHandModels(nil, nil)
		self._didOverride = nil
	end
    ISBaseTimedAction.stop(self);
end

function EHRRepairHeater:perform()
    -- Stop the sound of the blowtorch once the action is complete
    if self.sound then
        self.character:getEmitter():stopSound(self.sound)
        self.sound = nil
    end
	self.blowtorch:setJobDelta(0)
	if self._didOverride and self.setOverrideHandModels then
		self:setOverrideHandModels(nil, nil)
		self._didOverride = nil
	end

	local args = {
		vehicle         = self.part:getVehicle():getId(),
		part            = self.part:getId(),
		targetCondition = self.targetCondition,
		repairParts     = {}
	}

	for k, v in pairs(self.requiredParts or {}) do
		local full = tostring(k)
		if not full:find("%.") then full = "Base." .. full end
		args.repairParts[full] = (args.repairParts[full] or 0) + (tonumber(v) or 0)
	end
	sendClientCommand(self.character, 'EHR_vehicle', 'repairHeater', args)

	ISBaseTimedAction.perform(self)
end

function EHRRepairHeater:new(character, part, blowtorch, mask, timeToRepair, requiredParts, targetCondition)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.character = character
	o.vehicle = part:getVehicle()
	o.part = part
	o.blowtorch = blowtorch
	o.mask = mask

	o.maxTime = timeToRepair

--[[	
	if character:HasTrait("Handy") then
		o.maxTime = timeToRepair - 20;
    end
--]]

	if character:isTimedActionInstant() then
        o.maxTime = 1;
    end

	o.requiredParts = requiredParts
	o.targetCondition = targetCondition
	o.stopOnWalk = true;
	o.stopOnRun = true;
	o.sound = nil

	o.jobType = getText("ContextMenu_Repair")..' '..getText("IGUI_VehiclePartHeater")
	return o
end