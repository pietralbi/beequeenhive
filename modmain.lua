-- UTILS
local STRINGS = GLOBAL.STRINGS
local TUNING = GLOBAL.TUNING
local enabledROG = GLOBAL.IsDLCEnabled(GLOBAL.REIGN_OF_GIANTS)
local enabledSHIP = GLOBAL.rawget(GLOBAL, "CAPY_DLC") and GLOBAL.IsDLCEnabled(GLOBAL.CAPY_DLC)
local enabledPORK = GLOBAL.rawget(GLOBAL, "PORKLAND_DLC") and GLOBAL.IsDLCEnabled(GLOBAL.PORKLAND_DLC)
local enabledAnyDLC = enabledROG or enabledSHIP or enabledPORK
local vanilla = not enabledAnyDLC
local require = GLOBAL.require

local seg_time = 30
local total_day_time = seg_time*16
local day_segs = 10
local dusk_segs = 4
local night_segs = 2
local day_time = seg_time * day_segs
local dusk_time = seg_time * dusk_segs
local night_time = seg_time * night_segs

local MAX_INT = 2^53
local DEBUG = false

Assets = {
    Assets, Asset("ATLAS", "minimap/beequeenhive.xml"),
    Assets, Asset("ATLAS", "minimap/beequeenhivegrown.xml")
--  Asset("SOUND", "sound/beequeenhive.fsb"),
--	Asset("SOUNDPACKAGE", "sound/beequeenhive.fev"),
}

PrefabFiles = {
    "beequeenhive",
    "honeysplash",
    "beequeen",
    "beeguard",
    "honey_trail"
}

local U = require("beequeenhive_utils")

local DEPLOY_IGNORE_TAGS = { "NOBLOCK", "player", "FX", "INLIMBO", "DECOR" }

local function GetBeehiveClusterScore(hive, cluster_radius)
    if hive == nil or hive.Transform == nil then
        return 0
    end
    local x, y, z = hive.Transform:GetWorldPosition()
    -- Find beehives nearby (including itself)
    local ents = GLOBAL.TheSim:FindEntities(x, y, z, cluster_radius, nil, DEPLOY_IGNORE_TAGS)
    local n = 0
    for _, e in ipairs(ents) do
        if e ~= nil and e.IsValid ~= nil and e:IsValid() and e.prefab == "beehive" then
            n = n + 1
        end
    end
    -- exclude itself if present
    if n > 0 then
        n = n - 1
    end
    return n
end

