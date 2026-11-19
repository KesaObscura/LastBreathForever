# Working on Last Breath Forever

WoW: Forever addon (client 1.60.1, interface 16001): about how many seconds the current target has
left. Plain Lua 5.1, no libraries. Third addon of the Forever series with Full Mana Forever and
Full Health Forever (same owner, same rules).
Files load in TOC order: Locale.lua (9 languages) -> Skin.lua (the series' window look, a copy of
Full Mana Forever's with this addon's colour and logo) -> Core.lua (the seconds, the frame on
screen, commands) -> Options.lua (settings window) -> SelfTest.lua (`/lbf selftest`). Settings: `LastBreathForeverDB` (account-wide).

## Rules

- **No technical notes in this repository** (owner, 11 Nov, as for Full Mana Forever): what was
  found out about the game, test results, the owner's decisions, the roadmap and store text
  drafts live in the owner's private repository (folder `LastBreathForever/`, file
  `LBF-CLAUDE.md`). **Before any work, attach that repository (ask the owner if it is not in the
  session) and read `LBF-CLAUDE.md`**; write new findings and decisions there, never here. Code
  comments say what the code does, briefly.
- **Texts for players say what a thing does and when, never how it is done**: tooltips,
  changelog, CurseForge and README carry no word about the game calls or tricks behind a feature.
- **Public repository: nothing personal.** No session links, no `Co-Authored-By:` trailers, no
  e-mail addresses, no player names in commits, PR texts, code or docs. Commit messages describe
  the change only.
- Other addons: ideas only, never code.
- Every user-visible text in all 9 locale tables (esMX falls back to esES); every clickable
  control has a tooltip, also while greyed out.
- Run the tests after every change: `lua5.1 tests/run.lua` must end with `0 failed`.
- After every change, hand the owner a test zip built from the committed state:
  `git archive --format=zip --prefix=LastBreathForever/ -o LastBreathForever-<version>-<hash>.zip HEAD -- . ':!tests' ':!tools' ':!docs' ':!.gitignore' ':!.github' ':!.pkgmeta' ':!.gitattributes' ':!CURSEFORGE.md' ':!CLAUDE.md'`
- Keep in sync on every user-visible change: `CHANGELOG.md` (headings `**Last Breath Forever
  X.Y.Z**`), `README.md` (features, commands), the version in `LastBreathForever.toc` and
  `ns.VERSION` in `Core.lua` (a test checks both).
- Work on the session branch; `main` changes only through a PR the owner merges with **Squash
  and merge**; no PR unless the owner asks. Commit author `Claude <noreply@anthropic.com>`;
  never rewrite the history of `main`.
