local U = require("beequeenhive_utils")

local assets =
{
    Asset("ANIM", "anim/bee_queen_hive.zip"),
}

local base_prefabs =
{
    "beequeenhivegrown",
}

local prefabs =
{
    "beequeen",
    "honey",
    "honeycomb",
    "honey_splash",
}

local PHYS_RAD_LRG = 1.9
local PHYS_RAD_MED = 1.5
local PHYS_RAD_SML = .9

local function OnHoneyTask(inst, honeylevel)
    inst._honeytask = nil
    honeylevel = math.clamp(honeylevel, 0, 3)
    for i = 0, 3 do
        if i == honeylevel then
            inst.AnimState:Show("honey"..tostring(i))
        else
            inst.AnimState:Hide("honey"..tostring(i))
        end
    end
end

local function SetHoneyLevel(inst, honeylevel, delay)
    if inst._honeytask ~= nil then
        inst._honeytask:Cancel()
    end
    local workleft = inst.components.workable and inst.components.workable.workleft or "<none>"
    U.log("setting honey level to " .. tostring(honeylevel) .. " | workleft = " .. tostring(workleft))

    if delay ~= nil then
        OnHoneyTask(inst, honeylevel - 1)
        inst._honeytask = inst:DoTaskInTime(delay, OnHoneyTask, honeylevel)
    else
        inst._honeytask = nil
        OnHoneyTask(inst, honeylevel)
    end
end

local function StopHiveGrowthTimer(inst)
    inst.components.timer:StopTimer("hivegrowth1")
    inst.components.timer:StopTimer("hivegrowth2")
    inst.components.timer:StopTimer("hivegrowth")
    inst.components.timer:StopTimer("shorthivegrowth")
    inst.components.timer:StopTimer("firsthivegrowth")
    inst.AnimState:PlayAnimation("hole_idle")
    inst.AnimState:SetLayer(LAYER_BACKGROUND)
    inst.AnimState:SetSortOrder(3)
    SetHoneyLevel(inst, 0)
    inst.queenkilled = false
end

local function StartHiveGrowthTimer(inst)
    if inst.queenkilled then
        StopHiveGrowthTimer(inst)
        inst.components.timer:StartTimer("hivegrowth1", TUNING.BEEQUEEN_RESPAWN_TIME / 3)
    else
        StopHiveGrowthTimer(inst)
        inst.components.timer:StartTimer("shorthivegrowth", 10)
    end
end

local function OnQueenRemoved(queen)
    if queen.hivebase ~= nil then
        local otherqueen = queen.hivebase.components.entitytracker:GetEntity("queen")
        if (otherqueen == nil or otherqueen == queen) and
            queen.hivebase.components.entitytracker:GetEntity("hive") == nil then
            StartHiveGrowthTimer(queen.hivebase)
        end
    end
end

local function DoSpawnQueen(inst, worker, x1, y1, z1)
    U.log("Spawining queen")
    local x, y, z = inst.Transform:GetWorldPosition()
    local hivebase = inst.hivebase
    inst:Remove()

    local queen = SpawnPrefab("beequeen")
    queen.Transform:SetPosition(x, y, z)
    queen:ForceFacePoint(x1, y1, z1)

    if worker:IsValid() and
        worker.components.health ~= nil and
        not worker.components.health:IsDead() then
        queen.components.combat:SetTarget(worker)
    end

    queen.sg:GoToState("emerge")
    if hivebase ~= nil then
        queen.hivebase = hivebase
        StopHiveGrowthTimer(hivebase)
        hivebase.components.entitytracker:TrackEntity("queen", queen)
        hivebase:ListenForEvent("onremove", OnQueenRemoved, queen)
    end
end

local function CalcHoneyLevel(workleft)
    return math.clamp(3 + math.ceil((workleft - TUNING.BEEQUEEN_SPAWN_MAX_WORK) * .5), 0, 3)
end

local function RefreshHoneyState(inst)
    SetHoneyLevel(inst, CalcHoneyLevel(inst.components.workable.workleft))
