--- Multiplayer HUD utilities
--
-- This system handles heads-up display (HUD) functionality in multiplayer,
-- including damage feedback, timers, round indicators, scoreboards and 
-- world markers.
--
-- Execution context:
-- * Server-side: initialization and game state control (shared via `shared._hud`)
-- * Client-side: rendering HUD elements and reacting to events
--
-- Main features:
-- * Damage numbers and directional damage indicators
-- * Round / match timers and respawn timers
-- * Scoreboards, team score breakdown, and player lists
-- * In-world markers (players, objectives, etc.)
-- * Banners, titles.

#include "script/common.lua"
#include "script/include/player.lua"
#include "ui.lua"
#include "ui/ui_helpers.lua"


_titleAlpha = nil

shared._hud = {}

_hud = { 
	damageIndicators = {}, 
	equipOption = 0, 
	settings = {initiated = false, visible = false, animation = 0.0}, 
	healthBarData = {}, 
	endSoundStarted = false, 
	bannerQueue = {}, 
	fade = { active = false, t = 0.0, fadeIn = 0.0, hold = 0.0, fadeOut = 0.0, alpha = 1.0} 
}


-- Initialize the HUD system (server).
--
-- Configures which HUD features are enabled globally.
--
-- @param[type=bool] useDamageIndicators Whether to show directional damage indicators for players.
function hudInit(useDamageIndicators)
	shared._hud.useDamageIndicators = useDamageIndicators
	shared._hud.gameIsSetup = false
end

--- Enable the "Unstuck" pause menu button (server).
--
-- Allows clients to respawn themselves if stuck in the environment.
-- This button has a cooldown of 10 seconds per client.
function hudAddUnstuckButton()
	shared._hud.enableUnstuck = true
end

--- Process HUD-related events and health bar updates (client).
--
-- Handles `playerhurt` events to trigger damage indicators for the
-- local player and updates per-player health bar state. Also adds
-- the "Unstuck" button into the pause menu if enabled.
--
-- @param[type=number] dt Delta time in seconds, used to update internal states.
function hudTick(dt)
	local c = GetEventCount("playerhurt")
	for i=1,c do
		local victim, before, after, attacker, _point, _impulse = GetEvent("playerhurt", i)
		if attacker ~= 0 and math.ceil((before-after)*100) > 0 then
			if shared._hud.useDamageIndicators and victim == GetLocalPlayer() then
				client._receiveDamage(attacker)
			end
		end
	end

	for p in Players() do
		if not _hud.healthBarData[p] then
			_hud.healthBarData[p] = { damage=0, decay=-1.0, alpha=0.0, health = GetPlayerHealth(p) }
		end

		local hbData = _hud.healthBarData[p]

		local currentHealth = GetPlayerHealth(p)
		if currentHealth < hbData.health then
			local damage = hbData.health - currentHealth
			hbData.damage = hbData.damage + damage
			hbData.decay = 2.0
		else
			hbData.decay = hbData.decay - dt
		end

		if currentHealth <= 0.0 then
			hbData.alpha = 0.0
		end

		if hbData.decay <= 0.0 then
			hbData.decay = 0.0
			hbData.damage = clamp(hbData.damage - dt, 0.0, 1.0)
		end

		hbData.health = currentHealth
	end

	if shared._hud.enableUnstuck then
		if lastUnstuckTime == nil then
			lastUnstuckTime = -10.0
		end

		local delta = GetTime() - lastUnstuckTime
		if delta < 10.0 then
			PauseMenuButton("Unstuck ("..(math.floor(10.0-delta)+1)..")", "bottom_bar", true)
		else
			if PauseMenuButton("Unstuck") then
				lastUnstuckTime = GetTime()
				ServerCall("server._unstuck", GetLocalPlayer())
			end
		end
	end
end


--- Draw a countdown timer on the screen (client).
--
-- Shows time remaining in a human-readable `MM:SS` format (for example `1:25`)
-- near the top of the screen. Plays a warning sound during the last seconds.
-- Should be called from the UI render loop.
--
-- @param[type=number] time Time in seconds to display.
-- @param[opt,type=number] alpha Alpha multiplier in range [0..1] for fading the timer.
function hudDrawTimer(time, alpha)

	if time > 10 then
		_hud.endSoundStarted = false
	elseif not _hud.endSoundStarted and time <= 10 then
		_hud.endSoundStarted = true
		UiSound("timer/10-s-timer.ogg")
	end

	local a = 1.0
	if alpha then
		a = alpha
	end
	
	if time < 0 then
		time = 0
	end
	
	local t = math.ceil(time)
	local m = math.floor(t/60)
	local s = math.ceil(t-m*60)
	
	UiPush()
	UiAlign("center top")
	UiTranslate(UiCenter(), 40)
	
	local width = 138
	local height = 52
	
	UiColor(COLOR_BLACK_TRNSP[1], COLOR_BLACK_TRNSP[2], COLOR_BLACK_TRNSP[3], COLOR_BLACK_TRNSP[4] * a)
	UiRoundedRect(width, height, 8)
	
	if time <= 10.0 then
		UiColor(0.83, 0.34, 0.34, a)
	else
		UiColor(COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], COLOR_WHITE[4] * a)
	end
	UiFont(FONT_BOLD, FONT_SIZE_36)

	UiPush()
	UiAlign("center middle")
	UiTranslate(0, height/2)

	UiText(":")

	UiAlign("left middle")
	
	UiPush()
	local w, h, x, y = UiGetTextSize("00")
	UiTranslate(-(w + 10), 0)
	if m < 10 then
		UiText("0"..m)
	else
		UiText(m)
	end
	UiPop()
	
	UiPush()
	UiTranslate(10, 0)
	if s < 10 then
		UiText("0"..s)
	else
		UiText(s)
	end
	UiPop()

	UiPop()
	
	UiPop()
end

