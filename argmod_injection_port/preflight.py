#!/usr/bin/env python3
"""
Preflight check for RM module JSONs.

Mirrors every rejection branch in refinish-module-validate.lua.

Type names AND their needs_mat_id / needs_metal_id requirements are
parsed straight out of refinish-module-types.lua rather than hardcoded.
An earlier version of this script hardcoded them, drifted from the
engine, and missed the needs_mat_id class of failure entirely.
"""
import json, re, sys, os

# These three files must sit in the same folder as this script:
#   refinish-module-types.lua   (from Refinish Metal)
#   argmod_materials.json
#   argmod_reactions.json
TYPES = 'refinish-module-types.lua'
MATS  = 'argmod_materials.json'
RXNS  = 'argmod_reactions.json'


# ---------------------------------------------------------------
# PARSE THE ENGINE'S TYPE TABLES
# ---------------------------------------------------------------
def load_engine_types(path):
    t = open(path, encoding='utf-8', errors='replace').read().replace('\r', '')

    def table_keys(name):
        m = re.search(r'^' + name + r' = \{(.*?)^\}', t, re.S | re.M)
        return set(re.findall(r'^    ([A-Z_0-9]+)\s*=', m.group(1), re.M)) if m else set()

    # Reagent types plus their mat_id / metal_id requirements
    reagents = {}
    m = re.search(r'^REAGENT_TYPES = \{(.*?)^\}', t, re.S | re.M)
    if m:
        for e in re.finditer(r'^    ([A-Z_0-9]+) = \{(.*?)^    \}', m.group(1), re.S | re.M):
            body = e.group(2)
            reagents[e.group(1)] = (
                bool(re.search(r'needs_mat_id\s*=\s*true', body)),
                bool(re.search(r'needs_metal_id\s*=\s*true', body)),
            )

    skills = set()
    sm = re.search(r'SKILL_MAP = \{(.*?)^\}', t, re.S | re.M)
    if sm:
        skills = set(re.findall(r'^\s+([A-Z_0-9]+)\s*=\s*\d+', sm.group(1), re.M))

    return {
        'reagents':  reagents,
        'products':  table_keys('PRODUCT_TYPES'),
        'classes':   table_keys('MATERIAL_CLASS_PRESETS'),
        'buildings': table_keys('BUILDING_TYPES'),
        'skills':    skills,
    }


for _f, _what in ((TYPES, 'the engine type table from Refinish Metal'),
                  (MATS, "this module's materials file"),
                  (RXNS, "this module's reactions file")):
    if not os.path.exists(_f):
        print(f"Can't find {_f}: {_what}.")
        print("All three need to be in the same folder as this script.")
        sys.exit(2)

E = load_engine_types(TYPES)
PERM_MODES = {'NONE', 'AUTO', 'ENTITY_CODE', 'ALL'}

errs = []
def err(m): errs.append(m)


# ---------------------------------------------------------------
# MODULE BLOCKS
# ---------------------------------------------------------------
for path in (MATS, RXNS):
    d = json.load(open(path))
    m = d.get('module')
    if not m:
        err(f"{os.path.basename(path)}: missing module block"); continue
    if not str(m.get('prefix', '')).endswith('_'):
        err(f"{os.path.basename(path)}: module.prefix must end in underscore")
    if not m.get('name'):    err(f"{os.path.basename(path)}: module.name required")
    if not m.get('version'): err(f"{os.path.basename(path)}: module.version required")


# ---------------------------------------------------------------
# MATERIALS
# ---------------------------------------------------------------
mats = json.load(open(MATS))['materials']
if not mats: err("materials array is empty")
seen = set()
for i, x in enumerate(mats):
    t = f"materials[{i}] ({x.get('key')})"
    k = x.get('key', '')
    if not k:          err(f"{t}.key missing")
    if ' ' in k:       err(f"{t}.key contains a space")
    if k != k.upper(): err(f"{t}.key not uppercase")
    if k in seen:      err(f"{t}.key duplicated")
    seen.add(k)
    if not x.get('name'): err(f"{t}.name missing")
    if x.get('material_class') not in E['classes']:
        err(f"{t}.material_class unrecognised: {x.get('material_class')!r}")
    if x.get('material_class') == 'GEM':
        g = x.get('gem_names')
        if not (isinstance(g, list) and len(g) == 2):
            err(f"{t}: GEM requires gem_names as exactly 2 strings")
    for j, p in enumerate(x.get('reaction_products') or []):
        if not p.get('id'):     err(f"{t}.reaction_products[{j}].id missing")
        if not p.get('mat_id'): err(f"{t}.reaction_products[{j}].mat_id missing")


