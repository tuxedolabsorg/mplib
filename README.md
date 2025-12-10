# mplib — Multiplayer Lua Library for Teardown

`mplib` is a multiplayer support library for Teardown.  
It provides a collection of shared Lua modules that simplify creating multiplayer game modes by handling common systems such as gameplay logic, HUD and UI, tool and loot behavior, player spawning, stats, syncing, and client/server coordination.

## Features

`mplib` is organized into small modules that you can include as needed. Examples:

- **Match flow**
  - `countdown.lua` – pre-round countdown and match start
  - `eventlog.lua` – in-game event feed (kills, pickups, etc.)
  - `stats.lua` – kill/death stats and scoreboard data

- **Players & teams**
  - `teams.lua` – team assignment and helpers
  - `spectate.lua` – handles entering and controlling spectator mode.

- **Tools & loot**
  - `tools.lua` – loot tables, tool spawning, respawn, drops on death

- **HUD & UI**
  - `hud.lua` – common HUD elements:
    - title, timer, damage indicators
    - scoreboard and results screen
    - player list, world markers, respawn timer
    - setup UI for game settings

- **Utilities**
  - `util.lua` – helpers for loading/generating spawn points and other shared functions

You can combine these modules to build full multiplayer game modes while keeping your game mode logic focused on mode-specific rules.

## Getting Started

`mplib` is designed to be used inside a Teardown mod alongside your own game mode script.  
A typical setup consists of:

- a **main game mode script** (e.g., `mygamemode.lua`)
- optional **helper scripts** included from that main script
- the **mplib/ folder**, containing all reusable multiplayer modules

Below is the recommended workflow for getting started.

---

### 1. Add `mplib` to your mod

Copy the entire `mplib/` folder into your mod’s script directory.  
For example:
```
mod/
├─ mygamemode.lua            # your main game mode
├─ myhelperfunctions.lua     # optional helper script
└─ mplib/
````

### 2. Include the modules you need

In your `mygamemode.lua`, include the `mplib` modules relevant to your game mode.  
The exact combination depends on what systems you want to use.

```lua
#include "mplib/countdown.lua"
#include "mplib/eventlog.lua"
#include "mplib/stats.lua"
#include "mplib/teams.lua"
#include "mplib/tools.lua"
#include "mplib/util.lua"
#include "mplib/spectate.lua"
#include "mplib/hud.lua"
```

For a working reference, see:

- The example mod included in [`examples/plankclimbers`](examples/plankclimbers/README.md)
- Teardown’s built-in mod **“Multiplayer Classics”**, which uses most of the modules in `mplib` to implement several game modes

### 3. Follow the Teardown multiplayer client/server model

Teardown's multiplayer scripting uses a clear separation between **server-side** and **client-side** execution:

- `server.*` functions run only on the host  
- `client.*` functions run on each client  
- Shared values (`shared.*`) are synchronized automatically by the engine  

`mplib` follows this model closely. In the API documentation:

- Functions that are **server-only** or **client-only** are explicitly annotated  
- Functions that **can be used in both environments are not annotated**  

Because of this, it is important to:

- Check the annotation before calling a function  
- Ensure server logic never runs on the client and vice versa  
- Keep your game mode logic structured around these two environments  

Adhering to the client/server model is essential for correct multiplayer behavior.

### 4. Consult the API documentation

The full API documentation for `mplib` is available here:

https://tuxedolabsorg.github.io/mplib/

## Contributing

This repository is not currently accepting external pull requests or issues.

For more details, see the [`CONTRIBUTING`](CONTRIBUTING.md) file.

## License

This project is licensed under the MIT License.  
See the [`LICENSE`](LICENSE) file for the full terms.