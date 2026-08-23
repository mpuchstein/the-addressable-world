class_name WorldSim
extends RefCounted
## Deterministic artificial-life world. The document is the point:
## every moment is addressable, hashable, restorable from bytes.
## Integer-only evolution; same-binary replay is exact.

const W := 96
const H := 96
const GROWTH_DIV := 120            # higher = slower regrowth = scarcity bites
const BITE := 14                    # biomass per eating action
const HUNGRY_BELOW := 130           # creature seeks food when energy below this
const REPRO_AT := 200
const CHILD_COST := 80              # parent pays this; child receives CHILD_COST - 10
const PRED_REPRO_AT := 280
const PRED_CHILD_COST := 100        # predator children are expensive
const MEAT_ENERGY := 75             # base energy per kill, scaled by eff
const PRED_START := 14              # colonist count at arrival
const PRED_ARRIVAL_TICK := 500      # immigration when prey is plentiful
const RECOLONIZE_EVERY := 2000      # mainland island: new colonists if level died
const AGE_MAX := 900
const MUT_PCT := 25                 # per-gene mutation chance, percent
const SNAPSHOT_EVERY := 60
const MAX_SNAPSHOTS := 240          # ring size (~10 MB total)
const STATS_WINDOW := 4096

# --- state ---
var seed_i: int
var tick: int = 0
var next_id: int = 1
var kills: int = 0                 # telemetry: total pounces this world's lifetime
var plants: PackedInt32Array        # biomass per tile
var fert: PackedInt32Array          # per-tile capacity
var creatures: Array = []           # dicts, sorted by id ascending at all times

# history ring of {tick:int, bytes:PackedByteArray}
var snapshots: Array = []
var stats_pop: PackedInt32Array = PackedInt32Array()
var stats_plant: PackedInt32Array = PackedInt32Array()
var stats_pred: PackedInt32Array = PackedInt32Array()

# ---------------------------------------------------------------- RNG
# Stateless, order-independent randomness. Every die roll derives from
# (seed, tick, entity id, salt) so iteration order can never perturb it.

const GOLDEN := -7046029254386353131 # 0x9E3779B97F4A7C15
const MIX1 := -4658895280553007687   # 0xBF58476D1CE4E5B9
const MIX2 := -7723592293110705685   # 0x94D049BB133111EB

static func mix64(x: int) -> int:
	x += GOLDEN
	x = (x ^ (x >> 30)) * MIX1
	x = (x ^ (x >> 27)) * MIX2
	return x ^ (x >> 31)

func rnd(salt: int, id: int = 0) -> int:
	## uniform non-negative 31-bit value bound to this world/tick/entity
	var h := mix64(seed_i ^ mix64(tick * -4136764598241799491 + id * 1099511628211 + salt))
	return h & 0x7FFFFFFF

func chance(salt: int, id: int, pct: int) -> bool:
	return rnd(salt, id) % 100 < pct

# ---------------------------------------------------------------- setup
@warning_ignore("integer_division")
static func new_seeded(p_seed: int) -> WorldSim:
	var w := WorldSim.new()
	w.seed_i = p_seed
	var n := W * H
	w.plants.resize(n)
	w.fert.resize(n)
	for i in range(n):
		w.fert[i] = 40 + w.rnd(1000, i) % 80   # 40..119 raw
	w._smooth_fertility()
	for i in range(n):
		w.plants[i] = w.rnd(1001, i) % maxi(1, w.fert[i] / 2)
	for k in range(70):
		w.creatures.append(w._genesis_grazer(w, k))
		w.next_id += 1
	# NOTE: predators are NOT founded here — they arrive as a colonization
	# event at PRED_ARRIVAL_TICK, derived purely from the tick (see
	# tick_step), so restores and replays need no extra state.
	w.snapshot_now()   # genesis: tick 0 is addressable too
	return w

const KIND_GRAZER := 0
const KIND_PREDATOR := 1

