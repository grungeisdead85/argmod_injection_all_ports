# Working with the injected half of ArgMOD

I've ported most of ArgMOD to run through Refinish Metal's module engine. This
explains what changed, what you can now do from JSON, and where the edges are.

You don't need to know Lua. Everything here happens in two files:

```
data/argmod_materials.json
data/argmod_reactions.json
```

---

## What Refinish Metal is, and what "injected" means

Refinish Metal is a DFHack mod. The part that matters to you is its **module
engine**: after a save loads, it writes materials and reactions directly into
DF's memory, the same C++ arrays the game filled from your raws a moment
earlier. The game can't tell the difference. An injected reaction shows up in
the workshop menu and runs like any other.

Before every save it pulls all of that back out again, so **nothing custom is
ever written to the save file**. What that definitely buys you: you can rewrite
the injected half completely, change materials, add reactions, restructure the
lot, and reload the same save with no migration and no regen. (Whether a save 
survives *uninstalling* the RM outright I've never tested; there's still an 
`info.txt` registration in play.)

The payoff is that injected content is **not part of worldgen**. You can add,
change or delete an injected material or reaction and it takes effect on the
next launch, on an existing save, with no regen. Raws can't do that. Change an
`[INORGANIC:]` in raws and every existing world keeps the old one.

The cost is that this ArgMOD port **requires Refinish Metal** for the injected 
half to appear. Without it, the raw half loads normally and the rest simply 
isn't there.

### How much you can add

More than you're used to budgeting for. Once content is injected it's outside
worldgen entirely, so the usual reason to be frugal with new inorganics doesn't
apply. Only inorganics added via raws will impact mineral diversity at worldgen,
and once that issue is circumvented there is no further bottleneck which I've 
discovered beyond hardware limitations and menu bloat which can be managed with
categories.

For scale: my own load order with every RM base metal active runs somewhere 
upwards of 100,000 materials and on the order of a million reactions and 
permissions. The only thing that grows with it is data-cycle latency: how long 
the engine takes to write everything in on load and pull it back out before a 
save. Worldgen is untouched. Data cycle latency and menu latency are the only
limits left to manage.

Your injected half is 68 materials and 202 reactions. That's a drop in the bucket
once you escape worldgen. You could add a lot more stuff and it would still be a
drop in the bucket. If you're also running RM on top with all base metals selected 
and you have tens of thousands of refinished variations of all your base metals, 
you'll have a lot of menu lag when clicking a magnifying glass which contains those 
inorganics. That being said, base metal selections are fully configurable in RM. 
You can even choose to leave all base metals unselected, at which point RM can 
operate as a module injection shell without ever building or loading its own 
refinishing assets at all.

The limit you *will* hit is the workshop menu: latency and clutter, because
every reaction is a real entry in a real list. That's what reaction categories
are for. There may be better answers to menu clutter later; for now, categories.

---

## The one rule that will break things

**Raws are parsed when the world loads. Injection happens afterwards.**

That gives references a direction:

| | Works? |
|---|---|
| Injected content → raw material | **Yes.** Resolved at runtime, always fine. |
| Raw file → injected material | **No.** The material doesn't exist yet. |

A raw file pointing at an injected material doesn't error. It fails quietly, and
the symptoms don't look like a missing material:

- an unresolved **reagent** material degrades to *"any material of that item
  type"*, so the reaction silently accepts the wrong ingredients
- an unresolved **product** material leaves `mat_index` at −1, which the game
  renders as **magma**
- an unresolved **graphics** binding drops the custom tile with no complaint

I hit all three during the port. If a reaction ever produces magma, this is why.

The practical consequence: **if any raw file mentions a material, that material
has to stay in raws.** That's why some of your metals are still in
`inorganic_metals_arg.txt` despite being perfectly good injection candidates.
`SLAG` and `WROUGHT_IRON` are named by raw reactions which can't be injected; 
the ferroalloys are named by `graphics_arg_ores.txt`.

---

## What lives where, and why

### Stayed in raws

