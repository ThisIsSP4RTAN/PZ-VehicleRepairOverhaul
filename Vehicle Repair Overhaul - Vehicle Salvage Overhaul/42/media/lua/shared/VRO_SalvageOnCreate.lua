RecipeCodeOnCreate = RecipeCodeOnCreate or {}

local function _pickTargetContainer(items, result)
  local function fromOne(it)
    if it and it.getContainer then return it:getContainer() end
    return nil
  end
  local c = fromOne(result)
  if c then return c end
  if items then
    if items.size and items.get then
      for i = 0, items:size() - 1 do
        c = fromOne(items:get(i)); if c then return c end
      end
    elseif type(items) == "table" then
      for _, it in pairs(items) do
        c = fromOne(it); if c then return c end
      end
    end
  end
  if items and items.AddItem and items.getType then
    return items
  end
  return nil
end

local function _resolvePlayerFromItems(items, result)
  local function fromOne(it)
    if it and it.getContainer then
      local c = it:getContainer()
      if c and c.getParent then
        local owner = c:getParent()
        if owner and instanceof(owner, "IsoPlayer") then
          return owner
        end
      end
    end
    return nil
  end
  local p = fromOne(result)
  if p then return p end
  if items and items.size and items:size() > 0 then
    for i = 0, items:size() - 1 do
      p = fromOne(items:get(i)); if p then return p end
    end
  elseif type(items) == "table" then
    for _, it in pairs(items) do
      p = fromOne(it); if p then return p end
    end
  end
  return nil
end

local function _invokeReturns(recipeKey, player, items, result)
  if isClient() then
    local idx = (type(player) == "number") and player or (player and player:getPlayerNum()) or 0
    local ply = getSpecificPlayer(idx)
    if not ply then return end
    sendClientCommand(ply, "vro_salvage", "doReturns", { recipe = recipeKey, playerIndex = idx })
    return
  end

  local ply
  if player and instanceof(player, "IsoPlayer") then
    ply = player
  elseif result and instanceof(result, "IsoPlayer") then
    ply = result
  else
    ply = _resolvePlayerFromItems(items, result)
  end

  if ply and VRO_Salvage_Server_DoReturns then
    VRO_Salvage_Server_DoReturns(ply, recipeKey)
    return
  end

  local cont = _pickTargetContainer(items, result)
  if cont and VRO_Salvage_Server_DoReturnsToContainer then
    VRO_Salvage_Server_DoReturnsToContainer(cont, recipeKey)
  end
end

function RecipeCodeOnCreate.SalvageModuleReturnsSmall(items, result, player)              _invokeReturns("Small",                player, items, result) end
function RecipeCodeOnCreate.SalvageModuleReturnsFabrics(items, result, player)            _invokeReturns("Fabrics",              player, items, result) end
function RecipeCodeOnCreate.SalvageModuleReturnsSmallElectrics(items, result, player)     _invokeReturns("SmallElectrics",       player, items, result) end
function RecipeCodeOnCreate.SalvageModuleReturnsLargeMetals(items, result, player)        _invokeReturns("LargeMetals",          player, items, result) end
function RecipeCodeOnCreate.SalvageModuleReturnsArmourLargeMetals(items, result, player)  _invokeReturns("ArmourLargeMetals",    player, items, result) end
function RecipeCodeOnCreate.SalvageModuleReturnsSuspension(items, result, player)         _invokeReturns("Suspension",           player, items, result) end
function RecipeCodeOnCreate.SalvageModuleReturnsTires(items, result, player)              _invokeReturns("Tires",                player, items, result) end
function RecipeCodeOnCreate.SalvageModuleReturnsLeathers(items, result, player)           _invokeReturns("Leathers",             player, items, result) end
function RecipeCodeOnCreate.SalvageModuleReturnsSoftTops(items, result, player)           _invokeReturns("SoftTops",             player, items, result) end
function RecipeCodeOnCreate.SalvageModuleReturnsMufflers(items, result, player)           _invokeReturns("Mufflers",             player, items, result) end
function RecipeCodeOnCreate.SalvageModuleReturnsWooden(items, result, player)             _invokeReturns("Wooden",               player, items, result) end