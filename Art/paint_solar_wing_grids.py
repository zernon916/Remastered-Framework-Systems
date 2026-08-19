"""Paint high-contrast matte PV herringbone onto BOTH solar wing slots.

Measured (rfs_solar_v5):
- panel_base_material: 3012 tris, area~22.8 (wing bodies)
- solar_mirror_material: 36 tris, area~13.7 (glass overlay on wings)
  Sketchfab UVs sample solid (31,86,233) — zero grid under those UVs.
- panel_base was using shared rfs_asg (R200/G80) = glossy glass washout.

Writes dif + matte ASG for both; overwrites Mesh/ and fbm duplicates.
"""
import os
import re
from PIL import Image, ImageDraw

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
DAE = os.path.join(ROOT, "Objects", "Mesh", "rfs_solar_v5.dae")
TEX = os.path.join(ROOT, "Objects", "Textures", "solar")
MESH = os.path.join(ROOT, "Objects", "Mesh")
FBM = os.path.join(MESH, "rfs_solar.fbm")
PANEL_SRC = os.path.join(
    ROOT, "Art", "sketchfab_solar", "textures", "Panel Base Material_BaseColor_16.png"
)

SIZE = 1024
# High-contrast matte PV (readable under SM lighting).
BG = (12, 28, 72)
LINE = (220, 235, 255)
BUS = (245, 248, 252)
CELL_DARK = (8, 18, 48)
MATTE_ASG = (24, 220, 0, 255)  # low metal/spec, high roughness


def load_dae():
    text = open(DAE, encoding="utf-8").read()
    uv_m = re.search(
        r'id="rfs_solar_v5-mesh-map-0"[^>]*>\s*'
        r'<float_array[^>]+count="(\d+)"[^>]*>([^<]+)</float_array>',
        text,
    )
    uv_raw = [float(x) for x in uv_m.group(2).split()]
    uvs = list(zip(uv_raw[0::2], uv_raw[1::2]))
    return text, uvs


def mat_uvs(text, uvs, matname):
    tri = re.search(
        rf'<triangles material="{re.escape(matname)}" count="(\d+)">\s*'
        r'(?:<input[^/]*/>\s*)+\s*<p>([^<]+)</p>',
        text,
    )
    count = int(tri.group(1))
    indices = [int(x) for x in tri.group(2).split()]
    out = []
    for t in range(count):
        for k in range(3):
            out.append(uvs[indices[t * 9 + k * 3 + 2]])
    return out


def uv_bounds(used, pad=0.012):
    us = [u for u, _ in used]
    vs = [v for _, v in used]
    return (
        max(0.0, min(us) - pad),
        min(1.0, max(us) + pad),
        max(0.0, min(vs) - pad),
        min(1.0, max(vs) + pad),
    )


def to_px(u0, u1, v0, v1, size=SIZE):
    x0, x1 = int(u0 * size), int(u1 * size)
    y0, y1 = int((1.0 - v1) * size), int((1.0 - v0) * size)
    return x0, y0, x1, y1


