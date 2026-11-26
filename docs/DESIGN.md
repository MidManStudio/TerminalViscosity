# Terminal Viscosity: the locked design

This is the design of the game as the owner has stated it. It is the one place to look before building anything of the economy, the building, water, dispensers or chemistry, so that a new session does not have to be told again.

How to read it:

- **Locked** means the owner said it. It changes only when the owner says so.
- **Proposed** means it was worked out here to fill a gap, and waits for the owner's yes.
- **Open** means nothing has been decided, and nothing should be built on a guess.

What is built today is in `docs/ARCHITECTURE.md` and `client/docs/client.md`. This file is about where the game is going.

## The game in short

**Locked.** A multiplayer-first 3D water-balloon fight whose balloons hold liquid chemicals that the player makes in a lab. The lab is its own mode: fill balloons, paint them, keep up to three in a loadout, burn the ones that are not wanted. The arena is a coliseum where the loadout is what is thrown. Around the two modes is an economy: buy, build, repeat, make money, play against other people, and sell what is made.

## The building

**Locked.** The lab is one room of a whole building. The building has futuristic gate doors and corridors, a shop, a firing range or test ground, and a broker. For performance a place exists only while the player is in it, so the building needs culling and loading of places.

**Open.** How places load and unload, how big each is, and how the player moves between them. Nothing of the building exists yet. The current lab room is the first room of it.

## The economy

**Locked.** Buy, build, repeat, and make money. The player plays against other people and sells what is made. Dispensers are bought. Chemicals are bought wholesale from the shop. Chemicals and mixtures are unlocked before they can be bought or used. The broker buys what the player makes.

**Open.** Every price. How an unlock is earned or paid for. What the broker pays and how it decides. What the other players do in the economy, and whether anything is shared between players.

## The balloon fight

**Locked.** The player carries a basket of balloons in the left hand and throws with the right. Throwing needs aim assist. There is no slide. Movement is stepping left, right, forward and back, in the manner of shadow boxing, because a jetpack is planned. The jetpack gives quick dashes on the ground and manoeuvres in the air. Special launchers for balloons are planned as well, a slingshot and a lancer gun. Dying must be much easier in the lab than in the arena: nothing heals by itself, toxic chemicals kill slowly, and the player has to go and heal up by hand.

**Built.** In the arena: walking, jumping, a charged throw, hit points, knock-out and three bots. In the lab: hit points that come back by themselves after 4 s without a hit, at 8 a second (`health.odin`), and a first aid cabinet that restores full health at once, with a 30 s wait before it can be used again (`gear.odin`). The owner's rule above replaces the healing by itself, and it has not been changed yet.

**Not built.** The basket, aim assist, the dash, the jetpack, the launchers, and the slow poison of the lab.

## How a balloon bursts

**Locked.** A balloon changes when it lands: some splash, some explode and some turn to gas, and what each does depends on its kind.

- Splash kinds: regular; acidic, which melts the player on death; impact; exothermic, which sets the player on fire like a Molotov; endothermic, which freezes.
- Exploder kinds: push back; toxic, which leaves fumes; endothermic, which strips the oxygen away; freeze.
- Gas kinds: toxic; smoke; freeze; burn; one that makes a flood; one that confuses.

**Built.** A burst carries a compound, a volatility from 0 to 1 and a radius. The three states and the kinds do not exist yet.

**Proposed.** The mixture in the balloon decides both, so that the lab teaches the arena and nobody designs fifteen effects by hand: the volatility and the boiling point of the mixture decide whether it splashes, explodes or turns to gas, and the harm of its compounds decides the kind. This waits for the owner's yes.

**Open.** What each status does per second and for how long, what each death looks like, and how fumes, fire and flood are drawn on a phone.

## Bets and the money loop

**Locked.** The balloon fight is a competition between labs. Before a match the players place bets of fixed amounts, against another team or one against one. The more is bet, the more is paid back, and a smaller bet pays less. The money loop is: make chemicals in the lab and sell them to companies, in bulk or as a fixed amount that a buyer asks for; buy more supplies; improve the lab and its productivity; later automate parts of it. Customising the lab guy is a maybe. Raw materials and chemicals are bought and used up, and what is left over becomes the balloons for the fights.

**Proposed.** These are the gaps that were pointed out when the loop was described, and each waits for the owner's answer.

- A won bet has to pay more than the same balloons would sell for, or fighting never pays.
- A player with no money and no ammo needs a way back, such as cheap basic balloons that are always on offer, or the broker lending against later sales.
- Buyers can ask for an amount at a purity by a time, so that selling is a goal and purity matters. The pages already carry purity bands, unlocks, temperatures and catalysts.
- Bets come in fixed amounts, so they can double as brackets, with matches between labs of a similar tier.
- The smallest loop to build first is one contract, one sale, one fight with one bet, then back to the lab.

**Open.** Every amount, payout and price, what is lost on a defeat, and what automation does.

## Bots and the training center

**Locked.** Real multiplayer will use what Tower-Of-Babylon uses for networking. For now the arena has bots, and they will become a training center that helps the player get better at shooting. The bots have to be fair enough to hit, all the more once the jetpack exists.

**Built.** A bot sees some of the balloons that come at it and not others, reacts late and rests after a sidestep (see `bot.odin` in `client/docs/client.md`). The numbers are first guesses and have not been tried against a person.

**Open.** The levels of the training center, what it rewards, and how it is entered.

## The stations

**Locked.** Already in the lab: glassware (beakers, conical flasks and other vessels), cold and hot baths, the balloon fill unit, the balloon disposal unit, the chemical dispensers, the drawing station, the balloon loadout rack.

