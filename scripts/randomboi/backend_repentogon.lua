--[[
    Moteur REPENTOGON

    REPENTOGON donne accès aux succès (PersistentGameData) et au contenu brut
    des pools (ItemPool:PickCollectible). On randomise donc les vrais
    déblocages :

      - Chaque objet verrouillé par un succès (attribut "achievement" de
        items.xml / pocketitems.xml) est associé à un autre objet verrouillé
        par une permutation f.
      - Le succès qui débloque normalement X débloque f(X) à la place.
      - Les objets disponibles dès le début ne changent pas.
      - Les tirages respectent les pools : f(X) n'apparaît que dans ses
        propres pools (Devil Room, trésor, shop...), avec ses propres poids.

    Le fichier de sauvegarde n'est jamais modifié : désactiver le mod rend les
    déblocages d'origine.
]]

local MAX_PICKS = 40
local MAX_REDRAW = 20

-- Effets qui modifient la logique interne de GetCollectible : on laisse
-- alors le jeu tirer lui-même et on corrige seulement le résultat.
local VANILLA_ONLY_COLLECTIBLES = {
    402, -- Chaos
    691, -- Sacred Orb
    721, -- TMTRAINER
}

return function(mod, C)
    local game = Game()
    local B = { name = "REPENTOGON" }

    local state = {
        loaded = false,
        enabled = true,
        seed = nil,

        itemAch = {}, -- objet X -> succès qui le débloque normalement
        map = {}, -- X -> f(X)
        inverse = {}, -- f(X) -> X
        virtualAch = {}, -- Y -> succès qui débloque Y dans le mod
        achToItems = {}, -- succès -> { X, ... }

        trinketAch = {},
        trinketMap = {},
        trinketInverse = {},
        achToTrinkets = {},

        -- Objets retirés des pools par le mod pendant la partie en cours,
        -- à remettre si leur succès est débloqué en cours de partie
        runRemoved = {},
    }

    local function pgd()
        return Isaac.GetPersistentGameData()
    end

    local function isUnlocked(ach)
        return pgd():Unlocked(ach)
    end

    local function achievementOf(node, id)
        local entry = XMLData.GetEntryById(node, id)
        if not entry then
            return nil
        end
        local raw = entry.achievement
        local ach = tonumber(raw)
        if not ach and type(raw) == "string" and raw ~= "" then
            ach = Isaac.GetAchievementIdByName(raw)
        end
        if ach and ach > 0 then
            return ach
        end
        return nil
    end

    local function achievementName(ach)
        local entry = XMLData.GetEntryById(XMLNode.ACHIEVEMENT, ach)
        local name = entry and (entry.name or entry.text or entry.steam_name)
        if name and name ~= "" then
            return string.format("#%d \"%s\"", ach, name)
        end
        return "#" .. tostring(ach)
    end

    local function append(tbl, key, value)
        tbl[key] = tbl[key] or {}
        table.insert(tbl[key], value)
    end

    ---------------------------------------------------------------------------
    -- Génération
    ---------------------------------------------------------------------------

    local function generate()
        local itemConfig = Isaac.GetItemConfig()
        local rng = C.newRng(state.seed)

        -- Objets de collection
        state.itemAch = {}
        local groups = {}
        for id = 1, C.maxCollectible() do
            local cfg = itemConfig:GetCollectible(id)
            if C.isShufflableCollectible(id, cfg) then
                local ach = achievementOf(XMLNode.ITEM, id)
                if ach then
                    state.itemAch[id] = ach
                    C.addToGroup(groups, C.collectibleGroupKey(cfg), id)
                end
            end
        end
        state.map, state.inverse = C.buildMapping(groups, rng)

        state.virtualAch, state.achToItems = {}, {}
        for source, target in pairs(state.map) do
            local ach = state.itemAch[source]
            state.virtualAch[target] = ach
            append(state.achToItems, ach, source)
        end

        -- Trinkets
        state.trinketAch, state.trinketMap, state.trinketInverse, state.achToTrinkets = {}, {}, {}, {}
        if C.CONFIG.shuffleTrinkets then
            local trinkets = {}
            for id = 1, C.maxTrinket() do
                if C.isShufflableTrinket(id, itemConfig:GetTrinket(id)) then
                    local ach = achievementOf(XMLNode.TRINKET, id)
                    if ach then
                        state.trinketAch[id] = ach
                        C.addToGroup(trinkets, "trinket", id)
                    end
                end
            end
            state.trinketMap, state.trinketInverse = C.buildMapping(trinkets, rng)
            for source in pairs(state.trinketMap) do
                append(state.achToTrinkets, state.trinketAch[source], source)
            end
        end

        C.log("Permutation REPENTOGON générée (seed " .. state.seed .. ")")
    end

    -- true / false si l'objet est géré par la randomisation, nil sinon
    local function virtuallyAvailable(id)
        local ach = state.virtualAch[id]
        if ach then
            return isUnlocked(ach)
        end
        return nil
    end

    ---------------------------------------------------------------------------
    -- Sauvegarde
    ---------------------------------------------------------------------------

    local function save()
        C.saveData(mod, {
            seed = state.seed,
            enabled = state.enabled,
            runRemoved = C.setToList(state.runRemoved),
        })
    end

    local function load()
        local data = C.loadData(mod)
        if data and data.seed then
            state.seed = data.seed
            state.enabled = data.enabled ~= false
            state.runRemoved = C.listToSet(data.runRemoved)
        else
            state.seed = C.newSeed()
            state.enabled = true
            state.runRemoved = {}
            C.say("Nouvelle graine de randomisation : " .. state.seed)
        end
        generate()
        state.loaded = true
        save()
    end

    function B.ensureLoaded()
        if not state.loaded then
            load()
        end
    end

    function B.isActive()
        return state.enabled and not C.isChallengeBlocked()
    end

    local function vanillaOnly()
        for _, id in ipairs(VANILLA_ONLY_COLLECTIBLES) do
            if PlayerManager.AnyoneHasCollectible(id) then
                return true
            end
        end
        return false
    end

    ---------------------------------------------------------------------------
    -- Tirage des objets
    ---------------------------------------------------------------------------

    local busy = false

    -- Tirage principal : on pioche nous-mêmes dans le pool (poids d'origine)
    -- en acceptant les objets débloqués "virtuellement", même s'ils sont
    -- verrouillés dans la sauvegarde.
    mod:AddCallback(ModCallbacks.MC_PRE_GET_COLLECTIBLE, function(_, poolType, decrease, seed)
        if busy then
            return nil
        end
        B.ensureLoaded()
        if not B.isActive() or vanillaOnly() then
            return nil
        end

        local pool = game:GetItemPool()
        local rng = C.newRng(seed)
        local blacklist = pool:GetRoomBlacklistedCollectibles() or {}

        for _ = 1, MAX_PICKS do
            local pick = pool:PickCollectible(poolType, false, rng)
            if not pick then
                break -- pool vide : le jeu gère le repli (pool trésor, Breakfast)
            end
            local id = pick.itemID
            if id and id > 0 and not blacklist[id] then
                local available = virtuallyAvailable(id)
                if available == nil then
                    available = pick.isUnlocked
                end
                if available and pool:CanSpawnCollectible(id, true) then
                    if decrease then
                        pool:RemoveCollectible(id)
                        pool:SetLastPool(poolType)
                    end
                    return id
                end
            end
            rng:Next()
        end
        return nil
    end)

    -- Filet de sécurité : si le jeu a tiré lui-même (Chaos, TMTRAINER, repli...)
    -- un objet verrouillé dans la randomisation, on le retire et on retire.
    mod:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, function(_, selected, poolType, decrease, seed)
        if busy or selected <= 0 then
            return nil
        end
        B.ensureLoaded()
        if not B.isActive() or virtuallyAvailable(selected) ~= false then
            return nil
        end

        local pool = game:GetItemPool()
        local rng = C.newRng(seed)
        local result = CollectibleType.COLLECTIBLE_BREAKFAST

        busy = true
        for _ = 1, MAX_REDRAW do
            pool:RemoveCollectible(selected)
            state.runRemoved[selected] = true
            selected = pool:GetCollectible(poolType, decrease, rng:Next())
            if selected <= 0 or virtuallyAvailable(selected) ~= false then
                result = selected
                break
            end
        end
        busy = false

        return result
    end)

    -- Trinkets : le pool ne renvoie que des trinkets débloqués, donc tirer T
    -- signifie que le succès de T est obtenu, ce qui donne accès à f(T).
    mod:AddCallback(ModCallbacks.MC_GET_TRINKET, function(_, selected)
        if not C.CONFIG.shuffleTrinkets or selected <= 0 then
            return nil
        end
        B.ensureLoaded()
        if not B.isActive() then
            return nil
        end

        local golden = selected & C.TRINKET_GOLDEN_FLAG
        local target = state.trinketMap[selected & ~C.TRINKET_GOLDEN_FLAG]
        if target then
            return target | golden
        end
        return nil
    end)

    ---------------------------------------------------------------------------
    -- Déblocages
    ---------------------------------------------------------------------------

    mod:AddCallback(ModCallbacks.MC_POST_ACHIEVEMENT_UNLOCK, function(_, ach)
        B.ensureLoaded()
        local unlocked = {}

        for _, source in ipairs(state.achToItems[ach] or {}) do
            local target = state.map[source]
            if state.runRemoved[target] then
                game:GetItemPool():ResetCollectible(target)
                state.runRemoved[target] = nil
            end
            unlocked[#unlocked + 1] = { C.collectibleName(target), C.collectibleName(source) }
        end
        for _, source in ipairs(state.achToTrinkets[ach] or {}) do
            local target = state.trinketMap[source]
            unlocked[#unlocked + 1] = { C.trinketName(target), C.trinketName(source) }
        end

        for _, names in ipairs(unlocked) do
            C.say("Déblocage : " .. names[1] .. " (à la place de " .. names[2] .. ")")
            if C.CONFIG.announceUnlocks and state.enabled then
                pcall(function()
                    game:GetHUD():ShowItemText("Débloqué : " .. names[1], "à la place de " .. names[2])
                end)
            end
        end
        save()
    end)

    ---------------------------------------------------------------------------
    -- Chargement / partie
    ---------------------------------------------------------------------------

    mod:AddCallback(ModCallbacks.MC_POST_SAVESLOT_LOAD, function(_, _slot, _isSelected, rawSlot)
        -- rawSlot 0 : slot par défaut avant sélection, données non synchronisées
        if rawSlot ~= 0 then
            state.loaded = false
            load()
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
        B.ensureLoaded()
        if not isContinued then
            state.runRemoved = {}
            save()
        end
    end)

    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
        if state.loaded then
            save()
        end
    end)

    ---------------------------------------------------------------------------
    -- API pour les commandes console
    ---------------------------------------------------------------------------

    function B.getSeed()
        return state.seed
    end

    function B.setSeed(seed)
        state.seed = seed
        generate()
        save()
    end

    function B.isEnabled()
        return state.enabled
    end

    function B.setEnabled(enabled)
        state.enabled = enabled
        save()
    end

    function B.describeMap(id)
        local target = state.map[id]
        if target then
            return string.format("Le succès %s donne %s au lieu de %s",
                achievementName(state.itemAch[id]), C.collectibleName(target), C.collectibleName(id))
        end
        if C.PROGRESSION_COLLECTIBLES[id] then
            return C.collectibleName(id) .. " est un objet de progression : jamais randomisé"
        end
        return C.collectibleName(id) .. " n'est verrouillé par aucun succès : inchangé"
    end

    function B.describeWho(id)
        local ach = state.virtualAch[id]
        if ach then
            return string.format("%s est débloqué par le succès %s (qui donnait %s) : %s",
                C.collectibleName(id), achievementName(ach), C.collectibleName(state.inverse[id]),
                isUnlocked(ach) and "obtenu" or "pas encore obtenu")
        end
        return B.describeMap(id)
    end

    function B.describeUnlocked()
        local total, available = 0, 0
        for _, ach in pairs(state.virtualAch) do
            total = total + 1
            if isUnlocked(ach) then
                available = available + 1
            end
        end
        return string.format("%d / %d objets randomisés débloqués", available, total)
    end

    return B
end
