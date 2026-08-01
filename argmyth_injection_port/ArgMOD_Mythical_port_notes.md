# The mythical metals unit, injected

This follows the ArgMOD port. Everything in the first document still
applies: the schema, the reagent and product tables, how permissions and
`fortress_mode` work, and the direction rule. This one only covers what is
specific to the mythical unit, plus one thing the first document left
implicit that turns out to be the whole story.

---

## What moved

| | |
|---|---|
Injected materials | 10 |
Injected reactions | 12 |
Injected permits | 10 |
New reaction categories | 0 |

The ten are `BISMANGAZ_BRONZE`, `COOL_SILVER`, `SEA_GOLD`, `AKIMRIL`,
`IGERKEL`, `REMANGKEL`, `GOBRONZE`, `ORICHALCUM`, `MITHRIL` and `REDSTEEL`.

Every category the twelve reactions use already exists, so this unit
declares none of its own. `IRIDIUM_FROM_PGM` and `SPECIALTY_ALLOYING`
point at the ones ArgMOD injects; `NONFERROUS_ALLOYING`,
`PRECIOUS_METAL_ALLOYING` and `STEELMAKING` are shared names that both
halves land in, same as before.

---

## Deciding what stays raw

The first document gave you the direction rule and then a table of
exceptions, which made the split look more complicated than it is. There
is really only one rule and one test.

**The rule.** Raws are parsed when the world loads. Injection happens
afterwards. An injected thing may name a raw thing. A raw thing may never
name an injected thing.

**The test.** Does any raw file mention this material by id? If yes it
stays raw. If no it gets injected.

That is the entire decision. Everything below is just that test applied to
the four cases that keep coming up.

### Anything that spawns in the ground is raw

Worldgen has finished before injection starts, so a mineral or layer stone
cannot be injected at all. Not a preference, a hard limit.

### Any metal smelted directly from ore is raw

Its ore names it with `METAL_ORE`, and the ore is a mineral, so the ore is
raw, so the metal is named by a raw file. That is the test failing.

Four metals land here: `UMANITIUM`, `DYSTRUM`, `BLURIUM` and `RUBEDITIUM`.
If they were injected, the `[METAL_ORE:...]` on umanite, native dystrum,
blurite and rubedite would resolve to nothing and those four ores would
stop smelting into anything at all.

### Anything else a raw file names is raw

Graphics bindings name materials. So do `MATERIAL_REACTION_PRODUCT`
tokens, and any reaction you leave in raws. In the base ArgMOD port that
is what held the ferroalloys back, and it is the same test, just a
different token.

This unit gets off lightly: `graphics_arg_mythical_ores.txt` binds nothing
but boulders, so no metal here is held back for a bar tile.

### An alloy of ore-smelted metals is injected

This is the part that reads backwards at first. `REMANGKEL` is alloyed
from blurium, cropparine and dystrum. All three are raw. `REMANGKEL` is
still injected, because the test is not about what a material is made
from, it is about whether anything in raws names it. Nothing does.
`REMANGKEL` only ever appears as the product of a reaction, and that
reaction is injected too.

So the split does not follow the tech tree. `REDSTEEL_MAKING` consumes
rubeditium, which is raw, and produces redsteel, which is injected. That
is fine and expected. Injected content naming raw content is the direction
that works.

### What the engine still cannot do

Add only. No editing, no cutting. So `[CUT_INORGANIC:BISMOR]` and the
redefinition that follows it stay raw, as do the three
`SELECT_INORGANIC` edits and both `CUT_REACTION` blocks. If you ever want
those injected, the engine needs an editing pass, which is on my list.

---

## What that leaves in your raw files

`inorganic_mythical_metals_arg.txt` keeps the `BISMOR` cut and
replacement, the `BISMOR_BRONZE`, `CROPPARINE` and `UMASTEEL` edits, and
the four ore-fed metals. Down from 678 lines to 270.

