local assets_royaljelly =
{
    Asset("ANIM", "anim/royal_jelly.zip"),
}

local assets_jellybean = {
    Asset("ANIM", "anim/jellybean.zip"),
}

local prefabs_royaljelly =
{
    "spoiled_food",
}

local function fn_royaljelly()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    MakeInventoryPhysics(inst)

    inst.AnimState:SetBuild("royal_jelly")
    inst.AnimState:SetBank("royal_jelly")
    inst.AnimState:PlayAnimation("idle")

    inst:AddTag("honeyed")

    inst:AddComponent("edible")
    inst.components.edible.healthvalue = TUNING.HEALING_LARGE
    inst.components.edible.hungervalue = TUNING.CALORIES_SMALL
    inst.components.edible.sanityvalue = TUNING.SANITY_MED

    inst:AddComponent("stackable")
    inst.components.stackable.maxsize = TUNING.STACK_SIZE_SMALLITEM

    inst:AddComponent("perishable")
    inst.components.perishable:SetPerishTime(TUNING.PERISH_MED)
    inst.components.perishable:StartPerishing()
    inst.components.perishable.onperishreplacement = "spoiled_food"

    inst:AddComponent("tradable")
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname = "images/inventoryimages/royal_jelly.xml"

    inst:AddComponent("inspectable")

    return inst
end

local function fn_jellybean()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    MakeInventoryPhysics(inst)

    inst.AnimState:SetBuild("jellybean")
    inst.AnimState:SetBank("jellybean")
    inst.AnimState:PlayAnimation("idle", false)

    inst:AddTag("preparedfood")

    inst:AddComponent("edible")
    inst.components.edible.healthvalue = TUNING.JELLYBEANS_HEALTH
    inst.components.edible.hungervalue = 0
    inst.components.edible.foodtype = "GENERIC"
    inst.components.edible.foodstate = "PREPARED"
    inst.components.edible.sanityvalue = TUNING.SANITY_TINY

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname = "images/inventoryimages/jellybean.xml"

    inst:AddComponent("stackable")
    inst.components.stackable.maxsize = 3

    inst:AddTag("honeyed")

    inst:AddComponent("bait")
    inst:AddComponent("tradable")

    return inst
end

return Prefab("royal_jelly", fn_royaljelly, assets_royaljelly, prefabs_royaljelly), Prefab("common/inventory/jellybean", fn_jellybean, assets_jellybean)