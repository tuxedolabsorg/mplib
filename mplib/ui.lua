--- UI Helper & Utility Functions
--
-- Standardized helpers used across mplib scripts for rendering
-- text, panels, buttons, and player-related visuals. These functions 
-- unify visual style and behavior for common UI components.


FONT_BOLD = "bold.ttf"
FONT_MEDIUM = "medium.ttf"
FONT_ROBOTO = "RobotoMono-Regular.ttf"

FONT_SCALE = 1.23

-- NORMAL
FONT_SIZE_80 = 80 * FONT_SCALE
FONT_SIZE_50 = 50 * FONT_SCALE
FONT_SIZE_40 = 40 * FONT_SCALE
FONT_SIZE_30 = 30 * FONT_SCALE
FONT_SIZE_25 = 25 * FONT_SCALE
FONT_SIZE_22 = 22 * FONT_SCALE
FONT_SIZE_20 = 20 * FONT_SCALE
FONT_SIZE_18 = 18 * FONT_SCALE

-- SPECIAL 
FONT_SIZE_36 = 36 * FONT_SCALE
FONT_SIZE_32 = 32 * FONT_SCALE

COLOR_BLACK			= {0,0,0,1}
COLOR_BLACK_TRNSP 	= {0, 0, 0, 0.75}
COLOR_WHITE			= {1,1,1,1}
COLOR_YELLOW		= {1,1,0.5,1}
COLOR_RED			= {0.9, 0.3, 0.3, 1}

COLOR_TEAM_1 		= {0.2, 0.55, 0.8, 1}
COLOR_TEAM_2 		= {0.8, 0.25, 0.2, 1}
COLOR_TEAM_3 		= {0.25, 0.25, 0.75, 1}
COLOR_TEAM_4 		= {0.25, 0.75, 0.75, 1}

--- Measure how much of a text string fits within given constraints (client).
--
-- Performs width or multi-line height fitting based on `maxLines`. If the 
-- text does not fit, the function finds the longest substring that fits 
-- using a binary search, and appends an ellipsis.
--
-- @param[type=string] text   Text to measure
-- @param[type=string] font   Font asset path
-- @param[type=number] fontSize  Font size
-- @param[type=number] maxWidth  Maximum allowed width
-- @param[opt,type=number] maxLines Maximum number of lines; if omitted, single-line
--
-- @return[type=boolean] fits `true` if the entire text fits
-- @return[type=string] displayedText  Either the original text or truncated version
function uiTextConstrained(text, font, fontSize, maxWidth, maxLines)
	UiPush()
	UiFont(font, fontSize)
	if maxLines and maxLines > 1 then
		UiWordWrap(maxWidth)
	end

	local function Fits(str)
		local sizeX, sizeY, posX, posY = UiGetTextSize(str)
		if maxLines and maxLines > 1 then
			local estimatedLineCount = math.max(1, math.floor(sizeY / fontSize + 0.5 ))
			return estimatedLineCount <= maxLines
		else
			return sizeX <= maxWidth
		end
	end

	local fits = Fits(text)
	local displayedText = text

	if not fits then
		-- Binary Search for largest substring that fits
		local symbolCount = UiGetSymbolsCount(text)
		local lo = 1
		local hi = symbolCount
		local lastFits = lo
		while lo <= hi do
			local mid = math.floor((lo + hi) / 2)
			local testText = UiTextSymbolsSub(text, 1, mid).."…"
			if Fits(testText) then
				lo = mid + 1
				lastFits = mid
			else
				hi = mid - 1
			end
		end
		displayedText = UiTextSymbolsSub(text, 1, lastFits).."…"
	end
	UiPop()
	return fits, displayedText
end

--- Draw constrained text with error highlighting for overflow debugging (client).
--
-- Uses `uiTextConstrained` internally. If text overflows, displays the text 
-- in red to help identify problematic UI layouts.
--
-- @param[type=string] text   Text to draw
-- @param[type=string] font   Font asset path
-- @param[type=number] fontSize  Font size
-- @param[type=number] maxWidth  Max width before truncation
-- @param[opt,type=number] maxLines Max lines before truncation
function uiDrawTextConstrained(text, font, fontSize, maxWidth, maxLines)

	local fits, displayedText = uiTextConstrained(text, font, fontSize, maxWidth, maxLines)
	
	UiPush()
	UiFont(font, fontSize)
	if maxLines and maxLines > 1 then
		UiWordWrap(maxWidth)
	end
	if fits then
		UiText(displayedText)
	else
		-- DBG for finding text overflows
		UiColor(1,0,0,1)
		UiText(displayedText)
	end
	UiPop()
end

