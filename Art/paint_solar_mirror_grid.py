"""Paint high-contrast PV cell grid into solar_mirror UV islands (rfs_solar_v5.dae)."""
import os
import re
from PIL import Image, ImageDraw

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
DAE = os.path.join(ROOT, "Objects", "Mesh", "rfs_solar_v5.dae")
OUT = os.path.join(ROOT, "Objects", "Textures", "solar", "solar_mirror_material_dif.png")
MESH_OUT = os.path.join(ROOT, "Objects", "Mesh", "Solar Mirror Material_BaseColor.png")
ASG_OUT = os.path.join(ROOT, "Objects", "Textures", "solar", "solar_mirror_asg.tga")
SIZE = 1024

# Matte opaque PV — dark silicon blues + bright silver bus bars (readable in-world).
BG = (8, 10, 14)
CELL_A = (16, 28, 52)
CELL_B = (48, 82, 128)
BUS = (240, 244, 250)
CELL_EDGE = (170, 185, 205)


def mirror_uvs():
    text = open(DAE, encoding="utf-8").read()
    m = re.search(
        r'id="rfs_solar_v5-mesh-map-0"[^>]*>\s*<float_array[^>]+count="(\d+)"[^>]*>([^<]+)</float_array>',
        text,
    )
    uv_raw = [float(x) for x in m.group(2).split()]
    uvs = list(zip(uv_raw[0::2], uv_raw[1::2]))
    tri = re.search(
        r'<triangles material="solar_mirror_material-material" count="(\d+)">\s*'
        r'(?:<input[^/]*/>\s*)+\s*<p>([^<]+)</p>',
        text,
    )
    count = int(tri.group(1))
    indices = [int(x) for x in tri.group(2).split()]
    uv_idx = [indices[v * 3 + 2] for v in range(count * 3)]
    return [uvs[i] for i in uv_idx]


def write_matte_asg():
    # DifAsgNor: low spec/metal (R), high roughness (G) — was R200 G8 (mirror glass).
    Image.new("RGBA", (16, 16), (32, 210, 0, 255)).save(ASG_OUT, "TGA")
    print("wrote", ASG_OUT)


def paint_grid():
    used = mirror_uvs()
    us = [u for u, _ in used]
    vs = [v for _, v in used]
    pad = 0.015
    u0, u1 = max(0, min(us) - pad), min(1, max(us) + pad)
    v0, v1 = max(0, min(vs) - pad), min(1, max(vs) + pad)
    x0, x1 = int(u0 * SIZE), int(u1 * SIZE)
    y0, y1 = int((1 - v1) * SIZE), int((1 - v0) * SIZE)

    img = Image.new("RGB", (SIZE, SIZE), BG)
    draw = ImageDraw.Draw(img)

    cols, rows = 4, 6
    w, h = x1 - x0, y1 - y0
    bus = max(5, SIZE // 72)
    cell_w = w // cols
    cell_h = h // rows

    for row in range(rows):
        for col in range(cols):
            cx = x0 + col * cell_w
            cy = y0 + row * cell_h
            fill = CELL_A if (row + col) % 2 == 0 else CELL_B
            draw.rectangle(
                [cx + bus, cy + bus, cx + cell_w - bus, cy + cell_h - bus],
                fill=fill,
            )
            inset = bus + max(2, bus // 2)
            draw.rectangle(
                [cx + inset, cy + inset, cx + cell_w - inset, cy + cell_h - inset],
                outline=CELL_EDGE,
                width=max(2, bus // 2),
            )

    for c in range(cols + 1):
        x = x0 + c * cell_w
        draw.rectangle([x - bus // 2, y0, x + bus // 2, y1], fill=BUS)
    for r in range(rows + 1):
        y = y0 + r * cell_h
        draw.rectangle([x0, y - bus // 2, x1, y + bus // 2], fill=BUS)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, "PNG")
    img.resize((2048, 2048), Image.Resampling.NEAREST).save(MESH_OUT, "PNG")
    write_matte_asg()
    print("wrote", OUT, "island px", x0, y0, x1, y1)


if __name__ == "__main__":
    paint_grid()