# ---------------------------------------------------------------
# REACTIONS
# ---------------------------------------------------------------
doc = json.load(open(RXNS))
rxns, cats = doc['reactions'], doc.get('categories', [])
if not rxns: err("reactions array is empty")
seen = set()
for i, r in enumerate(rxns):
    t = f"reactions[{i}] ({r.get('key')})"
    k = r.get('key', '')
    if not k:     err(f"{t}.key missing")
    if k in seen: err(f"{t}.key duplicated")
    seen.add(k)
    if not r.get('name'): err(f"{t}.name missing")
    if r.get('building') not in E['buildings']:
        err(f"{t}.building unrecognised: {r.get('building')!r}")
    if r.get('skill') is not None and E['skills'] and r['skill'] not in E['skills']:
        err(f"{t}.skill unrecognised: {r['skill']!r}")
    if r.get('category') is not None and not isinstance(r['category'], str):
        err(f"{t}.category must be a string")

    perm = r.get('permissions') or {}
    mode = perm.get('mode')
    if mode is not None and mode not in PERM_MODES:
        err(f"{t}.permissions.mode unrecognised: {mode!r}")
    if mode == 'ENTITY_CODE' and not perm.get('entities'):
        err(f"{t}.permissions: ENTITY_CODE needs a non-empty entities array")
    if mode != 'ENTITY_CODE' and perm.get('entities'):
        err(f"{t}.permissions: entities set without ENTITY_CODE mode")

    # ---- reagents ----
    rgts = r.get('reagents') or []
    if not rgts: err(f"{t}.reagents must be non-empty")
    codes = set()
    for j, g in enumerate(rgts):
        rt = f"{t}.reagents[{j}] ({g.get('code')})"
        if not g.get('code'):      err(f"{rt}.code missing")
        if g.get('code') in codes: err(f"{rt}.code duplicated")
        codes.add(g.get('code'))

        ty = g.get('type')
        if ty not in E['reagents']:
            err(f"{rt}.type unrecognised: {ty!r}")
        else:
            need_mat, need_metal = E['reagents'][ty]
            if need_mat and not g.get('mat_id'):
                err(f"{rt}: type {ty!r} requires mat_id")
            if need_metal and not g.get('metal_id'):
                err(f"{rt}: type {ty!r} requires metal_id")
        if not isinstance(g.get('quantity'), int):
            err(f"{rt}.quantity must be a number")
    for j, g in enumerate(rgts):
        for f in ('contains', 'contains_in'):
            if g.get(f) and g[f] not in codes:
                err(f"{t}.reagents[{j}].{f} references unknown code {g[f]!r}")

    # ---- products ----
    prods = r.get('products') or []
    if not prods: err(f"{t}.products must be non-empty")
    for j, p in enumerate(prods):
        pt = f"{t}.products[{j}]"
        if p.get('type') not in E['products']:
            err(f"{pt}.type unrecognised: {p.get('type')!r}")
        ways = [p.get('mat_id') is not None,
                p.get('get_material_same') is not None,
                p.get('get_material_product') is not None]
        if sum(ways) == 0:
            err(f"{pt}: needs exactly one of mat_id/get_material_same/get_material_product")
        if sum(ways) > 1:
            err(f"{pt}: only one of mat_id/get_material_same/get_material_product allowed")
        gmp = p.get('get_material_product')
        if gmp is not None:
            if not isinstance(gmp, dict):
                err(f"{pt}.get_material_product must be a table")
            else:
                if not gmp.get('reagent_code'): err(f"{pt}.get_material_product.reagent_code missing")
                if not gmp.get('product_code'): err(f"{pt}.get_material_product.product_code missing")
                if gmp.get('reagent_code') and gmp['reagent_code'] not in codes:
                    err(f"{pt}.get_material_product.reagent_code unknown: {gmp['reagent_code']!r}")
        if p.get('get_material_same') and p['get_material_same'] not in codes:
            err(f"{pt}.get_material_same unknown code: {p['get_material_same']!r}")
        if p.get('to_container') and p['to_container'] not in codes:
            err(f"{pt}.to_container unknown code: {p['to_container']!r}")
        for f in ('count', 'dimension', 'probability'):
            if p.get(f) is not None and not isinstance(p[f], int):
                err(f"{pt}.{f} must be a number")


# ---------------------------------------------------------------
# CATEGORIES
# ---------------------------------------------------------------
seen = set()
for i, c in enumerate(cats):
    t = f"categories[{i}] ({c.get('key')})"
    if not c.get('key'):  err(f"{t}.key missing")
    if not c.get('name'): err(f"{t}.name missing")
    if not isinstance(c.get('parent', ''), str): err(f"{t}.parent must be a string")
    if c.get('key') in seen: err(f"{t}.key duplicated")
    seen.add(c.get('key'))


# ---------------------------------------------------------------
# REPORT
# ---------------------------------------------------------------
print(f"engine tables read from {os.path.basename(TYPES)}: "
      f"{len(E['reagents'])} reagent types, {len(E['products'])} product types, "
      f"{len(E['buildings'])} buildings, {len(E['skills'])} skills")
if errs:
    print(f"\nPREFLIGHT FAILED: {len(errs)} problem(s):\n")
    for e in errs[:40]: print("  " + e)
    if len(errs) > 40: print(f"  ... and {len(errs) - 40} more")
    sys.exit(1)
print(f"\nPREFLIGHT PASSED: {len(mats)} materials, {len(rxns)} reactions, {len(cats)} categories")