| Content | Reason |
|---|---|
| Everything in `inorganic_all_minerals_arg.txt` | Spawns in the ground. Worldgen can't be injected. |
| `CHROMIUM`, `COBALT`, `MANGANESE` | You `CUT_INORGANIC` and redefine them. Replacing isn't adding. |
| The 21 reactions you `CUT_REACTION` and redefine | Same reason. |
| `MAKE_SOAP_FROM_TALLOW_SODA` | Uses a `GLOB` reagent, which the engine can't express yet. |
| `SLAG`, `WROUGHT_IRON`, `ANTIMONY`, `COPPER_OXIDE`, `SODIUM_HYDROXIDE` | Named by those 21 raw reactions. |
| 10 ferroalloys and `MOLYBDENUM` | Named by `graphics_arg_ores.txt`. |
| 11 oxides and sulfates | Named by `MATERIAL_REACTION_PRODUCT` in the minerals file. |
| `building_arg_chemist.txt` | Buildings can't be injected *yet*. The engine locates yours by name instead. |
| `descriptor_color_palette_arg.txt` | Colours resolve by name at runtime. Keep this file; without it every custom metal falls back to grey, silently. |
| Your `SELECT_INORGANIC` edits to vanilla metals | Editing existing materials, not adding new ones. |

### Injected

Everything else: 29 alloys, 39 chemical powders and liquids, 202 reactions
across the smelter, chemist, mill, kiln, ashery and soap maker, 20 reaction
categories, and the entity permissions.

`FORTRESS_MODE_ENABLED` is carried on all 201 reactions that had it.
`WORLDGEN_ENABLED` on two reactions is not, and can't be, since worldgen has finished
before injection happens.

---

## Where the definition now lives

For anything injected, **the JSON is the definition.** I deleted those
`[REACTION:...]` and `[INORGANIC:...]` blocks from your raw files, so editing
the raws for that content does nothing; there's nothing left there to edit.

For anything still in raws, the raws remain the definition. The JSON can still
*reference* those materials freely. That's the whole point of the direction
rule above, and injected reactions do it constantly (`SLAG`, `WROUGHT_IRON` and
every vanilla metal are named from JSON). What the JSON doesn't do is redefine
them.

Nothing is defined in both places. If you're unsure which half something lives
in, search the JSON for its id first.

---

## Adding a material

Each entry in `argmod_materials.json` is one `[INORGANIC:...]`. The `key` is the
id **without** the `ARGMOD_` prefix. The engine adds that, so `DAMASCUS_STEEL`
becomes `ARGMOD_DAMASCUS_STEEL` in game.

**The prefix isn't cosmetic.** It's the only way the engine can tell its own
objects apart from the game's. Everything injected has to be found again and
removed before every save, restored after, and matched back up to items in your
fort across those cycles. That all keys off the prefix. Don't set it to
something another module might use, and don't write pre-prefixed ids into `key`
or you'd get `ARGMOD_ARGMOD_X` and the engine would lose track of it.

```json
{
  "key": "DAMASCUS_STEEL",
  "name": "damasklilar steel",
  "material_class": "METAL",
  "color": "DAMASCUS",
  "liquid_color": "RED",
  "gas_color": "RED",
  "value": 30,
  "solid_density": 7850,
  "liquid_density": 6980,
  "molar_mass": 55845,
  "heat": {
    "spec_heat": 500, "melting_point": 12718,
    "boiling_point": 14968, "ignite_point": null
  },
  "strength": {
    "yield":           { "IMPACT": 2590000, "COMPRESSIVE": 888000, "TENSILE": 740000,
                         "TORSION": 427239, "SHEAR": 427239, "BENDING": 740000 },
    "fracture":        { "IMPACT": 3745000, "COMPRESSIVE": 1284000, "TENSILE": 1070000,
                         "TORSION": 617765, "SHEAR": 617765, "BENDING": 1070000 },
    "strain_at_yield": { "IMPACT": 1551, "COMPRESSIVE": 532, "TENSILE": 370,
                         "TORSION": 555, "SHEAR": 555, "BENDING": 370 },
    "max_edge": 10384
  },
  "reaction_classes": [],
  "reaction_products": [],
  "material_flags": {
    "ITEMS_METAL": true, "ITEMS_HARD": true, "ITEMS_BARRED": true,
    "ITEMS_SCALED": true, "ITEMS_WEAPON": true, "ITEMS_WEAPON_RANGED": true,
    "ITEMS_AMMO": true, "ITEMS_DIGGER": true, "ITEMS_ARMOR": true,
    "ITEMS_ANVIL": true
  },
  "display_color": [0, 7, 1],
  "build_color": [0, 7, 1]
}
```

Against the tokens you already know:

