--@ module = true
-- ==========================================
-- RM MODULE: ArgMOD Mythical
-- ==========================================
-- Registers the mythical metals unit with Refinish Metal's module
-- engine. RM injects it into RAM at startup and sweeps it back out
-- on shutdown, so none of it touches worldgen or the save.
--
-- WHAT THIS MODULE INJECTS:
--   10 materials  - alloys and fantasy metals
--   12 reactions  - all smelter
--   0 categories  - every category used already exists
--   10 entity permits across MOUNTAIN, PLAINS and EVIL
--
-- WHAT STAYS IN RAWS (and must remain installed):
--   - All ground-spawning minerals. Worldgen cannot be injected.
--   - UMANITIUM, DYSTRUM, BLURIUM, RUBEDITIUM. Their ores name them
--     with METAL_ORE, and a raw file naming an injected material is
--     the one thing that cannot work. See DEPENDENCY DIRECTION below.
--   - BISMOR, the three SELECT_INORGANIC edits, BISMOR_BRONZE_MAKING
--     and NITRA_TO_COKE. The engine only adds, it does not edit or cut.
--   - The graphics bindings and the descriptor colour file.
--
-- ==========================================
-- DEPENDENCY DIRECTION
-- ==========================================
-- Raws are parsed when the world loads. Injection happens afterwards.
-- So an injected thing may name a raw thing, but never the reverse:
-- a raw file naming an injected material fails silently, and an
-- unresolved product renders as magma.
--
-- The same direction rule applies between modules. RM injects one
-- whole module at a time, and reaction building resolves material IDs
-- against the array as it stands at that moment, so a module can only
-- name materials from raws, from itself, or from a module already
-- injected.
--
-- This module names ArgMOD core materials (ARGMOD_EMENRIL and others),
-- so ArgMOD core has to go first. That is declared, not inferred:
-- both JSON files carry
--
--     "depends_on": ["ARGMOD_"]
--
-- in their module block, and RM orders injection from it. If ArgMOD is
-- not installed, RM skips this module entirely rather than injecting
-- reactions whose products cannot resolve.
--
-- RENAMING THIS PREFIX:
-- Injection order no longer depends on how prefixes sort, so the name
-- is free in that respect. It is NOT free in one other: a prefix must
-- not be a stem of another module's prefix, nor have one as its stem.
-- ARGMOD_MYTH_ would be wrong. Every asset sweep in RM selects by
-- prefix, so ARGMOD_ also selects ARGMOD_MYTH_ORICHALCUM, and ArgMOD's
-- shutdown would clear this module's materials. Anchoring the match
-- does not help, because a stem really does sit at the start of the
-- string. RM rejects an overlapping prefix at registration and says
-- so, but pick one that is clearly its own word to begin with.
--
-- Reaction categories are exempt from all of this. RM writes the
-- category as a plain string and DF matches it by name when it builds
-- the workshop menu, so ARGMOD_CAT_IRIDIUM_FROM_PGM carries no
-- ordering requirement at all.
--
-- REQUIREMENTS:
--   - Refinish Metal installed and active.
--   - ArgMOD (both halves) installed and active.
--   - The DRG minerals mod installed and active.
--   - argmyth_materials.json and argmyth_reactions.json in data/.
-- ==========================================

local scriptmanager = require('script-manager')


-- ==========================================
-- CONFIGURATION
-- ==========================================

-- MUST match the [ID:...] line in this mod's info.txt. If it is
-- wrong, getModSourcePath returns nil and the module cannot find its
-- own data folder. The registration step below reports that clearly
-- rather than failing silently.
local MODULE_ID = "argmod_mythical_materials_injected"

-- Friendly name used in RM's log output and in this file's messages.
local MODULE_NAME = "ArgMOD Mythical"

-- JSON data files, relative to the mod's data/ folder.
local MATERIALS_FILE = "argmyth_materials.json"
local REACTIONS_FILE = "argmyth_reactions.json"


-- ==========================================
-- RAW DEPENDENCY CHECK
-- ==========================================
-- This module is deliberately a hybrid: the injected half depends on
-- a raw half, and on two other mods. Each check below looks up one
-- thing that only a given raw file can provide, which proves that
-- file loaded.
--
-- These run at token-call time, NOT when this script first executes,
-- because raws are not parsed yet at script load.
--
-- Nothing here blocks registration. A missing dependency degrades the
-- mod rather than breaking it, so we warn and carry on.
-- ==========================================

-- Is there an inorganic with this id? Covers metals and minerals.
local function inorganic_exists(id)
    for _, mat in ipairs(df.global.world.raws.inorganics.all) do
        if mat.id == id then return true end
    end
    return false
end

