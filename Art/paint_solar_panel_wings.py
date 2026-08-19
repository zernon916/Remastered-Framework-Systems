"""Paint blue PV herringbone into panel_base wing UV islands (rfs_solar_v5.dae).

Wing collector faces (3012 tris) use panel_base_material, NOT solar_mirror_material
(36 tris overlay). Previous paint_solar_mirror_grid.py targeted the wrong slot.
"""
import os
import re
from PIL import Image, ImageDraw

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
DAE = os.path.join(ROOT, "Objects", "Mesh", "rfs_solar_v5.dae")
PANEL_DIF = os.path.join(ROOT, "Objects", "Textures", "solar", "panel_base_material_dif.png")
PANEL_SRC = os.path.join(
    ROOT, "Art", "sketchfab_solar", "textures", "Panel Base Material_BaseColor_16.png"
)
MIRROR_SRC = os.path.join(
    ROOT, "Art", "sketchfab_solar", "textures", "Solar Mirror Material_BaseColor_19.png"
)
OUT = PANEL_DIF
SIZE = 1024


def parse_dae():
    text = open(DAE, encoding="utf-8").read()
    pos_m = re.search(
        r'id="rfs_solar_v5-mesh-positions"[^>]*>\s*'
        r'<float_array[^>]+count="(\d+)"[^>]*>([^<]+)</float_array>',
        text,
    )
    pos_raw = [float(x) for x in pos_m.group(2).split()]
    positions = list(zip(pos_raw[0::3], pos_raw[1::3], pos_raw[2::3]))

    uv_m = re.search(
        r'id="rfs_solar_v5-mesh-map-0"[^>]*>\s*'
        r'<float_array[^>]+count="(\d+)"[^>]*>([^<]+)</float_array>',
        text,
    )
    uv_raw = [float(x) for x in uv_m.group(2).split()]
    uvs = list(zip(uv_raw[0::2], uv_raw[1::2]))

    tri = re.search(
        r'<triangles material="panel_base_material-material" count="(\d+)">\s*'
        r'(?:<input[^/]*/>\s*)+\s*<p>([^<]+)</p>',
        text,
    )
    count = int(tri.group(1))
    indices = [int(x) for x in tri.group(2).split()]
    tri_uv = []
    tri_pos = []
    for t in range(count):
        verts = []
        uvs3 = []
        for k in range(3):
            base = t * 9 + k * 3
            verts.append(positions[indices[base]])
            uvs3.append(uvs[indices[base + 2]])
        tri_pos.append(verts)
        tri_uv.append(uvs3)
    return tri_uv, tri_pos


def is_wing_tri(uv_tri, src_px, src_w, src_h):
    """Wing faces map to brown herringbone octagons in Panel Base albedo."""
    browns = 0
    for u, v in uv_tri:
        x = int(u * (src_w - 1))
        y = int((1.0 - v) * (src_h - 1))
        r, g, b = src_px[y * src_w + x][:3]
        # Brown/tan herringbone islands — not white frame or grey vent.
        if r > 95 and g > 70 and b < 200 and r > g and g > b * 0.7:
            browns += 1
    return browns >= 2


def wing_uv_bounds(tri_uv_list):
    us = [u for tri in tri_uv_list for u, _ in tri]
    vs = [v for tri in tri_uv_list for u, v in tri]
    pad = 0.008
    return max(0, min(us) - pad), min(1, max(us) + pad), max(0, min(vs) - pad), min(1, max(vs) + pad)


def paint_herringbone(draw, x0, y0, x1, y1):
    """Blue PV herringbone matching Sketchfab Solar Mirror Material."""
    w, h = x1 - x0, y1 - y0
    if w < 8 or h < 8:
        return
    bg = (28, 72, 210)
    line = (180, 210, 255)
    draw.rectangle([x0, y0, x1, y1], fill=bg)
    step = max(6, min(w, h) // 24)
    for y in range(y0 - step, y1 + step, step):
        pts = []
        x = x0
        flip = ((y - y0) // step) % 2 == 0
        while x < x1 + step:
            cy = y + (step // 2 if flip else -step // 2)
            pts.append((x, cy))
            x += step
            flip = not flip
        for i in range(len(pts) - 1):
            draw.line([pts[i], pts[i + 1]], fill=line, width=max(2, step // 4))
    # Fine cross-hatch for PV cell readability in-world.
    cell = max(8, step * 2)
    for cx in range(x0, x1, cell):
        draw.line([(cx, y0), (cx, y1)], fill=(20, 55, 170), width=1)
    for cy in range(y0, y1, cell):
        draw.line([(x0, cy), (x1, cy)], fill=(20, 55, 170), width=1)


def main():
    tri_uv, tri_pos = parse_dae()
    src_path = PANEL_SRC if os.path.isfile(PANEL_SRC) else PANEL_DIF
    src = Image.open(src_path).convert("RGB")
    if src.size != (SIZE, SIZE):
        src = src.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    src_px = list(src.getdata())

    wing_tris = []
    for i, uv_tri in enumerate(tri_uv):
        if is_wing_tri(uv_tri, src_px, SIZE, SIZE):
            wing_tris.append(uv_tri)

    print(f"panel_base tris={len(tri_uv)} wing tris={len(wing_tris)}")

    img = src.copy()
    draw = ImageDraw.Draw(img)

    # Cluster wing tris into separate octagonal islands (left + right wing).
    if wing_tris:
        u0, u1, v0, v1 = wing_uv_bounds(wing_tris)
        # Split at mid-U if two wings present.
        mid_u = (u0 + u1) * 0.5
        left = [t for t in wing_tris if sum(u for u, _ in t) / 3 < mid_u]
        right = [t for t in wing_tris if sum(u for u, _ in t) / 3 >= mid_u]
        islands = [x for x in (left, right, wing_tris) if x]
        seen = set()
        for cluster in islands:
            key = tuple(round(x, 3) for x in wing_uv_bounds(cluster))
            if key in seen:
                continue
            seen.add(key)
            bu0, bu1, bv0, bv1 = wing_uv_bounds(cluster)
            x0 = int(bu0 * SIZE)
            x1 = int(bu1 * SIZE)
            y0 = int((1.0 - bv1) * SIZE)
            y1 = int((1.0 - bv0) * SIZE)
            paint_herringbone(draw, x0, y0, x1, y1)
            print(f"  painted island px [{x0},{y0},{x1},{y1}]")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, "PNG")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