--- Queue an animated banner to be shown on screen (client).
--
-- The banner is added to an internal queue and consumed by `hudDrawBanner`.
--
-- @param[type=string] text Text shown in the banner.
-- @param[type=table] color Background color `{r, g, b, a}` for the banner.
function hudShowBanner(text, color)
	_hud.bannerQueue[#_hud.bannerQueue + 1] = { text = text, color = color, time = 0.0 }
end

--- Render the in-game scoreboard UI (client).
--
-- Displays a styled scoreboard with a title, column headers, and grouped rows.
-- Each group can have a name and color, and each row corresponds to a player.
-- The scoreboard animates when opening/closing.
--
-- @param[type=bool] show Whether the scoreboard should be visible.
-- @param[type=string] title   Optional title displayed at the top; if empty or `nil` no title is shown.
-- @param[type=table]  columns List of column descriptor tables:
--   * `name` (string)  Header label.
--   * `width` (number) Column width in pixels.
--   * `align` (string, optional) `"left"`, `"center"`, or `"right"`.
-- @param[type=table]  groups  List of group tables:
--   * `name` (string)      Group header text.
--   * `color` (table)      RGB color `{r, g, b}`.
--   * `outline` (bool)     Draw outline around the group (optional).
--   * `dim` (bool)         De-emphasize style for the group (optional).
--   * `rows` (table)       List of row tables:
--   * `player` (number) Player ID.
--   * `columns` (table) Per-column text values.
function hudDrawScoreboard(show, title, columns, groups)

	if not _scoreboard_anim then
        _scoreboard_anim = { 
            param = 0.0, 
            last_h = 0, 
            lastShow = false,
            openSound = LoadSound("shift-menu.ogg"),
            closeSound = LoadSound("shift-menu.ogg")
        }
    end

    if _scoreboard_anim.lastShow ~= show then
        _scoreboard_anim.lastShow = show
        if show then
            PlaySound(_scoreboard_anim.openSound)
        else
            PlaySound(_scoreboard_anim.closeSound)
        end
    end

	local dt = GetTimeStep()
	_scoreboard_anim.param = math.clamp(_scoreboard_anim.param + 7.5 * (show and dt or -dt), 0.0, 1.0)

	if _scoreboard_anim.param <= 0.0 then
		return
	end

	UiPush()
		UiTranslate(40, 40)
		
		-- apply animation
		UiTranslate(0, _scoreboard_anim.last_h*0.5)
		UiColorFilter(1,1,1, (_scoreboard_anim.param - 0.2) / 0.8)
		UiScale(1, smoothstep(0.0, 1.0, _scoreboard_anim.param))
		UiTranslate(0, -_scoreboard_anim.last_h*0.5)
		
		local w, h = _drawBoard(title, columns, groups, false, true)
		_scoreboard_anim.last_h = h
	UiPop()
end

--- Render the end-of-match results scoreboard UI (client).
--
-- Shows an animated results banner followed by a scoreboard with per-team
-- results. Includes a button panel allowing the host to choose game modes
-- or continue.
--
-- @param[type=string] bannerLabel Text used in the initial results banner.
-- @param[type=table] bannerColor Banner background color `{r, g, b, a}`.
-- @param[type=string] title Scoreboard title.
-- @param[type=table] columns List of column descriptor tables (see `hudDrawScoreboard`).
-- @param[type=table] groups List of group tables (see `hudDrawScoreboard`).
-- @param[opt,type=function] continueFunction Callback executed when the "Play Again" / continue button is pressed.
-- @param[opt,type=string] continueLabel  Custom label for the continue button (defaults to `"Play Again"`).
--
-- @return[type=number] boardWidth   Width of the scoreboard in pixels.
-- @return[type=number] boardHeight  Height of the scoreboard in pixels.
-- @return[type=number] param        Animation parameter in range [0..1].
function hudDrawResults(bannerLabel, bannerColor, title, columns, groups, continueFunction, continueLabel)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
	end

	continueLabel = continueLabel or "Play Again"
	SetBool("game.disablemap", true)

	if not _scoreresults_anim then
		_scoreresults_anim = { time = 0.0, param = 0.0 }
	end

	local bannerAnimTime = 5.0
	
	local dt = GetTimeStep()
	_scoreresults_anim.time = _scoreresults_anim.time + dt

	UiPush()
	if not hudDrawResultsAnimation(_scoreresults_anim.time, bannerLabel, bannerColor) then
		return 0, 0, 0
	end
	
	_scoreresults_anim.param = math.clamp(_scoreresults_anim.param + dt, 0.0, 1.0)

	-- Assumes winner in the first group and will de-emphasize other groups
	for i = 1, #groups do
		groups[i].dim = i > 1
	end
	-- apply animation
	UiTranslate(0, UiMiddle())
	UiColorFilter(1,1,1, math.sqrt(_scoreresults_anim.param))
	--UiScale(1, math.sqrt(_scoreresults_anim.param))
	UiTranslate(0, -UiMiddle())

	UiPush()
		UiTranslate(UiCenter(), UiMiddle())
		local boardWith, boardHeight = _drawBoard(title, columns, groups, true, false, #groups == 1)
	UiPop()

	UiPush()
		local y = UiMiddle() + boardHeight/2 + 20
		UiAlign("center top")
		UiTranslate(UiCenter(), y)

		if IsPlayerHost() then
			UiTranslate(0, 40)
			UiMakeInteractive()
			
			local buttonHeight = 40
			local buttonWidth = 290

			local gap = 10
			local padding = 20

			uiDrawPanel(buttonWidth + 2*padding, padding + buttonHeight + gap + buttonHeight + padding, 16)

			UiPush()
				UiTranslate(0, 20)
				if uiDrawSecondaryButton("Game Modes", buttonWidth) then
					SetBool("game.pausemenu.gamemodes", true)
				end

				UiTranslate(0, buttonHeight + gap)

				if uiDrawPrimaryButton(continueLabel, buttonWidth) then
					if continueFunction ~= nil then
						continueFunction()
					else
						SetString("game.gamemode.next", GetString("game.gamemode"))
					end
				end

			UiPop()
		else
			uiDrawTextPanel("loc@UI_TEXT_WAITING_FOR_HOST", 1)
		end

	UiPop()

	return boardWith, boardHeight, _scoreresults_anim.param
end


--- Draw a simple two-team score HUD (client).
--
-- Displays two team scores side by side, each in a colored box, near the top
-- of the screen.
--
-- @param[type=table]  team1Color Color `{r, g, b}` for Team 1.
-- @param[type=number] team1Score Score for Team 1.
-- @param[type=table]  team2Color Color `{r, g, b}` for Team 2.
-- @param[type=number] team2Score Score for Team 2.
-- @param[opt,type=number] alpha Alpha multiplier in range [0..1].
function hudDrawScore2Teams(team1Color, team1Score, team2Color, team2Score, alpha)


	local a = 1.0
	if alpha then
		a = alpha
	end

	UiPush()
	UiFont(FONT_BOLD, FONT_SIZE_32)

	local width = 95
	local height = 44
	
	UiAlign("center middle")
	UiTranslate(UiCenter(), 40 + 26)
	
	UiPush()
	UiTranslate(-(138/2+width/2+10), 0)
	UiColor(team1Color[1], team1Color[2], team1Color[3], a)
	UiRoundedRect(width, height, 8)
	UiColor(COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], COLOR_WHITE[4] * a)
	UiText(team1Score)
	UiPop()
	
	UiPush()
	UiTranslate(138/2+width/2+10, 0)
	UiColor(team2Color[1], team2Color[2], team2Color[3], a)
	UiRoundedRect(width, height, 8)
	UiColor(COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], COLOR_WHITE[4] * a)
	UiText(team2Score)
	UiPop()
	UiPop()
end


--- Display the current round indicator (client).
--
-- Renders text such as `Round 2/5` below the main timer.
--
-- @param[type=number] currentRound Current round number (starting from 1).
-- @param[type=number] maxRound Total number of rounds in the match.
-- @param[opt,type=number] width Minimum width in pixels for the text box.
function hudDrawRounds(currentRound, maxRound, width)

	if GetBool("game.map.enabled") then return end
	if GetPlayerScreen(GetLocalPlayer()) ~= 0 then return end

	UiPush()
		UiFont(FONT_BOLD, FONT_SIZE_22)
		local txt = "Round ".. currentRound.."/"..maxRound
		local w,h = UiGetTextSize(txt)

		if width and width > w then
			w = width
		end

		local timerEndY = 92
		local gap = 10

		UiTranslate(UiCenter(), timerEndY + gap + (h + 20)/2)
		UiAlign("center middle")
		UiColor(COLOR_BLACK_TRNSP)
		UiRoundedRect(w + 20, h + 20, 8)

		UiTextOutline(COLOR_BLACK)
		UiColor(COLOR_WHITE)
		UiText(txt)
	UiPop()
end

--- Draw a breakdown table of team scores per round (client).
--
-- Displays a table with team names on rows and rounds as columns, optionally
-- including a total column. A specific round column can be highlighted.
--
-- @param[type=string] header Header text displayed at the top of the table.
-- @param[type=table]  teamNames List of team names (`string`).
-- @param[type=table]  teamColors List of team colors `{r, g, b}`.
-- @param[type=table]  scoreTable List of round score arrays. Each entry is:
--
--    scoreTable[round][teamIndex] = score
--
-- @param[type=bool] drawTotal If `true`, draw an extra total column for each team.
-- @param[opt,type=number] highlightColumn Round index to visually highlight in the table (<= 0 disables highlight).
-- @param[opt,type=number] minWidth Minimum width in pixels for the entire table.
--
-- @return[type=number] totalWidth Actual drawn width in pixels.
-- @return[type=number] totalHeight Actual drawn height in pixels.
-- @usage
-- Example
--     -- construct the score matrix
--     local roundScores = {}
--     roundScores[1] = { team1_round1_score, team2_round1_score }
--     roundScores[2] = { team1_round2_score, team2_round2_score }
--     -- for as many rounds required.
--
--     local teamColors = { {1, 0, 0}, {0, 0, 1} }
--     local teamNames = { "Red team", "Blue team" }
--
--     hudDrawRoundScroreBreakdown("Current score", teamNames, teamColors, roundScores, false, currRound)
function hudDrawRoundScroreBreakdown(header, teamNames, teamColors, scoreTable, drawTotal, highlightColumn, minWidth)
	
	if highlightColumn <= 0 then
		highlightColumn = nil
	end

	local teamCount = #teamNames
	local roundCount = #scoreTable

	local widestTeamName = 0
	local rowHeight = 36
	local textPadding = 20
	local headerHeight = 57
	if not _isTextValid(header) then headerHeight = 0 end


	UiFont(FONT_BOLD, FONT_SIZE_30)
	for i=1,teamCount do
		widestTeamName, _ = math.max(UiGetTextSize(teamNames[i]), widestTeamName + textPadding * 2)
	end

	local scoreWidth = 36
	local padding = 4
	local border = 20
	local totalColumnWidth = 60
	local highlightColumnPadding = 6
	local xOffset = 0

	local totalWidth = border *2 + widestTeamName + scoreWidth * roundCount + padding * roundCount

	if drawTotal then
		totalWidth = totalWidth + totalColumnWidth + padding
	end

	if highlightColumn ~= nil and highlightColumn <= roundCount then
		totalWidth = totalWidth + highlightColumnPadding * 2
	end

	if minWidth and totalWidth < minWidth then
		xOffset = (minWidth - totalWidth) * 0.5
		totalWidth = minWidth
	end


	local totalHeight = (teamCount + 1) * rowHeight + teamCount * padding + 2 * border + headerHeight

	UiPush()
		UiAlign("center top")
	
		uiDrawPanel(totalWidth, totalHeight, 10)
		UiColor(COLOR_WHITE)

		UiTranslate(0, border)

		if headerHeight > 0 then
			-- header
			UiPush()
				UiTranslate(0, -10)
				UiFont(FONT_BOLD, FONT_SIZE_30)
				UiColor(COLOR_WHITE)
				UiAlign("center top")
				UiTranslate(0, 10)
				UiText(header)
				UiColor(0.53, 0.53, 0.53)
				UiTranslate(0, 37)
				UiRect(totalWidth - border * 2, 2)
			UiPop()

			UiTranslate(0, headerHeight)
		end

		UiPush()
			UiTranslate(-totalWidth * 0.5 + border + xOffset, rowHeight * 0.5)
			UiTranslate(widestTeamName, 0)

			UiColor(COLOR_WHITE)
			UiFont(FONT_BOLD, FONT_SIZE_20)
			UiAlign("right middle")
			UiText("Rounds #")
			UiAlign("center middle")
			
			if highlightColumn then
				UiPush()
					UiAlign("center top")
					local thickness = 2
					UiTranslate(highlightColumn * (scoreWidth + padding) - 12, -highlightColumnPadding - rowHeight * 0.5)
					UiColor(COLOR_YELLOW)
					UiRoundedRectOutline(scoreWidth + 2*padding+2*thickness, (teamCount+1) * (rowHeight + padding) + 2*padding, 8, thickness)
				UiPop()
			end

			UiTranslate(scoreWidth * 0.5 + padding, 0)

			for j=1,#scoreTable do

				if highlightColumn == j then
					UiTranslate(highlightColumnPadding, 0)
				end

				if j > 1 then
					UiTranslate(scoreWidth + padding, 0)
				end

				UiText(j)
				
				if highlightColumn == j then
					UiTranslate(highlightColumnPadding, 0)
				end
			end
			if drawTotal then
				UiAlign("left middle")
				UiTranslate(totalColumnWidth * 0.5, 0)
				UiText("Total")
			end
		UiPop()

		UiTranslate(0, rowHeight + padding + rowHeight * 0.5)

		for i=1,teamCount do
			
			UiPush()
				UiTranslate(-totalWidth * 0.5 + border + xOffset, 0)

				UiAlign("left middle")
				
				UiColor(teamColors[i][1], teamColors[i][2], teamColors[i][3])
				UiRoundedRect(widestTeamName, rowHeight, 6)
				
				UiColor(COLOR_WHITE)
				UiAlign("center middle")
				UiTranslate(widestTeamName * 0.5, 0)
				UiText(teamNames[i])

				UiPush()
					UiTranslate(widestTeamName * 0.5 + padding, 0)

					local scoreSum = nil

					for j=1,#scoreTable do
						UiAlign("left middle")

						local score = scoreTable[j][i]

						if score then
							if scoreSum == nil then
								scoreSum = score
							else
								scoreSum = scoreSum + score
							end
						end

						local hasWinningRoundScore = false
						if score then
							hasWinningRoundScore = true
							for t=1,teamCount do
								if t ~= i and scoreTable[j][t] and score < scoreTable[j][t] then
									hasWinningRoundScore = false
								end
							end
						end

						local color = { 1, 1, 1, hasWinningRoundScore and 0.2 or 0.1 }
						local textColor = hasWinningRoundScore and COLOR_YELLOW or COLOR_WHITE

						if highlightColumn == nil then
							if hasWinningRoundScore then
								textColor = COLOR_WHITE
								color = teamColors[i]
								color[4] = 1.0
							end
						else
							if highlightColumn == j and hasWinningRoundScore then
								textColor = COLOR_WHITE
								color = teamColors[i]
								color[4] = 1.0
							end
						end

						if highlightColumn == j then
							UiTranslate(highlightColumnPadding, 0)
						end

						UiColor(color[1], color[2], color[3], color[4])
						UiRoundedRect(scoreWidth, rowHeight, 6)
						
						if score then
							UiPush()
								UiTranslate(scoreWidth * 0.5, 0)
								UiColor(textColor[1], textColor[2], textColor[3])
								UiAlign("center middle")
								UiFont(FONT_BOLD, FONT_SIZE_20)
								UiText(score)
							UiPop()
						end

						if highlightColumn == j then
							UiTranslate(highlightColumnPadding, 0)
						end

						UiTranslate(scoreWidth + padding, 0)
					end

					if drawTotal then
						color = teamColors[i]
						color[4] = 1.0
						UiColor(color[1], color[2], color[3], color[4])
						UiRoundedRect(totalColumnWidth, rowHeight, 6)
						if scoreSum then
							UiPush()
								UiTranslate(totalColumnWidth * 0.5, 0)
								UiColor(COLOR_WHITE)
								UiAlign("center middle")
								UiFont(FONT_BOLD, FONT_SIZE_20)
								UiText(scoreSum)
							UiPop()
						end
					end

				UiPop()
			UiPop()

			UiTranslate(0, rowHeight + padding)
		end
	UiPop()

	return totalWidth, totalHeight
