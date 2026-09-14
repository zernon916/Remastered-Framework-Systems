# Crafting Station collision hull in SM block space (Y up).
# Body is inset on X so sticky +/-X hits the port nubs, not a flat end wall.
# Port nubs sit at the visual windows after Blender Z-up -> SM Y-up remap:
#   SM y = FBX z (~0), SM z = FBX y (~0.5)

from pathlib import Path

OUT = Path(r"C:\Coding Projects\RemasteredFrameworkSystems\Objects\Collision\rfs_crafting_station_col.obj")


def box(x0, x1, y0, y1, z0, z1, verts, faces):
	base = len(verts)
	verts.extend(
		[
			(x0, y0, z0),
			(x1, y0, z0),
			(x1, y1, z0),
			(x0, y1, z0),
			(x0, y0, z1),
			(x1, y0, z1),
			(x1, y1, z1),
			(x0, y1, z1),
		]
	)
	faces.extend(
		[
			(base + 1, base + 2, base + 3, base + 4),
			(base + 5, base + 8, base + 7, base + 6),
			(base + 1, base + 5, base + 6, base + 2),
			(base + 4, base + 3, base + 7, base + 8),
			(base + 1, base + 4, base + 8, base + 5),
			(base + 2, base + 6, base + 7, base + 3),
		]
	)


def main():
	verts = []
	faces = []
	# Main body: 6x5x4 footprint but X inset so end walls are not one sticky slab.
	box(-2.70, 2.70, -2.50, 2.50, -2.00, 2.00, verts, faces)
	# Port nubs flush with the visual face (~+/-2.98). Do not stick out past the mesh
	# or the vacuum pipe sits with a gap (do not stretch the render FBX).
	box(-3.00, -2.55, -0.60, 0.60, -1.10, 0.10, verts, faces)
	box(2.55, 3.00, -0.60, 0.60, -1.10, 0.10, verts, faces)
	lines = [
		"# rfs_crafting_station_col. SM blocks, Y up. Hull 6x5x4.",
		"# Body inset on X; nubs only at the left/right vacuum windows.",
		"g col",
	]
	for v in verts:
		lines.append("v %.6f %.6f %.6f" % v)
	for f in faces:
		lines.append("f %d %d %d %d" % f)
	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
	print("WROTE", OUT, "verts", len(verts), "faces", len(faces))


if __name__ == "__main__":
	main()
