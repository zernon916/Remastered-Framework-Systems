# Blender 4.4: CGTrader Apocalyptic fbx_kit -> lock, booster, beacon, handheld.
# Antenna only: export_rfs_radio.py (DTry). TransmitterRadio skipped (~28° off-axis).
# Run: blender --background --python Art/export_rfs_fbx_kit.py
import bpy
import os
import json
import math
import shutil
import mathutils

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
KIT_DIR = os.path.join(ROOT, "Art", "cgtrader", "source", "fbx_kit")
MEASURE_JSON = os.path.join(ROOT, "Art", "sm_measure_fbx_kit.json")
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh")
OUT_TEX = os.path.join(ROOT, "Objects", "Textures", "radio", "fbx_kit")
OUT_REND = os.path.join(ROOT, "Objects", "Renderable")
OUT_COL = os.path.join(ROOT, "Objects", "Collision")
OUT_TOOLS = os.path.join(ROOT, "Tools")
OUT_ART = os.path.join(ROOT, "Art")
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
SHARED_ASG_PAINT = PREFIX + "/Objects/Textures/shared/rfs_asg_paint.tga"
SHARED_ASG_LOCK = PREFIX + "/Objects/Textures/shared/rfs_asg_lock.tga"
SHARED_NOR = PREFIX + "/Objects/Textures/shared/rfs_nor.tga"

KIT_DDS = [
    "Military_communication_D.dds",
    "Military_communication_N.dds",
    "Military_communication_S.dds",
]

PARTS = [
    {
        "key": "lock",
        "fbx": "LaptopRadio.FBX",
        "stem": "rfs_radio_lock",
        "rend": "rfs_radio_lock.rend",
        "target": (2.0, 1.0, 2.0),
        "grid_yaw_deg": 1.4,
        "paintable": True,
        "collision_box": {"x": 2, "y": 1, "z": 2},
        "glass_name_fragments": ["screen", "lcd", "glass", "display"],
    },
    {
        "key": "brick",
        "fbx": "WalkieTalkieRadio.FBX",
        "stem": "rfs_radio_brick",
        "rend": "rfs_radio_brick.rend",
        "target": (2.0, 1.0, 1.0),
        "grid_yaw_deg": -1.8,
        "paintable": True,
        "collision_box": {"x": 2, "y": 1, "z": 1},
    },
    {
        "key": "beacon",
        "fbx": "ArVrRadio.FBX",
        "stem": "rfs_hack_beacon",
        "rend": "rfs_hack_beacon.rend",
        "target": (2.0, 1.0, 2.0),
        "grid_yaw_deg": -4.0,
        "paintable": True,
        "collision_box": {"x": 2, "y": 1, "z": 2},
    },
    {
        "key": "handheld",
        "fbx": "WalkieTalkieRadio.FBX",
        "stem": "rfs_radio_handheld",
        "rend": "rfs_radio_handheld.rend",
        "tool_fbx": True,
        "target": (1.4, 1.4, 1.4),
        "grid_yaw_deg": -1.8,
        "paintable": True,
    },
]

os.makedirs(OUT_MESH, exist_ok=True)
os.makedirs(OUT_TEX, exist_ok=True)
os.makedirs(OUT_REND, exist_ok=True)
os.makedirs(OUT_COL, exist_ok=True)
os.makedirs(OUT_TOOLS, exist_ok=True)


def load_yaw_overrides():
    out = {}
    if not os.path.isfile(MEASURE_JSON):
        return out
    with open(MEASURE_JSON, "r", encoding="utf-8") as f:
        data = json.load(f)
    for rec in data.get("parts", []):
        joined = rec.get("joined") or {}
        yaw = joined.get("recommend_grid_yaw_deg")
        if rec.get("file") and yaw is not None:
            out[rec["file"]] = float(yaw)
    return out


YAW_OVERRIDES = load_yaw_overrides()


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def world_bounds(objs):
    mins = mathutils.Vector((1e9, 1e9, 1e9))
    maxs = mathutils.Vector((-1e9, -1e9, -1e9))
    ok = False
    for o in objs:
        for corner in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(corner)
            mins.x = min(mins.x, w.x)
            mins.y = min(mins.y, w.y)
            mins.z = min(mins.z, w.z)
            maxs.x = max(maxs.x, w.x)
            maxs.y = max(maxs.y, w.y)
            maxs.z = max(maxs.z, w.z)
            ok = True
    return (mins, maxs) if ok else (None, None)


