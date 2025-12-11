--- Teams
--
-- Handles dynamic team assignment, player coloring, and UI rendering
-- for team selection in a multiplayer match. Tracks player membership in teams, allows
-- hosts to force team starts, and synchronizes team state to clients.
--
-- Core responsibilities:
--
-- * Create and configure teams (names, colors, players)
-- * Manage player joins, leaves, and team switches
-- * Handle team-based color assignment
-- * Provide a UI for team selection and team joining
--
-- Execution context:
--
-- * Server-only logic (team state, assignment)
-- * Client-side UI (draw functions)

_WAITING = 1
_COUNTDOWN = 2
_LOCKED = 3
_DONE = 4

_COUNTDOWNTIME = 3.0
_LOCKTIME = 2.5

#include "script/include/player.lua"
#include "ui.lua"

_teamState = { time=0.0, pendingTeamSwaps = {}, stateTime = 0.0, skippedCountdown = false }
client._teamState = { stateTime = 0.0, prevState = _WAITING }

--- Initialize the team system with a given number of teams (server).
--
-- Sets default team names and colors and clears any previous team state.
--
-- @param[type=number] teamCount Number of teams to create.
function teamsInit(teamCount)
    shared._teamState = { teams={}, state = _WAITING}
    for i=1,teamCount do
        shared._teamState.teams[1 + #shared._teamState.teams] = { 
            name=_teamsGetDefaultTeamName(i), 
            color=_teamsGetDefaultColor(i),
            players={}
        }
    end
end

--- Get the configured color for a team.
--
-- Returns the current team color. If the team does not exist, falls
-- back to `_teamsGetDefaultColor(teamId)`.
--
-- @param[type=number] teamId Team ID of the team (1-based).
-- @return[type=table] RGB color table `{r, g, b}` with components in [0, 1].
function teamsGetColor(teamId)
    if shared._teamState.teams[teamId] == nil then
        return _teamsGetDefaultColor(teamId)
    end
    return shared._teamState.teams[teamId].color
end

--- Set custom colors for all teams (server).
--
-- Updates the `color` of each team. The provided list should have
-- one entry per team.
--
-- @param[type=table] colors List of RGB color tables, one per team
--   (e.g. `{ {1,0,0}, {0,1,0}, ... }`).
function teamsSetColors(colors)
    for i=1,#shared._teamState.teams do
        shared._teamState.teams[i].color = colors[i]
    end
end

--- Set custom names for all teams (server).
--
-- Updates the `name` for each team. The provided list should match
-- the number of active teams.
--
-- @param[type=table] names List of team names as strings
--   (e.g. `{ "Red", "Blue", "Green" }`).
function teamsSetNames(names)
    for i=1,#shared._teamState.teams do
        shared._teamState.teams[i].name = names[i]
    end
end

--- Get the configured team name for a given team ID.
--
-- Retrieves the current team name. If the team does not exist,
-- falls back to `_teamsGetDefaultTeamName(teamId)`.
--
-- @param[type=number] teamId Numeric ID of the team (1-based).
-- @return[type=string] Team name or default name if not configured.
function teamsGetName(teamId)
    if shared._teamState.teams[teamId] == nil then
        return _teamsGetDefaultTeamName(teamId)
    end
    return shared._teamState.teams[teamId].name
end

--- Assign players to teams directly (server).
--
-- Replaces the current team player lists. Each element in `teams` 
-- is a list of player IDs.
--
-- @param[type=table] teams List of player ID lists, one per team.
--   Example: `{ {1, 2}, {3, 4} }` assigns players 1 and 2 to team 1,
--   and players 3 and 4 to team 2.
function teamsSetTeams(teams)
    local teamCount = #teams

    for i=1,teamCount do
        shared._teamState.teams[i].players = teams[i]
    end
end

