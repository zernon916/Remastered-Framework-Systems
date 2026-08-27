# Export compact Craftbot mesh (Myworkcraftbot_3x3.obj) -> SM FBX + rend.
# Vanilla Craftbot body/screen textures via $SURVIVAL_DATA paths.
# Run: blender --background --python Art/export_rfs_crafting_station.py
import bpy
import bmesh
import json
import mathutils
import os

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
OBJ_IN = r"C:\Users\benko\OneDrive\Desktop\RecipeFrameworkSurvival\DesignsBlender\Myworkcraftbot_3x3.obj"
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh", "rfs_crafting_station.fbx")
OUT_REND = os.path.join(ROOT, "Objects", "Renderable", "rfs_crafting_station.rend")
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
SUR = "$SURVIVAL_DATA/Character/Char_Craftbot"


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def world_bounds(obj):
    corners = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
    xs = [c.x for c in corners]
    ys = [c.y for c in corners]
    zs = [c.z for c in corners]
    return mathutils.Vector((min(xs), min(ys), min(zs))), mathutils.Vector((max(xs), max(ys), max(zs)))


def assign_screen_faces(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    axis_scores = {(1, 0, 0): 0, (-1, 0, 0): 0, (0, 1, 0): 0, (0, -1, 0): 0}
    for f in bm.faces:
        n = f.normal.normalized()
        for ax in axis_scores:
            if n.dot(mathutils.Vector(ax)) > 0.55:
                axis_scores[ax] += f.calc_area()
    front = mathutils.Vector(max(axis_scores, key=axis_scores.get))
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    screen = 0
    for f in bm.faces:
        f.material_index = 0
        n = f.normal.normalized()
        if n.dot(front) < 0.65:
            continue
        c = f.calc_center_median()
        if abs(front.y) > 0.5:
            u, v = c.x, c.z
            u_center = cx
        elif abs(front.x) > 0.5:
            u, v = c.y, c.z
            u_center = cy
        else:
            u, v = c.x, c.y
            u_center = cx
        if abs(u - u_center) < 0.95 and 0.8 < v < 2.35:
            f.material_index = 1
            screen += 1
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    return int(front.x), int(front.y), int(front.z), screen


def ensure_uv(obj):
    if obj.data.uv_layers:
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=66.0, island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")


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


def write_rend():
    data = {
        "_comment": "Compact 3x3 Crafting Station. Vanilla Craftbot textures; UVs from Blender smart project.",
        "lodList": [
            {
                "mesh": PREFIX + "/Objects/Mesh/rfs_crafting_station.fbx",
                "maxViewDistance": 1000.0,
                "subMeshMap": {
                    "craftbot": {
                        "custom": {"metalProfile": "DifAsgNor_Painted"},
                        "material": "DifAsgNor_Metal",
                        "textureList": [
                            SUR + "/char_craftbot_dif.tga",
                            SUR + "/char_craftbot_asg.tga",
                            SUR + "/char_craftbot_nor.tga",
                        ],
                    },
                    "screen": {
                        "custom": {"uv0": {"u": 0.25, "v": 0.25}},
                        "material": "UVAnimDifAsgNor",
                        "textureList": [
                            SUR + "/char_craftboticons_dif.tga",
                            SUR + "/char_craftboticons_asg.tga",
                            "$GAME_DATA/Textures/Materialtextures/normal_nor.tga",
                        ],
                    },
                },
            }
        ],
    }
    with open(OUT_REND, "w", encoding="utf-8") as f:
        json.dump(data, f, indent="\t")
        f.write("\n")


def main():
    if not os.path.isfile(OBJ_IN):
        raise SystemExit("Missing OBJ: " + OBJ_IN)
    os.makedirs(os.path.dirname(OUT_MESH), exist_ok=True)
    reset_scene()
    bpy.ops.wm.obj_import(filepath=OBJ_IN)
    obj = bpy.context.selected_objects[0]
    obj.name = "rfs_crafting_station"
    obj.data.name = "rfs_crafting_station"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    body_mat = bpy.data.materials.new("craftbot")
    body_mat.use_nodes = True
    screen_mat = bpy.data.materials.new("screen")
    screen_mat.use_nodes = True
    obj.data.materials.clear()
    obj.data.materials.append(body_mat)
    obj.data.materials.append(screen_mat)

    fx, fy, fz, screen_faces = assign_screen_faces(obj)
    ensure_uv(obj)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    export_fbx(OUT_MESH)
    write_rend()

    b0, b1 = world_bounds(obj)
    size = b1 - b0
    meta = {
        "obj_in": OBJ_IN,
        "fbx": OUT_MESH,
        "rend": OUT_REND,
        "verts": len(obj.data.vertices),
        "faces": len(obj.data.polygons),
        "screen_faces": screen_faces,
        "front_axis": [fx, fy, fz],
        "size_blender": [round(size.x, 4), round(size.y, 4), round(size.z, 4)],
        "size_sm": [round(size.x, 4), round(size.z, 4), round(size.y, 4)],
    }
    print("RFS_CRAFTING_STATION_EXPORT", json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
