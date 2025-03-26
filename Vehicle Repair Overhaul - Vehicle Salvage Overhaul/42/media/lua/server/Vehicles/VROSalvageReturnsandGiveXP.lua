require("recipecode");

function Recipe.OnGiveXP.Tailoring5(recipe, ingredients, result, player)
    player:getXp():AddXP(Perks.Tailoring, 5);
end

function Recipe.OnGiveXP.Tailoring10(recipe, ingredients, result, player)
    player:getXp():AddXP(Perks.Tailoring, 10);
end

function Recipe.OnGiveXP.Tailoring20(recipe, ingredients, result, player)
    player:getXp():AddXP(Perks.Tailoring, 20);
end

function Recipe.OnGiveXP.Mechanics5(recipe, ingredients, result, player)
    player:getXp():AddXP(Perks.Mechanics, 5);
end

function Recipe.OnGiveXP.Mechanics10(recipe, ingredients, result, player)
    player:getXp():AddXP(Perks.Mechanics, 10);
end

function Recipe.OnGiveXP.Mechanics20(recipe, ingredients, result, player)
    player:getXp():AddXP(Perks.Mechanics, 20);
end


function Recipe.OnCreate.SalvageModuleReturnsSmall(items, result, player)

    local isoPlayer = instanceof(player, "IsoPlayer") and player or getSpecificPlayer(0)
    local skill = (isoPlayer:getPerkLevel(Perks.Mechanics) + isoPlayer:getPerkLevel(Perks.MetalWelding))
    --print(skill) --Calculates by adding Mechanic skill + Metal Welding Skill--
    local success = 45 + skill; --highest value skill is 20, added here success would be 65% win--
    local inventory = isoPlayer:getInventory()

    --Creates 3 sets of chances for items from the salvage, each chance of getting an extra item--
    --from the salvage is dependent on player skill. First random roll chooses item, second random roll --
    --gives a number to compare with skill above. If random number is lower than success then you gain the extra item--
    for i=1,3 do --sets a loop of 3--
        local r = ZombRand(5);
        --print(r) --Gives 3 random numbers between 0-8--
        local chance = ZombRand(1,100);
        --print(chance) --Gives 3 random numbers between 1 and 100--
        if r==1 and chance<success then
            inventory:AddItem("Base.Screws") end;
        if r==2 and chance<success then
            inventory:AddItem("Base.SmallSheetMetal") end;
        if r==3 and chance<success then
            inventory:AddItem("Base.ScrapMetal") end;
        if r==4 and chance<success then
            inventory:AddItem("Base.SmallSheetMetal") end;
        end

end

function Recipe.OnCreate.SalvageModuleReturnsFabrics(items, result, player)

    local isoPlayer = instanceof(player, "IsoPlayer") and player or getSpecificPlayer(0)
    local skill = (isoPlayer:getPerkLevel(Perks.Mechanics) + isoPlayer:getPerkLevel(Perks.MetalWelding))
    local success = 45 + skill; --highest value skill is 20, added here success would be 65% win--
    local inventory = isoPlayer:getInventory()

    for i=1,3 do
        local r = ZombRand(6);
        local chance = ZombRand(1,100);

        if r==1 and chance<success then
            inventory:AddItem("Base.RippedSheetsDirty") end;
        if r==2 and chance<success then
            inventory:AddItem("Base.ScrapMetal") end;
        if r==3 and chance<success then
            inventory:AddItem("Base.DenimStripsDirty") end;
        if r==4 and chance<success then
            inventory:AddItem("Base.LeatherStripsDirty") end;
        if r==5 and chance<success then
            inventory:AddItem("Base.Thread") end;
        end

end

function Recipe.OnCreate.SalvageModuleReturnsSmallElectrics(items, result, player)

    local isoPlayer = instanceof(player, "IsoPlayer") and player or getSpecificPlayer(0)
    local skill = (isoPlayer:getPerkLevel(Perks.Mechanics) + isoPlayer:getPerkLevel(Perks.MetalWelding))
    local success = 45 + skill; --highest value skill is 20, added here success would be 65% win--
    local inventory = isoPlayer:getInventory()

    for i=1,3 do
        local r = ZombRand(6);
        local chance = ZombRand(1,100);

        if r==1 and chance<success then
            inventory:AddItem("Base.SmallSheetMetal") end;
        if r==2 and chance<success then
            inventory:AddItem("Base.ScrapMetal") end;
        if r==3 and chance<success then
            inventory:AddItem("Base.ElectronicsScrap") end;
        if r==4 and chance<success then
            inventory:AddItem("Base.Wire") end;
        if r==5 and chance<success then
            inventory:AddItem("Base.UnusableMetal") end;
        end

