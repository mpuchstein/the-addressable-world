extends SceneTree
## Population dynamics probe: does scarcity produce oscillation or collapse?
## Run: godot --headless --path . --script tests/dynamics_probe.gd --quit-after 20

const WorldSim := preload("res://world.gd")

func _initialize() -> void:
	for seed_val in [20260822, 42, 777]:
		var w := WorldSim.new_seeded(seed_val)
		var line := "seed %d:\n" % seed_val
		for phase in range(20):
			w.run_to(w.tick + 200)
			var avg_eff := 0
			var pop := w.creatures.size()
			if pop > 0:
				for c in w.creatures:
					avg_eff += c.genes.eff
				avg_eff /= pop
			line += "  t=%5d  pop=%4d  plants=%7d  eff=%d%%\n" % [
				w.tick, pop, w.stats_plant[-1], avg_eff]
		print(line)
	quit(0)
