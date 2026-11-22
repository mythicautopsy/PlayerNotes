# PlayerNotes

Shared WoW Forever rules: ../CLAUDE.md (if present locally).

Rate players (positive / neutral / negative + note up to 150 chars), get warned
when they group with you again, and rate your group after a dungeon.

## Files
- `PlayerNotes.toc`, `PlayerNotes.lua` (~1,000 lines, one file, sections marked
  with `-----` banners: ratings, DB, tooltips, menus, minimap button, notes
  list, feedback window, slash, events).

## SavedVariables `PlayerNotesDB` (account-wide)
- `players[Name-Realm]` — rating, note, level/race/class/guild, group count,
  last seen (time/place), dungeon history (keep last 15 runs).
- `settings` — `autoFeedback`, `raidWarning`, `trackAll` (all default true),
  plus minimap settings.
- Player keys are always `Name-Realm`; never build a key from a secret value.

## Behaviour to keep
- "Dungeon finished" = leave the instance alive, or the group breaks up while
  inside, AND (a boss died OR 10+ minutes inside). Release-spirit doesn't count.
- Details unreadable in combat are skipped and filled in on PLAYER_REGEN_ENABLED.
- Negative-rated players trigger a warning sound.
- Entry points: right-click menu "Add player note", `/pn`, minimap button,
  addon compartment (`PlayerNotes_OnCompartmentClick`).

## Slash: `/pn`, `/playernotes` — add, feedback, list, print, delete, track,
auto, warn, minimap, help.
No CHANGELOG.md yet.
