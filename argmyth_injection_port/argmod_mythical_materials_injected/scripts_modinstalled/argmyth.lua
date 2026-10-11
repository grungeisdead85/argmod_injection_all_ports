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
-- so ArgMOD core has to go first. It also names two of the Elemental
-- Metals Library's injected metals (EML_MAGNESIUM, EML_TITANIUM), so
-- the library goes first as well. That is declared, not inferred:
-- both JSON files carry
--
--     "depends_on": ["ARGMOD_", "EML_"]
--
-- in their module block, and RM orders injection from it. If either is
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
--   - Elemental Metals Library (Injected) installed and active.
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

-- Every colour the ten injected metals ask for. Five come from
-- ArgMOD's descriptor file, five are expected to resolve against
-- vanilla. Both are checked, because the failure looks identical.
local REQUIRED_COLORS = {
    "AKIMRIL", "GOBRONZE", "ORICHALCUM", "MITHRIL", "REDSTEEL",
    "SAFFRON", "PALE_BLUE", "AQUAMARINE", "RIVER_BLUE", "CERULEAN",
}

-- ==========================================
-- LOG FUNNEL
-- ==========================================
-- Every line this file writes goes to RM's log through log(), in the
-- grammar RM's log panel reads: SYSTEM SUBSYSTEM SUBJECT TYPE | body,
-- composed by refinish-log. The panel filters on TYPE:
--   DETAIL   debugging material, shown in Debug only
--   WARNING  degraded but working, shown at every Log Detail level
--   ERROR    the player meets it in play, shown at every level
--
-- No console prints. A print only appears as the direct answer to a
-- command typed into the DFHack console, so a message printed while
-- RM loads reaches nobody reading the log panel.
-- ==========================================
local LOG_SYS, LOG_SUB = 'ARGMYTH', 'MODULE'
local rlog = nil
pcall(function() rlog = reqscript('refinish-log') end)

local function log(typ, msg, subject)
    if not _G.refinish_log_event then return end
    local line
    if rlog then
        line = rlog.compose(LOG_SYS, LOG_SUB, subject, typ, msg)
    else
        -- The composer failed to load. Same grammar, unsanitised.
        line = string.format('%s %s %s %s | %s', LOG_SYS, LOG_SUB,
            tostring(subject or '-'), tostring(typ or 'UNTYPED'),
            tostring(msg))
    end
    _G.refinish_log_event(line)
end


-- ==========================================
-- RAW LOOKUPS
-- ==========================================
-- deps.check(category, id) answers whether this world's raws hold the
-- named thing: an inorganic by id, a colour descriptor by id, or a
-- custom workshop by code.
--
-- WHY IT LIVES HERE. This file used to load the same check from RM's
-- refinish-module-dependencies.lua, with a bare reqscript at the top.
-- RM v4.0.0 ships no such script, and reqscript throws when a script
-- is missing ("Could not find script", dfhack.lua). DFHack loads mod
-- scripts through a pcall (script-manager.lua, foreach_module_script),
-- so the error was swallowed: this file stopped at that line, the
-- listener below was never registered, and RM never injected
-- ArgMOD Mythical, with nothing in the console or the log to say so.
--
-- The lookups are the ones in RM's advanced module template
-- (rm-module-template-advanced.lua), so this file needs nothing from RM
-- but the module engine. Each walks one raws vector; they run once a
-- load, at the token call, so nothing is cached.
-- ==========================================
local deps = {}

function deps.check(category, id)
    local ok, found = pcall(function()
        local raws = df.global.world.raws
        if category == 'inorganic' then
            for _, mat in ipairs(raws.inorganics.all) do
                if mat.id == id then return true end
            end
        elseif category == 'color' then
            for _, c in ipairs(raws.descriptors.colors) do
                if c.id == id then return true end
            end
        elseif category == 'workshop' then
            for _, ws in ipairs(raws.buildings.workshops) do
                if ws.code == id then return true end
            end
        end
        return false
    end)
    return ok and found == true
end

local function check_raw_dependencies()
    local problems = {}

    -- Sentinel: only the DRG minerals mod defines HOLLOMITE.
    if not deps.check("inorganic", "HOLLOMITE") then
        table.insert(problems,
            "The DRG minerals raws are missing. Test: HOLLOMITE")
    end

    -- Sentinel: only ArgMOD's raw half defines SLAG.
    if not deps.check("inorganic", "SLAG") then
        table.insert(problems,
            "ArgMOD's inorganic raws missing. Test: SLAG")
    end

    -- Sentinel: this mod's own raw half holds the four ore-fed metals.
    if not deps.check("inorganic", "RUBEDITIUM") then
        table.insert(problems,
            "ArgMYTH inorganic raws missing. Test: RUBEDITIUM")
    end

    -- No check for the Elemental Metals Library here. The two library
    -- metals this module uses, magnesium and titanium, are injected
    -- now (EML_MAGNESIUM, EML_TITANIUM), so no raw can show them. Both
    -- JSONs list EML_ in depends_on instead, and RM skips this module,
    -- and says so in its log, when the library is not loaded.

    -- Color Check
    for _, id in ipairs(REQUIRED_COLORS) do
        if not deps.check("color", id) then
            table.insert(problems, "Missing ArgMYTH required colour raw: " .. id)
        end
    end

    -- One WARNING a problem, in RM's log: the module still loads, and
    -- only the parts that need the missing raws fail in play.
    for _, p in ipairs(problems) do
        log('WARNING', p .. '. Injected content still loads, but the parts'
            .. ' that need it will not work.', 'RAW_DEPS')
    end
    if #problems == 0 then
        log('DETAIL', 'Every raw dependency is loaded.', 'RAW_DEPS')
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
            -- Returning nil here means RM rejects the module, so say why
            -- in RM's log panel: a failure said only in the console is
            -- invisible to anyone reading the panel. ERROR: none of the
            -- module is in play this session. (The line used to be
            -- handed to refinish_log_event raw, outside the panel's
            -- grammar, and printed besides.)
            log('ERROR', "Cannot resolve the mod path for ID '" .. MODULE_ID
                .. "'. Check that MODULE_ID matches [ID:...] in info.txt.", 'DATA')
            return nil
        end

        -- Raws are loaded by now, so the dependency check is meaningful.
        check_raw_dependencies()

        local data_path = mod_path .. "data/"

        return {
            materials_json = data_path .. MATERIALS_FILE,
            reactions_json = data_path .. REACTIONS_FILE,
        }
    end, MODULE_ID)
end


-- ==========================================
-- AUTO-REGISTER ON LOAD
-- ==========================================
register_with_rm()

return _ENV
