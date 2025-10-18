local function _getPartListByName(name)
  -- Look in common places we use for centralized lists
  local V = rawget(_G, "VRO")
  if V then
    if type(V.PartLists) == "table" and type(V.PartLists[name]) == "table" then return V.PartLists[name] end
    if type(V.Lists)     == "table" and type(V.Lists[name])     == "table" then return V.Lists[name]     end
  end
  local PL = rawget(_G, "VRO_PART_LISTS")
  if type(PL) == "table" and type(PL[name]) == "table" then return PL[name] end
  return nil
end

local function _existsFullType(fullType)
  local sm = ScriptManager and ScriptManager.instance
  return (sm and sm:getItem(fullType)) ~= nil
end

local function _flattenTokens(tokens)
  -- tokens may be:
  --   "@GasTanks"   -> expands to that list
  --   "Base.Item"   -> include single item
  --   "!Base.Item"  -> exclude single item
  -- Order-preserving include, then apply exclusions.
  local includeList, includeSet = {}, {}
  local excludeSet = {}

  local function _add(ft)
    if not includeSet[ft] then
      includeSet[ft] = true
      table.insert(includeList, ft)
    end
  end

  for _, tok in ipairs(tokens or {}) do
    if type(tok) == "string" then
      local negative = false
      if tok:sub(1,1) == "!" then
        negative = true
        tok = tok:sub(2)
      end

      if tok:sub(1,1) == "@" then
        local listName = tok:sub(2)
        local lst = _getPartListByName(listName)
        if lst then
          if negative then
            for _, ft in ipairs(lst) do excludeSet[ft] = true end
          else
            for _, ft in ipairs(lst) do
              if _existsFullType(ft) then _add(ft) end
            end
          end
        else
          --print(("[VRO] [Fixing] Missing part list @%s (skipped)"):format(listName))
        end
      else
        -- single fullType
        if negative then
          excludeSet[tok] = true
        else
          if _existsFullType(tok) then _add(tok) else
            --print(("[VRO] [Fixing] Missing item (skipped): %s"):format(tok))
          end
        end
      end
    end
  end

  -- Apply exclusions while preserving order
  local out = {}
  for _, ft in ipairs(includeList) do
    if not excludeSet[ft] then table.insert(out, ft) end
  end
  return out
end

-- NEW: you can pass either an array of tokens, or a single string token (e.g. "@GasTanks")
local function injectFixingRequire(fixingName, itemListOrToken)
  local fixing = ScriptManager.instance:getFixing(fixingName)
  if not fixing then
    --print("[VRO] Fixing not found:", fixingName)
    return
  end

  local tokens
  if type(itemListOrToken) == "string" then
    tokens = { itemListOrToken }
  else
    tokens = itemListOrToken or {}
  end

  local validItems = _flattenTokens(tokens)

  if #validItems > 0 then
    -- Fixing.Load accepts a single script-like string chunk with Require entries (; delimited)
    local inputString = "{ Require = " .. table.concat(validItems, ";") .. ", }"
    fixing:Load(fixingName, inputString)
    --print("[VRO] [Fixing] Injected Require list for:", fixingName)
  else
    --print(("[VRO] [Fixing] No valid items for '%s'; leaving recipe unchanged."):format(fixingName))
  end
end