end

function Recipe.OnCreate.SalvageModuleReturnsLargeMetals(items, result, player)

    local isoPlayer = instanceof(player, "IsoPlayer") and player or getSpecificPlayer(0)
    local skill = (isoPlayer:getPerkLevel(Perks.Mechanics) + isoPlayer:getPerkLevel(Perks.MetalWelding))
    --print(skill) --Calculates by adding Mechanic skill + Metal Welding Skill--
    local success = 45 + skill; --highest value skill is 20, added here success would be 65% win--
    --print(success) --Used to give a variable based on skill from above with a static number(30)--
    local inventory = isoPlayer:getInventory()

    --Creates 3 sets of chances for items from the salvage, each chance of getting an extra item--
    --from the salvage is dependent on player skill. First random roll chooses item, second random roll --
    --gives a number to compare with skill above. If random number is lower than success then you gain the extra item--
    for i=1,3 do --sets a loop of 3--
        local r = ZombRand(8);
        --print(r) --Gives 3 random numbers between 0-8--
        local chance = ZombRand(1,100);
        --print(chance) --Gives 3 random numbers between 1 and 100--
        if r==1 and chance<success then
            inventory:AddItem("Base.SheetMetal") end;
        if r==2 and chance<success then
            inventory:AddItem("Base.SmallSheetMetal") end;
        if r==3 and chance<success then
            inventory:AddItem("Base.ElectronicsScrap") end;
        if r==4 and chance<success then
            inventory:AddItem("Base.Screws") end;
        if r==5 and chance<success then
            inventory:AddItem("Base.SheetMetal") end;
        if r==6 and chance<success then
            inventory:AddItem("Base.SmallSheetMetal") end;
        if r==7 and chance<success then
            inventory:AddItem("Base.MetalBar") end;
    end

end

function Recipe.OnCreate.SalvageModuleReturnsArmourLargeMetals(items, result, player)

    local isoPlayer = instanceof(player, "IsoPlayer") and player or getSpecificPlayer(0)
    local skill = (isoPlayer:getPerkLevel(Perks.Mechanics) + isoPlayer:getPerkLevel(Perks.MetalWelding))
    local success = 45 + skill; --highest value skill is 20, added here success would be 65% win--
    local inventory = isoPlayer:getInventory()

    for i=1,3 do
        local r = ZombRand(6);
        local chance = ZombRand(1,100);

        if r==1 and chance<success then
            inventory:AddItem("Base.SheetMetal") end;
        if r==2 and chance<success then
            inventory:AddItem("Base.SmallSheetMetal") end;
        if r==3 and chance<success then
            inventory:AddItem("Base.ScrapMetal") end;
        if r==4 and chance<success then
            inventory:AddItem("Base.SheetMetal") end;
        if r==5 and chance<success then
            inventory:AddItem("Base.MetalBar") end;
    end

end

function Recipe.OnCreate.SalvageModuleReturnsSuspension(items, result, player)

    local isoPlayer = instanceof(player, "IsoPlayer") and player or getSpecificPlayer(0)
    local skill = (isoPlayer:getPerkLevel(Perks.Mechanics) + isoPlayer:getPerkLevel(Perks.MetalWelding))
    local success = 45 + skill; --highest value skill is 20, added here success would be 65% win--
    local inventory = isoPlayer:getInventory()

    for i=1,3 do
        local r = ZombRand(7);
        local chance = ZombRand(1,100);

        if r==1 and chance<success then
            inventory:AddItem("Base.MetalBar") end;
        if r==2 and chance<success then
            inventory:AddItem("Base.MetalBar") end;
        if r==3 and chance<success then
            inventory:AddItem("Base.ScrapMetal") end;
        if r==4 and chance<success then
            inventory:AddItem("Base.ScrapMetal") end;
        if r==5 and chance<success then
            inventory:AddItem("Base.UnusableMetal") end;
        if r==6 and chance<success then
            inventory:AddItem("Base.Screws") end;
        end