**Locked.** To be added: a proper sink, a shelf for catalysts, an electrolysis station, a distillation station, an incinerator and waste disposal unit, a furnace, a centrifuge, emergency gear (a ballistic shield, a fire extinguisher, a gas mask, goggles), an oven and a freezer.

**Not in the owner's list, added at his request later:** the vial racks, the first aid cabinet, the scale and the shelves of bottles, built in `lab-1`.

**Open.** What each new station does, in detail, beyond what the chemistry below says. How the emergency gear is worn or placed, and what each piece protects from.

## Dispensers and the dispenser wall

**Locked.**
- A dispenser is bought, goes into the inventory, and is then placed on the dispenser wall by the player.
- The wall has a limited number of slots. It can take other mountable things as well as dispensers, in case more is added.
- Placing uses the drag and drop system that the building of things will use, with placing things and blueprints.
- It is one kind of dispenser, not one for each chemical. The player buys wholesale chemical from the shop and fills the dispenser with it. The dispenser has a gauge.
- Water is the exception: it has no dispenser. It comes from the sink.

**Open.** The number of slots. How big a wholesale container is and what it costs. What happens when a dispenser holds one chemical and the player wants another. How the gauge reads.

## Water and the sink

**Locked.**
- Water has purity: ordinary sink water, distilled water, all the way to ultra pure water.
- Water has no dispenser. It is fetched from the sink.
- The sink also has soap, for washing hands, and for fetching water.
- The player can purify water, by distilling it, in a mini-game that is played to reach specific levels of purity.

**Proposed.**
- Purity is a number from 0 to 1 that every liquid in a vessel carries, not only water. The bands of it have names, and reactions can ask for a band. For water the bands are sink water (below 0.5), distilled water (0.5 up to 0.95) and ultra pure water (0.95 and over). The bands live in the page of the compound (see `docs/REACTIONS.md`), so they can be moved by editing data.
- Sink water comes out of the tap at a fixed purity inside the sink band. Pouring two lots of the same compound together gives the mean of the two purities, weighted by volume.
- The mini-game is a thing of the distillation station. Until that station exists, there is no way to get past sink water.

**Open.**
- What washing hands does. Nothing in the game yet needs clean hands.
- The rules of the mini-game, and which levels of purity it can reach.
- Whether purity is shown as a number, as a band name, or both.
- What the sink's soap is for beyond washing hands.

## Chemicals

**Locked.**
- Each chemical is unlocked before it can be bought and used.
- Each chemical has its own page of reactions, a matrix of what it does with another chemical, and with two or more others. A combination can be of 2 up to n chemicals.
- The products have names of their own in the game and are real-world chemicals.
- A product has an unsafe meter and a reactivity. Some are enhanced by catalysts. Some are extracted by electrolysis. Some need a specific temperature to react safely.
- The page of a chemical says what a catalyst does for it, what electrolysis gives, what changes with ultra pure, distilled or sink water, and what changes when it is cold or hot.
- The player is not expected to remember all this: the UI has books.
- The start has 3 chemicals, 4 with water.
- The first four are water, acetic acid, ethanol and sulfuric acid.

**Proposed** (`docs/REACTIONS.md`): the format of the pages, written as DixScript, and the rules by which the game reads a vessel against them.

**Open.**
- The chemicals after the first four, and the products of the first four that need pages of their own (ethyl acetate, diethyl ether, ethylene, acetic anhydride and the rest of what the draft pages name).
- What a mix does when the player has not unlocked its reaction.
- How the books look and how a page is found in them.
- How the server learns the pages, since damage and volatility are worked out there.

## Reaction levels

**Locked.** A chemical is at most two reactions away from the base chemicals. Combining base chemicals into something new is reaction level 1. Combining that product with another chemical into something else is reaction level 2. There is no level 3. Most chemicals only ever reach level 1, and which ones reach level 2 depends on the chemical.

**Proposed.** Every compound page says its level: 0 for a base chemical, which is bought or fetched, 1 for what a reaction of base chemicals makes, and 2 for what a reaction makes that has a level 1 product among its inputs. A level 2 chemical starts no reactions. A reaction of any number of chemicals, from 2 up to n, is one level. A base chemical that comes out of a reaction, such as the water of an esterification, is a by-product and does not count. Electrolysis counts as one level. `scripts/check_chem.py` enforces all of it.

**Open.** Whether electrolysis should count as a level, and whether a catalyst should.

## How liquids look

**Locked.** Liquids are coloured differently from one another, so that a player can tell them apart in the glass. A compound gets a base colour and a seed for a procedural liquid shader, which gives it a small effect of its own.

**Proposed.** A page carries the base colour, the seed, how clear the liquid is, an effect (none, shimmer, swirl, bubbles or oily) and the strength of the effect. A mix is drawn in the blend of its ingredients' colours by volume, with a pattern whose seed is made from theirs. The checker refuses two compounds that share a seed, or whose colours are less than 40 steps apart in RGB.

**Open.** The shader itself, which is not written, what each effect looks like, and how the seed of a mix is made.

## What is not decided at all

- How the shop, the broker and the blueprints look and work.
- How multiplayer connects to the building and the economy.
- The player character, which the owner will make by hand.
- Combat beyond the assumptions in `docs/OPEN_DECISIONS.md`.
- What each kind of balloon does per second, and what each kind of death looks like.
- The numbers of bets, payouts, prices and contracts.

## Where the rest is

- What is built and how: `docs/ARCHITECTURE.md`, `client/docs/client.md`.
- Assumptions made in code that the owner has not confirmed: `docs/OPEN_DECISIONS.md`.
- The format of chemical pages, and the rules of mixing: `docs/REACTIONS.md`.
