---@diagnostic disable: need-check-nil
local M = {}

M.debug = true

--- Prints with a prefix.
function M.log(...)
    if M.debug then
        print("[BeeQueenHive] ", ...)
    end
end

--- Safely calls a function and logs any errors.
---@param fn function
---@vararg any
---@return any The result of the function or nil if an error occurred
function M.safecall(fn, ...)
    local success, result = pcall(fn, ...)
    if success then return result end
    M.log("Error:", result)
    return nil
end

local enabledROG  = REIGN_OF_GIANTS and IsDLCEnabled(REIGN_OF_GIANTS)
local enabledSHIP = CAPY_DLC and IsDLCEnabled(CAPY_DLC)
local enabledPORK = PORKLAND_DLC and IsDLCEnabled(PORKLAND_DLC)
local enabledAnyDLC = enabledROG or enabledSHIP or enabledPORK
local vanilla = not enabledAnyDLC

-- Expose flags
M.enabledROG = enabledROG
M.enabledSHIP = enabledSHIP
M.enabledPORK = enabledPORK
M.enabledAnyDLC = enabledAnyDLC
M.vanilla = vanilla

if PlayFootstep then
    M.log("PlayFootstep found")
end

local WEB_FOOTSTEP_SOUNDS = {
	[CREATURE_SIZE.SMALL]	=	{ runsound = "run_web_small",		walksound = "walk_web_small" },
	[CREATURE_SIZE.MEDIUM]	=	{ runsound = "run_web",				walksound = "walk_web" },
	[CREATURE_SIZE.LARGE]	=	{ runsound = "run_web_large",		walksound = "walk_web_large" },
}

if not (enabledSHIP or enabledPORK) then
    local footstep_path = "dontstarve/movement/"

    for _, v in pairs(WEB_FOOTSTEP_SOUNDS) do
        v.runsound = footstep_path .. v.runsound
        v.walksound = footstep_path .. v.walksound
    end
end

function M.PlayFootstepDLC(inst, volume)
	volume = volume or 1
	
    local sound = inst.SoundEmitter
    if sound then
        local tile, tileinfo = inst:GetCurrentTileType()
        if inst.components.locomotor ~= nil and inst.components.locomotor:TempGroundTile() then
            M.log("Overriding footstep sound tile")
            tile = inst.components.locomotor:TempGroundTile()
            tileinfo = GetTileInfo(tile)
        end

        if tile and tileinfo then	
			local x, y, z = inst.Transform:GetWorldPosition()
            
            local onflood = nil
            local ontar = nil
            if M.enabledSHIP or M.enabledPORK then
    			ontar = inst.slowing_objects and next(inst.slowing_objects)
    			onflood = GetWorld().Flooding and GetWorld().Flooding:OnFlood( x, y, z )
            end
			local oncreep = GetWorld().GroundCreep:OnCreep( x, y, z )
			local onsnow = GetSeasonManager() and GetSeasonManager():GetSnowPercent() > 0.15
			
            local onmud = nil
            if M.enabledAnyDLC then
                onmud = GetWorld().components.moisturemanager:GetWorldMoisture() > 15
            end

            local ininterior = nil
            if M.enabledPORK then
    			ininterior = tile == GROUND.INTERIOR
            end
			--this is only for playerd for the time being because isonroad is suuuuuuuper slow.
			local onroad = inst:HasTag("player") and RoadManager ~= nil and RoadManager:IsOnRoad( x, 0, z )
			if onroad then
				tile = GROUND.ROAD
				tileinfo = GetTileInfo( GROUND.ROAD )
			end

            -- vanilla & ROG: tileinfo includes footstep_path
            local footstep_path = ""
            if M.enabledSHIP or M.enabledPORK then
			    footstep_path = inst.footstep_path_override or "dontstarve/movement/"
            end

			local creature_size = CREATURE_SIZE.MEDIUM
			local size_affix = ""
			if inst:HasTag("smallcreature") then
				creature_size = CREATURE_SIZE.SMALL
				size_affix = "_small"
			elseif inst:HasTag("largecreature") then
				creature_size = CREATURE_SIZE.LARGE
				size_affix = "_large"
			end
			
			if ininterior then
 				local interiorSpawner = GetWorld().components.interiorspawner
 				if interiorSpawner.current_interior then			
					tileinfo = GetTileInfo( interiorSpawner.current_interior.groundsound )
					if not tileinfo then						
						tileinfo = GetTileInfo( "DIRT" )				
					end
				end
			end

			if onsnow then
				sound:PlaySound(footstep_path .. tileinfo.snowsound .. size_affix, nil, volume)
			elseif onmud then
				sound:PlaySound(footstep_path .. tileinfo.mudsound .. size_affix, nil, volume)
			else
				if inst.sg and inst.sg:HasStateTag("running") then
					sound:PlaySound(footstep_path .. tileinfo.runsound .. size_affix, nil, volume)
				else
					sound:PlaySound(footstep_path .. tileinfo.walksound .. size_affix, nil, volume)
				end
			end

			if oncreep then
				sound:PlaySound(footstep_path .. WEB_FOOTSTEP_SOUNDS[ creature_size ].runsound, nil, volume)
			end
			if onflood then
				sound:PlaySound(footstep_path .. WEB_FOOTSTEP_SOUNDS[ creature_size ].runsound, nil, volume) --play this for now
			end

			if ontar then
				sound:PlaySound(footstep_path .. tileinfo.mudsound .. size_affix, nil, volume)
			end		
        end
    end
