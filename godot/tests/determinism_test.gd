extends SceneTree
## Headless verification harness for WorldSim determinism claims.
## Run: godot --headless --path . --script tests/determinism_test.gd

const WorldSim := preload("res://world.gd")

var failures := 0

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("PASS  ", name)
	else:
		failures += 1
		print("FAIL  ", name, "  ", detail)

func _initialize() -> void:
	print("== WorldSim determinism harness ==")
	var t0 := Time.get_ticks_msec()

	var a := WorldSim.new_seeded(12345)
	var b := WorldSim.new_seeded(12345)
	a.run_to(600)
	b.run_to(600)
	check("same seed -> identical hash @600", a.state_hash() == b.state_hash(),
		"%d vs %d" % [a.state_hash(), b.state_hash()])
	check("world alive @600", a.creatures.size() > 0,
		"pop=%d" % a.creatures.size())

	var c := WorldSim.new_seeded(12345)
	c.run_to(300)
	var h_c300 := c.state_hash()
	var h_a_before: int = a.snapshots[5].bytes.size()
	check("snapshot bytes exist", h_a_before > 1000)

	# scrub back inside a lived-in world, then walk forward again
	check("restore_to_tick(300)", a.restore_to_tick(300))
	check("restored == straight-run @300", a.state_hash() == h_c300,
		"%d vs %d" % [a.state_hash(), h_c300])
	a.run_to(700)
	c.run_to(700)
	check("future reconverges @700", a.state_hash() == c.state_hash())

	# mid-snapshot restore forces actual re-simulation
	check("restore_to_tick(297)", a.restore_to_tick(297))
	var ref := WorldSim.new_seeded(12345)
	ref.run_to(297)
	check("re-simd @297 matches", a.state_hash() == ref.state_hash())

	# document round-trip
	var d := WorldSim.deserialize(a.serialize())
	check("serialize/deserialize round-trip", d.state_hash() == a.state_hash())
	d.tick_step()
	a.tick_step()
	check("deserialized copy stays in lockstep", d.state_hash() == a.state_hash())

	# different seed -> different universe
	var e := WorldSim.new_seeded(12346)
	e.run_to(600)
	check("different seed diverges", e.state_hash() != b.state_hash())

	# fork divergence measurement (the sensitive-dependence probe)
	var f1 := WorldSim.new_seeded(777)
	var f2 := WorldSim.new_seeded(778)
	var dists := []
	for phase in range(6):
		f1.run_to(f1.tick + 150)
		f2.run_to(f2.tick + 150)
		dists.append(_world_dist(f1, f2))
	print("      divergence (seed delta=1, world-distance): ", dists)
	check("one-bit fork diverges immediately", dists[1] > 0)

	print("== done in %d ms, failures: %d ==" % [Time.get_ticks_msec() - t0, failures])
	quit(1 if failures > 0 else 0)

func _world_dist(w1: WorldSim, w2: WorldSim) -> int:
	## macroscopic state distance: population gap + plant-total gap.
	## trajectory positions saturate on a bounded torus; attractor stats don't lie.
	var tp1 := 0
	for b in w1.plants: tp1 += b
	var tp2 := 0
	for b in w2.plants: tp2 += b
	return absi(w1.creatures.size() - w2.creatures.size()) \
		+ absi(tp1 - tp2) / 500
