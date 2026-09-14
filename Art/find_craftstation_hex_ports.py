# Find circular holes and hex-like loops on the crafting station X faces.
import json, math
import bpy
from mathutils import Vector

FBX = r"C:\Coding Projects\RemasteredFrameworkSystems\Objects\Mesh\rfs_crafting_station.fbx"
OUT = r"C:\Coding Projects\RemasteredFrameworkSystems\Art\craftstation_hex_ports.json"

def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.fbx(filepath=FBX, use_anim=False)
	obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
	mesh = obj.data
	mw = obj.matrix_world
	pts = [mw @ v.co for v in mesh.vertices]

	# World-space edges on each X side
	def side_pts(sign, xmin=2.4):
		return [p for p in pts if sign * p.x >= xmin]

	def local_holes(face, label):
		# Sample candidate centers on a 0.125 grid in yz
		cands = []
		for yi in range(-24, 25):
			for zi in range(-24, 25):
				cy = yi * 0.125
				cz = zi * 0.125
				rs = [math.hypot(p.y - cy, p.z - cz) for p in face]
				# hole: few verts in the very center, many in a tight ring
				core = sum(1 for r in rs if r < 0.15)
				ring = sum(1 for r in rs if 0.22 <= r <= 0.45)
				ring2 = sum(1 for r in rs if 0.45 < r <= 0.70)
				if ring + ring2 < 10:
					continue
				cands.append({
					"y": round(cy, 3),
					"z": round(cz, 3),
					"core": core,
					"ring": ring,
					"ring2": ring2,
					"score": ring * 2 + ring2 - core,
				})
		cands.sort(key=lambda c: c["score"], reverse=True)
		# suppress near-duplicates
		kept = []
		for c in cands:
			if any(math.hypot(c["y"] - k["y"], c["z"] - k["z"]) < 0.35 for k in kept):
				continue
			kept.append(c)
			if len(kept) >= 6:
				break
		return kept

	# Also report mean of verts that stick out past |x|=2.85 (flange)
	def flange_center(sign):
		fl = [p for p in pts if sign * p.x >= 2.85]
		if not fl:
			return None
		return {
			"n": len(fl),
			"y": round(sum(p.y for p in fl) / len(fl), 3),
			"z": round(sum(p.z for p in fl) / len(fl), 3),
			"x": round(sum(p.x for p in fl) / len(fl), 3),
		}

	report = {
		"plus_holes": local_holes(side_pts(1), "+X"),
		"minus_holes": local_holes(side_pts(-1), "-X"),
		"plus_flange": flange_center(1),
		"minus_flange": flange_center(-1),
		"bounds": {
			"min": [round(min(p[i] for p in pts), 3) for i in range(3)],
			"max": [round(max(p[i] for p in pts), 3) for i in range(3)],
		},
	}
	with open(OUT, "w", encoding="utf-8") as fh:
		json.dump(report, fh, indent=2)
	print(json.dumps(report, indent=2))

if __name__ == "__main__":
	main()
