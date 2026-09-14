# Find ring-like vertex clusters on the ±X faces of the crafting station FBX.
import json
import math
import os

import bpy
from mathutils import Vector

FBX = r"C:\Coding Projects\RemasteredFrameworkSystems\Objects\Mesh\rfs_crafting_station.fbx"
OUT = r"C:\Coding Projects\RemasteredFrameworkSystems\Art\craftstation_pipe_ports.json"

def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	if not os.path.isfile(FBX):
		raise RuntimeError("missing fbx " + FBX)
	bpy.ops.import_scene.fbx(filepath=FBX, use_anim=False)
	points = []
	for obj in bpy.context.scene.objects:
		if obj.type != "MESH":
			continue
		for vertex in obj.data.vertices:
			points.append(obj.matrix_world @ vertex.co)

	xs = [p.x for p in points]
	ys = [p.y for p in points]
	zs = [p.z for p in points]
	xmin, xmax = min(xs), max(xs)
	ymin, ymax = min(ys), max(ys)
	zmin, zmax = min(zs), max(zs)

	# Face slabs: verts near extreme X.
	margin = 0.12
	plus = [p for p in points if p.x >= xmax - margin]
	minus = [p for p in points if p.x <= xmin + margin]

	def clusters(face_pts, bin_size=0.15):
		# Bin by (y,z) to find dense patches (hex/ring ports).
		bins = {}
		for p in face_pts:
			key = (round(p.y / bin_size), round(p.z / bin_size))
			bins.setdefault(key, []).append(p)
		ranked = sorted(bins.values(), key=len, reverse=True)
		out = []
		for group in ranked[:8]:
			cy = sum(p.y for p in group) / len(group)
			cz = sum(p.z for p in group) / len(group)
			cx = sum(p.x for p in group) / len(group)
			# radius in yz
			rad = 0.0
			for p in group:
				rad = max(rad, math.hypot(p.y - cy, p.z - cz))
			out.append({
				"count": len(group),
				"x": round(cx, 3),
				"y": round(cy, 3),
				"z": round(cz, 3),
				"radius": round(rad, 3),
			})
		return out

	# Also report verts that look like a ring: many points at similar radius from a yz center.
	def best_ring(face_pts):
		if len(face_pts) < 12:
			return None
		# try several seed centers from dense bins
		best = None
		for seed in clusters(face_pts, 0.12)[:6]:
			cy, cz = seed["y"], seed["z"]
			rs = [math.hypot(p.y - cy, p.z - cz) for p in face_pts]
			# histogram radii
			buckets = {}
			for r in rs:
				if r < 0.05 or r > 0.9:
					continue
				k = round(r / 0.05)
				buckets[k] = buckets.get(k, 0) + 1
			if not buckets:
				continue
			rk, cnt = max(buckets.items(), key=lambda kv: kv[1])
			if best is None or cnt > best["ring_count"]:
				best = {
					"x": seed["x"],
					"y": cy,
					"z": cz,
					"ring_radius": round(rk * 0.05, 3),
					"ring_count": cnt,
				}
		return best

	report = {
		"fbx": FBX,
		"bounds": {
			"min": [round(xmin, 3), round(ymin, 3), round(zmin, 3)],
			"max": [round(xmax, 3), round(ymax, 3), round(zmax, 3)],
			"size": [round(xmax - xmin, 3), round(ymax - ymin, 3), round(zmax - zmin, 3)],
		},
		"plus_x_clusters": clusters(plus),
		"minus_x_clusters": clusters(minus),
		"plus_x_ring": best_ring(plus),
		"minus_x_ring": best_ring(minus),
		"plus_n": len(plus),
		"minus_n": len(minus),
		"sm_box": { "x": 6, "y": 5, "z": 4 },
		"note": "FBX is already in SM blocks (export *4). Shapeset box x=6 y=5 z=4. If SM Y=FBX Z and SM Z=FBX Y, remap pipe y/z.",
	}
	with open(OUT, "w", encoding="utf-8") as fh:
		json.dump(report, fh, indent=2)
	print("PIPE_PORT_REPORT", json.dumps(report))

if __name__ == "__main__":
	main()
