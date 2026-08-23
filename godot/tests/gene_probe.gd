extends SceneTree
const WorldSim := preload("res://world.gd")
func _initialize() -> void:
	var w := WorldSim.new_seeded(20260822)
	for phase in range(12):
		w.run_to(w.tick + 500)
		var gs := 0
		var ge := 0
		var gn := 0
		var ps := 0
		var pn := 0
		for c in w.creatures:
			if c.energy <= 0:
				continue
			if c.kind == WorldSim.KIND_GRAZER:
				gn += 1
				gs += c.genes.speed
				ge += c.genes.sense
			else:
				pn += 1
				ps += c.genes.speed
		if gn > 0:
			gs /= gn
			ge /= gn
		if pn > 0:
			ps /= pn
		print("t=%5d graze=%4d spd=%d sense=%d  pred=%3d spd=%d" % [w.tick, gn, gs, ge, pn, ps])
	quit(0)
