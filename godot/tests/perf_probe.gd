extends SceneTree
## Throughput probe: ticks/sec headless at realistic population.
## Run: godot --headless --path . --script tests/perf_probe.gd --quit-after 20

const WorldSim := preload("res://world.gd")

func _initialize() -> void:
	var w := WorldSim.new_seeded(20260822)
	w.run_to(1000)   # settle to equilibrium density
	var n := w.creatures.size()
	var t0 := Time.get_ticks_usec()
	var target := w.tick + 300
	w.run_to(target)
	var dt := Time.get_ticks_usec() - t0
	print("pop=%d  %d ticks in %d usec  -> %.1f ticks/sec" % [n, 300, dt, 300.0 / (dt / 1000000.0)])
	quit(0)
