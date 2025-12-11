--- Spawn
--
-- This system manages player spawning and respawning in a multiplayer game session.
-- It supports timed respawns, custom spawn locations, team-based spawn grouping,
-- and configurable player loadouts.
--
-- Core responsibilities:
--
-- * Automatically respawn dead players after a delay
-- * Allow forced respawns (e.g. at round start or by host)
-- * Select spawn positions from grouped spawn transforms
-- * Apply a configurable loadout upon respawn
--
-- Execution context:
--
-- * This system is intended to run **server-side only**
-- * Shared state is synced using the `shared.respawnTimeLeft` table


#include "script/include/player.lua"

_spawnState = {}
shared.respawnTimeLeft = {}

--- Initialize the spawn system (server).
--
-- Resets the internal state. Call this once when setting up the game mode.
function spawnInit()
    _spawnState = { deadTime={}, spawnTransformGroups={}, defaultLoadout=nil, respawnTime = 3, respawnAtCurrentLocation=false, forceRespawn={} }
end

--- Set spawn transforms for one or more groups (server).
--
-- Used to define where players can spawn based on group index (e.g. teams).
-- If no `groupIndex` is provided, all spawn points are assigned to group 1
-- and any previous group information is cleared.
-- 
-- The transforms are of the same type { pos, rot } that is used in the API.
--
-- @param[type=table] spawnTransforms List of spawn transforms.
-- @param[opt,type=number] groupIndex Group ID (defaults to 1).
-- @usage
-- -- Set spawn transforms for 2 teams.
-- spawnSetSpawnTransforms(spawnTransformTeam1, 1)
-- spawnSetSpawnTransforms(spawnTransformTeam2, 2)
function spawnSetSpawnTransforms(spawnTransforms, groupIndex)
    if groupIndex == nil then
        _spawnState.spawnTransformGroups = {}
        _spawnState.spawnTransformGroups[1] = spawnTransforms
    else
        _spawnState.spawnTransformGroups[groupIndex] = spawnTransforms
    end
end

--- Set the automatic respawn delay in seconds (server).
--
-- Controls how long a player must remain dead before being automatically
-- respawned by `spawnTick`.
--
-- @param[type=number] respawnTime Time in seconds before respawn.
function spawnSetRespawnTime(respawnTime)
    _spawnState.respawnTime = respawnTime
end

--- Set the default loadout to apply on respawn (server).
--
-- The loadout is a list of `{ toolName, ammoCount }` entries, applied in order.
-- All tools are disabled and cleared first, then tools in the loadout are enabled
-- and given the specified ammo. The first entry becomes the active tool.
--
-- @param[type=table] loadout List of `{ toolName, ammoCount }` tables.
-- @usage
-- function server.init()
--      defaultLoadout = {
--          {"gun", 7}, 
--          {"sledge", 0}, 
--          {"spraycan", 0}, 
--          {"extinguisher", 0}
--      }
--      spawnSetDefaultLoadout(defaultLoadout)
-- end
function spawnSetDefaultLoadout(loadout)
    _spawnState.defaultLoadout = loadout
end

--- Enable or disable respawning at the player's last position (server).
--
-- When enabled, players are respawned at the transform where they died instead
-- of at a spawn point chosen from `spawnTransformGroups`.
--
-- @param[type=bool] active `true` to enable, `false` to disable.
function spawnSetRespawnAtCurrentLocation(active)
    _spawnState.respawnAtCurrentLocation = active
end

--- Get time left until a player will respawn.
--
-- When the player is alive, this returns `0`. While dead, the value is updated
-- every tick and rounded up to whole seconds. 
--
-- @param[type=number] player Player ID.
-- @return[type=number] Time in seconds until respawn, or `0` when alive.
function spawnGetPlayerRespawnTimeLeft(player)
    if GetPlayerHealth(player) > 0 then return 0 end
    return shared.respawnTimeLeft[player]
end