| JSON | Raw equivalent | Notes |
|---|---|---|
| `key` | `[INORGANIC:X]` | Prefix added for you. |
| `name` | `[STATE_NAME_ADJ:ALL_SOLID:x]` | Liquid and gas become "molten x" / "boiling x" automatically. |
| `names` | the other `STATE_NAME_ADJ` lines | Optional: `{solid, liquid, gas, powder, paste, pressed}`. Needed whenever the automatic form would read wrong. An acid whose solid name is "frozen oil of vitriol" must not become "molten frozen oil of vitriol". All 39 of your chemicals use this. |
| `material_class` | `USE_MATERIAL_TEMPLATE` | `METAL`, `STONE`, `CERAMIC`, `GEM`, `GLASS`, `RAW`. Not a one-to-one mapping; see below. |
| `color` | `[STATE_COLOR:ALL_SOLID:X]` | A descriptor name. Your custom palette resolves fine. |
| `liquid_color`, `gas_color` | `[STATE_COLOR:LIQUID:X]` | Metals want `RED` (that's what `METAL_TEMPLATE` gives them). Omit to reuse `color`. |
| `display_color`, `build_color` | `[DISPLAY_COLOR:f:b:r]` | ANSI triples, 0-7. **A different number space from `color`**: one is a descriptor index, the other is a terminal colour. Don't cross them. |
| `tile` | `[TILE:n]` | Character code. |
| `value` | `[MATERIAL_VALUE:n]` | |
| `heat.*` | `[SPEC_HEAT]`, `[MELTING_POINT]`, … | |
| `strength.*` | `[IMPACT_YIELD]` and friends | Six axes each for yield, fracture and strain. |
| `reaction_classes` | `[REACTION_CLASS:X]` | |
| `reaction_products` | `[MATERIAL_REACTION_PRODUCT:ID:INORGANIC:X]` | `[{ "id": "...", "mat_id": "..." }]` |
| `material_flags` | `[ITEMS_METAL]` and friends | **Read the next section.** |

### Colour priority, and Caldfir's Metallic

`color` and `fallback_colors` are a priority chain. The engine tries `color`
first, then each entry in `fallback_colors` in order, and takes the first one
that resolves against the colour descriptors loaded in the game.

That gives you soft Metallic support with no detection and no configuration.
Name the Metallic colour first and your own as the fallback:

```json
"color": "METALLIC_STEEL",
"fallback_colors": ["EMENRIL","BLUE-GRAY"]
```

With Metallic loaded, the material comes out `METALLIC_STEEL`. Without it, that
name doesn't resolve, the chain falls through, and it comes out `EMENRIL`. If
that fails too for some reason, it next becomes `BLUE-GRAY`. The same JSON works 
either way, and a player who adds or removes Metallic later just gets the next 
colour in priority on next load. You can chain as many as you like.

**End the chain with something that definitely exists.** If nothing in it
resolves you get an arbitrary default rather than an error, which is a
frustrating thing to debug. A vanilla colour as the last entry costs nothing.

**This works with Metallic, and I checked.** Its `descriptor_color_1metallic.txt`
and `descriptor_color_2divine.txt` are `[OBJECT:DESCRIPTOR_COLOR]` files, so all
52 `METALLIC_*` names are real colour descriptors and the chain resolves them
exactly like your own palette. No caveat.

**Nothing was pre-loaded, because nothing could be.** All 16 of your
`METALLIC_*` recommendations sit on minerals or `WROUGHT_IRON`, and every one of
them stayed in raws, and the fallback chain only exists for injected materials.
Those stay manual `[STATE_COLOR:...]` edits, the way you have them now.

None of your 29 injected alloys currently uses a Metallic colour, so the chain
is available and completely unused. If you'd like `DAMASCUS_STEEL` to match 
Metallic's steel when it's loaded, that's `"color": "METALLIC_STEEL"` with
`"fallback_colors": ["DAMASCUS"]` and nothing else.

**One live collision.** You and Metallic both recolour `PIG_IRON`:
`DARKSTEEL` against `METALLIC_PIG_IRON`. Both are raw `SELECT_INORGANIC` edits,
so whichever loads last wins, and neither of you can do anything about it from
within your own mod. It's the only overlap; Metallic recolours 32 vanilla
materials and you touch 7, and `PIG_IRON` is the single intersection.

**This is the clearest argument for the editing engine.** Your Metallic
recommendations are manual comments precisely because those materials are raw
edits, and the engine can only add. Once it can edit existing materials, those
`SELECT_INORGANIC` recolours could become injected edits carrying a fallback
chain, and Metallic compatibility would just happen, on both sides, with no
comments to action and no load-order coin flip on `PIG_IRON`.

### Two places DF habits will mislead you

**`material_class` is not `USE_MATERIAL_TEMPLATE`.** A template gives you a set
of defaults you then override. A class here applies a *preset*, and `METAL`
turns on the entire capability set: weapons, armour, ammo, anvil, all of it.

Your metals aren't uniform. Of the 46 you wrote, only 22 grant weapons and 9
grant anvil, and the ferroalloys grant nothing at all. So **every material lists
every flag explicitly, `true` or `false`.** Leaving one out doesn't withhold it
the way omitting a token would: the preset grants it. Add a new ferroalloy
without the flag block and it'll come out forgeable into armour.

**There's no inheritance.** Whatever a template would have given you (spec
heat, densities, the whole strength block) has to be written out. The engine
clones a donor material to get a valid structure, then blanks everything
meaningful. If you leave a field out you get that donor value, either a wiped
value or worse yet a cloned value which survived the wipe. The effect of this 
would depend on what object RM evaluated to be the best match on load, not on 
a value derived from any meaningful template.

