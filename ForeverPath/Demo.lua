local _, NS = ...
-- SYNTHETIC FIXTURE. These are invented examples, never game records.
NS.Demo = {
    targets = { "demo-chain", "demo-craft", "demo-detour" },
    state = { level = 15, faction = "Alliance", profile = "strength", goal = "balanced", gold = 2,
        grouped = false, professions = { Blacksmithing = 75 }, completed = {},
        equipped = { chest = { ITEM_MOD_STRENGTH_SHORT = 2, ITEM_MOD_STAMINA_SHORT = 2 } } },
    graph = {
        ["demo-start"] = { title = "Demo: prepare the expedition", kind = "quest", requires = {},
            minutes = 8, costGold = 0, xp = 400, dependenciesKnown = true, rewardsKnown = true, evidence = "synthetic" },
        ["demo-chain"] = { title = "Finish a quest chain", kind = "quest", requires = { "demo-start" },
            minutes = 12, costGold = 0, xp = 900, minLevel = 12, faction = "Alliance",
            dependenciesKnown = true, rewardsKnown = true, downstreamKnown = true, evidence = "synthetic",
            choices = { { slot = "chest", stats = { ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 4 } },
                { slot = "chest", stats = { ITEM_MOD_INTELLECT_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 4 } } } },
        ["demo-craft"] = { title = "Craft an alternative chest", kind = "craft", requires = {},
            minutes = 5, costGold = 1.5, xp = 0, profession = "Blacksmithing", skill = 60,
            dependenciesKnown = true, rewardsKnown = true, downstreamKnown = true, evidence = "synthetic",
            rewards = { { slot = "chest", stats = { ITEM_MOD_STRENGTH_SHORT = 6, ITEM_MOD_STAMINA_SHORT = 3 } } } },
        ["demo-detour"] = { title = "Take an uncertain detour", kind = "quest", requires = {},
            minutes = 25, xp = 200, costGold = 0, dependenciesKnown = false, rewardsKnown = false, evidence = "synthetic" },
    }
}
