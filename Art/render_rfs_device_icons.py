# EEVEE 96x96 inventory icons for Crafting Station + both tablets.
# blender --background --python Art/render_rfs_device_icons.py
import os
import math
import bpy
import mathutils

ROOT = r"C:\Coding Projects\RemasteredFrameworkSystems"
OUT = os.path.join(ROOT, "Art")
TILE_BG = (20.0 / 255.0, 24.0 / 255.0, 28.0 / 255.0, 1.0)
TEX_TAB = os.path.join(ROOT, "Objects", "Textures", "tablets")
TEX_ST = os.path.join(ROOT, "Objects", "Textures", "craftstation")

JOBS = [
    {
        "out": "icon_craft_station_96.png",
        "fbx": os.path.join(ROOT, "Objects", "Mesh", "rfs_crafting_station.fbx"),
        "size": 3.2,
        "rot": (0.0, 0.0, 0.0),
        "face": True,
        "front": "y-",
        "tex": {
            "craftingstation_body": os.path.join(TEX_ST, "craftingstation_dif.png"),
            "craftingstation_slider": os.path.join(TEX_ST, "craftingstation_dif.png"),
            "craftingstation_screen": os.path.join(TEX_ST, "craftingstation_screen_dif.png"),
            "submesh_light_01": os.path.join(TEX_ST, "craftingstation_light01_dif.png"),
            "submesh_light_02": os.path.join(TEX_ST, "craftingstation_light02_dif.png"),
            "submesh_light_01_green": os.path.join(TEX_ST, "craftingstation_light01_dif.png"),
            "submesh_light_01_red": os.path.join(TEX_ST, "craftingstation_light02_dif.png"),
            "submesh_light_02_green": os.path.join(TEX_ST, "craftingstation_light01_dif.png"),
            "submesh_light_02_red": os.path.join(TEX_ST, "craftingstation_light02_dif.png"),
        },
    },
    {
        "out": "icon_farmers_tablet_96.png",
        "fbx": os.path.join(ROOT, "Tools", "rfs_farmers_tablet.fbx"),
        "size": 3.4,
        "rot": (0.0, 0.0, 0.0),
        "face": True,
        "tex": {
            "mat_farmers_tablet_body_black": os.path.join(TEX_TAB, "mat_farmers_tablet_body_black.png"),
            "mat_farmers_tablet_trim_yellow": os.path.join(TEX_TAB, "mat_farmers_tablet_trim_yellow.png"),
            "mat_farmers_tablet_screen": os.path.join(TEX_TAB, "mat_farmers_tablet_screen.png"),
            "mat_farmers_tablet_metal": os.path.join(TEX_TAB, "mat_farmers_tablet_metal.png"),
            "farmers_tablet_charging_port_recess": os.path.join(TEX_TAB, "farmers_tablet_charging_port_recess.png"),
            "mat_nameplate_dark": os.path.join(TEX_TAB, "mat_nameplate_dark.png"),
            "mat_name_text_yellow": os.path.join(TEX_TAB, "mat_name_text_yellow.png"),
        },
    },
    {
        "out": "icon_mobile_crafting_tablet_96.png",
        "fbx": os.path.join(ROOT, "Tools", "rfs_mobile_crafting_tablet.fbx"),
        "size": 3.4,
        "rot": (0.0, 0.0, 0.0),
        "face": True,
        "tex": {
            "mat_mcs_body_black": os.path.join(TEX_TAB, "mat_mcs_body_black.png"),
            "mat_mcs_trim_yellow": os.path.join(TEX_TAB, "mat_mcs_trim_yellow.png"),
            "mat_mcs_screen": os.path.join(TEX_TAB, "mat_mcs_screen.png"),
            "mat_mcs_metal": os.path.join(TEX_TAB, "mat_mcs_metal.png"),
            "mcs_charging_port_recess": os.path.join(TEX_TAB, "mcs_charging_port_recess.png"),
            "mat_nameplate_dark": os.path.join(TEX_TAB, "mat_nameplate_dark.png"),
            "mat_name_text_yellow": os.path.join(TEX_TAB, "mat_name_text_yellow.png"),
        },
    },
]


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH" and o.data]


def bounds(objs):
    mins = mathutils.Vector((1e9, 1e9, 1e9))
    maxs = mathutils.Vector((-1e9, -1e9, -1e9))
    ok = False
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            mins.x, mins.y, mins.z = min(mins.x, w.x), min(mins.y, w.y), min(mins.z, w.z)
            maxs.x, maxs.y, maxs.z = max(maxs.x, w.x), max(maxs.y, w.y), max(maxs.z, w.z)
            ok = True
    return (mins, maxs) if ok else (None, None)