--- Draw constrained text that always uses ellipsis when truncated (client).
--
-- Similar to `uiDrawTextConstrained`, but does not color overflow text red.
--
-- @param[type=string] text   Text to draw
-- @param[type=string] font   Font asset path
-- @param[type=number] fontSize  Font size
-- @param[type=number] maxWidth  Max width allowed
-- @param[opt,type=number] maxLines Max number of lines
function uiDrawTextEllipsis(text, font, fontSize, maxWidth, maxLines)

	local fits, displayedText = uiTextConstrained(text, font, fontSize, maxWidth, maxLines)
	
	UiPush()
	UiFont(font, fontSize)
	if maxLines and maxLines > 1 then
		UiWordWrap(maxWidth)
	end
	UiText(displayedText)
	UiPop()
end

--- Retrieve the preview image path for a player's character (client).
--
-- Falls back to a default placeholder preview image if none exists.
--
-- @param[type=number] playerId Player ID
--
-- @return[type=string] imagePath   Filepath to preview image
function uiGetPlayerImage(playerId)
    local characterId = GetPlayerCharacter(playerId)
    local imagePath = GetString("characters."..characterId..".preview")
    if imagePath == "" or not UiHasImage(imagePath) then
        imagePath = "level/menu/script/avatarui/resources/preview_default.png"
    end
    return imagePath
end

--- Draw a player's preview image with optional rounded outline (client).
--
-- Renders the player avatar using the character preview image. Optionally 
-- draws an outline using the player's team color or a provided color array.
--
-- @param[type=number] playerId Player ID
-- @param[type=number] width  Image width
-- @param[type=number] height Image height
-- @param[type=number] roundingRadius  Corner radius
-- @param[opt,type=table] outlineColor {r,g,b,a} color array
-- @param[opt,type=number] outlineThickness Outline thickness
function uiDrawPlayerImage(playerId, width, height, roundingRadius, outlineColor, outlineThickness)

	local imagePath = uiGetPlayerImage(playerId)
			
	UiPush()
	UiColor(COLOR_WHITE)
	UiFillImage(imagePath)
	UiRoundedRect(width, height, roundingRadius)
	UiPop()
			
	if outlineColor and outlineThickness then
		UiPush()
		UiColor(unpack(outlineColor))
		UiRoundedRectOutline(width, height, roundingRadius, outlineThickness)
		UiPop()
	end
end

--- Draw a full player row including avatar and player name (client).
--
-- Displays an avatar, player name, and color-coded status. Used in scoreboards 
-- and player lists. Auto-scales height and applies dimming or local-player 
-- highlighting.
--
-- @param[type=number] playerId Player ID
-- @param[opt,type=number] height   Height of the row (default: 32)
-- @param[type=number] maxWidth  Maximum width for name text
-- @param[opt,type=table] color  Override color {r,g,b}
-- @param[opt,type=boolean] dim  Whether to dim the row
function uiDrawPlayerRow(playerId, height, maxWidth, color, dim)

	local r = 0.52
	local g = 0.52
	local b = 0.52

	if color then
		r = color[1]
		g = color[2]
		b = color[3]
	else
		local isUsed, pr, pg, pb = GetPlayerColor(playerId)
		if isUsed then
			r = pr
			g = pg
			b = pb
		end
	end

	local size = 32.0
	local scale = 1.0
	if height then
		scale = height/size
		size = height
	end

	local roundingRadius = 4 * scale
	local outlineThickness = 2 * scale

	UiPush()
	UiAlign("left top")

	uiDrawPlayerImage(playerId, size, size, roundingRadius, {r,g,b}, outlineThickness)

	UiPush()
	UiTranslate(size + 10 * scale, 0)
	
	if IsPlayerLocal(playerId) then
		UiColor(COLOR_YELLOW)
	elseif dim then
		UiColor(0.67, 0.67, 0.67)
	else
		UiColor(COLOR_WHITE)
	end

	UiPush()
	UiAlign("left bottom")
	local fits, displayedText = uiTextConstrained(GetPlayerName(playerId), FONT_BOLD, FONT_SIZE_20 * scale, maxWidth - (size + 10 * scale))
	local w,h,x,y = UiGetTextSize(displayedText)
	UiTranslate(0, size + y - (8 * scale))
	UiFont(FONT_BOLD, FONT_SIZE_20*scale)
	UiText(displayedText)
	UiPop()
	UiPop()

	UiPop()
end

--- Draw a styled primary action button (client).
--
-- @param[type=string] title   Button text
-- @param[type=number] width   Button width in pixels
-- @param[opt,type=boolean] disabled Disable input
--
-- @return[type=boolean] pressed  `true` if clicked
function uiDrawPrimaryButton(title, width, disabled)
	return uiDrawButton(title, width, {0.5608, 0.8745, 0.6588, 0.4}, COLOR_YELLOW, true, disabled)
end


--- Draw a styled secondary action button (client).
--
-- @param[type=string] title   Button label
-- @param[type=number] width   Button width
-- @param[opt,type=boolean] disabled Disable input
--
-- @return[type=boolean] pressed  `true` if clicked
function uiDrawSecondaryButton(title, width, disabled)
	return uiDrawButton(title, width, {0,0,0,0.2}, COLOR_YELLOW, true, disabled)