end

local function OnWorked(inst, worker, workleft)
    if not inst.components.workable.workable then
        return
    end

    if workleft < 0 then
        workleft = 0
    end

    inst.components.timer:StopTimer("hiveregen")

    if workleft < 1 then
        inst.components.workable:SetWorkLeft(TUNING.BEEQUEEN_SPAWN_WORK_THRESHOLD > 0 and 1 or 0)
    end
    U.log("OnWorked workleft " .. tostring(inst.components.workable.workleft))

    inst.SoundEmitter:PlaySound("dontstarve/creatures/together/bee_queen/hive_hit")
    inst.AnimState:PlayAnimation("large_hit")
    SpawnPrefab("honey_splash").Transform:SetPosition(inst.Transform:GetWorldPosition())

    if worker ~= nil and worker:IsValid() and worker.components.health ~= nil and not worker.components.health:IsDead() then
        U.log("work left = " .. tostring(workleft))
        if TUNING.BEEQUEEN_SPAWN_WORK_THRESHOLD > 0 then
            local spawnchance = workleft < TUNING.BEEQUEEN_SPAWN_WORK_THRESHOLD and math.min(.8, 1 - workleft / TUNING.BEEQUEEN_SPAWN_WORK_THRESHOLD) or 0
            if math.random() < spawnchance then
                inst.components.workable:SetWorkable(false)
                SetHoneyLevel(inst, 0)
                local x, y, z = worker.Transform:GetWorldPosition()
                inst:DoTaskInTime(inst.AnimState:GetCurrentAnimationLength(), DoSpawnQueen, worker, x, y, z)
                return
            end
        end

        local lootscale = workleft / TUNING.BEEQUEEN_SPAWN_MAX_WORK
        local rnd = lootscale > 0 and math.random() / lootscale or 1
        local loot =
            (rnd < .01 and "honeycomb") or
            (rnd < .5 and "honey") or
            nil
        
        U.log("rnd : " .. tostring(rnd))

        if loot ~= nil then
            inst.components.lootdropper:SpawnLootPrefab(loot)
        end
    end

    inst.AnimState:PushAnimation("large", false)
    RefreshHoneyState(inst)

    U.log(inst.components.timer:GetDebugString())
    inst.components.timer:StartTimer("hiveregen", 4 * TUNING.SEG_TIME)
    U.log(inst.components.timer:GetDebugString())
end

local function OnHiveRegenTimer(inst, data)
    U.log("OnHiveRegenTimer " .. data.name)

    if data.name == "hiveregen" and
        inst.components.workable.workable and
        inst.components.workable.workleft < TUNING.BEEQUEEN_SPAWN_MAX_WORK then
        local oldhoneylevel = CalcHoneyLevel(inst.components.workable.workleft)
        inst.components.workable:SetWorkLeft(inst.components.workable.workleft + 1)
        local newhoneylevel = CalcHoneyLevel(inst.components.workable.workleft)
        if inst.components.workable.workleft < TUNING.BEEQUEEN_SPAWN_MAX_WORK then
            inst:DoTaskInTime(0, function()
                if inst:IsValid() and inst.components.timer ~= nil then
                    U.log("Restarting "  .. "hiveregen")
                    inst.components.timer:StartTimer("hiveregen", TUNING.SEG_TIME)
                end
            end)
        end
        if oldhoneylevel ~= newhoneylevel and not inst:IsAsleep() then
            inst.AnimState:PlayAnimation("transition")
            inst.AnimState:PushAnimation("large", false)
            SetHoneyLevel(inst, newhoneylevel, 10 * FRAMES)
        else
            SetHoneyLevel(inst, newhoneylevel)
        end
    end
end