---

## Adding a reaction

One entry per `[REACTION:...]`.

```json
{
  "key": "GRIND_SALTPETER",
  "name": "grind niter into potash saltpeter",
  "building": "MILL",
  "skill": "MILLING",
  "fuel": false,
  "category": "ARGMOD_CAT_MILL_MINERAL_REAGENT",
  "permissions": { "mode": "ENTITY_CODE", "entities": ["MOUNTAIN"] },
  "reaction_flags": { "fortress_mode": true },
  "reagents": [
    { "code": "A",   "type": "BOULDER", "quantity": 1, "mat_id": "SALTPETER" },
    { "code": "bag", "type": "BAG",     "quantity": 1,
      "flags": { "empty": true, "preserve": true,
                 "does_not_determine_product_amount": true } }
  ],
  "products": [
    { "type": "POWDER_MISC", "mat_id": "ARGMOD_POTASSIUM_NITRATE",
      "count": 4, "dimension": 150, "to_container": "bag" }
  ]
}
```

`code` is the reagent name you'd write in raws, and `contains`, `to_container`
and `get_material_product` refer back to it. **Codes must be unique within a
reaction.** DF tolerates duplicates when nothing references them; the RM engine
doesn't, because it resolves those links by name.

`mat_id` takes a full id: `ARGMOD_` prefix for injected materials, bare id for
vanilla or raw ones. `ARGMOD_POTASSIUM_NITRATE` but plain `SALTPETER`.

### Reagent types

Rather than writing item and material tokens, you pick a type. The engine fills
in the item type, material type and index behind it.

| Type | Equivalent raw reagent | Needs |
|---|---|---|
| `METAL_BAR` | `BAR:NO_SUBTYPE:METAL:X` | `mat_id` |
| `BAR_ANY` | `BAR:NONE:NONE:NONE` | |
| `BAR_POTASH` | `BAR:NONE:POTASH:NONE` | |
| `COAL` | `BAR:NO_SUBTYPE:COAL:NO_MATGLOSS` | |
| `BOULDER` | `BOULDER:NO_SUBTYPE:INORGANIC:X` | `mat_id` |
| `BOULDER_ANY` | `BOULDER:NONE:NONE:NONE` | |
| `ORE_OF` | boulder carrying `[METAL_ORE:X]` | `metal_id` |
| `FLUX` | flux stone | |
| `POWDER` | `POWDER_MISC:NONE:INORGANIC:X` | `mat_id` optional |
| `POWDER_ANY` | `POWDER_MISC:NONE:INORGANIC:NONE` | |
| `LIQUID` | `LIQUID_MISC:NONE:NONE:NONE` | |
| `LIQUID_INORGANIC` | `LIQUID_MISC:NONE:INORGANIC:X` | `mat_id` |
| `LIQUID_INORGANIC_ANY` | `LIQUID_MISC:NONE:INORGANIC:NONE` | |
| `WATER` | `LIQUID_MISC:NONE:WATER:NONE` | |
| `ROUGH` / `ROUGH_ANY` | `ROUGH:NONE:INORGANIC:X` / `:NONE` | `mat_id` for the first |
| `BLOCKS` | `BLOCKS:NONE:INORGANIC:X` | `mat_id` |
| `ROCK` | small rock | |
| `BAG`, `BUCKET`, `BARREL`, `JUG` | the matching container | |
| `CONTAINER` | `NONE:NONE:NONE:NONE` | Use with `contains`. |
| `BODY_PART` | untyped + `[USE_BODY_COMPONENT]` | Pair with `bone` / `shell` / `horn` flags. |

