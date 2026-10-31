local _, ns = ...

-- Keys are the English texts; missing translations fall back to the key.
ns.L = ns.L or setmetatable({}, { __index = function(_, k) return k end }) -- (L3) DonData/Engine/Locale.lua may have made it
-- (i18n) keys whose English text is shorter than the key
ns.L["%s %s (player and quest state)"] = "%s %s"
ns.L["done (turned in)"] = "done"
ns.L["ready (quest to turn in)"] = "ready"
ns.L["on"] = "on" -- (17.10.) setup window