local function EnableBase(inst, enable)
    inst.Physics:SetCapsule(PHYS_RAD_SML, 2)
    inst.Physics:SetActive(enable)
    inst.MiniMapEntity:SetEnabled(enable)
    inst.AnimState:PlayAnimation("hole_idle")
    inst.AnimState:SetLayer(LAYER_BACKGROUND)
    inst.AnimState:SetSortOrder(3)
    SetHoneyLevel(inst, 0)
    if enable then
        inst:Show()
    else
        inst:Hide()
    end
end

local function OnHiveRemoved(hive)
    if hive.hivebase ~= nil then
        local otherhive = hive.hivebase.components.entitytracker:GetEntity("hive")
        if otherhive == nil or otherhive == hive then
            EnableBase(hive.hivebase, true)

            if hive.hivebase.components.entitytracker:GetEntity("queen") == nil then
                StartHiveGrowthTimer(hive.hivebase)
            end
        end
    end
end

local function OnHiveShortGrowAnimOver(inst)
    if inst.AnimState:IsCurrentAnimation("grow_hole_to_small") then
        inst.Physics:SetCapsule(PHYS_RAD_MED, 2)
        inst.AnimState:PlayAnimation("grow_small_to_medium")
        inst.SoundEmitter:PlaySound("dontstarve/creatures/together/bee_queen/hive_grow")
        return
    elseif inst.AnimState:IsCurrentAnimation("grow_small_to_medium") then
        inst.Physics:SetCapsule(PHYS_RAD_LRG, 2)
        inst.AnimState:PlayAnimation("grow_medium_to_large")
        inst.SoundEmitter:PlaySound("dontstarve/creatures/together/bee_queen/hive_grow")
        return
    elseif inst.AnimState:IsCurrentAnimation("grow_medium_to_large") then
        inst.AnimState:PlayAnimation("large")
    end
    inst.components.workable:SetWorkable(true)
    inst:RemoveEventCallback("animover", OnHiveShortGrowAnimOver)
end

local function OnHiveLongGrowAnimOver(inst)
    if inst.AnimState:IsCurrentAnimation("grow_hole_to_small") then
        inst.Physics:SetCapsule(PHYS_RAD_MED, 2)
        inst.AnimState:PlayAnimation("grow_small_to_medium")
        inst.SoundEmitter:PlaySound("dontstarve/creatures/together/bee_queen/hive_grow")
        SetHoneyLevel(inst, 2, 4 * FRAMES)
        return
    elseif inst.AnimState:IsCurrentAnimation("grow_small_to_medium") then
        inst.Physics:SetCapsule(PHYS_RAD_LRG, 2)
        inst.AnimState:PlayAnimation("grow_medium_to_large")
        inst.SoundEmitter:PlaySound("dontstarve/creatures/together/bee_queen/hive_grow")
        SetHoneyLevel(inst, 3, 7 * FRAMES)
        return
    elseif inst.AnimState:IsCurrentAnimation("grow_medium_to_large") then
        inst.AnimState:PlayAnimation("large")
        SetHoneyLevel(inst, 3)
    end
    inst.components.workable:SetWorkable(true)
    inst:RemoveEventCallback("animover", OnHiveLongGrowAnimOver)
end

