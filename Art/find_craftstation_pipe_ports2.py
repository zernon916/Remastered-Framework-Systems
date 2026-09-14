import json, math, os
import bpy

FBX = r"C:\Coding Projects\RemasteredFrameworkSystems\Objects\Mesh\rfs_crafting_station.fbx"
OUT = r"C:\Coding Projects\RemasteredFrameworkSystems\Art\craftstation_pipe_ports2.json"

def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.fbx(filepath=FBX, use_anim=False)
	pts = []
	for obj in bpy.context.scene.objects:
		if obj.type != "MESH":
			continue
		for v in obj.data.vertices:
			pts.append(obj.matrix_world @ v.co)

	def scan(sign):
		# verts on this X side, including slightly inset ports
		face = [p for p in pts if sign * p.x >= 2.2]
		# grid search yz for ring score
		best = None
		for yi in range(-20, 21):
			for zi in range(-20, 21):
				cy = yi * 0.125
				cz = zi * 0.125
				rs = [math.hypot(p.y - cy, p.z - cz) for p in face]
				# count verts in annulus 0.15-0.55 (hex/pipe flange)
				ann = sum(1 for r in rs if 0.18 <= r <= 0.55)
				inner = sum(1 for r in rs if r < 0.12)
				if ann < 8:
					continue
				score = ann + inner * 0.3
				if best is None or score > best["score"]:
					xs = [p.x for p in face if 0.18 <= math.hypot(p.y - cy, p.z - cz) <= 0.55]
					best = {
						"score": round(score, 2),
						"annulus": ann,
						"inner": inner,
						"x": round(sum(xs) / max(1, len(xs)), 3) if xs else None,
						"y": round(cy, 3),
						"z": round(cz, 3),
					}
		return { "n": len(face), "best": best }

	# remap guesses: SM box x=6 y=5 z=4 vs FBX x~6 y~4 z~5
	# A: SM = FBX (no remap)
	# B: SM_y = FBX_z, SM_z = FBX_y
	report = {
		"plus": scan(1),
		"minus": scan(-1),
	}
	for key in ("plus", "minus"):
		b = report[key]["best"]
		if not b:
			continue
		report[key]["as_shapeset_no_remap"] = { "x": b["x"], "y": b["y"], "z": b["z"] }
		report[key]["as_shapeset_yz_swap"] = { "x": b["x"], "y": b["z"], "z": b["y"] }
	with open(OUT, "w", encoding="utf-8") as fh:
		json.dump(report, fh, indent=2)
	print(json.dumps(report, indent=2))

if __name__ == "__main__":
	main()
