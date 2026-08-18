# Blender 4.4: Colba GLB -> SM FBX _v8 + chemfill + collision.
# Height fits 6-block hull (1.5 m). Uniform scale. Sticky -Y = Blender -Z.
# Run: blender --background --python Art/export_rfs_colba_v8.py
import bpy
import os
import json
import math
import mathutils

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
GLB = os.path.join(ROOT, "Art", "sketchfab_colba", "source", "the_science_fiction_colba.glb")
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh")
OUT_TEX = os.path.join(ROOT, "Objects", "Textures", "deepsleep")
OUT_COL = os.path.join(ROOT, "Objects", "Collision")
OUT_REND = os.path.join(ROOT, "Objects", "Renderable")
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
STEM = "rfs_deepsleep_v8"
FILL_STEM = "rfs_chemfill_v8"
# 4x6x4 blocks * 0.25 m. Fit HEIGHT to 1.5 m so the tube is usable.
HULL_BLOCKS = (4, 6, 4)
TARGET_HEIGHT_M = HULL_BLOCKS[1] * 0.25

for d in (OUT_MESH, OUT_TEX, OUT_COL, OUT_REND):
    os.makedirs(d, exist_ok=True)


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
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def apply_tr(objs):
    if not objs:
        return
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


MAT_RENAME = {
    "colb_down": "down",
    "colb_up": "up",
    "colb_colba": "glass",
    "colb_decals": "decals",
}


def clear_parents_keep():
    objs = mesh_objects()
    select_meshes(objs)
    try:
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    except Exception:
        pass


def linear_to_srgb(c):
    c = max(0.0, min(1.0, float(c)))
    if c <= 0.0031308:
        return 12.92 * c
    return 1.055 * (c ** (1.0 / 2.4)) - 0.055


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
    bc = bsdf.inputs.get("Base Color")
    col = [0.8, 0.8, 0.8, 1.0]
    if bc:
        col = [float(bc.default_value[i]) for i in range(4)]
    return None, col


def rename_materials(objs):
    for o in objs:
        if not o.data:
            continue
        for mat in o.data.materials:
            if not mat:
                continue
            new = MAT_RENAME.get(mat.name, sanitize(mat.name))
            mat.name = new


def join_by_material(objs):
    buckets = {}
    for o in objs:
        mname = "down"
        if o.data and o.data.materials and o.data.materials[0]:
            mname = o.data.materials[0].name
        buckets.setdefault(mname, []).append(o)
    joined = []
    for mname, group in buckets.items():
        select_meshes(group)
        if len(group) > 1:
            bpy.ops.object.join()
        body = bpy.context.view_layer.objects.active
        body.name = mname
        if body.data:
            body.data.name = mname
        joined.append(body)
    return joined


def join_all(objs, name):
    select_meshes(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    if body.data:
        body.data.name = name
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
        "refraction": 0.12,
        "responsiveGlow": 1.0,
        "transmission": 0.82,
        "transparencyBack": 0.18,
        "transparencyFront": 0.68,
    }
}

PURPLE_GLASS = {
    "glass": {
        "ROI": 1.33,
        "blurriness": 0.15,
        "depthBlurDistance": 1,
        "depthBlurMin": 0,
        "magnification": 1.0,
        "magnificationDirection": [1.0, 1.0],
        "refraction": 0.08,
        "responsiveGlow": 0.4,
        "transmission": 0.55,
        "transparencyBack": 0.35,
        "transparencyFront": 0.45,
    }
}


