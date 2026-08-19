# Blender 4.4: Sketchfab Yberpunk robot head -> SM Aim Core (1-2 block cube).
# SOP: named materials, FBX+DAE, sit on sticky -Y, verts in SM BLOCKS.
# Run: blender --background --python Art/export_rfs_aimcore.py
import bpy
import os
import json
import mathutils

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
GLB = os.path.join(ROOT, "Art", "sketchfab_aimcore", "source", "yberpunk_robot_head_sketch.glb")
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh")
OUT_TEX = os.path.join(ROOT, "Objects", "Textures", "aimcore")
OUT_REND = os.path.join(ROOT, "Objects", "Renderable")
OUT_COL = os.path.join(ROOT, "Objects", "Collision")
OUT_ART = os.path.join(ROOT, "Art")
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
STEM = "rfs_aimcore_v1"
# Fit a turret head in at most 2x2x2 SM blocks (uniform scale).
TARGET = (2.0, 2.0, 2.0)
DECIMATE_TRIS = 5000
os.makedirs(OUT_MESH, exist_ok=True)
os.makedirs(OUT_TEX, exist_ok=True)
os.makedirs(OUT_REND, exist_ok=True)
os.makedirs(OUT_COL, exist_ok=True)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def world_bounds(objs):
    mins = mathutils.Vector((1e9, 1e9, 1e9))
    maxs = mathutils.Vector((-1e9, -1e9, -1e9))
    any_ok = False
    for o in objs:
        if o.type != "MESH" or not o.data:
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
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
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def apply_tr(objs):
    if not objs:
        return
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
        if ch.isalnum():
            out.append(ch.lower())
        else:
            out.append("_")
    s = "".join(out).strip("_")
    while "__" in s:
        s = s.replace("__", "_")
    return s[:40] or "mesh"


def count_tris(obj):
    n = 0
    for p in obj.data.polygons:
        n += max(len(p.vertices) - 2, 0)
    return n


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
        return None, [0.55, 0.58, 0.62, 1.0], None
    img = linked_image(bsdf.inputs.get("Base Color"))
    nor = None
    ninp = bsdf.inputs.get("Normal")
    if ninp and ninp.is_linked:
        nnode = ninp.links[0].from_node
        if nnode.type == "NORMAL_MAP":
            color = nnode.inputs.get("Color")
            nor = linked_image(color) if color else None
        elif nnode.type == "TEX_IMAGE":
            nor = nnode.image
    if img:
        return img, None, nor
    bc = bsdf.inputs.get("Base Color")
    col = [0.55, 0.58, 0.62, 1.0]
    if bc:
        col = [float(bc.default_value[i]) for i in range(4)]
    return None, col, nor


def save_image_png(img, path, max_px=1024):
    copy = img.copy()
    w, h = int(copy.size[0]), int(copy.size[1])
    if w < 1 or h < 1:
        return False
    m = max(w, h)
    if m > max_px:
        s = max_px / float(m)
        copy.scale(max(1, int(w * s)), max(1, int(h * s)))
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


def prepare_materials(objs):
    mapping = []
    seen = set()
    name_count = {}
    nor_path = None
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
            base = sanitize(original)
            n = name_count.get(base, 0)
            name_count[base] = n + 1
            mname = base if n == 0 else ("%s_%d" % (base, n + 1))
            mat.name = mname
            png = os.path.join(OUT_TEX, mname + "_dif.png")
            img, col, nor = albedo_from_material(mat)
            if img:
                if not save_image_png(img, png, max_px=1024):
                    save_solid_png(col or [0.55, 0.58, 0.62, 1.0], png)
            else:
                save_solid_png(col or [0.55, 0.58, 0.62, 1.0], png)
            rec = {"material": mname, "png": png, "from": original}
            if nor and nor_path is None:
                npath = os.path.join(OUT_TEX, "aimcore_nor.png")
                if save_image_png(nor, npath, max_px=1024):
                    nor_path = npath
                    rec["nor"] = npath
            mapping.append(rec)
    return mapping, nor_path


