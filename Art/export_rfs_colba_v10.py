# Blender 4.4: scale Colba _v9 mesh from meters into SM hull blocks (x4).
# v9 baked glass 2.75 m / base at y=-2.125 m. SM renderables share hull BLOCK
# space (solar 5-unit mesh on a 5-block box). Result: 17-block hull, base at -8.5.
# Run: blender --background --python Art/export_rfs_colba_v10.py
import bpy
import os
import json

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh")
OUT_REND = os.path.join(ROOT, "Objects", "Renderable")
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
BLOCK = 0.25
SCALE = 1.0 / BLOCK  # meters -> blocks
STEM = "rfs_deepsleep_v10"
FILL_STEM = "rfs_chemfill_v10"
SRC_BODY = os.path.join(OUT_MESH, "rfs_deepsleep_v9.fbx")
SRC_FILL = os.path.join(OUT_MESH, "rfs_chemfill_v9.fbx")
# Lower body mesh so rim sits flush with adjacent blocks (full 1 SM block).
BODY_Y_NUDGE_BLOCKS = -1.0


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


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


def world_bounds(objs):
    import mathutils
    mins = mathutils.Vector((1e9, 1e9, 1e9))
    maxs = mathutils.Vector((-1e9, -1e9, -1e9))
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
    return mins, maxs


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


def scale_imported(path, stem, y_nudge_blocks=0.0):
    reset_scene()
    bpy.ops.import_scene.fbx(filepath=path)
    objs = mesh_objects()
    if not objs:
        raise SystemExit("no mesh in " + path)
    apply_tr(objs)
    for o in objs:
        o.scale = (SCALE, SCALE, SCALE)
    apply_tr(objs)
    if y_nudge_blocks:
        for o in objs:
            o.location.y += y_nudge_blocks
        apply_tr(objs)
    body = objs[0]
    body.name = stem
    if body.data:
        body.data.name = stem
    select_meshes([body])
    fbx = os.path.join(OUT_MESH, stem + ".fbx")
    dae = os.path.join(OUT_MESH, stem + ".dae")
    export_fbx(fbx)
    export_dae(dae)
    mins, maxs = world_bounds([body])
    size = maxs - mins
    return {
        "stem": stem,
        "fbx": fbx,
        "dae": dae,
        "scale": SCALE,
        "world_min": [float(mins.x), float(mins.y), float(mins.z)],
        "world_max": [float(maxs.x), float(maxs.y), float(maxs.z)],
        "world_size": [float(size.x), float(size.y), float(size.z)],
        "verts": len(body.data.vertices),
        "materials": [m.name for m in (body.data.materials or []) if m],
    }


def write_rend_body():
    asg = PREFIX + "/Objects/Textures/shared/rfs_asg.tga"
    nor = PREFIX + "/Objects/Textures/shared/rfs_nor.tga"
    gd = "$GAME_DATA/Objects/Textures/industrial/obj_industrial_windowglass"
    glass_custom = {
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
    tex = PREFIX + "/Objects/Textures/deepsleep/"
    sub = {
        "down": {
            "material": "DifAsgNor",
            "textureList": [tex + "down_dif.png", asg, nor],
        },
        "up": {
            "material": "DifAsgNor",
            "textureList": [tex + "up_dif.png", asg, nor],
        },
        "glass": {
            "material": "Glass",
            "custom": glass_custom,
            "textureList": [gd + "_dif.tga", gd + "_asg.tga", gd + "_nor.tga"],
            "textures": {
                "diffuse": gd + "_dif.tga",
                "asg": gd + "_asg.tga",
                "normalMap": gd + "_nor.tga",
            },
        },
        "decals": {
            "material": "Glass",
            "custom": glass_custom,
            "textureList": [tex + "decals_dif.png", asg, nor],
        },
    }
    data = {
        "_comment": "Colba _v10. Mesh verts in hull BLOCKS (x4 from v9 meters). Base at -Y.",
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


def write_rend_fill():
    asg = PREFIX + "/Objects/Textures/shared/rfs_asg.tga"
    nor = PREFIX + "/Objects/Textures/shared/rfs_nor.tga"
    png = PREFIX + "/Objects/Textures/deepsleep/chemfill_dif.png"
    data = {
        "_comment": "Purple chem tank fill _v10. Unparented ShapeRenderable. Block-space mesh.",
        "lodList": [
            {
                "mesh": PREFIX + "/Objects/Mesh/" + FILL_STEM + ".fbx",
                "subMeshMap": {
                    "chemfill": {
                        "material": "Glass",
                        "custom": {
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
                        },
                        "textureList": [png, asg, nor],
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


def main():
    if not os.path.isfile(SRC_BODY):
        raise SystemExit("missing " + SRC_BODY)
    if not os.path.isfile(SRC_FILL):
        raise SystemExit("missing " + SRC_FILL)
    body = scale_imported(SRC_BODY, STEM, y_nudge_blocks=BODY_Y_NUDGE_BLOCKS)
    fill = scale_imported(SRC_FILL, FILL_STEM)
    rend = write_rend_body()
    fill_rend = write_rend_fill()
    meta = {
        "stem": STEM,
        "fill_stem": FILL_STEM,
        "scale_from_v9": SCALE,
        "hull_blocks": [17, 17, 17],
        "note": "v9 meters x4; body Y nudge %s blocks for ground flush"
        % (BODY_Y_NUDGE_BLOCKS,),
        "body_y_nudge_blocks": BODY_Y_NUDGE_BLOCKS,
        "body": body,
        "fill": fill,
        "rend": rend,
        "fill_rend": fill_rend,
        "stand_local_sm_m": [0.0, -1.225, 0.0],
        "fill_lua_m": {"radius": 0.650, "height": 2.255, "bottom_y": -1.197},
    }
    out = os.path.join(ROOT, "Art", "sm_export_v10_meta.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
    print("DONE", json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