def select_meshes(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def apply_tr(objs):
    select_meshes(objs)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def ensure_xyz_rotation(objs):
    for o in objs:
        o.rotation_mode = "XYZ"


def sanitize(name):
    out = []
    for ch in (name or "mesh"):
        out.append(ch.lower() if ch.isalnum() else "_")
    s = "".join(out).strip("_")
    while "__" in s:
        s = s.replace("__", "_")
    return s[:40] or "mesh"


def copy_kit_textures():
    os.makedirs(OUT_TEX, exist_ok=True)
    copied = []
    for name in KIT_DDS:
        src = os.path.join(KIT_DIR, name)
        dst = os.path.join(OUT_TEX, name)
        if os.path.isfile(src):
            shutil.copy2(src, dst)
            copied.append(dst)
    return copied


def kit_texture_paths():
    dif = os.path.join(OUT_TEX, "Military_communication_D.dds")
    nor = os.path.join(OUT_TEX, "Military_communication_N.dds")
    return dif, nor


def prepare_materials(objs, part):
    mapping = []
    seen = {}
    glass_frags = [g.lower() for g in part.get("glass_name_fragments", [])]
    dif_path, nor_path = kit_texture_paths()
    for o in objs:
        for slot in o.material_slots:
            mat = slot.material
            if not mat:
                continue
            original = mat.name
            base = sanitize(original)
            is_glass = any(g in original.lower() for g in glass_frags)
            if is_glass:
                base = base + "_glass"
            n = seen.get(base, 0)
            seen[base] = n + 1
            mname = base if n == 0 else f"{base}_{n + 1}"
            mat.name = mname
            mapping.append(
                {
                    "material": mname,
                    "dif": dif_path,
                    "nor": nor_path,
                    "from": original,
                    "glass": is_glass,
                }
            )
    if not mapping:
        mapping.append(
            {
                "material": "military_communication",
                "dif": dif_path,
                "nor": nor_path,
                "from": "default",
                "glass": False,
            }
        )
    return mapping


def join_meshes(objs, name):
    if not objs:
        return None
    apply_tr(objs)
    select_meshes(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    if body.data:
        body.data.name = name
    body.rotation_mode = "XYZ"
    apply_tr([body])
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")
    bpy.ops.object.mode_set(mode="OBJECT")
    return body


def snap_yaw_to_grid(body):
    apply_tr([body])
    body.rotation_mode = "XYZ"
    z = body.rotation_euler.z
    snapped = round(z / (math.pi * 0.5)) * (math.pi * 0.5)
    if abs(z - snapped) > 0.01:
        body.rotation_euler.z = snapped
        apply_tr([body])


def apply_grid_yaw(body, deg):
    apply_tr([body])
    body.rotation_mode = "XYZ"
    if deg:
        body.rotation_euler.z += math.radians(float(deg))
        apply_tr([body])
    else:
        snap_yaw_to_grid(body)


def flush_bottom(body, box_y):
    apply_tr([body])
    mins, maxs = world_bounds([body])
    if mins is None:
        return
    dz = (-box_y * 0.5) - mins.z
    if abs(dz) > 0.001:
        body.matrix_world.translation += mathutils.Vector((0.0, 0.0, dz))
        apply_tr([body])


def scale_and_sit(body, target, uniform=True):
    apply_tr([body])
    mins, maxs = world_bounds([body])
    size = maxs - mins
    tx, ty, tz = target
    if uniform:
        s = min(tx / max(size.x, 1e-6), ty / max(size.z, 1e-6), tz / max(size.y, 1e-6))
        center = (mins + maxs) * 0.5
        body.scale = (s, s, s)
        body.location = body.location - center * s
    else:
        body.scale = (
            tx / max(size.x, 1e-6),
            tz / max(size.y, 1e-6),
            ty / max(size.z, 1e-6),
        )
    apply_tr([body])
    mins, maxs = world_bounds([body])
    size = maxs - mins
    box_x = max(1, min(6, int(round(size.x + 0.45))))
    box_y = max(1, min(10, int(round(size.z + 0.45))))
    box_z = max(1, min(6, int(round(size.y + 0.45))))
    cx = 0.5 * (mins.x + maxs.x)
    cy = 0.5 * (mins.y + maxs.y)
    dz = (-box_y * 0.5) - mins.z
    body.matrix_world.translation += mathutils.Vector((-cx, -cy, dz))
    apply_tr([body])
    return {"box": {"x": box_x, "y": box_y, "z": box_z}}


def export_fbx(path):
    kw = dict(
        filepath=path,
        use_selection=True,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        global_scale=1.0,
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=True,
        object_types={"MESH"},
        use_mesh_modifiers=True,
        add_leaf_bones=False,
        path_mode="STRIP",
        embed_textures=False,
        mesh_smooth_type="FACE",
    )
    try:
        bpy.ops.export_scene.fbx(use_triangles=True, **kw)
    except TypeError:
        bpy.ops.export_scene.fbx(**kw)


def content_path(abs_path):
    rel = os.path.relpath(abs_path, ROOT).replace("\\", "/")
    return PREFIX + "/" + rel


def write_rend(part, mat_map, mesh_path):
    sub = {}
    for rec in mat_map:
        mname = rec["material"]
        nor = content_path(rec["nor"]) if os.path.isfile(rec["nor"]) else SHARED_NOR
        if rec.get("glass"):
            sub[mname] = {
                "material": "Glass",
                "custom": {
                    "glass": {
                        "ROI": 1.52,
                        "blurriness": 0.0,
                        "depthBlurDistance": 1,
                        "depthBlurMin": 0,
                        "magnification": 1.0,
                        "magnificationDirection": [1.0, 1.0],
                        "refraction": 0.12,
                        "responsiveGlow": 1.0,
                        "transmission": 0.82,
                        "transparencyBack": 0.18,
                        "transparencyFront": 0.68,
                    }
                },
                "textureList": [
                    content_path(rec["dif"]),
                    PREFIX + "/Objects/Textures/shared/rfs_asg.tga",
                    nor,
                ],
            }
        else:
            asg = SHARED_ASG_PAINT if part.get("paintable", True) else SHARED_ASG_LOCK
            sub[mname] = {
                "material": "DifAsgNor",
                "textureList": [content_path(rec["dif"]), asg, nor],
            }
    data = {
        "_comment": f"CGTrader fbx_kit / {part['key']} (Military communication kit). Antenna stays DTry.",
        "lodList": [
            {
                "mesh": content_path(mesh_path),
                "subMeshMap": sub,
                "maxViewDistance": 1000.0,
            }
        ],
    }
    out = os.path.join(OUT_REND, part["rend"])
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent="\t")
        f.write("\n")
    if part.get("tool_fbx"):
        tool_rend = os.path.join(OUT_TOOLS, "radio_handheld_preview.rend")
        with open(tool_rend, "w", encoding="utf-8") as f:
            json.dump(data, f, indent="\t")
            f.write("\n")
    return out


def write_collision(stem, box):
    path = os.path.join(OUT_COL, stem + "_col.obj")
    hx, hy, hz = box["x"] * 0.5, box["y"] * 0.5, box["z"] * 0.5
    verts = [
        (-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
        (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz),
    ]
    faces = [(1, 2, 3, 4), (5, 8, 7, 6), (1, 5, 6, 2), (4, 3, 7, 8), (1, 4, 8, 5), (2, 6, 7, 3)]
    lines = [f"# {stem} collision box", "g col"]
    for v in verts:
        lines.append("v %.6f %.6f %.6f" % v)
    for f in faces:
        lines.append("f %d %d %d %d" % f)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return path


def import_fbx(path):
    bpy.ops.import_scene.fbx(filepath=path)
    objs = mesh_objects()
    ensure_xyz_rotation(objs)
    apply_tr(objs)
    return objs


def export_part(part):
    fbx_name = part["fbx"]
    src = os.path.join(KIT_DIR, fbx_name)
    if not os.path.isfile(src):
        return {"key": part["key"], "error": "missing " + src}
    reset_scene()
    print("IMPORT", src, "PART", part["key"])
    objs = import_fbx(src)
    print("  meshes", len(objs), [o.name for o in objs])
    mat_map = prepare_materials(objs, part)
    objs = mesh_objects()
    body = join_meshes(objs, part["stem"])
    meta = scale_and_sit(body, tuple(part["target"]), uniform=part.get("uniform_scale", True))
    flush_bottom(body, meta["box"]["y"])
    yaw = YAW_OVERRIDES.get(fbx_name, part.get("grid_yaw_deg", 0.0))
    apply_grid_yaw(body, yaw)
    flush_bottom(body, meta["box"]["y"])
    mins, maxs = world_bounds([body])
    size = maxs - mins
    meta["box"] = {
        "x": max(1, min(6, int(round(size.x + 0.45)))),
        "y": max(1, min(10, int(round(size.z + 0.45)))),
        "z": max(1, min(6, int(round(size.y + 0.45)))),
    }
    meta["grid_yaw_deg"] = yaw
    fbx_out = os.path.join(OUT_TOOLS if part.get("tool_fbx") else OUT_MESH, part["stem"] + ".fbx")
    select_meshes([body])
    export_fbx(fbx_out)
    rend = write_rend(part, mat_map, fbx_out)
    col_box = part.get("collision_box") or meta["box"]
    col = write_collision(part["stem"], col_box)
    tri_count = len(body.data.polygons) if body.data else 0
    return {
        "key": part["key"],
        "stem": part["stem"],
        "source_fbx": fbx_name,
        "fbx": fbx_out,
        "rend": rend,
        "col": col,
        "materials": len(mat_map),
        "tris": tri_count,
        "box": meta["box"],
        "grid_yaw_deg": yaw,
    }


def main():
    copied = copy_kit_textures()
    print("COPIED", len(copied), "DDS ->", OUT_TEX)
    results = []
    for part in PARTS:
        results.append(export_part(part))
    meta_path = os.path.join(OUT_ART, "sm_export_fbx_kit_meta.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump({"kit_dir": KIT_DIR, "parts": results}, f, indent=2)
    print("WROTE", meta_path)
    for r in results:
        print(r)


if __name__ == "__main__":
    main()
