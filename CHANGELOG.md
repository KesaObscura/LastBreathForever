**Last Breath Forever 0.2.1**

Also new:
- `/lbf selftest`: tries every setting for about 40 seconds and lists any error with the setting it came from; your settings come back at the end (also after a /reload in the middle). `/lbf selftest stop` ends it early. Paste those lines in a bug report.

**Last Breath Forever 0.2.0**

- **Time to die on nameplates:** small seconds above every enemy that is being hit, also above your target and your focus: see which mob of a pull goes down first. From the last 30 s by default (1 min or 1:30 in the settings), above the enemy's debuffs, with their own size and rules or the target's; the height above the nameplate can be set.
- **Boss and adds at the same time:** every enemy with a nameplate is counted from its first hit, also while it is not your target. Switch from an add to the boss and back, and its seconds are there at once, also in dungeons. Needs the enemy nameplates switched on (the addon's part is on by default and can be switched off).

Also new:
- Target, focus and nameplate can be the same enemy: it shows the same number everywhere, also when its nameplate goes out of view for a moment.
- Enemies that are neither target nor focus show their seconds only while they are being hit, and nothing once they die.
- In a group, enemies other than bosses wait until they have lost 8 % (10 % if already hurt): the first hits of a pull come all at once.
- Smoother in big pulls with many enemies.
- Settings in three columns: target, focus, nameplates.
- New icon, sharper and clearer at every size, in one style with the other Forever addons.

Fixed:
- An enemy that resets (evades) while you fight on starts its seconds anew instead of keeping the old ones.

**Last Breath Forever 0.1.1**

- The icon now matches the other addons of the Forever series: the same circle, glow and infinity sign.

**Last Breath Forever 0.1.0**

First release: time to die for WoW Forever.

- Shows about how many seconds your current target has left ("~12 s"; longer times as "~2:30" or "~12 min"), live in combat: solo, in a group, in dungeons and on bosses.
- The seconds appear after a few hits. For a target that was already hurt when you joined (a boss at 50 %, the next mob of a pull), they show a little later: once it has lost some more health.
- In the open world a target you come back to in the same fight keeps its seconds.
- A second frame with the seconds of your focus (off by default), with the target frame's settings or its own. Healers: put the boss in your focus, and its seconds stay on screen while an ally is your target.
- The language of the addon follows your game, or choose one in the settings.
- The seconds wait until the target has lost a few percent, in a group or on a boss also about 10 s: the first seconds of a pull say too little. Meanwhile a dim icon shows that the addon is counting.
- Settings (`/lbf`, also in the addon menu at the minimap) in two columns, target and focus: size, "Show from" (only once about 30 s to 10 min or less are left, or always), last seconds in red (from 5 s up to a minute before the end, 10 s by default), the icon, only elites and bosses, position; the window opens where you left it.
- 9 languages: English, Deutsch, Español (EU and AL), Français, Русский, 한국어, Português, 简体中文, 繁體中文.
- `/lbf check` shows what the game answered in the last fights, for bug reports.
