local Commands = {}

local function _giveItem(isoPlayer, fullType, count)
  if not (isoPlayer and fullType) then return end
  count = tonumber(count) or 1
  if count <= 0 then return end
  local inv = isoPlayer:getInventory()
  if not inv then return end
  for _ = 1, count do
    local it = inv:AddItem(fullType)
    if it then
      if sendAddItemToContainer then
        sendAddItemToContainer(inv, it)
      elseif it.transmitCompleteItemToClients then
        it:transmitCompleteItemToClients()
      end
    end
  end
end

local function _skillSum(isoPlayer, perkA, perkB)
  local a = (perkA and isoPlayer:getPerkLevel(perkA)) or 0
  local b = (perkB and isoPlayer:getPerkLevel(perkB)) or 0
  return a + b
end

local function _giveItemToContainer(container, fullType, count)
  if not (container and fullType) then return end
  count = tonumber(count) or 1
  if count <= 0 then return end
  for _ = 1, count do
    local it = container:AddItem(fullType)
    if it then
      if sendAddItemToContainer then
        sendAddItemToContainer(container, it)
      elseif it.transmitCompleteItemToClients then
        it:transmitCompleteItemToClients()
      end
    end
  end
end

local function _rollAwardsToTarget(target, asContainer, isoPlayerOrNil, pool)
  local success = 45
  if isoPlayerOrNil and pool.successFrom then
    success = math.max(0, pool.successFrom(isoPlayerOrNil))
  end
  for _ = 1, pool.rolls do
    local r = ZombRand(1, #pool.items)
    local pick = pool.items[r]
    local chance = ZombRand(1, 100)
    if chance < success then
      if asContainer then
        _giveItemToContainer(target, pick, 1)
      else
        _giveItem(isoPlayerOrNil, pick, 1)
      end
    end
  end
end

function Commands.addXp(player, args)
  if not (player and args) then return end
  local amt = tonumber(args.amount) or 0
  if amt <= 0 then return end

  -- Resolve perk robustly
  local perk = nil
  if args.perk then
    if Perks and Perks.FromString then
      local ok, p = pcall(function() return Perks.FromString(tostring(args.perk)) end)
      if ok then perk = p end
    end
    if not perk and Perks then
      perk = Perks[tostring(args.perk)]
    end
  end
  if not perk then return end

  if addXp then
    addXp(player, perk, amt)
  else
    local xp = player.getXp and player:getXp()
    if xp and xp.AddXP then xp:AddXP(perk, amt) end
  end
end

local POOLS = {
  Small = {
    rolls = 3,
    items = { "Base.Screws", "Base.SmallSheetMetal", "Base.ScrapMetal", "Base.SmallSheetMetal" },
    successFrom = function(p) return 45 + _skillSum(p, Perks.Mechanics, Perks.MetalWelding) end,
  },
  Fabrics = {
    rolls = 3,
    items = { "Base.RippedSheetsDirty", "Base.ScrapMetal", "Base.DenimStripsDirty", "Base.LeatherStripsDirty", "Base.Thread" },
    successFrom = function(p) return 45 + _skillSum(p, Perks.Mechanics, Perks.MetalWelding) end,
  },
  SmallElectrics = {
    rolls = 3,
    items = { "Base.SmallSheetMetal", "Base.ScrapMetal", "Base.ElectronicsScrap", "Base.Wire", "Base.UnusableMetal" },
    successFrom = function(p) return 45 + _skillSum(p, Perks.Mechanics, Perks.MetalWelding) end,
  },
  LargeMetals = {
    rolls = 3,
    items = { "Base.SheetMetal", "Base.SmallSheetMetal", "Base.ElectronicsScrap", "Base.Screws", "Base.SheetMetal", "Base.SmallSheetMetal", "Base.MetalBar" },
    successFrom = function(p) return 45 + _skillSum(p, Perks.Mechanics, Perks.MetalWelding) end,
  },
  ArmourLargeMetals = {
    rolls = 3,
    items = { "Base.SheetMetal", "Base.SmallSheetMetal", "Base.ScrapMetal", "Base.SheetMetal", "Base.MetalBar" },
    successFrom = function(p) return 45 + _skillSum(p, Perks.Mechanics, Perks.MetalWelding) end,
  },
  Suspension = {
    rolls = 3,
    items = { "Base.MetalBar", "Base.MetalBar", "Base.ScrapMetal", "Base.ScrapMetal", "Base.UnusableMetal", "Base.Screws" },
    successFrom = function(p) return 45 + _skillSum(p, Perks.Mechanics, Perks.MetalWelding) end,
  },
  Tires = {
    rolls = 3,
    items = { "Base.ScrapMetal", "Base.ScrapMetal", "Base.Wire", "Base.UnusableMetal", "Base.Screws" },
    successFrom = function(p) return 45 + _skillSum(p, Perks.Mechanics, Perks.MetalWelding) end,
  },
  Leathers = {
    rolls = 3,
    items = { "Base.LeatherStrips", "Base.LeatherStripsDirty", "Base.Thread", "Base.Thread" },
    successFrom = function(p) return 45 + _skillSum(p, Perks.Mechanics, Perks.Tailoring) end,
  },
  SoftTops = {
    rolls = 3,
    items = { "Base.LeatherStrips", "Base.LeatherStripsDirty", "Base.Thread", "Base.Tarp" },
    successFrom = function(p) return 45 + _skillSum(p, Perks.Mechanics, Perks.Tailoring) end,
  },
  Mufflers = {
    rolls = 3,
    items = { "Base.MetalPipe", "Base.SmallSheetMetal", "Base.Screws", "Base.UnusableMetal", "Base.ScrapMetal" },
    successFrom = function(p) return 45 + _skillSum(p, Perks.Mechanics, Perks.MetalWelding) end,
  },
  Wooden = {
    rolls = 3,
    items = { "Base.Plank", "Base.Nails", "Base.Screws", "Base.UnusableWood" },
    successFrom = function(p) return 45 + _skillSum(p, Perks.Mechanics, Perks.Woodwork) end,
  },
}

function Commands.doReturns(player, args)
  if not (player and args and args.recipe) then return end
  local pool = POOLS[tostring(args.recipe)]
  if not pool then return end
  _rollAwardsToTarget(player, false, player, pool)
end

function VRO_Salvage_Server_DoReturns(player, recipeKey)
  if not player then return end
  return Commands.doReturns(player, { recipe = recipeKey, playerIndex = player:getPlayerNum() })
end

function VRO_Salvage_Server_DoReturnsToContainer(container, recipeKey)
  local pool = POOLS[tostring(recipeKey)]
  if not (container and pool) then return end
  local parent = container.getParent and container:getParent() or nil
  local ply = (parent and instanceof(parent, "IsoPlayer")) and parent or nil
  _rollAwardsToTarget(container, true, ply, pool)
end

local SalvageCmds = {}

SalvageCmds.OnClientCommand = function(module, command, player, args)
  if module ~= "vro_salvage" then return end
  if Commands[command] then
    Commands[command](player, args)
  end
end

Events.OnClientCommand.Add(SalvageCmds.OnClientCommand)