static func _genesis_grazer(w: WorldSim, k: int) -> Dictionary:
	return {
		"id": w.next_id,
		"kind": KIND_GRAZER,
		"x": w.rnd(2004, k) % W,
		"y": w.rnd(2005, k) % H,
		"energy": 80 + w.rnd(2006, k) % 60,
		"dir": w.rnd(2007, k) % 4,
		"age": 0,
		"cool": 0,
		"genes": {
			"speed": 1 + w.rnd(2000, k) % 4,      # 1..4
			"sense": 2 + w.rnd(2001, k) % 6,      # 2..7
			"eff": 60 + w.rnd(2002, k) % 90,      # 60..149 (%)
			"hue": w.rnd(2003, k) % 360,
		},
	}

@warning_ignore("integer_division")
static func _genesis_predator(w: WorldSim, k: int) -> Dictionary:
	return {
		"id": w.next_id,
		"kind": KIND_PREDATOR,
		"x": w.rnd(2104, k) % W,
		"y": w.rnd(2105, k) % H,
		"energy": 240 + w.rnd(2106, k) % 80,
		"dir": w.rnd(2107, k) % 4,
		"age": 0,
		"cool": 0,
		"genes": {
			"speed": 2 + w.rnd(2100, k) % 3,      # 2..4 hunters start faster
			"sense": 3 + w.rnd(2101, k) % 5,      # 3..7
			"eff": 70 + w.rnd(2102, k) % 80,      # 70..149 (%)
			"hue": w.rnd(2103, k) % 360,
		},
	}

func _smooth_fertility() -> void:
	# one pass: each tile averages with right+down neighbour -> fertile patches
	var src := fert.duplicate()
	for y in range(H):
		for x in range(W):
			var i := y * W + x
			var s: int = src[i] * 2
			s += src[y * W + ((x + 1) % W)]
			s += src[((y + 1) % H) * W + x]
			fert[i] = s >> 2

func idx(x: int, y: int) -> int:
	return (y % H) * W + (x % W)

# ---------------------------------------------------------------- tick
var _occ := {}        # tile idx -> lowest-id living grazer, rebuilt each tick
var _occ_pred := {}   # tile idx -> some living predator position, rebuilt each tick

func tick_step() -> void:
	if tick == PRED_ARRIVAL_TICK or (tick > PRED_ARRIVAL_TICK and tick % RECOLONIZE_EVERY == 0):
		# colonization events: pure function of the tick — replay-exact.
		# mainland-island model: whichever level went extinct here gets
		# immigrants; grazers first, since nothing eats without them.
		var ng := 0
		var np := 0
		for c in creatures:
			if c.energy <= 0:
				continue
			if c.kind == KIND_GRAZER:
				ng += 1
			else:
				np += 1
		# mainland-island rescue rules, in order of need:
		#   grazers extinct -> grazer immigrants (predators starve anyway)
		#   grazers alive, predators extinct -> predator colonists
		#   both extinct -> grazers only; predators wait for prey to recover
		if ng == 0:
			for k in range(24):
				creatures.append(_genesis_grazer(self, k))
				next_id += 1
		elif np == 0:
			for k in range(PRED_START):
				creatures.append(_genesis_predator(self, k))
				next_id += 1
	_grow_plants()
	var order := creatures.duplicate()
	order.sort_custom(func(a, b): return a.id < b.id)
	_occ.clear()
	_occ_pred.clear()
	for c in order:
		if c.energy <= 0:
			continue
		var ti := idx(c.x, c.y)
		if c.kind == KIND_GRAZER:
			if not _occ.has(ti) or _occ[ti].id > c.id:
				_occ[ti] = c
		else:
			if not _occ_pred.has(ti):
				_occ_pred[ti] = Vector2i(posmod(c.x, W), posmod(c.y, H))
	for c in order:
		_act(c)
	_bury_the_dead()
	tick += 1
	_record_stats()
	if tick % SNAPSHOT_EVERY == 0:
		snapshot_now()

@warning_ignore("integer_division")
func _grow_plants() -> void:
	for i in range(plants.size()):
		var b := plants[i]
		if b < fert[i]:
			b += maxi(1, (fert[i] - b) / GROWTH_DIV)   # grows from zero: no dead-trap state
			if b > fert[i]: b = fert[i]
			plants[i] = b

