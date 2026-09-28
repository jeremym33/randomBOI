--[[
    RandomBOI - Unlock Randomizer
    The Binding of Isaac: Repentance+

    Deux moteurs :
      - REPENTOGON (recommandé) : randomise les vrais succès et respecte les pools.
      - vanilla (repli) : permutation virtuelle des objets, sans accès aux succès.
    Voir le README pour le détail.
]]

local mod = RegisterMod("RandomBOI", 1)
local C = include("scripts.randomboi.common")

local backend
if REPENTOGON and not C.CONFIG.forceVanillaBackend then
    backend = include("scripts.randomboi.backend_repentogon")(mod, C)
else
    backend = include("scripts.randomboi.backend_vanilla")(mod, C)
end

C.registerCommands(mod, backend)

C.log("Chargé (moteur " .. backend.name .. ")")
