# Blender 4.4: R&S Military radio (DTry, CC-BY-4.0) -> antenna only.
# Lock/brick/beacon/handheld: Art/export_rfs_fbx_kit.py (Apocalyptic fbx_kit).
# Run: blender --background --python Art/export_rfs_radio.py
#      RFS_EXPORT_KEYS=antenna blender --background --python Art/export_rfs_radio.py
import bpy
import os
import json
import math
import mathutils

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
GLB = r"C:\Users\benko\Downloads\rs_military_radio.glb"
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh")
OUT_TEX = os.path.join(ROOT, "Objects", "Textures", "radio")
OUT_REND = os.path.join(ROOT, "Objects", "Renderable")
OUT_COL = os.path.join(ROOT, "Objects", "Collision")
OUT_TOOLS = os.path.join(ROOT, "Tools")
OUT_ART = os.path.join(ROOT, "Art")
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
SHARED_ASG_PAINT = PREFIX + "/Objects/Textures/shared/rfs_asg_paint.tga"
SHARED_ASG_LOCK = PREFIX + "/Objects/Textures/shared/rfs_asg_lock.tga"
SHARED_NOR = PREFIX + "/Objects/Textures/shared/rfs_nor.tga"

# Node name fragments (merge all mesh children under matching roots).
PARTS = [
    {
        "key": "antenna",
        "stem": "rfs_radio_antenna",
        "rend": "rfs_radio_antenna.rend",
        "roots": ["HandheltRadio.026_low.001", "HandheltRadio.031_low"],
        "exclude": ["HandheltRadio.028_low"],
        "target": (1.0, 7.0, 1.0),
        "uniform_scale": False,
        "align_long_axis_z": True,
        "sit_visual_bottom": True,
        "grid_yaw_deg": 0.0,
        "paintable": True,
    },
]

os.makedirs(OUT_MESH, exist_ok=True)
os.makedirs(OUT_TEX, exist_ok=True)
os.makedirs(OUT_REND, exist_ok=True)
os.makedirs(OUT_COL, exist_ok=True)
os.makedirs(OUT_TOOLS, exist_ok=True)


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


def unparent_keep(objs):
    if not objs:
        return
    select_meshes(objs)
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")


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
        return None, [0.55, 0.58, 0.50, 1.0]
    img = linked_image(bsdf.inputs.get("Base Color"))
    if img:
        return img, None
    bc = bsdf.inputs.get("Base Color")
    col = [0.55, 0.58, 0.50, 1.0]
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
    col = col or [0.55, 0.58, 0.50, 1.0]
    img = bpy.data.images.new("solid", size, size)
    px = [int(col[0] * 255), int(col[1] * 255), int(col[2] * 255), int(col[3] * 255)]
    img.pixels = px * (size * size)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return True


def obj_matches_part(o, part):
    name = o.name
    low = name.lower()
    for ex in part.get("exclude", []):
        if ex.lower() in low:
            return False
    for root in part["roots"]:
        rl = root.lower()
        if part.get("exact_roots"):
            if low == rl or low.startswith(rl + "_"):
                return True
        elif rl in low:
            return True
    return False


def collect_part_meshes(part):
    return [o for o in mesh_objects() if obj_matches_part(o, part)]


def prepare_materials(objs, part_key):
    mapping = []
    seen = {}
    glass = set(m.lower() for m in PARTS[[p["key"] for p in PARTS].index(part_key)].get("glass_mats", []))
    for o in objs:
        for slot in o.material_slots:
            mat = slot.material
            if not mat:
                continue
            original = mat.name
            base = sanitize(original)
            if base in glass:
                base = base + "_glass"
            n = seen.get(base, 0)
            seen[base] = n + 1
            mname = base if n == 0 else f"{base}_{n + 1}"
            mat.name = mname
            png = os.path.join(OUT_TEX, part_key, mname + "_dif.png")
            os.makedirs(os.path.dirname(png), exist_ok=True)
            img, col = albedo_from_material(mat)
            if img:
                if not save_image_png(img, png):
                    save_solid_png(col, png)
            else:
                save_solid_png(col, png)
            mapping.append({"material": mname, "png": png, "from": original, "glass": "glass" in mname})
    return mapping