end

-- Stategraph functions
local function onsleepex(inst)
    inst.sg.mem.sleeping = true
	if inst.components.health == nil or not inst.components.health:IsDead() then
        if not inst.sg:HasAnyStateTag("nosleep", "sleeping") then
		    inst.sg:GoToState("sleep")
		end
    end
end

local function onwakeex(inst)
    inst.sg.mem.sleeping = false
    if inst.sg:HasStateTag("sleeping") and not inst.sg:HasStateTag("nowake") and
        not (inst.components.health ~= nil and inst.components.health:IsDead()) then
        inst.sg.statemem.continuesleeping = true
        inst.sg:GoToState("wake")
    end
end

M.OnSleepEx = function()
    return EventHandler("gotosleep", onsleepex)
end

M.OnWakeEx = function()
    return EventHandler("onwakeup", onwakeex)
end

M.OnNoSleepTimeEvent = function(t, fn)
    return TimeEvent(t, function(inst)
        if inst.sg.mem.sleeping and not (inst.components.health ~= nil and inst.components.health:IsDead()) then
            inst.sg:GoToState("sleep")
        elseif fn ~= nil then
            fn(inst)
        end
    end)
end

M.OnNoSleepAnimOver = function(nextstate)
    return EventHandler("animover", function(inst)
        if inst.AnimState:AnimDone() then
            if inst.sg.mem.sleeping then
                inst.sg:GoToState("sleep")
            elseif type(nextstate) == "string" then
                inst.sg:GoToState(nextstate)
            elseif nextstate ~= nil then
                nextstate(inst)
            end
        end
    end)
end


local function sleepexonanimover(inst)
    if inst.AnimState:AnimDone() then
        inst.sg.statemem.continuesleeping = true
        inst.sg:GoToState(inst.sg.mem.sleeping and "sleeping" or "wake")
    end
end

local function sleepingexonanimover(inst)
    if inst.AnimState:AnimDone() then
        inst.sg.statemem.continuesleeping = true
        inst.sg:GoToState("sleeping")
    end
end

local function wakeexonanimover(inst)
    if inst.AnimState:AnimDone() then
        inst.sg:GoToState(inst.sg.mem.sleeping and "sleep" or "idle")
    end
end