--- Returns a lookup table mapping each player to their team ID.
--
-- Iterates over all players and builds a map from player ID to their assigned team ID.
-- Useful for broadcasting team membership.
--
-- @return A table where keys are player IDs and values are team IDs
-- (e.g., `{ [1] = 2, [2] = 1, ... }`)
function teamsGetPlayerTeamsList()
    local playerTeamList = {}

    for p in Players() do
        playerTeamList[p] = teamsGetTeamId(p)
    end

    return playerTeamList
end

--- Get the list of players belonging to a specific team.
--
-- @param[type=number] teamId Team ID (1-based).
-- @return[type=table] List of player IDs in the team (empty if team does not exist).
function teamsGetTeamPlayers(teamId)
    if shared._teamState.teams[teamId] == nil then
        return {}
    end
    return shared._teamState.teams[teamId].players
end

--- Returns a lookup table mapping each player ID to their current team color.
--
-- This is convenient for construction UIs that uses team colors.
--
-- @return table A table where keys are player IDs and values are RGB color tables
-- @usage
-- - Returned table will have this format: 
-- { 
--    [1] = {0.2, 0.55, 0.8}, 
--    [2] = {0.8, 0.25, 0.2},
--    [3] = {0.3, 0.90, 0.1}, -- etc..
-- }
function teamsGetPlayerColorsList()
    local playerColorList = {}
    
    for p in Players() do
        local team = teamsGetTeamId(p)
        playerColorList[p] = teamsGetColor(team)
    end

    return playerColorList
end

--- Start the match or begin the team selection countdown (server).
--
-- If `skipCountdown` is `true`, teams are auto-assigned immediately and the
-- team state assignment is concidered done. If countdown is not skipped, it
-- is expected that the UI is rendered with `teamsDraw` to allow players to
-- pick teams.
--
-- @param[type=bool] skipCountdown Whether to skip the team selection countdown.
function teamsStart(skipCountdown)
    if skipCountdown then
        shared._teamState.state = _DONE
        _teamState.skippedCountdown = true
        _teamsAssignPlayers()
    else
        if shared._teamState.state == _WAITING then
            shared._teamState.state = _COUNTDOWN
            _teamState.stateTime = 0.0
        end
    end
end

--- Check if team setup is complete and the match has started.
--
-- @return[type=bool] `true` if setup is complete.
function teamsIsSetup()
    return shared._teamState.state == _DONE
end

--- Get the team ID of a specific player.
--
-- @param[type=number] playerId Player ID to look up.
-- @return[type=number] Team ID (1-based), or `0` if the player is unassigned.
function teamsGetTeamId(playerId)
    for i=1,#shared._teamState.teams do
        for p=1,#shared._teamState.teams[i].players do
            if shared._teamState.teams[i].players[p] == playerId then
                return i
            end
        end
    end
    return 0
end

