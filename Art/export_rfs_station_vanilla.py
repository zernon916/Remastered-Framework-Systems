# Blender 4.4: re-export vanilla SM station meshes with PropY grid yaw baked in.
# Run: blender --background --python Art/export_rfs_station_vanilla.py
import bpy
import os
import json
import math
import mathutils

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
SM = r"C:\Steam\steamapps\common\Scrap Mechanic"
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh")
OUT_REND = os.path.join(ROOT, "Objects", "Renderable")
OUT_ART = os.path.join(ROOT, "Art")
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID

PARTS = [
    {
        "key": "timer",
        "stem": "rfs_station_timer",
        "rend": "rfs_station_timer.rend",
        "fbx": os.path.join(SM, "Data", "Objects", "Mesh", "interactive", "obj_interactive_timer.fbx"),
        "box": (1, 2, 1),
        "grid_yaw_deg": 0.0,
        "snap_grid": True,
        "vanilla_rend": "$GAME_DATA/Objects/Renderable/Interactive/obj_interactive_timer.rend",
    },
    {
        "key": "sensor",
        "stem": "rfs_station_sensor",
        "rend": "rfs_station_sensor.rend",
        "fbx": os.path.join(SM, "Survival", "Objects", "Mesh", "interactive", "obj_interactive_sensor_off.fbx"),
        "box": (1, 1, 1),
        # Sensor mesh is authored for PropZY wall (south=Z). Rotate to PropY floor (south=-Y).
        "pre_rot_deg": (-90.0, 0.0, 0.0),
        "grid_yaw_deg": 0.0,
        "snap_grid": True,
        "vanilla_rend": "$SURVIVAL_DATA/Objects/Renderable/interactive_upgradeable/obj_interactiveupgradeable_sensor01.rend",
    },
    {
        "key": "batterybox",
        "stem": "rfs_station_batterybox",
        "rend": "rfs_station_batterybox.rend",
        "fbx": os.path.join(SM, "Survival", "Objects", "Mesh", "containers", "obj_containers_battery.fbx"),
        "box": (4, 3, 3),
        "grid_yaw_deg": 0.0,
        "snap_grid": True,
        # Vanilla container mesh is already authored at the shape origin; sit_on_bottom
        # pushes it to z=-boxY/2 and the part renders invisible on PropY.
        "sit_on_bottom": False,
        "vanilla_rend": "$SURVIVAL_DATA/Objects/Renderable/Containers/obj_containers_battery.rend",
    },
]

os.makedirs(OUT_MESH, exist_ok=True)
os.makedirs(OUT_REND, exist_ok=True)


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


def join_meshes(objs, name):
    select_meshes(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    if body.data:
        body.data.name = name
    apply_tr([body])
    return body


def snap_yaw_to_grid(body):
    apply_tr([body])
    z = body.rotation_euler.z
    snapped = round(z / (math.pi * 0.5)) * (math.pi * 0.5)
    if abs(z - snapped) > 0.01:
        body.rotation_euler.z = snapped
        apply_tr([body])


def apply_grid_yaw(body, deg, snap=False):
    apply_tr([body])
    if deg:
        body.rotation_euler.z += math.radians(float(deg))
        apply_tr([body])
    if snap:
        snap_yaw_to_grid(body)


def sit_on_bottom(body, box_y):
    apply_tr([body])
    mins, _ = world_bounds([body])
    if mins is None:
        return
    dz = (-box_y * 0.5) - mins.z
    if abs(dz) > 0.001:
        body.matrix_world.translation += mathutils.Vector((0.0, 0.0, dz))
        apply_tr([body])


def center_xz(body):
    apply_tr([body])
    mins, maxs = world_bounds([body])
    if mins is None:
        return
    cx = 0.5 * (mins.x + maxs.x)
    cy = 0.5 * (mins.y + maxs.y)
    body.matrix_world.translation += mathutils.Vector((-cx, -cy, 0.0))
    apply_tr([body])


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


def copy_vanilla_rend(part, mesh_path):
    """Clone vanilla .rend subMesh entries but point mesh at our re-export."""
    vanilla_path = part["vanilla_rend"]
    sm_root = SM
    rel = vanilla_path.replace("$GAME_DATA/", os.path.join(sm_root, "Data") + os.sep)
    rel = rel.replace("$SURVIVAL_DATA/", os.path.join(sm_root, "Survival") + os.sep)
    if not os.path.isfile(rel):
        raise FileNotFoundError(rel)
    with open(rel, "r", encoding="utf-8") as f:
        data = json.load(f)
    mesh_ref = PREFIX + "/Objects/Mesh/" + os.path.basename(mesh_path)
    if data.get("lodList"):
        data["lodList"][0]["mesh"] = mesh_ref
        if len(data["lodList"]) > 1 and "lod1" in part["stem"]:
            pass
        # Drop LOD1 — station props are close-range; keeps rend small.
        data["lodList"] = data["lodList"][:1]
    data["_comment"] = (
        f"Vanilla {part['key']} mesh re-export for PropY grid snap (0850-d). "
        f"Textures unchanged from {vanilla_path}."
    )
    out = os.path.join(OUT_REND, part["rend"])
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent="\t")
        f.write("\n")
    return out


def export_part(part):
    reset_scene()
    fbx_in = part["fbx"]
    if not os.path.isfile(fbx_in):
        return {"key": part["key"], "error": "missing " + fbx_in}
    bpy.ops.import_scene.fbx(filepath=fbx_in)
    objs = mesh_objects()
    body = join_meshes(objs, part["stem"])
    pre = part.get("pre_rot_deg")
    if pre:
        body.rotation_euler = tuple(math.radians(v) for v in pre)
        apply_tr([body])
    center_xz(body)
    bx, by, bz = part["box"]
    if part.get("sit_on_bottom", True):
        sit_on_bottom(body, by)
    apply_grid_yaw(body, part.get("grid_yaw_deg", 0.0), snap=part.get("snap_grid", False))
    if part.get("sit_on_bottom", True):
        sit_on_bottom(body, by)
    out_fbx = os.path.join(OUT_MESH, part["stem"] + ".fbx")
    select_meshes([body])
    export_fbx(out_fbx)
    rend = copy_vanilla_rend(part, out_fbx)
    return {
        "key": part["key"],
        "stem": part["stem"],
        "fbx": out_fbx,
        "rend": rend,
        "grid_yaw_deg": part.get("grid_yaw_deg", 0.0),
        "pre_rot_deg": part.get("pre_rot_deg"),
    }


def main():
    results = [export_part(p) for p in PARTS]
    meta = os.path.join(OUT_ART, "sm_export_station_vanilla_meta.json")
    with open(meta, "w", encoding="utf-8") as f:
        json.dump({"parts": results}, f, indent=2)
    print("WROTE", meta)
    for r in results:
        print(r)


if __name__ == "__main__":
    main()
