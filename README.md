# ForeverAi

An in-game assistant for **World of Warcraft: Forever** that knows your character.

Type `/fai` and ask in plain words. ForeverAi answers from your own character and server:

- **Quest checklists** – `checklist In Dreams` shows every quest you need first, ticked from your character's
  quest history, your next step with a map pin, and what comes after.
- **Lost progress** – `lost progress` finds follow-up quests you finished the prerequisites for but never picked up, at any level.
- **Your bags and bank** – `anything important in my bank` flags items that start or finish an open quest.
- **Routes** – `give me the route in order` lists every stop left on a chain, with a pin each (TomTom shows them all).
- **Gold, gear and reputation** – gold farms ranked by your professions and your server's AH prices (Auctionator),
  gear upgrades in your bags, reputation progress.
- **Forever knowledge** – new zones, dungeons, raids, professions, Camping, Legacy, Skyborne and more.

Works with Questie, RestedXP, Auctionator and TomTom when you have them.

## Install the addon

**Easiest:** install ForeverAi with the CurseForge app. It also installs **QuestieDB** for you, the free quest database
ForeverAi reads (just the data: no map icons, no tracker; Questie itself is optional).

**By hand:** download `ForeverAi-addon.zip` from [Releases](../../releases), unzip it into
`World of Warcraft\_forever_\Interface\AddOns\`, and also install **QuestieDB** (Forever version) from CurseForge.
Without QuestieDB everything still works except quest chains, routes, NPC locations and lost progress, and ForeverAi
tells you so. Restart WoW, then type `/fai`.

The addon works fully on its own. Everything below is optional.

## Optional: live AI answers (about 2 minutes)

The addon can't reach the internet (WoW doesn't allow it), so for questions it doesn't know it can hand them to
**ForeverAi Companion**, a small program on your PC that asks Google Gemini using your own **free** key and shows
the answer right inside ForeverAi's window, built on your character's real data.

1. Download `ForeverAiCompanion.exe` from [Releases](../../releases).
2. Run it. A setup window opens.
3. Click **Open Google AI Studio**, sign in, click **Create API key**, copy it.
4. Paste it, click **Test key, install and start**. Done.

Play WoW in **Windowed** or **Borderless (Windowed Fullscreen)** mode for live answers.

### "Windows protected your PC"

The companion isn't code-signed yet (signing certificates cost money), so Windows SmartScreen may warn you the
first time. Click **More info → Run anyway**. Before you do, you can check it yourself:

- **The code is all here** – [`companion/`](companion) is about 1,200 lines of plain Python, standard library only.
- **It's built by GitHub, not on someone's PC** – the [build workflow](.github/workflows/release.yml) compiles the
  .exe from this repo on GitHub's servers and publishes a signed provenance record. Verify with:
  `gh attestation verify ForeverAiCompanion.exe --repo <owner>/ForeverAi`
- **Checksums** – `SHA256SUMS.txt` is attached to every release.
- **Scan it** – upload it to [VirusTotal](https://www.virustotal.com) if you like. A few engines sometimes flag any
  program packed with PyInstaller; that's a known false positive.

## What the companion does and doesn't do

**Does:**
- While WoW is open, reads only ForeverAi's small colored strip in the corner of its window (your question plus
  level, class, zone, professions, gold, quest log and quest progress) and draws the answer over ForeverAi's panel.
- Sends that question and info to Google's Gemini API with your key.

**Doesn't:**
- Press keys, click, move your character, or read/modify game files or memory. It can't play the game.
- Need admin rights. Everything lives in your user folder:
  - `%LOCALAPPDATA%\Programs\ForeverAi\` – the program
  - `%APPDATA%\ForeverAi\` – your key, a log, and your question/answer history (never uploaded anywhere)
  - "Start with Windows" is a checkbox, and it sleeps until WoW is open.
- Send your key anywhere except Google.

**Uninstall:** Windows Settings → Apps → *ForeverAi Companion* → Uninstall (or run it with `--uninstall`).

It reads the screen and draws on top of the game the way Discord or OBS overlays do; it never automates gameplay.
Use it at your own discretion like any third-party tool.

## Accuracy

Offline answers come from game data (Questie), your character, and researched Forever notes. When ForeverAi isn't
sure what you meant it says `Reading this as: …` so a misread is obvious, and it says "I don't know" rather than guess.
Answers marked *(Classic info)* are Classic rules Forever hasn't confirmed yet.

## Sources

Forever knowledge was researched from the official Forever announcements and patch notes, Wowhead, the WoW wiki,
and community sites such as foreverchanges.pro and forever-xp.com, rewritten in our own words. Thank you to those communities.

## License

MIT. Quest/NPC data comes from Questie at runtime; World of Warcraft is a trademark of Blizzard Entertainment.
ForeverAi is a fan project, not affiliated with Blizzard.