def paint_herringbone(draw, x0, y0, x1, y1):
    w, h = x1 - x0, y1 - y0
    if w < 8 or h < 8:
        return
    draw.rectangle([x0, y0, x1, y1], fill=BG)
    step = max(5, min(w, h) // 18)
    thick = max(2, step // 3)
    # Dense zigzag / herringbone (Sketchfab Solar Mirror style).
    for y in range(y0 - step * 2, y1 + step * 2, step):
        pts = []
        x = x0 - step
        flip = ((y - y0) // step) % 2 == 0
        while x < x1 + step * 2:
            cy = y + (step // 2 if flip else -step // 2)
            pts.append((x, cy))
            x += step
            flip = not flip
        for i in range(len(pts) - 1):
            draw.line([pts[i], pts[i + 1]], fill=LINE, width=thick)
    # Cross bus bars for cell readability.
    cell = max(10, step * 3)
    bus_w = max(2, thick)
    for cx in range(x0, x1 + 1, cell):
        draw.rectangle([cx - bus_w // 2, y0, cx + bus_w // 2, y1], fill=BUS)
    for cy in range(y0, y1 + 1, cell):
        draw.rectangle([x0, cy - bus_w // 2, x1, cy + bus_w // 2], fill=BUS)
    # Dark cell inset corners so it isn't one flat blue plate.
    inset = max(3, cell // 5)
    for cx in range(x0, x1, cell):
        for cy in range(y0, y1, cell):
            ix0, iy0 = cx + inset, cy + inset
            ix1, iy1 = min(x1, cx + cell - inset), min(y1, cy + cell - inset)
            if ix1 > ix0 and iy1 > iy0:
                draw.rectangle(
                    [ix0, iy0, ix1, iy1],
                    outline=CELL_DARK,
                    width=max(1, thick // 2),
                )


def write_asg(path):
    Image.new("RGBA", (16, 16), MATTE_ASG).save(path, "TGA")
    print("wrote", path)


def save_all(img, basename_png, mesh_name=None, fbm_name=None):
    out = os.path.join(TEX, basename_png)
    img.save(out, "PNG")
    print("wrote", out)
    big = img.resize((2048, 2048), Image.Resampling.NEAREST)
    if mesh_name:
        mp = os.path.join(MESH, mesh_name)
        big.save(mp, "PNG")
        print("wrote", mp)
    if fbm_name:
        fp = os.path.join(FBM, fbm_name)
        big.save(fp, "PNG")
        print("wrote", fp)


def paint_mirror(text, uvs):
    used = mat_uvs(text, uvs, "solar_mirror_material-material")
    u0, u1, v0, v1 = uv_bounds(used, pad=0.02)
    x0, y0, x1, y1 = to_px(u0, u1, v0, v1)
    print(f"mirror UV island px [{x0},{y0},{x1},{y1}] nUV={len(used)}")
    img = Image.new("RGB", (SIZE, SIZE), (8, 10, 14))
    draw = ImageDraw.Draw(img)
    paint_herringbone(draw, x0, y0, x1, y1)
    save_all(
        img,
        "solar_mirror_material_dif.png",
        mesh_name="Solar Mirror Material_BaseColor.png",
        fbm_name="solar_mirrors_dif.png",
    )
    # also kill legacy name if present
    legacy = os.path.join(TEX, "solar_mirrors_dif.png")
    img.save(legacy, "PNG")
    write_asg(os.path.join(TEX, "solar_mirror_asg.tga"))


def paint_panel(text, uvs):
    used = mat_uvs(text, uvs, "panel_base_material-material")
    src = Image.open(PANEL_SRC).convert("RGB")
    if src.size != (SIZE, SIZE):
        src = src.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    src_px = list(src.getdata())

    # Wing islands: brown/tan octagons in original Panel Base albedo.
    wing_uv = []
    for i in range(0, len(used), 3):
        tri = used[i : i + 3]
        browns = 0
        for u, v in tri:
            x = int(u * (SIZE - 1))
            y = int((1.0 - v) * (SIZE - 1))
            r, g, b = src_px[y * SIZE + x][:3]
            if r > 95 and g > 70 and b < 200 and r > g and g > b * 0.7:
                browns += 1
        if browns >= 2:
            wing_uv.append(tri)

    print(f"panel wing tris~{len(wing_uv)} of {len(used)//3}")
    img = src.copy()
    draw = ImageDraw.Draw(img)

    if wing_uv:
        flat = [uv for tri in wing_uv for uv in tri]
        mid_u = sum(u for u, _ in flat) / len(flat)
        left = [t for t in wing_uv if sum(u for u, _ in t) / 3 < mid_u]
        right = [t for t in wing_uv if sum(u for u, _ in t) / 3 >= mid_u]
        seen = set()
        for cluster in (left, right):
            if not cluster:
                continue
            key = tuple(round(x, 3) for x in uv_bounds([uv for t in cluster for uv in t]))
            if key in seen:
                continue
            seen.add(key)
            bu0, bu1, bv0, bv1 = uv_bounds([uv for t in cluster for uv in t], pad=0.01)
            x0, y0, x1, y1 = to_px(bu0, bu1, bv0, bv1)
            paint_herringbone(draw, x0, y0, x1, y1)
            print(f"  panel island px [{x0},{y0},{x1},{y1}]")

    save_all(
        img,
        "panel_base_material_dif.png",
        mesh_name="Panel Base Material_BaseColor.png",
        fbm_name="solar_panel_base_dif.png",
    )
    # legacy texture name used by older paths
    legacy = os.path.join(TEX, "solar_panel_base_dif.png")
    img.resize((512, 512), Image.Resampling.LANCZOS).save(legacy, "PNG")
    write_asg(os.path.join(TEX, "panel_base_asg.tga"))


def main():
    text, uvs = load_dae()
    paint_mirror(text, uvs)
    paint_panel(text, uvs)
    print("done")


if __name__ == "__main__":
    main()