--- Respawn a player at a given transform and with a given loadout (server).
--
-- If `transform` is `nil`, the player is respawned using the engine's default
-- spawn position. When a `loadout` is provided those tools will be 
-- equipped and the current tools will be removed.
--
-- @param[type=table|nil]  transform Optional spawn transform.
-- @param[type=table|nil]  loadout   Optional loadout `{ {toolName, ammoCount}, ... }`.
-- @param[type=number] player Player ID.
function spawnSpawnPlayer(transform, loadout, player)
    if transform then
        RespawnPlayerAtTransform(transform, player)
    else
        RespawnPlayer(player)
    end

    if loadout ~= nil then
        local tools = ListKeys("game.tool")
        for ti=1, #tools do
            local tool = tools[ti]
            SetToolEnabled(tool, false, player)
            SetToolAmmo(tool, 0, player)
        end

        for i=1,#loadout do
            SetToolEnabled(loadout[i][1], true, player)
            SetToolAmmo(loadout[i][1], loadout[i][2], player)
        end

        -- make the first tool in loadout the active tool
        if #loadout > 0 then
            SetPlayerTool(loadout[1][1], player)
        else
            SetPlayerTool("none", player)
        end
    end
end

--- Flag a player for forced respawn on the next tick (server).
--
-- The player will be respawned immediately during the next `spawnTick` call,
-- regardless of how long they have been dead.
--
-- @param[type=number] playerId Player ID.
function spawnRespawnPlayer(playerId)
    _spawnState.forceRespawn[playerId] = true
end

--- Flag all players for forced respawn on the next tick (server).
--
-- Useful for round start or when resetting global game state.
function spawnRespawnAllPlayers()
    for p in Players() do
        spawnRespawnPlayer(p)
    end
end

--- Main update loop for the spawn system (server).
--
-- Should be called every tick. For each player it:
--
-- * Tracks time spent dead
-- * Automatically respawns players once they exceed the configured respawn time
-- * Performs forced respawns flagged via `spawnRespawnPlayer` / `spawnRespawnAllPlayers`
--
-- If respawning at current location is disabled, a spawn transform is chosen
-- from the group-based spawn lists using `spawnPickSpawnTransform`.
--
-- @param[type=number] dt Time step in seconds.
-- @param[opt,type=table] playerGroupList Table mapping player IDs to group indices.
--
-- @usage
-- local playerGroupList = {}
-- playerGroupList[1] = 1 -- player id 1,2,3 is in team 1 and 4,5,6 in team 2
-- playerGroupList[2] = 1
-- playerGroupList[3] = 1
-- playerGroupList[4] = 2
-- playerGroupList[5] = 2
-- playerGroupList[6] = 2
-- spawnTick(dt, playerGroupList)
function spawnTick(dt, playerGroupList)
    for p in Players() do
        local doRespawn = false

        if _spawnState.forceRespawn[p] then
            doRespawn = true
        elseif _spawnState.deadTime[p] == nil then
            _spawnState.deadTime[p] = 0.0
        elseif GetPlayerHealth(p) <= 0.0 then
            _spawnState.deadTime[p] = _spawnState.deadTime[p] + dt
            shared.respawnTimeLeft[p] = math.ceil(_spawnState.respawnTime - _spawnState.deadTime[p])

            if _spawnState.deadTime[p] > _spawnState.respawnTime then
                doRespawn = true
            end
        else
            _spawnState.deadTime[p] = 0.0
        end

        if doRespawn then
            local t = spawnPickSpawnTransform(p, playerGroupList)
            spawnSpawnPlayer(t, _spawnState.defaultLoadout, p)
            _spawnState.deadTime[p] = 0.0
        end

        _spawnState.forceRespawn[p] = false;
   end
end

--- Get all current spawn transform groups (server).
--
-- @return[type=table] Table mapping group indices to lists of spawn transforms.
function spawnGetSpawnTransformGroups()
    return _spawnState.spawnTransformGroups
end


function spawnPickSpawnTransform(playerId, playerGroupList)
    local groupIndex = 1

    if _spawnState.respawnAtCurrentLocation then
        return GetPlayerTransform(playerId)
    end

    if playerGroupList then
        groupIndex = playerGroupList[playerId]
    end

    if #_spawnState.spawnTransformGroups == 0 then
        return nil
    end

    local transformList = _spawnState.spawnTransformGroups[groupIndex]

    if #transformList == 0 then
        return nil
    end

	return transformList[GetRandomInt(1, #transformList)]
end