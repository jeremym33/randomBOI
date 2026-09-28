--[[
    RandomBOI - Unlock Randomizer
    The Binding of Isaac: Repentance / Repentance+

    Principe
    --------
    L'API Lua officielle ne permet pas de modifier les succès (achievements) du
    fichier de sauvegarde. Le mod applique donc une permutation "virtuelle" :

        objet réellement débloqué X  ->  objet obtenu f(X)

    f est une bijection générée à partir d'une graine (seed) propre à chaque
    slot de sauvegarde. Chaque fois qu'un pool d'objets renvoie X (ce qui
    n'arrive que si X est débloqué), le mod remplace X par f(X). Débloquer X en
    jeu revient donc à débloquer f(X) : on garde exactement le même nombre
    d'objets disponibles, mais pas les mêmes.

    Les objets de progression ne sont jamais permutés : ils restent fixes
    (f(X) = X) et ne peuvent pas être la cible d'une autre permutation.
]]

local mod = RegisterMod("RandomBOI", 1)
local json = require("json")
local game = Game()

local SAVE_VERSION = 1
local MAX_REDRAW = 20
local TRINKET_GOLDEN_FLAG = TrinketType and TrinketType.TRINKET_GOLDEN_FLAG or 32768

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------

local CONFIG = {
    -- Permuter aussi les trinkets
    shuffleTrinkets = true,
    -- Ne permuter qu'entre objets de même qualité (0 à 4) : garde l'équilibre
    stratifyByQuality = true,
    -- Ne permuter les actifs qu'avec des actifs, les passifs qu'avec des passifs
    keepActivePassiveSplit = true,
    -- Inclure les objets ajoutés par d'autres mods
    includeModdedItems = false,
    -- Désactiver le mod pendant les challenges (objets imposés)
    disableInChallenges = true,
}

-- Objets nécessaires à la progression : jamais randomisés.
-- IDs numériques (plutôt que les noms d'enum) pour éviter une clé nil si un
-- nom venait à changer entre deux versions du jeu.
local PROGRESSION_COLLECTIBLES = {
    [25]  = "Breakfast (objet de repli quand un pool est vide)",
    [327] = "The Polaroid",
    [328] = "The Negative",
    [238] = "Key Piece 1",
    [239] = "Key Piece 2",
    [550] = "Broken Shovel (1)",
    [551] = "Broken Shovel (2)",
    [552] = "Mom's Shovel",
    [580] = "Red Key",
    [626] = "Knife Piece 1",
    [627] = "Knife Piece 2",
    [633] = "Dogma",
    [668] = "Dad's Note",
}

local PROGRESSION_TRINKETS = {
}

---------------------------------------------------------------------------
-- État
---------------------------------------------------------------------------

local state = {
    loaded = false,
    enabled = true,
    seed = nil,
    collectibleMap = {}, -- réel -> obtenu
    collectibleInverse = {}, -- obtenu -> réel
    trinketMap = {},
    trinketInverse = {},
    run = { collectibles = {} }, -- objets déjà donnés pendant la partie en cours
}

local function log(msg)
    Isaac.DebugString("[RandomBOI] " .. msg)
end

local function say(msg)
    print("[RandomBOI] " .. msg)
    log(msg)
end

---------------------------------------------------------------------------
-- Génération de la permutation
---------------------------------------------------------------------------

local function isQuestItem(cfg)
    return ItemConfig.TAG_QUEST ~= nil and cfg:HasTags(ItemConfig.TAG_QUEST)
end

local function maxVanillaCollectible()
    return CollectibleType.NUM_COLLECTIBLES - 1
end

local function maxVanillaTrinket()
    return TrinketType.NUM_TRINKETS - 1
end

-- Mélange de Fisher-Yates avec le RNG du jeu (déterministe pour une graine donnée)
local function shuffle(list, rng)
    for i = #list, 2, -1 do
        local j = rng:RandomInt(i) + 1
        list[i], list[j] = list[j], list[i]
    end
end

-- Construit une bijection sur les éléments de `groups` (table groupe -> liste d'IDs)
local function buildMapping(groups, rng)
    local map, inverse = {}, {}
    -- Parcours des groupes dans un ordre stable pour rester déterministe
    local keys = {}
    for key in pairs(groups) do
        keys[#keys + 1] = key
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        local ids = groups[key]
        table.sort(ids)
        local targets = {}
        for i, id in ipairs(ids) do
            targets[i] = id
        end
        shuffle(targets, rng)
        for i, id in ipairs(ids) do
            map[id] = targets[i]
            inverse[targets[i]] = id
        end
    end
    return map, inverse
end

local function collectibleGroups()
    local itemConfig = Isaac.GetItemConfig()
    local maxId = CONFIG.includeModdedItems and (itemConfig:GetCollectibles().Size - 1) or maxVanillaCollectible()
    local groups = {}

    for id = 1, maxId do
        local cfg = itemConfig:GetCollectible(id)
        if cfg and not cfg.Hidden and not PROGRESSION_COLLECTIBLES[id] and not isQuestItem(cfg) then
            local quality = CONFIG.stratifyByQuality and (cfg.Quality or 0) or 0
            local kind = "item"
            if CONFIG.keepActivePassiveSplit then
                kind = (cfg.Type == ItemType.ITEM_ACTIVE) and "active" or "passive"
            end
            local key = kind .. ":" .. quality
            groups[key] = groups[key] or {}
            table.insert(groups[key], id)
        end
    end
    return groups
end

local function trinketGroups()
    local itemConfig = Isaac.GetItemConfig()
    local maxId = CONFIG.includeModdedItems and (itemConfig:GetTrinkets().Size - 1) or maxVanillaTrinket()
    local list = {}

    for id = 1, maxId do
        local cfg = itemConfig:GetTrinket(id)
        if cfg and not cfg.Hidden and not PROGRESSION_TRINKETS[id] then
            table.insert(list, id)
        end
    end
    return { trinket = list }
end

local function generate()
    local rng = RNG()
    rng:SetSeed(state.seed, 35)

    state.collectibleMap, state.collectibleInverse = buildMapping(collectibleGroups(), rng)
    if CONFIG.shuffleTrinkets then
        state.trinketMap, state.trinketInverse = buildMapping(trinketGroups(), rng)
    else
        state.trinketMap, state.trinketInverse = {}, {}
    end
    log("Permutation générée (seed " .. state.seed .. ")")
end

local function newSeed()
    local seed = Random()
    if seed == 0 then
        seed = 1
    end
    return seed
end

---------------------------------------------------------------------------
-- Sauvegarde
---------------------------------------------------------------------------

local function save()
    local given = {}
    for id in pairs(state.run.collectibles) do
        given[#given + 1] = id
    end
    local data = {
        version = SAVE_VERSION,
        seed = state.seed,
        enabled = state.enabled,
        runGiven = given,
    }
    mod:SaveData(json.encode(data))
end

local function load()
    local data
    if mod:HasData() then
        local ok, decoded = pcall(json.decode, mod:LoadData())
        if ok and type(decoded) == "table" then
            data = decoded
        end
    end

    if data and data.seed then
        state.seed = data.seed
        state.enabled = data.enabled ~= false
        state.run.collectibles = {}
        for _, id in ipairs(data.runGiven or {}) do
            state.run.collectibles[id] = true
        end
    else
        state.seed = newSeed()
        state.enabled = true
        state.run.collectibles = {}
        say("Nouvelle graine de randomisation : " .. state.seed)
    end

    generate()
    state.loaded = true
    save()
end

local function ensureLoaded()
    if not state.loaded then
        load()
    end
end

local function isActive()
    if not state.enabled then
        return false
    end
    if CONFIG.disableInChallenges and Isaac.GetChallenge() ~= Challenge.CHALLENGE_NULL then
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------

local redrawing = false

-- Remplace l'objet tiré dans un pool par son image dans la permutation
mod:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, function(_, selected, poolType, decrease, seed)
    if redrawing or selected <= 0 then
        return nil
    end
    ensureLoaded()
    if not isActive() then
        return nil
    end

    local target = state.collectibleMap[selected]
    if not target then
        return nil -- objet de progression ou non géré
    end

    -- Objet déjà obtenu pendant cette partie : on retire un autre objet du pool
    if state.run.collectibles[target] then
        local pool = game:GetItemPool()
        local rng = RNG()
        rng:SetSeed(seed ~= 0 and seed or 1, 35)
        local found = nil

        redrawing = true
        for _ = 1, MAX_REDRAW do
            local alt = pool:GetCollectible(poolType, true, rng:Next())
            local altTarget = state.collectibleMap[alt] or alt
            if not state.run.collectibles[altTarget] or PROGRESSION_COLLECTIBLES[altTarget] then
                found = altTarget
                break
            end
        end
        redrawing = false

        target = found or CollectibleType.COLLECTIBLE_BREAKFAST
    end

    if decrease then
        state.run.collectibles[target] = true
    end
    return target
end)

if CONFIG.shuffleTrinkets then
    mod:AddCallback(ModCallbacks.MC_GET_TRINKET, function(_, selected, rng)
        if selected <= 0 then
            return nil
        end
        ensureLoaded()
        if not isActive() then
            return nil
        end

        local golden = selected & TRINKET_GOLDEN_FLAG
        local base = selected & ~TRINKET_GOLDEN_FLAG
        local target = state.trinketMap[base]
        if target then
            return target | golden
        end
        return nil
    end)
end

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
    -- Recharger à chaque partie : le joueur peut avoir changé de slot de sauvegarde
    state.loaded = false
    load()
    if not isContinued then
        state.run.collectibles = {}
        save()
    end
end)

mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    if state.loaded then
        save()
    end
end)

mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
    if state.loaded then
        save()
    end
end)

---------------------------------------------------------------------------
-- Commandes console (touche ²/~ puis "rboi ...")
---------------------------------------------------------------------------

local function collectibleName(id)
    local cfg = Isaac.GetItemConfig():GetCollectible(id)
    return cfg and cfg.Name or ("#" .. tostring(id))
end

local HELP = [[
rboi                 : aide
rboi status          : état du mod et graine actuelle
rboi on | off        : activer / désactiver la randomisation
rboi seed <nombre>   : fixer la graine (prend effet immédiatement)
rboi reroll          : tirer une nouvelle graine au hasard
rboi map <id>        : objet obtenu à la place de l'objet <id>
rboi who <id>        : objet qu'il faut avoir débloqué pour obtenir <id>
rboi unlocked        : nombre d'objets accessibles avec vos déblocages]]

mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, function(_, cmd, params)
    if cmd ~= "rboi" then
        return
    end
    ensureLoaded()

    local args = {}
    for word in string.gmatch(params or "", "%S+") do
        args[#args + 1] = word
    end
    local sub = args[1]
    local num = tonumber(args[2] or "")

    if sub == nil or sub == "help" then
        print(HELP)
    elseif sub == "status" then
        say(string.format("%s | graine %d | actif dans cette partie : %s",
            state.enabled and "activé" or "désactivé", state.seed, tostring(isActive())))
    elseif sub == "on" or sub == "off" then
        state.enabled = (sub == "on")
        save()
        say(state.enabled and "Randomisation activée" or "Randomisation désactivée")
    elseif sub == "seed" and num then
        state.seed = math.floor(num)
        generate()
        save()
        say("Graine fixée à " .. state.seed)
    elseif sub == "reroll" then
        state.seed = newSeed()
        generate()
        save()
        say("Nouvelle graine : " .. state.seed)
    elseif sub == "map" and num then
        local target = state.collectibleMap[num]
        if target then
            say(collectibleName(num) .. " -> " .. collectibleName(target))
        else
            say(collectibleName(num) .. " n'est pas randomisé (progression ou inconnu)")
        end
    elseif sub == "who" and num then
        local source = state.collectibleInverse[num]
        if source then
            say("Pour obtenir " .. collectibleName(num) .. ", il faut avoir débloqué " .. collectibleName(source))
        else
            say(collectibleName(num) .. " n'est pas randomisé (progression ou inconnu)")
        end
    elseif sub == "unlocked" then
        local itemConfig = Isaac.GetItemConfig()
        local total, available = 0, 0
        for source in pairs(state.collectibleMap) do
            total = total + 1
            local cfg = itemConfig:GetCollectible(source)
            if cfg and select(2, pcall(cfg.IsAvailable, cfg)) == true then
                available = available + 1
            end
        end
        say(string.format("%d / %d objets randomisés accessibles", available, total))
    else
        print(HELP)
    end
end)

log("Chargé")