def look_at(obj, target):
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def principled(dif):
    mat = bpy.data.materials.new("rfs_icon")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = 0.08
    bsdf.inputs["Roughness"].default_value = 0.4
    if dif and os.path.isfile(dif):
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(dif)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if "screen" in os.path.basename(dif).lower():
            bsdf.inputs["Emission Color"].default_value = (1, 1, 1, 1)
            try:
                bsdf.inputs["Emission Strength"].default_value = 0.35
            except Exception:
                pass
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def assign(objs, texmap):
    cache = {}
    keys = list(texmap.keys())
    for o in objs:
        slots = list(o.material_slots)
        print("mesh", o.name, "slots", [s.name for s in slots])
        if not slots:
            path = next(iter(texmap.values()), None)
            if path not in cache:
                cache[path] = principled(path)
            o.data.materials.append(cache[path])
            continue
        for slot in slots:
            n = slot.name.split(".")[0]
            path = texmap.get(n)
            if not path:
                low = n.lower()
                path = next((texmap[k] for k in keys if k.lower() in low or low in k.lower()), None)
            if not path:
                if "screen" in n.lower():
                    path = next((texmap[k] for k in keys if "screen" in k), None)
                elif "trim" in n.lower() or "yellow" in n.lower():
                    path = next((texmap[k] for k in keys if "trim" in k), None)
                elif "metal" in n.lower():
                    path = next((texmap[k] for k in keys if "metal" in k), None)
                elif "port" in n.lower() or "recess" in n.lower():
                    path = next((texmap[k] for k in keys if "port" in k or "recess" in k), None)
                elif "name" in n.lower() or "plate" in n.lower():
                    path = next((texmap[k] for k in keys if "name" in k or "plate" in k), None)
                else:
                    path = next((texmap[k] for k in keys if "body" in k), next(iter(texmap.values()), None))
            if path not in cache:
                cache[path] = principled(path)
            slot.material = cache[path]


def face_on(objs):
    mn, mx = bounds(objs)
    if not mn:
        return mathutils.Vector((2.4, -2.8, 1.8))
    size = mx - mn
    axes = [(size.x, 0), (size.y, 1), (size.z, 2)]
    axes.sort()
    thin = axes[0][1]
    wide = axes[-1][1]
    dist = max(size.x, size.y, size.z) * 1.55
    loc = mathutils.Vector((0.0, 0.0, 0.0))
    loc[thin] = -dist
    loc[wide] = dist * 0.18
    loc.z += dist * 0.12
    print("bounds", tuple(size), "cam", tuple(loc), "thin", thin)
    return loc


def fit(objs, size):
    mn, mx = bounds(objs)
    if not mn:
        return
    c = (mn + mx) * 0.5
    for o in objs:
        o.location -= c
    mn, mx = bounds(objs)
    m = max((mx - mn).x, (mx - mn).y, (mx - mn).z)
    if m <= 0:
        return
    f = size / m
    for o in objs:
        o.scale *= f
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    try:
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    except Exception:
        pass


def render_job(job):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if not os.path.isfile(job["fbx"]):
        print("missing", job["fbx"])
        return False
    bpy.ops.import_scene.fbx(filepath=job["fbx"])
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            o.hide_render = True
            o.hide_viewport = True
    objs = meshes()
    if not objs:
        print("no mesh", job["out"])
        return False
    rx, ry, rz = [math.radians(a) for a in job["rot"]]
    for o in objs:
        o.rotation_euler[0] += rx
        o.rotation_euler[1] += ry
        o.rotation_euler[2] += rz
    bpy.context.view_layer.update()
    fit(objs, job["size"])
    assign(objs, job["tex"])
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 96
    scene.render.resolution_y = 96
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = os.path.join(OUT, job["out"])
    scene.view_settings.view_transform = "Standard"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("w")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = TILE_BG
        bg.inputs[1].default_value = 1.0
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    if job.get("face"):
        cam.location = face_on(objs)
        if job.get("front") == "y-":
            mn, mx = bounds(objs)
            size = mx - mn
            dist = max(size.x, size.y, size.z) * 1.7
            cam.location = mathutils.Vector((0.0, -dist, size.z * 0.04))
        elif job.get("front") == "y+":
            mn, mx = bounds(objs)
            size = mx - mn
            dist = max(size.x, size.y, size.z) * 1.7
            cam.location = mathutils.Vector((0.0, dist, size.z * 0.04))
        elif job.get("front") == "x-":
            mn, mx = bounds(objs)
            size = mx - mn
            dist = max(size.x, size.y, size.z) * 1.7
            cam.location = mathutils.Vector((-dist, 0.0, size.z * 0.04))
        elif job.get("front") == "z+":
            mn, mx = bounds(objs)
            size = mx - mn
            dist = max(size.x, size.y, size.z) * 1.7
            cam.location = mathutils.Vector((0.0, 0.0, dist))
        elif job.get("front") == "z-":
            mn, mx = bounds(objs)
            size = mx - mn
            dist = max(size.x, size.y, size.z) * 1.7
            cam.location = mathutils.Vector((0.0, 0.0, -dist))
    else:
        cam.location = mathutils.Vector((2.4, -2.8, 1.8))
    look_at(cam, mathutils.Vector((0, 0, 0)))
    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
    key.data.energy = 250
    key.data.size = 3
    key.location = cam.location + mathutils.Vector((1.2, 0.4, 1.6))
    scene.collection.objects.link(key)
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "AREA"))
    fill.data.energy = 80
    fill.data.size = 4
    fill.location = cam.location + mathutils.Vector((-2.0, 0.8, 0.6))
    scene.collection.objects.link(fill)
    bpy.ops.render.render(write_still=True)
    print("wrote", scene.render.filepath)
    return True


def main():
    os.makedirs(OUT, exist_ok=True)
    ok = True
    for job in JOBS:
        if not render_job(job):
            ok = False
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
