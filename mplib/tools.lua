--- Multiplayer Tool & Loot System
--
-- Server-side system for managing tools, loot crates, and dropped weapons
-- in multiplayer matches.
--
-- Responsibilities:
--
-- * Define and manage respawnable loot tiers (tool spawn points)
-- * Drop tools with remaining ammo when players die
-- * Spawn and manage physical tool bundles (crates and loose drops)
-- * Handle tool pickup from world entities
--

#include "script/include/player.lua"
#include "script/toolutilities.lua"

_toolState = {}

--- Initialize the tool system (server).
--
-- Resets all loot tiers and tool bundles, sets default configuration, and
-- precomputes tool pickup data used by crates and drops.
function toolsInit()
    toolsCleanup()
    setupToolsUpgradedFully()
	_refillSound = LoadSound("tool_pickup.ogg")
    _toolState = { currComparePlayerIndex = 0, lootTiers = {}, lootTools = {}, respawnTime = 10.0, despawnTime = 30.0, despawnRange = 30.0, dropToolsOnDeath=true, toolBundles={}, notDroppableTools = {} }
    _initiateToolPickupData()
end

--- Set the loot respawn time for all tiers (server).
--
-- Controls how long it takes for a loot spawn point to refill after its
-- previous tool has despawned or been picked up.
--
-- @param[type=number] respawnTime  Time in seconds before loot respawns
function toolsSetRespawnTime(respawnTime)
    _toolState.respawnTime = respawnTime
end


--- Enable or disable dropping tools on player death (server).
--
-- When enabled, tools with remaining ammo are spawned as world drops when
-- a player dies.
--
-- @param[type=boolean] dropTools  `true` to enable tool drops; `false` to disable
function toolsSetDropToolsOnDeath(dropTools)
    _toolState.dropToolsOnDeath = dropTools
end

--- Prevent a specific tool from being dropped on death (server).
--
-- Marks a tool ID as non-droppable even if `toolsSetDropToolsOnDeath(true)`
-- is active.
--
-- @param[type=string] toolId  Tool ID to prevent from dropping
function toolsPreventToolDrop(toolId)
    _toolState.notDroppableTools[toolId] = true
end

--- Add all custom (mod-defined) tools to a loot table.
--
-- Scans `game.tool` for tools marked with `custom=true` and inserts them
-- into the provided loot table if they are not already present.
-- A default pickup amount is determined from tool config or falls back
-- to a sensible default.
--
-- Can be called on server or client, but typically used when building
-- server loot tables.
--
-- @param[type=table] lootTable A list of loot entries to extend
-- @param[opt,type=number] weight Spawn weight to assign to each added tool (default: 3)
function toolsAddModToolsToLootTable(lootTable, weight)
    local existing = {}
    for i, entry in ipairs(lootTable) do
        existing[entry.name] = true
    end

    weight = weight or 3

    local tools = ListKeys("game.tool")
    for i = 1, #tools do
        local toolId = tools[i]
        local toolKey = "game.tool."..toolId
        if GetBool(toolKey..".custom") and not existing[toolId] then
            local pickupAmount = GetToolAmmoPickupAmount(toolId)
            if pickupAmount <= 0 then pickupAmount = 20 end
            table.insert(lootTable, {
                name = toolId,
                weight = weight,
                amount = pickupAmount
            })
        end
    end
end

