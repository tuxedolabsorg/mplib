--- Event Log
--
-- Functionality to display a list of game events in the top-right corner.
-- Event log messages are posted on the server and then broadcasted
-- to all players. 
-- 
-- The `items` used to construct a message is designed
-- to allow mods to express a wide variety of events. 
-- By calling eventlogTick(..) player death events will automatically be
-- posted.
-- 
-- The client-side of the script will only need to call eventlogDraw(..).
--     -- Example that uses all of the eventlog functions.
--     function server.tick(dt)
--         eventlogTick(dt)
--    
--         -- mod/game mode stuff
--     
--         if somethingNoteworthy then
--             -- Posted events will be shared with all players.
--             eventlogPostMessage({playerId, "did something cool!"}, 5.0)
--             somethingNoteworthy = false
--         end
--     end
--    
--     function client.draw(dt)
--         -- Draw the events client-side.
--         eventlogDraw(dt)
--     end


#include "script/include/common.lua"

--- Post a message to the event log (server).
--
-- Constructs a message for the eventlog from `items` and broadcasts the message to all players.
--
-- @param[type=table] items A list of "items" to put together in the message (in order). 
-- @param[type=number] time The duration that the message should last (in seconds).
--
-- An item can have:
--     text (string): Text to display on the item
--     textColor (table): color of the text. The table can have 3 numbers: {r, g, b}
--     color (table): Background color of the item. The table can have 3 numbers: {r, g, b}
--     icon (string): Path to icon image
--     iconTint (table): Color tint of the icon
--     playerId (number): Player ID associated with the item. Used to automatically 
--         determine other properties like the background color and icon. 
--         Also highlights the text in yellow when the ID matches the client
--     iconRight (boolean): Moves the icon to be positioned on the right of the text
--
-- An item can also be automatically converted to a table from:
-- * a string. automatically converted to a table in the form: `{text = x}`
-- * a number. automatically converted to a table in the form: `{playerId = x}`
--
function eventlogPostMessage(items, time)
    if time == nil then time = 9.0 end
    local message = { items = {}, time = time }
    for j=1, #items do
        local item = items[j]
        local itemType = type(item)

        if itemType == "number" then
            local playerId = item
            item = {playerId = playerId}
        elseif itemType == "string" then
            local messageStr = items[j]
            item = {text = messageStr}
        end

        if type(item) == "table" then
            local isPlayer = item.playerId ~= nil and item.playerId > 0
            if isPlayer then
                if item.text == nil then
                    item.text = GetPlayerName(item.playerId)
                end
                if item.icon == nil then
                    local characterId = GetPlayerCharacter(item.playerId)
                    local imagePath = GetString("characters."..characterId..".preview")
                    item.icon = imagePath
                end
            end
            
            message.items[#message.items + 1] = item
        end
    end
    ClientCall(0, "client._eventlogPostMessage", message)
end

--- Tick the event log (server).
--
-- Detects `playerdied` events and posts a relevant message.
-- @param[type=number] dt Time step
function eventlogTick(dt)
    local count = GetEventCount("playerdied") --get number of death events this frame
    for i=1,count do
        local victim, attacker, _, _, cause, _, _ = GetEvent("playerdied", i) --get each event
        local messageElements = {}
        if attacker ~= nil and attacker > 0 and attacker ~= victim then
            messageElements[#messageElements+1] = attacker
        end
        messageElements[#messageElements+1] = {text = cause, textColor = {1.0, 0.38, 0.38}}
        messageElements[#messageElements+1] = {playerId = victim, iconRight = true}
        eventlogPostMessage(messageElements)
    end
end

client.playerColors = {}
client.messages = {}

--- Draw event log notifications on screen (client).
-- 
-- The `playerColors` table is used to set the color of an item in a message,
-- that is related to a specific player.
-- @param[type=number] dt Delta time used to decrement messages display time.
-- @param[opt,type=table] playerColors A table that maps playerId to color {r,g,b}.
function eventlogDraw(dt, playerColors)
    local scrollY = 0
    local i = 1
    while i <= #client.messages do
        local s = client.messages[i]
        if s ~= nil then 
            s.time = s.time - dt
            if s.time <= 0 then
                scrollY = scrollY + s.scrollY + 1
                table.remove(client.messages, i)
            else
                s.scrollY = s.scrollY + scrollY
                scrollY = 0
                i = i + 1
            end
        end
    end

    UiPush()
    UiTranslate(UiWidth() - 40, 40)
    for i=1, #client.messages do
        local alpha = 1.0
        local message = client.messages[i]
        local r,g,b = 1,1,1
        if message.time < 0.5 then
            alpha = message.time * 2.0
        end

        UiPush()
        UiColorFilter(1,1,1,alpha)
        UiFont("bold.ttf", 20*1.23)

        local margin = 4
        local gap = 4

        local messageWidth = 0

        -- Layout
        for j=1, #message.items do
            local item = message.items[j]

            local isPlayer = item.playerId ~= nil and item.playerId > 0
            if isPlayer then
                if item.color == nil then
                    if playerColors ~= nil then
                        item.color = playerColors[item.playerId]
                        if item.color == nil then
                            item.color = client.playerColors[item.playerId]
                        else
                            client.playerColors[item.playerId] = item.color
                        end
                    end
                end
                
                if not UiHasImage(item.icon) then
                    item.icon = "level/menu/script/avatarui/resources/preview_default.png"
                end
            end
            
            if item.iconRight == nil then
                item.iconRight = false
            end
            
            local w, h = UiGetTextSize(item.text)
            if item.icon ~= nil then
                item.width = 32 + gap + w + margin
            else
                item.width = margin + w + margin
            end
            message.items[j] = item
            messageWidth = messageWidth + item.width
        end

        messageWidth = messageWidth + (#message.items - 1) * gap

        message.scrollY = math.max(0, message.scrollY - dt * 4)
        UiTranslate(-messageWidth, (32 + 10) * message.scrollY)

        -- Draw
        for j=1, #message.items do
            local item = message.items[j]
            if item ~= nil then
                _drawItem(item, margin, gap)
                UiTranslate(item.width + gap, 0)
            end
        end

        UiPop()
        UiTranslate(0, (32 + 10) * (message.scrollY + 1))
    end
    UiPop()
end

function _drawItem(item, margin, gap)
    UiPush()
    local width = item.width
    local isPlayer = item.playerId ~= nil and item.playerId > 0
    if item.color ~= nil then
        UiColor(item.color[1], item.color[2], item.color[3])
    else
        UiColor(0, 0, 0, 0.75)
    end

    UiRoundedRect(width, 32, 4)

    UiTranslate(0, 16)
    UiAlign("left middle")

    if item.icon ~= nil and not item.iconRight then
        if item.iconTint ~= nil then
            UiColor(item.iconTint[1], item.iconTint[2], item.iconTint[3])
        else
            UiColor(COLOR_WHITE)
        end
        UiTranslate(2, 0)
        _drawItemIcon(item.icon, 28, 28, 4)
        UiTranslate(30 + gap, 0)
    else
        UiTranslate(margin, 0)
    end

    if item.textColor ~= nil then
        UiColor(item.textColor[1], item.textColor[2], item.textColor[3])
    elseif isPlayer and IsPlayerLocal(item.playerId) then
        UiColor(COLOR_YELLOW)
    else
        UiColor(COLOR_WHITE)
    end

    if item.text ~= nil then
        UiAlign("left bottom")
        local w, h, x, y = UiGetTextSize(item.text)
        local fontHeight = (20/1.23)
        local textPosY = (32 - fontHeight) / 2 + y
        UiTranslate(0, textPosY)
        UiText(item.text)
        UiTranslate(w + gap, -textPosY)
        UiAlign("left middle")
    end

    if item.icon ~= nil and item.iconRight then
        if item.iconTint ~= nil then
            UiColor(item.iconTint[1], item.iconTint[2], item.iconTint[3])
        else
            UiColor(COLOR_WHITE)
        end
        UiTranslate(2, 0)
        _drawItemIcon(item.icon, 28, 28, 4)
    end

    UiPop()
end

function _drawItemIcon(imgPath, width, height, roundingRadius)
    UiPush()
    UiFillImage(imgPath)
    UiRoundedRect(width, height, roundingRadius)
    UiPop()
end

--
function client._eventlogPostMessage(message)
    message.scrollY = 0
    client.messages[#client.messages + 1] = message
end