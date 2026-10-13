--[[
    Moteur vanilla (sans REPENTOGON)

    L'API officielle ne permet ni de lire les succès ni de lire le contenu des
    pools. On applique donc une permutation "virtuelle" sur tous les objets :

        objet réellement débloqué X  ->  objet obtenu f(X)

    Chaque fois qu'un pool renvoie X (ce qui n'arrive que si X est débloqué),
    X est remplacé par f(X). Limite : f(X) peut venir d'un autre pool que X.
]]

local MAX_REDRAW = 20

return function(mod, C)
    local game = Game()
    local B = { name = "vanilla" }

    local state = {
        loaded = false,
        enabled = true,
        seed = nil,
        collectibleMap = {}, -- réel -> obtenu
        collectibleInverse = {}, -- obtenu -> réel
        trinketMap = {},
        runGiven = {}, -- objets déjà donnés pendant la partie en cours
    }

    local function generate()
        local itemConfig = Isaac.GetItemConfig()
        local rng = C.newRng(state.seed)

        local groups = {}
        for id = 1, C.maxCollectible() do
            local cfg = itemConfig:GetCollectible(id)
            if C.isShufflableCollectible(id, cfg) then
                C.addToGroup(groups, C.collectibleGroupKey(cfg), id)
            end
        end
        state.collectibleMap, state.collectibleInverse = C.buildMapping(groups, rng)

        state.trinketMap = {}
        if C.CONFIG.shuffleTrinkets then
            local trinkets = {}
            for id = 1, C.maxTrinket() do
                if C.isShufflableTrinket(id, itemConfig:GetTrinket(id)) then
                    C.addToGroup(trinkets, "trinket", id)
                end
            end
            state.trinketMap = C.buildMapping(trinkets, rng)
        end
        C.log("Permutation vanilla générée (seed " .. state.seed .. ")")
    end

    local function save()
        C.saveData(mod, {
            seed = state.seed,
            enabled = state.enabled,
            runGiven = C.setToList(state.runGiven),
        })
    end

    local function load()
        local data = C.loadData(mod)
        if data and data.seed then
            state.seed = data.seed
            state.enabled = data.enabled ~= false
            state.runGiven = C.listToSet(data.runGiven)
        else
            state.seed = C.newSeed()
            state.enabled = true
            state.runGiven = {}
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

    ---------------------------------------------------------------------------
    -- Callbacks
    ---------------------------------------------------------------------------

    local redrawing = false

    mod:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, function(_, selected, poolType, decrease, seed)
        if redrawing or selected <= 0 then
            return nil
        end
        B.ensureLoaded()
        if not B.isActive() then
            return nil
        end

        local target = state.collectibleMap[selected]
        if not target then
            return nil -- objet de progression ou non géré
        end

        -- Objet déjà obtenu pendant cette partie : on retire un autre objet du pool
        if state.runGiven[target] then
            local pool = game:GetItemPool()
            local rng = C.newRng(seed)
            local found = nil

            redrawing = true
            for _ = 1, MAX_REDRAW do
                local alt = pool:GetCollectible(poolType, true, rng:Next())
                local altTarget = state.collectibleMap[alt] or alt
                if not state.runGiven[altTarget] or C.PROGRESSION_COLLECTIBLES[altTarget] then
                    found = altTarget
                    break
                end
            end
            redrawing = false

            target = found or CollectibleType.COLLECTIBLE_BREAKFAST
        end

        if decrease then
            state.runGiven[target] = true
        end
        return target
    end)

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

    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
        -- Recharger à chaque partie : le joueur peut avoir changé de slot de sauvegarde
        state.loaded = false
        load()
        if not isContinued then
            state.runGiven = {}
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
        local target = state.collectibleMap[id]
        if target then
            return C.collectibleName(id) .. " -> " .. C.collectibleName(target)
        end
        return C.collectibleName(id) .. " n'est pas randomisé (progression ou inconnu)"
    end

    function B.describeWho(id)
        local source = state.collectibleInverse[id]
        if source then
            return "Pour obtenir " .. C.collectibleName(id) .. ", il faut avoir débloqué " .. C.collectibleName(source)
        end
        return C.collectibleName(id) .. " n'est pas randomisé (progression ou inconnu)"
    end

    function B.describeUnlocked()
        local itemConfig = Isaac.GetItemConfig()
        local total, available = 0, 0
        for source in pairs(state.collectibleMap) do
            total = total + 1
            local cfg = itemConfig:GetCollectible(source)
            if cfg and select(2, pcall(cfg.IsAvailable, cfg)) == true then
                available = available + 1
            end
        end
        return string.format("%d / %d objets randomisés accessibles", available, total)
    end

    return B
end
