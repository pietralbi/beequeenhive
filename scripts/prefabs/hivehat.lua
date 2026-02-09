local U = require("beequeenhive_utils")

local function MakeHat(name)

	local fname = "hat_"..name
	local symname = name.."hat"
	local texture = symname..".tex"
	local prefabname = symname
	local assets =
		{
			Asset("ANIM", "anim/"..fname..".zip"),
            Asset("IMAGE", "images/inventoryimages/hivehat.tex"),
	        Asset("ATLAS", "images/inventoryimages/hivehat.xml"),
		}

	local function onequip(inst, owner, fname_override)
		local build = fname_override or fname
		owner.AnimState:OverrideSymbol("swap_hat", build, "swap_hat")
		owner.AnimState:Show("HAT")
		owner.AnimState:Show("HAIR_HAT")
		owner.AnimState:Hide("HAIR_NOHAT")
		owner.AnimState:Hide("HAIR")

		if owner:HasTag("player") then
			owner.AnimState:Hide("HEAD")
			owner.AnimState:Show("HEAD_HAIR")
			owner.AnimState:Hide("HAIRFRONT")
		end

		if inst.components.fueled then
			inst.components.fueled:StartConsuming()        
		end

		if inst:HasTag("antmask") then
			owner:AddTag("has_antmask")
		end		

		if inst:HasTag("gasmask") then
			owner:AddTag("has_gasmask")
		end				

		if inst:HasTag("venting") then
			owner:AddTag("venting")
		end

		if inst:HasTag("sneaky") then
			if not owner:HasTag("monster") then
				owner:AddTag("monster")
			else
				owner:AddTag("originaly_monster")
			end
			owner:AddTag("sneaky")
		end						
	end

	local function hideHat(inst, owner)
		owner.AnimState:Hide("HAT")
		owner.AnimState:Hide("HAIR_HAT")
		owner.AnimState:Show("HAIR_NOHAT")
		owner.AnimState:Show("HAIR")

		if owner:HasTag("player") then
			owner.AnimState:Show("HEAD")
			owner.AnimState:Hide("HEAD_HAIR")
			owner.AnimState:Show("HAIRFRONT")
		end
	end

	local function onunequip(inst, owner)
		hideHat(inst, owner)

		if inst.components.fueled then
			inst.components.fueled:StopConsuming()        
		end
		if inst:HasTag("antmask") then
			owner:RemoveTag("has_antmask")
		end	
		if inst:HasTag("gasmask") then
			owner:RemoveTag("has_gasmask")
		end	

		if inst:HasTag("venting") then
			owner:RemoveTag("venting")
		end	

		if inst:HasTag("sneaky") then
			if not owner:HasTag("originaly_monster") then
				owner:RemoveTag("monster")
			else
				owner:RemoveTag("originaly_monster")
			end
			owner:RemoveTag("sneaky")
		end	
	end

	local function simple()
		local inst = CreateEntity()

		inst.entity:AddTransform()
		inst.entity:AddAnimState()
		MakeInventoryPhysics(inst)

		if name ~= "double_umbrella" and name ~= "aerodynamic" then
			-- gas mask is different
			inst.AnimState:SetBank(symname)
			inst.AnimState:SetBuild(fname)
			inst.AnimState:PlayAnimation("anim")
		end
        
		inst:AddTag("hat")

		inst:AddComponent("inspectable")

		inst:AddComponent("inventoryitem")
		inst:AddComponent("tradable")

		inst:AddComponent("equippable")
		inst.components.equippable.equipslot = EQUIPSLOTS.HEAD

		inst.components.equippable:SetOnEquip( onequip )

		inst.components.equippable:SetOnUnequip( onunequip )

		return inst
	end

    local function hive_onunequip(inst, owner)
        onunequip(inst, owner)

        if owner ~= nil and owner.components.sanity ~= nil and (U.enabledSHIP or U.enabledPORK) then
            local old_modifier = owner.components.sanity:GetRateModifier()
            U.log("HiveHat onunequip old_modifier: "..tostring(old_modifier))
            owner.components.sanity:RemoveRateModifier("neg_aura_absorb")
            local new_modifier = owner.components.sanity:GetRateModifier()
            U.log("HiveHat onunequip new_modifier: "..tostring(new_modifier))
        end
    end

    local function hive_onequip(inst, owner)
        onequip(inst, owner)

        if owner ~= nil and owner.components.sanity ~= nil and (U.enabledSHIP or U.enabledPORK) then
            local old_modifier = owner.components.sanity:GetRateModifier()
            U.log("HiveHat onequip old_modifier: "..tostring(old_modifier))
            local new_modifier = - old_modifier * (1 + TUNING.ARMOR_HIVEHAT_SANITY_ABSORPTION)
            U.log("HiveHat onequip new_modifier: "..tostring(new_modifier))
            owner.components.sanity:AddRateModifier("neg_aura_absorb", new_modifier)
            U.log("HiveHat onequip new_modifier: "..tostring(owner.components.sanity:GetRateModifier() ))
        end
    end

    local hive = function()
        local inst = simple()

        inst:AddComponent("armor")
        inst.components.armor:InitCondition(TUNING.ARMOR_HIVEHAT, TUNING.ARMOR_HIVEHAT_ABSORPTION)

        inst:AddComponent("waterproofer")
        inst.components.waterproofer:SetEffectiveness(TUNING.WATERPROOFNESS_SMALL)

        inst.components.equippable:SetOnEquip(hive_onequip)
        inst.components.equippable:SetOnUnequip(hive_onunequip)

        if not (U.enabledSHIP or U.enabledPORK) then
            inst.components.equippable.dapperness = TUNING.DAPPERNESS_MED_LARGE
        end

        inst.components.inventoryitem.atlasname = "images/inventoryimages/hivehat.xml"

        return inst
    end

	local fn = hive
    
	return Prefab( "common/inventory/"..prefabname, fn, assets)
end

return MakeHat("hive")