-- Hand-checked gameplay answers and extra phrasings, written to fix wrong matches found in testing.
-- Only mechanics we're sure of go here. src = "classic" marks Classic rules Forever hasn't confirmed.
local _, FAI = ...
local KB = FAI.KB
local function add(e) KB[#KB + 1] = e end

-- extra ways people ask an existing question
local function alias(first, more)
    for _, e in ipairs(KB) do
        if e.q and e.q[1] == first then
            for _, m in ipairs(more) do e.q[#e.q + 1] = m end
            return
        end
    end
end

alias("profession changes forever", { "are there new professions", "are there new professions or just the old ones reworked",
    "any new professions in forever", "is there a new profession" })

add{ q = { "do grey mobs give xp", "grey level mobs xp", "why do i get no xp from low level mobs", "mobs too low no xp",
    "grey mobs worth killing", "do low level mobs give experience" },
  a = "Mobs whose level shows in grey are far enough below you that they give no XP. They still drop loot and still count for quests. A grey name or health bar is different: that mob was tagged by another player, so you get nothing from it." }

add{ q = { "fastest way from ironforge to darnassus", "how do i get to darnassus from ironforge", "ironforge to darnassus",
    "how to get to darnassus", "stormwind to darnassus", "how do i get to teldrassil" },
  a = "Take the Deeprun Tram to Stormwind, then the boat from Stormwind Harbor to Auberdine in Darkshore. From Auberdine, take the boat to Rut'theran Village and walk into the portal there to reach Darnassus. The older route still works too: Menethil Harbor in the Wetlands has a boat to Auberdine. Mages can just teleport." }

add{ q = { "should i go to hyjal or eastern plaguelands", "hyjal or plaguelands at 58", "hyjal vs eastern plaguelands",
    "where to level 55 60", "best zone for 58" },
  a = "Both work at 58. Mount Hyjal is Forever's new 55-60 zone with new quests and factions; you need the level-55 potion quest in Everlook to get past Darkwhisper Gorge. Eastern Plaguelands is the Classic 53-60 zone, worth it if you want Argent Dawn reputation or Stratholme and Scholomance quests." }

add{ q = { "what alchemy recipes sell good on the ah", "what potions sell best", "what should i craft with alchemy for gold",
    "alchemy gold making", "best alchemy items to sell" },
  a = "Raid and PvP consumables sell best: the potions and elixirs from the raid kit (ask 'which potions do I need for raiding'). Before you craft, check today's price with 'price of <item>' on the potion and on its herbs. Sometimes the herbs are worth more than the potion." }

add{ q = { "how do i get out of combat to stealth again", "cant stealth in combat", "how to drop combat", "stuck in combat cant stealth",
    "how long until combat drops", "vanish out of combat" },
  a = "You can't stealth while in combat. Combat drops a few seconds after nothing is hitting you and no mob is chasing you, so run out of range or kill what's on you. Rogues can Vanish to drop combat and stealth in one go. Night Elf Shadowmeld only works out of combat." }

add{ q = { "warlock epic mount quest", "dreadsteed quest", "warlock mount quest at 60", "how do i get the dreadsteed", "warlock 60 mount how hard" },
  src = "classic", class = "WARLOCK",
  a = "Classic Dreadsteed: a long level 60 chain that starts with Mor'zul Bloodbringer in the Burning Steppes. It ends with a summoning ritual inside Dire Maul that needs a full group to defend. It takes a few days and costs real gold in materials. The level 40 Felsteed is the short one." }

add{ q = { "what is dkp", "what is dkp and how does it work", "how does dkp work", "dkp loot system", "is dkp allowed" },
  a = "DKP (Dragon Kill Points) is a guild loot system, not part of the game. You earn points for showing up to raids and kills, then spend them bidding on loot. Each guild sets its own rules and usually tracks points with an addon or a spreadsheet. Normal DKP is fine; GDKP, where people bid gold, is not allowed in Forever." }

add{ q = { "my auction didnt sell where did my item go", "auction expired", "unsold auction", "where do expired auctions go",
    "item didnt sell on ah", "do i get my deposit back" },
  a = "When an auction expires unsold, the item comes back to you by mail, so check any mailbox. The deposit is not refunded. If it sold, the gold arrives by mail instead, minus the auction house cut." }

add{ q = { "how do i know what price to sell stuff for", "what should i price my items at", "how to price items on ah",
    "what price should i list at", "how much should i sell this for" },
  a = "Search the item at the auction house and list slightly under the cheapest copy. With Auctionator installed, ForeverAi can check it for you: ask 'price of <item>' to get today's AH price next to the vendor price. If the AH price is barely above the vendor price, just vendor it." }

add{ q = { "horde or alliance which is better", "should i play horde or alliance", "alliance or horde in forever", "is horde or alliance better" },
  a = "Neither faction is stronger. Pick the side your friends play, since you can't group with or trade with the other faction. Then pick the race and class combo you like; Forever opened new combos on both sides, and Skyborne pick a faction when they're created." }

alias("forever leveling route", { "best route 1-60", "best leveling route for my class", "leveling route 1-60" })

alias("dungeon group size", { "how many people for a dungeon", "how many players do i need for a dungeon" })

add{ q = { "how do i make a raid group", "convert party to raid", "how to make a raid", "how do i start a raid group", "turn group into raid" },
  a = "Form a party first. Then the party leader right-clicks their own portrait and chooses Convert to Raid (it's also a button on the Raid tab of the social window, O). A raid holds up to 40 players in groups of 5. Party quests can't be completed while you're in a raid group." }

add{ q = { "how do i get soul shards", "where do soul shards come from", "how to farm soul shards", "drain soul shards" }, src = "classic", class = "WARLOCK",
  a = "Cast Drain Soul on a mob and let it die while the channel is running. If the mob gives XP or honor, you get a Soul Shard. Shards stack in a soul bag, which can go in the reagent bag slot in Forever." }

add{ q = { "where can i smelt thorium", "how do i smelt thorium", "smelt thorium skill", "where is a forge", "where do i smelt ore" }, src = "classic",
  a = "Smelt at any forge: every capital has one (Ironforge's Great Forge, the forges in Stormwind, Orgrimmar and Undercity), plus many towns. Thorium needs Mining 230. Open the Professions window, pick Mining and click the bar you want to smelt while you stand next to the forge." }

add{ q = { "how do i get the timbermaw quest items", "timbermaw turn ins", "deadwood headdress feathers", "winterfall spirit beads", "timbermaw rep items" }, src = "classic",
  a = "Timbermaw rep turn-ins: Deadwood Headdress Feathers drop from Deadwood furbolgs in northern Felwood, and Winterfall Spirit Beads from Winterfall furbolgs in Winterspring. Turn them in, in stacks of 5, to the Timbermaw furbolgs at either end of the Timbermaw Hold tunnel. Killing those furbolgs also gives Timbermaw rep on its own." }
alias("summoning stones forever", { "how do i summon people to a dungeon", "how do i summon my group", "summon people to dungeon" })

add{ q = { "how do i whisper someone from the other faction", "can i talk to the other faction", "can i mail items to the other faction",
    "can i trade with horde", "can i trade with alliance", "send items to other faction" }, src = "classic",
  a = "You can't whisper, mail, trade or group with the other faction in game. To chat across factions, add each other as BattleTag friends in the Friends list (O). To move an item across, list it on a neutral auction house (Booty Bay, Gadgetzan or Everlook) and have the other character buy it." }

add{ q = { "what happens if i die in pvp", "dying in pvp", "does pvp death lose durability", "do i lose anything dying to players" }, src = "classic",
  a = "A PvP death works like any other: release to the graveyard and run back, or rez at the spirit healer. In Classic rules, deaths to players don't damage your gear's durability, and being killed gives you no penalty beyond the run back." }

add{ q = { "how do i get better gear at 60", "what do i do for gear at 60", "how to gear up at 60", "how do i get pre raid gear" },
  a = "At 60, gear comes from: the level 60 dungeons (Blackrock Depths, Lower and Upper Blackrock Spire, Dire Maul, Scholomance, Stratholme) and Forever's new Blackmaw Hold and Shaper's Terrace; crafted BoE pieces from the AH; the PvP honor set; and then the launch raids, The Barrow Deeps (10), Hyjal Summit (20) and Onyxia's Lair. Ask 'I hit 60 now what' for a step-by-step plan." }

add{ q = { "where is grom'gol", "grom'gol base camp", "how do i get to grom'gol", "where is the zeppelin to stranglethorn" }, src = "classic",
  a = "Grom'gol Base Camp is the Horde camp in northwest Stranglethorn Vale, on the coast. It has a flight master and zeppelins to Orgrimmar and the Undercity." }
alias("group xp penalty", { "does killing mobs in a group give less xp", "do i get less xp in a group", "is grouping worse xp" })

add{ q = { "can you make waypoints on my map", "can you set a waypoint", "can you put a pin on my map", "can foreverai mark my map",
    "how do i get a waypoint", "can you make an arrow to it" },
  a = "Yes. Click any [pin] in my answers and I'll set a waypoint on your map (and a TomTom arrow if you have TomTom). For a quest chain, ask 'checklist <quest>', then 'give me the route in order': I'll list every stop you have left with a pin each, and 'Pin every stop' places them all with TomTom." }