@warning_ignore("integer_division")
func _neighbor_green(i: int) -> int:
	var x := i % W
	var y := i / W
	var s := 0
	s += plants[idx(x + 1, y)] + plants[idx(x - 1, y)]
	s += plants[idx(x, y + 1)] + plants[idx(x, y - 1)]
	return s

@warning_ignore("integer_division")
func _act(c: Dictionary) -> void:
	if c.energy <= 0:   # killed earlier this tick by a predator
		return
	c.age += 1
	if c.cool > 0: c.cool -= 1
	var g: Dictionary = c.genes
	# basal metabolism: the cost of existing, not of moving
	c.energy -= 3 + g.sense / 2 + ((g.eff * g.eff) >> 11)
	var steps: int
	if c.kind == KIND_PREDATOR:
		steps = _act_predator(c, g)
	else:
		steps = _act_grazer(c, g)
	# locomotion: legs cost energy only while they carry you
	c.energy -= steps * g.speed
	if c.energy <= 0 or c.age > AGE_MAX:
		c.energy = -1  # marked dead; buried after the loop
		return
	if c.kind == KIND_PREDATOR:
		if c.energy >= PRED_REPRO_AT and c.cool == 0:
			c.cool = 80
			_reproduce(c)
	elif c.energy >= REPRO_AT and c.cool == 0:
		c.cool = 40   # refractory period: birth waves, not continuous rain
		_reproduce(c)

func _act_grazer(c: Dictionary, g: Dictionary) -> int:
	var ox: int = c.x
	var oy: int = c.y
	var steps := 0
	var threat := _find_kind(c.x, c.y, g.sense, KIND_PREDATOR)
	if threat.x >= 0 and c.energy > 20:
		for s in range(g.speed):   # flight spends legs: speed vs speed pursuit
			_flee_step(c, threat)
			steps += 1
			threat = _find_kind(c.x, c.y, mini(g.sense, 3), KIND_PREDATOR)
			if threat.x < 0:
				break
	elif c.energy < HUNGRY_BELOW:
		var t := _find_food(c.x, c.y, g.sense)
		if t.x >= 0:
			for s in range(g.speed):   # fast genes close distance while starving
				_step_toward(c, t)
				steps += 1
				if plants[idx(c.x, c.y)] > 0:
					break
		else:
			_wander(c)
			steps = 1
	else:
		_wander(c)
		steps = 1
	if c.x != ox or c.y != oy:
		_occ_move(c, ox, oy)   # live map: vacated tiles can't be pounced
	# graze opportunistically — scarcity, not a gate, regulates energy
	var i := idx(c.x, c.y)
	if plants[i] > 0:
		var eaten := mini(BITE, plants[i])
		plants[i] -= eaten
		c.energy += eaten * g.eff / 100
	return steps

func _occ_move(c: Dictionary, ox: int, oy: int) -> void:
	var ti_old := idx(ox, oy)
	if _occ.has(ti_old) and _occ[ti_old] == c:
		_occ.erase(ti_old)
	var ti_new := idx(c.x, c.y)
	if not _occ.has(ti_new):
		_occ[ti_new] = c

func _act_predator(c: Dictionary, g: Dictionary) -> int:
	var steps := 0
	for s in range(g.speed):
		if _try_kill(c):
			return steps
		var prey := _find_prey(c.x, c.y, g.sense)
		if prey.x < 0:
			return steps
		_step_toward(c, prey)
		steps += 1
	_wander(c)
	return steps + 1

func _find_prey(x: int, y: int, r: int) -> Vector2i:
	## nearest grazer via the occupancy map (start-of-tick positions)
	var best_d := 1 << 30
	var best := Vector2i(-1, -1)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := absi(dx) + absi(dy)
			if d > r or d >= best_d:
				continue
			var ti := idx(x + dx, y + dy)
			if _occ.has(ti):
				best_d = d
				best = Vector2i(posmod(x + dx, W), posmod(y + dy, H))
	return best