def write_rend_body(mat_files):
    asg = PREFIX + "/Objects/Textures/shared/rfs_asg.tga"
    nor = PREFIX + "/Objects/Textures/shared/rfs_nor.tga"
    gd = "$GAME_DATA/Objects/Textures/industrial/obj_industrial_windowglass"
    sub = {}
    for mname, png in mat_files.items():
        if mname == "glass":
            sub[mname] = {
                "material": "Glass",
                "custom": GLASS_CUSTOM,
                "textureList": [gd + "_dif.tga", gd + "_asg.tga", gd + "_nor.tga"],
                "textures": {
                    "diffuse": gd + "_dif.tga",
                    "asg": gd + "_asg.tga",
                    "normalMap": gd + "_nor.tga",
                },
            }
        elif mname == "decals":
            sub[mname] = {
                "material": "Glass",
                "custom": GLASS_CUSTOM,
                "textureList": [content_path(png), asg, nor],
            }
        else:
            sub[mname] = {
                "material": "DifAsgNor",
                "textureList": [content_path(png), asg, nor],
            }
    data = {
        "_comment": "Colba Chemical Regeneration Station. Mesh _v8. Named down/up/glass/decals.",
        "lodList": [
            {
                "mesh": PREFIX + "/Objects/Mesh/" + STEM + ".fbx",
                "subMeshMap": sub,
                "maxViewDistance": 1000.0,
            }
        ],
    }
    out = os.path.join(OUT_REND, "rfs_deepsleep.rend")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent="\t")
        f.write("\n")
    return out


def write_rend_fill(png):
    asg = PREFIX + "/Objects/Textures/shared/rfs_asg.tga"
    nor = PREFIX + "/Objects/Textures/shared/rfs_nor.tga"
    data = {
        "_comment": "Purple chem tank fill. Hidden part, ShapeRenderable only. Not parented to station.",
        "lodList": [
            {
                "mesh": PREFIX + "/Objects/Mesh/" + FILL_STEM + ".fbx",
                "subMeshMap": {
                    "chemfill": {
                        "material": "Glass",
                        "custom": PURPLE_GLASS,
                        "textureList": [content_path(png), asg, nor],
                    }
                },
                "maxViewDistance": 1000.0,
            }
        ],
    }
    out = os.path.join(OUT_REND, "rfs_chemfill.rend")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent="\t")
        f.write("\n")
    return out


def write_collision_obj(path, bx, by, bz):
    # SM hull col units = blocks. Origin at part center. Y up.
    hx, hy, hz = bx * 0.5, by * 0.5, bz * 0.5
    floor_top = -hy + 0.35
    # Hollow tube: floor slab + 4 thin walls. Interior open so the lock can stand.
    wall = 0.28
    verts = []
    faces = []

    def box(x0, x1, y0, y1, z0, z1):
        i = len(verts) + 1
        verts.extend(
            [
                (x0, y0, z0),
                (x1, y0, z0),
                (x1, y1, z0),
                (x0, y1, z0),
                (x0, y0, z1),
                (x1, y0, z1),
                (x1, y1, z1),
                (x0, y1, z1),
            ]
        )
        faces.extend(
            [
                (i, i + 1, i + 2, i + 3),
                (i + 4, i + 7, i + 6, i + 5),
                (i, i + 4, i + 5, i + 1),
                (i + 3, i + 2, i + 6, i + 7),
                (i, i + 3, i + 7, i + 4),
                (i + 1, i + 5, i + 6, i + 2),
            ]
        )

    box(-hx + 0.05, hx - 0.05, -hy, floor_top, -hz + 0.05, hz - 0.05)
    box(-hx, -hx + wall, floor_top, hy, -hz, hz)
    box(hx - wall, hx, floor_top, hy, -hz, hz)
    box(-hx + wall, hx - wall, floor_top, hy, -hz, -hz + wall)
    box(-hx + wall, hx - wall, floor_top, hy, hz - wall, hz)
    lines = [
        "# rfs_deepsleep_col — Chemical Regeneration Station. Units: blocks. Hull %dx%dx%d."
        % (bx, by, bz),
        "# Floor + walls so they do not fall through. Sticky -Y. Re-place the part.",
        "g col",
    ]
    for v in verts:
        lines.append("v %.6f %.6f %.6f" % v)
    for f in faces:
        lines.append("f %d %d %d %d" % f)
    lines.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def blender_to_sm(v):
    return [float(v.x), float(v.z), float(-v.y)]


