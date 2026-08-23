extends SceneTree
const WorldSim := preload("res://world.gd")
func _initialize() -> void:
	var w := WorldSim.new_seeded(20260822)
	for i in range(300):
		w.tick_step()
		if i % 25 == 0:
			var np := 0
			var te := 0
			for c in w.creatures:
				if c.kind == WorldSim.KIND_PREDATOR and c.energy > 0:
					np += 1
					te += c.energy
			print("t=%3d preds=%2d avgE=%s kills=%d" % [i, np, str(te / maxi(np, 1)), w.kills])
	quit(0)
