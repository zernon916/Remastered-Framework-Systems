# Blender: measure CGTrader fbx_kit yaw + bounds vs SM grid.
# Run: blender --background --python Art/measure_fbx_kit_yaw.py
import bpy
import os
import json
import math

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
KIT_DIR = os.path.join(ROOT, "Art", "cgtrader", "source", "fbx_kit")
OUT = os.path.join(ROOT, "Art", "sm_measure_fbx_kit.json")

FBX_FILES = [
    "WalkieTalkieRadio.FBX",
    "LaptopRadio.FBX",
    "TransmitterRadio.FBX",
    "ArVrRadio.FBX",
]
EXTRA = [
    ("Radio1.obj", os.path.join(ROOT, "Art", "cgtrader", "source", "Radio1.obj")),
]


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_file(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    else:
        raise ValueError("unsupported: " + path)


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def apply_tr(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def join_meshes(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = name
    return body


def obb_yaw_deg(body):
    """Dominant horizontal edge yaw; rotation-only on local verts (ignores bad FBX object scale)."""
    import numpy as np

    rot = body.matrix_world.to_quaternion().to_matrix()
    verts = [rot @ v.co for v in body.data.vertices]
    if len(verts) < 3:
        return 0.0
    pts = np.array([[v.x, v.y] for v in verts])
    cov = np.cov(pts.T)
    evals, evecs = np.linalg.eigh(cov)
    major = evecs[:, int(np.argmax(evals))]
    yaw = math.degrees(math.atan2(major[1], major[0]))
    while yaw >= 90.0:
        yaw -= 180.0
    while yaw < -90.0:
        yaw += 180.0
    return round(yaw, 2)


def nearest_grid_residual(yaw):
    snapped = round(yaw / 90.0) * 90.0
    return round(yaw - snapped, 2)


def grid_class(residual):
    a = abs(residual)
    if a <= 15.0:
        return "axis (~0°)"
    if 30.0 <= a <= 60.0:
        return "diagonal (~45°)"
    return "off-axis"


def local_bounds_cm(body):
    """Mesh local bounds; CGTrader FBX verts are typically cm before bad object scale."""
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for v in body.data.vertices:
        for i, c in enumerate(v.co):
            mn[i] = min(mn[i], c)
            mx[i] = max(mx[i], c)
    sx, sy, sz = mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]
    return {
        "size_cm_xyz": [round(sx, 2), round(sy, 2), round(sz, 2)],
        "size_meters": [round(sx / 100, 3), round(sy / 100, 3), round(sz / 100, 3)],
        "footprint_blocks_xy": [round(sx / 100, 2), round(sy / 100, 2)],
        "height_blocks": round(sz / 100, 2),
    }


def measure_object(body):
    raw_yaw = obb_yaw_deg(body)
    residual = nearest_grid_residual(raw_yaw)
    b = local_bounds_cm(body)
    return {
        "name": body.name,
        "raw_pca_yaw_deg": raw_yaw,
        "residual_off_grid_deg": residual,
        "recommend_grid_yaw_deg": round(-residual, 1),
        "grid_class": grid_class(residual),
        "bounds": b,
        "footprint_blocks_xy": b["footprint_blocks_xy"],
        "height_blocks": b["height_blocks"],
    }


def measure_path(path, label=None):
    reset_scene()
    import_file(path)
    objs = mesh_objects()
    if not objs:
        return {"file": label or os.path.basename(path), "error": "no meshes"}
    per_mesh = [measure_object(o) for o in objs]
    apply_tr(objs)
    body = join_meshes(list(objs), "measure")
    joined = measure_object(body)
    return {
        "file": label or os.path.basename(path),
        "path": path,
        "mesh_count": len(per_mesh),
        "joined": joined,
        "meshes": per_mesh,
    }


def main():
    results = []
    for name in FBX_FILES:
        path = os.path.join(KIT_DIR, name)
        if not os.path.isfile(path):
            results.append({"file": name, "error": "missing"})
            continue
        results.append(measure_path(path))

    for label, path in EXTRA:
        if os.path.isfile(path):
            results.append(measure_path(path, label))

    payload = {"kit_dir": KIT_DIR, "parts": results}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
    print("WROTE", OUT)
    for r in results:
        print(json.dumps(r, indent=2))


if __name__ == "__main__":
    main()
