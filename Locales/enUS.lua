local _, ns = ...

-- Keys are the English texts; missing translations fall back to the key.
ns.L = setmetatable({}, { __index = function(_, k) return k end })
-- (i18n) keys whose English text is shorter than the key
ns.L["%s %s (player and quest state)"] = "%s %s"
ns.L["done (turned in)"] = "done"
