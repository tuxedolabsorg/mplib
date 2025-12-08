--- Stats
--
-- Tracks kill and death counts for each player in a multiplayer session.
--
-- Core responsibilities:
--
-- * Increment death count for victims
-- * Increment kill count for attackers (when valid)
-- * Provide API to query per-player kills and deaths
--
-- Execution context:
--
-- * `statsTick` must be called **server-side**
-- * `statsGetKills` / `statsGetDeaths` can be used on both server and client


#include "script/include/player.lua"

shared._statsState = {}

--- Initialize the stats (server).
--
-- Clears all previously recorded stats. Call this at the start of a
-- match or round.
function statsInit()
    shared._statsState = {}
end

--- Update player statistics based on `playerdied` events (server).
--
-- Processes all `playerdied` events since the last tick and updates stats.
-- This should be called once per tick on the server during an
-- active match.
--
-- @param[type=table|nil] playerTeamList Table mapping player IDs to team identifiers.
-- @usage
-- -- Example
-- local playerGroupList = {}
-- playerGroupList[1] = 1 -- player id 1,2,3 is in team 1 and 4,5,6 in team 2
-- playerGroupList[2] = 1
-- playerGroupList[3] = 1
-- playerGroupList[4] = 2
-- playerGroupList[5] = 2
-- playerGroupList[6] = 2
-- statsTick(playerGroupList)
-- -- or in a free-for-all game mode
-- statsTick(nil)
function statsTick(playerTeamList)

    local count = GetEventCount("playerdied")
	for i=1,count do
		local victim, attacker, _, _, _, _, _ = GetEvent("playerdied", i)

        if not shared._statsState[victim] then
            shared._statsState[victim] = {kills=0,deaths=0}            
        end

        if not shared._statsState[attacker] then
            shared._statsState[attacker] = {kills=0,deaths=0}            
        end

        shared._statsState[victim].deaths = shared._statsState[victim].deaths + 1

        if attacker ~= nil and attacker ~= 0 and attacker ~= victim and not _statsIsSameTeam(attacker, victim, playerTeamList) then
            shared._statsState[attacker].kills = shared._statsState[attacker].kills + 1
        end
    end
end

--- Get the number of kills for a player.
--
-- If the player has no recorded stats, returns 0.
--
-- @param[type=number] playerId Player ID.
-- @return[type=number] Number of kills recorded for this player.
function statsGetKills(playerId)
    if shared._statsState[playerId] == nil then
        return 0
    end

    return shared._statsState[playerId].kills
end

--- Get the number of deaths for a player.
--
-- If the player has no recorded stats, returns 0.
--
-- @param[type=number] playerId Player ID.
-- @return[type=number] Number of deaths recorded for this player.
function statsGetDeaths(playerId)
    if shared._statsState[playerId] == nil then
        return 0
    end
    return shared._statsState[playerId].deaths
end

function _statsIsSameTeam(attacker, victim, playerTeamList)
    if playerTeamList == nil then return false end
    return playerTeamList[attacker] == playerTeamList[victim]
end