# Blender 4.4: Colba GLB -> SM FBX _v9.
# Glass tube ~2.75 m (11 blocks). Circular BASE sits on hull -Y (not AABB of hanging arms).
# SM hull origin is the box CENTER; sticky -Y is -halfY. Bake base min to that face.
# Run: blender --background --python Art/export_rfs_colba_v9.py
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
STEM = "rfs_deepsleep_v9"
FILL_STEM = "rfs_chemfill_v9"
TARGET_GLASS_H_M = 2.75
BLOCK = 0.25

for d in (OUT_MESH, OUT_TEX, OUT_COL, OUT_REND):
    os.makedirs(d, exist_ok=True)

MAT_RENAME = {
    "colb_down": "down",
    "colb_up": "up",
    "colb_colba": "glass",
    "colb_decals": "decals",
}


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


def blocks_for(meters):
    return max(1, int(math.ceil(float(meters) / BLOCK - 1e-4)))


def clear_parents_keep():
    objs = mesh_objects()
    select_meshes(objs)
    try:
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    except Exception:
        pass


def rename_materials(objs):
    for o in objs:
        if not o.data:
            continue
        for mat in o.data.materials:
            if not mat:
                continue
            new = MAT_RENAME.get(mat.name, mat.name)
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
        "_comment": "Colba Chemical Regeneration Station. Mesh _v9. Base on hull -Y. Glass ~2.75m.",
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
        "_comment": "Purple chem tank fill _v9. Unparented ShapeRenderable.",
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


def write_collision_obj(path, bx, by, bz, inner_r_blocks):
    # Units: blocks. Origin = hull CENTER. Y up. Sticky -Y = y=-by/2.
    hx, hy, hz = bx * 0.5, by * 0.5, bz * 0.5
    floor_top = -hy + 0.45
    r = max(inner_r_blocks, 1.2)
    wall = 0.35
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

    # Tube floor so they stand inside. Walls at glass radius.
    box(-r, r, -hy, floor_top, -r, r)
    box(-r - wall, -r, floor_top, hy, -r - wall, r + wall)
    box(r, r + wall, floor_top, hy, -r - wall, r + wall)
    box(-r, r, floor_top, hy, -r - wall, -r)
    box(-r, r, floor_top, hy, r, r + wall)
    lines = [
        "# rfs_deepsleep_col _v9. Units: blocks. Hull %dx%dx%d. Origin center."
        % (bx, by, bz),
        "# Circular-base at y=-%.3f. Inner tube floor + walls. Re-place." % hy,
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
    print("IMPORT", GLB, os.path.isfile(GLB))
    if not os.path.isfile(GLB):
        raise SystemExit("missing glb")
    bpy.ops.import_scene.gltf(filepath=GLB)
    clear_parents_keep()
    objs = mesh_objects()
    apply_tr(objs)
    objs = mesh_objects()
    rename_materials(objs)
    parts = join_by_material(objs)
    apply_tr(parts)

    glass = down = None
    for o in parts:
        if o.name == "glass":
            glass = o
        if o.name == "down":
            down = o
    gmins, gmaxs = world_bounds([glass] if glass else parts)
    gsize = gmaxs - gmins
    s = TARGET_GLASS_H_M / max(gsize.z, 1e-6)
    for o in parts:
        o.scale = (s, s, s)
    apply_tr(parts)

    gmins, gmaxs = world_bounds([glass] if glass else parts)
    dmins, dmaxs = world_bounds([down] if down else parts)
    omins, omaxs = world_bounds(parts)
    # Sit circular BASE on hull bottom. Ignore hanging-arm verts below the plate.
    base_z = dmins.z
    top_z = omaxs.z
    height = top_z - base_z
    cx = (omins.x + omaxs.x) * 0.5
    cy = (omins.y + omaxs.y) * 0.5
    # Hull Y from base→cap, then park the plate exactly on sticky -Y (origin center).
    by_blocks = blocks_for(height)
    half_y_m = by_blocks * BLOCK * 0.5
    for o in parts:
        o.location.x -= cx
        o.location.y -= cy
        o.location.z -= base_z + half_y_m
    apply_tr(parts)

    gmins, gmaxs = world_bounds([glass] if glass else parts)
    gsize = gmaxs - gmins
    gcenter = (gmins + gmaxs) * 0.5
    fill_r = min(gsize.x, gsize.y) * 0.42
    fill_h = max(gsize.z * 0.82, 1.2)
    fill_z0 = gmins.z + (gsize.z - fill_h) * 0.08

    mat_files = {}
    for o in parts:
        png = os.path.join(OUT_TEX, o.name + "_dif.png")
        mat_files[o.name] = png

    body = join_all(list(parts), STEM)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    fbx = os.path.join(OUT_MESH, STEM + ".fbx")
    dae = os.path.join(OUT_MESH, STEM + ".dae")
    export_fbx(fbx)
    export_dae(dae)
    rend = write_rend_body(mat_files)

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
    bpy.ops.object.select_all(action="DESELECT")
    fill.select_set(True)
    bpy.context.view_layer.objects.active = fill
    fill_fbx = os.path.join(OUT_MESH, FILL_STEM + ".fbx")
    fill_dae = os.path.join(OUT_MESH, FILL_STEM + ".dae")
    export_fbx(fill_fbx)
    export_dae(fill_dae)
    fill_rend = write_rend_fill(os.path.join(OUT_TEX, "chemfill_dif.png"))

    bmins, bmaxs = world_bounds([body])
    bsize = bmaxs - bmins
    bx = blocks_for(max(bsize.x, abs(bsize.y)))
    bz = bx
    by = by_blocks
    inner_r_m = min(gsize.x, gsize.y) * 0.5
    inner_r_blocks = max(inner_r_m / BLOCK, 1.5)
    write_collision_obj(
        os.path.join(OUT_COL, "rfs_deepsleep_col.obj"),
        bx, by, bz, inner_r_blocks,
    )

    half_y_m = by * BLOCK * 0.5
    stand_y = -half_y_m + 0.90
    fill_bottom_sm_y = float(fill_z0)  # blender Z == SM Y after bake
    meta = {
        "stem": STEM,
        "hull_blocks": [bx, by, bz],
        "glass_height_m": float(gsize.z),
        "mesh_height_m": float(bsize.z),
        "mesh_width_m": [float(bsize.x), float(bsize.y)],
        "scale": s,
        "fill_radius_m": float(fill_r),
        "fill_height_m": float(fill_h),
        "fill_bottom_y_sm": fill_bottom_sm_y,
        "stand_local_sm": [0.0, round(stand_y, 3), 0.0],
        "root_jnt": {"x": 0.0, "y": round(stand_y, 3), "z": 0.0},
        "exit_forward_m": round(inner_r_m + 0.85, 3),
        "exit_lift_m": 0.4,
        "half_y_m": half_y_m,
        "inner_r_m": float(inner_r_m),
        "verts": len(body.data.vertices),
        "polys": len(body.data.polygons),
    }
    out = os.path.join(ROOT, "Art", "sm_export_v9_meta.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
    print("DONE", json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
