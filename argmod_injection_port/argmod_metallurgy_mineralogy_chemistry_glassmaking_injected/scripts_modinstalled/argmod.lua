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
--   Edits to 33 of the Elemental Metals Library's metals, applied in
--   RAM once they are injected (EDITS TO THE LIBRARY'S METALS below)
--
-- WHAT STAYS IN RAWS (and must remain installed):
--   - All ground-spawning minerals and layer stones. Many injected
--     reactions consume them, and worldgen content cannot be injected.
--   - descriptor_color_palette_arg.txt: the custom metal colours.
--   - building_arg_chemist.txt: 52 reactions attach to this workshop.
--   - The vanilla material rebalances, cut/redefined reactions, and
--     the tallow soap reaction.
--   - The edits to the five library metals that stay in raws:
--     palladium, and the cut and redefined chromium, manganese,
--     cobalt and molybdenum.
--
-- That split is why this file runs a dependency check at load time:
-- if the raws half goes missing, the symptoms are silent and strange
-- (grey metals, 52 reactions attached to nothing), so we say so.
--
-- REQUIREMENTS:
--   - Refinish Metal installed and active.
--   - argmod_materials.json and argmod_reactions.json in data/.
--   - Elemental Metals Library (Injected) installed and active. Both
--     JSONs list EML_ in depends_on, so RM injects the library first,
--     and skips ArgMOD, with every module built on it, without it.
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

local REQUIRED_COLORS = {
    "AMETHYST", "APPLE_GREEN", "AQUA", "AQUAMARINE", "BRIGHTSTEEL", "BURNT_UMBER",
    "CARMINE", "CHESTNUT", "CLEAR", "COBALT", "COPPER", "DARK_AZURE",
    "DARK_GREEN", "DARK_INDIGO", "DARK_OLIVE", "DARK_VIOLET", "DEEP_SEA_BLUE", "EGGPLANT",
    "EMERALD", "EUCALYPTUS", "FLAX", "GRAY", "GREEN", "IVORY",
    "LEMON", "LILAC", "MAHOGANY", "MAROON", "MIDNIGHT_BLUE", "MOSS_GREEN",
    "PALE_BLUE", "PUMPKIN", "PURPLE", "RIVER_BLUE", "SCARLET", "VIOLET",
    "WHITE",
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
local LOG_SYS, LOG_SUB = 'ARGMOD', 'MODULE'
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
-- ArgMOD, with nothing in the console or the log to say so.
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

    -- Color Check
    for _, id in ipairs(REQUIRED_COLORS) do
        if not deps.check("color", id) then
            table.insert(problems, "Missing ArgMOD required colour raw: " .. id)
        end
    end
    -- Workshop Check
    if not deps.check("workshop", "CHEMIST") then
        table.insert(problems, "Missing workshop: CHEMIST")
    end

    -- Inorganic Check
    if not deps.check("inorganic", "SYENITE") then
        table.insert(problems, "ArgMOD inorganic raws missing. Test: SYENITE")
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
-- EDITS TO THE LIBRARY'S METALS
-- ==========================================
-- ArgMOD's raw file retuned 33 of Putnam's library metals with
-- SELECT_INORGANIC blocks in inorganic_metals_arg.txt: material
-- values, titanium's and tungsten's strength, colours, mercury's gas
-- name, a reaction class, and SPECIAL on most of them.
--
-- The Elemental Metals Library (Injected) now puts those 33 into RAM
-- at startup, as EML_LITHIUM, EML_TITANIUM and so on. A raw can never
-- reach them: DF parses raws before RM injects anything. So the edits
-- moved here, kept as the raw tokens themselves so each one can be
-- checked against the original file, and apply_eml_edits writes them
-- into RAM.
--
-- WHEN IT RUNS. RM calls apply_eml_edits through on_materials_injected
-- (REGISTRATION, below), right after ArgMOD's own materials inject.
-- Both ArgMOD JSONs list EML_ in depends_on, so the library's metals
-- are already in the array by then, and RM's scan has not run yet, so
-- everything after it reads the edited values. Every data cycle
-- injects the metals fresh and runs this again.
--
-- WHAT IT UNDERSTANDS. Exactly the tokens these edits use, applied in
-- the order listed, the way DF applies a raw block:
--   SPECIAL                         the inorganic's SPECIAL flag
--   MATERIAL_VALUE:n                material value
--   SOLID_DENSITY:n                 solid density
--   LIQUID_DENSITY:n                liquid density
--   <STRESS>_YIELD:n                strength yield for that stress
--   <STRESS>_FRACTURE:n             strength fracture
--   <STRESS>_STRAIN_AT_YIELD:n      strength strain at yield
--   MAX_EDGE:n                      strength max edge
--   STATE_COLOR:<state>:<colour>    colour word and art, per state
--   STATE_NAME_ADJ:<state>:<text>   name and adjective, per state
--   REACTION_CLASS:<class>          appended, as the raw token does
-- Anything else is an ERROR in RM's log, never skipped quietly. A
-- colour is checked against the loaded descriptors first, because
-- RM's resolve_color falls back to colour 7 without a word.
--
-- The five library metals that stay in raws (chromium, manganese,
-- cobalt, molybdenum, palladium) keep their edits in
-- inorganic_metals_arg.txt, where raws can still reach them.
-- ==========================================
local EML_PREFIX = "EML_"

-- Metal key (the library's id without EML_) to its raw tokens, in the
-- order inorganic_metals_arg.txt listed them.
local EML_EDITS = {
    MAGNESIUM    = { "MATERIAL_VALUE:15" },
    LITHIUM      = { "SPECIAL" },
    SODIUM       = { "MATERIAL_VALUE:15", "SPECIAL" },
    BERYLLIUM    = { "SPECIAL" },
    INDIUM       = { "SPECIAL" },
    MERCURY      = { "STATE_NAME_ADJ:GAS:boiling mercury", "SPECIAL" },
    THALLIUM     = { "SPECIAL" },
    SCANDIUM     = { "SPECIAL" },
    TITANIUM     = {
        "SOLID_DENSITY:4510",
        "LIQUID_DENSITY:4100",
        "MATERIAL_VALUE:30",
        "IMPACT_YIELD:1690500",
        "IMPACT_FRACTURE:1932000",
        "IMPACT_STRAIN_AT_YIELD:1537",
        "COMPRESSIVE_YIELD:483000",
        "COMPRESSIVE_FRACTURE:552000",
        "COMPRESSIVE_STRAIN_AT_YIELD:439",
        "TENSILE_YIELD:483000",
        "TENSILE_FRACTURE:552000",
        "TENSILE_STRAIN_AT_YIELD:460",
        "TORSION_YIELD:253750",
        "TORSION_FRACTURE:290000",
        "TORSION_STRAIN_AT_YIELD:634",
        "SHEAR_YIELD:253750",
        "SHEAR_FRACTURE:290000",
        "SHEAR_STRAIN_AT_YIELD:634",
        "BENDING_YIELD:483000",
        "BENDING_FRACTURE:552000",
        "BENDING_STRAIN_AT_YIELD:460",
        "MAX_EDGE:10120",
        "SPECIAL",
        "STATE_COLOR:ALL:SILVER",
        "REACTION_CLASS:NICKEL_OR_NOBLE",
    },
    VANADIUM     = { "SPECIAL", "STATE_COLOR:ALL:BLUE-GRAY" },
    YTTRIUM      = { "SPECIAL" },
    ZIRCONIUM    = { "SPECIAL" },
    TECHNETIUM   = { "SPECIAL" },
    CADMIUM      = { "SPECIAL" },
    LANTHANUM    = { "SPECIAL" },
    TUNGSTEN     = {
        "MATERIAL_VALUE:70",
        "IMPACT_YIELD:2625000",
        "IMPACT_FRACTURE:3430000",
        "IMPACT_STRAIN_AT_YIELD:765",
        "COMPRESSIVE_YIELD:2625000",
        "COMPRESSIVE_FRACTURE:3430000",
        "COMPRESSIVE_STRAIN_AT_YIELD:765",
        "TENSILE_YIELD:750000",
        "TENSILE_FRACTURE:980000",
        "TENSILE_STRAIN_AT_YIELD:182",
        "TORSION_YIELD:375000",
        "TORSION_FRACTURE:490000",
        "TORSION_STRAIN_AT_YIELD:233",
        "SHEAR_YIELD:375000",
        "SHEAR_FRACTURE:490000",
        "SHEAR_STRAIN_AT_YIELD:233",
        "BENDING_YIELD:750000",
        "BENDING_FRACTURE:980000",
        "BENDING_STRAIN_AT_YIELD:182",
        "MAX_EDGE:11600",
        "SPECIAL",
        "STATE_COLOR:ALL:TAUPE_GRAY",
    },
    RHENIUM      = { "SPECIAL" },
    CERIUM       = { "SPECIAL" },
    PRASEODYMIUM = { "SPECIAL" },
    NEODYMIUM    = { "SPECIAL" },
    PROMETHIUM   = { "SPECIAL" },
    SAMARIUM     = { "SPECIAL" },
    GADOLINIUM   = { "SPECIAL" },
    TERBIUM      = { "SPECIAL" },
    DYSPROSIUM   = { "SPECIAL" },
    HOLMIUM      = { "SPECIAL" },
    ERBIUM       = { "SPECIAL" },
    THULIUM      = { "SPECIAL" },
    YTTERBIUM    = { "SPECIAL" },
    LUTETIUM     = { "SPECIAL" },
    THORIUM      = { "SPECIAL" },
    PLUTONIUM    = { "SPECIAL" },
    URANIUM      = { "SPECIAL" },
}

-- Raw state words, mapped to the per-state fields DF keeps on a
-- material (state_color, state_name, state_adj).
local STATE_GROUPS = {
    ALL           = { "Solid", "Liquid", "Gas", "Powder", "Paste", "Pressed" },
    ALL_SOLID     = { "Solid", "Powder", "Paste", "Pressed" },
    SOLID         = { "Solid" },
    LIQUID        = { "Liquid" },
    GAS           = { "Gas" },
    POWDER        = { "Powder" },
    SOLID_POWDER  = { "Powder" },
    PASTE         = { "Paste" },
    SOLID_PASTE   = { "Paste" },
    PRESSED       = { "Pressed" },
    SOLID_PRESSED = { "Pressed" },
}

-- Plain number fields on the material, by token.
local NUMBER_FIELDS = {
    MATERIAL_VALUE = "material_value",
    SOLID_DENSITY  = "solid_density",
    LIQUID_DENSITY = "liquid_density",
}

-- A strength token is a stress followed by one of three suffixes. The
-- strain suffix is tested first, because it also ends in _YIELD.
local STRESSES = {
    IMPACT = true, COMPRESSIVE = true, TENSILE = true,
    TORSION = true, SHEAR = true, BENDING = true,
}
local STRENGTH_SUFFIXES = {
    { "_STRAIN_AT_YIELD", "strain_at_yield" },
    { "_FRACTURE",        "fracture" },
    { "_YIELD",           "yield" },
}

-- Applies one raw token to one injected inorganic. Returns true when
-- applied, or false and the reason. inj is RM's material injector,
-- for resolve_color and new_string_ptr.
local function apply_edit_token(inorg, token, inj)
    local mat = inorg.material
    local f = {}
    for part in string.gmatch(token, "[^:]+") do f[#f + 1] = part end
    local head = f[1]

    if head == "SPECIAL" then
        inorg.flags.SPECIAL = true
        return true
    end

    if NUMBER_FIELDS[head] or head == "MAX_EDGE" then
        local n = tonumber(f[2])
        if not n then return false, "no number" end
        if head == "MAX_EDGE" then
            mat.strength.max_edge = n
        else
            mat[NUMBER_FIELDS[head]] = n
        end
        return true
    end

    for _, sf in ipairs(STRENGTH_SUFFIXES) do
        local suffix, field = sf[1], sf[2]
        if #head > #suffix and string.sub(head, -#suffix) == suffix then
            local stress = string.sub(head, 1, #head - #suffix)
            local n = tonumber(f[2])
            if not STRESSES[stress] then return false, "unknown stress" end
            if not n then return false, "no number" end
            mat.strength[field][stress] = n
            return true
        end
    end

    if head == "STATE_COLOR" then
        local states = STATE_GROUPS[f[2] or ""]
        if not states then return false, "unknown state" end
        if not (f[3] and deps.check("color", f[3])) then
            return false, "colour not loaded"
        end
        -- state_color holds a PATTERN index, which resolve_color gives.
        local pattern = inj.resolve_color(f[3])
        for _, st in ipairs(states) do mat.state_color[st] = pattern end
        return true
    end

    if head == "STATE_NAME_ADJ" then
        local states = STATE_GROUPS[f[2] or ""]
        if not states or not f[3] then return false, "unknown state" end
        local text = table.concat(f, ":", 3)
        for _, st in ipairs(states) do
            mat.state_name[st] = text
            mat.state_adj[st] = text
        end
        return true
    end

    if head == "REACTION_CLASS" then
        if not f[2] then return false, "no class" end
        -- Appended, as the raw token does. Skipped when already there,
        -- so a second run on the same material cannot double it.
        for _, s in ipairs(mat.reaction_class) do
            if s.value == f[2] then return true end
        end
        mat.reaction_class:insert('#', inj.new_string_ptr(f[2]))
        return true
    end

    return false, "token not understood"
end

-- Writes every edit into RAM. RM calls this once ArgMOD's materials
-- are in (on_materials_injected, REGISTRATION below).
local function apply_eml_edits()
    -- RM's material injector, for resolve_color and new_string_ptr.
    -- Looked up here, not at file load: reqscript throws on a missing
    -- script, and at file load that would stop this file before the
    -- listener registers (see RAW LOOKUPS).
    local ok, inj = pcall(reqscript, 'refinish-module-inject')
    if not ok or not inj then
        -- ERROR: the library's metals keep Putnam's values this session.
        log('ERROR', "RM's material injector did not load, so no edit to"
            .. " the library's metals was applied.", 'EML_EDITS')
        return
    end

    -- One walk to find the library's metals by id.
    local by_id = {}
    for _, inorg in ipairs(df.global.world.raws.inorganics.all) do
        if string.sub(inorg.id, 1, #EML_PREFIX) == EML_PREFIX then
            by_id[inorg.id] = inorg
        end
    end

    -- Sorted so the log reads the same every load.
    local keys = {}
    for key in pairs(EML_EDITS) do keys[#keys + 1] = key end
    table.sort(keys)

    local metals, applied, failed = 0, 0, 0
    for _, key in ipairs(keys) do
        local id = EML_PREFIX .. key
        local inorg = by_id[id]
        if not inorg then
            -- ERROR: this metal plays with Putnam's values, not ArgMOD's.
            failed = failed + #EML_EDITS[key]
            log('ERROR', string.format('%s is not in RAM, so its %d edit(s)'
                .. ' were not applied.', id, #EML_EDITS[key]), 'EML_EDITS')
        else
            metals = metals + 1
            for _, token in ipairs(EML_EDITS[key]) do
                local ok_t, done, why = pcall(apply_edit_token, inorg, token, inj)
                if ok_t and done then
                    applied = applied + 1
                else
                    failed = failed + 1
                    -- ERROR: this one value stays Putnam's.
                    log('ERROR', string.format('%s: edit %s not applied (%s).',
                        id, token, tostring(ok_t and why or done)), 'EML_EDITS')
                end
            end
        end
    end

    log('DETAIL', string.format('%d edit(s) applied to %d library metal(s),'
        .. ' %d not applied.', applied, metals, failed), 'EML_EDITS')
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
            -- Returning nil makes RM reject the module, so say why in RM's
            -- log panel. ERROR: none of ArgMOD is in play this session.
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

            -- Run once ArgMOD's materials are in RAM, and so after
            -- the library's (depends_on EML_): see EDITS TO THE
            -- LIBRARY'S METALS above.
            on_materials_injected = apply_eml_edits,
        }
    end, MODULE_ID)
end


-- ==========================================
-- AUTO-REGISTER ON LOAD
-- ==========================================
register_with_rm()

return _ENV