def join_keep_materials(objs, name):
    select_meshes(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    if body.data:
        body.data.name = name
    unparent_keep([body])
    apply_tr([body])
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")
    bpy.ops.object.mode_set(mode="OBJECT")
    return body


def decimate(body, target_tris):
    before = count_tris(body)
    if before <= 8000:
        return before, before, 1.0
    ratio = max(0.05, min(1.0, float(target_tris) / float(before)))
    mod = body.modifiers.new(name="rfs_decimate", type="DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=mod.name)
    after = count_tris(body)
    return before, after, ratio


def scale_fit_and_sit(body, target):
    # Blender Z-up -> SM Y via FBX axis_up=Y. Native base at -Z becomes sticky -Y.
    unparent_keep([body])
    apply_tr([body])
    mins, maxs = world_bounds([body])
    size = maxs - mins
    tx, ty, tz = target
    s = min(tx / max(size.x, 1e-6), ty / max(size.z, 1e-6), tz / max(size.y, 1e-6))
    body.scale = (s, s, s)
    apply_tr([body])
    mins, maxs = world_bounds([body])
    size = maxs - mins
    box_x = 2 if size.x > 1.02 else 1
    box_y = 2 if size.z > 1.02 else 1
    box_z = 2 if size.y > 1.02 else 1
    # World-space park: SM X/Z centered, blender min Z = sticky -Y = -boxY/2.
    cx = 0.5 * (mins.x + maxs.x)
    cy = 0.5 * (mins.y + maxs.y)
    dz = (-box_y * 0.5) - mins.z
    body.matrix_world.translation += mathutils.Vector((-cx, -cy, dz))
    apply_tr([body])
    mins2, maxs2 = world_bounds([body])
    size2 = maxs2 - mins2
    return {
        "scale": s,
        "box": {"x": box_x, "y": box_y, "z": box_z},
        "size_blender": [float(size2.x), float(size2.y), float(size2.z)],
        "size_sm": [float(size2.x), float(size2.z), float(size2.y)],
        "min_blender": [float(mins2.x), float(mins2.y), float(mins2.z)],
        "max_blender": [float(maxs2.x), float(maxs2.y), float(maxs2.z)],
        "min_sm": [float(mins2.x), float(mins2.z), float(-maxs2.y)],
        "max_sm": [float(maxs2.x), float(maxs2.z), float(-mins2.y)],
    }


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
        bake_anim=False,
    )
    try:
        bpy.ops.export_scene.fbx(use_triangles=True, **kw)
    except TypeError:
        kw.pop("bake_anim", None)
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


def write_collision_box(path, box):
    hx, hy, hz = box["x"] * 0.5, box["y"] * 0.5, box["z"] * 0.5
    verts = [
        (-hx, -hy, -hz),
        (hx, -hy, -hz),
        (hx, hy, -hz),
        (-hx, hy, -hz),
        (-hx, -hy, hz),
        (hx, -hy, hz),
        (hx, hy, hz),
        (-hx, hy, hz),
    ]
    faces = [
        (1, 2, 3, 4),
        (5, 8, 7, 6),
        (1, 5, 6, 2),
        (4, 3, 7, 8),
        (1, 4, 8, 5),
        (2, 6, 7, 3),
    ]
    lines = [
        "# rfs_aimcore_col — Aim Core. Units: blocks. Origin center. Y up.",
        "# Simple box matching the %dx%dx%d hull. Sticky -Y."
        % (box["x"], box["y"], box["z"]),
        "g col",
    ]
    for v in verts:
        lines.append("v %.6f %.6f %.6f" % v)
    for f in faces:
        lines.append("f %d %d %d %d" % f)
    lines.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def content_path(abs_path):
    rel = os.path.relpath(abs_path, ROOT).replace("\\", "/")
    return PREFIX + "/" + rel


def write_rend(stem, mat_map, nor_path):
    asg = PREFIX + "/Objects/Textures/aimcore/aimcore_asg.tga"
    nor = PREFIX + "/Objects/Textures/shared/rfs_nor.tga"
    sub = {}
    for rec in mat_map:
        mname = rec["material"]
        sub[mname] = {
            "material": "DifAsgNor",
            "textureList": [content_path(rec["png"]), asg, nor],
        }
    data = {
        "_comment": "Aim Core _v1. Sketchfab Yberpunk robot head (3DWorkbench, CC BY 4.0). Matte ASG. Base at -Y.",
        "lodList": [
            {
                "mesh": PREFIX + "/Objects/Mesh/" + stem + ".fbx",
                "subMeshMap": sub,
                "maxViewDistance": 1000.0,
            }
        ],
    }
    out = os.path.join(OUT_REND, "rfs_aimcore.rend")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent="\t")
        f.write("\n")
    return out, asg, nor


def render_icon(body, out_png):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 96
    scene.render.resolution_y = 96
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    if scene.world:
        scene.world.color = (0.078, 0.094, 0.110)
    cam_data = bpy.data.cameras.new("rfs_aimcore_icon")
    cam = bpy.data.objects.new("rfs_aimcore_icon", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam_data.type = "ORTHO"
    mins, maxs = world_bounds([body])
    c = (mins + maxs) * 0.5
    size = maxs - mins
    cam_data.ortho_scale = max(size.x, size.y, size.z, 0.5) * 1.55
    offset = mathutils.Vector((1.8, -2.0, 1.3))
    cam.location = c + offset
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    return out_png


def main():
    if not os.path.isfile(GLB):
        raise SystemExit("missing " + GLB)
    reset_scene()
    print("IMPORT", GLB)
    bpy.ops.import_scene.gltf(filepath=GLB)
    objs = mesh_objects()
    print("meshes", len(objs), [o.name for o in objs])
    if not objs:
        raise SystemExit("no mesh")
    unparent_keep(objs)
    apply_tr(objs)
    mat_map, nor_path = prepare_materials(objs)
    objs = mesh_objects()
    body = join_keep_materials(objs, STEM)
    before, after, ratio = decimate(body, DECIMATE_TRIS)
    print("tris", before, "->", after, "ratio", ratio)
    meta = scale_fit_and_sit(body, TARGET)
    mats = [m.name for m in body.data.materials if m]
    fbx = os.path.join(OUT_MESH, STEM + ".fbx")
    dae = os.path.join(OUT_MESH, STEM + ".dae")
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    export_fbx(fbx)
    export_dae(dae)
    col = os.path.join(OUT_COL, "rfs_aimcore_col.obj")
    write_collision_box(col, meta["box"])
    rend, asg, nor = write_rend(STEM, mat_map, nor_path)
    icon = os.path.join(OUT_ART, "icon_aimcore_96.png")
    try:
        render_icon(body, icon)
    except Exception as e:
        print("icon render failed", e)
        icon = None
    result = {
        "stem": STEM,
        "fbx": fbx,
        "dae": dae,
        "col": col,
        "rend": rend,
        "asg": asg,
        "nor": nor,
        "icon": icon,
        "object": body.name,
        "materials": mats,
        "mat_map": mat_map,
        "meta": meta,
        "tris_before": before,
        "tris_after": after,
        "decimate_ratio": ratio,
        "verts": len(body.data.vertices),
        "polys": len(body.data.polygons),
    }
    out = os.path.join(OUT_ART, "sm_export_aimcore_meta.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    print("WROTE", out)
    print("DONE", json.dumps({k: result[k] for k in result if k != "mat_map"}, indent=2))


if __name__ == "__main__":
    main()