local function ChooseBeehivePreferClusters(beehives, cluster_radius)
    -- Weighted random: weight = 1 + score (so isolated hives still possible)
    local weights = {}
    local total = 0
    for i, hive in ipairs(beehives) do
        local score = GetBeehiveClusterScore(hive, cluster_radius)
        local w = 1 + score
        weights[i] = w
        total = total + w
    end

    local r = math.random() * total
    local acc = 0
    for i, w in ipairs(weights) do
        acc = acc + w
        if r <= acc then
            U.log("Selecting beehive with score " .. w)
            return beehives[i]
        end
    end
    return beehives[math.random(#beehives)]
end

local function IsClearOfEntities(x, y, z, radius, ignore_ent)
    if radius == nil then
        return true
    end
    local ents = GLOBAL.TheSim:FindEntities(x, y, z, radius, nil, DEPLOY_IGNORE_TAGS)
    for _, e in ipairs(ents) do
        if e ~= nil and e ~= ignore_ent and e.IsValid ~= nil and e:IsValid() then
            return false
        end
    end
    return true
end

local function IsFarFromStructures(x, y, z, radius, ignore_ent)
    if radius == nil then
        return true
    end
    local ents = GLOBAL.TheSim:FindEntities(x, y, z, radius, { "structure" }, DEPLOY_IGNORE_TAGS)
    for _, e in ipairs(ents) do
        if e ~= nil and e ~= ignore_ent and e.IsValid ~= nil and e:IsValid() then
            return false
        end
    end
    return true
end

local function AddNewPrefab(inst, prefab, anchor_prefab, min_space, max_space, dist_from_structures, canplacefn, on_add_prefab, skip_if_any_prefabs_exist)
    local MAX_PLACEMENT_ATTEMPTS = 100

    local world = inst or (GLOBAL.GetWorld ~= nil and GLOBAL.GetWorld()) or nil
    if world == nil then
        U.log("AddNewPrefab: world is nil")
        return false
    end

    -- If any of these prefabs already exist in the world, skip placement entirely.
    if type(skip_if_any_prefabs_exist) == "table" and GLOBAL.Ents ~= nil then
        local wanted = {}
        for _, p in ipairs(skip_if_any_prefabs_exist) do
            if type(p) == "string" and p ~= "" then
                wanted[p] = true
            end
        end

        if GLOBAL.next(wanted) ~= nil then
            for _, e in pairs(GLOBAL.Ents) do
                if e ~= nil and e.IsValid ~= nil and e:IsValid() then
                    local ep = e.prefab
                    if ep ~= nil and wanted[ep] then
                        U.log("AddNewPrefab: Skipping spawn of " .. tostring(prefab)
                            .. " because " .. tostring(ep) .. " already exists.")
                        return true
                    end
                end
            end
        end
    end

    -- Collect anchor beehives from the live entity table
    local beehives = {}
    if GLOBAL.Ents ~= nil then
        for _, e in pairs(GLOBAL.Ents) do
            if e ~= nil and e.prefab == anchor_prefab and e.IsValid ~= nil and e:IsValid() then
                table.insert(beehives, e)
            end
        end
    end

    if #beehives == 0 then
        U.log("Adding prefab " .. prefab .. ": Failed (no beehive anchors found).")
        return false
    end

    local attempt = 1
    while attempt <= MAX_PLACEMENT_ATTEMPTS do
        local CLUSTER_RADIUS = 60
        local anchor = ChooseBeehivePreferClusters(beehives, CLUSTER_RADIUS)
        local ax, ay, az = anchor.Transform:GetWorldPosition()

        -- Use min_space as a reasonable default radius to search around the anchor.
        -- If you want it closer/farther, pass a different min_space value.
        min_space = (type(min_space) == "number" and min_space > 0) and min_space or 4
        max_space = (type(max_space) == "number" and max_space > 0) and max_space or 10
        local radius = min_space + (max_space - min_space) * math.random()

        local theta = math.random() * 2 * GLOBAL.PI
        local pt = GLOBAL.Vector3(ax, ay, az)

        -- DS placement primitive: returns an offset Vector3 or nil
        local offset = GLOBAL.FindWalkableOffset(pt, theta, radius, 10, true)
        if offset ~= nil then
            local x = pt.x + offset.x
            local y = pt.y + offset.y
            local z = pt.z + offset.z
            local is_clear = IsClearOfEntities(x, y, z, min_space, anchor)
            local is_far = IsFarFromStructures(x, y, z, dist_from_structures, anchor)

            if (canplacefn == nil or canplacefn(x, y, z, prefab)) and is_clear and is_far
                 then
                local e = GLOBAL.SpawnPrefab(prefab)
                if e ~= nil then
                    e.Transform:SetPosition(x, y, z)
                    if on_add_prefab ~= nil then
                        on_add_prefab(e, anchor)
                    end
                    U.log("Adding prefab " .. prefab .. ": Success after " .. attempt .. " attempts.")
                    return true
                end
            end
        end

        attempt = attempt + 1
    end

    U.log("Adding prefab " .. prefab .. ": Failed.")
    return false
end

local function GroundNameFromId(id)
    for name, value in pairs(GLOBAL.GROUND) do
        if value == id then
            return name
        end
    end
end

local function test_ground(x, y, z, prefab)
	local tiletype = GLOBAL.GetGroundTypeAtPosition(GLOBAL.Vector3(x,y,z))
    U.log("Attempting to spawn on tile " .. GroundNameFromId(tiletype))
	local ground_OK = tiletype ~= GLOBAL.GROUND.ROAD and
                    tiletype ~= GLOBAL.GROUND.ROCKY and
                    tiletype ~= GLOBAL.GROUND.IMPASSABLE and
					tiletype ~= GLOBAL.GROUND.UNDERROCK and
                    tiletype ~= GLOBAL.GROUND.WOODFLOOR and
					tiletype ~= GLOBAL.GROUND.CARPET and
                    tiletype ~= GLOBAL.GROUND.CHECKER and
                    tiletype < GLOBAL.GROUND.UNDERGROUND
    return ground_OK
end

AddPrefabPostInit("forest", function(inst)
    inst:DoTaskInTime(0, function()
        local tries = 0
        local function Try()
            tries = tries + 1

            local skip_if_any_prefabs_exist = {"beequeenhive", "beequeenhivegrown", "beequeen"}
            local ok = AddNewPrefab(inst, "beequeenhive", "beehive", 12.0, 30.0, 12.0, test_ground, nil, skip_if_any_prefabs_exist)
            if ok then
                return
            end

            -- If beehives aren't spawned yet, keep retrying briefly
            if tries < 20 then
                inst:DoTaskInTime(1, Try)
            end
        end
        Try()
    end)
end)

modimport("scripts/strings/beequeenhive_strings.lua")

TUNING.BEEQUEEN_HEALTH = 2250
TUNING.BEEQUEEN_DAMAGE = 120
TUNING.BEEQUEEN_ATTACK_PERIOD = 2
TUNING.BEEQUEEN_ATTACK_RANGE = 4
TUNING.BEEQUEEN_HIT_RANGE = 6
TUNING.BEEQUEEN_SPEED = 4
TUNING.BEEQUEEN_HIT_RECOVERY = 1
TUNING.BEEQUEEN_MIN_GUARDS_PER_SPAWN = 4
TUNING.BEEQUEEN_MAX_GUARDS_PER_SPAWN = 5
TUNING.BEEQUEEN_TOTAL_GUARDS = 8
TUNING.BEEQUEEN_CHASE_TO_RANGE = 8
TUNING.BEEQUEEN_MAX_STUN_LOCKS = 4

TUNING.BEEQUEEN_DODGE_SPEED = 6
TUNING.BEEQUEEN_DODGE_HIT_RECOVERY = 2
TUNING.BEEQUEEN_AGGRO_DIST = 15
TUNING.BEEQUEEN_DEAGGRO_DIST = 60
TUNING.BEEQUEEN_RESPAWN_TIME = total_day_time * 20
TUNING.BEEQUEEN_SPAWN_WORK_THRESHOLD = 12
TUNING.BEEQUEEN_SPAWN_MAX_WORK = 16
TUNING.BEEQUEEN_EPICSCARE_RANGE = 10
TUNING.BEEQUEEN_SPAWNGUARDS_CD = { 18, 16, 7, 12 }
TUNING.BEEQUEEN_SPAWNGUARDS_CHAIN = { 0, 1, 0, 1 }
TUNING.BEEQUEEN_FOCUSTARGET_CD = { 0, 0, 20, 16 }
TUNING.BEEQUEEN_FOCUSTARGET_RANGE = 20
TUNING.BEEQUEEN_HONEYTRAIL_SPEED_PENALTY = 0.4

TUNING.BEEGUARD_HEALTH = 180
TUNING.BEEGUARD_DAMAGE = 30
TUNING.BEEGUARD_ATTACK_PERIOD = 2
TUNING.BEEGUARD_ATTACK_RANGE = 1.5
TUNING.BEEGUARD_SPEED = 3
TUNING.BEEGUARD_GUARD_RANGE = 4
TUNING.BEEGUARD_AGGRO_DIST = 12

TUNING.BEEGUARD_SQUAD_SIZE = 3
TUNING.BEEGUARD_DASH_SPEED = 8
TUNING.BEEGUARD_PUFFY_DAMAGE = 40
TUNING.BEEGUARD_PUFFY_ATTACK_PERIOD = 1.5
TUNING.BOOK_BEES_MAX_ATTACK_RANGE = 5

-- Extend locomotor component
AddComponentPostInit("locomotor", function(LocoMotor)
    LocoMotor.tempgroundspeedmultiplier = nil
    LocoMotor.tempgroundspeedmulttime = nil
    LocoMotor.tempgroundtile = nil

    local orig_GetSpeedMultiplier = LocoMotor.GetSpeedMultiplier
    function LocoMotor:GetSpeedMultiplier()
        local multiplier = orig_GetSpeedMultiplier(self)
        -- Needs to substitute self.groundspeedmultiplier, not multiply it
        if self.tempgroundspeedmultiplier then
            multiplier = multiplier / (self.groundspeedmultiplier or 1)
            multiplier = multiplier * self:TempGroundSpeedMultiplier()
        end
        return multiplier
    end

    -- Override to set tempground variables
    function LocoMotor:EnableGroundSpeedMultiplier(enable)
        self.enablegroundspeedmultiplier = enable
        if not enable then
            self.groundspeedmultiplier = 1
            self.tempgroundspeedmultiplier = nil
            self.tempgroundspeedmulttime = nil
            self.tempgroundtile = nil
        end
    end

    -- New functions
    function LocoMotor:PushTempGroundSpeedMultiplier(mult, tile)
        if self.enablegroundspeedmultiplier then
            local t = GLOBAL.GetTime()
            if self.tempgroundspeedmultiplier == nil or
                t > self.tempgroundspeedmulttime or
                mult <= self.tempgroundspeedmultiplier then
                self.tempgroundspeedmultiplier = mult
                self.tempgroundtile = tile
            end
            self.tempgroundspeedmulttime = t
        end
    end

    function LocoMotor:TempGroundSpeedMultiplier()
        if self.tempgroundspeedmultiplier ~= nil then
            if self.tempgroundspeedmulttime + 0.034 > GLOBAL.GetTime() then
                return self.tempgroundspeedmultiplier
            end
            self.tempgroundspeedmultiplier = nil
            self.tempgroundspeedmulttime = nil
            self.tempgroundtile = nil
        end
    end

    function LocoMotor:TempGroundTile()
        if self.tempgroundtile ~= nil then
            if self.tempgroundspeedmulttime + 0.034 > GLOBAL.GetTime() then
                return self.tempgroundtile
            end
            self.tempgroundspeedmultiplier = nil
            self.tempgroundspeedmulttime = nil
            self.tempgroundtile = nil
        end
    end
end)

-- Extend combat component
AddComponentPostInit("combat", function(Combat)
    -- New lastwasattackedtime behaviour

    Combat.lastwasattackedtime = 0
    local orig_GetAttacked = Combat.GetAttacked
    function Combat:GetAttacked(...)
        if not (self.inst.components.health and self.inst.components.health:IsDead()) then
            self.lastwasattackedtime = GLOBAL.GetTime()
        end
        return orig_GetAttacked(self, ...)
    end

    function Combat:GetLastAttackedTime()
        return self.lastwasattackedtime
    end
end)

GLOBAL.orig_PlayFootstep = GLOBAL.PlayFootstep
GLOBAL.PlayFootstep = U.PlayFootstepDLC