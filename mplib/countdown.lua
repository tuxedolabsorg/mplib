#include "hud.lua"

--- Countdown
--
-- These functions provide the ability to display a countdown timer
-- that also locks players during countdown. 
-- 
-- Countdown timer should be initialized and ticked server-side and
-- drawn on client-side. Audio is played during countdown.
--
--     -- Example of typical usage
--     function server.init()
--         countdownInit(3.0)
--     end
--     
--     function server.tick(dt)
--         if countdownTick(dt) then
--             return -- Match hasn't started yet..
--         end
--     
--         -- countdown is now done!
--         -- do game logic.
--     end
--     
--     function client.draw()
--         countdownDraw()
--     end
--


shared.countdownTimer = 3
countdown = {skip = false, seconds = nil}

--- Initialize count down timer (server)
--
-- Initializes a count down timer that can be displayed for all players.
-- @param[type=number] countdownSeconds Time in seconds that represents the duration of the countdown.
function countdownInit(countdownSeconds)
    shared.countdownTimer = countdownSeconds
	countdownFinished = LoadSound("timer/game-start.ogg")
end

--- Tick down the timer (server)
--
-- Decrement the timer by `dt`. Players are locked during countdown.
-- @param[type=number] dt Time in seconds that represents the duration of the countdown.
-- @return[type=bool] true if the timer is still active.
function countdownTick(dt)
	if shared.countdownTimer <= 0.0 then return false end

	shared.countdownTimer = shared.countdownTimer - dt
	if shared.countdownTimer > 0 then
		for p in Players() do
            SetPlayerWalkingSpeed(0, p)
			DisablePlayerDamage(p)
			SetPlayerParam("disableinteract", true, p)
        end
	else
		PlaySound(countdownFinished) --NOTE: placed here since UISound stops when the window closes
	end

	shared.countdownTimer = math.max(shared.countdownTimer, 0.0)
	return shared.countdownTimer > 0.0
end

--- Draw the countdown timer (client)
--
-- Draws the countdown timer and a 'Match starts in...' label. 
-- @return[type=bool] true if the timer is still active.
function countdownDraw()
	if shared.countdownTimer <= 0.0 then return false end

	if client.countdownSeconds == nil then
		client.countdownSeconds = math.ceil(shared.countdownTimer)
	end

	local currSeconds = math.ceil(shared.countdownTimer)
	if currSeconds < client.countdownSeconds then
		if currSeconds == 0.0 then
			-- UiSound("mp/timer/game-start.ogg") -- TODO: final sound
		elseif currSeconds <= 3.0 then
			UiSound("timer/1-s-countdown.ogg")
		end

		client.countdownSeconds = currSeconds
	end

	hudDrawInformationMessage("Match starts in...", math.min(shared.countdownTimer - 0.5,0.25)/0.25)
	hudDrawCountDown(shared.countdownTimer)

	return shared.countdownTimer > 0.0
end

--- Check if countdown is complete.
--
-- Used to check if the countdown is finished or still progressing.
-- @return[type=bool] true if the countdown has reached 0.
function countdownDone()
	return shared.countdownTimer <= 0.0
end

--- Get remaining time.
--
-- Returns the remaining time, clamped to 0
-- @return[type=number] Remaining time.
function countdownGetTime()
	return math.max(shared.countdownTimer, 0.0)
end
    