end

--- Draw a animated title banner (client).
--
-- Fades a title message in and out near the top of the screen. 
-- If `show` is `nil`, the title will remain visible for
-- 5 seconds and then fade out automatically.
--
-- Should be called every frame from the client’s UI draw loop.
--
-- @param[type=number] dt Time step in seconds, used for timing and fade animation.
-- @param[type=string] title Title text to display.
-- @param[opt,type=bool] show Explicit visibility flag; if `nil` the function
--   will auto-hide the title after 5 seconds.
function hudDrawTitle(dt, title, show)

	if not _titleState then
		_titleState = { time = 0, show = false }
		_titleAlpha = 0.0
	end

	_titleState.time = _titleState.time + dt

	if show == nil then
		if _titleState.time > 5 then
			show = false
		else
			show = true
		end
	end

	if show ~= _titleState.show then
		_titleState.show = show
		if show then
			SetValue("_titleAlpha", 1, "cosine", 0.25)
		else
			SetValue("_titleAlpha", 0, "cosine", 0.25)
		end
	end

	if _titleAlpha > 0 and not GetBool("game.map.enabled") then
		UiPush()
		UiTranslate(0, 140*_titleAlpha-140)
		uiDrawPanel(UiWidth(), 140)
		UiColor(COLOR_WHITE)
		UiFont("bold.ttf", FONT_SIZE_80)
		UiAlign("center middle")
		local w, h = UiGetTextSize(title)
		UiTranslate(UiCenter(), 70)
		UiText(title)
		UiPop()
	end
end

--- Draw a centered information message panel (client).
--
-- Renders a small text panel with the specified message near the top of the screen.
--
-- @param[type=string] message Text to display.
-- @param[type=number] alpha Alpha multiplier in range [0..1] for fading.
function hudDrawInformationMessage(message, alpha)
	UiPush()
	UiTranslate(UiCenter(), 190)
	uiDrawTextPanel(message, alpha)
	UiPop()
end

--- Draw a large numeric countdown in the center of the screen (client).
--
-- Shows the remaining time as a big number with a fade effect.
--
-- @param[type=number] time Remaining time in seconds. Values <= 0 disable rendering.
function hudDrawCountDown(time)
	if time <= 0.0 then return end

	local alpha = clamp(time/0.25, 0.0, 1.0)
	
	UiPush()
	UiFont(FONT_BOLD, 100)
	UiColor(1,1,1, alpha)
	UiTextShadow(0,0,0,0.5 * alpha,2.0)
	UiTranslate(UiCenter(), 310)
	UiAlign("center middle")
	UiScale(2,2)
	UiText(tostring(math.ceil(time)))
	UiPop()
end

--- Draw a respawn countdown for the local player (client).
--
-- When `time` is greater than 0, displays a "Respawn in..." message and a
-- numeric countdown using `hudDrawCountDown`. Also triggers a brief fade
-- effect as the respawn approaches.
--
-- @param[type=number] time Remaining respawn time in seconds, or `nil` / <= 0 if alive.
function hudDrawRespawnTimer(time)

	local alive = time == nil or time <= 0.0
	if alive then
		return
	end

	if not _hud.fade.active and time <= 1.0 then
		_hud.fade.active = true
		_hud.fade.t = 0.0
		_hud.fade.fadeIn = 0.5
		_hud.fade.hold = 1.0
		_hud.fade.fadeOut = 0.5
	end

	hudDrawInformationMessage("Respawn in...", math.min(time - 0.5,0.25)/0.25)
	hudDrawCountDown(time)
end

--- Draw world markers for a list of players (client).
--
-- Creates marker entries for each valid remote player and forwards them to
-- `hudDrawWorldMarkers`. Uses the player position and name as label.
--
-- @param[type=table] players List of player IDs.
-- @param[type=bool] lineOfSightRequired If `true`, markers are hidden when occluded.
-- @param[type=number] maxRange Maximum range in meters; markers beyond this are hidden.
-- @param[opt,type=table] color Color `{r, g, b, a}`; defaults to white.
function hudDrawPlayerWorldMarkers(players, lineOfSightRequired, maxRange, color)
	local markers = {}
	for i=1,#players do
		local p = players[i]
		if not IsPlayerLocal(p) and GetPlayerHealth(p) > 0 and not IsPlayerDisabled(p) and IsPlayerValid(p) then
			markers[1 + #markers] = { 
				pos=VecAdd(GetPlayerTransform(p).pos, Vec(0, 1.0, 0)), 
				offset = Vec(0, 1.2, 0),
				color= color or COLOR_WHITE,
				label=GetPlayerName(p),
				lineOfSightRequired = lineOfSightRequired,
				maxRange = maxRange or 9999.0,
				icon = "ui/hud/team-direction.png",
				drawIconInView = false,
				player = p
			}
		end
	end
	hudDrawWorldMarkers(markers)
end