local function OnHiveGrowthTimer(inst, data)
    if data.name == "hivegrowth" or
        data.name == "shorthivegrowth" or
        data.name == "firsthivegrowth" then

        EnableBase(inst, false)

        U.log("OnHiveGrowthTimer: " .. tostring(data.name))
        local hive = SpawnPrefab("beequeenhivegrown")
        hive.Transform:SetPosition(inst.Transform:GetWorldPosition())
        if inst:IsAsleep() then
            if data.name == "shorthivegrowth" then
                hive.components.workable:SetWorkLeft(1)
                hive.components.timer:StartTimer("hiveregen", 8 * TUNING.SEG_TIME)
                SetHoneyLevel(hive, 0)
            end
        else
            if data.name == "hivegrowth" then
                hive.AnimState:PlayAnimation("grow_medium_to_large")
                hive:ListenForEvent("animover", OnHiveLongGrowAnimOver)
                SetHoneyLevel(hive, 3, 7 * FRAMES)
            elseif data.name == "shorthivegrowth" then
                hive.Physics:SetCapsule(PHYS_RAD_SML, 2)
                hive.AnimState:PlayAnimation("grow_hole_to_small")
                hive:ListenForEvent("animover", OnHiveShortGrowAnimOver)
                hive.components.workable:SetWorkLeft(1)
                hive.components.timer:StartTimer("hiveregen", 8 * TUNING.SEG_TIME)
                SetHoneyLevel(hive, 0)
            else--if data.name == "firsthivegrowth" then
                hive.Physics:SetCapsule(PHYS_RAD_SML, 2)
                hive.AnimState:PlayAnimation("grow_hole_to_small")
                hive:ListenForEvent("animover", OnHiveLongGrowAnimOver)
                SetHoneyLevel(hive, 1)
            end
            hive.SoundEmitter:PlaySound("dontstarve/creatures/together/bee_queen/hive_grow")
            hive.components.workable:SetWorkable(false)
        end

        hive.hivebase = inst
        inst.components.entitytracker:TrackEntity("hive", hive)
        inst:ListenForEvent("onremove", OnHiveRemoved, hive)
    elseif data.name == "hivegrowth1" then
        if inst:IsAsleep() then
            inst.AnimState:PlayAnimation("small")
        else
            inst.AnimState:PlayAnimation("grow_hole_to_small")
            inst.AnimState:PushAnimation("small", false)
            inst.SoundEmitter:PlaySound("dontstarve/creatures/together/bee_queen/hive_grow")
        end
        inst.AnimState:SetLayer(LAYER_WORLD)
        inst.AnimState:SetSortOrder(0)
        SetHoneyLevel(inst, 1)
        inst.components.timer:StartTimer("hivegrowth2", TUNING.BEEQUEEN_RESPAWN_TIME / 3)
    elseif data.name == "hivegrowth2" then
        if inst:IsAsleep() then
            inst.AnimState:PlayAnimation("medium")
            SetHoneyLevel(inst, 2)
        else
            inst.AnimState:PlayAnimation("grow_small_to_medium")
            inst.AnimState:PushAnimation("medium", false)
            SetHoneyLevel(inst, 2, 4 * FRAMES)
            inst.SoundEmitter:PlaySound("dontstarve/creatures/together/bee_queen/hive_grow")
        end
        inst.AnimState:SetLayer(LAYER_WORLD)
        inst.AnimState:SetSortOrder(0)
        inst.Physics:SetCapsule(PHYS_RAD_MED, 2)
        inst.components.timer:StartTimer("hivegrowth", TUNING.BEEQUEEN_RESPAWN_TIME / 3)
    end
end

local function OnBaseLoadPostPass(inst, newents, data)
    local hive = inst.components.entitytracker:GetEntity("hive")
    if hive ~= nil then
        hive.hivebase = inst
        StopHiveGrowthTimer(inst)
        EnableBase(inst, false)
        inst:ListenForEvent("onremove", OnHiveRemoved, hive)
    end

    local queen = inst.components.entitytracker:GetEntity("queen")
    if queen ~= nil then
        queen.hivebase = inst
        StopHiveGrowthTimer(inst)
        inst:ListenForEvent("onremove", OnQueenRemoved, queen)
    end
end

