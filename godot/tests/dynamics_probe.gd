extends SceneTree
## Two-level population dynamics probe: grazers, predators, plants.
## Run: godot --headless --path . --script tests/dynamics_probe.gd --quit-after 20

const WorldSim := preload("res://world.gd")

func _initialize() -> void:
	for seed_val in [20260822, 42]:
		var w := WorldSim.new_seeded(seed_val)
		var line := "seed %d:\n" % seed_val
		for phase in range(20):
			w.run_to(w.tick + 200)
			var np := w.stats_pred[-1]
			line += "  t=%5d  graze=%4d  pred=%3d  plants=%7d\n" % [
				w.tick, w.stats_pop[-1], np, w.stats_plant[-1]]
		print(line)
	quit(0)
