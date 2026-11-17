-- Open-ended knowledge. Each entry: q = example phrasings, a = answer ({level},{class},{zone},{name},{race},{faction} are filled in),
-- class = only for that class token, src = "classic" when it's Classic baseline that Forever may have changed.
-- The updater appends thousands more of these (Knowledge/KB_Learned.lua) - this is the hand-written seed.
local _, FAI = ...
local KB = FAI.KB

local function add(e) KB[#KB + 1] = e end

------------------------------------------------------------------------ general
add{ q = { "what can you do", "help", "how do i use this", "what can i ask" },
  a = "Ask me anything about WoW Forever in plain words. Try:\n- where is Hogger\n- who drops Linen Cloth\n- quest The Defias Brotherhood\n- what should I do next\n- where should I level\n- what dungeons should I run\n- onyxia attunement\n- best warrior leveling talents\n- price of Arcanite Bar\nClick a [pin] to put a waypoint on your map." }

add{ q = { "what is rested experience", "how does rested work", "rested bonus", "how long to get fully rested" }, src = "classic",
  a = "Rested XP doubles mob-kill XP until it runs out (quest XP isn't affected). You gain it while logged out or standing in an inn/capital: 5% of a level every 8 hours, capped at 1.5 levels. Log out in inns." }

add{ q = { "how do i make gold", "best way to make gold", "gold while leveling", "how to make money", "im broke" },
  a = "While leveling: take two gathering professions (Skinning/Mining or Herbalism/Mining) and sell everything raw on the AH, loot all cloth, skip expensive spell ranks you don't use. At 60: farm Runecloth + Essences in Eastern Plaguelands, Dark Iron Ore / BRD runs, Arcane Crystals (Thorium), Black Lotus routes, or Dire Maul runs. Check prices with 'price of <item>'." }

add{ q = { "best professions for leveling", "what profession should i pick", "best professions", "professions for gold" },
  a = "Leveling: two gathering professions make the most gold (Herbalism + Mining or Skinning + Mining). Always keep First Aid; Cooking and Fishing are free value. At 60 most switch to: Engineering (PvP/raid utility), Alchemy (flasks/potions), Enchanting, or a gear craft like Blacksmithing/Tailoring/Leatherworking for pre-raid BiS." }

add{ q = { "first aid", "how to level first aid", "bandages" },
  a = "First Aid trainers are in every capital. Level it on cloth as you loot it: Linen -> Wool -> Silk -> Mageweave -> Runecloth bandages. At 225 the Triage quest (Theramore/Hammerfall doctor) unlocks Expert to 300. Bandages save huge downtime for non-healers." }

add{ q = { "how do i train weapon skill", "weapon master", "learn new weapon", "where do i learn swords axes daggers maces polearms staves bows guns" }, src = "classic",
  a = "Weapon Masters teach new weapon types for 10s each. Alliance: Woo Ping (Stormwind), Buliwyf Stonehand and Bixi Wobblebonk (Ironforge), Ilyenia Moonfire (Darnassus). Horde: Hanashi and Sayoc (Orgrimmar), Ansekhwa (Thunder Bluff), Archibald (Undercity). Each sells different types - ask 'where is Woo Ping' for a pin." }

add{ q = { "rare spawns", "rare elite", "how to find rares" },
  a = "You have RareScanner installed - it alerts you and marks rares on the map. Ask 'where is <rare name>' and I'll pin its spawn points." }

add{ q = { "elite quests", "group quests", "should i do elite quests" },
  a = "Elite/group quests give big XP and good gear but cost time finding a group. Do them when a group forms naturally or you outlevel them by 3-5 levels; skip the ones RestedXP skips." }

add{ q = { "what do i do at 60", "endgame", "what now at 60", "max level what next" },
  a = "At 60: get your Molten Core and Onyxia attunements, run pre-raid BiS dungeons (UBRS, Scholomance, Stratholme, Dire Maul, BRD), farm reputations (Argent Dawn, Thorium Brotherhood, Timbermaw), build gold for your epic mount, and join a raiding guild. Ask '<class> pre raid bis' or 'mc attunement'." }

add{ q = { "hearthstone", "how to set hearthstone", "hearthstone cooldown" }, src = "classic",
  a = "Talk to an innkeeper and choose 'Make this inn your home'. Hearthstone has a 1-hour cooldown. Smart move: set it at the hub you'll return to, and use flight paths for the rest." }

add{ q = { "how much experience to level", "how long to level 60", "fastest way to level", "leveling tips" },
  a = "Fastest leveling: follow your RestedXP route (ask 'what should I do next'), always carry quests while traveling, kill everything on the way, use rested XP, skip elite quests unless grouped, and AoE-farm dungeons with friends if you're a mage. Turn in quests in batches near flight paths." }

add{ q = { "bags", "where to get bags", "bigger bags" },
  a = "Cheap: buy 6-8 slot bags from general vendors or the AH. Tailors make Linen (6), Woolen (8), Silk (10), Mageweave (12) and Runecloth (14) bags - usually cheap on the AH. 16-slot bags (e.g. Onyxia Hide Backpack from the Onyxia attunement) are endgame." }

------------------------------------------------------------------------ attunements
add{ q = { "ubrs key", "seal of ascension", "how to get into ubrs", "upper blackrock spire key" }, src = "classic",
  a = "UBRS key (Seal of Ascension): quest from Vaelan at the LBRS entrance. In LBRS collect the Unadorned Seal (random drop) plus gemstones from Highlord Omokk, War Master Voone and Overlord Wyrmthalak. Then forge it with Emberstrife in Dustwallow's Wyrmbog while disguised with the Amulet of Draconic Subversion. Only one key holder is needed per group." }

add{ q = { "scholomance key", "skeleton key", "how to get into scholomance" }, src = "classic",
  a = "Scholomance needs the Skeleton Key. Alliance: Commander Ashlam Valorfist at Chillwind Camp (Western Plaguelands) starts the chain; Horde: High Executor Derrington at the Bulwark. The chain ends with forging the key from the Skeleton Key Mold." }

add{ q = { "dire maul key", "crescent key", "how to get into dire maul west north" }, src = "classic",
  a = "Dire Maul East: chase Pusillin through the wing - he drops the Crescent Key, which opens the West and North wings (and the North tribute run)." }

add{ q = { "stratholme key", "key to the city" }, src = "classic",
  a = "Key to the City drops from Magistrate Barthilas in Stratholme and opens the side gate - not required, you can always enter through the main gate." }

add{ q = { "argent dawn reputation", "how to get argent dawn rep", "scourgestones" }, src = "classic",
  a = "Argent Dawn: equip the Argent Dawn Commission (Light's Hope / Chillwind Camp) and turn in Scourgestones at Light's Hope Chapel or the Chillwind Camp/Bulwark officers. Scholomance, Stratholme and Plaguelands quests give lots too." }

add{ q = { "timbermaw reputation", "timbermaw rep", "how to get to winterspring through felwood" }, src = "classic",
  a = "Timbermaw Hold: kill Deadwood furbolgs (Felwood) and Winterfall furbolgs (Winterspring), turn in Deadwood Headdress Feathers / Winterfall Spirit Beads at Timbermaw Hold. Unlocks safe passage, the Timbermaw tunnel and good recipes." }

add{ q = { "thorium brotherhood reputation", "thorium brotherhood rep", "dark iron residue" }, src = "classic",
  a = "Thorium Brotherhood: turn in Dark Iron Residue (BRD) and crafted/raw materials to Lokhtos Darkbargainer in BRD's Grim Guzzler. Unlocks Dark Iron and fire-resistance recipes." }

add{ q = { "pre raid bis", "pre raid best in slot", "best gear before raiding", "what gear should i farm at 60" },
  a = "Pre-raid gear comes mostly from UBRS, Scholomance, Stratholme (Baron), Dire Maul and BRD, plus crafted items and the Dungeon Set 1 pieces. You have AtlasLoot installed - open it for your class's list - and ask me 'who drops <item>' for any single piece." }

add{ q = { "what is the max level", "what is the level cap", "max level forever", "how high can i level" },
  a = "The level cap in Forever is 60, same as Classic. Profession skill caps are 300." }
add{ q = { "how long does it take to hit 60", "how long to get to max level", "how many hours to 60", "how long is leveling" },
  a = "Most players take roughly 4-7 days of /played to reach 60 in Classic-style leveling; Forever's XP curve is the same (about 4.08M XP), with more quests and lower dungeon kill XP. Following a RestedXP route, using rested XP and the camp/food XP buffs gets you toward the fast end. Ask 'what should I do next' for your route." }
