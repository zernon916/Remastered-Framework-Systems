# Blender 4.x: GLB -> SM FBX+DAE with named materials and albedo PNGs.
# Does NOT join into a dummy white "body". Does NOT align_longest_to_y
# (that laid the incubator on its side). SM part Y = up = Blender Z after
# axis_up=Y bake. Stand/base stays at -Y.
# Run: blender --background --python Art/export_rfs_sm_mesh.py
import bpy
import os
import json
import mathutils

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh")
OUT_TEX = os.path.join(ROOT, "Objects", "Textures")
OUT_REND = os.path.join(ROOT, "Objects", "Renderable")
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
os.makedirs(OUT_MESH, exist_ok=True)
os.makedirs(OUT_REND, exist_ok=True)

# Sketchfab HUD atlases. Do not replace with viewport screenshots.
HUD_JPEG = {
    "top_display": os.path.join(ROOT, "Art", "sketchfab_incubator", "textures", "26900_1.jpeg"),
    "top_display_screen": os.path.join(ROOT, "Art", "sketchfab_incubator", "textures", "26900_1.jpeg"),
    "bottom_display": os.path.join(ROOT, "Art", "sketchfab_incubator", "textures", "thanit2022april_19_0.jpeg"),
}

JOBS = [
    {
        "name": "deepsleep",
        "glb": os.path.join(ROOT, "Art", "sketchfab_incubator", "source", "Incubator.glb"),
        "target": (7.0, 9.0, 7.0),
        "stem": "rfs_deepsleep_v7",
        "bed_name": "Bed",
        "glass_materials": ["shell"],
        "keep_textures": False,
        "rename_materials": {"Light.001": "bed"},
    },
    {
        "name": "solar",
        "glb": os.path.join(ROOT, "Art", "sketchfab_solar", "source", "HexaRay Node - For texturing.glb"),
        "target": (5.0, 5.0, 5.0),
        "stem": "rfs_solar_v5",
        "bed_name": None,
        "glass_materials": [],
        "keep_textures": True,
        "rename_materials": {},
    },
]


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def world_bounds(objs):
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


def select_meshes(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def apply_tr(objs):
    select_meshes(objs)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def sanitize(name):
    out = []
    for ch in (name or "mesh"):
        if ch.isalnum():
            out.append(ch.lower())
        else:
            out.append("_")
    s = "".join(out).strip("_")
    while "__" in s:
        s = s.replace("__", "_")
    return s[:40] or "mesh"


def scale_and_center(objs, target):
    # Blender 4.4 glTF import already converts glTF Y-up -> Blender Z-up.
    # Native incubator Stand and solar "Back Bottom base support" sit at -Z.
    # FBX axis_up=Y bakes Blender Z -> SM Y, so -Z becomes sticky -Y (ground).
    # Do NOT extra-rotate +90 X: that mapped panel/capsule width onto SM Y
    # and stood both parts on their side.
    apply_tr(objs)
    mins, maxs = world_bounds(objs)
    if mins is None:
        return None
    size = maxs - mins
    tx, ty, tz = target
    s = min(tx / max(size.x, 1e-6), ty / max(size.z, 1e-6), tz / max(size.y, 1e-6))
    center = (mins + maxs) * 0.5
    for o in objs:
        o.scale = (s, s, s)
        o.location = o.location - center * s
    apply_tr(objs)
    mins2, maxs2 = world_bounds(objs)
    size2 = maxs2 - mins2
    return {
        "scale": s,
        "size_blender": [float(size2.x), float(size2.y), float(size2.z)],
        "size_sm": [float(size2.x), float(size2.z), float(size2.y)],
        "min": [float(mins2.x), float(mins2.y), float(mins2.z)],
        "max": [float(maxs2.x), float(maxs2.y), float(maxs2.z)],
    }


def blender_to_sm(v):
    # bake_space_transform + axis_up=Y + axis_forward=-Z: (x, y, z) -> (x, z, -y)
    return [float(v.x), float(v.z), float(-v.y)]


def object_center(o):
    mins, maxs = world_bounds([o])
    if mins is None:
        return mathutils.Vector((0, 0, 0)), mathutils.Vector((0, 0, 0))
    return (mins + maxs) * 0.5, (maxs - mins)


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
        return None, [0.8, 0.8, 0.8, 1.0]
    img = linked_image(bsdf.inputs.get("Base Color"))
    if img:
        return img, None
    img = linked_image(bsdf.inputs.get("Emission Color"))
    if img:
        return img, None
    bc = bsdf.inputs.get("Base Color")
    col = [0.8, 0.8, 0.8, 1.0]
    if bc:
        col = [float(bc.default_value[0]), float(bc.default_value[1]), float(bc.default_value[2]), float(bc.default_value[3])]
    return None, col


def save_image_png(img, path, max_px=512):
    copy = img.copy()
    w, h = int(copy.size[0]), int(copy.size[1])
    if w < 1 or h < 1:
        return False
    m = max(w, h)
    if m > max_px:
        s = max_px / float(m)
        nw = max(1, int(w * s))
        nh = max(1, int(h * s))
        copy.scale(nw, nh)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    copy.filepath_raw = path
    copy.file_format = "PNG"
    copy.save()
    return True


def linear_to_srgb(c):
    c = max(0.0, min(1.0, float(c)))
    if c <= 0.0031308:
        return 12.92 * c
    return 1.055 * (c ** (1.0 / 2.4)) - 0.055


def save_solid_png(color, path, px=16):
    img = bpy.data.images.new(os.path.basename(path), width=px, height=px)
    r = linear_to_srgb(color[0])
    g = linear_to_srgb(color[1])
    b = linear_to_srgb(color[2])
    a = color[3] if len(color) > 3 else 1.0
    img.pixels = [r, g, b, a] * (px * px)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def ensure_uv(obj):
    if not obj.data:
        return
    if obj.data.uv_layers:
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    try:
        bpy.ops.uv.smart_project(angle_limit=66.0, island_margin=0.02)
    except Exception:
        bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.001)
    bpy.ops.object.mode_set(mode="OBJECT")