end

function Recipe.OnCreate.SalvageModuleReturnsTires(items, result, player)

    local isoPlayer = instanceof(player, "IsoPlayer") and player or getSpecificPlayer(0)
    local skill = (isoPlayer:getPerkLevel(Perks.Mechanics) + isoPlayer:getPerkLevel(Perks.MetalWelding))
    local success = 45 + skill; --highest value skill is 20, added here success would be 65% win--
    local inventory = isoPlayer:getInventory()

    for i=1,3 do
        local r = ZombRand(6);
        local chance = ZombRand(1,100);

        if r==1 and chance<success then
            inventory:AddItem("Base.ScrapMetal") end;
        if r==2 and chance<success then
            inventory:AddItem("Base.ScrapMetal") end;
        if r==3 and chance<success then
            inventory:AddItem("Base.Wire") end;
        if r==4 and chance<success then
            inventory:AddItem("Base.UnusableMetal") end;
        if r==5 and chance<success then
            inventory:AddItem("Base.Screws") end;
        end

end

function Recipe.OnCreate.SalvageModuleReturnsLeathers(items, result, player)

    local isoPlayer = instanceof(player, "IsoPlayer") and player or getSpecificPlayer(0)
    local skill = (isoPlayer:getPerkLevel(Perks.Mechanics) + isoPlayer:getPerkLevel(Perks.MetalWelding))
    local success = 45 + skill; --highest value skill is 20, added here success would be 65% win--
    local inventory = isoPlayer:getInventory()

    for i=1,3 do
        local r = ZombRand(5);
        local chance = ZombRand(1,100);

        if r==1 and chance<success then
            inventory:AddItem("Base.LeatherStrips") end;
        if r==2 and chance<success then
            inventory:AddItem("Base.LeatherStripsDirty") end;
        if r==3 and chance<success then
            inventory:AddItem("Base.Thread") end;
        if r==4 and chance<success then
            inventory:AddItem("Base.Thread") end;
        end

end

function Recipe.OnCreate.SalvageModuleReturnsSoftTops(items, result, player)

    local isoPlayer = instanceof(player, "IsoPlayer") and player or getSpecificPlayer(0)
    local skill = (isoPlayer:getPerkLevel(Perks.Mechanics) + isoPlayer:getPerkLevel(Perks.MetalWelding))
    local success = 45 + skill; --highest value skill is 20, added here success would be 65% win--
    local inventory = isoPlayer:getInventory()

    for i=1,3 do
        local r = ZombRand(5);
        local chance = ZombRand(1,100);

        if r==1 and chance<success then
            inventory:AddItem("Base.LeatherStrips") end;
        if r==2 and chance<success then
            inventory:AddItem("Base.LeatherStripsDirty") end;
        if r==3 and chance<success then
            inventory:AddItem("Base.Thread") end;
        if r==4 and chance<success then
            inventory:AddItem("Base.Tarp") end;
    end
end


 function Recipe.OnCreate.SalvageModuleReturnsMufflers(items, result, player)

    local isoPlayer = instanceof(player, "IsoPlayer") and player or getSpecificPlayer(0)
    local skill = (isoPlayer:getPerkLevel(Perks.Mechanics) + isoPlayer:getPerkLevel(Perks.MetalWelding))
     local success = 45 + skill; --highest value skill is 20, added here success would be 65% win--
     local inventory = isoPlayer:getInventory()

     for i=1,3 do
         local r = ZombRand(6);
         local chance = ZombRand(1,100);

         if r==1 and chance<success then
             inventory:AddItem("Base.MetalPipe") end;
         if r==2 and chance<success then
             inventory:AddItem("Base.SmallSheetMetal") end;
         if r==3 and chance<success then
             inventory:AddItem("Base.Screws") end;
         if r==4 and chance<success then
             inventory:AddItem("Base.UnusableMetal") end;
         if r==5 and chance<success then
             inventory:AddItem("Base.ScrapMetal") end;
     end
 end