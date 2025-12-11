# Changelog
All notable changes to this project will be documented in this file.

## [0.1.0] - 2025-12-11
### Added
- Initial public release of `mplib`, the multiplayer support library used in Teardown.
- Added all core Lua modules:
  - `countdown.lua` – pre-round countdown and match start logic.
  - `eventlog.lua` – in-game event feed for kills, pickups, and notifications.
  - `stats.lua` – player statistics and scoreboard data.
  - `teams.lua` – team assignment and helpers.
  - `tools.lua` – tool spawning, loot tables, respawn timers, and drop-on-death logic.
  - `util.lua` – spawn point loading and generation helpers.
  - `spectate.lua` – spectator mode logic when the player is dead.
  - `hud.lua` – shared HUD components (timer, world markers, scoreboard, results, setup UI).
  - `spawn.lua` – player spawn and respawn management system (server-side only).
  - `ui.lua` – shared UI helpers for text, panels, and button rendering.
- Added example game mode in `examples/plankclimbers/` demonstrating how to use `mplib`.
- Added generated API documentation (via LuaDoc) in `/docs`, published through GitHub Pages.
- Added `mplib/version.lua` containing the library version identifier.
- Added `README.md` with usage instructions, features, and getting started guide.
- Added `CONTRIBUTING.md` describing contribution policy.
- Added MIT license.

