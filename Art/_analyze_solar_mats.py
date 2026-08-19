"""Measure solar material UV coverage and texture contrast (no game edits)."""
import os
import re
from PIL import Image

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
DAE = os.path.join(ROOT, "Objects", "Mesh", "rfs_solar_v5.dae")
FBX = os.path.join(ROOT, "Objects", "Mesh", "rfs_solar_v5.fbx")


def main():
    text = open(DAE, encoding="utf-8").read()
    for mat, count in re.findall(
        r'<triangles material="([^"]+)" count="(\d+)">', text
    ):
        print(f"tris {mat} {count}")

    uv_m = re.search(
        r'id="rfs_solar_v5-mesh-map-0"[^>]*>\s*'
        r'<float_array[^>]+count="(\d+)"[^>]*>([^<]+)</float_array>',
        text,
    )
    uv_raw = [float(x) for x in uv_m.group(2).split()]
    uvs = list(zip(uv_raw[0::2], uv_raw[1::2]))

    pos_m = re.search(
        r'id="rfs_solar_v5-mesh-positions"[^>]*>\s*'
        r'<float_array[^>]+count="(\d+)"[^>]*>([^<]+)</float_array>',
        text,
    )
    pos_raw = [float(x) for x in pos_m.group(2).split()]
    positions = list(zip(pos_raw[0::3], pos_raw[1::3], pos_raw[2::3]))

    def analyze(matname):
        tri = re.search(
            rf'<triangles material="{re.escape(matname)}" count="(\d+)">\s*'
            r'(?:<input[^/]*/>\s*)+\s*<p>([^<]+)</p>',
            text,
        )
        count = int(tri.group(1))
        indices = [int(x) for x in tri.group(2).split()]
        used_uv = []
        used_pos = []
        areas = []
        for t in range(count):
            p3 = []
            u3 = []
            for k in range(3):
                base = t * 9 + k * 3
                p3.append(positions[indices[base]])
                u3.append(uvs[indices[base + 2]])
            used_uv.extend(u3)
            used_pos.extend(p3)
            # approx world area via cross product
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
        xs = [p[0] for p in used_pos]
        ys = [p[1] for p in used_pos]
        zs = [p[2] for p in used_pos]
        print(
            f"{matname}: tris={count} areaSum={sum(areas):.4f} "
            f"UV u=[{min(us):.4f},{max(us):.4f}] v=[{min(vs):.4f},{max(vs):.4f}] "
            f"pos x=[{min(xs):.3f},{max(xs):.3f}] y=[{min(ys):.3f},{max(ys):.3f}] "
            f"z=[{min(zs):.3f},{max(zs):.3f}]"
        )
        # sample albedo under UV
        return used_uv

    panel_uv = analyze("panel_base_material-material")
    mirror_uv = analyze("solar_mirror_material-material")

    panel = Image.open(
        os.path.join(ROOT, "Objects", "Textures", "solar", "panel_base_material_dif.png")
    ).convert("RGB")
    mirror = Image.open(
        os.path.join(ROOT, "Objects", "Textures", "solar", "solar_mirror_material_dif.png")
    ).convert("RGB")
    sketch_m = Image.open(
        os.path.join(
            ROOT,
            "Art",
            "sketchfab_solar",
            "textures",
            "Solar Mirror Material_BaseColor_19.png",
        )
    ).convert("RGB")

    def sample(img, used, label, n=200):
        w, h = img.size
        step = max(1, len(used) // n)
        cols = []
        for u, v in used[::step]:
            x = min(w - 1, max(0, int(u * (w - 1))))
            y = min(h - 1, max(0, int((1.0 - v) * (h - 1))))
            cols.append(img.getpixel((x, y)))
        r = sum(c[0] for c in cols) / len(cols)
        g = sum(c[1] for c in cols) / len(cols)
        b = sum(c[2] for c in cols) / len(cols)
        lums = [0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2] for c in cols]
        print(
            f"  sample {label}: mean=({r:.1f},{g:.1f},{b:.1f}) "
            f"lum[{min(lums):.1f},{max(lums):.1f}] n={len(cols)}"
        )

    print("What panel_base tris actually sample:")
    sample(panel, panel_uv, "panel_base_material_dif.png")
    print("What solar_mirror tris actually sample:")
    sample(mirror, mirror_uv, "solar_mirror_material_dif.png")
    sample(sketch_m, mirror_uv, "Sketchfab Solar Mirror (orig)")

    # FBX embedded texture name refs
    fbx = open(FBX, "rb").read()
    for needle in [
        b"Panel Base Material_BaseColor",
        b"Solar Mirror Material_BaseColor",
        b"panel_base_material_dif",
        b"solar_mirror_material_dif",
        b"solar_mirrors_dif",
        b"solar_panel_base_dif",
    ]:
        print(f"FBX count {needle.decode()}: {fbx.count(needle)}")

    # contrast in painted blue region of panel
    w, h = panel.size
    blues = []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = panel.getpixel((x, y))
            if b > 150 and b > r + 40:
                blues.append(0.3 * r + 0.59 * g + 0.11 * b)
    if blues:
        print(
            f"panel blue-region lum n={len(blues)} "
            f"min={min(blues):.1f} max={max(blues):.1f} "
            f"mean={sum(blues)/len(blues):.1f} "
            f"spread={max(blues)-min(blues):.1f}"
        )


if __name__ == "__main__":
    main()
