# Rebuild ItemIconsSet0 so RFS does not replace/steal vanilla Data tiles.
# Custom Game IconMap.xml Resource ItemIconsSet0 overlays vanilla Data/Gui/IconMap.xml.
# A 480x192 sheet left Metal/Glass/etc. without indices, and Extra Large sign/LCD
# shared the empty (288,0) cell. Put RFS icons on unused row y=864 of vanilla 2048x1024.
from PIL import Image
import colorsys
import os
import re

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
VANILLA_PNG = r"C:\Steam\steamapps\common\Scrap Mechanic\Data\Gui\IconMap.png"
VANILLA_XML = r"C:\Steam\steamapps\common\Scrap Mechanic\Data\Gui\IconMap.xml"
SURV_PNG = r"C:\Steam\steamapps\common\Scrap Mechanic\Survival\Gui\IconMapSurvival.png"
RFS_PNG = os.path.join(ROOT, "Gui", "IconMap.png")
RFS_XML = os.path.join(ROOT, "Gui", "IconMap.xml")
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
TEX = "$CONTENT_" + LID + "/Gui/IconMap.png"
ROW_Y = 864  # vanilla Data IconMap last used row is y=768

# Unique unused cells (do not use vanilla (0,96) Thruster / (96,96) Controller).
RFS_TILES = [
    ("b4e8c1a0-7d2f-4a91-9c3e-29f1a8d6b5e7", 0, "hack"),
    ("c5f9d2b1-8e30-4ba2-ad4f-30a2b9e7c6f8", 96, "control"),
    ("d6a0e3c2-9f41-4cb3-be50-41b3c0f8d709", 192, "infect"),
    ("9a1528a6-acd2-44db-8050-b2f493362191", 288, "maplock"),
    ("d96c2fe4-177b-49bb-be40-e4b1bcdd8f76", 384, "gps"),
    ("e7b1f4d3-0a52-4dc4-cf61-52c4d1e9e81a", 480, "arealoader"),
    ("f8c2a5e4-1b63-4ed5-9072-63d5e2f0f92b", 576, "sign_s"),
    ("09d3b6f5-2c74-4fe6-a183-74e6f3010a3c", 672, "sign_m"),
    ("1ae4c706-3d85-40f7-b294-85f704121b4d", 768, "sign_xl"),
    ("3c06e928-5f97-42a9-d4b6-a7f926343d7f", 864, "lcd_s"),
    ("4d17fa39-60a8-43ba-e5c7-b80a37454e80", 960, "lcd_m"),
    ("5e280b4a-71b9-44cb-f6d8-c91b48565f91", 1056, "lcd_xl"),
    ("6f391c5b-82d4-4e17-9a60-c1d5e8f2a4b7", 1152, "pod"),
    ("7a402d6c-93e5-4f28-ab71-d2e6f9a3b5c8", 1248, "solar"),
    ("8b513e7d-a4f6-4039-bc82-e3f70a4b6d9e", 1344, "cell"),
    ("9c624f8e-b507-414a-cd93-f4081b5c7eaf", 1440, "box"),
    ("c2f158b0-4d7e-4a19-9c6b-8e3a1f50d247", 1536, "aimcore"),
    ("e8f4a2b1-3c7d-4e9f-8a2b-1d5e6f7a8b9c", 1632, "handheld"),
    ("d9e3b1a0-2b6c-4d8e-9f1a-0c4d5e6f7a8b", 1728, "radiobrick"),
    ("ca2d0a9f-1a5b-4c7d-8e09-fb3a4b5c6d7e", 1824, "antenna"),
    ("bb1c098e-094a-4b6c-7d08-ea293a4b5c6d", 1920, "radiolock"),
]


def crop96(im, x, y):
    return im.crop((x, y, x + 96, y + 96))