def join_meshes(objs, name):
    if not objs:
        return None
    unparent_keep(objs)
    apply_tr(objs)
    select_meshes(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    if body.data:
        body.data.name = name
    apply_tr([body])
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")
    bpy.ops.object.mode_set(mode="OBJECT")
    return body


def align_long_axis_z(body):
    # glTF import -> Blender Z-up. FBX axis_up=Y bakes Blender Z -> SM Y (height).
    apply_tr([body])
    mins, maxs = world_bounds([body])
    size = maxs - mins
    dims = [(size.x, "X"), (size.y, "Y"), (size.z, "Z")]
    dims.sort(key=lambda t: t[0], reverse=True)
    longest = dims[0][1]
    if longest == "X":
        body.rotation_euler = (math.radians(-90.0), 0.0, 0.0)
    elif longest == "Y":
        body.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    apply_tr([body])


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
    if deg:
        # glTF import leaves QUATERNION mode; rotation_euler.z is ignored until XYZ.
        body.rotation_mode = "XYZ"
        body.rotation_euler.z += math.radians(float(deg))
        apply_tr([body])
    else:
        snap_yaw_to_grid(body)


def dense_bottom_z(body, percentile=0.05):
    apply_tr([body])
    zs = []
    for v in body.data.vertices:
        zs.append((body.matrix_world @ v.co).z)
    if not zs:
        return None
    zs.sort()
    idx = min(len(zs) - 1, max(0, int(len(zs) * percentile)))
    return zs[idx]


def trim_below_dense_bottom(body, percentile=0.05, margin=0.02):
    """Drop thin mount/wire verts below the bulk visual base (antenna float fix)."""
    z_cut = dense_bottom_z(body, percentile=percentile)
    if z_cut is None:
        return 0.0
    z_cut -= margin
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bm = __import__("bmesh").from_edit_mesh(body.data)
    for v in bm.verts:
        w = body.matrix_world @ v.co
        v.select = w.z < z_cut
    __import__("bmesh").update_edit_mesh(body.data)
    bpy.ops.mesh.delete(type="VERT")
    bpy.ops.object.mode_set(mode="OBJECT")
    apply_tr([body])
    return z_cut


def sit_visual_bottom(body, box_y, percentile=0.05):
    """Shift mesh so bulk geometry base sits at hull bottom (-box_y/2)."""
    apply_tr([body])
    z_dense = dense_bottom_z(body, percentile=percentile)
    if z_dense is None:
        return
    base_z = -box_y * 0.5
    dz = base_z - z_dense
    if abs(dz) > 0.001:
        body.matrix_world.translation += mathutils.Vector((0.0, 0.0, dz))
        apply_tr([body])


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
    # target = (SM x width, SM y height, SM z depth). Blender: x, y=depth, z=height.
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


def write_rend(part, stem, mat_map, mesh_path):
    sub = {}
    for rec in mat_map:
        mname = rec["material"]
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
                    content_path(rec["png"]),
                    PREFIX + "/Objects/Textures/shared/rfs_asg.tga",
                    SHARED_NOR,
                ],
            }
        else:
            asg = SHARED_ASG_PAINT if part.get("paintable", True) else SHARED_ASG_LOCK
            sub[mname] = {
                "material": "DifAsgNor",
                "textureList": [content_path(rec["png"]), asg, SHARED_NOR],
            }
    data = {
        "_comment": f"R&S Military radio / {part['key']} (DTry CC-BY-4.0). Paintable olive/grey via shape color.",
        "lodList": [
            {
                "mesh": content_path(mesh_path),
                "subMeshMap": sub,
                "maxViewDistance": 1000.0,
            }
        ],
    }
    out = os.path.join(OUT_REND if not part.get("tool_fbx") else OUT_REND, part["rend"])
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


def export_part(part):
    reset_scene()
    print("IMPORT", GLB, "PART", part["key"])
    bpy.ops.import_scene.gltf(filepath=GLB)
    objs = collect_part_meshes(part)
    print("  matched", len(objs), [o.name for o in objs[:8]], "..." if len(objs) > 8 else "")
    if not objs:
        return {"key": part["key"], "error": "no meshes matched"}
    unparent_keep(objs)
    apply_tr(objs)
    mat_map = prepare_materials(objs, part["key"])
    objs = collect_part_meshes(part)
    body = join_meshes(objs, part["stem"])
    if part.get("align_long_axis_z"):
        align_long_axis_z(body)
    meta = scale_and_sit(body, tuple(part["target"]), uniform=part.get("uniform_scale", True))
    if part.get("sit_visual_bottom"):
        sit_visual_bottom(body, meta["box"]["y"])
    else:
        flush_bottom(body, meta["box"]["y"])
    apply_grid_yaw(body, part.get("grid_yaw_deg", 0.0))
    if not part.get("sit_visual_bottom"):
        flush_bottom(body, meta["box"]["y"])
    mins, maxs = world_bounds([body])
    size = maxs - mins
    if part.get("sit_visual_bottom"):
        # Keep declared hull height (1x7x1) — mesh may extend below hull for thin pole wire.
        meta["box"] = {
            "x": part["target"][0],
            "y": part["target"][1],
            "z": part["target"][2],
        }
    else:
        meta["box"] = {
            "x": max(1, min(6, int(round(size.x + 0.45)))),
            "y": max(1, min(10, int(round(size.z + 0.45)))),
            "z": max(1, min(6, int(round(size.y + 0.45)))),
        }
    meta["grid_yaw_deg"] = part.get("grid_yaw_deg", 0.0)
    fbx = os.path.join(OUT_MESH if not part.get("tool_fbx") else OUT_TOOLS, part["stem"] + ".fbx")
    select_meshes([body])
    export_fbx(fbx)
    rend = write_rend(part, part["stem"], mat_map, fbx)
    col_box = part.get("collision_box") or meta["box"]
    col = write_collision(part["stem"], col_box)
    tri_count = len(body.data.polygons) if body.data else 0
    return {
        "key": part["key"],
        "stem": part["stem"],
        "fbx": fbx,
        "rend": rend,
        "col": col,
        "materials": len(mat_map),
        "tris": tri_count,
        "box": col_box,
    }


def main():
    if not os.path.isfile(GLB):
        raise SystemExit("missing GLB: " + GLB)
    only = os.environ.get("RFS_EXPORT_KEYS", "").strip()
    keys = [k.strip() for k in only.split(",") if k.strip()] if only else None
    # Default: antenna only (fbx_kit handles lock/brick/beacon/handheld).
    default_keys = [p["key"] for p in PARTS]
    results = []
    for part in PARTS:
        if keys:
            if part["key"] not in keys:
                continue
        elif part["key"] not in default_keys:
            continue
        results.append(export_part(part))
    meta_path = os.path.join(OUT_ART, "sm_export_radio_meta.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump({"glb": GLB, "parts": results}, f, indent=2)
    print("WROTE", meta_path)
    for r in results:
        print(r)


if __name__ == "__main__":
    main()