def prepare_materials(objs, job_name, keep_textures=False, rename_materials=None, glass_materials=None):
    tex_dir = os.path.join(OUT_TEX, job_name)
    os.makedirs(tex_dir, exist_ok=True)
    rename_materials = rename_materials or {}
    glass_materials = set(glass_materials or [])
    seen = set()
    name_count = {}
    mapping = []
    for o in objs:
        if not o.data:
            continue
        for mat in list(o.data.materials):
            if not mat:
                continue
            mid = mat.as_pointer()
            if mid in seen:
                continue
            seen.add(mid)
            original = mat.name
            renamed = rename_materials.get(original, original)
            base = sanitize(renamed)
            n = name_count.get(base, 0)
            name_count[base] = n + 1
            mname = base if n == 0 else ("%s_%d" % (base, n + 1))
            mat.name = mname
            png = os.path.join(tex_dir, mname + "_dif.png")
            hud = HUD_JPEG.get(mname) or HUD_JPEG.get(original.lower() if original else "")
            if hud and os.path.isfile(hud):
                # Never stamp Cursor screenshots. GLB UVs were authored for these jpegs.
                ok = False
                img = bpy.data.images.load(hud)
                ok = save_image_png(img, png, max_px=1024)
                if ok:
                    mapping.append({"material": mname, "png": png, "from": original, "hud": hud})
                    continue
            if keep_textures and os.path.isfile(png):
                mapping.append({"material": mname, "png": png, "from": original, "kept": True})
                continue
            img, col = albedo_from_material(mat)
            if mname in glass_materials:
                # Mostly-clear cover: Glass shader uses this as tint.
                save_solid_png([0.75, 0.88, 0.92, 0.18], png)
            elif img:
                ok = save_image_png(img, png)
                if not ok:
                    save_solid_png(col or [0.8, 0.8, 0.8, 1.0], png)
            else:
                save_solid_png(col or [0.8, 0.8, 0.8, 1.0], png)
            mapping.append({"material": mname, "png": png, "from": original})
    return mapping


