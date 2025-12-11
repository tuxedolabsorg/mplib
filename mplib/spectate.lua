--- Multiplayer Spectator System
--
-- Client-side spectating logic for multiplayer.
-- Spectate mode will be enabled when the local player dies.
--
-- Provides:
--
-- * Third-person camera when local player is dead
-- * Smooth transitions into spectate mode
-- * Mouse-based camera orbit and zoom
-- * Player cycling with mouse buttons
-- * Optional map handling and outlines for spectated player/vehicle
--
-- All functions in this module are intended to run on the **client**.
--
-- Example usage:
--
--	function client.tick()
--		spectateTick(GetAllPlayers())
-- 	end
--
--	function client.draw()
--		spectateDraw()
--	end
--
--	function client.render(dt)
--		spectateRender(dt)
--	end

#include "script/common.lua"
#include "ui.lua"

SPECTATE_DEFAULT_X_ROT = -math.pi / 8

_spectateState = { 
	currPlayer = nil, 
	playerList = {},

	attacker = 0, -- player who killed the local player

	enabled = false, -- whether the spectate system is enabled
	time = 0.0, -- time since the spectate system was enabled
	delay = 2.0, -- delay before enabling the spectate system
	transition = 0.0,
	initialCameraTransform = Transform(), -- initial camera transform when spectate mode is enabled

	-- camera state
	rotX = SPECTATE_DEFAULT_X_ROT, 
	rotY = 0.0, 
	timeSinceRotation = 0.0, 
	distance = 8.0, 
	actualDistance = 4.0, 
	followTransform = nil,

	transform = Transform(), 
	eye = Vec(), 
	lookAt = Vec(), 
	vehicle = 0,

	-- Map state
	mapEnabled = false,
	mapCameraTransform = Transform(),
	mapCameraTransition = 1.0,

	-- configurations
	mapAllowed = true, -- whether the map is allowed in spectate mode
	hideLabel = false, -- whether to hide the label of the spectated player
}

--- Update spectate state and current target based on player health and events (client).
--
-- Spectate mode is automatically enabled when the local player dies.
-- Call this once per frame from your main tick function on the client.
--
-- Responsibilities:
--
-- * Enable/disable spectate mode when the local player dies or respawns
-- * Track the attacker when the local player is killed
-- * Filter and store a clean list of valid spectatable players
-- * Ensure current spectated player remains valid, or select a new one
--
--
-- @param[type=table] playerList  List of player IDs to consider for spectating
-- @usage
-- -- Example usage in client tick function
-- spectateTick({}) -- pass an empy list to only allow spectating the local player
-- spectateTick(GetAllPlayers()) -- will be able to spectate all players
-- specateTick(teamsGetLocalTeamPlayers()) -- will spectate all players in the local team

