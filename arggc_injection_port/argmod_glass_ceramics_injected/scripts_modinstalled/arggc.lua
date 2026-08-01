--@ module = true
-- ==========================================
-- RM MODULE: ArgMOD Glass and Ceramics
-- ==========================================
-- Registers the glass, glaze and ceramics unit with Refinish Metal's
-- module engine. RM injects it into RAM at startup and sweeps it back
-- out on shutdown, so none of it touches worldgen or the save.
--
-- WHAT THIS MODULE INJECTS:
--   51 materials   - glasses, glazes, fluxes and oxides
--   950 reactions  - kiln, glass furnace and compounder
--   61 categories  - a real tree, 31 of them nested
--   1144 entity permits across MOUNTAIN, PLAINS and EVIL
--
-- WHAT STAYS IN RAWS (and must remain installed):
--   - All 26 clays. graphics_arg_clays.txt names every one of them by
--     id, and three are SOIL layers besides.
--   - All 30 ceramics. inorganic_clay_minerals_arg.txt stays raw and
--     names every one of them with MATERIAL_REACTION_PRODUCT, so the
--     clays' FIRED_MAT links would break if they were injected.
--   - The Compounder workshop itself, its graphics, and the three
--     PERMITTED_BUILDING grants. Buildings cannot be injected.
--   - 13 cut-and-redefine reactions. The engine only adds.
--   - The SELECT_INORGANIC edits. These modify materials that already
--     exist, and the engine only adds.
--
-- ==========================================
-- DEPENDENCY DIRECTION
-- ==========================================
-- Raws are parsed when the world loads. Injection happens afterwards.
-- So an injected thing may name a raw thing, but never the reverse:
-- a raw file naming an injected material fails silently, and an
-- unresolved product renders as magma.
--
-- The same rule applies between modules, which is why both JSON files
-- carry
--
--     "depends_on": ["ARGMOD_"]
--
-- in their module block. These reactions name ten ArgMOD materials
-- directly (the oxides, aqua regia, sodium and calcium carbonates), so
-- ArgMOD core has to inject first. RM orders it from that declaration
-- and skips this module entirely if ArgMOD is absent, rather than
-- injecting reactions whose products cannot resolve.
--
-- RENAMING THIS PREFIX:
-- Order no longer depends on how prefixes sort, so the name is free in
-- that respect. It is NOT free in one other: a prefix must not be a
-- stem of another module's prefix, nor have one as its stem, because
-- every asset sweep in RM selects by prefix. ARGGC_ shares no stem
-- with ARGMOD_ or ARGMYTH_. RM refuses an overlapping prefix at
-- registration and says so, but pick one that is clearly its own word.
--
-- REQUIREMENTS:
--   - Refinish Metal installed and active.
--   - ArgMOD (both halves) installed and active.
--   - arggc_materials.json and arggc_reactions.json in data/.
-- ==========================================

local json = require('json')
local scriptmanager = require('script-manager')


-- ==========================================
-- CONFIGURATION
-- ==========================================

-- MUST match the [ID:...] line in this mod's info.txt. If it is wrong,
-- getModSourcePath returns nil, the listener returns nil, and RM
-- rejects the module. That is reported to both the console and RM's
-- log panel below, because a silent rejection here is very hard to
-- diagnose from the outside.
local MODULE_ID = "argmod_glass_ceramics_injected"

-- Friendly name used in RM's log output and in this file's messages.
local MODULE_NAME = "ArgMOD Glass and Ceramics"

-- JSON data files, relative to the mod's data/ folder.
local MATERIALS_FILE = "arggc_materials.json"
local REACTIONS_FILE = "arggc_reactions.json"


-- ==========================================
-- RAW DEPENDENCY CHECK
-- ==========================================
-- This module is a hybrid: the injected half depends on a raw half and
-- on ArgMOD. Each check looks up one thing only a given raw file can
-- provide, which proves that file loaded.
--
-- These run at token-call time, NOT when this script first executes,
-- because raws are not parsed yet at script load.
--
-- Nothing here blocks registration. A missing dependency degrades the
-- mod rather than breaking it, so we warn and carry on.
-- ==========================================

local function inorganic_exists(id)
    for _, mat in ipairs(df.global.world.raws.inorganics.all) do
        if mat.id == id then return true end
    end
    return false
end

-- Colours resolve by name at injection time, so a missing one is
-- silent: the material just comes out grey with no error anywhere.
local function color_exists(id)
    for _, c in ipairs(df.global.world.raws.descriptors.colors) do
        if c.id == id then return true end
    end
    return false
end

-- Custom workshops are found by code, the same way the reaction
-- builder finds them. Without the Compounder, 118 reactions have
-- nowhere to appear.
local function workshop_exists(code)
    local ok, defs = pcall(function()
        return df.global.world.raws.buildings.workshops
    end)
    if not ok or not defs then return false end
    for _, b in ipairs(defs) do
        if b.code == code then return true end
    end
    return false
end