end

--- Draw a generic button with configurable background, hover colors and outline (client).
--
-- Base implementation for all button types in the mplib UI.
--
-- @param[type=string] title   Text displayed in button
-- @param[type=number] width   Button width
-- @param[type=table] color Background {r,g,b,a}
-- @param[type=table] hoverColor  Hover highlight {r,g,b,a}
-- @param[type=boolean] outline   Whether to draw outline
-- @param[opt,type=boolean] disabled Disable interaction
--
-- @return[type=boolean] pressed  `true` on click
function uiDrawButton(title, width, color, hoverColor, outline, disabled)
	local pressed = false

	local alphaScale = 1
	if disabled then
		alphaScale = 0.2
	end

	UiPush()
		if color then
			UiColor(color[1], color[2], color[3], color[4] * alphaScale)
			UiRoundedRect(width, 40, 6)
		end

		UiButtonHoverColor(unpack(hoverColor))

		if outline then
			UiButtonImageBox("ui/common/box-outline-fill-6.png", 6, 6, 1, 1, 1, 1 * alphaScale)
		end
		
		UiFont(FONT_MEDIUM, FONT_SIZE_22)
		UiColor(1,1,1,1 * alphaScale)

		if disabled then
			UiDisableInput()
		end
		if UiTextButton(title, width, 40) then
			pressed = true
		end

	UiPop()

	return pressed
end

--- Draw a translucent panel with optional rounded corners (client).
--
-- Used for modal dialogs, popups, player lists, and other UI grouping elements.
--
-- @param[type=number] width   Panel width
-- @param[type=number] height  Panel height
-- @param[opt,type=number] radius Corner radius
function uiDrawPanel(width, height, radius)

	local hasRadius = radius and radius > 0

	UiPush()
		UiColor(COLOR_WHITE)
		UiBackgroundBlur(0.75)
		
		if hasRadius then
			UiRoundedRect(width, height, radius)
		else
			UiRect(width, height)
		end
	UiPop()
	
	UiPush()
		UiColor(COLOR_BLACK_TRNSP)
		
		if hasRadius then
			UiRoundedRect(width, height, radius)
		else
			UiRect(width, height)
		end
	UiPop()
end

--- Draw a text panel with background and padding (client).
--
-- Common for notifications or tooltips within mplib UI.
--
-- @param[type=string] message Text to display
-- @param[opt,type=number] alpha  Opacity multiplier
function uiDrawTextPanel(message, alpha)


	local a = 1.0
	if alpha then
		a = alpha
	end

	UiPush()
	UiAlign("left top")

	UiFont(FONT_BOLD, FONT_SIZE_30)
	local w,h,x,y = UiGetTextSize(message)

	local panelWidth = w + 20
	local panelHeight = 42

	UiTranslate(-panelWidth/2,0)

	UiPush()
	UiColor(0,0,0,0.75 * a)
	UiRoundedRect(panelWidth, panelHeight, 8)
	UiPop()

	UiPush()
	
	UiTranslate(10, panelHeight - 10)
	UiColor(1,1,1,a)
	
	UiPush()
	UiAlign("left bottom")
	UiTranslate(0, y)
	UiText(message)
	UiPop()
	UiPop()

	UiPop()	
end


--- Draw a panel containing text and an image icon (client).
--
-- Often used for objective info.
--
-- @param[type=string] message Text to display
-- @param[type=table] imageItem   Table containing:
--  * `path` (string) Image path
--  * `color` (table) {r,g,b}
-- @param[opt,type=number] alpha  Opacity multiplier
function uiDrawTextAndImagePanel(message, imageItem, alpha)
	UiPush()

		UiAlign("left top")

		local a = 1
		if alpha then
			a = alpha
		end

		local gap = 10
		local margin = 10

		UiFont(FONT_BOLD, FONT_SIZE_30)
		local w,h,x,y = UiGetTextSize(message)

		local imgSize = 24

		local panelHeight = 42
		local panelWidth = w + gap + imgSize + 2*margin

		UiTranslate(-panelWidth/2,0)

		UiPush()
		UiColor(0,0,0,0.75 * a)
		UiRoundedRect(panelWidth, panelHeight, 8)
		UiPop()

		UiPush()
		UiTranslate(10, panelHeight - 10)
		
		UiPush()
		UiColor(1,1,1,a)
		UiAlign("left bottom")
		UiTranslate(0, y)
		UiText(message)
		UiPop()

		UiPush()
		UiAlign("left bottom")
		UiTranslate(w + gap, 0)
		UiFillImage(imageItem.path)
		UiColor(imageItem.color[1], imageItem.color[2], imageItem.color[3], a)
		UiRoundedRect(imgSize, imgSize, 2)
		UiPop()

		UiPop()

	UiPop()	
end