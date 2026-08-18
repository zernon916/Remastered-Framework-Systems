# Blender 4.x: glb -> SM-sized FBX + PNG diffuse per material.
# Run: blender --background --python Art/convert_glb_to_sm.py

import bpy
import os
import math
import json

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh")
OUT_TEX = os.path.join(ROOT, "Objects", "Textures")
os.makedirs(OUT_MESH, exist_ok=True)
os.makedirs(OUT_TEX, exist_ok=True)

JOBS = [
    {
        "name": "deepsleep",
        "glb": os.path.join(ROOT, "Art", "sketchfab_incubator", "source", "Incubator.glb"),
        # Placeable pod: incubator-sized (SM blocks).
        "target": (3.0, 3.0, 4.0),
        "fbx": os.path.join(OUT_MESH, "rfs_deepsleep.fbx"),
    },
    {
        "name": "solar",
        "glb": os.path.join(ROOT, "Art", "sketchfab_solar", "source", "HexaRay Node - For texturing.glb"),
        "target": (3.0, 4.0, 3.0),
        "fbx": os.path.join(OUT_MESH, "rfs_solar.fbx"),
    },
]


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
    bpy.ops.import_scene.gltf(filepath=path)


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def world_bounds(objs):
    import mathutils
    mins = mathutils.Vector((1e9, 1e9, 1e9))
    maxs = mathutils.Vector((-1e9, -1e9, -1e9))
    any_ok = False
    for o in objs:
        for corner in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(corner)
            mins.x = min(mins.x, w.x)
            mins.y = min(mins.y, w.y)
            mins.z = min(mins.z, w.z)
            maxs.x = max(maxs.x, w.x)
            maxs.y = max(maxs.y, w.y)
            maxs.z = max(maxs.z, w.z)
            any_ok = True
    if not any_ok:
        return None, None
    return mins, maxs


def sanitize(name):
    out = []
    for ch in (name or "mesh"):
        if ch.isalnum():
            out.append(ch.lower())
        else:
            out.append("_")
    s = "".join(out).strip("_")
    return s[:48] or "mesh"


def unique_names(objs):
    seen = {}
    for o in objs:
        base = sanitize(o.name)
        n = seen.get(base, 0)
        seen[base] = n + 1
        o.name = base if n == 0 else ("%s_%d" % (base, n + 1))
        if o.data:
            o.data.name = o.name


def scale_and_center(objs, target):
    mins, maxs = world_bounds(objs)
    if mins is None:
        return None
    size = maxs - mins
    tx, ty, tz = target
    sx = tx / max(size.x, 1e-6)
    sy = ty / max(size.y, 1e-6)
    sz = tz / max(size.z, 1e-6)
    s = min(sx, sy, sz)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mins, maxs = world_bounds(objs)
    size = maxs - mins
    center = (mins + maxs) * 0.5
    for o in objs:
        o.scale = (s, s, s)
        o.location = o.location - center * s
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mins2, maxs2 = world_bounds(objs)
    size2 = maxs2 - mins2
    return {
        "scale": s,
        "size": [float(size2.x), float(size2.y), float(size2.z)],
        "min": [float(mins2.x), float(mins2.y), float(mins2.z)],
        "max": [float(maxs2.x), float(maxs2.y), float(maxs2.z)],
        "meshes": [o.name for o in objs],
    }


def export_textures(job_name, objs, tex_dir):
    used = []
    packed_dir = os.path.join(tex_dir, job_name)
    os.makedirs(packed_dir, exist_ok=True)
    for o in objs:
        mats = list(o.data.materials) if o.data else []
        for mat in mats:
            if not mat or not mat.use_nodes:
                continue
            for node in mat.node_tree.nodes:
                if node.type != "TEX_IMAGE" or not node.image:
                    continue
                img = node.image
                fname = sanitize(o.name) + "_dif.png"
                path = os.path.join(packed_dir, fname)
                try:
                    if img.packed_file or img.size[0] > 0:
                        img.filepath_raw = path
                        img.file_format = "PNG"
                        img.save()
                        used.append({"mesh": o.name, "png": path})
                        break
                except Exception as e:
                    print("tex save failed", o.name, e)
    return used


def export_fbx(path):
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=False,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=True,
        object_types={"MESH"},
        use_mesh_modifiers=True,
        add_leaf_bones=False,
        path_mode="COPY",
        embed_textures=False,
    )


def run_job(job):
    reset_scene()
    print("IMPORT", job["glb"])
    if not os.path.isfile(job["glb"]):
        print("MISSING", job["glb"])
        return None
    import_glb(job["glb"])
    objs = mesh_objects()
    print("meshes", len(objs), [o.name for o in objs])
    unique_names(objs)
    meta = scale_and_center(objs, job["target"])
    tex = export_textures(job["name"], objs, OUT_TEX)
    export_fbx(job["fbx"])
    result = {
        "name": job["name"],
        "fbx": job["fbx"],
        "meta": meta,
        "textures": tex,
    }
    print("DONE", json.dumps(result, indent=2))
    return result


def main():
    all_meta = []
    for job in JOBS:
        all_meta.append(run_job(job))
    out = os.path.join(ROOT, "Art", "sm_convert_meta.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(all_meta, f, indent=2)
    print("WROTE", out)


if __name__ == "__main__":
    main()