def join_keep_materials(objs, name):
    select_meshes(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    if body.data:
        body.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")
    bpy.ops.object.mode_set(mode="OBJECT")
    return body


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


def export_dae(path):
    bpy.ops.wm.collada_export(
        filepath=path,
        apply_modifiers=True,
        selected=True,
        include_children=False,
        include_armatures=False,
        include_shapekeys=False,
        triangulate=True,
        use_object_instantiation=False,
        use_blender_profile=False,
        limit_precision=True,
        keep_bind_info=False,
    )


def content_path(abs_path):
    rel = os.path.relpath(abs_path, ROOT).replace("\\", "/")
    return PREFIX + "/" + rel


GLASS_CUSTOM = {
    "glass": {
        "ROI": 1.52,
        "blurriness": 0.0,
        "depthBlurDistance": 1,
        "depthBlurMin": 0,
        "magnification": 1.0,
        "magnificationDirection": [1.0, 1.0],
        "refraction": 0.1,
        "responsiveGlow": 1.0,
        "transmission": 0.85,
        "transparencyBack": 0.15,
        "transparencyFront": 0.72,
    }
}


def write_rend(job_name, stem, mat_map, glass_materials=None):
    asg = PREFIX + "/Objects/Textures/shared/rfs_asg.tga"
    nor = PREFIX + "/Objects/Textures/shared/rfs_nor.tga"
    glass_materials = set(glass_materials or [])
    sub = {}
    for rec in mat_map:
        mname = rec["material"]
        entry = {
            "textureList": [content_path(rec["png"]), asg, nor],
        }
        if mname in glass_materials:
            # Cover/glass only. Use vanilla industrial window Glass textures
            # (proven in Survival fittings) plus Glass shader.
            gd = "$GAME_DATA/Objects/Textures/industrial/obj_industrial_windowglass"
            entry["material"] = "Glass"
            entry["custom"] = GLASS_CUSTOM
            entry["textureList"] = [gd + "_dif.tga", gd + "_asg.tga", gd + "_nor.tga"]
            entry["textures"] = {
                "diffuse": gd + "_dif.tga",
                "asg": gd + "_asg.tga",
                "normalMap": gd + "_nor.tga",
            }
        else:
            entry["material"] = "DifAsgNor"
        sub[mname] = entry
    data = {
        "_comment": "Named materials. _v7: Sketchfab HUD jpegs + Glass shell. Mesh _v7 cache bust.",
        "lodList": [
            {
                "mesh": PREFIX + "/Objects/Mesh/" + stem + ".fbx",
                "subMeshMap": sub,
                "maxViewDistance": 1000.0,
            }
        ],
    }
    out = os.path.join(OUT_REND, "rfs_" + job_name + ".rend")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent="\t")
        f.write("\n")
    return out


def run_job(job):
    reset_scene()
    glb = job["glb"]
    print("IMPORT", glb, "exists", os.path.isfile(glb))
    if not os.path.isfile(glb):
        return None
    bpy.ops.import_scene.gltf(filepath=glb)
    objs = mesh_objects()
    print("meshes", len(objs), [o.name for o in objs])
    meta = scale_and_center(objs, job["target"])
    objs = mesh_objects()

    lie = None
    bed_name = job.get("bed_name")
    if bed_name:
        bed = None
        for o in objs:
            if o.name == bed_name or o.name.lower() == bed_name.lower():
                bed = o
                break
        if bed:
            c, size = object_center(bed)
            sm_c = blender_to_sm(c)
            sm_size = blender_to_sm(size)
            lift = 0.22
            back = 0.12
            lie = {
                "bed_object": bed.name,
                "center_sm": sm_c,
                "size_sm": [abs(sm_size[0]), abs(sm_size[1]), abs(sm_size[2])],
                "front_sm": [0.0, 0.0, 1.0],
                "root_jnt": {
                    "x": round(sm_c[0], 3),
                    "y": round(sm_c[1] + lift, 3),
                    "z": round(sm_c[2] - back, 3),
                    "rotation_deg_x": -18.0,
                    "rotation": {
                        "w": 0.9876883405951378,
                        "x": -0.15643446504023087,
                        "y": 0.0,
                        "z": 0.0,
                    },
                },
                "exit": {
                    "forward_m": 1.55,
                    "lift_m": 0.45,
                    "local_axis": "+Z",
                },
            }
            print("LIE", json.dumps(lie))

    for o in objs:
        ensure_uv(o)
    mat_map = prepare_materials(
        objs,
        job["name"],
        keep_textures=job.get("keep_textures", False),
        rename_materials=job.get("rename_materials") or {},
        glass_materials=job.get("glass_materials") or [],
    )
    objs = mesh_objects()
    body = join_keep_materials(objs, job["stem"])
    mats = [m.name for m in body.data.materials if m]
    fbx = os.path.join(OUT_MESH, job["stem"] + ".fbx")
    dae = os.path.join(OUT_MESH, job["stem"] + ".dae")
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    export_fbx(fbx)
    export_dae(dae)
    rend = write_rend(job["name"], job["stem"], mat_map, job.get("glass_materials") or [])
    result = {
        "name": job["name"],
        "fbx": fbx,
        "dae": dae,
        "rend": rend,
        "object": body.name,
        "materials": mats,
        "mat_map": mat_map,
        "meta": meta,
        "lie": lie,
        "verts": len(body.data.vertices),
        "polys": len(body.data.polygons),
    }
    print("DONE", json.dumps({k: result[k] for k in result if k != "mat_map"}, indent=2))
    return result


def main():
    all_meta = []
    for job in JOBS:
        all_meta.append(run_job(job))
    out = os.path.join(ROOT, "Art", "sm_export_v7_meta.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(all_meta, f, indent=2)
    print("WROTE", out)


if __name__ == "__main__":
    main()
