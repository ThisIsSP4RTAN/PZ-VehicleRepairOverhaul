---@diagnostic disable: undefined-field, param-type-mismatch, redundant-parameter
require "TimedActions/ISBaseTimedAction"
local VRO = require "VRO/Core"

----------------------------------------------------------------
-- Minimal helpers the action relies on
----------------------------------------------------------------
local function isDrainable(it) return it and instanceof(it, "DrainableComboItem") end

local function drainableUses(it)
  if not it then return 0 end
  if isDrainable(it) then
    if it.getDrainableUsesInt then return it:getDrainableUsesInt() end
    if it.getCurrentUses then return it:getCurrentUses() end
    if it.getUsedDelta and it.getUseDelta then
      local used, step = it:getUsedDelta(), it:getUseDelta()
      if step and step > 0 then return math.max(0, math.floor((1.0 - used) / step + 0.0001)) end
    end
    return 0
  end
  return 1
end

local function isTorchItem(it)
  if not it then return false end

  -- 42.13+ :hasTag expects an ItemTag; try it safely if registry is present
  if it.hasTag and ItemTag and (ResourceLocation and (ResourceLocation.of or ResourceLocation.new)) then
    local rl = ResourceLocation.of and ResourceLocation.of("base:BlowTorch")
             or (ResourceLocation.new and ResourceLocation.new("base","BlowTorch"))
    if rl then
      local ok, tag = pcall(function() return ItemTag.get(rl) end)
      if ok and tag and it:hasTag(tag) then return true end
    end
  end

  -- Fallbacks that also work on older builds
  local t  = it.getType     and it:getType()     or ""
  local ft = it.getFullType and it:getFullType() or ""
  return t == "BlowTorch" or ft == "Base.BlowTorch"
end

local function defaultAnimForPart(part)
  if not part then return "VehicleWorkOnMid" end
  if part.getWheelIndex and part:getWheelIndex() ~= -1 then return "VehicleWorkOnTire" end
  local id = tostring(part.getId and part:getId() or "")
  if string.find(id, "Brake", 1, true) then return "VehicleWorkOnTire" end
  return "VehicleWorkOnMid"
end

-- Build a job label like: "Repair Car Seat"
local function buildJobType(part, brokenItem)
  local label = getText("ContextMenu_Repair")
  local name
  if brokenItem and brokenItem.getDisplayName then
    name = brokenItem:getDisplayName()
  elseif part and part.getInventoryItem and part:getInventoryItem() then
    local inv = part:getInventoryItem()
    if inv and inv.getDisplayName then name = inv:getDisplayName() end
  end
  if name and name ~= "" then
    return label .. " " .. name
  end
  return label
end

-- Turn a bundle list into fullType->count, counting uses for drainables.
local function _bundleToTypeCounts(bundle)
  local out = {}
  if not (bundle and bundle[1] ~= nil) then return out end
  for i = 1, #bundle do
    local b = bundle[i]
    if b and b.item and (b.takeUses or 0) > 0 then
      local it = b.item
      local ft = (it.getFullType and it:getFullType())
              or (it.getType and ("Base."..it:getType()))
      if ft then
        local add = 1
        if isDrainable and isDrainable(it) then
          add = b.takeUses or 0
        end
        out[ft] = (out[ft] or 0) + add
      end
    end
  end
  return out
end

local function _mergeCounts(a, b)
  local out = {}
  for k,v in pairs(a or {}) do out[k] = (out[k] or 0) + (v or 0) end
  for k,v in pairs(b or {}) do out[k] = (out[k] or 0) + (v or 0) end
  return out
end

-- Gather keep-flag targets so the server can apply degrade/sharpness checks.
-- We hint which exact item to pick (hands) and fallback to fullType if needed.
local function _packKeepFlags(self, list)
  local out = {}
  if not (list and list[1] ~= nil) then return out end
  for i = 1, #list do
    local k = list[i]
    if k and k.item and k.flags then
      local it = k.item
      local ft = (it.getFullType and it:getFullType()) or (it.getType and ("Base."..it:getType()))
      out[#out+1] = {
        fullType    = ft,
        inPrimary   = (self.expectedPrimary   == it) or (self.character:getPrimaryHandItem()   == it),
        inSecondary = (self.expectedSecondary == it) or (self.character:getSecondaryHandItem() == it),
        flags       = k.flags,
      }
    end
  end
  return out
end