def main():
    reset_scene()
    print("IMPORT", GLB, "exists", os.path.isfile(GLB))
    if not os.path.isfile(GLB):
        raise SystemExit("missing glb")
    bpy.ops.import_scene.gltf(filepath=GLB)
    clear_parents_keep()
    objs = mesh_objects()
    apply_tr(objs)
    objs = mesh_objects()
    mins, maxs = world_bounds(objs)
    size = maxs - mins
    s = TARGET_HEIGHT_M / max(size.z, 1e-6)
    center = (mins + maxs) * 0.5
    for o in objs:
        o.scale = (s, s, s)
        o.location = o.location - center * s
    apply_tr(objs)
    objs = mesh_objects()
    rename_materials(objs)
    parts = join_by_material(objs)
    apply_tr(parts)

    glass = None
    for o in parts:
        if o.name == "glass":
            glass = o
            break
    gmins, gmaxs = world_bounds([glass] if glass else parts)
    gsize = gmaxs - gmins
    gcenter = (gmins + gmaxs) * 0.5
    fill_r = min(gsize.x, gsize.y) * 0.38
    fill_h = max(gsize.z * 0.78, 0.35)
    fill_z0 = gmins.z + (gsize.z - fill_h) * 0.12

    mat_files = {}
    for o in parts:
        mname = o.name
        png = os.path.join(OUT_TEX, mname + "_dif.png")
        img, col = albedo_from_material(o.data.materials[0] if o.data.materials else None)
        if mname == "glass":
            save_solid_png([0.75, 0.88, 0.92, 0.18], png)
        elif img:
            if not save_image_png(img, png, max_px=512):
                save_solid_png(col or [0.7, 0.7, 0.7, 1.0], png)
        else:
            save_solid_png(col or [0.7, 0.7, 0.7, 1.0], png)
        mat_files[mname] = png

    body = join_all(list(parts), STEM)
    fbx = os.path.join(OUT_MESH, STEM + ".fbx")
    dae = os.path.join(OUT_MESH, STEM + ".dae")
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    export_fbx(fbx)
    export_dae(dae)
    rend = write_rend_body(mat_files)

    # Fill cylinder as its own object/file. Origin at geometric center.
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=20,
        radius=fill_r,
        depth=fill_h,
        location=(gcenter.x, gcenter.y, fill_z0 + fill_h * 0.5),
    )
    fill = bpy.context.view_layer.objects.active
    fill.name = FILL_STEM
    if fill.data:
        fill.data.name = FILL_STEM
    mat = bpy.data.materials.new("chemfill")
    mat.use_nodes = True
    fill.data.materials.append(mat)
    apply_tr([fill])
    purple = os.path.join(OUT_TEX, "chemfill_dif.png")
    save_solid_png([0.42, 0.12, 0.72, 0.62], purple, px=32)
    bpy.ops.object.select_all(action="DESELECT")
    fill.select_set(True)
    bpy.context.view_layer.objects.active = fill
    fill_fbx = os.path.join(OUT_MESH, FILL_STEM + ".fbx")
    fill_dae = os.path.join(OUT_MESH, FILL_STEM + ".dae")
    export_fbx(fill_fbx)
    export_dae(fill_dae)
    fill_rend = write_rend_fill(purple)

    # Hide fill from the body scene file (already exported).
    fill.hide_render = True
    fill.hide_viewport = True

    write_collision_obj(
        os.path.join(OUT_COL, "rfs_deepsleep_col.obj"),
        HULL_BLOCKS[0],
        HULL_BLOCKS[1],
        HULL_BLOCKS[2],
    )

    bmins, bmaxs = world_bounds([body])
    bsize = bmaxs - bmins
    floor_y_sm = -TARGET_HEIGHT_M * 0.5
    stand_y = floor_y_sm + 0.85
    meta = {
        "stem": STEM,
        "hull_blocks": list(HULL_BLOCKS),
        "target_height_m": TARGET_HEIGHT_M,
        "scale": s,
        "size_blender": [float(bsize.x), float(bsize.y), float(bsize.z)],
        "size_sm": blender_to_sm(bsize),
        "fill_radius_m": float(fill_r),
        "fill_height_m": float(fill_h),
        "fill_bottom_z_blender": float(fill_z0),
        "stand_local_sm": [0.0, round(stand_y, 3), 0.0],
        "exit_forward_m": 1.15,
        "exit_lift_m": 0.4,
        "materials": list(mat_files.keys()),
        "fbx": fbx,
        "fill_fbx": fill_fbx,
        "rend": rend,
        "fill_rend": fill_rend,
        "verts": len(body.data.vertices),
        "polys": len(body.data.polygons),
    }
    out = os.path.join(ROOT, "Art", "sm_export_v8_meta.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
    print("DONE", json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
