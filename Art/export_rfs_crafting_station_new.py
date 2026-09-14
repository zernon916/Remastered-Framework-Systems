# Export Crafting_Station_SM.blend -> rfs_crafting_station.fbx
# Faithful 1:1 export at the model's native position/scale (no recenter/re-scale),
# per instruction not to edit the .blend. Blender 5.2 io_scene_fbx addon.
# Run: "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --python Art\export_rfs_crafting_station_new.py
import bpy
import json
import mathutils
import os

BLEND = r"C:\Coding Projects\models\WIP Models\Crafting_Station_SM.blend"
ROOT = r"C:\Coding Projects\RemasteredFrameworkSystems"
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh", "rfs_crafting_station.fbx")
META = os.path.join(ROOT, "Art", "sm_export_crafting_station_new_meta.json")
BLOCK = 0.25  # 1 SM block = 0.25 m


def all_mesh_objects():
    out = []
    def walk(obj):
        if obj.type == "MESH":
            out.append(obj)
        for c in getattr(obj, "children", []):
            walk(c)
    for o in list(bpy.context.scene.objects):
        walk(o)
    return out


def world_bounds(objs):
    mins = None
    maxs = None
    for o in objs:
        mx = mathutils.Matrix(o.matrix_world)
        for c in o.bound_box:
            w = mx @ mathutils.Vector(c)
            if mins is None:
                mins = mathutils.Vector(w); maxs = mathutils.Vector(w)
            else:
                mins.x = min(mins.x, w.x); mins.y = min(mins.y, w.y); mins.z = min(mins.z, w.z)
                maxs.x = max(maxs.x, w.x); maxs.y = max(maxs.y, w.y); maxs.z = max(maxs.z, w.z)
    return mins, maxs


def export_fbx(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kw = dict(
        filepath=path,
        use_selection=True,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        global_scale=1.0,
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=True,
        object_types=set(["MESH"]),
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


def main():
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    objs = all_mesh_objects()
    print("MESHES", len(objs), [o.name for o in objs])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mins, maxs = world_bounds(objs)
    size = maxs - mins
    per = []
    for o in objs:
        per.append({
            "name": o.name,
            "verts": len(o.data.vertices),
            "faces": len(o.data.polygons),
            "materials": [m.name for m in o.data.materials if m is not None],
        })
    meta = {
        "blend": BLEND,
        "fbx": OUT_MESH,
        "scale": 1.0,
        "recentered": False,
        "exported_objects": per,
        "size_m": [round(size.x, 4), round(size.y, 4), round(size.z, 4)],
        # SM: X=right, Y=up, Z=depth (FBX exporter -Z forward/Y up -> size.z world = SM depth after export).
        "size_sm_blocks": [round(size.x / BLOCK, 3), round(size.z / BLOCK, 3), round(size.y / BLOCK, 3)],
        "min_world": [round(mins.x, 4), round(mins.y, 4), round(mins.z, 4)],
        "max_world": [round(maxs.x, 4), round(maxs.y, 4), round(maxs.z, 4)],
    }
    export_fbx(OUT_MESH, objs)
    with open(META, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
    print("RFS_CRAFTING_EXPORT_OK", json.dumps(meta, sort_keys=True))


if __name__ == "__main__":
    main()