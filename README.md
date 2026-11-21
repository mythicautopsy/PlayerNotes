# PlayerNotes

**Rate the players you group with and get reminded when you meet them again.** Made for WoW Forever.

Had a great tank? A healer who rage-quit after one wipe? Give them a green tick, a yellow question mark or a red X, add a short note, and PlayerNotes will tell you the next time they join your group.

A simpler take on "I Will Remember You": no setup, no options maze.

## Features

- **Rate anyone in three clicks.** Right-click a player (party frame, target, or their name in chat) and choose **Add player note**. Pick positive, neutral or negative and type a short note (up to 150 characters).
- **Reminders when you group again.** When a player you've rated joins your group, you get a chat message and a big on-screen warning with your rating and note. Negative ratings also play a warning sound.
- **Rate your group after a dungeon.** When you finish a dungeon, a "Rate your group" window lists everyone from the run, including people who left partway. Pick an icon and add a note for whoever you like, then save.
- **Player database.** Records level, race, class, guild, how many times you've grouped together, and when and where you last saw each player.
- **Dungeon history.** Remembers which dungeons you've run with each player, with the date and bosses killed (last 15 runs per player).
- **Searchable notes list.** Search by name, guild, class, dungeon or note text, and filter by rating. Click any row to edit.
- **Tooltips.** Hovering over a player shows your rating, note, how often you've grouped and your last dungeon together.
- **Minimap button.** Left-click opens your notes, right-click rates your current group, drag to move it.
- Notes are shared by all characters on your account.

### When does a dungeon count as finished?

WoW Forever has no end-of-dungeon screen, so PlayerNotes treats a run as finished when you **leave the dungeon alive** or **the group breaks up while you're inside**, as long as at least one boss died or you were inside for 10+ minutes. Dying and releasing your spirit doesn't count.

You can always open the window yourself with `/pn feedback`.

## Commands

| Command | What it does |
| --- | --- |
| `/pn` | Note for your target, or open your notes list if you have no player targeted |
| `/pn add Name-Realm` | Add or edit a note for a player |
| `/pn feedback` | Rate your current group (or your last dungeon group) |
| `/pn list` | Open your notes list |
| `/pn print` | Print all notes to chat |
| `/pn delete Name-Realm` | Remove a player |
| `/pn track` | Turn recording everyone you group with on or off (default on). Off means only players you rate are saved |
| `/pn auto` | Turn the automatic after-dungeon window on or off |
| `/pn warn` | Turn the big on-screen reminder on or off |
| `/pn minimap` | Show or hide the minimap button |
| `/pn help` | List commands |

`/playernotes` works anywhere `/pn` does.

## Install

1. Fully quit WoW. A `/reload` isn't enough for a newly installed addon.
2. Unzip into `World of Warcraft\_forever_\Interface\AddOns\`. You should end up with `AddOns\PlayerNotes\PlayerNotes.toc` (not a `PlayerNotes` folder inside another `PlayerNotes` folder).
3. Start WoW Forever and make sure PlayerNotes is ticked on the AddOns screen.

Or install it with the CurseForge app.

## Known issues

- Built for WoW Forever's client (interface 16001). Please report anything that doesn't work on the GitHub page.
- Runs done before you installed PlayerNotes aren't in the dungeon history.
- A player's level, class and guild are filled in when you group with them or hover over them. Guild names occasionally take a moment to load and may show blank at first.
- Leaving a dungeon partway through (for repairs, say) after a boss kill opens the rating window. Click **Skip** and it will come back when you finish.
- Because of Blizzard's addon restrictions, some details may not be readable during combat inside instances. PlayerNotes skips them and fills them in later.

## Author

mythicautopsy – The Monsoon Brigade @ Alliance PVE

Source and issues: https://github.com/mythicautopsy/PlayerNotes

Licensed under the MIT License.