def tint_teal(im):
    out = im.copy()
    pix = im.load()
    op = out.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if a < 8:
                continue
            mx = max(r, g, b)
            mn = min(r, g, b)
            if mx - mn < 14:
                continue
            hv, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if hv < 0.18 or hv > 0.92:
                hv = (hv + 0.42) % 1.0
                nr, ng, nb = colorsys.hsv_to_rgb(hv, min(1.0, s * 1.05), v)
                op[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return out


def boost_contrast(im, gain=1.18):
    out = im.copy()
    pix = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if a < 8:
                continue
            r = max(0, min(255, int((r - 128) * gain + 128)))
            g = max(0, min(255, int((g - 128) * gain + 128)))
            b = max(0, min(255, int((b - 128) * gain + 128)))
            pix[x, y] = (r, g, b, a)
    return out


def icon_from_texture(path, bg=(20, 24, 28, 255)):
    if not os.path.isfile(path):
        return Image.new("RGBA", (96, 96), bg)
    src = Image.open(path).convert("RGBA")
    side = min(src.size[0], src.size[1])
    cx = (src.size[0] - side) // 2
    cy = (src.size[1] - side) // 2
    sq = src.crop((cx, cy, cx + side, cy + side))
    sq = sq.resize((84, 84), Image.Resampling.LANCZOS)
    sq = boost_contrast(sq)
    canvas = Image.new("RGBA", (96, 96), bg)
    canvas.paste(sq, (6, 6), sq)
    return canvas


def icon_from_file(path, fallback=None):
    if not os.path.isfile(path):
        return fallback
    im = Image.open(path).convert("RGBA")
    if im.size != (96, 96):
        im = im.resize((96, 96), Image.Resampling.LANCZOS)
    return im


def parse_vanilla_indices(xml_text):
    m = re.search(
        r'<Resource[^>]*name="ItemIconsSet0"[\s\S]*?<Group[^>]*>([\s\S]*?)</Group>',
        xml_text,
    )
    if not m:
        raise SystemExit("vanilla ItemIconsSet0 group not found")
    body = m.group(1)
    used = set()
    for pt in re.finditer(r'<Frame point="(\d+)\s+(\d+)"/>', body):
        used.add((int(pt.group(1)), int(pt.group(2))))
    return body, used


def build_rfs_indices():
    lines = []
    for uuid, x, _name in RFS_TILES:
        lines.append('\t\t\t<Index name="%s">' % uuid)
        lines.append('\t\t\t\t<Frame point="%d %d"/>' % (x, ROW_Y))
        lines.append("\t\t\t</Index>")
    return "\n".join(lines)


def main():
    vanilla_xml = open(VANILLA_XML, "r", encoding="utf-8").read()
    group_body, used = parse_vanilla_indices(vanilla_xml)
    for _uuid, x, name in RFS_TILES:
        cell = (x, ROW_Y)
        if cell in used:
            raise SystemExit("vanilla already uses RFS cell %s %s" % (cell, name))

    vanilla = Image.open(VANILLA_PNG).convert("RGBA")
    old = Image.open(RFS_PNG).convert("RGBA")
    surv = Image.open(SURV_PNG).convert("RGBA")

    tiles = {
        "hack": crop96(old, 0, 0),
        "control": crop96(old, 96, 0),
        "infect": crop96(old, 192, 0),
        # Nutt World Map gps_icon_b4.png (256²); shrink to 96² like hack beacon Art icons.
        "gps": icon_from_file(
            os.path.join(ROOT, "Gui", "gps_icon_b4.png"),
            fallback=crop96(old, 384, 0),
        ),
        # Chemical Regeneration Station / DeepSleep UUID ("pod" row) should use
        # the explicit deep sleep icon (not the old gray-crop fallback).
        "pod": icon_from_file(
            os.path.join(ROOT, "Art", "icon_deepsleep_96.png"),
            fallback=crop96(old, 0, 96),
        ),
        # Solar Panel UUID should use the explicit solar icon (not old sheet crop).
        "solar": icon_from_file(
            os.path.join(ROOT, "Art", "icon_solar_96.png"),
            fallback=crop96(old, 96, 96),
        ),
        # Use explicit rechargeable battery icons.
        # (Crop fallback keeps script usable if icons are missing.)
        "cell": icon_from_file(
            os.path.join(ROOT, "Art", "icon_recharge_cell_96.png"),
            fallback=crop96(old, 192, 96),
        ),
        "box": icon_from_file(
            os.path.join(ROOT, "Art", "icon_recharge_box_96.png"),
            fallback=crop96(old, 288, 96),
        ),
        "arealoader": crop96(vanilla, 480, 96),  # vanilla Radio
        "sign_s": crop96(surv, 2016, 1248),
        "sign_m": crop96(surv, 2112, 1248),
        "sign_xl": crop96(surv, 2208, 1248),
    }
    tiles["lcd_s"] = tint_teal(tiles["sign_s"])
    tiles["lcd_m"] = tint_teal(tiles["sign_m"])
    tiles["lcd_xl"] = tint_teal(tiles["sign_xl"])
    # Map lock cell was empty on the small sheet; keep a dark GPS-like mark.
    tiles["maplock"] = tiles["gps"].copy()
    aim_path = os.path.join(ROOT, "Art", "icon_aimcore_96.png")
    tiles["aimcore"] = icon_from_file(
        aim_path,
        fallback=Image.new("RGBA", (96, 96), (20, 24, 28, 255)),
    )

    # Radio row icons: prefer Blender renders (object-specific),
    # fallback to the old UV-diff-sheet crops if renders are missing.
    tiles["hack"] = icon_from_file(
        os.path.join(ROOT, "Art", "icon_hackbeacon_96.png"),
        fallback=tiles["hack"],
    )
    # Radio row: use each part's own texture so icons are distinct in menus.
    tex_root = os.path.join(ROOT, "Objects", "Textures", "radio")
    tiles["handheld"] = icon_from_file(
        os.path.join(ROOT, "Art", "icon_radio_handheld_96.png"),
        fallback=icon_from_texture(
            os.path.join(tex_root, "handheld", "handheltradio_dif.png"),
            (16, 24, 30, 255),
        ),
    )
    tiles["radiobrick"] = icon_from_file(
        os.path.join(ROOT, "Art", "icon_radio_brick_96.png"),
        fallback=icon_from_texture(
            os.path.join(tex_root, "brick", "radio_2_dif.png"),
            (30, 24, 16, 255),
        ),
    )
    tiles["antenna"] = icon_from_file(
        os.path.join(ROOT, "Art", "icon_radio_antenna_96.png"),
        fallback=icon_from_texture(
            os.path.join(tex_root, "antenna", "handheltradio_dif.png"),
            (20, 30, 20, 255),
        ),
    )
    tiles["radiolock"] = icon_from_file(
        os.path.join(ROOT, "Art", "icon_radio_lock_96.png"),
        fallback=icon_from_texture(
            os.path.join(tex_root, "lock", "ampfilter_first_dif.png"),
            (26, 18, 28, 255),
        ),
    )

    sheet = vanilla.copy()
    for _uuid, x, name in RFS_TILES:
        sheet.paste(tiles[name], (x, ROW_Y))
    sheet.save(RFS_PNG, "PNG")

    vanilla_group = group_body.rstrip()
    # vanilla uses spaces; keep as-is then append tab-indented RFS indices
    rfs_block = (
        '\t<Resource name="ItemIconsSet0" type="ResourceImageSet">\n'
        '\t\t<Group name="ItemIcons" texture="%s" size="96 96">\n'
        "%s\n"
        "%s\n"
        "\t\t</Group>\n"
        "\t</Resource>"
    ) % (TEX, vanilla_group, build_rfs_indices())

    xml = open(RFS_XML, "r", encoding="utf-8").read()
    xml2, n = re.subn(
        r'\t<Resource name="ItemIconsSet0" type="ResourceImageSet">[\s\S]*?</Resource>',
        rfs_block,
        xml,
        count=1,
    )
    if n != 1:
        raise SystemExit("failed to splice ItemIconsSet0 (n=%d)" % n)
    open(RFS_XML, "w", encoding="utf-8", newline="\n").write(xml2)
    print("wrote", RFS_PNG, sheet.size, "rfs row y=%d usedVanilla=%d" % (ROW_Y, len(used)))


if __name__ == "__main__":
    main()