local function injectAllFixingRequires()

    injectFixingRequire("VRO Fix Gas Tank Welding",
        { "@GasTank_All" }
    )

    injectFixingRequire("VRO Fix Gas Tank",
        { "@GasTank_All" }
    )

    injectFixingRequire("VRO Fix Gas Tank Small Welding",
        { "@GasTankSmall_All" }
    )

    injectFixingRequire("VRO Fix Gas Tank Small",
        { "@GasTankSmall_All" }
    )

    injectFixingRequire("VRO Fix Trailer Welding",
        { "@Trailer_All" }
    )

    injectFixingRequire("VRO Fix Trailer",
        { "@Trailer_All" }
    )

    injectFixingRequire("VRO Fix Trailer 1",
        { "@Trailer_All" }
    )

    injectFixingRequire("VRO Fix Trailer Lids Welding",
        { "@TrailerLids_All" }
    )

    injectFixingRequire("VRO Fix Trailer Lids",
        { "@TrailerLids_All" }
    )

    injectFixingRequire("VRO Fix Trailer Lids 1",
        { "@TrailerLids_All" }
    )

    injectFixingRequire("VRO Fix Hood Welding",
        { "@Hood_All" }
    )

    injectFixingRequire("VRO Fix Hood",
        { "@Hood_All" }
    )

    injectFixingRequire("VRO Fix Military Hood Welding",
        { "@MilitaryHood_All" }
    )

    injectFixingRequire("VRO Fix Military Hood",
        { "@MilitaryHood_All" }
    )

    injectFixingRequire("VRO Fix KI5 Wood Parts",
        { "@WoodParts_All" }
    )

    injectFixingRequire("VRO Fix Small Trunk Welding",
        { "@SmallTrunk_All" }
    )

    injectFixingRequire("VRO Fix Small Trunk",
        { "@SmallTrunk_All" }
    )

    injectFixingRequire("VRO Fix Small Trunk 1",
        { "@SmallTrunk_All" }
    )

    injectFixingRequire("VRO Fix Trunk Welding",
        { "@Trunk_All" }
    )

    injectFixingRequire("VRO Fix Trunk",
        { "@Trunk_All" }
    )

    injectFixingRequire("VRO Fix Trunk 1",
        { "@Trunk_All" }
    )

    injectFixingRequire("VRO Fix Trunk Welding Military",
        { "@TrunkMilitary_All" }
    )

    injectFixingRequire("VRO Fix Trunk Military",
        { "@TrunkMilitary_All" }
    )

    injectFixingRequire("VRO Fix Trunk Door Welding",
        { "@TrunkDoor_All" }
    )

    injectFixingRequire("VRO Fix Trunk Door",
        { "@TrunkDoor_All" }
    )

    injectFixingRequire("VRO Fix Trunk Door Welding Military",
        { "@TrunkDoorMilitary_All" }
    )

    injectFixingRequire("VRO Fix Trunk Door Military",
        { "@TrunkDoorMilitary_All" }
    )

    injectFixingRequire("VRO Fix Door Welding",
        { "@Door_All" }
    )

    injectFixingRequire("VRO Fix Door",
        { "@Door_All" }
    )

    injectFixingRequire("VRO Fix Door 1",
        { "@Door_All" }
    )

    injectFixingRequire("VRO Fix Door Welding Military",
        { "@DoorMilitary_All" }
    )

    injectFixingRequire("VRO Fix Door Military",
        { "@DoorMilitary_All" }
    )

    injectFixingRequire("VRO Fix Glove box",
        { "@GloveBox_All" }
    )

    injectFixingRequire("VRO Fix Glove box 1",
        { "@GloveBox_All" }
    )

    injectFixingRequire("VRO Fix Glove Box Welding",
        { "@GloveBox_All" }
    )

    injectFixingRequire("VRO Fix Car seat",
        { "@CarSeat_All", "Base.ATAMotoBagBMW1", "Base.ATAMotoBagBMW2", "Base.ATAMotoHarleyBag", "Base.ATAMotoHarleyHolster", "Base.SS100topbag3", "Base.90pierceArrowHoses", "Base.FireDeptHosesMedium" }
    )

    injectFixingRequire("VRO Fix Car seat 1",
        { "@CarSeat_All", "Base.ATAMotoBagBMW1", "Base.ATAMotoBagBMW2", "Base.ATAMotoHarleyBag", "Base.ATAMotoHarleyHolster", "Base.SS100topbag3", "Base.90pierceArrowHoses", "Base.FireDeptHosesMedium" }
    )

    injectFixingRequire("VRO Fix Car seat 2",
        { "@CarSeat_All" }
    )

    injectFixingRequire("VRO Fix Car seat 3",
        { "@CarSeat_All" }
    )

    injectFixingRequire("VRO Fix Tire",
        { "@Tire_All" }
    )

    injectFixingRequire("VRO Fix Military Tire",
        { "@MilitaryTire_All" }
    )

    injectFixingRequire("VRO Fix Small Brake",
        { "@SmallBrake_All" }
    )

    injectFixingRequire("VRO Fix Small Brake Welding",
        { "@SmallBrake_All" }
    )

    injectFixingRequire("VRO Fix Brake",
        { "@Brake_All" }
    )

    injectFixingRequire("VRO Fix Brake Welding",
        { "@Brake_All" }
    )

    injectFixingRequire("VRO Fix Military Brake Welding",
        { "@MilitaryBrake_All" }
    )

    injectFixingRequire("VRO Fix Battery",
        { "@Battery_All" }
    )

    injectFixingRequire("VRO Fix Large Battery",
        { "@LargeBattery_All" }
    )

    injectFixingRequire("VRO Fix Small Suspension Welding",
        { "@SmallSuspension_All" }
    )

    injectFixingRequire("VRO Fix Small Suspension 1",
        { "@SmallSuspension_All" }
    )

    injectFixingRequire("VRO Fix Suspension Welding",
        { "@Suspension_All" }
    )

    injectFixingRequire("VRO Fix Suspension 1",
        { "@Suspension_All" }
    )

    injectFixingRequire("VRO Fix Military Suspension Welding",
        { "@MilitarySuspension_All" }
    )

    injectFixingRequire("VRO Fix Military Suspension 1",
        { "@MilitarySuspension_All" }
    )

    injectFixingRequire("VRO Fix Small Muffler Welding",
        { "@SmallMuffler_All" }
    )

    injectFixingRequire("VRO Fix Small Muffler",
        { "@SmallMuffler_All" }
    )

    injectFixingRequire("VRO Fix Small Muffler 1",
        { "@SmallMuffler_All" }
    )

    injectFixingRequire("VRO Fix Muffler Welding",
        { "@Muffler_All" }
    )

    injectFixingRequire("VRO Fix Muffler",
        { "@Muffler_All" }
    )

    injectFixingRequire("VRO Fix Muffler 1",
        { "@Muffler_All" }
    )

    injectFixingRequire("VRO Fix Window Welding",
        { "@Window_All" }
    )

    injectFixingRequire("VRO Fix Window",
        { "@Window_All" }
    )

    injectFixingRequire("VRO Fix Window 1",
        { "@Window_All" }
    )

    injectFixingRequire("VRO Fix Military Windows Welding",
        { "@MilitaryWindow_All" }
    )

    injectFixingRequire("VRO Fix Radio",
        { "@Radio_All" }
    )

    injectFixingRequire("VRO Fix Light",
        { "@Light_All" }
    )

    injectFixingRequire("VRO Fix Roof Rack Welding",
        { "@RoofRack_All", "Base.TowBar" }
    )

    injectFixingRequire("VRO Fix Roof Rack",
        { "@RoofRack_All" }
    )

    injectFixingRequire("VRO Fix Roof Rack 1",
        { "@RoofRack_All", "Base.TowBar", "Base.93fordCF8000Brushes" }
    )

    injectFixingRequire("VRO Fix Bullbar Welding",
        { "@Bullbar_All", "Base.M113FrontWindow1", "Base.M113FrontWindow2", "Base.M113FrontWindow3", "Base.M923SpareMount1", "Base.MH_MkII_guntower1", "Base.MH_MkII_guntower2", "Base.MH_MkII_guntower3", "Base.M998SpareMount_Item", "Base.M998SpareTireMount_Item", "Base.M35TarpFrame2", "Base.ShermanDriveSprocket2", "Base.ShermanRearSprocket2", "Base.ShermanHatch2" }
    )

    injectFixingRequire("VRO Fix Bullbar",
        { "@Bullbar_All", "Base.M113FrontWindow1", "Base.M113FrontWindow2", "Base.M113FrontWindow3", "Base.M923SpareMount1", "Base.MH_MkII_guntower1", "Base.MH_MkII_guntower2", "Base.MH_MkII_guntower3", "Base.M998SpareMount_Item", "Base.M998SpareTireMount_Item", "Base.M35TarpFrame2", "Base.ShermanDriveSprocket2", "Base.ShermanRearSprocket2", "Base.ShermanHatch2" }
    )

    injectFixingRequire("VRO Fix Bullbar 1",
        { "@Bullbar_All" }
    )

    injectFixingRequire("VRO Fix Saddlebags Hard",
        { "@SaddlebagsHard_All" }
    )

    injectFixingRequire("VRO Fix Saddlebags Hard 1",
        { "@SaddlebagsHard_All" }
    )

    injectFixingRequire("VRO Fix SoftTops",
        { "@SoftTops_All" }
    )

    injectFixingRequire("VRO Fix SoftTops 1",
        { "@SoftTops_All" }
    )

    injectFixingRequire("VRO Fix SoftTops 2",
        { "@SoftTops_All" }
    )

    injectFixingRequire("VRO Fix Panels Welding",
        { "@Panels_All" }
    )

    injectFixingRequire("VRO Fix Panels",
        { "@Panels_All" }
    )

    injectFixingRequire("VRO Fix Panels 1",
        { "@Panels_All" }
    )

    injectFixingRequire("VRO Fix Tank Containers",
        { "@TankContainers_All" }
    )

    injectFixingRequire("VRO Fix Vehicle Shovel",
        { "@VehicleShovel_All" }
    )

    injectFixingRequire("VRO Fix Tire FixAFlat",
        { "@FixAFlat_All" }
    )
end

Events.OnInitWorld.Add(injectAllFixingRequires)
if isServer() then
    Events.OnGameBoot.Add(injectAllFixingRequires)
end