-- Is there a colour descriptor with this id? Colours resolve by name
-- at injection time, so a missing one is silent: the metal just comes
-- out grey with no error anywhere.
local function color_exists(id)
    for _, c in ipairs(df.global.world.raws.descriptors.colors) do
        if c.id == id then return true end
    end
    return false
end

-- Every colour the ten injected metals ask for. Five come from
-- ArgMOD's descriptor file, five are expected to resolve against
-- vanilla. Both are checked, because the failure looks identical.
local REQUIRED_COLORS = {
    "AKIMRIL", "GOBRONZE", "ORICHALCUM", "MITHRIL", "REDSTEEL",
    "SAFFRON", "PALE_BLUE", "AQUAMARINE", "RIVER_BLUE", "CERULEAN",
}

local function check_raw_dependencies()
    local problems = {}

    -- Sentinel: only the DRG minerals mod defines HOLLOMITE.
    if not inorganic_exists("HOLLOMITE") then
        table.insert(problems,
            "The DRG minerals mod is missing. Reactions consuming cropparine, umasteel and bismor bronze have no valid reagents.")
    end

    -- Sentinel: only ArgMOD's raw half defines SLAG.
    if not inorganic_exists("SLAG") then
        table.insert(problems,
            "ArgMOD's raw half is missing. Five reactions produce slag and cannot resolve it.")
    end

    -- Sentinel: this mod's own raw half holds the four ore-fed metals.
    if not inorganic_exists("RUBEDITIUM") then
        table.insert(problems,
            "This mod's raw half is missing. Umanitium, dystrum, blurium and rubeditium are defined there, not here.")
    end

    -- Sentinel: TITANIUM comes from Elemental Metals Library.
    if not inorganic_exists("TITANIUM") then
        table.insert(problems,
            "Elemental Metals Library is missing. Akimril and mithril cannot be alloyed without titanium.")
    end

    -- Colours are checked individually: one missing name means one
    -- grey metal, not a whole broken file, so name the ones that fail.
    local missing_colors = {}
    for _, name in ipairs(REQUIRED_COLORS) do
        if not color_exists(name) then
            table.insert(missing_colors, name)
        end
    end
    if #missing_colors > 0 then
        table.insert(problems,
            "Missing colour descriptors (those metals will render grey): " ..
            table.concat(missing_colors, ", "))
    end

    if #problems > 0 then
        print(MODULE_NAME .. ": raw dependency check found " .. #problems .. " issue(s):")
        for _, p in ipairs(problems) do
            print("  - " .. p)
        end
        print("  Injected content will still load, but parts of the mod will not work as intended.")
    end

    return #problems == 0
end


-- ==========================================
-- REGISTRATION
-- ==========================================
-- Registers a listener with RM's module engine. RM broadcasts a token
-- call at startup and this listener answers with paths to our JSON
-- files. The engine loads, validates, and injects them.
--
-- We hand back file paths rather than pre-built Lua tables because
-- every material here carries an explicit MATERIAL_VALUE, so there is
-- nothing to compute at runtime and the engine can read the files
-- directly.
-- ==========================================
local function register_with_rm()
    -- Locate RM's module engine. If RM is not installed this fails
    -- gracefully via pcall and the module simply never registers.
    local ok, engine = pcall(dfhack.script_environment, 'refinish-module-engine')
    if not ok or not engine or not engine.register_listener then
        return
    end

    engine.register_listener(MODULE_NAME, function()
        -- Resolve our own mod folder at runtime. Returns paths like
        --   "mods/<workshop id>/"            (Steam Workshop)
        --   "data/installed_mods/<name>/"    (installed locally)
        local mod_path = scriptmanager.getModSourcePath(MODULE_ID)
        if not mod_path then
            -- Returning nil here means RM rejects the module. Say why
            -- in both places: print goes to the DFHack console, and
            -- refinish_log_event goes to RM's own log panel. Without
            -- the second one this failure is invisible to anyone
            -- reading the panel rather than the console.
            local msg = MODULE_NAME .. ": cannot resolve mod path for ID '" .. MODULE_ID ..
                        "'. Check that MODULE_ID matches [ID:...] in info.txt."
            print(msg)
            if _G.refinish_log_event then
                _G.refinish_log_event(msg)
            end
            return nil
        end

        -- Raws are loaded by now, so the dependency check is meaningful.
        check_raw_dependencies()

        local data_path = mod_path .. "data/"

        return {
            materials_json = data_path .. MATERIALS_FILE,
            reactions_json = data_path .. REACTIONS_FILE,
        }
    end)
end


-- ==========================================
-- AUTO-REGISTER ON LOAD
-- ==========================================
register_with_rm()

return _ENV