--- Add a new loot tier with multiple spawn points (server).
-- A loot tier is a collection of spawn locations and tools with individual spawn configurations.
--
-- @usage
-- lootTables = {}
-- lootTables[1] = {	
--     {name = "steroid", weight = 10, amount = 4},
--     {name = "plank", weight = 2, amount = 5}
-- }
-- lootTables[2] = {
--     {name = "shotgun", weight = 7},
--     {name = "gun", weight = 7},
--     {name = "bomb", weight = 5}
-- }
-- lootTables[3] = {
--     {name = "rifle", weight = 9},
--     {name = "pipebomb", weight = 5},
--     {name = "rocket", weight = 10},
--     {name = "explosive", weight = 5}
-- }
-- toolsAddLootTier(toolSpawns[1], lootTables[1])
-- toolsAddLootTier(toolSpawns[2], lootTables[2])
-- toolsAddLootTier(toolSpawns[3], lootTables[3])
--
-- @param[type=table] transforms  List of TTransform spawn locations
-- @param[type=table] lootTable   List of loot entries
function toolsAddLootTier(transforms, lootTable)
    _toolState.lootTiers[1 + #_toolState.lootTiers] = { lootTable = lootTable, loot={} }
    
    local newIndex = #_toolState.lootTiers
    local lootList = _toolState.lootTiers[newIndex].loot
    
    for i=1,#transforms do
        lootList[1 + #lootList] = { transform=transforms[i], body=nil, timer=(math.random() * _toolState.despawnTime * 0.5) } -- Stagger the inital spawning of Tool crates
    end
end

--- Clean up all active tool bundles and reset loot tiers (server).
--
-- Deletes all spawned tool entities via `_cleanUpToolBundle` and clears the
-- loot tier definitions. Typically called when starting a new match or
-- re-initializing the system.
function toolsCleanup()
    
    if not _toolState.lootTiers then return end 
    
    for i=1,#_toolState.toolBundles do
        _cleanUpToolBundle(_toolState.toolBundles[i])
    end
    
    _toolState.lootTiers = {}
end

--- Main server update loop for the tool system (server).
--
-- Should be called once per frame. Handles:
-- * Despawning tool bundles when all players are far away
-- * Ticking loot tiers and spawning new crates when timers expire
-- * Dropping tools on player death
-- * Handling player interaction with ammo/tool pickup bodies
--
-- @param[type=number] dt  Delta time in seconds
function toolsTick(dt)
    
    local players = GetAllPlayers()
    _toolState.currComparePlayerIndex = _toolState.currComparePlayerIndex + 1
    if _toolState.currComparePlayerIndex > #players then
        _toolState.currComparePlayerIndex = 1
    end

    local playerComparePos = GetPlayerTransform(players[_toolState.currComparePlayerIndex]).pos

    for i=#_toolState.toolBundles,1,-1 do
        if not IsHandleValid(_toolState.toolBundles[i].body) then
            _cleanUpToolBundle(_toolState.toolBundles[i])
            table.remove(_toolState.toolBundles, i)
        else
            local dist = VecLength(VecSub(GetBodyTransform(_toolState.toolBundles[i].body).pos, playerComparePos))

            if dist < _toolState.despawnRange then
                _toolState.toolBundles[i].distantPlayerCounter = 0
            else
                _toolState.toolBundles[i].distantPlayerCounter = _toolState.toolBundles[i].distantPlayerCounter + 1
            end

            if _toolState.toolBundles[i].distantPlayerCounter >= #players then
                _toolState.toolBundles[i].despawn = _toolState.toolBundles[i].despawn + dt
                
                if _toolState.toolBundles[i].despawn > _toolState.despawnTime then
                    _cleanUpToolBundle(_toolState.toolBundles[i])
                    table.remove(_toolState.toolBundles, i)
                end
            end
        end
    end
    
    for i=1,#_toolState.lootTiers do
        _tickLootTable(dt, _toolState.lootTiers[i].lootTable, _toolState.lootTiers[i].loot)
    end
    
    if _toolState.dropToolsOnDeath then
        local c = GetEventCount("playerdied")
        for i=1,c do
            local victim, _, _, _, _ = GetEvent("playerdied", i)

            local tools = ListKeys("game.tool")

            for i=1,#tools do
                local toolId = tools[i]
                if _toolsIsDroppable(toolId) and IsToolEnabled(toolId, victim) then
                    --only throw out tools with ammo left
                    local toolAmmo = GetToolAmmo(toolId, victim)
                    if toolAmmo > 0 then
                        --setup the spawn location
                        local t = GetPlayerTransform(victim)
                        t.pos[2] = t.pos[2] + 1.0
                        local offset = VecScale(VecNormalize(Vec(-1.0 + 2.0 * math.random(), -1.0 + 2.0 * math.random(), -1.0 + 2.0 * math.random())), 0.5)
                        t.pos = VecAdd(t.pos, offset)
                        
                        local bundle = _spawnToolDrop(toolId, t, toolAmmo)                        
                        _applyImpulse(bundle.body, GetRandomDirection(100))
                        _toolState.toolBundles[1 + #_toolState.toolBundles] = bundle
                    end
                end
                
                SetToolEnabled(toolId, false, victim)
                SetToolAmmo(toolId, 0, victim)
            end
        end
    end
    
    for p in Players() do
        if GetPlayerHealth(p) > 0 and InputPressed("interact", p) then
            interactBody = GetPlayerInteractBody(p)
            if HasTag(interactBody, "mp-builtin-ammo") then
                PlaySound(_refillSound, GetBodyTransform(interactBody).pos)

                local amount = GetTagValue(interactBody, "amount")
                local tool = GetTagValue(interactBody, "tool")

                local newAmount = amount
                local isNewTool = true
                if IsToolEnabled(tool, p) then
                    newAmount = GetToolAmmo(tool, p) + amount
                    isNewTool = false
                else
                    SetToolEnabled(tool, true, p)
                end

                SetToolAmmo(tool, newAmount, p)

                if isNewTool then
                    SetPlayerTool(tool, p)
                end

                Delete(interactBody)
            end
        end
    end
end

-- Internal functions

function _tickLootTable(dt, lootTable, loot)
    
    local weightSum = 0
    for i=1,#lootTable do
        weightSum = weightSum + lootTable[i].weight
    end
    
    for s=1,#loot do
        if IsHandleValid(loot[s].body) then
            loot[s].timer = _toolState.respawnTime
        else
            loot[s].timer = loot[s].timer - dt
            
            if loot[s].timer <= 0 then
                loot[s].timer = _toolState.respawnTime
                
                local rnd = GetRandomFloat(0.0, weightSum)
                
                local toolId = nil
                local amount = nil
                
                local sum = 0
                for i=1,#lootTable do
                    sum = sum + lootTable[i].weight
                    if rnd < sum then
                        toolId = lootTable[i].name
                        amount = lootTable[i].amount
                        break
                    end
                end
                
                local bundle = _spawnToolCrate(toolId, Transform(loot[s].transform.pos), amount)
                if bundle ~= nil then
                    loot[s].body = bundle.body
                    _toolState.toolBundles[1 + #_toolState.toolBundles] = bundle
                end
            end
        end
    end
end

function _makeToolBundle(entities)
    local body = 0
    for i=1,#entities do
        if GetEntityType(entities[i]) == "body" then
            body = entities[i]
        end
    end
    return { body=body, entities=entities, despawn=0.0, distantPlayerCounter = 0 }
end

function _cleanUpToolBundle(bundle)
    for i=1,#bundle.entities do
        Delete(bundle.entities[i])
    end
end

function _spawnToolCrate(toolId, transform, amount)
    if amount == nil then
        amount = GetToolAmmoPickupAmount(toolId)
        if amount <= 0 then
            amount = 20 -- Default pickup amount
        end
    end
    
    local entities = nil
    if GetBool("game.tool."..toolId..".custom") then
        entities = _spawnCustomToolCrate(toolId, transform)
    else
        entities = Spawn("ammo/mp/"..toolId..".xml", transform)
    end
    if entities == nil or #entities == 0 then
        return nil
    end

    local bundle = _makeToolBundle(entities)
    SetTag(bundle.body, "amount", amount)
    return bundle
end

function _spawnToolDrop(toolId, transform, ammo)
    
    local entities = SpawnTool(toolId, transform, false, _toolData[toolId].scale)
    local toolBody = _getLastEntityOfType(entities, "body")
	_centerOrigin(toolBody)
    
    local bundle = _makeToolBundle(entities)
    local name = GetString("game.tool."..toolId..".name")
    SetTag(bundle.body, "mp-builtin-ammo")
    SetTag(bundle.body, "amount", ammo)
    SetTag(bundle.body, "tool", toolId)
    SetTag(bundle.body, "interact", "loc@PICK_UP")
    SetTag(bundle.body, "desc", name)
    return bundle
end

function _spawnCustomToolCrate(toolId, transform)

    local toolData = _toolData[toolId]

    if not toolData then
        return nil
    end

    local entities = SpawnTool(toolId, Transform(), false, toolData.scale)
    local toolBody = _getLastEntityOfType(entities, "body")
	_centerOrigin(toolBody)

    local name = GetString("game.tool."..toolId..".name")
    local crateEntities = Spawn(
    "<prefab version='1.2.0'>" ..
    "<group name='instance=ammo/custom.xml' pos='-8.7 15.4 1.9' rot='0.0 0.0 0.0'>" ..
    "<body tags='mp-builtin-ammo unbreakable tool="..toolId.." interact=loc@PICK_UP' pos='0.0 0.5 0.0' dynamic='true' desc='"..name.."'>" ..
    "<vox pos='0.0 -0.5 0.0' rot='0.0 0.0 0.0' file='prop/toolcrate_open.vox' object='small_no-prefab_fallback'>" ..
    "<light pos='0.0 2.0 0.0'/>" ..
    "</vox>" ..
    "</body>" ..
    "</group>" ..
    "</prefab>", Transform())
    local crateTopMiddle = Vec(0, 0.5, 0.0)

    local crateBody = _getLastEntityOfType(crateEntities, "body")

    local toolShapes = GetBodyShapes(toolBody)
    for index, shape in ipairs(toolShapes) do
        local t = GetShapeLocalTransform(shape);

        -- Create tool pose. Long tools pointing up with an angle

        local q = nil
		if toolData.axis == 1 then
			q = QuatAxisAngle(Vec(0,0,1), 80.0)
		elseif toolData.axis == 2 then
			q = QuatAxisAngle(Vec(0,0,1), 20.0)
		elseif toolData.axis == 3 then
			q = QuatAxisAngle(Vec(1,0,0), 80.0)
		end

		q = QuatRotateQuat(QuatAxisAngle(Vec(0,1,0), 10.0), q)
		t = TransformToParentTransform(Transform(Vec(), q), t)

        -- Place tool in the top middle of the crate. Move up if it doesn't fit.
        local size2 = (toolData.axisSize * toolData.scale) * 0.5
		if size2 > 0.5 then
            local offsetAxis = nil
            if toolData.axis == 1 then
                offsetAxis = Vec(1,0,0)
            elseif toolData.axis == 2 then
                offsetAxis = Vec(0,1,0)
            elseif toolData.axis == 3 then
                offsetAxis = Vec(0,0,-1)
            end
            local v = TransformToParentVec(Transform(Vec(), q), offsetAxis)
            t.pos = VecAdd(t.pos, VecScale(v, size2 - 0.5))
		end
        t.pos = VecAdd(t.pos, crateTopMiddle)

        SetShapeBody(shape, crateBody, t)
    end

    for i = 1, #crateEntities do
        table.insert(entities, crateEntities[i])
    end

    min, max = GetBodyBounds(crateBody)
    transform.pos[2] = transform.pos[2] + 0.55
    SetBodyTransform(crateBody, transform)

    return entities
end

function _centerOrigin(body)
	local bt = GetBodyTransform(body)
	local min, max = GetBodyBounds(body)
	local center = VecLerp(min, max, 0.5)
	center = TransformToLocalPoint(bt, center)

	local toCenter = Transform(center)

	local shapes = GetBodyShapes(body)
	for index, shape in ipairs(shapes) do
		local st = GetShapeLocalTransform(shape)
		st = TransformToLocalTransform(toCenter, st)
		SetShapeLocalTransform(shape, st)
	end
end

function _getLastEntityOfType(entities, type)

    for i = #entities, 1, -1 do
        if GetEntityType(entities[i]) == type then
            return entities[i]
        end
    end

    return nil
end

function _applyImpulse(body, impulse)
    if IsHandleValid(body) then
        --apply impulse
        local pos = Vec(0,0,0)
        local imp = GetRandomDirection(100)
        ApplyBodyImpulse(body, pos, impulse)
        
        -- clamp velocity
        local vel = GetBodyVelocity(body)
        local amp = VecLength(vel)
        amp = math.min(amp, 10.0)
        SetBodyVelocity(body, VecScale(VecNormalize(vel), amp))
    end
end

function _toolsIsDroppable(toolId)
    if toolId == "sledge" or toolId == "spraycan" or toolId == "extinguisher" then
        return false
    end

    if _toolState.notDroppableTools[toolId] then
        return false
    end
    
    return true
end

function _initiateToolPickupData()
    local tools = ListKeys("game.tool")

    _toolData = {}
    for i = 1, #tools do
        local toolId = tools[i]
        
        local entities = SpawnTool(toolId, Transform())
        if entities ~= nil and #entities > 0 then
            local voxSize = 0.1
            local min = nil
            local max = nil
            for index, e in ipairs(entities) do
                local type = GetEntityType(e)
                if type == "body" then
                    if min == nil then
                        min,max = GetBodyBounds(e)
                    else
                        local mi,ma = GetBodyBounds(e)
                        for j = 1, 3 do
                            min[j] = math.min(min[j], mi[j])
                            max[j] = math.max(max[j], ma[j])
                        end
                    end
                elseif type == "shape" then
                    local x,y,z,s = GetShapeSize(e)
                    if s < voxSize then
                        voxSize = s
                    end
                end
            end

            local dim = VecSub(max, min)
            
            local maxSize = 0
            local minSize = 1000
            
            local axis = 1
            for j = 1, 3 do
                if dim[j] > maxSize then
                    axis = j
                    maxSize = dim[j]
                end

                if dim[j] < minSize then
                    minSize = dim[j]
                end
            end

            if maxSize < minSize * 1.5 then
                axis = 2
                maxSize = dim[axis]
            end

            local scale = voxSize/0.1
            if maxSize < 1.5 and scale < 0.7 then
                scale = 1.5
            elseif maxSize > 1.5 and scale > 0.5 then
                scale = 0.5
            end
            _toolData[toolId] = {scale = scale, axis = axis, axisSize = maxSize}

            for index, value in ipairs(entities) do
                Delete(value)
            end

        end
    end

end