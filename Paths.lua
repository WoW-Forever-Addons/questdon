local _, ns = ...

---------------------------------------------------------------------------
-- (1.3.6, Daniel 11.10.: "the arrow goes in a straight line; with mountains in the way I have to run
-- around") Ways around mountains for the arrow. Each zone map is a grid of N x N cells:
--   walked cells (where you or the shipped recordings went: surely walkable) cost WALKED,
--   mountain cells (only zones checked by hand on Forever's map art, Data/Paths.lua) cost ROCK,
--   everything else 1.
-- The cheapest way (A*) from you to the arrow's target becomes a few waypoints; the arrow points at the
-- next one. Where nothing is known, or the way is not better than the straight line, nothing changes.
---------------------------------------------------------------------------
local N = ns.PATH_N or 100
local ROCK, WALKED, OPEN = 12, 0.35, 1
local RECORD_EVERY = 2      -- seconds between notes of where you walk
local REACHED = 20          -- yards: a waypoint counts as reached
local RECALC = 1.5          -- seconds at least between two calculations
local OFF_WAY = 3           -- cells away from the way: calculate again

local rockCache, seedCache = {}, {}
local InsideCost

-- Data/Paths.lua: rock as run lengths (base 36, two characters each, starting with open cells),
-- walked cells as base 36 numbers of three characters
local function Rock(m)
  local c = rockCache[m]
  if c ~= nil then return c or nil end
  local s = ns.PATH_ROCK and ns.PATH_ROCK[m]
  if type(s) ~= "string" then rockCache[m] = false return nil end
  c = {}
  local cell, isRock = 0, false
  for i = 1, #s - 1, 2 do
    local n = tonumber(s:sub(i, i + 1), 36) or 0
    if isRock then for k = cell, cell + n - 1 do c[k] = true end end
    cell = cell + n
    isRock = not isRock
  end
  rockCache[m] = c
  return c
end
local function Seed(m)
  local c = seedCache[m]
  if c ~= nil then return c or nil end
  local s = ns.PATH_WALKED and ns.PATH_WALKED[m]
  if type(s) ~= "string" then seedCache[m] = false return nil end
  c = {}
  for i = 1, #s - 2, 3 do
    local n = tonumber(s:sub(i, i + 2), 36)
    if n then c[n] = true end
  end
  seedCache[m] = c
  return c
end
local function Walked(m)
  local w = type(ns.db.walked) == "table" and ns.db.walked[m]
  return type(w) == "table" and w or nil
end

-- (11.10., Daniel: "the quest deep in the cave: following the arrow I would have run into the mountain outside")
-- the inside of caves and buildings: cell -> the cell of its way in. Shipped (Data/Paths.lua PATH_INSIDE:
-- six base 36 characters per cell, the cell and its way in, from Leveldon recordings) and your own
-- (ns.db.insides, noted while IsIndoors() says you are inside)
local insideCache, mergedInside = {}, {}
local function Inside(m)
  local c = insideCache[m]
  if c == nil then
    c = false
    local s = ns.PATH_INSIDE and ns.PATH_INSIDE[m]
    if type(s) == "string" then
      c = {}
      for i = 1, #s - 5, 6 do
        local cell, way = tonumber(s:sub(i, i + 2), 36), tonumber(s:sub(i + 3, i + 5), 36)
        if cell and way then c[cell] = way end
      end
    end
    insideCache[m] = c
  end
  local own = type(ns.db.insides) == "table" and type(ns.db.insides[m]) == "table" and ns.db.insides[m] or nil
  if not c and not own then return nil end
  if not own then return c end
  if not c then return own end
  -- (16.10. late, /qd mem) the merged view kept while both tables are the same (it was made at every arrow update)
  local mv = mergedInside[m]
  if mv and mv.own == own and mv.c == c then return mv.view end
  local view = setmetatable({}, { __index = function(_, k) local v = own[k] if v == nil then v = c[k] end return v end })
  mergedInside[m] = { own = own, c = c, view = view }
  return view
end
local NEIGHBOURS -- the 8 neighbour offsets of a cell (made once)
local function InsideOf(ins, c, outside)
  if not (ins and c) then return nil end
  if ins[c] then return ins[c] end
  -- a neighbour cell counts (an objective spot a little off the walked cells), not when you walked this very
  -- cell outside (an NPC by the wall of a house)
  if outside and outside(c) then return nil end
  local N_ = ns.PATH_N or 100
  if not NEIGHBOURS or NEIGHBOURS.n ~= N_ then NEIGHBOURS = { -1, 1, -N_, N_, -N_ - 1, -N_ + 1, N_ - 1, N_ + 1, n = N_ } end
  for i = 1, 8 do
    local d = NEIGHBOURS[i]
    if ins[c + d] then return ins[c + d] end
  end
  return nil
end
local function Indoors() return IsIndoors ~= nil and ns.True(ns.Value(IsIndoors)) or false end
-- walked cells that are not inside anything: surely outside
local outsideFn = {} -- [m] = { ins, seed, own, fn } (16.10.: the same function while its tables are the same)
local function Outside(m, ins)
  local seed, own = Seed(m), Walked(m)
  local o = outsideFn[m]
  if o and o.ins == ins and o.seed == seed and o.own == own then return o.fn end
  local fn = function(c)
    if ins and ins[c] then return false end
    return (seed and seed[c]) or (own and own[c]) or false
  end
  outsideFn[m] = { ins = ins, seed = seed, own = own, fn = fn }
  return fn
end

local function Cell(x, y) -- x, y 0-1
  local i, j = math.floor(x * N), math.floor(y * N)
  if i < 0 or j < 0 or i >= N or j >= N then return nil end
  return j * N + i
end
local function Center(c) return ((c % N) + 0.5) / N, (math.floor(c / N) + 0.5) / N end
ns.PathCell, ns.PathCenter = Cell, Center -- (tests)

local function CostFn(m)
  local rock, seed, own = Rock(m), Seed(m), Walked(m)
  local shared = ns.SharedWalked and ns.SharedWalked(m)
  if not (rock or seed or own or shared) then return nil end
  return function(c)
    if (own and own[c]) or (seed and seed[c]) or (shared and shared[c]) then return WALKED end
    if rock and rock[c] then return ROCK end
    return OPEN
  end
end

-- A* over the cells (8 neighbours); returns the cells from a to b and the cost
local function AStar(cost, a, b)
  local heap, hn = {}, 0
  local function push(f, c)
    hn = hn + 1
    local i = hn
    heap[i] = { f, c }
    while i > 1 do
      local p = math.floor(i / 2)
      if heap[p][1] <= heap[i][1] then break end
      heap[p], heap[i] = heap[i], heap[p]
      i = p
    end
  end
  local function pop()
    local top = heap[1]
    heap[1] = heap[hn]
    heap[hn] = nil
    hn = hn - 1
    local i = 1
    while true do
      local l, r, s = i * 2, i * 2 + 1, i
      if l <= hn and heap[l][1] < heap[s][1] then s = l end
      if r <= hn and heap[r][1] < heap[s][1] then s = r end
      if s == i then break end
      heap[s], heap[i] = heap[i], heap[s]
      i = s
    end
    return top
  end
  local bx, by = b % N, math.floor(b / N)
  local function h(c)
    local dx, dy = math.abs(c % N - bx), math.abs(math.floor(c / N) - by)
    return (math.max(dx, dy) + 0.414 * math.min(dx, dy)) * WALKED
  end
  local g, from, closed = { [a] = 0 }, {}, {}
  push(h(a), a)
  local steps = 0
  while hn > 0 do
    local top = pop()
    local c = top[2]
    if c == b then break end
    if not closed[c] then
      closed[c] = true
      steps = steps + 1
      if steps > N * N then return nil end
      local cx, cy = c % N, math.floor(c / N)
      local cc = cost(c)
      for dy = -1, 1 do
        for dx = -1, 1 do
          if dx ~= 0 or dy ~= 0 then
            local nx, ny = cx + dx, cy + dy
            if nx >= 0 and ny >= 0 and nx < N and ny < N then
              local n = ny * N + nx
              if not closed[n] then
                local step = ((dx ~= 0 and dy ~= 0) and 1.414 or 1) * (cc + cost(n)) / 2
                local ng = g[c] + step
                if not g[n] or ng < g[n] then
                  g[n] = ng
                  from[n] = c
                  push(ng + h(n), n)
                end
              end
            end
          end
        end
      end
    end
  end
  if not g[b] then return nil end
  local path, c = {}, b
  while c do
    table.insert(path, 1, c)
    c = from[c]
  end
  return path, g[b]
end

ns.PathAStar = function(m, a, b) local c = CostFn(m) if c then return AStar(c, a, b) end end -- (tests)
ns.PathCost = function(m, c) local f = CostFn(m) return f and f(c) end -- (tests)

-- the cost of the straight line between two cells, cell by cell
local function LineCost(cost, a, b)
  local ax, ay, bx, by = a % N, math.floor(a / N), b % N, math.floor(b / N)
  local n = math.max(math.abs(bx - ax), math.abs(by - ay), 1)
  local sum, last = 0, nil
  for k = 0, n do
    local c = math.floor(ay + (by - ay) * k / n + 0.5) * N + math.floor(ax + (bx - ax) * k / n + 0.5)
    if c ~= last then sum = sum + cost(c) last = c end
  end
  return sum * math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) / math.max(1, n)
end

-- (11.10., Daniel: a way around in the open Coldridge Valley) is there a mountain cell on the straight line?
-- Walked cells only choose between ways around mountains; without a mountain in the way the arrow goes straight
local function LineHasRock(cost, a, b)
  local ax, ay, bx, by = a % N, math.floor(a / N), b % N, math.floor(b / N)
  local n = math.max(math.abs(bx - ax), math.abs(by - ay), 1)
  -- the cells in between (you may stand on a mesa drawn as mountain, the NPC too)
  for k = 1, n - 1 do
    local c = math.floor(ay + (by - ay) * k / n + 0.5) * N + math.floor(ax + (bx - ax) * k / n + 0.5)
    if cost(c) >= ROCK then return true end
  end
  return false
end

-- the fewest waypoints: from each point the farthest later cell of the way whose straight line costs
-- not more than the way between them (a little slack)
local function Waypoints(cost, path)
  local out, i = {}, 1
  local pre = { 0 }
  for k = 2, #path do
    local a, b = path[k - 1], path[k]
    local diag = (a % N ~= b % N) and (math.floor(a / N) ~= math.floor(b / N))
    pre[k] = pre[k - 1] + (diag and 1.414 or 1) * (cost(a) + cost(b)) / 2
  end
  while i < #path do
    local j = #path
    while j > i + 1 and LineCost(cost, path[i], path[j]) > (pre[j] - pre[i]) * 1.1 + 0.5 do j = j - 1 end
    out[#out + 1] = path[j]
    i = j
  end
  return out
end

-- The way for a target: waypoints { cell, ... } or nil (straight is as good)
function ns.PathFor(m, fromX, fromY, toX, toY)
  local cost = CostFn(m)
  if not cost then return nil end
  local a, b = Cell(fromX, fromY), Cell(toX, toY)
  if not (a and b) or a == b then return nil end
  if not LineHasRock(cost, a, b) then return nil end
  local path, total = AStar(cost, a, b)
  if not path then return nil end
  local straight = LineCost(cost, a, b)
  if total >= straight * 0.9 then return nil end
  local wps = Waypoints(cost, path)
  if #wps < 2 then return nil end
  return wps
end

-- inside a cave: its walked cells are cheap, everything else (rock between the tunnels) dear
local INSIDE_WALL = 30
InsideCost = function(ins, way)
  return function(c) if ins[c] == way then return WALKED end return INSIDE_WALL end
end
function ns.PathInside(m, fromX, fromY, toX, toY, way)
  local ins = Inside(m)
  if not ins then return nil end
  local cost = InsideCost(ins, way)
  local a, b = Cell(fromX, fromY), Cell(toX, toY)
  if not (a and b) or a == b then return nil end
  local path = AStar(cost, a, b)
  if not path then return nil end
  local wps = Waypoints(cost, path)
  if #wps < 2 then return nil end
  return wps
end
-- The target lies inside a cave or building you are not in: its way in ({ mapID, x, y }, reached with the way
-- around mountains if there is one), or nil
function ns.PathCave(t)
  if not (t and t.mapID and t.x and t.y) or ns.db.arrowPaths == false then return nil end
  local m, px, py = ns.PlayerPosition()
  if m ~= t.mapID or not px then return nil end
  local ins = Inside(m)
  local way = InsideOf(ins, Cell(t.x, t.y), Outside(m, ins))
  if not way then return nil end
  if Indoors() and InsideOf(ins, Cell(px, py)) == way then return nil end
  local ex, ey = Center(way)
  local e = { mapID = m, x = ex, y = ey }
  local d = ns.DistanceAndBearing(e)
  if d and d <= REACHED then return nil end
  return ns.PathNext(e) or e
end

-- The arrow's next point on the way to target t ({ mapID, x, y } 0-1), or nil for the straight line
local state = { key = nil, wps = nil, at = -1e9 }
local function Now() return ns.Num(ns.Value(GetTime)) or 0 end
-- (23.10., Daniel's /qd mem with Leveldon's target: arrow 15 KB a second at 27 calls) no closure per call (Recalc
-- was one, with eight upvalues), one probe table for the reached check, and the answer table kept while the
-- waypoint stays the same (a new table only when the way moves on)
local function Recalc(now, key, inside, m, px, py, t, tway)
  if now - state.at < RECALC and state.key == key then return end
  state.key, state.at = key, now
  local ok, wps
  if inside then ok, wps = pcall(ns.PathInside, m, px, py, t.x, t.y, tway) else ok, wps = pcall(ns.PathFor, m, px, py, t.x, t.y) end
  state.wps = ok and wps or nil
end
local probe = {}
local function Answer(m, cell, wx, wy)
  local o = state.out
  if not (o and o.mapID == m and state.outCell == cell) then
    o = { mapID = m, x = wx, y = wy }
    state.out, state.outCell = o, cell
  end
  return o
end
function ns.PathNext(t)
  if not (t and t.mapID and t.x and t.y) or ns.db.arrowPaths == false then return nil end
  local m, px, py = ns.PlayerPosition()
  if m ~= t.mapID or not px then return nil end
  local me = Cell(px, py)
  -- inside the same cave or building as the target: along the cells walked inside
  local ins = Inside(m)
  local tway = InsideOf(ins, Cell(t.x, t.y), Outside(m, ins))
  local inside = tway and Indoors() and InsideOf(ins, me) == tway
  local key = ("%d:%.3f:%.3f:%s"):format(t.mapID, t.x, t.y, inside and "in" or "out")
  local now = Now()
  if state.key ~= key then Recalc(now, key, inside, m, px, py, t, tway) end
  local wps = state.wps
  if not wps then return nil end
  -- reached waypoints go; the last one is the target itself (the arrow takes it from there)
  while #wps > 1 do
    local wx, wy = Center(wps[1])
    probe.mapID, probe.x, probe.y = m, wx, wy
    local d = ns.DistanceAndBearing(probe)
    if d and d <= REACHED then table.remove(wps, 1) else break end
  end
  if #wps <= 1 then return nil end
  -- (11.10., Daniel: "when I am already closer than the waypoint it showed, can't it jump on?") from where you
  -- stand: the farthest point of the way (the target too) you reach straight without a mountain in between.
  -- (Not simply "closer to the target than the waypoint": a ramp may lead away from the target first.)
  if state.me ~= me then
    state.me = me
    local cost = inside and InsideCost(ins, tway) or CostFn(m)
    if cost then
      for k = #wps, 2, -1 do
        if not LineHasRock(cost, me, wps[k]) then
          for _ = 1, k - 1 do table.remove(wps, 1) end
          break
        end
      end
    end
    if #wps <= 1 then return nil end
  end
  -- far off the way: a new way
  local wx, wy = Center(wps[1])
  local cx, cy = me % N, math.floor(me / N)
  local tx, ty = wps[1] % N, math.floor(wps[1] / N)
  if math.max(math.abs(cx - tx), math.abs(cy - ty)) > OFF_WAY * 6 then
    Recalc(now, key, inside, m, px, py, t, tway)
    wps = state.wps
    if not wps or #wps <= 1 then return nil end
    wx, wy = Center(wps[1])
  end
  return Answer(m, wps[1], wx, wy)
end
function ns.PathReset() state.key, state.wps, state.at, state.me, state.out, state.outCell = nil, nil, -1e9, nil, nil, nil end -- (tests)

-- (11.10., Daniel: "a dotted line on the map and minimap") the way the arrow leads, as points on the zone map
-- ({ mapID, { x, y }, ... } 0-1, from you to the target), or nil when it points straight. way: the point the
-- arrow points at (Arrow.lua), cave: the target lies inside and that point leads to its way in.
local line = { pts = {} }
function ns.PathLine(t, way, cave)
  if not (t and way and t.mapID) then return nil end
  local m, px, py = ns.PlayerPosition()
  if m ~= t.mapID or not px then return nil end
  local pts, n = line.pts, 0
  local function add(x, y) n = n + 1 local p = pts[n] if not p then p = {} pts[n] = p end p[1], p[2] = x, y end
  add(px, py)
  -- the waypoints still ahead (state belongs to the target the arrow asked for last: the way in for a cave)
  local wps = state.wps
  if wps then
    for k = 1, #wps - 1 do local x, y = Center(wps[k]) add(x, y) end
  end
  if cave then
    local ins = Inside(m)
    local wayIn = InsideOf(ins, Cell(t.x, t.y), Outside(m, ins))
    if wayIn then local x, y = Center(wayIn) add(x, y) end
  elseif n == 1 then
    add(way.x, way.y)
  end
  add(t.x, t.y)
  for k = n + 1, #pts do pts[k] = nil end
  line.mapID = m
  return line
end

-- Where you walk: one note every RECORD_EVERY seconds when you moved on the ground (not on a flight path,
-- not flying, not swimming)
local lastCell, lastMap, wayIn, lastOut
local function Record()
  if ns.db.recordWays == false then return end
  if (UnitOnTaxi and ns.True(ns.Value(UnitOnTaxi, "player"))) or (IsFlying and ns.True(ns.Value(IsFlying)))
      or (IsSwimming and ns.True(ns.Value(IsSwimming))) then return end
  local m, x, y = ns.PlayerPosition()
  -- (16.10.) not on a continent map (named as the player's map for a moment after a loading screen)
  if not m or (ns.IsZoneMap and not ns.IsZoneMap(m)) then return end
  local c = Cell(x, y)
  if not c then return end
  -- (11.10.) inside a cave or building: the cell where you went in is its way in
  if Indoors() then
    if not wayIn or wayIn.m ~= m then wayIn = { m = m, c = lastOut and lastOut.m == m and lastOut.c or c } end
    ns.db.insides = type(ns.db.insides) == "table" and ns.db.insides or {}
    local t = ns.db.insides[m]
    if type(t) ~= "table" then t = {} ns.db.insides[m] = t end
    if t[c] == nil then t[c] = wayIn.c end
  else
    wayIn = nil
    lastOut = { m = m, c = c }
  end
  if c == lastCell and m == lastMap then return end -- (17.10.) the same cell number on another map is another place
  lastCell, lastMap = c, m
  ns.db.walked = type(ns.db.walked) == "table" and ns.db.walked or {}
  local w = ns.db.walked[m]
  if type(w) ~= "table" then w = {} ns.db.walked[m] = w end
  w[c] = true
end
ns.PathRecord = Record -- (tests)
ns.OnInit(function()
  ns.NewTicker(RECORD_EVERY, Record)
end)

---------------------------------------------------------------------------
-- (1.3.6, Daniel: "the ways other players walked through Questdon's data exchange") Exchange.lua sends
-- "W <map> <block> <mask>": a block is 10 x 10 cells (block = column + row * 10), the mask 100 bits as 25
-- hex digits (bit = cell column + cell row * 10, four bits per digit, lowest first); only cells the shipped
-- data does not have. A cell others walked counts once two players reported it through guild or group, or
-- three in all (as every shared fact).
---------------------------------------------------------------------------
local BLOCK = 10
local HEX = "0123456789abcdef"
function ns.WalkRecords()
  local out = {}
  local walked = type(ns.db.walked) == "table" and ns.db.walked or {}
  local maps = {}
  for m in pairs(walked) do
    if type(m) == "number" and not (ns.IsZoneMap and not ns.IsZoneMap(m)) then maps[#maps + 1] = m end
  end
  table.sort(maps)
  for _, m in ipairs(maps) do
    local seed = Seed(m)
    local blocks = {}
    for c in pairs(walked[m]) do
      if type(c) == "number" and c >= 0 and c < N * N and not (seed and seed[c]) then
        local i, j = c % N, math.floor(c / N)
        local b = math.floor(i / BLOCK) + math.floor(j / BLOCK) * (N / BLOCK)
        local bit = (i % BLOCK) + (j % BLOCK) * BLOCK
        blocks[b] = blocks[b] or {}
        blocks[b][bit] = true
      end
    end
    local keys = {}
    for b in pairs(blocks) do keys[#keys + 1] = b end
    table.sort(keys)
    for _, b in ipairs(keys) do
      local digits = {}
      for d = 0, 24 do
        local v = 0
        for k = 0, 3 do if blocks[b][d * 4 + k] then v = v + 2 ^ k end end
        digits[#digits + 1] = HEX:sub(v + 1, v + 1)
      end
      out[#out + 1] = ("W %d %d %s"):format(m, b, table.concat(digits))
    end
  end
  return out
end

local walkVersion, walkCache = 0, {}
-- reporter: Exchange's reporter key; open: came through the open channel
function ns.StoreWalk(m, b, mask, reporter, open)
  if not (m and b and type(mask) == "string" and #mask == 25 and reporter) then return end
  if ns.IsZoneMap and not ns.IsZoneMap(m) then return end
  ns.db.sharedWalk = type(ns.db.sharedWalk) == "table" and ns.db.sharedWalk or {}
  local sm = ns.db.sharedWalk[m]
  if type(sm) ~= "table" then sm = {} ns.db.sharedWalk[m] = sm end
  local e = sm[b]
  if type(e) ~= "table" then e = {} sm[b] = e end
  local n = 0
  for _ in pairs(e) do n = n + 1 end
  if not e[reporter] and n >= 8 then return end
  e[reporter] = (open and "o" or "t") .. mask
  walkVersion = walkVersion + 1
end
function ns.SharedWalked(m)
  local c = walkCache[m]
  if c and c.v == walkVersion then return c.set end
  local set
  local sm = type(ns.db.sharedWalk) == "table" and ns.db.sharedWalk[m]
  for b, e in pairs(type(sm) == "table" and sm or {}) do
    if type(b) == "number" and type(e) == "table" then
      local trusted, all = {}, {}
      for _, v in pairs(e) do
        if type(v) == "string" and #v == 26 then
          local open = v:sub(1, 1) == "o"
          for d = 0, 24 do
            local val = (HEX:find(v:sub(d + 2, d + 2), 1, true) or 1) - 1
            for k = 0, 3 do
              if math.floor(val / 2 ^ k) % 2 == 1 then
                local bit = d * 4 + k
                all[bit] = (all[bit] or 0) + 1
                if not open then trusted[bit] = (trusted[bit] or 0) + 1 end
              end
            end
          end
        end
      end
      local bi, bj = b % (N / BLOCK), math.floor(b / (N / BLOCK))
      for bit, n in pairs(all) do
        if (trusted[bit] or 0) >= 2 or n >= 3 then
          set = set or {}
          set[(bj * BLOCK + math.floor(bit / BLOCK)) * N + bi * BLOCK + bit % BLOCK] = true
        end
      end
    end
  end
  walkCache[m] = { v = walkVersion, set = set }
  return set
end
