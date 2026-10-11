--@ module = true
-- ==========================================
-- RM MODULE: Elemental Metals Library
-- ==========================================
-- Registers Putnam's Elemental Metals Library with Refinish Metal's
-- module engine. RM injects the metals into RAM at startup and sweeps
-- them back out on shutdown, so they take no inorganic slot at
-- worldgen, where room for real minerals is scarce.
--
-- WHAT THIS MODULE INJECTS:
--   33 metals, prefix EML_ (EML_TITANIUM, EML_TUNGSTEN and so on),
--   exactly as Putnam's raw file defines them. Every value the raw
--   took from vanilla's METAL_TEMPLATE is written out in the JSON,
--   because RM builds each material from a cloned donor metal and
--   keeps the donor's value for anything the JSON leaves out.
--   No reactions: like the raw library, nothing here makes them.
--   Other modules (ArgMOD) bring the reactions.
--
-- WHAT STAYS IN RAWS (and must remain installed):
--   objects/inorganic_metals_library.txt keeps five metals:
--   CHROMIUM, MANGANESE, COBALT, MOLYBDENUM and PALLADIUM. Raw
--   objects in other mods reach those five (ores name them, ArgMOD
--   cuts and redefines four and edits palladium), and a raw can never
--   name an injected material: raws are parsed before RM injects.
--
-- MODULES BUILT ON THIS ONE:
--   ArgMOD lists EML_ in depends_on, so the engine injects this module
--   first, and drops ArgMOD (and everything built on ArgMOD) when this
--   module is missing. ArgMOD also retunes some of these metals once
--   they are in RAM; see EML_EDITS in argmod.lua. This file never
--   carries another mod's edits, so the metals here stay Putnam's.
--
-- REQUIREMENTS:
--   - Refinish Metal installed and active.
--   - eml_materials.json in data/.
-- ==========================================

local scriptmanager = require('script-manager')


-- ==========================================
-- CONFIGURATION
-- ==========================================

-- MUST match the [ID:...] line in this mod's info.txt. If it is
-- wrong, getModSourcePath returns nil and the module cannot find its
-- own data folder. The registration step below reports that clearly.
local MODULE_ID = "metal_library_injected"

-- Friendly name used in RM's log output and this file's messages.
local MODULE_NAME = "Elemental Metals Library"

-- JSON data file, relative to the mod's data/ folder. Materials only:
-- the engine accepts a module that returns no reactions file.
local MATERIALS_FILE = "eml_materials.json"


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
local LOG_SYS, LOG_SUB = 'EML', 'MODULE'
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
-- RAW DEPENDENCY CHECK
-- ==========================================
-- The injected half and the raw half ship together. If the raw file
-- is missing, the five raw metals vanish and so do the ores and the
-- ArgMOD redefinitions that need them, with nothing to say why. So we
-- say so.
--
-- PALLADIUM is the sentinel: only this mod's raw file defines it.
-- ArgMOD edits it but cannot create it.
--
-- Runs at token-call time, NOT when this script first executes,
-- because raws aren't parsed yet at script load. Nothing here blocks
-- registration: the 33 injected metals load either way.
-- ==========================================
local function has_inorganic(id)
    local ok, found = pcall(function()
        for _, mat in ipairs(df.global.world.raws.inorganics.all) do
            if mat.id == id then return true end
        end
        return false
    end)
    return ok and found == true
end

local function check_raw_dependencies()
    if has_inorganic("PALLADIUM") then
        log('DETAIL', 'Every raw dependency is loaded.', 'RAW_DEPS')
        return true
    end
    log('WARNING', 'Library raws missing. Test: PALLADIUM. The 33 injected'
        .. ' metals still load, but the five raw ones and everything that'
        .. ' names them will not work.', 'RAW_DEPS')
    return false
end


-- ==========================================
-- REGISTRATION
-- ==========================================
-- Registers a listener with RM's module engine. RM broadcasts a token
-- call at startup; this listener answers with the path to our JSON.
-- The engine loads, validates, and injects it.
--
-- A file path rather than a pre-built Lua table: every metal carries
-- explicit values, so there is nothing to compute at runtime.
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
        --   "mods/1234567890/"                           (Steam Workshop)
        --   "data/installed_mods/metal_library_injected (1)/"  (local)
        local mod_path = scriptmanager.getModSourcePath(MODULE_ID)
        if not mod_path then
            -- Returning nil makes RM reject the module, so say why in
            -- RM's log panel. ERROR: none of the 33 metals are in play,
            -- and the engine drops ArgMOD with them.
            log('ERROR', "Cannot resolve the mod path for ID '" .. MODULE_ID
                .. "'. Check that MODULE_ID matches [ID:...] in info.txt.", 'DATA')
            return nil
        end

        -- Raws are loaded by now, so the dependency check is meaningful.
        check_raw_dependencies()

        return {
            materials_json = mod_path .. "data/" .. MATERIALS_FILE,
        }
    end, MODULE_ID)
end


-- ==========================================
-- AUTO-REGISTER ON LOAD
-- ==========================================
register_with_rm()

return _ENV