**`INORGANIC:NONE`** In the raws it's shorthand for "any inorganic of this item type, 
narrowed by `REACTION_CLASS`", used in ArgMOD 36 times. It maps to the `_ANY` variant 
of the desired type in the module engine. Using the strict type with no `mat_id` is 
rejected rather than treated as a wildcard, because that ambiguity is how a reagent 
silently becomes "anything at all".

### Reagent flags

`reaction_class`, `has_material_reaction_product` and `metal_id` sit directly on
the reagent. Everything else goes in a `flags` object:

`preserve`, `empty`, `does_not_determine_product_amount`, `in_container`,
`unrotten`, `glass_material`, `sand_bearing`, `body_part`, `bone`, `shell`,
`horn`, `fire_safe`, `magma_safe`, `non_economic`, `building_material`,
`allow_melt_dump`.

One has no raw equivalent: **`in_container`**. DF sets this for you when it sees
another reagent's `[CONTAINS:]` during parsing. Nothing parses the JSON that
way, so you write it yourself: every powder that lives in a bag needs
`"in_container": true`, and the bag needs `"contains": "<that code>"`. Miss it
and the reaction won't find its reagent.

### Product types

| Type | Equivalent |
|---|---|
| `BAR` | `BAR:NO_SUBTYPE:METAL:X` |
| `BAR_COAL` | `BAR:NO_SUBTYPE:COAL:COKE` |
| `BAR_POTASH` | `BAR:NONE:POTASH:NONE` |
| `POWDER_MISC` | `POWDER_MISC:NONE:INORGANIC:X` |
| `LIQUID_MISC` | water |
| `LIQUID_MISC_INORGANIC` | an acid or other inorganic liquid |
| `BOULDER`, `BLOCKS`, `ROUGH`, `ROCK` | as named |

Every product names its material exactly one way: `mat_id`,
`get_material_same` (a reagent code), or `get_material_product`
(`{ "reagent_code": "...", "product_code": "..." }`, your
`GET_MATERIAL_FROM_REAGENT`). For builtins, name the builtin:
`"mat_id": "POTASH"`, `"mat_id": "COKE"`. It won't resolve as an inorganic, and
that's fine; the material type comes from the product type itself.

`count`, `dimension`, `probability` and `to_container` mean what you'd expect.

### Buildings and skills

Buildings: `SMELTER`, `KILN`, `MILL`, `ASHERY`, `SOAP_MAKER`, `CHEMIST`,
`FORGE`, `MASON`, `CRAFTSMAN`, `JEWELER`, `GLASS_FURNACE`, `NONE`.

`MILL` is quern **and** millstone in one entry, since you list both on all 41 of
your grinding reactions. I'll might break this up in future updates.

`CHEMIST` works because the engine looks your workshop up by its code string at
runtime; the building itself stays in raws. If you add a second custom
workshop, it needs a one-line table entry on the engine side before reactions
can point at it.

Skills are the usual names: `SMELT`, `MILLING`, `POTASH_MAKING`, `LYE_MAKING`,
`SOAP_MAKING`, `MASONRY`, and so on.

### Permissions and `fortress_mode`

These are two separate switches that both sound like "can this be used". Setting
one doesn't change the other.

**`reaction_flags.fortress_mode`** is a flag on the reaction itself, the direct
equivalent of `[FORTRESS_MODE_ENABLED]`. It's what makes the reaction usable in
fortress mode at all. **Leave it `true` on anything you want players to use.**
All 201 of your reactions that had the token still have it.

```json
"reaction_flags": { "fortress_mode": true }
```

**`permissions`** replaces `[PERMITTED_REACTION:...]` in the entity file. It
controls which civilisations the engine grants the reaction to. Four modes:

| `mode` | What the engine does |
|---|---|
| `"ENTITY_CODE"` | Grants it to the entity raws you list. Needs an `entities` array. This is the direct translation of your entity file. |
| `"NONE"` | Grants it to nobody. |
| `"ALL"` | Grants it to every civilisation. |
| `"AUTO"` | Decides per civilisation from their capabilities, e.g. only civs that can work metal get smelter reactions. |

```json
"permissions": { "mode": "ENTITY_CODE", "entities": ["MOUNTAIN", "PLAINS", "EVIL"] }
"permissions": { "mode": "NONE" }
```

**If you only care that it works in your fort:** set `fortress_mode` true and
you're done. `"mode": "NONE"` is a perfectly valid setting and is what 74 of
your reactions currently have, including the ore-weathering grinds and
`PURPLE_GOLD_MAKING`, all of which work fine in a fort. A reaction with
`fortress_mode` true and `"mode": "NONE"` is not misconfigured.