func _try_kill(c: Dictionary) -> bool:
	## the pounce: prey on this tile or any neighbour is taken — unless it
	## was fast enough to twist away. Speed contests make the arms race real.
	var dirs := [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]
	for i in range(5):
		var ti := idx(c.x + dirs[i][0], c.y + dirs[i][1])
		if _occ.has(ti):
			var victim: Dictionary = _occ[ti]
			if victim.energy > 0:
				var dodge: int = clampi(25 + victim.genes.speed * 12, 37, 97)
				if rnd(6001, victim.id) % 100 < dodge:
					_occ.erase(ti)   # escaped: this tile is clean for the tick
					continue
				victim.energy = -1
				_occ.erase(ti)
				c.energy += MEAT_ENERGY * c.genes.eff / 100
				kills += 1
				return true   # no scavenging
	return false

func _find_kind(x: int, y: int, r: int, kind: int) -> Vector2i:
	## nearest predator via the predator occupancy map (O(r²) tile probes)
	var occ := _occ_pred
	var best_d := 1 << 30
	var best := Vector2i(-1, -1)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := absi(dx) + absi(dy)
			if d > r or d >= best_d:
				continue
			var ti := idx(x + dx, y + dy)
			if occ.has(ti):
				best_d = d
				best = Vector2i(posmod(x + dx, W), posmod(y + dy, H))
	return best

func _flee_step(c: Dictionary, threat: Vector2i) -> void:
	var dx := posmod(threat.x - c.x + W / 2, W) - W / 2
	var dy := posmod(threat.y - c.y + H / 2, H) - H / 2
	if dx == 0 and dy == 0:
		c.x = posmod(c.x + rnd(6000, c.id) % 3 - 1, W)   # pinned under a predator: scramble
		return
	if absi(dx) >= absi(dy):
		c.x = posmod(c.x - signi(dx), W)
	else:
		c.y = posmod(c.y - signi(dy), H)

func _find_food(x: int, y: int, r: int) -> Vector2i:
	var best_score := 0
	var best := Vector2i(-1, -1)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := absi(dx) + absi(dy)
			if d == 0 or d > r:
				continue
			var score: int = plants[idx(x + dx, y + dy)] - d * 2
			if score > best_score:
				best_score = score
				best = Vector2i(posmod(x + dx, W), posmod(y + dy, H))
	return best

func _step_toward(c: Dictionary, t: Vector2i) -> void:
	var dx := posmod(t.x - c.x + W / 2, W) - W / 2   # torus-shortest delta
	var dy := posmod(t.y - c.y + H / 2, H) - H / 2
	if dx == 0 and dy == 0:
		return
	if absi(dx) >= absi(dy):
		c.x = posmod(c.x + signi(dx), W)
	else:
		c.y = posmod(c.y + signi(dy), H)

func _wander(c: Dictionary) -> void:
	var turn := rnd(4000, c.id) % 8
	if turn == 0: c.dir = (c.dir + 1) % 4
	elif turn == 1: c.dir = (c.dir + 3) % 4
	match c.dir:
		0: c.y = posmod(c.y - 1, H)
		1: c.x = posmod(c.x + 1, W)
		2: c.y = posmod(c.y + 1, H)
		3: c.x = posmod(c.x - 1, W)

func _reproduce(parent: Dictionary) -> void:
	var pred: bool = parent.kind == KIND_PREDATOR
	parent.energy -= PRED_CHILD_COST if pred else CHILD_COST
	var bounds_lo := {"speed": 1, "sense": 1, "eff": 40, "hue": 0}
	var bounds_hi := {"speed": 6, "sense": 9, "eff": 180, "hue": 359}
	var child_genes := {}
	for key in ["speed", "sense", "eff", "hue"]:
		var v: int = parent.genes[key]
		if chance(5000 + key.hash(), parent.id, MUT_PCT):
			v += (rnd(5001, parent.id) % 2) * 2 - 1        # +-1
			if key == "hue": v += (rnd(5002, parent.id) % 11) - 5
		child_genes[key] = clampi(v, bounds_lo[key], bounds_hi[key])
	creatures.append({
		"id": next_id,
		"kind": KIND_PREDATOR if pred else KIND_GRAZER,
		"x": posmod(parent.x + rnd(5003, next_id) % 3 - 1, W),
		"y": posmod(parent.y + rnd(5004, next_id) % 3 - 1, H),
		"energy": (PRED_CHILD_COST if pred else CHILD_COST) - 10,
		"dir": rnd(5005, next_id) % 4,
		"age": 0,
		"cool": 0,
		"genes": child_genes,
	})
	next_id += 1