`reaction_mythical_metals_arg.txt` keeps the two commented-out
`NITRATED_DEEPCOKE` reactions untouched, `SELECT_REACTION:NITRA_TO_COKE`,
both `CUT_REACTION` lines and the `BISMOR_BRONZE_MAKING` redefinition.
Down from 257 lines to 53.

`inorganic_mythical_minerals_arg.txt` and `graphics_arg_mythical_ores.txt`
are unchanged. Nothing in either could be injected.

**`entity_mythical_arg.txt` should be deleted.** All ten of its permits
belong to reactions that are now injected, so every line in it is a raw
file naming injected content. Stripping it correctly leaves three
`SELECT_ENTITY` headers with nothing underneath, which does nothing at
all. The permits are carried in `argmyth_reactions.json` instead.

---

## Things I noticed in your raws

Same standard as last time. I ported everything exactly as written, and
these are only the things I could not resolve by reading. Several of them
I expect you already know about.

**`GOBRONZE_MAKING` has no `[FORTRESS_MODE_ENABLED]`.** I read this as
deliberate and ported it as-is. Gobronze is permitted to `EVIL` alone, and
fortress mode would hand it to the player regardless of permits, which
would defeat the point of a bronze the goblins make because they cannot do
better. Say so if I have that wrong and I will flip it.

**Four reactions have no `PERMITTED_REACTION` in any entity file:**
`ORICHALCUM_MAKING`, `REDSTEEL_MAKING`, `AKIMRIL_MAKING` and
`MITHRIL_MAKING`. All four have `FORTRESS_MODE_ENABLED`, so they are
reachable in fort mode and only unreachable to other civs. They are
ported that way, as `"mode": "NONE"` with `fortress_mode` true.
Flagging it only in case the omission was accidental rather than a
deliberate player-only tier.

**`IRIDIUM_EXTRACTION_DYSTRUM` uses `[SKILL:LYE_MAKING]`** while
`IRIDIUM_EXTRACTION_PLATINUM` uses `SMELT`, despite being the same
reaction shape at the same building. Both work. Ported as written.

**Two raw files declare the wrong id on line 1.**
`inorganic_mythical_metals_arg.txt` opens with `inorganic_metals_arg` and
`entity_mythical_arg.txt` opens with `entity_arg`, both duplicating the id
of your base files. I have not confirmed what DF does with duplicate raw
file ids, so treat this as worth a look rather than a known problem. The
entity one goes away if you delete that file.

**`RUBEDITIUM` carries `[SPECIAL]` twice.** Harmless, ported once.

**`NITRATED_DEEPCOKE` is not defined anywhere.** Only the two commented-out
reactions produce it, so nothing is broken. Mentioning it in case those
were meant to come back.

---

## Colours

Five of the ten metals use colours from
`descriptor_color_palette_arg.txt`: `AKIMRIL`, `GOBRONZE`, `ORICHALCUM`,
`MITHRIL` and `REDSTEEL`. Keep that file, as before.

The other five ask for `SAFFRON`, `PALE_BLUE`, `AQUAMARINE`, `RIVER_BLUE`
and `CERULEAN`, which are resolving against vanilla. Colours resolve by 
name at runtime and a miss is silent grey with no error anywhere, so 
`argmyth.lua` now checks all ten by name at load and prints any that are 
missing. If bismangaz bronze, cool silver, sea gold, igerkel or remangkel 
ever come out grey, that check will already have told you which name to add.

---

## This unit needs ArgMOD

Ten of the twelve reactions name ArgMOD materials directly: emenril,
iridium, aqua regia, salt of ammon, bone ash, flowers of beryl-alum and
three of the bronzes. It also needs your DRG minerals mod for cropparine,
umasteel and bismor bronze, and Elemental Metals Library for titanium and
magnesium.

That is declared in the JSON and RM resolves module load order from it. 
`argmyth.lua` also checks each of those mods at load and names any that 
are missing.