**If you care what other civilisations do with it,** that's what `permissions`
is for, and here the ground gets less certain, so I'd rather flag it than let
you build on it:

- Permits *appear* to apply to every civ of an entity type rather than just the
  player's. `[PERMITTED_REACTION:...]` sits on the entity raw, and `MOUNTAIN` is
  one shared definition every mountain civilisation points at, so there's no
  per-civ granularity to grant even in principle. I spent a long time on this
  and landed on "it must be all mountain civs", but I never proved it.
- Whether this remains true on `fortress_mode` alone and NPC civs then *act* on 
  it (produce these items, bring them to trade) is something I haven't yet 
  confirmed firsthand.

Your content splits roughly in half here: 128 reactions carry entity permits and
74 don't, following when things were written rather than any design line. Since
`fortress_mode` covers your own fort either way, that inconsistency has probably
never been visible in play.

### Categories

Your 20 injected categories sit at the bottom of the reactions file with a bare
`key`. A reaction refers to one as `ARGMOD_CAT_<key>`.

Six categories are shared with reactions that stayed raw: `COKING`,
`IRONWORKING`, `STEELMAKING`, `LIME_CALCINATION`, `NONFERROUS_ALLOYING` and
`PRECIOUS_METAL_ALLOYING`. Injected reactions in those six use the **bare raw
id** with no prefix, so both halves land in the same workshop submenu instead of
two identically-named ones.

I also re-declared `[CATEGORY_NAME:Coking]` and `[CATEGORY_NAME:Ironworking]` in
your raws. Both names were originally declared on reactions that are now
injected, so removing those reactions took the display name with them.

---

## Checking your work before you launch

`preflight.py` reads both JSON files and checks them against every rule the
engine enforces, printing exactly what's wrong and where. It reads the engine's
own type tables rather than a copy, so it can't drift out of date as the engine
gains types.

A pass means the module will load. It won't catch design mistakes (a reaction
nothing can reach, or a material nothing produces), but it catches every
structural error, and it's a second rather than a DF launch.

### Running it

It's a Python script, and Windows doesn't ship with Python. If you already have
it, skip to the file list.

