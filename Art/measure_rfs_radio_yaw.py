# Blender 4.4: measure pre-export mesh yaw vs SM grid (0850-h).
# Run: blender --background --python Art/measure_rfs_radio_yaw.py
import bpy
import os
import json
import math
import mathutils

# Reuse export pipeline constants.
import sys
ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
sys.path.insert(0, os.path.join(ROOT, "Art"))

# Import shared helpers from export script by exec (Blender has no package import).
_export_path = os.path.join(ROOT, "Art", "export_rfs_radio.py")
with open(_export_path, "r", encoding="utf-8") as f:
    _src = f.read()
# Strip main guard so we get functions only.
_src = _src.split('if __name__ == "__main__":')[0]
exec(_src, globals())


def obb_yaw_deg(body):
    """Dominant horizontal edge yaw in Blender XY (SM floor plane after FBX export)."""
    apply_tr([body])
    verts = [(body.matrix_world @ v.co) for v in body.data.vertices]
    if len(verts) < 3:
        return 0.0
    import numpy as np
    pts = np.array([[v.x, v.y] for v in verts])
    cov = np.cov(pts.T)
    evals, evecs = np.linalg.eigh(cov)
    major = evecs[:, int(np.argmax(evals))]
    yaw = math.degrees(math.atan2(major[1], major[0]))
    # Normalize to [-90, 90) vs nearest axis-aligned direction.
    while yaw >= 90.0:
        yaw -= 180.0
    while yaw < -90.0:
        yaw += 180.0
    return round(yaw, 2)


def nearest_grid_residual(yaw):
    """Signed degrees off nearest 90° grid line."""
    snapped = round(yaw / 90.0) * 90.0
    return round(yaw - snapped, 2)


def measure_part(part):
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=GLB)
    objs = collect_part_meshes(part)
    if not objs:
        return {"key": part["key"], "error": "no meshes"}
    unparent_keep(objs)
    apply_tr(objs)
    objs = collect_part_meshes(part)
    body = join_meshes(objs, part["stem"] + "_measure")
    if part.get("align_long_axis_z"):
        align_long_axis_z(body)
    scale_and_sit(body, tuple(part["target"]), uniform=part.get("uniform_scale", True))
    if part.get("sit_visual_bottom"):
        sit_visual_bottom(body, part["target"][1])
    else:
        flush_bottom(body, part["target"][1])
    raw_yaw = obb_yaw_deg(body)
    residual = nearest_grid_residual(raw_yaw)
    # Counter-rotate mesh so silhouette aligns to grid at placement.
    recommend = round(-residual, 1)
    return {
        "key": part["key"],
        "raw_pca_yaw_deg": raw_yaw,
        "residual_off_grid_deg": residual,
        "recommend_grid_yaw_deg": recommend,
    }


def main():
    if not os.path.isfile(GLB):
        raise SystemExit("missing GLB: " + GLB)
    results = []
    for part in PARTS:
        results.append(measure_part(part))
    out = os.path.join(OUT_ART, "sm_measure_radio_yaw.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"glb": GLB, "parts": results}, f, indent=2)
    print("WROTE", out)
    for r in results:
        print(r)


if __name__ == "__main__":
    main()
