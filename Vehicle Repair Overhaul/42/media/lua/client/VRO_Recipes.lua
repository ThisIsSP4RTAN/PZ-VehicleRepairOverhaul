VRO.Recipes = VRO.Recipes or {
----------------------------------------------------------------
-- A) Recipes (edit these)
-- You can put defaults on the recipe itself:
--   equip = { primary="Base.BlowTorch", wearTag="WeldingMask" }
--   anim  = "Welding"
--   sound = "BlowTorch"
--   time  = function(player, brokenItem) return 160 end  -- or a number
----------------------------------------------------------------
    {
    name = "Fix Gas Tank Welding",
    require = {
      "Base.NormalGasTank1","Base.BigGasTank1","Base.NormalGasTank2","Base.BigGasTank2",
      "Base.NormalGasTank3","Base.BigGasTank3","Base.NormalGasTank8","Base.BigGasTank8",
      "Base.U1550LGasTank2","Base.MH_MkIIgastank1","Base.MH_MkIIgastank2","Base.MH_MkIIgastank3",
      "Base.M35FuelTank2","Base.NivaGasTank1","Base.97BushGasTank2","Base.ShermanGasTank2","Base.87fordF700GasTank2",
    },
    -- Global item: drives propane usage requirement
    globalItem = { item="Base.BlowTorch", uses=3 },
    conditionModifier = 0.8,

    -- Recipe-level defaults (fixers may override)
    equip = { primary="Base.BlowTorch", wearTag="WeldingMask" },
    anim  = "Welding",
    sound = "BlowTorch",
    time  = 160,

    -- Fixers can override equip/anim/sound/time per entry if needed:
    fixers = {
      { item="Base.SheetMetal",        uses=1, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.SmallSheetMetal",   uses=2, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.CopperSheet",       uses=1, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.SmallCopperSheet",  uses=2, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.GoldSheet",         uses=1, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.SilverSheet",       uses=1, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.SmallArmorPlate",   uses=2, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.AluminumScrap",     uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.BrassScrap",        uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.CopperScrap",       uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.IronScrap",         uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.ScrapMetal",        uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.SteelScrap",        uses=8, skills={ MetalWelding=3, Mechanics=3 } },
      { item="Base.UnusableMetal",     uses=8, skills={ MetalWelding=3, Mechanics=3 } },
    },
  },
}