-- Every colour the 51 materials name. Only BRIGHTSTEEL comes from
-- ArgMOD's descriptor file; the rest are expected to resolve against
-- vanilla. All are checked, because the failure looks identical either
-- way and a miss is a silently grey material.
local REQUIRED_COLORS = {
    "AMETHYST", "APPLE_GREEN", "AQUA", "AQUAMARINE", "BRIGHTSTEEL", "BURNT_UMBER",
    "CARMINE", "CHESTNUT", "CLEAR", "COBALT", "COPPER", "DARK_AZURE",
    "DARK_GREEN", "DARK_INDIGO", "DARK_OLIVE", "DARK_VIOLET", "DEEP_SEA_BLUE", "EGGPLANT",
    "EMERALD", "EUCALYPTUS", "FLAX", "GRAY", "GREEN", "IVORY",
    "LEMON", "LILAC", "MAHOGANY", "MAROON", "MIDNIGHT_BLUE", "MOSS_GREEN",
    "PALE_BLUE", "PUMPKIN", "PURPLE", "RIVER_BLUE", "SCARLET", "VIOLET",
    "WHITE",
}

local function check_raw_dependencies()
    local problems = {}

    -- Sentinel: only this mod's raw half defines the stoneware clays.
    if not inorganic_exists("RED_STONEWARE_CLAY") then
        table.insert(problems,
            "This mod's raw half is missing. All 26 clays are defined there, not here, and every ceramic reaction consumes one.")
    end

    -- Sentinel: only ArgMOD's raw half defines SLAG.
    if not inorganic_exists("SLAG") then
        table.insert(problems,
            "ArgMOD's raw half is missing. The slag flux and slag glaze chains cannot resolve.")
    end

    if not workshop_exists("COMPOUNDER") then
        table.insert(problems,
            "The Compounder workshop is missing. 118 reactions have no building to appear at.")
    end

    -- Named individually: one missing colour means one grey material,
    -- not a whole broken file, so say which ones failed.
    local missing_colors = {}
    for _, name in ipairs(REQUIRED_COLORS) do
        if not color_exists(name) then
            table.insert(missing_colors, name)
        end
    end
    if #missing_colors > 0 then
        table.insert(problems,
            "Missing colour descriptors (those materials will render grey): " ..
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
-- JSON LOADER
-- ==========================================
-- Reads and parses a JSON file from disk. Returns the parsed table,
-- or nil on failure.
--
-- This module used to hand RM two file paths and let the engine do
-- the reading. It now reads them here instead, because the sand
-- reagents need patching before the engine ever sees them. See the
-- SAND PATCHER below for why.
-- ==========================================
local function load_json(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*all")
    file:close()
    if not content or content == "" then return nil end
    local ok, parsed = pcall(json.decode, content)
    if not ok then return nil end
    return parsed
end


-- ==========================================
-- SAND MATERIAL RESOLVER
-- ==========================================
-- Scans the live inorganic array for a suitable sand material.
-- Vanilla DF has multiple sand types (SAND_TAN, SAND_WHITE,
-- SAND_BLACK, SAND_RED, SAND_YELLOW), all flagged SOIL_SAND.
-- Modded worlds may add more or remove some.
--
-- Preference order:
--   1. SAND_TAN (most common vanilla sand, always present
--      in unmodded worlds)
--   2. First inorganic with the SOIL_SAND flag
--
-- Returns: the inorganic ID string (e.g. "SAND_TAN"), or nil
-- if the world has no sand materials at all.
-- ==========================================
local function resolve_sand_id()
    local raws = df.global.world.raws.inorganics.all
    local fallback = nil

    for _, mat in ipairs(raws) do
        if mat.flags.SOIL_SAND then
            -- Preferred: vanilla SAND_TAN — return immediately
            if mat.id == "SAND_TAN" then
                return "SAND_TAN"
            end
            -- Otherwise remember the first sand we find
            if not fallback then
                fallback = mat.id
            end
        end
    end

    return fallback  -- nil if no sand exists in this world
end


-- ==========================================
-- SAND PATCHER
-- ==========================================
-- Resolves null mat_id fields on sand-related reactions to the
-- best available sand inorganic in this world.
--
-- Patches three places:
--   1. GRIND_SAND products — what the grinder outputs
--   2. CRUSH_AGGREGATE products — sand byproduct from crushing
--   3. MIX_CONCRETE sand reagents — what the mixer accepts
--
-- All three use mat_id = null (JSON null → Lua nil) as a sentinel
-- meaning "resolve to the best sand at boot time."
--
-- If no sand material exists in the world, GRIND_SAND is removed
-- entirely. CRUSH_AGGREGATE keeps its gravel output but loses
-- sand byproducts and their bag reagents. MIX_CONCRETE's sand
-- reagents stay nil (engine can't resolve them = no concrete).
--
-- This runs AFTER JSON loading but BEFORE the data is returned
-- to the module engine, so the engine never sees a nil mat_id.
-- ==========================================
local function patch_sand(rxn_data)
    if not rxn_data or not rxn_data.reactions then return end

    local sand_id = resolve_sand_id()

    if sand_id then
        local reagents_patched = 0

        for _, rxn in ipairs(rxn_data.reactions) do

            -- GRIND_SAND + CRUSH_AGGREGATE: patch null product mat_id.
            -- Both reactions produce sand as output (GRIND_SAND as the
            -- primary product, CRUSH_AGGREGATE as a byproduct alongside
            -- gravel). The null sentinel on each product means "fill in
            -- the world's sand material at boot time."
            if rxn.key == "GRIND_SAND" or rxn.key == "CRUSH_AGGREGATE" then
                for _, prod in ipairs(rxn.products or {}) do
                    if prod.mat_id == nil then
                        prod.mat_id = sand_id
                    end
                end
            end

            -- MIX_CONCRETE and any other sand consumer: patch null
            -- reagent mat_id. This is item 3 in the header above. It was
            -- documented but never implemented, so the mixer's sand slots
            -- stayed wildcard in RAM (mat_type -1 / mat_index -1) while
            -- only the GRIND_SAND output ever got a real material.
            --
            -- A wildcard POWDER reagent matches ANY powder sitting in a
            -- bag. With four wildcard sand slots next to a specific
            -- cement slot, DF has nothing to tell them apart and reagent
            -- matching goes non deterministic. Resolving the material
            -- here makes every sand slot specific, exactly like cement.
            --
            -- Predicate: type POWDER, no mat_id, code starting "sand".
            --   sand_bag_N  is type BAG      -> skipped, bags are
            --                                   deliberately material free
            --   sandstone   is type BOULDER  -> skipped, and it already
            --                                   carries mat_id SANDSTONE
            for _, rgt in ipairs(rxn.reagents or {}) do
                if rgt.type == "POWDER"
                        and rgt.mat_id == nil
                        and string.find(rgt.code, "^sand") then

                    rgt.mat_id = sand_id
                    reagents_patched = reagents_patched + 1

                    -- Drop sand_bearing once the material is known. It
                    -- was introduced as a stand in for this resolution
                    -- while the reagent was wildcard. Leaving both means
                    -- an item must satisfy the material AND the
                    -- SOIL_SAND flag: redundant, and one more filter
                    -- that can silently reject a valid bag.
                    rgt.sand_bearing = nil
                end
            end

        end
        print(MODULE_NAME .. ": Sand resolved to " .. sand_id
              .. " (" .. reagents_patched .. " sand reagents patched)")
    else
        -- No sand in this world — remove GRIND_SAND entirely (it only
        -- makes sand, so it's useless). Strip sand byproducts from
        -- CRUSH_AGGREGATE but keep the reaction (gravel is its primary
        -- output). Also strip sand bag reagents since they're only
        -- there to hold the sand byproduct.
        for i = #rxn_data.reactions, 1, -1 do
            local rxn = rxn_data.reactions[i]
            if rxn.key == "GRIND_SAND" then
                table.remove(rxn_data.reactions, i)

            elseif rxn.key == "CRUSH_AGGREGATE" then
                -- Remove sand products (null mat_id = sand sentinel)
                for j = #rxn.products, 1, -1 do
                    if rxn.products[j].mat_id == nil then
                        table.remove(rxn.products, j)
                    end
                end
                -- Remove sand bag reagents (only needed for sand output)
                for j = #rxn.reagents, 1, -1 do
                    if string.find(rxn.reagents[j].code, "^sand_") then
                        table.remove(rxn.reagents, j)
                    end
                end
            end
        end
        print(MODULE_NAME .. ": WARNING — No sand material found. GRIND_SAND removed, CRUSH_AGGREGATE sand stripped.")
    end
end


-- ==========================================
-- REGISTRATION
-- ==========================================
-- Registers a listener with RM's module engine. RM broadcasts a token
-- call at startup and this listener answers with paths to our JSON
-- files. The engine loads, validates, and injects them.
-- ==========================================
local function register_with_rm()
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
            -- refinish_log_event goes to RM's own log panel.
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

        -- Read both files here rather than handing RM their paths.
        -- The engine accepts either form; it only reads files itself
        -- when given materials_json / reactions_json. We need the
        -- parsed tables in hand so patch_sand can fix the sand
        -- reagents before validation and injection run.
        local mat_data = load_json(data_path .. MATERIALS_FILE)
        if not mat_data then
            local msg = MODULE_NAME .. ": failed to load " .. MATERIALS_FILE
            print(msg)
            if _G.refinish_log_event then _G.refinish_log_event(msg) end
            return nil
        end

        local rxn_data = load_json(data_path .. REACTIONS_FILE)
        if not rxn_data then
            local msg = MODULE_NAME .. ": failed to load " .. REACTIONS_FILE
            print(msg)
            if _G.refinish_log_event then _G.refinish_log_event(msg) end
            return nil
        end

        -- Give the wildcard sand reagents a real material.
        patch_sand(rxn_data)

        return {
            materials  = mat_data.materials,
            reactions  = rxn_data.reactions,
            categories = rxn_data.categories,
            module     = mat_data.module or rxn_data.module,
        }
    end)
end


-- ==========================================
-- AUTO-REGISTER ON LOAD
-- ==========================================
register_with_rm()

return _ENV