**Getting Python.** Download it from
[python.org/downloads](https://www.python.org/downloads/) and run the installer.
The only thing that matters is ticking **"Add python.exe to PATH"** on the first
screen. It's off by default and it's the reason the command below wouldn't
otherwise work. Everything else can stay at its defaults. You don't need to
touch PowerShell's execution policy; that applies to `.ps1` scripts, not this.

**Put four files in one folder**, anywhere, it doesn't have to be near the mod:

```
preflight.py
argmod_materials.json
argmod_reactions.json
refinish-module-types.lua
```

The last one comes from the Refinish Metal install and is how the script knows
what the engine currently accepts. **Take a fresh copy whenever RM updates**, or
you'll get failures for reagent types that do actually exist. The script is
only ever as current as that file.

**Run it.** In that folder, hold Shift and right-click on empty space → *Open
PowerShell window here*. (Or click the folder's address bar, type `cmd`, and
press Enter.) Then:

```
python preflight.py
```

**Reading the output.** A pass looks like this:

```
engine tables read from refinish-module-types.lua: 24 reagent types, 10 product types, 12 buildings, 25 skills

PREFLIGHT PASSED: 68 materials, 202 reactions, 20 categories
```

A failure names the reaction, the reagent and the problem, so you can go
straight to it:

```
PREFLIGHT FAILED: 1 problem(s):

  reactions[66] (PITCHBLENDE_REDUCTION).reagents[3] (caustic): type 'LIQUID_INORGANIC' requires mat_id
```

If it says `python` isn't recognised as a command, the PATH box didn't get
ticked. Either rerun the installer and choose *Modify*, or try `py preflight.py`
instead, which usually works regardless.

### One thing to be aware of on the chemistry side

The engine picks a donor material and a template reaction for everything it
injects by scoring candidates from the loaded game. That scoring was built
around metals and dusts, which is what the mod originally did, and it shows: for
your chemicals and chemist reactions the winning scores are low. The RAW-class
donor scores a 3; the chemist reactions land on things like `PRESS_OIL` and
`ACACIA_BARK_DYE` in the 50-70 range, against 85 for a typical smelter reaction.

Everything I've tested from that side behaves correctly, so low scores aren't
evidence of a problem unless you notice things aren't behaving as intended. 
I don't yet know whether the scoring is simply weak for this kind of content, 
or whether vanilla genuinely has nothing that's a close structural match for a 
chemist reaction. If something in the chemistry behaves oddly in a way that isn't 
a reagent problem, tell me. That's the first place I'd look, and it's my end to 
fix rather than yours.

---

## What needs engine changes

These aren't things you can do from JSON, so RM updates would be required before
designing around them:

- **New reagent or product types.** The tables above are the whole vocabulary.
  `GLOB`, plant and creature materials, tools other than jugs. Each needs a new
  entry.
- **New buildings.** Vanilla ones are a table entry. A second custom workshop of
  yours works the same way the chemist does, but still needs that entry.
  Injecting buildings outright is probably possible; I just haven't had reason
  to build it without encountering a building bottleneck.
- **Material properties not listed.** `absorption` isn't exposed, for instance.
- **Graphics.** Bindings are parsed from raws and name materials directly, so an
  injected material can't carry a custom tile. That's the only reason the
  ferroalloys stayed behind.
- **Editing or removing existing content.** The engine only *adds*. Anything you
  `CUT` or `SELECT` has to stay in raws. This is the big one; see the last
  section.

---

## Bugs I found while porting

**I ported every one of these exactly as written.** The goal was a faithful
port: the injected half behaves identically to your mod as it stands today, bugs
included. I didn't silently improve anything, because a port that quietly
changes behaviour is worse than one that doesn't, because you'd have no way to tell
which differences were deliberate.

These are only things that appear to be **mechanically** broken. I've avoided
treating things as bugs because there may be elements of design choice, but I
wanted to point these ones out just in case you don't know:

### 1. `FERROTUNGSTEN_MAKING` names both reagents `A`

DF tolerates it because nothing in that reaction refers to a code, but it's a
latent trap: the moment you add a `CONTAINS` or `PRODUCT_TO_CONTAINER` there it
breaks. The RM engine requires unique codes, so during the port the second one 
became `A2`.

**Fix in `argmod_reactions.json`:** change that reagent's `"code": "A2"` to
`"code": "B"`, or whatever element you choose.

### 2. `SALT_GLAZE` is referenced but not present

`SODIUM_CHLORIDE` and `POTASSIUM_CHLORIDE` both declare a `GLAZE_MAT` reaction
product pointing at `SALT_GLAZE`, and it isn't currently in the core mod. My 
guess is it went with the glass and ceramics content when you split that off, 
and since the missing element breaks nothing it's just a compromise to reduce
raw footprint if someone chooses not to install Glass & Ceramics.

Flagging it in case it's news. **If you want it back, fix in
`argmod_materials.json`** since both those materials are injected: add
`SALT_GLAZE` as an injected material and point at `ARGMOD_SALT_GLAZE`, or drop
the two `reaction_products` entries to stop pointing at a ghost.

Worth saying: If you like how this port works, I'd be glad to port the remaining
offshoots. If the footprint can be reduced enough you might even be able to run
the whole suite with less impact than the core mod in raw format. That's my goal
anyway.

### 3. Seven acids have a malformed `[STATE_COLOR:CLEAR]`

`AMMONIA_SOLUTION`, `SODIUM_HYDROXIDE`, `SULFURIC_ACID`, `NITRIC_ACID`,
`HYDROCHLORIC_ACID`, `HYDROFLUORIC_ACID` and `AQUA_REGIA` are all missing the
state selector, which DF shouldn't be able to parse. I'd expect that means your
intended ivory, cream and vermilion never took effect and those materials have
been falling back to the template's `CLEAR`, but I didn't verify that in game,
so treat it as likely rather than established. The port carries `CLEAR` either
way, matching the token as written.

**Fix in `argmod_materials.json`**, and it's easier than it was in raws, because
JSON has no malformed-token failure mode, so there's no selector to forget:

```json
"color": "IVORY"
```

---

## Reducing your raw footprint

68 of your 98 non-spawning materials are injected. The other 30 are held back,
each for a specific structural reason:

| Held | Why | Recoverable? |
|---|---|---|
| 11 | `MATERIAL_REACTION_PRODUCT` in the minerals file names them | with a tradeoff |
| 11 | graphics files bind tiles to them | not until the engine can inject graphics |
| 5 | the 21 cut-and-redefined reactions name them | **only at real risk**, read below |
| 3 | they're cut-and-redefined themselves | needs the library sorted out |

I want to be straight about all four, including the two where my first instinct
was wrong.

### Cut-and-replace: don't change this yet

My initial idea was that you cut vanilla reactions without redefining them
and inject your replacements instead, freeing five materials and moving 21
reactions into the editable half. Having thought about it properly, **I don't
think you should**, at least not now.

**Why you probably cut-and-replace in the first place.** I imagine it's to
inherit the vanilla reaction's behaviour so it lands in the right workshop and
carries whatever internal state makes it act like a real reaction. It's worth 
knowing the engine addresses this differently: an injected reaction clones a 
structurally similar vanilla reaction as a template (matched on building type, 
subtype, fuel flag, reagent count) and then overwrites its identity and contents. 
So it gets genuine vanilla internals rather than a synthesized shell. Nothing is 
hardcoded. Every injected reaction is scored against the available vanilla ones 
and takes the best match. `STEEL_MAKING2` currently scores `BRASS_MAKING` highest; 
the ore reductions land on `BITUMINOUS_COAL_TO_COKE`. Change a reaction's shape 
and it may well pick a different template next load.

**But I haven't tested that specific migration.** I don't know first-hand that
cutting `STEEL_MAKING` and injecting a replacement cloned from `BRONZE_MAKING`
gives identical results. I can't see why it wouldn't. This game does unintuitive
things that break everything in the most infuriating ways, so best to approach
with caution.

**And the load-order problem is serious.** If you cut `STEEL_MAKING` and your
replacement becomes `ARGMOD_STEEL_MAKING`, every other mod that references
`STEEL_MAKING` stops resolving. That's not a footnote. It's your mod silently
breaking in other people's load orders, and then you're stuck writing 
compatibility patches for all of them. That risk alone outweighs five raw entries.

**There's also a template-supply issue.** The engine builds injected reactions
by grading and cloning vanilla ones. If you cut many smelter reactions and
replace them all with injected versions, you can starve the engine of clone 
sources. If you ever do go down this road, leave a healthy set of vanilla 
reactions of each shape intact.

**The real fix is on my end.** The engine only adds; it can't edit. When it can, by 
redefining an existing reaction in place rather than adding a new one, this
problem disappears. You'd keep `STEEL_MAKING` under its own id, other mods keep
resolving, and the definition still lives in JSON. That's now high on my
priority list precisely because of this. Until then, cut-and-replace is still the
right call and I'd leave it alone.

### `MATERIAL_REACTION_PRODUCT` versus reaction classes

This one's a genuine tradeoff.

> A **`REACTION_CLASS`** on a mineral is just a string tag. It names no
> material, so it creates no dependency, and an injected reaction can filter on
> it freely.
>
> A **`MATERIAL_REACTION_PRODUCT`** on a mineral names a specific material. That
> is a hard reference, and it forces the target to stay in raws.

Your sulfide chain uses both patterns for the same job. The per-metal reactions
filter on `REACTION_CLASS:NICKEL_SULFIDE` and name their product directly.
Those are fully injected and cost nothing. The generic `_ANY_SULFIDE_ORE`
variants derive their product through `MATERIAL_REACTION_PRODUCT`, and that
single choice is what pins all 11 oxides and sulfates into raws.

Dropping those lines and relying on the per-metal reactions would free all 11,
but at the cost of the generic reaction, which is genuinely more elegant.

There may be a way for the engine to handle generic-reagent reactions like this 
without the raw-side dependency. It's not solved, and I don't want to promise a 
shape for it, but it's on the list. If the generic reactions matter to you, 
leaving this as-is for now will work fine.

### Graphics

Eleven materials stay in raws purely so their bar tiles resolve. Graphics
bindings are parsed from raws and name materials directly, and there's no way
around that until the engine can inject graphics. Possible, but a new
subsystem rather than a tweak. No action on your side.

### `CHROMIUM`, `COBALT`, `MANGANESE`

These come from Elemental Metals Library, which you cut and redefine. Freeing
them means dealing with the library itself, either porting it for injection or
absorbing the relevant definitions into the ArgMOD port's JSON.

That's a bigger conversation than this port, and it has the same load-order
hazard as above: the library exists to be depended on via raws, so converting it
would break anything else that depends on it.

### If you were starting from scratch

- **Anything that spawns in the ground stays raw.** Not negotiable.
- **Tag minerals with reaction classes rather than pointing them at materials.**
- **Add new content by injection; keep cuts and edits in raws**, until the
  engine can edit, at which point most of this gets simpler.
- **Keep custom graphics for materials that were always going to be raw anyway.**

The split will feel like something to work around at first, because ArgMOD
wasn't written with it in mind and the line falls in some odd places as a
result. Most of the awkwardness can be designed away, but not all of it, and 
some of it is waiting on me rather than you and will improve as I continue to 
develop RM.
