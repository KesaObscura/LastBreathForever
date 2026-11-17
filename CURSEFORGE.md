**Time to die for World of Warcraft: Forever (WoW Forever, Classic+): about how many seconds your target has left.**

A small frame next to your target shows **"~12 s"** (longer times as "~2:30" or "~12 min"), live in combat. Finish the long cast or switch targets, keep the potion, the trinket and the cooldown for the last seconds, and see when a boss is about to go down. Solo, in a group, in dungeons and on bosses. For every class: damage dealers, tanks and healers.

*Features asked for in the comments get built. Tell us what you need: comment here or open an issue on [GitHub](https://github.com/KesaObscura/LastBreathForever/issues).*

## Time to die, kill time: what it shows

- **About how many seconds your target has left**, worked out from how fast it has been losing health in this fight. Always "about", never exact: when the damage changes a lot (a burn phase, the group arriving late), the number follows with a delay. In the last part of a fight it is close.
- **No number is better than a wrong one.** The seconds appear once the target has lost a few percent; in a group or on a boss also after about 10 s, because the first seconds of a pull say too little. Meanwhile a **dim icon** shows that the addon is counting.
- **Joined late?** A boss you take into your target at 50 %, the next mob of a pull: it gets its seconds too, a little later, once it has lost some more health.
- **Back to the same target** in the open world: its seconds are there at once.
- **Last seconds in red**: from 5 s up to a minute before the end (10 s by default), for the cooldowns, trinkets and potions you keep for the finish.
- **Longer fights read easily:** "~2:30" above 90 s, "~12 min" above 10 minutes.

## Healers: keep the boss on your focus

Switch on the **focus frame** and `/focus` the boss: its seconds stay on screen while an ally is your target. Damage dealers use the same for the boss while they kill adds. When your target is your focus, both frames show the same seconds.

## Settings

Two columns, target and focus (the focus frame can use the target's settings or its own):

- **Show from**: only once about 30 s, 1, 2, 5 or 10 minutes or less are left (5 minutes by default), or always.
- **Last seconds in red**: off, 5, 10, 15, 20, 30, 45 or 60 s.
- **Only elites and bosses**, **size**, **icon**.
- **Language**: your game's language or any of the 9; the window opens where you left it.
- Unlock the frames to drag them anywhere; a fight locks them again.

## Commands

| Command | Does |
|---|---|
| `/lbf` | open the settings (also: the addon menu at the minimap) |
| `/lbf unlock` / `/lbf lock` | move the frames / lock them |
| `/lbf reset` | put the frames back in the middle of the screen |
| `/lbf check` | what the game answered in the last fights, for bug reports |
| `/lbf help` | list the commands |

## FAQ

- **Is it exact?** No addon can be exact here: the number is an estimate from the fight so far. It is close in the last part of a fight and can be off by a lot when the damage suddenly changes.
- **Why is there no number at the start of a fight?** The first seconds of a pull say too little (the tank alone, then the group). A number that is three times too high would cost you a cooldown; the dim icon says the addon is counting.
- **Does it work in WoW Classic Era, Hardcore or retail?** No. It is made for World of Warcraft: Forever (client 1.60.1) and its addon rules.
- **I switched to an add and back to the boss in a dungeon, and the number took a moment.** Put the boss on your focus: the focus keeps its count all fight long.
- **Does it need other addons?** No libraries, nothing else.

## Tested so far

- **In the live game**, priest level 24-30: solo in the open world, in a group of five in dungeons, on dungeon bosses, with the boss as target and as focus, in English and Russian.
- Accuracy checked against the real kill time on more than a dozen boss fights and many solo fights.
- **Not confirmed in game yet:** raids. Playing one? Tell us in the comments.

## More Forever addons

- [Full Mana Forever](https://github.com/KesaObscura/FullManaForever): the right mana potion at the right moment, the five-second rule and live mana regen.

## Bug reports

Please include the lines of `/lbf check` (they are also kept in `WTF\Account\ACCOUNTNAME\SavedVariables\LastBreathForever.lua`; no names), your class and level, and what you expected. Lua errors are easiest to read with BugGrabber + BugSack.

Source code and issues: [GitHub](https://github.com/KesaObscura/LastBreathForever).

Vollständig auf Deutsch · Totalmente en español · Entièrement en français · Полностью на русском · 한국어 완전 지원 · Totalmente em português · 完整简体中文 · 完整繁體中文 — the addon follows your game language.

- **Deutsch:** Zeigt, wie viele Sekunden dein Ziel ungefähr noch lebt, live im Kampf.
- **Español:** Muestra cuántos segundos le quedan más o menos a tu objetivo, en pleno combate.
- **Français :** Affiche combien de secondes il reste environ à ta cible, en plein combat.
- **Русский:** Показывает, сколько примерно секунд осталось жить твоей цели, прямо в бою.
- **한국어:** 전투 중 대상이 대략 몇 초 뒤에 죽는지 보여 줍니다.
- **Português:** Mostra quantos segundos mais ou menos restam ao seu alvo, em pleno combate.
- **简体中文：** 在战斗中显示你的目标大约还能活几秒。
- **繁體中文：** 在戰鬥中顯示你的目標大約還能活幾秒。
