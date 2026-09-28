-- Code partagé entre les deux moteurs (vanilla et REPENTOGON)

local json = require("json")

local M = {}

M.SAVE_VERSION = 2
M.TRINKET_GOLDEN_FLAG = TrinketType and TrinketType.TRINKET_GOLDEN_FLAG or 32768

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------

M.CONFIG = {
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
    -- Forcer le moteur vanilla même si REPENTOGON est installé
    forceVanillaBackend = false,
    -- Afficher à l'écran l'objet réellement obtenu quand un succès est débloqué (REPENTOGON)
    announceUnlocks = true,
}

-- Objets nécessaires à la progression : jamais randomisés.
-- IDs numériques (plutôt que les noms d'enum) pour éviter une clé nil si un
-- nom venait à changer entre deux versions du jeu.
M.PROGRESSION_COLLECTIBLES = {
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

M.PROGRESSION_TRINKETS = {
}

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------

function M.log(msg)
    Isaac.DebugString("[RandomBOI] " .. msg)
end

function M.say(msg)
    print("[RandomBOI] " .. msg)
    M.log(msg)
end

function M.isQuestItem(cfg)
    return ItemConfig.TAG_QUEST ~= nil and cfg:HasTags(ItemConfig.TAG_QUEST)
end

function M.maxCollectible()
    if M.CONFIG.includeModdedItems then
        return Isaac.GetItemConfig():GetCollectibles().Size - 1
    end
    return CollectibleType.NUM_COLLECTIBLES - 1
end

function M.maxTrinket()
    if M.CONFIG.includeModdedItems then
        return Isaac.GetItemConfig():GetTrinkets().Size - 1
    end
    return TrinketType.NUM_TRINKETS - 1
end

-- Objet de collection éligible à la randomisation (hors progression)
function M.isShufflableCollectible(id, cfg)
    return cfg ~= nil and not cfg.Hidden and not M.PROGRESSION_COLLECTIBLES[id] and not M.isQuestItem(cfg)
end

function M.isShufflableTrinket(id, cfg)
    return cfg ~= nil and not cfg.Hidden and not M.PROGRESSION_TRINKETS[id]
end

-- Groupe de permutation d'un objet (qualité / actif-passif)
function M.collectibleGroupKey(cfg)
    local quality = M.CONFIG.stratifyByQuality and (cfg.Quality or 0) or 0
    local kind = "item"
    if M.CONFIG.keepActivePassiveSplit then
        kind = (cfg.Type == ItemType.ITEM_ACTIVE) and "active" or "passive"
    end
    return kind .. ":" .. quality
end

function M.addToGroup(groups, key, id)
    groups[key] = groups[key] or {}
    table.insert(groups[key], id)
end

-- Mélange de Fisher-Yates avec le RNG du jeu (déterministe pour une graine donnée)
local function shuffle(list, rng)
    for i = #list, 2, -1 do
        local j = rng:RandomInt(i) + 1
        list[i], list[j] = list[j], list[i]
    end
end

function M.newRng(seed)
    local rng = RNG()
    rng:SetSeed(seed ~= 0 and seed or 1, 35)
    return rng
end

-- Construit une bijection sur les éléments de `groups` (table groupe -> liste d'IDs)
function M.buildMapping(groups, rng)
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

function M.newSeed()
    local seed = Random()
    if seed == 0 then
        seed = 1
    end
    return seed
end

function M.isChallengeBlocked()
    return M.CONFIG.disableInChallenges and Isaac.GetChallenge() ~= Challenge.CHALLENGE_NULL
end

function M.collectibleName(id)
    local cfg = Isaac.GetItemConfig():GetCollectible(id)
    return cfg and cfg.Name or ("#" .. tostring(id))
end

function M.trinketName(id)
    local cfg = Isaac.GetItemConfig():GetTrinket(id)
    return cfg and cfg.Name or ("#" .. tostring(id))
end

-- Liste <-> ensemble (json n'aime pas les tables à clés numériques creuses)
function M.setToList(set)
    local list = {}
    for id in pairs(set) do
        list[#list + 1] = id
    end
    return list
end

function M.listToSet(list)
    local set = {}
    for _, id in ipairs(list or {}) do
        set[id] = true
    end
    return set
end

---------------------------------------------------------------------------
-- Sauvegarde (données du mod, propres à chaque slot)
---------------------------------------------------------------------------

function M.loadData(mod)
    if not mod:HasData() then
        return nil
    end
    local ok, decoded = pcall(json.decode, mod:LoadData())
    if ok and type(decoded) == "table" then
        return decoded
    end
    return nil
end

function M.saveData(mod, data)
    data.version = M.SAVE_VERSION
    mod:SaveData(json.encode(data))
end

---------------------------------------------------------------------------
-- Commandes console (touche ²/~ puis "rboi ...")
---------------------------------------------------------------------------

local HELP = [[
rboi                 : aide
rboi status          : état du mod, moteur utilisé et graine actuelle
rboi on | off        : activer / désactiver la randomisation
rboi seed <nombre>   : fixer la graine (prend effet immédiatement)
rboi reroll          : tirer une nouvelle graine au hasard
rboi map <id>        : objet obtenu à la place de l'objet <id>
rboi who <id>        : ce qu'il faut débloquer pour obtenir <id>
rboi unlocked        : nombre d'objets randomisés accessibles]]

--[[
    `backend` doit fournir :
      name, ensureLoaded(), getSeed(), setSeed(seed), isEnabled(),
      setEnabled(bool), isActive(), describeMap(id), describeWho(id),
      describeUnlocked()
]]
function M.registerCommands(mod, backend)
    mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, function(_, cmd, params)
        if cmd ~= "rboi" then
            return
        end
        backend.ensureLoaded()

        local args = {}
        for word in string.gmatch(params or "", "%S+") do
            args[#args + 1] = word
        end
        local sub = args[1]
        local num = tonumber(args[2] or "")

        if sub == "status" then
            M.say(string.format("moteur %s | %s | graine %d | actif dans cette partie : %s",
                backend.name, backend.isEnabled() and "activé" or "désactivé",
                backend.getSeed(), tostring(backend.isActive())))
        elseif sub == "on" or sub == "off" then
            backend.setEnabled(sub == "on")
            M.say(backend.isEnabled() and "Randomisation activée" or "Randomisation désactivée")
        elseif sub == "seed" and num then
            backend.setSeed(math.floor(num))
            M.say("Graine fixée à " .. backend.getSeed())
        elseif sub == "reroll" then
            backend.setSeed(M.newSeed())
            M.say("Nouvelle graine : " .. backend.getSeed())
        elseif sub == "map" and num then
            M.say(backend.describeMap(math.floor(num)))
        elseif sub == "who" and num then
            M.say(backend.describeWho(math.floor(num)))
        elseif sub == "unlocked" then
            M.say(backend.describeUnlocked())
        else
            print(HELP)
        end
    end)
end

return M
