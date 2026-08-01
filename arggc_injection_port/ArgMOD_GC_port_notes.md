# ArgMOD Glass and Ceramics: Refinish Metal port

What I did, what I found, and what you might want to change.

---

## The short version

A large portion of glass, glaze and ceramics unit now runs through 
Refinish Metal's module system instead of loading from raws. It 
injects at map load and sweeps out on shutdown. Nothing touches 
worldgen or the save.

Injected: 51 materials, 950 reactions, 61 categories, 1144 permits.

Still in raws: all 26 clays, all 30 ceramics, the Compounder, and 13
reactions that redefine existing entries.

Prefix is `ARGGC_`.

---

## What had to stay in raws, and why

Injected content is invisible to worldgen, so anything worldgen needs
had to stay put. Three things pinned material to the raws:

**The clays.** `graphics_arg_clays.txt` names all 26 by id in
`BOULDER_GRAPHICS`, and three of them are SOIL layers besides.

**The ceramics.** `inorganic_clay_minerals_arg.txt` names all 30 with
`MATERIAL_REACTION_PRODUCT:FIRED_MAT`. If the ceramics moved, those
links would dangle. Clay and its fired counterpart have to stay
together.

**The Compounder.** Buildings cannot be injected at all. It stays,
along with its graphics and its three `PERMITTED_BUILDING` grants.

Plus 13 reactions that cut and redefine existing entries. The engine
only adds, it still can't edit existing entries.

---

## What the engine handles now

Most of the work for this port landed in the engine rather than the 
data, so it is worth knowing what is available if you ever want to 
move more across.

**Materials.** Six clone classes: METAL, STONE, GEM, CERAMIC, GLASS,
RAW. You give it flags, colours, value, density, thermal points,
strength, gem names, reaction classes and material reaction products;
it picks a structurally similar existing material and clones from
there. Material flags and inorganic flags are separate fields because
DF stores them in separate places.

**Reactions.** 31 reagent types and 14 product types. Everything this
unit needed is in there: `BOULDER_UNTYPED` for the untyped stone
selector, `BLOCKS_ANY`, `LARGE_POT`, `STATUE`, `ANY_CRAFT`, ash and
pearlash bars as both reagent and product, `CRAFTS` for the generic
craft output, and `IMPROVEMENT` for glazing, which is a different
product class entirely and clones its flag bits off a live donor. Sand
reagents (collect sand etc) are now working correctly with the engine
as well.

**Buildings and skills.** 13 buildings including your Compounder and
Chemist as custom workshops, and 27 skills including `GLAZING`.

**Categories.** Real trees, not flat lists. 31 of this module's 61 are
nested. Descriptions and hotkeys both work.

**Permissions.** Three modes per reaction. `ENTITY_CODE` names civs
explicitly, `AUTO` evaluates every civ against what it can actually
process, `NONE` pushes nothing. Each is gated on whether the civ has
the professions that operate the building, which is read from
`df.profession` directly. That gate is why the goblin ceramics problem
below is visible at all.

**Cross-module linking.** Modules declare `depends_on` and the engine
topologically sorts load order from it. References that point into a
module which has not loaded yet get deferred and resolved in a final
pass once everything is in, which is how `SALT_GLAZE` works across the
two units.

**Failure isolation.** Each module's materials, categories and
reactions inject independently. A fault in one stops that step and
names it in the log; the other modules still load. A module that fails
validation is rejected cleanly rather than taking the pipeline down.

### What it cannot do

- **Buildings.** Workshops have to stay in raws.
- **Worldgen.** Injected content is invisible to it.
- **Redefinition.** The engine only adds. Anything that cuts or
  overwrites an existing entry stays raw.
- **Builtin materials.** It will not clone from them, which is why the
  glasses clone a ceramic.
- **Graphics, creatures, plants, entities (reaction permissions can be 
injected).** Raws only.

---

## Dependency on ArgMOD core

Glass and Ceramics declares a dependency on the core module and RM
resolves load order from it. The actual link is `SALT_GLAZE`:
`SODIUM_CHLORIDE` and `POTASSIUM_CHLORIDE` in core both carry
`MATERIAL_REACTION_PRODUCT:GLAZE_MAT:INORGANIC:SALT_GLAZE`, and
`SALT_GLAZE` lives here.

Two references, one direction. Core loads first, this resolves against
it.

---

## Goblins cannot fire ceramics

This is the one thing worth acting on.

130 kiln reactions are permitted to EVIL and none of them can run.
Goblins have `MASON`, `STONECRAFTER`, `GLASSMAKER`, `WOODCRAFTER`,
`BONE_CARVER` and `WOOD_BURNER`. No `POTTER`, no `GLAZER`. DF gates
workshop operation on permitted professions, so the whole earthenware,
stoneware, porcelain and kiln-glazing range is dead for them.

If you want goblin ceramics, the fix is `[PERMITTED_JOB:POTTER]` on the
EVIL entity, not more reaction permits. If you did not, those 130
grants do nothing and can come out.

They do have `GLASSMAKER`, so the glass furnace side works for them.

This is hard to catch from inside a fort. You cannot watch goblins
across a world and check whether they are making pots.

---

## Permission spread, for reference

Every reaction carries `FORTRESS_MODE_ENABLED`, so the player has all
950 regardless. The permits below only govern which NPC civs produce
and trade them.

| Permits | Reactions |
|---|---|
All three civs | 157 |
MOUNTAIN only | 673 |
None | 120 |

The 120 with no grants are player-only. No NPC civ of any type will
produce them. That set is the `GOLD` and `TIN` glass families (36
each), all 34 `_BULK` variants, the three `MAKE_REDUCED_*_GLAZE`
reactions, and the complete feldspar glaze chain.

Listing it in case any of that was meant to show up in trade. Nothing
is broken either way.

---

## Source problems

`MAKE_RED_GOLDSTONE_BULK` is missing its closing bracket. The port
includes it so the reaction parses. Your parser may be tolerating it.

`RUBEDITIUM` carries `[SPECIAL]` twice. Harmless in itself, but it
looks like a copy-paste that could have doubled something else.

---

## Worldgen

53 reactions carried `WORLDGEN_ENABLED`, all Compounder recipes
producing clay boulders. Moving them into injection is what removed
worldgen from them, because injected content cannot participate in it
at all.

If you want those generating during worldgen, they need to go back
into raws.

---

## Glass materials

RM builds injected materials by cloning a structurally similar
existing one. Glass in DF is builtin rather than an inorganic, and RM
does not clone from builtin materials, so the 19 glass materials clone
`CERAMIC_EARTHENWARE` instead. It behaves correctly. Mentioning it
only so you know where to look if glass ever does something strange.

---

## Files

| File | |
|---|---|
`arggc_materials.json` | 51 materials |
`arggc_reactions.json` | 950 reactions, 61 categories, 1144 permits |
`arggc.lua` | module registration |
`inorganic_glass_glaze_arg.txt` | stripped, 1051 lines to 21 |
`reaction_glass_glaze_arg.txt` | stripped, 10044 to 151 |
`reaction_ceramics_arg.txt` | stripped, 3117 to 137 |
`entity_ggc_arg.txt` | stripped, 1211 to 12 |
`inorganic_clay_minerals_arg.txt` | unchanged |
`inorganic_ceramics_arg.txt` | unchanged |