----------------------------------------------------------------
-- Progress helpers: show bars on every used item
----------------------------------------------------------------
-- Progress helpers: show bars on the EXACT items we actually use/keep
local function collectProgressItems(self)
  local list, seen = {}, {}
  local function add(it)
    if it and it.setJobDelta and not seen[it] then
      seen[it] = true
      list[#list + 1] = it
    end
  end

  local function addBundle(bundle)
    if not (bundle and bundle[1] ~= nil) then return end
    for i = 1, #bundle do
      local b = bundle[i]
      if b then add(b.item) end
    end
  end

  -- Consumed stuff
  addBundle(self.fixerBundle)
  addBundle(self.globalBundle)

  -- Not-consumed items we explicitly chose for flags/damage (globals keep + equip keep)
  local keep = self.keepFlagTargets
  if keep and keep[1] ~= nil then
    for i = 1, #keep do
      local k = keep[i]
      if k then add(k.item) end
    end
  end

  -- Hands we told the TA to show (in case they weren’t in keepFlagTargets)
  add(self.expectedPrimary)
  add(self.expectedSecondary)

  -- The loose broken item (inventory repair)
  add(self.brokenItem)

  return list
end

-- Sum total available "uses" for a fullType (counts stacks and drainables)
local function _countUsesForFullType(inv, fullType)
  if not (inv and fullType) then return 0 end
  local bagged = ArrayList.new()
  inv:getAllTypeRecurse(fullType, bagged)
  if bagged:isEmpty() then return 0 end
  local have = 0
  for i = 0, bagged:size() - 1 do
    local it = bagged:get(i)
    if isDrainable(it) then
      have = have + drainableUses(it)
    else
      have = have + 1
    end
  end
  return have
end

-- How many torch uses do we require? (derive from the bundles we planned)
local function _calcTorchUsesFromBundles(self)
  local function from(bundle)
    local tot = 0
    if not (bundle and bundle[1] ~= nil) then return 0 end
    for i = 1, #bundle do
      local b = bundle[i]
      if b and b.item and isTorchItem(b.item) then
        tot = tot + (b.takeUses or 0)
      end
    end
    return tot
  end
  return from(self.globalBundle) + from(self.fixerBundle)
end

-- Do we currently have a single blowtorch with >= need uses?
local function _hasTorchWithUses(inv, need)
  if (need or 0) <= 0 then return true end
  if not inv then return false end

  -- Prefer a safe predicate search (works across nested containers).
  if inv.getFirstEvalRecurse then
    local function pred(it)
      return isTorchItem(it) and (drainableUses(it) >= need)
    end
    local found = inv:getFirstEvalRecurse(pred)
    return found ~= nil
  end

  if inv.getItems then
    local items = inv:getItems()
    if items and items.size then
      for i = 0, items:size() - 1 do
        local it = items:get(i)
        if isTorchItem(it) and (drainableUses(it) >= need) then
          return true
        end
      end
    end
  end
  return false
end

-- Rebuild the consume map from our planned bundles and check availability NOW.
-- Returns true when everything needed still exists in the player's inventory.
local function _hasEnoughNow(self)
  local inv = self.character and self.character:getInventory()
  if not inv then return false end

  -- What we originally planned to consume (computed exactly like perform())
  local c1 = _bundleToTypeCounts(self.fixerBundle)
  local c2 = _bundleToTypeCounts(self.globalBundle)
  local needMap = _mergeCounts(c1, c2)

  -- Torch requirement (single-torch rule comes ONLY from the bundles)
  local torchNeed = tonumber(self.torchUses) or _calcTorchUsesFromBundles(self)
  if torchNeed > 0 and not _hasTorchWithUses(inv, torchNeed) then
    return false
  end

  -- Non-torch consumables: fullType → uses/count
  for fullType, need in pairs(needMap) do
    if fullType ~= "Base.BlowTorch" then
      local have = _countUsesForFullType(inv, fullType)
      if have < (need or 0) then
        return false
      end
    end
  end
  return true
end

----------------------------------------------------------------
-- Timed Action (shared)
----------------------------------------------------------------
VRO.DoFixAction = ISBaseTimedAction:derive("VRO_DoFixAction")

-- Face the specific repair area (e.g. the corner a tire sits on) rather than
-- the vehicle origin, so the character visibly turns toward the part. Prefers
-- the area we walked to (repairArea), falls back to the part's own area, then
-- to facing the vehicle as a whole.
local function _faceRepairArea(self)
  local veh = self.part and self.part:getVehicle()
  if not veh then return end

  -- The part's own world square is resolved by the engine from the vehicle's
  -- position AND rotation, so facing its tile centre points at the real part
  -- regardless of which way the vehicle is parked.
  local sq = self.part.getSquare and self.part:getSquare() or nil
  if sq and sq.getX then
    self.character:faceLocation(sq:getX() + 0.5, sq:getY() + 0.5)
    return
  end

  -- Fallback: the repair area's world square (also engine-resolved). Prefer the
  -- area we walked to (overrides included), else the part's declared area.
  local area = self.repairArea
  if (not area or area == "") and self.part.getArea then area = self.part:getArea() end
  if area and area ~= "" and veh.getSquareForArea then
    local ok, asq = pcall(function() return veh:getSquareForArea(area) end)
    if ok and asq and asq.getX then
      self.character:faceLocation(asq:getX() + 0.5, asq:getY() + 0.5)
      return
    end
  end

  -- Last resort: face the vehicle as a whole.
  self.character:faceThisObject(veh)
end

function VRO.DoFixAction:isValid()
  if self.part and self.part:getVehicle() then
    return _hasEnoughNow(self)
  end
  if self.brokenItem then
    return _hasEnoughNow(self)
  end
  return false
end

function VRO.DoFixAction:waitToStart()
  _faceRepairArea(self)
  return self.character:shouldBeTurning()
end

function VRO.DoFixAction:update()
  _faceRepairArea(self)

  if not _hasEnoughNow(self) then
    self:forceStop()
    return
  end

  -- Drive all progress bars
  local items = self._progressItems
  if items and items[1] ~= nil then
    local jd = self:getJobDelta()
    for i = 1, #items do
      local it = items[i]
      if it and it.setJobDelta then it:setJobDelta(jd) end
    end
  end

  if self.setMetabolicTarget then
    self.character:setMetabolicTarget(Metabolics.UsingTools)
  end
end

function VRO.DoFixAction:start()
  local anim = self.actionAnim or defaultAnimForPart(self.part)
  if anim and self.setActionAnim then self:setActionAnim(anim) end
    if not _hasEnoughNow(self) then
    self:forceStop()
    return
  end

  if self.setOverrideHandModels then
    if self.showModel ~= false then
      local p = self.expectedPrimary   or self.character:getPrimaryHandItem()
      local s = self.expectedSecondary or self.character:getSecondaryHandItem()
      self:setOverrideHandModels(p, s)
    else
      self:setOverrideHandModels(nil, nil)
    end
    self._didOverride = true
  end

  -- Set up all items to show progress bars + text
  self._progressItems = collectProgressItems(self)
  local job = self.jobType or buildJobType(self.part, self.brokenItem)
  local list = self._progressItems
  if list and list[1] ~= nil then
    for i = 1, #list do
      local it = list[i]
      if it then
        if it.setJobType  then it:setJobType(job) end
        if it.setJobDelta then it:setJobDelta(0)  end
      end
    end
  end

  if self.fxSound then
    self._soundHandle = self.character:getEmitter():playSound(self.fxSound)
  end

  if self.fxSound and (self.fxSound ~= "Sewing") then
    local radius = 12
    if self.fxSound == "BlowTorch" and self.character.getWeldingSoundMod then
      radius = 20 * self.character:getWeldingSoundMod()
    end
    addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), radius, radius)
  end
