#version 2

#include "mplib/mp.lua"

local timelimit = 120

-- server only
server.time = timelimit

-- this shared table is accessible from clients (but clients have read-only access)
shared.elevation = {}
shared.time = server.time

function server.init()
	-- init spawn component and set the default loadout.
	spawnInit()
	spawnSetDefaultLoadout({
		{"plank", 200},
		{"sledge", 0},
		{"spraycan", 0},
		{"extinguisher", 0}
	})

	-- generate 20 random starting transforms
	local spawnTransforms = utilGenerateSpawnPoints(20)
	-- and make our spawn component use these for spawning players
	spawnSetSpawnTransforms(spawnTransforms)
	
	-- initialize a 5 second countdown for starting of the game.
	countdownInit(5.0)
end

function server.tick(dt)

	for p in PlayersAdded() do
		-- new player joined. respawn that player to give the default loadout.
		spawnRespawnPlayer(p)
		-- initiliaze elevation to 0
		shared.elevation[p] = 0.0
	end

	spawnTick(dt)

	if countdownTick(dt) then return end -- return while countdown is active
	
	server.time = server.time - dt 			-- update time
	shared.time = math.floor(server.time) 	-- sync only whole seconds to client

	-- Save the highest elevation for each player
	for p in Players() do
		local elevation = GetPlayerTransform(p).pos[2]
		if elevation > shared.elevation[p] then
			shared.elevation[p] = math.floor(elevation * 10.0) * 0.1
		end

		-- Disable player input when game is over
		if server.time <= 0.0 then
			DisablePlayerInput(p)
		end
	end

end


client.bestElevation = 0.0
client.bestElevationPlayer = -1

function client.tick(dt)

	if not countdownDone() then return end

	-- check if a new player is in the lead
	-- if so, post a banner to celebrate
	for p in Players() do
		if shared.elevation[p] > client.bestElevation then
			client.bestElevation = shared.elevation[p]
			if p ~= client.bestElevationPlayer then
				client.bestElevationPlayer = p
				hudShowBanner(GetPlayerName(p).." is now in the lead!", {0.2, 0.55, 0.8, 1})
			end
		end
	end
end


function client.draw(dt)
	-- during countdown, display the title of the game mode.
	hudDrawTitle(dt, "Plank climbers!")

	-- show a description of the objective for the first 10 seconds (or if shift is held).
	if shared.time > (timelimit - 10) or InputDown("shift") then
		hudDrawGameModeHelpText("Plank climbers!", "See how far up you can elevate yourself before the time runs out!")
	end

	if countdownDraw() then	return end

	-- draw the timer (top center)
	hudDrawTimer(shared.time)
	-- and any banner that may have been posted with hudShowBanner() above.
	hudDrawBanner(dt)

	local gameOver = shared.time <= 0.0
	
	if not gameOver then
		-- draw in-world markers, one for each player.
		local worldMarkers = {}
		for p in Players() do
			local marker = {}
			marker.pos = GetPlayerTransform(p).pos
			marker.color = {1.0, 1.0, 1.0}
			marker.label = GetPlayerName(p).." "..shared.elevation[p].."m"
			marker.offset = Vec(0,2,0)
			marker.lineOfSightRequired = false
			marker.player = p
			marker.icon = "gfx/playermarker.png"
			marker.drawIconInView = false
			worldMarkers[1 + #worldMarkers] = marker
		end
		hudDrawWorldMarkers(worldMarkers)
	end

	-- prepare and draw scoreboard
	local rows = {}
	for p in Players() do
		rows[#rows+1] = { player=p, columns = { shared.elevation[p] }}
	end

	-- sort scoreboard on elevation (meters)
	table.sort(rows, function (a, b) return a.columns[1] > b.columns[1] end )

	-- our scoreboard will have one group with all players in it.
	local groups = {{name="Players", color={0.2, 0.55, 0.8, 1}, outline = false, rows = rows}}
	local columns = {{name="Meters", width=90, align="center"}}

	-- Once time is over, present results banner and leaderboard.
	if gameOver then
		hudDrawResults(GetPlayerName(client.bestElevationPlayer).." won!", {0.2, 0.55, 0.8, 1}, "Results", columns, groups)
	else
		hudDrawScoreboard(InputDown("shift"), "Results", columns, groups)
	end
end