func _bury_the_dead() -> void:
	creatures = creatures.filter(func(c): return c.energy > 0)

func _record_stats() -> void:
	var np := 0
	for c in creatures:
		if c.kind == KIND_PREDATOR:
			np += 1
	stats_pop.append(creatures.size() - np)
	stats_pred.append(np)
	var tp := 0
	for b in plants: tp += b
	stats_plant.append(tp)
	if stats_pop.size() > STATS_WINDOW * 2:
		trim_stats()

func trim_stats() -> void:
	stats_pop = stats_pop.slice(STATS_WINDOW)
	stats_plant = stats_plant.slice(STATS_WINDOW)
	stats_pred = stats_pred.slice(STATS_WINDOW)

# ---------------------------------------------------------------- the document
func serialize() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_64(seed_i); buf.put_64(tick); buf.put_64(next_id)
	buf.put_32(W); buf.put_32(H)
	for b in plants: buf.put_32(b)
	for f in fert: buf.put_32(f)
	buf.put_32(creatures.size())
	for c in creatures:
		buf.put_64(c.id); buf.put_32(c.kind)
		buf.put_32(c.x); buf.put_32(c.y)
		buf.put_32(c.energy); buf.put_32(c.dir); buf.put_32(c.age); buf.put_32(c.cool)
		buf.put_32(c.genes.speed); buf.put_32(c.genes.sense)
		buf.put_32(c.genes.eff); buf.put_32(c.genes.hue)
	return buf.data_array

static func deserialize(data: PackedByteArray) -> WorldSim:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var w := WorldSim.new()
	w.seed_i = buf.get_64(); w.tick = buf.get_64(); w.next_id = buf.get_64()
	assert(buf.get_32() == W and buf.get_32() == H)
	var n := W * H
	w.plants.resize(n); w.fert.resize(n)
	for i in range(n): w.plants[i] = buf.get_32()
	for i in range(n): w.fert[i] = buf.get_32()
	for k in range(buf.get_32()):
		w.creatures.append({
			"id": buf.get_64(), "kind": buf.get_32(),
			"x": buf.get_32(), "y": buf.get_32(),
			"energy": buf.get_32(), "dir": buf.get_32(), "age": buf.get_32(),
			"cool": buf.get_32(),
			"genes": {
				"speed": buf.get_32(), "sense": buf.get_32(),
				"eff": buf.get_32(), "hue": buf.get_32(),
			},
		})
	return w

func state_hash() -> int:
	## FNV-1a over the serialized document — the fingerprint of a moment
	var h: int = -3750763034362895579   # 0xcbf29ce484222325 signed
	for b in serialize():
		h = (h ^ b) * 1099511628211
	return h

func snapshot_now() -> void:
	snapshots.append({"tick": tick, "bytes": serialize()})
	if snapshots.size() > MAX_SNAPSHOTS:
		snapshots.pop_front()

func restore_to_tick(t: int) -> bool:
	## rebuild exact state at tick t from nearest snapshot <= t, then re-sim.
	## snapshots <= t survive the jump: you forget the future, never the past.
	var best: Dictionary = {}
	for s in snapshots:
		if s.tick <= t and (best.is_empty() or s.tick > best.tick):
			best = s
	if best.is_empty():
		return false
	var past := snapshots.filter(func(s): return s.tick <= t)
	var restored: WorldSim = deserialize(best.bytes)
	while restored.tick < t:
		restored.tick_step()
	seed_i = restored.seed_i; tick = restored.tick; next_id = restored.next_id
	plants = restored.plants; fert = restored.fert; creatures = restored.creatures
	snapshots = past
	stats_pop = restored.stats_pop      # keep whatever the re-sim recorded
	stats_plant = restored.stats_plant
	stats_pred = restored.stats_pred
	return true

func run_to(t: int) -> void:
	while tick < t:
		tick_step()