M.AddSleepExStates = function(states, timelines, fns)
    table.insert(states, State{
        name = "sleep",
        tags = { "busy", "sleeping", "nowake" },

        onenter = function(inst)
            if inst.components.locomotor ~= nil then
                inst.components.locomotor:StopMoving()
            end
            inst.AnimState:PlayAnimation("sleep_pre")
            if fns ~= nil and fns.onsleep ~= nil then
                fns.onsleep(inst)
            end
        end,

        timeline = timelines ~= nil and timelines.starttimeline or nil,

        events =
        {
            EventHandler("animover", sleepexonanimover),
        },

        onexit = function(inst)
            if not inst.sg.statemem.continuesleeping and inst.components.sleeper ~= nil and inst.components.sleeper:IsAsleep() then
                inst.components.sleeper:WakeUp()
            end
            if fns ~= nil and fns.onexitsleep ~= nil then
                fns.onexitsleep(inst)
            end
        end,
    })

    table.insert(states, State{
        name = "sleeping",
        tags = { "busy", "sleeping" },

        onenter = function(inst)
            inst.AnimState:PlayAnimation("sleep_loop")
            if fns ~= nil and fns.onsleeping ~= nil then
                fns.onsleeping(inst)
            end
        end,

        timeline = timelines ~= nil and timelines.sleeptimeline or nil,

        events =
        {
            EventHandler("animover", sleepingexonanimover),
        },

        onexit = function(inst)
            if not inst.sg.statemem.continuesleeping and inst.components.sleeper ~= nil and inst.components.sleeper:IsAsleep() then
                inst.components.sleeper:WakeUp()
            end
            if fns ~= nil and fns.onexitsleeping ~= nil then
                fns.onexitsleeping(inst)
            end
        end,
    })

    table.insert(states, State{
        name = "wake",
        tags = { "busy", "waking", "nosleep" },

        onenter = function(inst)
            if inst.components.locomotor ~= nil then
                inst.components.locomotor:StopMoving()
            end
            inst.AnimState:PlayAnimation("sleep_pst")
            if inst.components.sleeper ~= nil and inst.components.sleeper:IsAsleep() then
                inst.components.sleeper:WakeUp()
            end
            if fns ~= nil and fns.onwake ~= nil then
                fns.onwake(inst)
            end
        end,

        timeline = timelines ~= nil and timelines.waketimeline or nil,

        events =
        {
            EventHandler("animover", wakeexonanimover),
        },

        onexit = fns ~= nil and fns.onexitwake or nil,
    })
end

local function onunfreeze(inst)
    inst.sg:GoToState(inst.sg.sg.states.hit ~= nil and "hit" or "idle")
end

local function onthaw(inst)
	inst.sg.statemem.thawing = true
    inst.sg:GoToState("thaw")
end

local function onenterfrozenpre(inst)
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:StopMoving()
    end
    inst.AnimState:PlayAnimation("frozen", true)
    inst.SoundEmitter:PlaySound("dontstarve/common/freezecreature")
    inst.AnimState:OverrideSymbol("swap_frozen", "frozen", "frozen")
end

local function onenterfrozenpst(inst)
    if inst.components.freezable == nil then
        onunfreeze(inst)
    elseif inst.components.freezable:IsThawing() then
        onthaw(inst)
    elseif not inst.components.freezable:IsFrozen() then
        onunfreeze(inst)
    end
end

local function onexitfrozen(inst)
	if not inst.sg.statemem.thawing then
		inst.AnimState:ClearOverrideSymbol("swap_frozen")
	end
end

local function onenterthawpre(inst)
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:StopMoving()
    end
    inst.AnimState:PlayAnimation("frozen_loop_pst", true)
    inst.SoundEmitter:PlaySound("dontstarve/common/freezethaw", "thawing")
    inst.AnimState:OverrideSymbol("swap_frozen", "frozen", "frozen")
end

local function onenterthawpst(inst)
    if inst.components.freezable == nil or not inst.components.freezable:IsFrozen() then
        onunfreeze(inst)
    end
end

local function onexitthaw(inst)
    inst.SoundEmitter:KillSound("thawing")
    inst.AnimState:ClearOverrideSymbol("swap_frozen")
end

M.AddFrozenStates = function(states, onoverridesymbols, onclearsymbols)
    table.insert(states, State{
        name = "frozen",
        tags = { "busy", "frozen" },

        onenter = function(inst)
            onenterfrozenpre(inst)
            onoverridesymbols(inst)
            onenterfrozenpst(inst)
        end,

        events =
        {
            EventHandler("unfreeze", onunfreeze),
            EventHandler("onthaw", onthaw),
        },

        onexit = onclearsymbols ~= nil and function(inst)
            onexitfrozen(inst)
            onclearsymbols(inst)
        end or onexitfrozen,
    })

    table.insert(states, State{
        name = "thaw",
        tags = { "busy", "thawing" },

        onenter = function(inst)
            onenterthawpre(inst)
            onoverridesymbols(inst)
            onenterthawpst(inst)
        end,

        events =
        {
            EventHandler("unfreeze", onunfreeze),
        },

        onexit = function(inst)
            onexitthaw(inst)
            onclearsymbols(inst)
        end,
    })
end
return M
