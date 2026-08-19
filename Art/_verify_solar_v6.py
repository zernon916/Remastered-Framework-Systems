"""Verify rfs_solar_v6 overlay UVs sample the 4x6 cells texture."""
import os
import re
from PIL import Image

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
DAE = os.path.join(ROOT, "Objects", "Mesh", "rfs_solar_v6.dae")
FBX = os.path.join(ROOT, "Objects", "Mesh", "rfs_solar_v6.fbx")
PNG = os.path.join(ROOT, "Objects", "Textures", "solar", "solar_cells_dif.png")
REND = os.path.join(ROOT, "Objects", "Renderable", "rfs_solar.rend")


def main():
    dae = open(DAE, encoding="utf-8").read()
    print("=== tris ===")
    for mat, count in re.findall(r'<triangles material="([^"]+)" count="(\d+)">', dae):
        print(mat, count)
    uv_m = re.search(
        r'id="rfs_solar_v6-mesh-map-0"[^>]*>\s*'
        r'<float_array[^>]+count="(\d+)"[^>]*>([^<]+)</float_array>',
        dae,
    )
    uv_raw = [float(x) for x in uv_m.group(2).split()]
    uvs = list(zip(uv_raw[0::2], uv_raw[1::2]))
    pos_m = re.search(
        r'id="rfs_solar_v6-mesh-positions"[^>]*>\s*'
        r'<float_array[^>]+count="(\d+)"[^>]*>([^<]+)</float_array>',
        dae,
    )
    pos_raw = [float(x) for x in pos_m.group(2).split()]
    positions = list(zip(pos_raw[0::3], pos_raw[1::3], pos_raw[2::3]))
    tri = re.search(
        r'<triangles material="solar_cells-material" count="(\d+)">\s*'
        r'(?:<input[^/]*/>\s*)+\s*<p>([^<]+)</p>',
        dae,
    )
    count = int(tri.group(1))
    indices = [int(x) for x in tri.group(2).split()]
    used_uv = []
    areas = []
    for t in range(count):
        p3 = []
        u3 = []
        for k in range(3):
            base = t * 9 + k * 3
            p3.append(positions[indices[base]])
            u3.append(uvs[indices[base + 2]])
        used_uv.extend(u3)
        ax, ay, az = (
            p3[1][0] - p3[0][0],
            p3[1][1] - p3[0][1],
            p3[1][2] - p3[0][2],
        )
        bx, by, bz = (
            p3[2][0] - p3[0][0],
            p3[2][1] - p3[0][1],
            p3[2][2] - p3[0][2],
        )
        cx = ay * bz - az * by
        cy = az * bx - ax * bz
        cz = ax * by - ay * bx
        areas.append(0.5 * (cx * cx + cy * cy + cz * cz) ** 0.5)
    us = [u for u, _ in used_uv]
    vs = [v for _, v in used_uv]
    print(
        f"solar_cells tris={count} area={sum(areas):.4f} "
        f"UV u=[{min(us):.4f},{max(us):.4f}] v=[{min(vs):.4f},{max(vs):.4f}]"
    )
    img = Image.open(PNG).convert("RGB")
    w, h = img.size
    cols = []
    step = max(1, len(used_uv) // 80)
    for u, v in used_uv[::step]:
        x = min(w - 1, max(0, int(u * (w - 1))))
        y = min(h - 1, max(0, int((1.0 - v) * (h - 1))))
        cols.append(img.getpixel((x, y)))
    lums = [0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2] for c in cols]
    mean = tuple(round(sum(c[i] for c in cols) / len(cols), 1) for i in range(3))
    print(
        f"sample solar_cells_dif mean RGB={mean} "
        f"lum[{min(lums):.1f},{max(lums):.1f}] spread={max(lums) - min(lums):.1f}"
    )
    fbx = open(FBX, "rb").read()
    for n in [
        b"solar_mirror_material",
        b"solar_cells",
        b"solar_cells_dif",
        b"Solar Mirror Material_BaseColor",
        b"panel_base_asg",
        b"solar_mirror_asg",
    ]:
        print("FBX", n.decode(), fbx.count(n))
    rend = open(REND, encoding="utf-8").read()
    print("rend Glass", "Glass" in rend)
    print("rend solar_mirror", "solar_mirror" in rend)
    print("rend v6", "rfs_solar_v6.fbx" in rend)


if __name__ == "__main__":
    main()