local function OnBaseLoad(inst, data)
    if data ~= nil and data.queenkilled then
        StopHiveGrowthTimer(inst)
        inst.queenkilled = true
        StartHiveGrowthTimer(inst)
    end

    if inst.components.timer:TimerExists("hivegrowth") then
        U.log("TimerExists: hivegrowth")
        inst.AnimState:PlayAnimation("medium")
        inst.AnimState:SetLayer(LAYER_WORLD)
        inst.AnimState:SetSortOrder(0)
        inst.Physics:SetCapsule(PHYS_RAD_MED, 2)
        SetHoneyLevel(inst, 2)
    elseif inst.components.timer:TimerExists("hivegrowth2") then
        U.log("TimerExists: hivegrowth2")
        inst.AnimState:PlayAnimation("small")
        inst.AnimState:SetLayer(LAYER_WORLD)
        inst.AnimState:SetSortOrder(0)
        SetHoneyLevel(inst, 1)
    elseif inst.components.timer:TimerExists("hivegrowth1")
        or inst.components.timer:TimerExists("shorthivegrowth") then
        U.log("TimerExists: hivegrowth1 or shorthivegrowth")
        inst.AnimState:PlayAnimation("hole_idle")
        inst.AnimState:SetLayer(LAYER_BACKGROUND)
        inst.AnimState:SetSortOrder(3)
        SetHoneyLevel(inst, 0)
    else
        return
    end
    inst.components.timer:StopTimer("firsthivegrowth")
end

local function OnBaseSave(inst, data)
    data.queenkilled = inst.queenkilled or nil
end

local function BaseGetStatus(inst)
    return not inst.AnimState:IsCurrentAnimation("hole_idle") and "GROWING" or nil
end

local function BaseDisplayNameFn(inst)
    return (not inst:IsValid() or inst.AnimState:IsCurrentAnimation("hole_idle")) and STRINGS.NAMES.BEEQUEENHIVE or STRINGS.NAMES.BEEQUEENHIVEGROWING
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddMiniMapEntity()

    MakeObstaclePhysics(inst, PHYS_RAD_LRG)

    inst.AnimState:SetBank("bee_queen_hive")
    inst.AnimState:SetBuild("bee_queen_hive")
    inst.AnimState:PlayAnimation("large")
    inst.AnimState:Hide("honey0")
    inst.AnimState:Hide("honey1")
    inst.AnimState:Hide("honey2")

    inst.Transform:SetScale(1.4, 1.4, 1.4)

    inst.MiniMapEntity:SetIcon("beequeenhivegrown.tex")

    inst:AddComponent("lootdropper")
    inst.components.lootdropper.alwaysinfront = true
    inst:AddComponent("inspectable")

    inst:AddComponent("timer")
    inst:ListenForEvent("timerdone", OnHiveRegenTimer)

    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetMaxWork(TUNING.BEEQUEEN_SPAWN_MAX_WORK)
    inst.components.workable:SetWorkLeft(TUNING.BEEQUEEN_SPAWN_MAX_WORK)
    inst.components.workable:SetOnWorkCallback(OnWorked)
    inst.components.workable.savestate = true

    inst.OnLoad = RefreshHoneyState

    return inst
end

local function base_fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddMiniMapEntity()

    MakeObstaclePhysics(inst, PHYS_RAD_SML, 2)
    
    inst.AnimState:SetBank("bee_queen_hive")
    inst.AnimState:SetBuild("bee_queen_hive")
    inst.AnimState:PlayAnimation("hole_idle")
    inst.AnimState:Hide("honey1")
    inst.AnimState:Hide("honey2")
    inst.AnimState:Hide("honey3")
    inst.AnimState:SetLayer(LAYER_BACKGROUND)
    inst.AnimState:SetSortOrder(3)

    inst.Transform:SetScale(1.4, 1.4, 1.4)

    inst.MiniMapEntity:SetIcon("beequeenhive.tex")

    inst.displaynamefn = BaseDisplayNameFn

    inst:AddComponent("inspectable")
    inst.components.inspectable.getstatus = BaseGetStatus

    inst:AddComponent("timer")
    inst.queenkilled = false
    inst.components.timer:StartTimer("firsthivegrowth", 10)
    inst:ListenForEvent("timerdone", OnHiveGrowthTimer)
    
    inst:AddComponent("entitytracker")

    inst.OnLoadPostPass = OnBaseLoadPostPass
    inst.OnLoad = OnBaseLoad
    inst.OnSave = OnBaseSave

    return inst
end

return Prefab("beequeenhive", base_fn, assets, base_prefabs),
    Prefab("beequeenhivegrown", fn, assets, prefabs)
