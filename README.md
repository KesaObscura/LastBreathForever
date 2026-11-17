# Last Breath Forever – time to die addon for WoW Forever

An addon for **World of Warcraft: Forever** (WoW Forever, "Classic+", client 1.60.1): see **about
how many seconds your target has left** ("~12 s"), live in combat. Finish the long cast, switch
targets or save the cooldown. Part of the Forever series with
[Full Mana Forever](https://github.com/KesaObscura/FullManaForever).

**Status: test versions.** No release yet.

## What it shows

- **About how many seconds your target has left** ("~12 s"), live in combat: solo, in a group, in
  dungeons and on bosses. It is an estimate from how fast the target has been losing health in
  this fight, so it is always "about", never exact.
- The seconds appear after a few hits. Joined a fight late, or switched to a target that is
  already hurt? They show for it too, a little later: once it has lost some more health.
  No number is better than a wrong one.
- In the open world a target you come back to in the same fight keeps its seconds.
- **Also for the focus** (optional): a second frame with the seconds of your focus, with the
  target frame's settings or its own. **Healers**: put the boss in your focus, and its seconds
  stay on screen while an ally is your target.
- The language of the addon follows your game, or choose one in the settings.
- The seconds wait until the target has lost a few percent: the very first seconds of a fight
  say too little.
- **Show from**: only once about 30 s to 10 min or less are left, or always.
- **Last seconds in red**: from 3 s up to a minute before the end, for cooldowns and trinkets you
  keep for the finish. **Only elites and bosses**, size, icon, position.
- 9 languages: English, Deutsch, Español (EU and AL), Français, Русский, 한국어, Português,
  简体中文, 繁體中文. The addon follows your game language.

## Commands

| Command | What it does |
|---|---|
| `/lbf` | Opens the settings (also: the addon menu at the minimap) |
| `/lbf unlock` | Lets you drag the seconds where you want them |
| `/lbf lock` | Locks them in place (a fight locks them too) |
| `/lbf reset` | Puts them back in the middle of the screen |
| `/lbf check` | Shows what the game answered in the last fights (for bug reports) |
| `/lbf help` | Lists the commands |

## Install

Unzip into `World of Warcraft/_forever_/Interface/AddOns/` (folder `LastBreathForever`).

License: MIT.
