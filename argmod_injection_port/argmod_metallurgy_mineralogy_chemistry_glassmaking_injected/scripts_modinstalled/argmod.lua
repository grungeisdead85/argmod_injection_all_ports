--@ module = true
-- ==========================================
-- RM MODULE: ArgMOD
-- ==========================================
-- Registers ArgMOD's runtime-injected content with Refinish Metal's
-- module engine. RM injects it into RAM at startup and sweeps it back
-- out on shutdown, so none of it touches worldgen or the save.
--
-- WHAT THIS MODULE INJECTS:
--   68 materials:  29 metals/alloys, 39 chemical powders and liquids
--   202 reactions: smelter, chemist, mill, kiln, ashery, soap maker
--   20 categories
--   128 entity permits across MOUNTAIN, PLAINS and EVIL
--
-- WHAT STAYS IN RAWS (and must remain installed):
--   - All ground-spawning minerals and layer stones. Many injected
--     reactions consume them, and worldgen content cannot be injected.
--   - descriptor_color_palette_arg.txt: the custom metal colours.
--   - building_arg_chemist.txt: 52 reactions attach to this workshop.
--   - The vanilla material rebalances, cut/redefined reactions, and
--     the tallow soap reaction.
--
-- That split is why this file runs a dependency check at load time:
-- if the raws half goes missing, the symptoms are silent and strange
-- (grey metals, 52 reactions attached to nothing), so we say so.
--
-- REQUIREMENTS:
--   - Refinish Metal installed and active.
--   - argmod_materials.json and argmod_reactions.json in data/.
-- ==========================================

local scriptmanager = require('script-manager')


-- ==========================================
-- CONFIGURATION
-- ==========================================

-- MUST match the [ID:...] line in ArgMOD's info.txt. If this is
-- wrong, getModSourcePath returns nil and the module cannot find
-- its own data folder. The check below reports that clearly.
local MODULE_ID = "argmod_metallurgy_mineralogy_chemistry_glassmaking_injected"

-- Friendly name used in RM's log output and this file's messages.
local MODULE_NAME = "ArgMOD"

-- JSON data files, relative to the mod's data/ folder.
local MATERIALS_FILE = "argmod_materials.json"
local REACTIONS_FILE = "argmod_reactions.json"


-- ==========================================
-- RAW DEPENDENCY CHECK
-- ==========================================
-- This module is deliberately a hybrid: the injected half depends on
-- the raw half. Each entry below names one raw file, something we can
-- look up to prove it loaded, and what breaks if it didn't.
--
-- Checks run at token-call time, NOT when this script first executes,
-- because raws aren't parsed yet at script load.
--
-- Nothing here blocks registration. A missing dependency degrades the
-- mod rather than breaking it, so we warn and carry on.
-- ==========================================

-- Is there an inorganic with this id? Covers minerals and layer stones.
local function inorganic_exists(id)
    for _, mat in ipairs(df.global.world.raws.inorganics.all) do
        if mat.id == id then return true end
    end
    return false
end

-- Is there a colour descriptor with this id?
local function color_exists(id)
    for _, c in ipairs(df.global.world.raws.descriptors.colors) do
        if c.id == id then return true end
    end
    return false
end

-- Is there a custom workshop with this code?
local function workshop_exists(code)
    for _, ws in ipairs(df.global.world.raws.buildings.workshops) do
        if ws.code == code then return true end
    end
    return false
end

local function check_raw_dependencies()
    local problems = {}

    -- Sentinel values: each is something only the named raw file
    -- provides, so finding it proves that file loaded.
    if not workshop_exists("CHEMIST") then
        table.insert(problems,
            "building_arg_chemist.txt is missing. 52 chemistry reactions have no workshop to appear at.")
    end

    if not color_exists("GUNMETAL") then
        table.insert(problems,
            "descriptor_color_palette_arg.txt is missing. Custom metal colours will fall back to grey.")
    end

    if not inorganic_exists("ANTHRACITE") then
        table.insert(problems,
            "inorganic_all_minerals_arg.txt is missing. Reactions consuming ArgMOD ores and minerals will have no valid reagents.")
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
-- call at startup; this listener answers with paths to our JSON files.
-- The engine loads, validates, and injects them.
--
-- We hand back file paths rather than pre-built Lua tables because
-- every ArgMOD material carries an explicit MATERIAL_VALUE, so there is
-- nothing to compute at runtime, so the engine can read the files
-- directly.
-- ==========================================
local function register_with_rm()
    -- Locate RM's module engine. If RM isn't installed this fails
    -- gracefully and the module simply never registers.
    local ok, engine = pcall(dfhack.script_environment, 'refinish-module-engine')
    if not ok or not engine or not engine.register_listener then
        return
    end

    engine.register_listener(MODULE_NAME, function()
        -- Resolve our own mod folder at runtime. Returns paths like
        --   "mods/2945575779/"                (Steam Workshop)
        --   "data/installed_mods/argmod (108)/"  (installed locally)
        local mod_path = scriptmanager.getModSourcePath(MODULE_ID)
        if not mod_path then
            print(MODULE_NAME .. ": cannot resolve mod path for ID '" .. MODULE_ID ..
                  "'. Check that MODULE_ID matches [ID:...] in info.txt.")
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
