# Downscale textures, write .rend, expand IconMap.png for Deep Sleep / solar / rechargeable.
import json
import os
from PIL import Image, ImageDraw

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
META = os.path.join(ROOT, "Art", "sm_convert_meta.json")
TEX = os.path.join(ROOT, "Objects", "Textures")
REND = os.path.join(ROOT, "Objects", "Renderable")
os.makedirs(REND, exist_ok=True)
os.makedirs(os.path.join(TEX, "shared"), exist_ok=True)

WHITE = os.path.join(TEX, "shared", "rfs_white_dif.png")
ASG = os.path.join(TEX, "shared", "rfs_asg.png")
NOR = os.path.join(TEX, "shared", "rfs_nor.png")


def save_png(img, path, size=None):
    im = img.convert("RGBA")
    if size:
        im.thumbnail((size, size), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        x = (size - im.size[0]) // 2
        y = (size - im.size[1]) // 2
        canvas.paste(im, (x, y), im)
        im = canvas
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, "PNG")


def make_shared():
    Image.new("RGBA", (16, 16), (220, 220, 220, 255)).save(WHITE)
    Image.new("RGBA", (16, 16), (180, 40, 0, 255)).save(ASG)
    Image.new("RGBA", (16, 16), (128, 128, 255, 255)).save(NOR)


def content_path(abs_path):
    rel = os.path.relpath(abs_path, ROOT).replace("\\", "/")
    return PREFIX + "/" + rel


def downscale_dir(folder, max_px=512):
    if not os.path.isdir(folder):
        return
    for name in os.listdir(folder):
        if not name.lower().endswith(".png"):
            continue
        path = os.path.join(folder, name)
        im = Image.open(path)
        if max(im.size) > max_px:
            im.thumbnail((max_px, max_px), Image.Resampling.LANCZOS)
            im.save(path, "PNG", optimize=True)


def write_rend(job_name, meshes, tex_by_mesh, out_name):
    # Joined _v1 mesh + DifAsgNor (no Painted-on-DifAsgNor). Do not regenerate
    # the 14/17-name subMeshMap that rendered invisible in world.
    white = content_path(WHITE)
    asg = PREFIX + "/Objects/Textures/shared/rfs_asg.tga"
    nor = PREFIX + "/Objects/Textures/shared/rfs_nor.tga"
    dif = white
    if job_name == "solar":
        mirrors = os.path.join(TEX, "solar", "solar_mirrors_dif.png")
        if os.path.isfile(mirrors):
            dif = content_path(mirrors)
    slot = {
        "textureList": [dif, asg, nor],
        "material": "DifAsgNor",
    }
    data = {
        "lodList": [
            {
                "mesh": PREFIX + "/Objects/Mesh/rfs_" + job_name + "_v1.fbx",
                "subMeshList": [slot],
                "maxViewDistance": 1000.0,
            }
        ]
    }
    path = os.path.join(REND, out_name)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent="\t")
    print("wrote", path, "v1 joined")


def expand_iconmap():
    src = os.path.join(ROOT, "Gui", "IconMap.png")
    old = Image.open(src).convert("RGBA")
    sheet = Image.new("RGBA", (480, 192), (0, 0, 0, 0))
    sheet.paste(old, (0, 0))

    def place(x, y, im):
        icon = im.convert("RGBA")
        icon.thumbnail((96, 96), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (96, 96), (20, 24, 28, 255))
        canvas.paste(icon, ((96 - icon.size[0]) // 2, (96 - icon.size[1]) // 2), icon)
        sheet.paste(canvas, (x, y))

    # Inventory tiles come from studio renders via Art/make_rfs_item_icons.py.
    # Never stamp mesh dif / UV atlas / HUD textures onto ItemIconsSet0.
    try:
        import importlib.util
        icon_py = os.path.join(ROOT, "Art", "make_rfs_item_icons.py")
        spec = importlib.util.spec_from_file_location("make_rfs_item_icons", icon_py)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        mod.main()
        return
    except Exception as e:
        print("studio icon stamp skipped", e)

    surv = r"C:\Steam\steamapps\common\Scrap Mechanic\Survival\Gui\IconMapSurvival.png"
    bat = Image.open(surv).crop((576, 384, 672, 480))
    crate = Image.open(surv).crop((96, 384, 192, 480))
    place(192, 96, bat)
    # Box: vanilla Survival battery container / crate (not the lightning cell).
    place(288, 96, crate)

    sheet.save(src, "PNG")
    print("iconmap", sheet.size)


def main():
    make_shared()
    downscale_dir(os.path.join(TEX, "deepsleep"), 512)
    downscale_dir(os.path.join(TEX, "solar"), 512)
    meta = json.load(open(META, encoding="utf-8"))
    for job in meta:
        name = job["name"]
        meshes = job.get("meta", {}).get("meshes") or []
        tex_by_mesh = {}
        for t in job.get("textures") or []:
            tex_by_mesh[t["mesh"]] = t["png"]
        out = "rfs_deepsleep.rend" if name == "deepsleep" else "rfs_solar.rend"
        fbx_name = "deepsleep" if name == "deepsleep" else "solar"
        write_rend(fbx_name, meshes, tex_by_mesh, out)
    expand_iconmap()


if __name__ == "__main__":
    main()