end

function VRO.DoFixAction:stop()
  local items = self._progressItems
  if items and items[1] ~= nil then
    for i = 1, #items do
      local it = items[i]
      if it and it.setJobDelta then it:setJobDelta(0) end
    end
  end

  if self._soundHandle then
    self.character:getEmitter():stopSound(self._soundHandle)
    self._soundHandle = nil
  end
  if self._didOverride and self.setOverrideHandModels then
    self:setOverrideHandModels(nil, nil)
    self._didOverride = nil
  end
  ISBaseTimedAction.stop(self)
end

function VRO.DoFixAction:perform()
  -- CLIENT: stop bars/sounds/models (no mutations)
  if self._progressItems and self._progressItems[1] ~= nil then
    for i = 1, #self._progressItems do
      local it = self._progressItems[i]
      if it and it.setJobDelta then it:setJobDelta(0) end
    end
  end

  if self._soundHandle then
    self.character:getEmitter():stopSound(self._soundHandle)
    self._soundHandle = nil
  end

  if self.successSfx then
    self.character:getEmitter():playSound(self.successSfx)
  end

  if self._didOverride and self.setOverrideHandModels then
    self:setOverrideHandModels(nil, nil)
    self._didOverride = nil
  end

  local veh = self.part and self.part:getVehicle() or nil

  if veh and self.part then
    -- ===== Vehicle part → server does the mutation =====
    if not _hasEnoughNow(self) then
      ISBaseTimedAction.perform(self); return
    end

    local args = {}

    args.vehicleId  = veh:getId()
    args.partId     = self.part:getId()

    -- HBR (seed) – the server re-reads this from the item and increments after success
    do
      local inv = self.part.getInventoryItem and self.part:getInventoryItem() or nil
      if inv and inv.getHaveBeenRepaired then
        args.hbr = inv:getHaveBeenRepaired() or 0
      else
        local md = self.part:getModData()
        args.hbr = (md and md.VRO_HaveBeenRepaired) or 0
      end
    end

    args.fixerIndex    = self.fixerIndex or 1
    args.fixingCondMod = (self.fixing and self.fixing.conditionModifier) or 1.0
    args.fixerSkills   = (self.fixer and self.fixer.skills) or (self.fixing and self.fixing.skills) or nil

    -- Torch info: only drain chosen torch on server; never delete when empty
    args.torchUses        = tonumber(self.torchUses) or 0
    local inPrimaryTorch  = (self.expectedPrimary and isTorchItem(self.expectedPrimary)) and true or false
    args.torchFromPrimary = inPrimaryTorch

    -- Aggregate non-torch consumables by fullType → required "uses" or count
    local c1 = _bundleToTypeCounts(self.fixerBundle)
    local c2 = _bundleToTypeCounts(self.globalBundle)
    args.consumeMap = _mergeCounts(c1, c2)

    args.keepFlags = _packKeepFlags(self, self.keepFlagTargets)
    sendClientCommand(self.character, 'VRO_vehicle', 'doFix', args)
    else
      -- ===== Loose inventory item → server does the mutation now =====
      if not _hasEnoughNow(self) then
        ISBaseTimedAction.perform(self); return
      end

      local args = {}
      local bi   = self.brokenItem
      if not bi or not bi.getFullType then
        ISBaseTimedAction.perform(self); return
      end

      args.itemFullType = bi:getFullType()
      if bi.getID then args.itemId = bi:getID() end

      -- HBR seed from item if available
      if bi.getHaveBeenRepaired then
        args.hbr = bi:getHaveBeenRepaired() or 0
      else
        local md = bi:getModData()
        args.hbr = (md and md.VRO_HaveBeenRepaired) or 0
      end

      args.fixerIndex    = self.fixerIndex or 1
      args.fixingCondMod = (self.fixing and self.fixing.conditionModifier) or 1.0
      args.fixerSkills   = (self.fixer and self.fixer.skills) or (self.fixing and self.fixing.skills) or nil

      -- Torch info
      args.torchUses        = tonumber(self.torchUses) or 0
      local inPrimaryTorch  = (self.expectedPrimary and isTorchItem(self.expectedPrimary)) and true or false
      args.torchFromPrimary = inPrimaryTorch

      -- Aggregate the consumables we planned to consume
      local c1 = _bundleToTypeCounts(self.fixerBundle)
      local c2 = _bundleToTypeCounts(self.globalBundle)
      args.consumeMap = _mergeCounts(c1, c2)
      args.keepFlags = _packKeepFlags(self, self.keepFlagTargets)

      sendClientCommand(self.character, 'VRO_vehicle', 'doFixInventory', args)
    end

  ISBaseTimedAction.perform(self)