function spectateTick(playerList)
	if GetPlayerHealth() <= 0.0 then	
		if not _spectateState.enabled then
			_enableSpectate()
		end
	else
		_disableSpectate()
	end

	-- Track who killed the local player
	local count = GetEventCount("playerdied")
    for i=1,count do
        local victim, attacker = GetEvent("playerdied", i)
        if attacker ~= 0 and IsPlayerLocal(victim) then
    	    _spectateState.attacker = attacker
            break
        end
    end

	if not _spectateState.enabled then
		return
	end

    -- Build a filtered copy
	local filtered = {}
	local seen = {}

	for i = 1, #playerList do
		local p = playerList[i]

		-- skip local here; we'll insert it explicitly at index 1 later
		if not IsPlayerLocal(p)
			and IsPlayerValid(p)
			and not IsPlayerDisabled(p)
			and not seen[p]
		then
			seen[p] = true
			filtered[#filtered + 1] = p
		end
	end

	-- Make sure the local player is always first in the list,
	local localPlayer = GetLocalPlayer()
	table.insert(filtered, 1, localPlayer)

    _spectateState.playerList = filtered
    if #filtered == 0 then
        _spectateState.currPlayer = nil
        return
    end

    local foundPlayer = false
    for i=1,#filtered do
        if filtered[i] == _spectateState.currPlayer then
            foundPlayer = true
        end
    end

    if not foundPlayer then
		_setCurrentPlayer(filtered[1])
    end
end

--- Draw spectate HUD elements and handle player switching (client).
--
-- Call this from your UI/draw loop when spectate mode should be active.
--
-- Responsibilities:
--
-- * Cycle between available players using:
--     * Left mouse button  -> next player
--     * Right mouse button -> previous player
-- * Draw a label with the current spectated player's name, if enabled
function spectateDraw()

	if not _spectateState.enabled or _spectateState.transition < 1.0 then
		return
	end
	if _spectateState.currPlayer == nil then
		return
	end

	if _spectateState.mapCameraTransition < 1.0 then
		return
	end

	if not IsPlayerValid(_spectateState.currPlayer) then
		_setCurrentPlayer(nil)
		return
	end
	if #_spectateState.playerList == 0 then return end

    if InputPressed("lmb") then
        _switchPlayer(true)
    elseif InputPressed("rmb") then
        _switchPlayer(false)
    end
	if not _spectateState.hideLabel then
		UiPush()
			UiTranslate(UiCenter(), UiHeight() - 150)
			uiDrawTextPanel("Spectating: " .. GetPlayerName(_spectateState.currPlayer))
		UiPop()
	end
end

--- Update and render the spectator camera (client).
--
-- Call this once per frame from your client render loop.
--
-- Responsibilities:
--
-- * Handle map state integration (disabling map, blending from map camera)
-- * Smoothly interpolate into spectate camera transform
-- * Position camera behind spectated target (player or vehicle)
-- * Avoid clipping into world geometry using raycasts and occlusion checks
-- * Draw outlines around the spectated player/vehicle and temporary outline
--   around the attacker (if any)
--
-- @param[type=number] dt  Delta time in seconds
function spectateRender(dt)
    if not _spectateState.enabled or _spectateState.currPlayer == nil then
        return
    end

	_spectateState.mapCameraTransition = clamp(_spectateState.mapCameraTransition + GetTimeStep() * 1.5, 0.0, 1.0)
	if not _spectateState.mapAllowed then
		SetBool("game.disablemap", true)
		_spectateState.mapEnabled = false
	else
		_spectateState.mapEnabled = GetBool("game.map.enabled")
		if _spectateState.mapEnabled then
			_spectateState.mapCameraTransform = GetCameraTransform()
			_spectateState.mapCameraTransition = 0.0
		end
	end

	if _spectateState.transition >= 1.0 and not _isInMap() then
		_handleInput(dt)
	end

	_spectateState.time = _spectateState.time + dt
	if _spectateState.time >= _spectateState.delay then

		if _spectateState.initialCameraTransform == nil then
			_spectateState.initialCameraTransform = GetCameraTransform()
		end

		local TRANSITION_TIME = 1.0

		local alpha = math.clamp(_spectateState.time - _spectateState.delay, 0.0, TRANSITION_TIME) / TRANSITION_TIME
		_spectateState.transition = _easeInOutCubic(alpha)

		_calculateCameraTransform(_spectateState.currPlayer, dt)

		local ct = nil
		if _spectateState.transition >= 1.0 then
			ct = _spectateState.transform
			if not IsPlayerDisabled(_spectateState.currPlayer) then
				_drawOutline(_spectateState.eye, _spectateState.lookAt, _spectateState.currPlayer, _spectateState.vehicle)
			end
		else
			ct = _interpolateTransform(
				_spectateState.initialCameraTransform, 
				_spectateState.transform, 
				_spectateState.transition
			)
		end

		if _spectateState.mapCameraTransition < 1.0 then
			ct = _interpolateTransform(_spectateState.mapCameraTransform, ct, _spectateState.mapCameraTransition)
			SetFloat("game.map.fade", 1.0 - ( _spectateState.mapCameraTransition^0.5))
		end

		if GetPlayerHealth() <= 0.0 then
			SetCameraDof(0.1, 0.5 - 0.5 * _spectateState.transition)
		end
		if not _spectateState.mapEnabled then
			SetCameraTransform(ct)
		end
	else
		SetBool("game.disablemap", true) -- disable map while transitioning
	end


	if _spectateState.attacker ~= 0 and IsPlayerValid(_spectateState.attacker) and _spectateState.mapCameraTransition >= 1.0 then

		local a = 1.0 - math.clamp((_spectateState.time - 7.0) / 0.5, 0.0, 1.0)
		_drawPlayerOutline(_spectateState.attacker,1,0,0,0.5 * a)
	end
	
	if not _spectateState.mapAllowed then
		SetBool("game.disablemap", true)
	end
end


-- Internal functions

function _switchPlayer(up)
    
    local index = -1
    for i=1,#_spectateState.playerList do
        if _spectateState.playerList[i] == _spectateState.currPlayer then
            index = i
        end
    end

    if index <= 0 then
		_setCurrentPlayer(_spectateState.playerList[1])
        return
    end

    index = index + (up and 1 or -1)
    
    if index > #_spectateState.playerList then
        index = 1
    elseif index < 1 then
        index = #_spectateState.playerList
    end

	_setCurrentPlayer(_spectateState.playerList[index])
end

function _enableSpectate()
	_spectateState.enabled = true
	_spectateState.time = 0.0
	_spectateState.transition = 0.0
	_spectateState.initialCameraTransform = nil
	_spectateState.distance = 8.0
	_spectateState.actualDistance = 4.0

	SetBool("game.disablemap", true)
end

function _disableSpectate()
	if not _spectateState.enabled then return end

	_spectateState.enabled = false
	_spectateState.currPlayer = nil
	_spectateState.attacker = 0

	SetBool("game.disablemap", true)
end

function _isInMap()
	return _spectateState.mapCameraTransition < 1.0
end

function _easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        return 1 - ((-2 * t + 2)^3) / 2
    end
end

function _interpolateTransform(t1, t2, alpha)
	return Transform(
		VecLerp(t1.pos, t2.pos, alpha),
		QuatSlerp(t1.rot, t2.rot, alpha)
	)
end

function _setCurrentPlayer(player)
	if player == nil or not IsPlayerValid(player) then
		_spectateState.currPlayer = nil
		return
	end

	if player == _spectateState.currPlayer then
		return
	end

	_spectateState.currPlayer = player
	_spectateState.rotX = SPECTATE_DEFAULT_X_ROT
	_spectateState.rotY = 0.0
	_spectateState.followTransform = nil
end	

function _getAABB(bodies)
	
	local min = Vec()
	local max = Vec()

	for i = 1, #bodies do

		local bmin, bmax = GetBodyBounds(bodies[i])
			
		if i == 1 then
			min = bmin
			max = bmax
		else
			for j = 1, 3 do
				if bmin[j] < min[j] then min[j] = bmin[j] end
				if bmax[j] > max[j] then max[j] = bmax[j] end
			end
		end
	end

	return min, max
end

function _getDiameter(min, max)
	local dx = max[1] - min[1]
    local dy = max[2] - min[2]
    local dz = max[3] - min[3]
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

function _queryBodies(bodies, start, direction, distance, radius, onPreQuery)

	local hitPoint = nil
	local searching = true
	local rejectBodies = {}

	while searching do
		if onPreQuery then
			onPreQuery()
		end

		QueryRejectBodies(rejectBodies)
		
		local hit, dist, normal, shape = QueryRaycast(start, direction, distance, radius)
		if hit then
			local body = GetShapeBody(shape)
			rejectBodies[#rejectBodies+1] = body
			for i = 1, #bodies do
				if bodies[i] == body then
					hitPoint = VecAdd(start, VecScale(direction, dist))
					searching = false
				end
			end
		else
			searching = false
		end
		
	end

	return hitPoint ~= nil, hitPoint
end

function _dampVal(rate, dt)
    return 1.0 - 2.0^(-rate * dt)
end

function _checkOcclusion(eye, lookAt, step, onPreQuery, dbg)
	local up = Vec(0,1,0)
	local fwd = VecNormalize(VecSub(lookAt, eye))
	local right = VecNormalize(VecCross(fwd, up))
	up = VecNormalize(VecCross(right, fwd))

	if dbg then
		DebugLine(lookAt, VecAdd(lookAt, right), 1,0,0)
		DebugLine(lookAt, VecAdd(lookAt, up), 0,1,0)
		DebugLine(lookAt, VecAdd(lookAt, fwd), 0,0,1)
	end

	local samples = {}
	for i = 0, 2 do
		samples[#samples+1] = VecAdd(VecAdd(lookAt, VecScale(up, step)), VecScale(right, -step + i * step))
		samples[#samples+1] = VecAdd(lookAt, VecScale(right, -step + i * step))
		samples[#samples+1] = VecAdd(VecAdd(lookAt, VecScale(up, -step)), VecScale(right, -step + i * step))
	end


	local primaryHit = false
	local primaryHitDistance = VecLength(VecSub(lookAt, eye))
	local totalHits = 0
	for index, point in ipairs(samples) do

		if onPreQuery then
			onPreQuery()
		end
	
		local direction = VecSub(eye, point)
		local distance = VecLength(direction)
		direction = VecNormalize(direction)
	
		local hit, dist, normal, shape = QueryRaycast(point, direction, distance, 0)

		if hit then
			totalHits = totalHits + 1
			if dbg then
				DebugCross(point, 1,0,0,1)
			end
		else
			if dbg then
				DebugCross(point, 0,1,0,1)
			end
		end

		if index == 5 then
			primaryHit = hit
			primaryHitDistance = dist
		end
	end

	return primaryHit, primaryHitDistance, totalHits/9.0
end

function _drawBodyOutline(bodies, r,g,b,a)
	for i = 1, #bodies do
		DrawBodyOutline(bodies[i], r,g,b,a)
	end
end

function _drawPlayerOutline(player, r,g,b,a)
	if a <= 0 then return end

	local playerBodies = GetPlayerBodies(player)

	if playerBodies == nil or #playerBodies == 0 then
		return
	end

	local toolBody = GetToolBody(player)
	if toolBody ~= 0 then
		playerBodies[#playerBodies+1] = toolBody
	end
	_drawBodyOutline(playerBodies, r,g,b,a)
end

function _drawVehicleOutline(vehicle, r,g,b,a)
	if a <= 0 then return end

	local bodies = GetVehicleBodies(vehicle)
	_drawBodyOutline(bodies, r,g,b,a)
end

function _drawOutline(eye, lookAt, player, vehicle)
	local step = 0.5
	if vehicle ~= 0 then
		step = 1.5
	end

	local hit, dist, occlusion = _checkOcclusion(eye, lookAt, step, function ()
		QueryRejectPlayer(player)
		QueryRejectVehicle(vehicle)
	end, false)

	if vehicle ~= 0 then
		_drawVehicleOutline(vehicle, 1,1,1,occlusion * 0.2)
	else
		_drawPlayerOutline(player, 1,1,1,occlusion * 0.2)
	end
end


function _handleInput(dt)
	_spectateState.distance = _spectateState.distance - InputValue("mousewheel") * 0.5

	local inputY = -InputValue("cameray")
    local inputX = -InputValue("camerax")

	if inputY == 0 and inputX == 0 and not IsPlayerLocal(_spectateState.currPlayer) then
		_spectateState.timeSinceRotation = _spectateState.timeSinceRotation + dt
	else
		_spectateState.timeSinceRotation = 0.0
	end

	if _spectateState.rotY >=  math.pi * 2 then
		_spectateState.rotY = _spectateState.rotY - math.pi * 2
	elseif _spectateState.rotY <= -math.pi * 2 then
		_spectateState.rotY = _spectateState.rotY + math.pi * 2
	end

	if _spectateState.timeSinceRotation > 4.0 then
		local alpha = _dampVal(3.0, dt)
		_spectateState.rotX = _spectateState.rotX + (SPECTATE_DEFAULT_X_ROT - _spectateState.rotX) * alpha

		local sign = 1.0
		if _spectateState.rotY < 0 then
			sign = -1.0
		end

		local toAngle = 0.0
		if math.abs(_spectateState.rotY) > math.pi then
			toAngle = math.pi * 2 * sign
		end
		_spectateState.rotY = _spectateState.rotY + (toAngle - _spectateState.rotY) * alpha
	end

    _spectateState.rotX = _spectateState.rotX + inputY
    _spectateState.rotY = _spectateState.rotY + inputX
	_spectateState.rotX = math.max(math.min(_spectateState.rotX, 0.17), -1.4)
end

function _updateFollowTransform(transform, dt)
	if _spectateState.followTransform == nil then
		_spectateState.followTransform = transform
	end

	local alpha = _dampVal(20.0, dt)
	local beta = _dampVal(100.0, dt)
	_spectateState.followTransform.pos = VecLerp(_spectateState.followTransform.pos, transform.pos, beta)
	_spectateState.followTransform.rot = QuatSlerp(_spectateState.followTransform.rot, transform.rot, alpha)

	return _spectateState.followTransform
end

function _calculateCameraTransform(player, dt)
	local localRot = QuatAxisAngle(Vec(1,0,0), _spectateState.rotX * 180/3.14)
	localRot = QuatRotateQuat(QuatAxisAngle(Vec(0,1,0), _spectateState.rotY * 180/3.14), localRot)

	local lookAt = Vec()
	local eyeDir = Vec()

	local distanceMin = 1.0
	local distanceMax = 6.0
	
	local vehicle = GetPlayerVehicle(player)
	if vehicle ~= 0 then

		local vt = GetVehicleTransform(vehicle)
		vt = _updateFollowTransform(vt, dt)

		local dp, _ = GetVehicleDriverPos(vehicle)
		local dpw = TransformToParentPoint(vt, dp)
		lookAt = dpw

		local bodies = GetVehicleBodies(vehicle)
		local min,max = _getAABB(bodies)
		local diameter = _getDiameter(min, max)
        
		local worldRot = QuatRotateQuat(vt.rot, localRot)
		eyeDir = QuatRotateVec(worldRot, Vec(0,0,1))

		local start = VecAdd(lookAt, VecScale(eyeDir, diameter))
		local direction = VecScale(eyeDir,-1)
		local vehicleHit, vehicleHitPoint = _queryBodies(bodies, start, direction, diameter, 1.0, function ()
			QueryRequire("physical dynamic large")
		end)

		distanceMax = 20.0 
		if vehicleHit then
			distanceMin = VecLength(VecSub(lookAt, vehicleHitPoint))
		end
	else
		local transform = GetPlayerTransform(player)

		if GetPlayerHealth(player) <= 0 then
			local playerAnimator = GetPlayerAnimator(player)
			transform.pos = GetBoneWorldTransform(playerAnimator, "chest").pos
		end

		transform = _updateFollowTransform(transform, dt)

		lookAt = VecCopy(transform.pos)
		lookAt[2] = lookAt[2] + 1.5 - GetPlayerCrouch(player) * 0.5

		local worldRot = QuatRotateQuat(transform.rot, localRot)
		eyeDir = QuatRotateVec(worldRot, Vec(0,0,1))

		local bodies = GetPlayerBodies(player)
		local start = VecAdd(lookAt, VecScale(eyeDir, distanceMax))
		local direction = VecScale(eyeDir,-1)
		local playerHit, playerHitPoint = _queryBodies(bodies, start, direction, distanceMax, 0.2, function ()
			QueryInclude("player")
		end)
		if playerHit then
			distanceMin = VecLength(VecSub(lookAt, playerHitPoint))
		end
	end


	_spectateState.distance = math.max(distanceMin, math.min(_spectateState.distance, distanceMax))
	local eye = VecAdd(lookAt, VecScale(eyeDir, _spectateState.distance))

	local step = 0.5
	if vehicle ~= 0 then
		step = 1.5
	end

	local hit, dist, occlusion = _checkOcclusion(eye, lookAt, step, function ()
		QueryRejectPlayer(player)
		QueryRejectVehicle(vehicle)
	end)
	if hit and occlusion > 0.77 then
		local correctedDistance = dist - 0.1
		if correctedDistance < _spectateState.actualDistance then
			_spectateState.actualDistance = dist - 0.1
		end
	else
		local alpha = _dampVal(3.0, dt)
		_spectateState.actualDistance = _spectateState.actualDistance + (_spectateState.distance - _spectateState.actualDistance) * alpha
	end
	_spectateState.actualDistance = math.max(distanceMin, math.min(_spectateState.actualDistance, distanceMax))

	eye = VecAdd(lookAt, VecScale(eyeDir, _spectateState.actualDistance))

	local t = Transform(eye, QuatLookAt(eye, lookAt))
	_spectateState.transform = t
	_spectateState.eye = eye
	_spectateState.lookAt = lookAt
	_spectateState.vehicle = vehicle
end

function _drawAABB(mi,ma)
	DebugLine(Vec(mi[1],mi[2],mi[3]), Vec(ma[1],mi[2],mi[3]), 1, 0, 0)
	DebugLine(Vec(mi[1],mi[2],mi[3]), Vec(mi[1],mi[2],ma[3]), 1, 0, 0)
	DebugLine(Vec(ma[1],mi[2],ma[3]), Vec(ma[1],mi[2],mi[3]), 1, 0, 0)
	DebugLine(Vec(ma[1],mi[2],ma[3]), Vec(mi[1],mi[2],ma[3]), 1, 0, 0)

	DebugLine(Vec(mi[1],ma[2],mi[3]), Vec(ma[1],ma[2],mi[3]), 0, 1, 0)
	DebugLine(Vec(mi[1],ma[2],mi[3]), Vec(mi[1],ma[2],ma[3]), 0, 1, 0)
	DebugLine(Vec(ma[1],ma[2],ma[3]), Vec(ma[1],ma[2],mi[3]), 0, 1, 0)
	DebugLine(Vec(ma[1],ma[2],ma[3]), Vec(mi[1],ma[2],ma[3]), 0, 1, 0)

	DebugLine(Vec(mi[1],mi[2],mi[3]), Vec(mi[1],ma[2],mi[3]), 0, 0, 1)
	DebugLine(Vec(mi[1],mi[2],ma[3]), Vec(mi[1],ma[2],ma[3]), 0, 0, 1)
	DebugLine(Vec(ma[1],mi[2],mi[3]), Vec(ma[1],ma[2],mi[3]), 0, 0, 1)
	DebugLine(Vec(ma[1],mi[2],ma[3]), Vec(ma[1],ma[2],ma[3]), 0, 0, 1)
end
