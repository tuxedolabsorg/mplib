# Example - Plank Climbers

This game mode (mod) serves as a basic example of how to incorporate `mplib` into a mod. 

To help understand this example it can be useful to read this document together with the documentation and the code in `plankclimbers.lua`.

## Description of Plank Climbers
Plank Climbers is a game mode where your objective is to get as high up as possible. The player that has reached the farthest up during the 2 minutes wins. Players can see the progress of other players by holding `shift` which reveals the scoreboard. The game mode starts with a 5 second countdown to let players know it's about to start. Once the time is up players will be presented with the results screen.

This game mode uses `world markers` to display in-world text labels, one for each player. We decide to let the label display the corresponding players' name and his/hers best achieved score. This will allow players to easily locate other players, and to see their progress.

For this game mode we're going to assign each player a very basic set of tools (loadout). Let's equip every player with the `sledge`, `spray can`, `extinguisher` and of course, lots of `planks`, it's Plank Climbers after all..

We will also post a banner notification to notify players whenever there is a new player in the lead.

## mplib
Plank Climbers only needs to utilize parts of `mplib`.

`mplib` modules used in this game mode:
 - **util**

    We want our players to spawn (and respawn) at a random point in the world. We can achieve this by calling `utilGenerateSpawnPoints(20)` which generates 20 random spawn transforms for us. We will pass these to `spawnSetSpawnTransforms` to make the `spawn` module use these points. We could also use these 20 random transforms for other purposes.

 - **spawn**

    - We first initialize the `spawn` module by calling `spawnInit()` when we initialize our game mode (in `server.init()`).

    - We can set the loadout described above by calling `spawnSetDefaultLoadout`. This will make sure that every spawned player is assigned that loudout.

    - The transforms passed to `spawnSetSpawnTransforms` will be used when spawning players, picking one random each time.

    - To let the `spawn` module handle respawning for us, we call `spawnTick(dt)` from `server.tick(dt)`. This will moniter when players need to respawn, pick one of the spawn transforms at random as well as equipping the player with our chosen loadout, before respawning that player.
    
 - **countdown**

    - We initialize the countdown with a time of 5 seconds by calling `countdownInit(5.0)`. 
    
    - In `server.tick(dt)` we need to call `countdownTick(dt)` to let the timer count down. This function return `true` for as long as the countdown is still ongoing. This allows us to return early and not process any game mode logic until the countdown is complete. 
    
    - The client part of our script can do a similar check by calling `countdownDone()`. This example does that to *not* draw the timer, banners, worldmakers or scoreboard during countdown.
    
- **hud**

  - Most of the functionality in `hud` draws various UI elements and should be called from `client.draw(dt)`, but there are exceptions. In this example there is one such exception, namely `hudShowBanner`, which is called from `client.tick(dt)` to enqueue a banner notification, which is later drawn in `client.draw(dt)`.

  - Using `hudDrawTitle` we can draw the title of the game mode. By default it will be shown for 5 seconds.

  - `hudDrawGameModeHelpText` allows us to show a short descriptive text of the game mode. In this example, we choose to display it for the first 10 seconds of match or if `shift` is held.

  - The server part of our script will decrement our match time (2 minutes). We synchronize this to clients using the `shared` table. Clients can draw the timer by calling `hudDrawTimer(shared.time)`.

  - To draw the banner notifications that has been enqueued we call `hudDrawBanner(dt)`.

  - Depending on if the match is over or not, we either display a scoreboard using `hudDrawScoreboard` (if `shift` is held.) or the final results table by calling `hudDrawResults`.