--- Tick team logic (server).
--
-- Should be called once per tick on the server. It:
-- * Handles connecting/disconnecting players.
-- * Assigns teams and updates player colors when the setup is done.
-- * Posts an `teamsupdated` event when team setup is complete.
--
-- @param[type=number] dt Time step in seconds.
-- @return[type=bool] `true` if the pending game start was triggered this tick, `false` otherwise.
function teamsTick(dt)

    _teamState.stateTime = _teamState.stateTime + dt
        
    for p in PlayersRemoved() do
        for t=1,#shared._teamState.teams do
            local players = shared._teamState.teams[t].players
            for i=1,#players do
                if players[i] == p then
                    table.remove(players, i)
                    break
                end
            end
        end
    end

    if shared._teamState.state == _DONE then
        for p in PlayersAdded() do
            _teamsAssignPlayers()
        end

        for p in Players() do
            local team = teamsGetTeamId(p)
            local color = teamsGetColor(team)
            SetPlayerColor(color[1], color[2], color[3], p)
        end
    end
    
    for i=1,#_teamState.pendingTeamSwaps do
        local playerId = _teamState.pendingTeamSwaps[i][1]
        local teamId = _teamState.pendingTeamSwaps[i][2]
        for i=1,#shared._teamState.teams do
            for p=1, #shared._teamState.teams[i].players do
                if shared._teamState.teams[i].players[p] == playerId then
                    table.remove(shared._teamState.teams[i].players, p)
                    break
                end
            end
        end

        if teamId > 0 then
            local players = shared._teamState.teams[teamId].players
            players[1 + #players] = playerId
        end
    end
    _teamState.pendingTeamSwaps = {}

    if shared._teamState.state == _DONE and _teamState.skippedCountdown then
        _teamState.skippedCountdown = false
        return true
    end

    if shared._teamState.state == _COUNTDOWN then
        if _teamState.stateTime > _COUNTDOWNTIME then
            shared._teamState.state = _LOCKED
            _teamState.stateTime = 0.0
            _teamsAssignPlayers()
        end
    end

    if shared._teamState.state == _LOCKED then
        if _teamState.stateTime > _LOCKTIME then
            shared._teamState.state = _DONE
            _teamState.stateTime = 0.0
            PostEvent("teamsupdated", teamsGetPlayerTeamsList(), teamsGetPlayerColorsList())
            return true
        end
    end

    return false
end


--- Get a list of players on the same team as the local player (client).
--
-- @return[type=table] List of player IDs on the local player's team.
function teamsGetLocalTeam()
    local team = {}
    local teamId = teamsGetTeamId(GetLocalPlayer())
	for p in Players() do
		if teamsGetTeamId(p) == teamId then
			team[1 + #team] = p
		end
	end

    return team
end


--- Render the team selection screen UI (client).
--
-- Draws a team selection UI where players can pick a team to join.
-- Will early-out and skip any UI drawing if team setup is completed.
--
-- @param[type=number] dt Time step in seconds.
function teamsDraw(dt)
    if shared._teamState.state == _DONE then return end

    client._teamState.stateTime = client._teamState.stateTime + dt

    if client._teamState.prevState ~= shared._teamState.state then
        client._teamState.prevState = shared._teamState.state
        client._teamState.stateTime = 0.0
    end

    -- rotate camera around origo as a backdrop to team selection
    _teamState.time = _teamState.time + dt
    local cam = VecScale(Vec(math.sin(_teamState.time*0.025), 1.0, math.cos(_teamState.time*0.025)), 50.0)
    SetCameraTransform(Transform(cam, QuatLookAt(cam, Vec())))
	SetCameraDof(0, 0)

    UiMakeInteractive()
    SetBool("game.disablemap", true)

    local teamCount = #shared._teamState.teams

    local teamBoxWidth = 292
    local teamBoxHeight = 376

    local width = 10 + teamBoxWidth * teamCount + 10 * (teamCount-1) + 10
    local height = 432

    UiPush()
        UiAlign("left top")
        UiTranslate(UiCenter() - width/2, UiMiddle() - height/2)
        uiDrawPanel(width, height, 16)

        UiTranslate(0,10)

        UiPush()
            UiTranslate(width/2, 0)
            UiColor(COLOR_WHITE)
            UiFont("bold.ttf", 32 * 1.23)
            UiAlign("center top")
            UiText("Join a team")
        UiPop()

        UiTranslate(0, 36)

        UiPush()
        UiTranslate(10,0)
        for i = 1, teamCount do
            _teamsDrawTeamBox(i, teamBoxWidth, teamBoxHeight)
            UiTranslate(teamBoxWidth + 10,0)
        end
        UiPop()
    UiPop()

    UiPush()

    UiTranslate(UiCenter(), UiMiddle() + 300)
    if shared._teamState.state >= _LOCKED then
        uiDrawTextPanel("Starting...", 1)
    elseif shared._teamState.state >= _COUNTDOWN then
        local text = "Locking teams in"

        if teamsGetTeamId(GetLocalPlayer()) == 0 then
            text = "Auto assigning teams in"
        end

        uiDrawTextPanel(text.." "..clamp(math.ceil(_COUNTDOWNTIME - client._teamState.stateTime), 0.0, _COUNTDOWNTIME), 1)
    elseif IsPlayerHost() then
        uiDrawTextPanel("Waiting for host...", 1)
    end

    UiPop()
end

-- Internal functions

function server._teamsJoinTeam(playerId, teamId)
    _teamState.pendingTeamSwaps[1 + #_teamState.pendingTeamSwaps] = {playerId, teamId}
end

function _teamsAssignPlayers()
    for p in Players() do
        if teamsGetTeamId(p) == 0 then
            local newTeam = 1
            local minCount = 999

            for t=1,#shared._teamState.teams do
                local count = #shared._teamState.teams[t].players

                if count < minCount then
                    minCount = count
                    newTeam = t
                end
            end

            local players = shared._teamState.teams[newTeam].players
            players[1 + #players] = p
        end
    end

    local teamColors = {}
    for i=1,#shared._teamState.teams do
        teamColors[1 + #teamColors] = teamsGetColor(i)
    end

    PostEvent("teamsupdated", teamsGetPlayerTeamsList(), teamColors)
end

function _teamsDrawTeamBox(teamId, width, height)
    UiPush()
        
        local playerNames = {}

        local players = shared._teamState.teams[teamId].players;
        for i=1,#players do
            playerNames[1 + #playerNames] = GetPlayerName(players[i])
        end

        local teamName = shared._teamState.teams[teamId].name
        local color = shared._teamState.teams[teamId].color
        local bgCol = VecScale(color, 0.75)

        UiColor(bgCol[1], bgCol[2], bgCol[3])
        UiRoundedRectOutline(width, height, 12, 4)

        UiTranslate(8,8)
        UiRoundedRect(width - 2 * 8, 36, 4)
        
        UiFont("bold.ttf", 32)
        UiColor(COLOR_WHITE)
        UiPush()
            UiTranslate((width - 2 * 8)/2, 18)
            UiAlign("center middle")
            UiText(teamName)
        UiPop()

        UiTranslate(0, 36 + 4)

        UiAlign("left middle")

        UiTranslate(0, 32/2)

        for i=1,#players do
            
            UiPush()
            
            local isLocalPlayer = players[i] == GetLocalPlayer()
            
            if isLocalPlayer then
                UiColor(1,1,1,0.2)
            else
                UiColor(1,1,1,0.1)
            end
            
            UiRoundedRect(width - 2 * 8, 32, 4)

            UiPush()
            UiTranslate(0, -32/2)
            uiDrawPlayerRow(players[i], 32,width - 2 * 8, bgCol)
            UiPop()
            
            UiPop()
            
            UiTranslate(0, 32 + 2)
        end

        for i = 1, 8 - #players do
            UiColor(1,1,1,0.1)
            UiRoundedRect(width - 2 * 8, 32, 4)
            UiTranslate(0, 32 + 2)
        end

        UiTranslate(0, 10)

        UiFont(FONT_BOLD, FONT_SIZE_20)

        local team = teamsGetTeamId(GetLocalPlayer())
        if team == teamId then
            if uiDrawSecondaryButton("Leave", width - 2 * 8, shared._teamState.state and shared._teamState.state >= _LOCKED) then
                ServerCall("server._teamsJoinTeam", GetLocalPlayer(), 0)
            end
        else

            if uiDrawSecondaryButton("Join", width - 2 * 8, team ~= 0 or (shared._teamState.state and shared._teamState.state >= _LOCKED)) then
                ServerCall("server._teamsJoinTeam", GetLocalPlayer(), teamId)
            end
        end
    UiPop()
end

function _teamsGetDefaultColor(teamIndex)
    if teamIndex == 1 then
        return COLOR_TEAM_1
    elseif teamIndex == 2 then
        return COLOR_TEAM_2
    elseif teamIndex == 3 then
        return COLOR_TEAM_3
    elseif teamIndex == 4 then
        return COLOR_TEAM_4
    end

    return COLOR_WHITE
end

function _teamsGetDefaultTeamName(teamId)
    if teamId == 1 then
        return "Team A"
    elseif teamId == 2 then
        return "Team B"
    elseif teamId == 3 then
        return "Team C"
    elseif teamId == 4 then
        return "Team D"
    end
    return "Team X"
end