--- Draw dynamic in-world markers on the HUD (client).
--
-- Projects world-space marker positions to screen space and renders labels
-- and/or icons. Markers may include line-of-sight checks, maximum range,
-- and optional health bars for associated players.
--
-- @param[type=table] markers List of markers.
-- @usage
-- A marker table can have these members:
--     pos (Vec3)                  World-space position.
--     offset (Vec3)               offset added before projection. (Optional)
--     color ({r, g, b, a})        Marker color.
--     label (string)              text label. (Optional)
--     maxRange (number)           max distance (default 9999.0). (Optional)
--     lineOfSightRequired (bool)  hide when occluded.
--     player (number)             player ID used for occlusion/vehicle checks. (Optional)
--     icon (string)               icon image path. (Optional)
--     uiOffset ({x, y})           2D offset after projection. (Optional)
--     drawIconInView (bool)       draw icon when marker is on-screen. (Optional)
--     iconColor ({r, g, b})       icon color override. (Optional)
-- @usage
-- Example
--    local worldMarkers = {}
--    for p in Players() do
--        local marker = {}
--        marker.pos = GetPlayerTransform(p).pos
--        marker.color = {1.0, 1.0, 1.0}
--        marker.label = GetPlayerName(p)
--        marker.offset = Vec(0,2,0)
--        marker.lineOfSightRequired = false
--        marker.player = p
--        worldMarkers[1 + #worldMarkers] = marker
--    end
--    hudDrawWorldMarkers(worldMarkers)
function hudDrawWorldMarkers(markers)
	
	if GetBool("game.map.enabled") then
		return
	end
	
	UiPush()
	UiFont("bold.ttf", FONT_SIZE_25)
	local ct = GetCameraTransform()
	
	for i=1,#markers do
		UiPush()
		local marker = markers[i]

		local vehicle = marker.player and GetPlayerVehicle(marker.player) or 0
		if vehicle > 0 then
			if vehicle > 0 then
				marker.offset[2] = marker.offset[2] - 1.0
			end
		end

		local x, y, dist = UiWorldToPixel(VecAdd(marker.pos, marker.offset and marker.offset or Vec(0,0,0)))
		local padding = 42
		local inView = false
		
		if not marker.maxRange then
			marker.maxRange = 9999.0
		end

		marker.drawIconInView = marker.drawIconInView == nil and true or marker.drawIconInView

		local direction = 0
		
		if dist > 0 and x > padding and y > padding and x < (UiWidth() - padding) and y < (UiHeight() - padding) then
			inView = true
		else
			if dist < 0 then
				y = UiHeight()
				x = UiWidth() - x
			end

			if x < padding then
				direction = 3
			elseif x > UiWidth() - padding then
				direction = 1
			elseif y < padding then
				direction = 2
			elseif y > UiHeight() - padding then
				direction = 4
			end
			
			x = clamp(x, padding, UiWidth() - padding)
			y = clamp(y, padding, UiHeight() - padding)
		end

		local hasIcon = marker.icon and UiHasImage(marker.icon)
		local doRenderIcon = false
		local doRenderLabel = false
		
		local toMarker = VecSub(marker.pos, ct.pos)
		local dir = VecNormalize(toMarker)
		local distToMarker = VecLength(toMarker)
		
		local inRange = distToMarker <= marker.maxRange

		if inRange and inView then
			doRenderIcon = marker.drawIconInView and hasIcon
			doRenderLabel = marker.label and marker.label ~= ""
			
			if marker.lineOfSightRequired then
				QueryRequire("physical")
				
				if marker.player then
					if vehicle > 0 then
						QueryRejectVehicle(vehicle)
					end
				end
				local hit = QueryRaycast(ct.pos, dir, distToMarker)
				doRenderLabel = doRenderLabel and not hit
				doRenderIcon = doRenderIcon and not hit
			end
		elseif inRange then
			doRenderIcon = not marker.lineOfSightRequired
		end

		UiTranslate(x, y)

		if inView then
			local distanceScale = clamp(1.0 - ((distToMarker-15) / 75.0), 0.66, 1.0)
			UiTranslate(0, -clamp(distToMarker, 0, 50) * 0.3)
			UiScale(distanceScale)
		end
		
		if doRenderIcon or doRenderLabel then
			UiPush()	

			if inView and marker.uiOffset then
				UiTranslate(marker.uiOffset[1], marker.uiOffset[2])
			end

			local c = marker.color
			UiColor(c[1], c[2], c[3])
			UiAlign("center bottom")
			if doRenderLabel then
				UiPush()				
					UiTextShadow(0, 0, 0, 1, 2.0, 0.85)
					UiTextOutline(0, 0, 0, 1, 0.5)
					UiText(marker.label)
				UiPop()
			end
			
			if doRenderIcon then
				if hasIcon then
					local size = inView and 48 or 40
					local w, h = UiGetImageSize(marker.icon)
					local greatestDimension = math.max(w, h)
					UiPush()

						if marker.iconColor then
							UiColor(marker.iconColor[1], marker.iconColor[2], marker.iconColor[3])
						end

						if doRenderLabel then
							UiTranslate(0, -h * 0.5)
						end

						if not inView then
							UiAlign("center middle")
						end
						
						UiScale(size/greatestDimension, size/greatestDimension)
						UiImage(marker.icon)
					UiPop()
				else
					UiPush()
						if not inView then
							UiAlign("center middle")
						end
						UiScale(0.5) -- rounded_rect is 64x64
						UiImage("gfx/rounded_rect.png")
					UiPop()
				end

				if not inView then
					UiPush()
						UiAlign("center middle")
						local arrowSpacing = 28
						if direction == 1 then
							UiTranslate(arrowSpacing, 0)
						elseif direction == 2 then
							UiTranslate(0, -arrowSpacing)
						elseif direction == 3 then
							UiTranslate(-arrowSpacing, 0)
						elseif direction == 4 then
							UiTranslate(0, arrowSpacing)
						end
						UiRotate(direction * 90)
						UiScale(0.5)
						UiImage("ui/hud/arrow-direction.png")
					UiPop()
				end
			end
			
			local player = marker.player
			if player then
				if not _hud.healthBarData[player] then
					_hud.healthBarData[player] = { damage=0, decay=-1.0, alpha=0.0, health = GetPlayerHealth(player) }
				end

				local hbData = _hud.healthBarData[player]
				local healthBarRendered = false
				if inView then
					local health = hbData.health
					local alpha = hbData.alpha
					local healthBefore = clamp(health + hbData.damage, 0, 1)
					local redAlpha = clamp((hbData.damage) / 0.1, 0.0, 1.0)
					
					local width = 91
					local height = 12
					local radius = 6
					
					if hbData.alpha > 0.0 then
						UiPush()
							UiColorFilter(1,1,1,hbData.alpha)
							UiAlign("left middle")

							UiTranslate(-width*0.5, 13)
			
							if marker.color and (marker.color[1] ~= 1 or marker.color[2] ~= 1 or marker.color[3] ~= 1) then
								UiPush()
								local thickness = 3
								UiTranslate(-thickness, 0)
								UiColor(marker.color[1], marker.color[2], marker.color[3], hbData.alpha)
								UiRoundedRectOutline(width+2*thickness, height+2*thickness, radius+3, thickness)
								UiPop()
							end				
							
							UiColor(0, 0, 0, 0.75)
							UiRoundedRect(width, height, radius)
							
							UiTranslate(2, 0)
							if health ~= healthBefore and healthBefore > 0 then
								local w = (width-4)*healthBefore
								if w < 12 then w = 12 end
								local h = height-4
								UiColor(0.65,0.11,0.11,redAlpha)
								UiRoundedRect(w, h, radius - 2)
							end
		
							if health > 0 then
								local w = (width-4)*health
								if w < 12 then w = 12 end
								local h = height-4
								UiColor(1,1,1,1)
								UiRoundedRect(w, h, radius - 2)
							end
						UiPop()
					end
					healthBarRendered = health > 0 and health < 1
				end
				
				hbData.alpha = clamp(hbData.alpha + (healthBarRendered and 5.0 or -5.0) * GetTimeStep(), 0.0, 1.0)
			end

			UiPop()
		end
		UiPop()
	end
	UiPop()

end


--- Draw directional damage indicators for the local player (client).
--
-- Renders fade-out indicators pointing towards recent damage sources, based on
-- the local player’s orientation and the attack direction.
--
-- @param[type=number] dt Delta time in seconds, used to fade indicators.
function hudDrawDamageIndicators(dt)
	local pt = GetPlayerTransform()
	local forward = VecNormalize(QuatRotateVec(pt.rot, Vec(0, 0, -1)))
	local right = VecNormalize(QuatRotateVec(pt.rot, Vec(1, 0, 0)))
	
	for i, indicator in ipairs(_hud.damageIndicators) do
		indicator.alpha = indicator.alpha - dt
		if indicator.alpha <= 0.0 then
			table.remove(_hud.damageIndicators, i)
		else
			local damagePos = indicator.position
			
			local dir = VecNormalize(VecSub(damagePos, pt.pos))
			
			local x = (0.5 + 0.5 * VecDot(dir, right)) * UiWidth()
			local y = (0.5 - 0.5 * VecDot(dir, forward)) * UiHeight()
			
			local padding = 75
			
			x = clamp(x, padding, UiWidth() - padding)
			y = clamp(y, padding, UiHeight() - padding)
			
			UiPush()
			UiTranslate(x, y)
			
			local angle = math.acos(VecDot(dir, forward)) * 180.0 / 3.1415
			if VecDot(dir, right) > 0 then angle = -angle end
			UiRotate(angle)
			UiScale(1.0)
			UiColorFilter(0.6, 0.0, 0.0, 0.5 * indicator.alpha)
			UiAlign("center middle")
			UiImage("gfx/damage-indicator.png")
			UiPop()
		end
	end
	
end

--- Check if the game has been set up by the host.
--
-- Returns the current setup state as managed by the HUD system, typically
-- toggled when the host presses **Start** in `hudDrawGameSetup`.
--
-- @return[type=bool] setup `true` if the game has been set up, `false` otherwise.	
function hudGameIsSetup()
	return shared._hud.gameIsSetup
end

--- Draws the host-only game setup UI and initializes settings (client).
--
-- **For host**:
--
-- Two buttons buttons will be drawn; 
--
-- - *Start* that progresses the setup (`hudGameIsSetup()` will return true).
--
-- - *Settings* that toggles the visibility of the settings view where the host can choose settings
-- from those provided.
--
--
-- **For clients**:
--
-- - A message: "Waiting for host ..." is drawn on the screen until the host is done configuring settings.
--
--
-- @usage
-- -- Example settings table that can be passed to hudDrawGameSetup(...)
-- local settings = {
--   {
--     title = "",
--     items = {
--       {
--         key    = "savegame.mod.settings.time",
--         label  = "Time",
--         info   = "Select match time.",
--         options = {
--           { label = "05:00", value = 5*60 },
--           { label = "10:00", value = 10*60 },
--           { label = "03:00", value = 3*60 },
--         }
--       },
--       {
--         key    = "savegame.mod.settings.unlimited",
--         label  = "Unlimited tool ammo",
--         info   = "Toggle unlimited ammo",
--         options = {
--           { label = "On", value = 1 }, -- Use `value` = 1 or 0 for boolean values.
--           { label = "Off", value = 0 },
--         }
--       }
--     }
--   }
-- }
--
-- @param[type=table] settings Array of groups containing configuration items.
-- @return[type=bool] started `true` if the Play/Start button has been pressed, `false` otherwise.
function hudDrawGameSetup(settings)
	local playPressed = false
	SetBool("game.disablemap", true)

	if not IsPlayerHost(GetLocalPlayer()) then
		UiPush()
		UiTranslate(UiCenter(), UiMiddle() + 300)
		uiDrawTextPanel("loc@UI_TEXT_WAITING_FOR_HOST", 1)
		UiPop()
	else
        if LastInputDevice() == UI_DEVICE_GAMEPAD then
            UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
		end
		UiMakeInteractive()

		local hasSettings = settings ~= nil

		if hasSettings then
			for i = 1, #settings do
				local group = settings[i]
				for j = 1, #group.items do
					local item = group.items[j]

					local hasKey = HasKey(item.key)
					if hasKey and not _hud.settings.initiated then 
						-- Handle savegame keys. Re-init values (can be changed during mod dev)
						local index = GetInt(item.key..".index")
						SetString(item.key, item.options[index].value)
					elseif not hasKey then
						-- Set default value
						SetInt(item.key..".index", 1)
						SetString(item.key, item.options[1].value)
					end
				end
			end
		end
		_hud.settings.initiated = true
		
		local width = 330
		local height = 166
		if not hasSettings then
			height = height - 50
		end
		
		UiPush()
		UiTranslate(UiCenter(), UiMiddle() + 300)
		UiAlign("center top")
		uiDrawPanel(width, height, 16)
		UiTranslate(0, 14)
		UiColor(COLOR_WHITE)
		UiFont(FONT_BOLD, FONT_SIZE_30)
		UiText("Host Menu")
		UiTranslate(0, 26 + 10)
		
		if hasSettings then
			if uiDrawSecondaryButton("Game Mode Settings", 290) then
				_hud.settings.visible = not _hud.settings.visible
				
				if _hud.settings.visible then
					SetValueInTable(_hud.settings, "animation", 1, "easeout", 0.4)
				else
					SetValueInTable(_hud.settings, "animation", 0, "easeout", 0.4)
				end
			end

			UiTranslate(0, 40 + 10)
		end

		if uiDrawPrimaryButton("Start", 290) then
			ServerCall("server.hudPlayPressed")
			playPressed = true
		end
		
		
		UiPop()
		
		UiPush()
		if hasSettings and _hud.settings.animation > 0 then
			UiTranslate(-650*(1.0-_hud.settings.animation), 0)
			_drawSettings(settings)
		end
		
		UiPop()
	end

	return playPressed
end

--- Draw the current player list (client).
--
-- Shows a panel listing all players in the session, highlighting the local
-- player.
function hudDrawPlayerList()

	UiPush()

	local _, maxPlayers = NetSessionGetPlayersCountRange()
	local players = GetAllPlayers()

	local headerHeight = 36
	local headerRoundingRadius = 4

	local rowHeight = 32
	local rowGap = 2

	local contentOutlineThickness = 4

	local contentGap = 4
	local contentWidth = 276
	local contentHeight = headerHeight + contentGap + maxPlayers * rowHeight + (maxPlayers - 1) * rowGap

	local boardPadding = 20
	local boardWidth = contentWidth + contentOutlineThickness * 4 + boardPadding * 2
	local boardHeight = contentHeight + contentOutlineThickness * 4 + boardPadding * 2

	local boardWidth2 = boardWidth/2
	local boardHeight2 = boardHeight/2

	UiTranslate(UiCenter()-boardWidth2, UiMiddle()-boardHeight2)

	uiDrawPanel(boardWidth, boardHeight, 16)

	UiTranslate(boardPadding, boardPadding)

	UiColor(0.52, 0.52, 0.52)
	UiRoundedRectOutline(boardWidth-boardPadding*2, boardHeight-boardPadding*2, 12, 4)
	UiTranslate(contentOutlineThickness*2, contentOutlineThickness*2)

	UiRoundedRect(contentWidth, headerHeight, headerRoundingRadius)

	UiPush()
	UiTranslate(contentWidth/2, headerHeight/2)
	UiAlign("center middle")
	UiColor(COLOR_WHITE)
	UiFont(FONT_BOLD, FONT_SIZE_30)
	UiText("Players")
	UiPop()

	UiTranslate(0, headerHeight + contentGap)

	UiAlign("left top")
	for i = 1, maxPlayers do

		local player = nil
		if i <= #players then
			player = players[i]
		end

		if player ~= nil and IsPlayerLocal(player) then
			UiColor(1,1,1,0.2)
		else
			UiColor(1,1,1,0.1)
		end

		UiRoundedRect(contentWidth, rowHeight, 4)

		if player then
			uiDrawPlayerRow(player, rowHeight, contentWidth)
		end

		UiTranslate(0, rowHeight+rowGap)
	end

	UiPop()
end

--- Draw a game mode help text box (client).
--
-- Useful for explaining rules or objectives of the current game mode.
--
-- @param[type=string] header Header text shown at the top of the box. Ignored if nil or "".
-- @param[type=string] text Main body text to display.
-- @param[opt,type=table] headerColor Color `{r, g, b, a}` for the header (defaults to yellow).
function hudDrawGameModeHelpText(header, text, headerColor)
	local hasHeader = header ~= nil and header ~= ""
	
	UiPush()
		local padding = 20
		local width = 300
		local textOffset = 0
		local textMaxWidth = width - 2 * padding

		UiWordWrap(textMaxWidth)

		if hasHeader then
			UiFont("bold.ttf", 26 * 1.23)
			local w, h = UiGetTextSize(header)
			textOffset = h
		end
		
		UiFont("regular.ttf", 25 * 1.23)
		local w, h = UiGetTextSize(text)
		local height = h + padding * 2 + textOffset + (hasHeader and padding or 0)
		
		UiTranslate(UiWidth() - (width + 40), UiMiddle() - height * 0.5)
		uiDrawPanel(width, height, 8)
		
		UiTranslate(padding, padding)
		UiAlign("top left")

		if hasHeader then
			UiFont("bold.ttf", 26 * 1.23)
			local w, h = UiGetTextSize(header)
			textOffset = h + 20

			if headerColor then
				UiColor(headerColor[1], headerColor[2], headerColor[3])
			else
				UiColor(COLOR_YELLOW)
			end

			UiText(header)
			UiTranslate(0, textOffset)
		end

		UiFont("regular.ttf", 25 * 1.23)
		UiColor(COLOR_WHITE)
		UiText(text)
	UiPop()
end

--- Draw the animated end-of-match banner and camera motion (client).
--
-- Moves the camera, plays intro/outro sounds, and animates a centered banner
-- with the given text.
--
-- @param[type=number] time Elapsed animation time in seconds.
-- @param[type=string] text Banner text.
-- @param[opt,type=table]  backgroundColor Table representing background color (`{r, g, b, a}`). Defaults to `COLOR_BLACK_TRNSP`.
--
-- @return[type=bool] finished `true` when the animation has fully finished.
function hudDrawResultsAnimation(time, text, backgroundColor)
	backgroundColor = backgroundColor or COLOR_BLACK_TRNSP
	
	if not _resultsAnimCamPos then
		_resultsAnimCamPos = GetPlayerCameraTransform().pos
		_resultsAnimCamRot = GetPlayerCameraTransform().rot
	end

	_resultsAnimTime = _resultsAnimTime and (_resultsAnimTime + GetTimeStep()) or 0.0

	if _resultsAnimTime == 0 then
		UiSound("ui/win-start.ogg")
		endSoundPlayed = false
	end

	if not endSoundPlayed and _resultsAnimTime > 1.8 then -- just before banner fades out
		UiSound("ui/win-end.ogg")
		endSoundPlayed = true
	end
	
    local camPos = VecScale(Vec(math.sin(_resultsAnimTime*0.025), 1.0, math.cos(_resultsAnimTime*0.025)), 50.0)
    local camRot = QuatLookAt(camPos, Vec(0, 0, 0))

	local param = smoothstep(0, 1, clamp(time*0.5, 0, 1))

	local pos = VecLerp(_resultsAnimCamPos, camPos, param)
	local rot = QuatSlerp(_resultsAnimCamRot, camRot, param)

	SetCameraTransform(Transform(pos, rot))
	SetCameraDof(0, 0)

	local LINEAR = 1
	local EASE_IN = 2
	local EASE_OUT = 3

	local bannerStates = {}
	bannerStates[1] 	= { time = 0.166, alpha = 1.0, scaleX = 1.0, scaleY = 1.0 }
	bannerStates[2] 	= { time = 2.833, alpha = 1.0, scaleX = 1.0, scaleY = 1.0 }
	bannerStates[3] 	= { time = 0.166, alpha = 0.0, scaleX = 1.0, scaleY = 0.0 }

	local textStates = {}
	textStates[1] = { time = 0.166+0.05, alpha = 0.0, scale = 2.5, ramp = EASE_IN }
	textStates[2] = { time = 0.300, alpha = 1.0, scale = 0.9, ramp = LINEAR }
	textStates[3] = { time = 0.050, alpha = 1.0, scale = 1.0, ramp = LINEAR }
	textStates[4] = { time = 2.233, alpha = 1.0, scale = 1.0, ramp = LINEAR }
	textStates[5] = { time = 0.050, alpha = 1.0, scale = 1.1, ramp = LINEAR }
	textStates[6] = { time = 0.350, alpha = -0.5, scale = 0.3, ramp = EASE_OUT }

	local maxTime = 0.0
	for i=1,#textStates do
		maxTime = maxTime + textStates[i].time
	end
	
	local textScale = 2.0
	local textAlpha = 0.0
	local bannerAlpha = 0.0
	local bannerScaleX = 1.0
	local bannerScaleY = 0.0

	local animTime = time
	for i=1,#textStates do
		if animTime < textStates[i].time then
			local param = animTime / textStates[i].time

			if textStates[i].ramp == EASE_IN then
				param = param * param
			elseif textStates[i].ramp == EASE_OUT then
				param = param^(0.5)
			end

			if i > 1 then
				textAlpha = textStates[i-1].alpha
				textScale = textStates[i-1].scale
			end

			textAlpha = clamp(textAlpha + param * (textStates[i].alpha - textAlpha), 0.0, 1.0)
			textScale = textScale + param * (textStates[i].scale - textScale)
			break
		else
			animTime = animTime - textStates[i].time
		end
	end

	local animTime = time
	for i=1,#bannerStates do
		if animTime < bannerStates[i].time then
			local param = animTime / bannerStates[i].time

			if i > 1 then
				bannerAlpha = bannerStates[i-1].alpha
				bannerScaleX = bannerStates[i-1].scaleX
				bannerScaleY = bannerStates[i-1].scaleY
			end

			bannerAlpha = bannerAlpha + param * (bannerStates[i].alpha - bannerAlpha)
			bannerScaleX = bannerScaleX + param * (bannerStates[i].scaleX - bannerScaleX)
			bannerScaleY = bannerScaleY + param * (bannerStates[i].scaleY - bannerScaleY)
			break
		else
			animTime = animTime - bannerStates[i].time
		end
	end

	local height = 140
	UiPush()
		UiAlign("center middle")
		UiTranslate(UiCenter(), UiMiddle())
	
		UiPush()
			UiScale(bannerScaleX, bannerScaleY)
			UiColor(COLOR_WHITE)
			UiBackgroundBlur(0.75 * bannerAlpha)
			UiRect(UiWidth(), height)
		UiPop()
		UiPush()
			UiScale(bannerScaleX, bannerScaleY)
			UiColor(backgroundColor[1], backgroundColor[2], backgroundColor[3], bannerAlpha * backgroundColor[4])
			UiRect(UiWidth(), height)
		UiPop()
		UiColor(COLOR_WHITE)
		UiFont("bold.ttf", 80 * 1.23)
		UiColorFilter(1, 1, 1, textAlpha)
		UiTextShadow(0, 0, 0, 0.5, 2.0, 0.75)
		UiScale(textScale)
		UiText(text)
	UiPop()

	return time >= maxTime + 1 -- extra second before results are shown
end

--- Draw a full-screen fade effect based on queued events (client).
--
-- Consumes `hudFade` events and performs fade-in, hold, and fade-out over time,
-- optionally disabling HUD while fully black.
--
-- @param[type=number] dt Delta time in seconds.
function hudDrawFade(dt)

	local count = GetEventCount("hudFade")
	for i=1,count do
		local fadeIn, hold, fadeOut = GetEvent("hudFade", i)
		_hud.fade.active = true
		_hud.fade.t = 0.0
		_hud.fade.fadeIn = fadeIn or 0.5
		_hud.fade.hold = hold or 2.0
		_hud.fade.fadeOut = fadeOut or 0.5
	end

	if _hud.fade.active then

		_hud.fade.t = _hud.fade.t + dt

		_hud.fade.alpha = 0

		if _hud.fade.t < _hud.fade.fadeIn then
			-- Fade in
			local k = _hud.fade.t / _hud.fade.fadeIn
			_hud.fade.alpha = smoothstep(0.0, 1.0, k)

		elseif _hud.fade.t < _hud.fade.fadeIn + _hud.fade.hold then
			-- Hold full black
			_hud.fade.alpha = 1
			SetBool("hud.disable", true)

		elseif _hud.fade.t < _hud.fade.fadeIn + _hud.fade.hold + _hud.fade.fadeOut then
			-- Fade out
			local k = (_hud.fade.t - _hud.fade.fadeIn - _hud.fade.hold) / _hud.fade.fadeOut
			_hud.fade.alpha = 1 - smoothstep(0.0, 1.0, k)
			

		else
			-- Done
			_hud.fade.active = false
		end
	end

	if not _hud.fade.active then
		return
	end

	UiPush()
		UiAlign("center middle")
		UiTranslate(UiCenter(), UiMiddle())
		UiColor(0, 0, 0, _hud.fade.alpha)
		UiRect(UiWidth(), UiHeight())
	UiPop()
end

-- Internal functions


function client._receiveDamage(attacker)
	
	if GetBool("hud.disabled") then return end
	
	local indicator = {}
	indicator.position = GetPlayerTransform(attacker).pos
	indicator.alpha = 1.0
	
	for i=1,#_hud.damageIndicators do
		if VecLength(VecSub(indicator.position, _hud.damageIndicators[i].position)) < 3.0 then
			_hud.damageIndicators[i].alpha = 1.0
			_hud.damageIndicators[i].position = indicator.position
			return
		end
	end
	
	_hud.damageIndicators[1 + #_hud.damageIndicators] = indicator
end

function _drawSettings(settings)
	
	local margin = 30
	
	local width = 481
	local height = UiHeight() - 60
	
	UiPush()
	UiTranslate(margin, margin)
	
	UiPush()
	
	UiPush()
	uiDrawPanel(width, height, 16)
	UiTranslate(width/2,40)
	UiAlign("center middle")
	UiFont("bold.ttf", 36 * 1.23)
	UiColor(COLOR_WHITE)
	UiText("GAME MODE SETTINGS")
	UiTranslate(0, 36)
	UiColor(0.53,0.53,0.53,1)
	UiRect(width-2*margin, 2)
	UiTranslate(0, 10)
	UiPop()
	
	UiTranslate(0, 110)
	for i = 1, #settings do
		if settings[i].title ~= nil and settings[i].title ~= "" then
			UiPush()
			UiTranslate(width/2,6)
			UiAlign("center middle")
			UiFont("bold.ttf", 22 * 1.23)
			UiColor(COLOR_WHITE)
			UiText(settings[i].title)
			UiTranslate(0, 20)
			UiColor(0.53,0.53,0.53,1)
			UiRect(width-2*margin, 2)
			UiPop()

			UiTranslate(0, 60)
		end
		
		for j = 1, #settings[i].items do
			UiPush()
			UiTranslate(margin, 0)
			UiAlign("left middle")
			local item = settings[i].items[j]
			_drawSettingsItemStepper(item.key, item.label, item.info, item.options, width - 2*margin, true)
			UiPop()
			UiTranslate(0, 32 + 10)
		end
	end
	
	UiPop()
	
	
	UiPush()
	
	UiTranslate(width/2, height - 20 - margin)
	UiAlign("center middle")
	
	UiPush()
	UiTranslate(-105 - 10,0)

	if uiDrawSecondaryButton("Reset to defaults", 210) then
		for i = 1, #settings do
			local group = settings[i]
			for j = 1, #group.items do
				local item = group.items[j]
				SetInt(item.key..".index", 1)
				SetString(item.key, item.options[1].value)
			end
		end
	end
	UiPop()

	UiPush()
	UiTranslate(105 + 10,0)
	if uiDrawSecondaryButton("Close", 210) then
		SetValueInTable(_hud.settings, "animation", 0, "easeout", 0.4)
		_hud.settings.visible = false
	end
	UiPop()
	
	UiPop()
end

function _drawSettingsItemStepper(key, title, info, options, width, cyclic)
	
	local navId = UiNavGroupBegin()
	UiNavGroupSize(width, 32)
	
	UiColorFilter(1.0, 1.0, 1.0, 1)
	
	local isFocused = UiReceivesInput() and (UiIsMouseInRect(width, 32.0) or UiIsComponentInFocus(navId))
	
	if isFocused then
		UiPush()
		if info ~= nil and info ~= "" then
			-- local x, y = UiGetCursorPos()
			UiPush()
			UiTranslate(width + 50, -16)
			_drawToolTip(title, info)
			UiPop()
		end
		
		UiColor(1,1,1,0.2)
		UiRoundedRect(width, 32, 4)
		UiPop()
	end
	
	UiPush()
	UiColor(COLOR_WHITE)
	UiFont("regular.ttf", 23*1.23)
	UiText(title)
	UiPop()
	
	UiPush()
	UiTranslate(width - 242, 0)
	
	if isFocused then
		UiColor(COLOR_YELLOW)
	else
		UiColor(COLOR_WHITE)
	end
	_drawStepper(key, options, 242, cyclic, isFocused)
	UiPop()
	
	UiNavGroupEnd()
end

function _drawStepper(key, options, width, cyclic, focused)
	
	local currentIdx = GetInt(key..".index")
	if currentIdx == 0 then
		currentIdx = 1
		SetInt(key..".index", currentIdx)
	end
	if currentIdx > #options then
		currentIdx = #options
		SetInt(key..".index", currentIdx)
	end
	SetString(key, options[currentIdx].value)
	
	local isCyclic = cyclic
	
	UiPush()
	local navId = UiNavComponent(width, 24.0)
	local leftArrow = "ui/common/stepper_l_btn_white.png"
	local rightArrow = "ui/common/stepper_r_btn_white.png"
	local arrowWidth, arrowHeight = UiGetImageSize(leftArrow)
	local isInFocus = UiIsMouseInRect(width, 24.0) or UiIsComponentInFocus(navId)
	
	UiIgnoreNavigation()
	
	local canMoveLeft = not (currentIdx <= 1 and not isCyclic)
	
	UiPush()
	
	if focused or isInFocus then
		UiColor(COLOR_YELLOW)
	else
		UiColor(0.53, 0.53, 0.53, 1)
	end
	if canMoveLeft then
		if UiImageButton(leftArrow) then
			UiSound("ui/common/click.ogg")
			currentIdx = currentIdx - 1
			if currentIdx < 1 then
				currentIdx = #options
			end
			
			SetInt(key..".index", currentIdx)
			SetString(key, options[currentIdx].value)
		end
	end
	
	UiPop()
	
	if canMoveLeft and isInFocus and InputPressed("menu_left") and not (not isCyclic and currentIdx <= 1) then
		UiSound("ui/common/click.ogg")
		UiNavSkipUpdate()
		currentIdx = currentIdx - 1
		if currentIdx < 1 then
			currentIdx = #options
		end
		
		SetInt(key..".index", currentIdx)
		SetString(key, options[currentIdx].value)
	end
	
	
	UiPush()
	UiAlign("middle center")
	UiTranslate(width/2, 0)
	
	if focused or isInFocus then
		UiColor(COLOR_YELLOW)
	else
		UiColor(COLOR_WHITE)
	end
	
	UiFont("regular.ttf", 23*1.23)
	UiText(options[currentIdx].label)
	UiPop()
	
	UiTranslate(width - arrowWidth, 0.0)
	
	local canMoveRight = not(currentIdx >= #options and not isCyclic)
	
	UiPush()
	
	if focused or isInFocus then
		UiColor(COLOR_YELLOW)
	else
		UiColor(0.53, 0.53, 0.53, 1)
	end
	
	if canMoveRight then
		if UiImageButton(rightArrow) then
			UiSound("ui/common/click.ogg")
			currentIdx = currentIdx + 1
			if currentIdx > #options then
				currentIdx = 1
			end
			
			SetInt(key..".index", currentIdx)
			SetString(key, options[currentIdx].value)
		end
	end
	
	UiPop()
	if canMoveRight and isInFocus and InputPressed("menu_right") and not (not isCyclic and currentIdx >= #options) then
		UiSound("ui/common/click.ogg")
		UiNavSkipUpdate()
		currentIdx = currentIdx + 1
		if currentIdx > #options then
			currentIdx = 1
		end
		SetInt(key..".index", currentIdx)
		SetString(key, options[currentIdx].value)
	end
	
	UiPop()
end

function _drawToolTip(title, info)
	
	local width = 264
	local height = 0
	
	UiAlign("left top")
	
	UiFont("regular.ttf", 22*1.23)
	local titleW, titleH = UiGetTextSize(title)
	height = height + titleH + 10
	
	UiWordWrap(244)
	UiFont("regular.ttf", 20*1.23)
	local infoW, infoH = UiGetTextSize(info)
	height = height + infoH + 10
	
	height = height
	
	UiColor(COLOR_BLACK_TRNSP)
	UiRoundedRect(width, height + 20, 8)
	
	UiTranslate(10, 10)
	UiColor(COLOR_WHITE)
	UiFont("regular.ttf", 22*1.23)
	UiText(title)
	UiTranslate(0, titleH + 10)
	UiFont("regular.ttf", 20*1.23)
	UiText(info)
end

function server.hudPlayPressed()
	shared._hud.gameIsSetup = true
end


--- Draw banners (client).
--
-- Draws banners that have been enqueued via `hudShowBanner`. Should be called
-- continuously to animate and consume the banner queue.
--
-- @param[type=number] dt Delta time in seconds used to advance the current banner animation.
function hudDrawBanner(dt)
	local banner = _hud.bannerQueue[1]
	if banner == nil then
		return
	end

	if banner.time < 0 then
		return
	end

	if banner.time == 0.0 then
		UiSound("small-banner.ogg")
		banner.time = 0.001
	end

	banner.time = banner.time + dt

	local LINEAR = 1
	local EASE_IN = 2
	local EASE_OUT = 3

	local bannerStates = {}
	bannerStates[1] 	= { time = 0.166, alpha = 1.0, scaleX = 1.0, scaleY = 1.0 }
	bannerStates[2] 	= { time = 2.733, alpha = 1.0, scaleX = 1.0, scaleY = 1.0 }
	bannerStates[3] 	= { time = 0.166, alpha = 0.0, scaleX = 2.5, scaleY = 0.0 }

	local textStates = {}
	textStates[1] = { time = 0.01, alpha = 0.0, scale = 0.01, ramp = EASE_IN }
	textStates[2] = { time = 0.300, alpha = 1.0, scale = 1.05, ramp = LINEAR }
	textStates[3] = { time = 0.150, alpha = 1.0, scale = 1.0, ramp = LINEAR }
	textStates[4] = { time = 2.133, alpha = 1.0, scale = 1.0, ramp = LINEAR }
	textStates[5] = { time = 0.150, alpha = 1.0, scale = 1.05, ramp = LINEAR }
	textStates[6] = { time = 0.350, alpha = -0.5, scale = 0.3, ramp = EASE_OUT }

	local maxBannerTime = 0.0
	local maxTextTime = 0.0
	for i=1,#bannerStates do
		maxBannerTime = maxBannerTime + bannerStates[i].time
	end
	for i=1,#textStates do
		maxTextTime = maxTextTime + textStates[i].time
	end

	local maxTime = math.max(maxBannerTime, maxTextTime)
	
	local textScale = 2.0
	local textAlpha = 0.0
	local bannerAlpha = 0.0
	local bannerScaleX = 2.5
	local bannerScaleY = 0.0

	local animTime = banner.time
	for i=1,#textStates do
		if animTime < textStates[i].time then
			local param = animTime / textStates[i].time

			if textStates[i].ramp == EASE_IN then
				param = param * param
			elseif textStates[i].ramp == EASE_OUT then
				param = param^(0.5)
			end

			if i > 1 then
				textAlpha = textStates[i-1].alpha
				textScale = textStates[i-1].scale
			end

			textAlpha = clamp(textAlpha + param * (textStates[i].alpha - textAlpha), 0.0, 1.0)
			textScale = textScale + param * (textStates[i].scale - textScale)
			break
		else
			animTime = animTime - textStates[i].time
		end
	end

	local animTime = banner.time
	for i=1,#bannerStates do
		if animTime < bannerStates[i].time then
			local param = animTime / bannerStates[i].time

			if i > 1 then
				bannerAlpha = bannerStates[i-1].alpha
				bannerScaleX = bannerStates[i-1].scaleX
				bannerScaleY = bannerStates[i-1].scaleY
			end

			bannerAlpha = bannerAlpha + param * (bannerStates[i].alpha - bannerAlpha)
			bannerScaleX = bannerScaleX + param * (bannerStates[i].scaleX - bannerScaleX)
			bannerScaleY = bannerScaleY + param * (bannerStates[i].scaleY - bannerScaleY)
			break
		else
			animTime = animTime - bannerStates[i].time
		end
	end

	local height = 140

	UiFont("bold.ttf", FONT_SIZE_25)
	local text = banner.text
	local w, h = UiGetTextSize(text)

	local bannerWidth = w + 20
	local bannerHeight = h + 20

	UiPush()
		UiAlign("center middle")
		UiTranslate(UiCenter(), 250)
	
		UiPush()
			UiScale(bannerScaleX, bannerScaleY)
			UiColor(banner.color[1], banner.color[2], banner.color[3], bannerAlpha^2)
			UiRoundedRect(bannerWidth, bannerHeight, 8)
		UiPop()
		UiColor(COLOR_WHITE)
		UiColorFilter(1, 1, 1, textAlpha)
		UiTextShadow(0, 0, 0, 0.25, 1.0, 0.75)
		UiScale(textScale)
		UiText(text)
	UiPop()

	if banner.time > maxTime then
		table.remove(_hud.bannerQueue, 1)
	end
end


function _isTextValid(text)
	return text ~= nil and text ~= ""
end

function server._unstuck(player) 
	SetPlayerHealth(0, player)
end

function _drawBoard(title, columns, groups, centered, compact, numbered)

	local layout = {
		boardPadding = {10,20,20,20}, -- Top Right Bottom Left
		boardGap = 10,
		boardTitleFontSize = FONT_SIZE_30,
		boardTitleHeight = 36,
		boardRoundingRadius = 8,
		
		-- content
		groupsPadding = {0,0},
		groupsRoundingRadius = 12,
		groupsOutlineThickness = 4,
		
		headerRowHeight = 32,
		headerRowPadding = {10,0},
		headerRowFontSize = FONT_SIZE_22,
		headerRowRoundingRadius = 4,
		headerRowGap = 4,

		playerColumnWidth = 220,
		playerRowHeight = 32,
		playerRowRoundingRadius = 4,
		playerRowGap = 2,
		playerRowFontSize = FONT_SIZE_20,

		numberedColumnWidth = 0
	}

	if compact then
		layout.boardPadding = {10,10,10,10}
	elseif not _isTextValid(title) then
		layout.boardPadding[1] = 20
	end

	if numbered then
		layout.numberedColumnWidth = 40
	end
	
	local contentWidth = layout.numberedColumnWidth + layout.playerColumnWidth
	for i = 1, #columns do
		if columns[i].width ~= nil then
			contentWidth = contentWidth + columns[i].width
		end
	end
	contentWidth = contentWidth + 10
	
	local contentHeight = 0
	if _isTextValid(title) then
		contentHeight = contentHeight + layout.boardTitleHeight + layout.boardGap
	end
	for i = 1, #groups do
		contentHeight = contentHeight + _getGroupHeight(groups[i], layout)
		contentHeight = contentHeight + layout.boardGap
		
		if groups[i].outline then
			layout.groupsPadding = {8, 8} -- Make space for outline
			layout.boardRoundingRadius = 16
		end
	end
	contentHeight = contentHeight-layout.boardGap -- Remove final Gap
	
	contentWidth = contentWidth + 2 * layout.groupsPadding[1]
	contentHeight = contentHeight + 2 * layout.groupsPadding[2] * #groups
	
	local boardWidth = contentWidth + layout.boardPadding[2] + layout.boardPadding[4]
	local boardWidth2 = boardWidth * 0.5
	
	local boardHeight = contentHeight + layout.boardPadding[1] + layout.boardPadding[3]
	local boardHeight2 = boardHeight * 0.5
	
	UiPush()
	
	if not centered then
		UiTranslate(boardWidth2, boardHeight2)
	end
	
	-- Background
	UiTranslate(-boardWidth2, -boardHeight2)
	uiDrawPanel(boardWidth, boardHeight, layout.boardRoundingRadius)
	
	UiTranslate(0, layout.boardPadding[1])
	
	-- Title
	if _isTextValid(title) then
		UiPush()
		UiTranslate(boardWidth2, layout.boardTitleHeight*0.5)
		UiAlign("center middle")
		UiFont(FONT_BOLD, layout.boardTitleFontSize)
		UiColor(COLOR_WHITE)
		UiText(title)
		UiPop()
		
		UiTranslate(0, layout.boardTitleHeight + layout.boardGap)
	end
	
	UiTranslate(layout.boardPadding[2], 0)
	
	-- Groups
	for i = 1, #groups do
		_drawGroup(columns, groups[i], layout)
		UiTranslate(0, layout.boardGap)
	end

	UiPop()

	return boardWidth, boardHeight
end

function _getGroupHeight(group, layout)
	return layout.headerRowHeight + layout.headerRowGap + #group.rows * layout.playerRowHeight + ((#group.rows - 1) * layout.playerRowGap)
end

function _drawGroup(columns, group, layout)
	
	local width = layout.numberedColumnWidth + layout.playerColumnWidth

	for i = 1, #columns do
		width = width + columns[i].width
	end
	width = width + layout.groupsPadding[1] * 2 + 10
	
	local height = layout.headerRowHeight + layout.headerRowGap
	height = height + #group.rows * layout.playerRowHeight + (#group.rows - 1) * layout.playerRowGap
	height = height + layout.groupsPadding[2] * 2
	if group.outline then
		UiPush()
		UiColor(group.color[1], group.color[2], group.color[3])
		UiRoundedRectOutline(width, height, layout.groupsRoundingRadius, layout.groupsOutlineThickness)
		UiPop()
	end
	
	UiTranslate(0, layout.groupsPadding[2])
	
	UiPush()
	UiTranslate(layout.groupsPadding[1], 0)
	_drawGroupHeader(columns, group, layout)
	UiPop()
	UiTranslate(0, layout.headerRowHeight + layout.headerRowGap)
	
	UiPush()
	UiTranslate(layout.groupsPadding[1], 0)
	_drawGroupRows(columns, group, layout)
	UiPop()
	UiTranslate(0, #group.rows * layout.playerRowHeight + (#group.rows - 1) * layout.playerRowGap)
	
	UiTranslate(0, layout.groupsPadding[2])
end

function _drawGroupHeader(columns, group, layout)
	local header = {}

	if layout.numberedColumnWidth > 0 then
		header[#header+1] = {name="#", width=layout.numberedColumnWidth, align="center"}
		header[#header+1] = {name=group.name, width=layout.playerColumnWidth, align="left"}
	else
		header[#header+1] = {name=group.name, width=layout.playerColumnWidth, align="left"}
		if #columns == 0 then
			header[1].align = "center"
			header[1].margin = 0
		end
	end

	local width = layout.numberedColumnWidth + layout.playerColumnWidth
	
	for i = 1, #columns do
		header[#header+1] = {name=columns[i].name, width=columns[i].width, align=columns[i].align}
		width = width + columns[i].width
	end
	width = width + 10
	
	UiAlign("left top")
	--UiTranslate(0, layout.headerRowHeight * 0.5)
	UiColor(group.color[1], group.color[2], group.color[3])
	UiRoundedRect(width, layout.headerRowHeight, layout.headerRowRoundingRadius)
	
	UiTranslate(layout.headerRowGap, 0)
	
	UiFont(FONT_BOLD, layout.headerRowFontSize)
	UiColor(COLOR_WHITE)
	for i=1,#header do
		local step = header[i].width

		if header[i].align ~= nil then
			UiAlign(header[i].align.." top")
			if header[i].align == "center" then
				UiTranslate(header[i].width * 0.5, 0)
				step = header[i].width * 0.5
			elseif header[i].align == "right" then
				UiTranslate(header[i].width, 0)
				step = 0
			end
		else
			UiAlign("left top")
		end
		
		UiPush()

		UiAlign(header[i].align.." bottom")

		local w,h,x,y = UiGetTextSize(header[i].name)
		UiTranslate(0, layout.headerRowHeight + y - 8)
		if header[i].margin then
			UiTranslate(header[i].margin, 0)
		end
		UiText(header[i].name)
		UiPop()

		UiTranslate(step, 0)
	end
end

function _drawGroupRows(columns, group, layout)
	
	local width = layout.numberedColumnWidth + layout.playerColumnWidth
	for i = 1, #columns do
		width = width + columns[i].width
	end
	width = width + 10
	
	UiAlign("left top")
	--UiTranslate(0, layout.playerRowHeight * 0.5)
	for i=1,#group.rows do
		
		UiPush()
		
		local row = group.rows[i]
		if IsPlayerLocal(row.player) then
			UiColor(1, 1, 1, 0.2)
		else
			UiColor(1, 1, 1, 0.1)
		end
		UiRoundedRect(width, layout.playerRowHeight, layout.playerRowRoundingRadius)
		
		UiColor(COLOR_WHITE)
		UiFont(FONT_BOLD, layout.playerRowFontSize)

		-- Draw numbers
		if layout.numberedColumnWidth > 0 then
			UiPush()
			UiAlign("center top")
			UiTranslate(layout.numberedColumnWidth/2, 0)
			if IsPlayerLocal(row.player) then
				UiColor(COLOR_YELLOW)
			elseif group.dim then
				UiColor(0.67, 0.67, 0.67)
			else
				UiColor(COLOR_WHITE)
			end

			UiPush()
			UiAlign("center bottom")
			local num = ""..i
			local w,h,x,y = UiGetTextSize(num)
			UiTranslate(0, layout.playerRowHeight + y - 8)
			UiText(num)
			UiPop()
			UiPop()
			UiTranslate(layout.numberedColumnWidth, 0)
		end
		
		if row.player then
			UiPush()
			--UiTranslate(0, -layout.playerRowHeight * 0.5)
			uiDrawPlayerRow(row.player, layout.playerRowHeight, layout.playerColumnWidth, group.color, group.dim)
			UiPop()
		end
		UiTranslate(layout.playerColumnWidth,0)
		
		for c=1,#columns do
			local step = columns[c].width
			
			if columns[c].align ~= nil then
				UiAlign(columns[c].align.." top")
				if columns[c].align == "center" then
					UiTranslate(columns[c].width/2, 0)
					step = columns[c].width/2
				elseif columns[c].align == "top" then
					UiTranslate(columns[c].width, 0)
					step = 0
				end
			else
				UiAlign("left top")
			end
			if IsPlayerLocal(row.player) then
				UiColor(COLOR_YELLOW)
			elseif group.dim then
				UiColor(0.67, 0.67, 0.67)
			else
				UiColor(COLOR_WHITE)
			end
			
			UiPush()
			UiAlign(columns[c].align.." bottom")
			local w,h,x,y = UiGetTextSize(row.columns[c])
			UiTranslate(0, layout.playerRowHeight + y - 8)
			UiText(row.columns[c])
			UiPop()
			UiTranslate(step, 0)
		end
		UiPop()
		
		UiTranslate(0, layout.playerRowHeight + layout.playerRowGap)
	end
	
	UiTranslate(0, -layout.playerRowGap) -- Remove last gap
end