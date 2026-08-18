# Knock out studio backgrounds from user reference shots and stamp 96x96
# tiles onto Gui/IconMap.png (ItemIconsSet0). Do not use mesh dif/UV maps as icons.
from PIL import Image
import os

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
ASSETS = r"C:\Users\benko\.cursor\projects\c-Users-benko-Desktop-RecipeFrameworkSurvival\assets"
ICONMAP = os.path.join(ROOT, "Gui", "IconMap.png")
# Mesh studio render (Blender Art/render_rfs_colba_icon.py). Do not use cryo screenshots.
POD_TILE = os.path.join(ROOT, "Art", "icon_deepsleep_96.png")
POD_SRC = os.path.join(
    ASSETS,
    "c__Users_benko_AppData_Roaming_Cursor_User_workspaceStorage_empty-window_images_image-814a3987-7c1f-404f-83ca-9b63fb9e0522.png",
)
SOLAR_SRC = os.path.join(
    ASSETS,
    "c__Users_benko_AppData_Roaming_Cursor_User_workspaceStorage_empty-window_images_image-aec1feac-541c-44ef-a017-9e621e02136b.png",
)
# Match neighboring SM item tiles (dark empty).
TILE_BG = (20, 24, 28, 255)


def chroma(r, g, b):
    return max(r, g, b) - min(r, g, b)


def lum(r, g, b):
    return 0.299 * r + 0.587 * g + 0.114 * b


def _row_bg(pix, y, w):
    samples = []
    for x in list(range(0, min(14, w))) + list(range(max(0, w - 14), w)):
        r, g, b, _a = pix[x, y]
        samples.append((r, g, b))
    samples.sort()
    return samples[len(samples) // 2]


def knockout(src, mode):
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    pix = im.load()
    from collections import deque

    row_bg = [_row_bg(pix, y, w) for y in range(h)]

    def dist(rgb, ref):
        return abs(rgb[0] - ref[0]) + abs(rgb[1] - ref[1]) + abs(rgb[2] - ref[2])

    def is_bg(x, y):
        r, g, b, a = pix[x, y]
        if a < 8:
            return True
        c = chroma(r, g, b)
        L = lum(r, g, b)
        ref = row_bg[y]
        d = dist((r, g, b), ref)
        if mode == "pod":
            # Keep the white shell (brighter than the grey gradient) and cyan FX.
            if c > 22:
                return False
            if L > lum(*ref) + 18:
                return False
            return d < 48 or L < lum(*ref) - 8
        if c > 16:
            return False
        return d < 36 or L < 88

    vis = [[False] * w for _ in range(h)]
    bg = [[False] * w for _ in range(h)]
    q = deque()

    def enqueue(x, y):
        if 0 <= x < w and 0 <= y < h and not vis[y][x]:
            vis[y][x] = True
            q.append((x, y))

    for x in range(w):
        enqueue(x, 0)
        enqueue(x, h - 1)
    for y in range(h):
        enqueue(0, y)
        enqueue(w - 1, y)

    while q:
        x, y = q.popleft()
        if not is_bg(x, y):
            continue
        bg[y][x] = True
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            enqueue(x + dx, y + dy)

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            if bg[y][x]:
                continue
            op[x, y] = pix[x, y]
    return out


def crop_alpha(im, pad_frac=0.06):
    bbox = im.getbbox()
    if not bbox:
        return im
    x0, y0, x1, y1 = bbox
    bw, bh = x1 - x0, y1 - y0
    pad = int(max(bw, bh) * pad_frac)
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(im.size[0], x1 + pad)
    y1 = min(im.size[1], y1 + pad)
    return im.crop((x0, y0, x1, y1))


def to_tile(im, size=96):
    im = crop_alpha(im)
    im.thumbnail((size - 4, size - 4), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), TILE_BG)
    x = (size - im.size[0]) // 2
    y = (size - im.size[1]) // 2
    canvas.paste(im, (x, y), im)
    return canvas


def main():
    if os.path.isfile(POD_TILE):
        pod = Image.open(POD_TILE).convert("RGBA")
        if pod.size != (96, 96):
            pod = to_tile(pod)
    elif os.path.isfile(POD_SRC):
        pod = to_tile(knockout(POD_SRC, "pod"))
    else:
        raise SystemExit("missing pod icon")
    if not os.path.isfile(SOLAR_SRC):
        raise SystemExit("missing solar studio shot")
    solar = to_tile(knockout(SOLAR_SRC, "solar"))
    sheet = Image.open(ICONMAP).convert("RGBA")
    if sheet.size[0] < 2048 or sheet.size[1] < 1024:
        bigger = Image.new("RGBA", (max(sheet.size[0], 2048), max(sheet.size[1], 1024)), (0, 0, 0, 0))
        bigger.paste(sheet, (0, 0))
        sheet = bigger
    # Unused vanilla Data row y=864. Do not paste onto (0,96) Thruster / (96,96) Controller.
    sheet.paste(pod, (1152, 864))
    sheet.paste(solar, (1248, 864))
    # Cell 8b513e7d → (1344,864). Box 9c624f8e → (1440,864).
    surv = r"C:\Steam\steamapps\common\Scrap Mechanic\Survival\Gui\IconMapSurvival.png"
    if os.path.isfile(surv):
        surv_im = Image.open(surv).convert("RGBA")
        sheet.paste(surv_im.crop((576, 384, 672, 480)), (1344, 864))
        sheet.paste(surv_im.crop((96, 384, 192, 480)), (1440, 864))
    sheet.save(ICONMAP, "PNG")
    preview_dir = os.path.join(ROOT, "Art")
    pod.save(os.path.join(preview_dir, "icon_deepsleep_96.png"), "PNG")
    solar.save(os.path.join(preview_dir, "icon_solar_96.png"), "PNG")
    print("wrote", ICONMAP, "tiles pod/solar/cell/crate", sheet.size)


if __name__ == "__main__":
    main()
