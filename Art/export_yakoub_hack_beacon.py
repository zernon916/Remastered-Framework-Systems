# PARKED 0850-o — beacon is DTry stacked MR300 via export_rfs_radio.py (not yakoub).
# Run: blender --background --python Art/export_yakoub_hack_beacon.py
import sys
print("PARKED 0850-o: use Art/export_rfs_radio.py beacon (DTry GLB stacked MR300)")
sys.exit(0)
import bpy
import os
import json
import math
import mathutils

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
SRC = os.path.join(ROOT, "Art", "cgtrader", "source", "yakoubimedali8_military_radio.fbx")
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh")
OUT_TEX = os.path.join(ROOT, "Objects", "Textures", "radio", "yakoub")
OUT_REND = os.path.join(ROOT, "Objects", "Renderable")
OUT_COL = os.path.join(ROOT, "Objects", "Collision")
OUT_ART = os.path.join(ROOT, "Art")
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
SHARED_ASG_PAINT = PREFIX + "/Objects/Textures/shared/rfs_asg_paint.tga"
SHARED_NOR = PREFIX + "/Objects/Textures/shared/rfs_nor.tga"

PART = {
    "key": "beacon",
    "stem": "rfs_hack_beacon",
    "rend": "rfs_hack_beacon.rend",
    "target": (2.0, 1.0, 2.0),
    "grid_yaw_deg": -13.3,
    "paintable": True,
    "collision_box": {"x": 2, "y": 1, "z": 2},
    "exclude_name_prefixes": ["Text"],
}

os.makedirs(OUT_MESH, exist_ok=True)
os.makedirs(OUT_TEX, exist_ok=True)
os.makedirs(OUT_REND, exist_ok=True)
os.makedirs(OUT_COL, exist_ok=True)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def keep_mesh(o, part):
    for pref in part.get("exclude_name_prefixes", []):
        if o.name.startswith(pref):
            return False
    return True


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


def find_bsdf(mat):
    if not mat or not mat.use_nodes:
        return None
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    return None


def linked_image(inp):
    if not inp or not inp.is_linked:
        return None
    node = inp.links[0].from_node
    if node.type == "TEX_IMAGE" and node.image:
        return node.image
    for sock in getattr(node, "inputs", []):
        if sock.is_linked:
            src = sock.links[0].from_node
            if src.type == "TEX_IMAGE" and src.image:
                return src.image
    return None


def albedo_from_material(mat):
    bsdf = find_bsdf(mat)
    if not bsdf:
        return None, [0.42, 0.44, 0.38, 1.0]
    img = linked_image(bsdf.inputs.get("Base Color"))
    if img and img.size[0] > 0 and img.size[1] > 0:
        return img, None
    bc = bsdf.inputs.get("Base Color")
    col = [0.42, 0.44, 0.38, 1.0]
    if bc:
        col = [float(bc.default_value[i]) for i in range(4)]
    return None, col


def save_image_png(img, path, max_px=1024):
    copy = img.copy()
    w, h = int(copy.size[0]), int(copy.size[1])
    if w < 1 or h < 1:
        return False
    m = max(w, h)
    if m > max_px:
        copy.scale(max_px / m, max_px / m)
    copy.file_format = "PNG"
    copy.filepath_raw = path
    copy.save()
    return True


def save_solid_png(col, path, size=256):
    col = col or [0.42, 0.44, 0.38, 1.0]
    img = bpy.data.images.new("solid", size, size)
    px = [int(col[0] * 255), int(col[1] * 255), int(col[2] * 255), int(col[3] * 255)]
    img.pixels = px * (size * size)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return True


def prepare_materials(objs):
    mapping = []
    seen = {}
    for o in objs:
        for slot in o.material_slots:
            mat = slot.material
            if not mat:
                continue
            original = mat.name
            base = sanitize(original)
            n = seen.get(base, 0)
            seen[base] = n + 1
            mname = base if n == 0 else f"{base}_{n + 1}"
            mat.name = mname
            png = os.path.join(OUT_TEX, mname + "_dif.png")
            img, col = albedo_from_material(mat)
            if img:
                if not save_image_png(img, png):
                    save_solid_png(col, png)
            else:
                save_solid_png(col, png)
            mapping.append({"material": mname, "png": png, "from": original})
    if not mapping:
        png = os.path.join(OUT_TEX, "yakoub_default_dif.png")
        save_solid_png([0.42, 0.44, 0.38, 1.0], png)
        mapping.append({"material": "yakoub_default", "png": png, "from": "default"})
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
        sub[mname] = {
            "material": "DifAsgNor",
            "textureList": [
                content_path(rec["png"]),
                SHARED_ASG_PAINT,
                SHARED_NOR,
            ],
        }
    data = {
        "_comment": "CGTrader yakoubimedali8 military radio / beacon (Hack Device). Antenna stays DTry.",
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


def main():
    if not os.path.isfile(SRC):
        raise SystemExit("missing source: " + SRC)
    reset_scene()
    print("IMPORT", SRC)
    bpy.ops.import_scene.fbx(filepath=SRC)
    objs = [o for o in mesh_objects() if keep_mesh(o, PART)]
    print("  meshes", len(objs))
    ensure_xyz_rotation(objs)
    apply_tr(objs)
    mat_map = prepare_materials(objs)
    objs = [o for o in mesh_objects() if keep_mesh(o, PART)]
    body = join_meshes(objs, PART["stem"])
    meta = scale_and_sit(body, tuple(PART["target"]), uniform=True)
    flush_bottom(body, meta["box"]["y"])
    apply_grid_yaw(body, PART.get("grid_yaw_deg", 0.0))
    flush_bottom(body, meta["box"]["y"])
    mins, maxs = world_bounds([body])
    size = maxs - mins
    meta["box"] = {
        "x": max(1, min(6, int(round(size.x + 0.45)))),
        "y": max(1, min(10, int(round(size.z + 0.45)))),
        "z": max(1, min(6, int(round(size.y + 0.45)))),
    }
    fbx_out = os.path.join(OUT_MESH, PART["stem"] + ".fbx")
    select_meshes([body])
    export_fbx(fbx_out)
    rend = write_rend(PART, mat_map, fbx_out)
    col_box = PART.get("collision_box") or meta["box"]
    col = write_collision(PART["stem"], col_box)
    tri_count = len(body.data.polygons) if body.data else 0
    result = {
        "key": PART["key"],
        "stem": PART["stem"],
        "source": os.path.basename(SRC),
        "fbx": fbx_out,
        "rend": rend,
        "col": col,
        "materials": len(mat_map),
        "tris": tri_count,
        "box": col_box,
        "grid_yaw_deg": PART.get("grid_yaw_deg", 0.0),
    }
    meta_path = os.path.join(OUT_ART, "sm_export_yakoub_meta.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    print("WROTE", meta_path)
    print(result)


if __name__ == "__main__":
    main()
