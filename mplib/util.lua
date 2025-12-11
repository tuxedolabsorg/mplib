--- Multiplayer Level Utility Functions
--
-- This module provides utilities for extracting spawn positions, tool spawn locations,
-- and points of interest from level tags, as well as generating valid dynamic spawn points
-- in a level using raycasting and terrain checks.
--
-- Tags Used in FindLocations:
--
-- * `"playerspawn"` General player spawn location (used when no team is specified).
-- * `"teamspawn"`   Team-specific spawn. Tagged with: teamspawn=1, teamspawn=2, etc.
-- * `"ammospawn"`   Tool or ammo loot spawn. Optional: rarity=low
-- * `"pointofinterest"` Marks locations of gameplay interest. Optionally: pointofinterest=1, pointofinterest=2


--- Loads player spawn transforms from tagged level locations.
--
-- Searches for locations tagged as `"playerspawn"` or `"teamspawn"`, and optionally
-- filters them by team ID.
--
-- @param[opt,type=number] teamId The numeric team ID to filter by
-- @return[type=table] A list of transforms representing spawn points
function utilLoadLevelPlayerSpawns(teamId)

	local tag = not teamId and "playerspawn" or "teamspawn"
    local locs = FindLocations(tag, true)
	
    local spawnTransforms = {}
	for i=1, #locs do
		if (not teamId or teamId == tonumber(GetTagValue(locs[i], "teamspawn"))) then
			spawnTransforms[1 + #spawnTransforms] = GetLocationTransform(locs[i])
		end
    end

    return spawnTransforms
end

--- Loads tool spawn locations from the level by tag and optional rarity.
--
-- Finds locations tagged `"ammospawn"` and filters them by the given rarity value,
-- if specified.
--
-- @param[opt,type=string] rarity A string representing the rarity level (e.g. `"low"`, `"medium"`, `"high"`).
-- @return[type=table] A list of transforms representing ammo/tool spawn points
function utilLoadLevelToolSpawns(rarity)
    local locs = FindLocations("ammospawn", true)
    local resultTransforms = {}
	for i=1, #locs do
        if not rarity or rarity == GetTagValue(locs[i], "rarity") then
            resultTransforms[1 + #resultTransforms] = GetLocationTransform(locs[i])
        end
    end
    return resultTransforms
end

--- Loads points of interest (POIs) from the level.
--
-- Looks for locations tagged as `"pointofinterest"`, optionally filtering by a
-- numeric team ID if POIs are team-specific.
--
-- @param[opt,type=number] teamId The numeric team ID to filter by.
-- @return[type=table] A list of transforms (TTransform) representing POIs
function utilLoadLevelPoi(teamId)
    local locs = FindLocations("pointofinterest", true)
    local pois = {}
	for i=1, #locs do
		if (not teamId or teamId == tonumber(GetTagValue(locs[i], "pointofinterest"))) then
			pois[1 + #pois] = GetLocationTransform(locs[i])
		end
    end

    return pois
end

--- Generates multiple lists of spawn transforms with varying densities.
--
-- Uses `utilGenerateSpawnPoints` to create a list of transforms for each density level.
-- Densities are specified as a list of floats, where each float represents the density
-- 
-- @param[type=table] densities A list of density values (e.g. `{1.0, 0.66, 0.5}`)
-- @return[type=table] A list of lists, where each sublist contains transforms (TTransform) for a specific density
function utilGenerateSpawnPointLists(densities)
	local spawnPoints = {}
	local existingTransforms = {}
	for i=1, #densities do
		spawnPoints[i] = utilGenerateSpawnPointsDensity(densities[i], existingTransforms)	
		for j=1, #spawnPoints[i] do
			existingTransforms[1 + #existingTransforms] = spawnPoints[i][j]
		end
	end
	return spawnPoints
end

--- Generates a list of spawn points with the specified density.
--
-- Uses `utilGenerateSpawnPoints` to create a list of transforms based on the given density.
--
-- @param[type=number] density A number representing the density of spawn points (e.g. `1.0` for high density)
-- @param[opt,type=table] existingTransforms A list of existing transforms to avoid overlap
-- @return[type=table] A list of transforms (TTransform) representing valid spawn points
function utilGenerateSpawnPointsDensity(density, existingTransforms)
	-- Generate a list of spawn points with the specified density
	local area = GetBoundaryArea()
	local density = clamp(density, 0.01, 2.0)
	local count = density * area / 1000
	return utilGenerateSpawnPoints(count, existingTransforms)
end

--- Generates a specified number of valid random spawn transforms in the level.
--
-- Uses `utilGenerateSpawnPoint` to test and collect terrain-validated spawn positions.
--
-- @param[type=number] count Number of valid spawn points to generate
-- @param[opt,type=table] existingTransforms A list of existing transforms to avoid overlap
-- @return[type=table] A list of transforms (TTransform) representing valid spawn points
function utilGenerateSpawnPoints(count, existingTransforms)
	aabbMin, aabbMax = GetBoundaryBounds()

	local wantedCandidateCount = count * 5

	local candidatePoints = {}
	local iters = 0
	while #candidatePoints < wantedCandidateCount do
		iters = iters + 1

		if iters > 2000 then
			break
		end

		local x = GetRandomFloat(aabbMin[1], aabbMax[1])
		local z = GetRandomFloat(aabbMin[3], aabbMax[3])
		
		local inBounds, distToBoundary = IsPointInBoundaries(Vec(x, 0, z))
		
		if inBounds and distToBoundary > 10 then
			local pos = Vec(x, 200, z)
			local dir = Vec(0, -1, 0)
			local hit, dist, _, s = QueryRaycast(pos, Vec(0,-1,0), 250)
			if hit and not IsBodyDynamic(GetShapeBody(s)) then
				local p = VecAdd(pos, VecScale(dir, dist))

				if not IsPointInWater(p) then

					local score = 0

					for i=1, #candidatePoints do
						local len = VecLength(VecSub(p, candidatePoints[i].pos))
						if len < 25.0 then
							score = score - 3.0 * (1.0 - (len/25.0))
						end
					end

					if existingTransforms then
						for j=1, #existingTransforms do
							local len = VecLength(VecSub(p, existingTransforms[j].pos))
							if len < 25.0 then
								score = score - 3.0 * (1.0 - (len/25.0))
							end
						end
					end

					local below = VecAdd(p, Vec(0, -2, 0))
					hit, dist = QueryRaycast(below, dir, 200)
					if hit and dist > 0.5 then
						local new_p = VecAdd(below, VecScale(dir, dist))
						if not IsPointInWater(new_p) then
							p = new_p
							score = score + 0.5
						end
					end

					local closeToObject = false
					local probe = VecAdd(p, Vec(0, 0.6, 0))
					if not QueryClosestPoint(probe, 0.5) then
						for i=1, 10 do
							local ang = i*2*math.pi/10
							local d = Vec(math.cos(ang), 0, math.sin(ang))
							--Must be laterally close to something
							if QueryRaycast(probe, d, 1.5) then 
								score = score + 0.5
								break
							end
						end
					else
						--score = score - 0.2
					end

					if not _isFlat(p) then
						score = score - 0.75
					end

					candidatePoints[1 + #candidatePoints] = { pos = p, score = score }
				end
			end
		end
	end

	table.sort(candidatePoints, function (a, b) return a.score > b.score end )

	local transforms = {}
	for i=1, count do
		transforms[1 + #transforms] = Transform(candidatePoints[i].pos)
	end
	return transforms
end

-- Internal functions


--- Internal helper to check if a point lies on a relatively flat surface.
--
-- Casts vertical raycasts from 4 side offsets and verifies uniform elevation.
--
-- @param[type=TVec] point A Vec3 point to test
-- @return `true` if the surface is flat and solid; `false` otherwise
-- @local
function _isFlat(point)
	local p = Vec(point[1], point[2]+0.5, point[3])
	local off = {Vec(-0.5, 0, 0), Vec(0.5, 0, 0), Vec(0, 0, -0.5), Vec(0, 0, 0.5)}
	for i=1, 4 do
		local hit, dist = QueryRaycast(VecAdd(p, off[i]), Vec(0, -1, 0), 1)
		if not hit or math.abs(dist-0.5) > 0.1 then
			return false
		end
	end
	return true
end