end

function VRO.DoFixAction:new(args)
  local o = ISBaseTimedAction.new(self, args.character)
  o.stopOnWalk        = true
  o.stopOnRun         = true
  o.character         = args.character
  o.part              = args.part
  o.repairArea        = args.repairArea
  o.fixing            = args.fixing
  o.fixer             = args.fixer
  o.fixerIndex        = args.fixerIndex or 1
  o.brokenItem        = args.brokenItem
  o.fixerBundle       = args.fixerBundle
  o.globalBundle      = args.globalBundle
  o.maxTime           = args.time or 150
  o.actionAnim        = args.anim
  o.fxSound           = args.sfx
  o.successSfx        = args.successSfx
  o.showModel         = (args.showModel ~= false)
  o.expectedPrimary   = args.expectedPrimary
  o.expectedSecondary = args.expectedSecondary
  o.torchUses         = tonumber(args.torchUses) or 0
  o.caloriesModifier  = 4
  o.jobType           = args.jobType or buildJobType(args.part, args.brokenItem)

  -- Fold any keep-lists (globals keep + equip keep + direct)
  local keep = {}
  local function append(lst) if lst then for i=1,#lst do keep[#keep+1] = lst[i] end end end
  append(args.globalKeep)
  append(args.equipKeep)
  append(args.keepFlagTargets)
  o.keepFlagTargets = (#keep > 0) and keep or nil

  return o
end

return VRO