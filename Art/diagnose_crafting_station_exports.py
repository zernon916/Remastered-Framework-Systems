# Compare source, prior FBX, and current FBX without modifying any asset.
import json
import bpy
from mathutils import Vector

SOURCE = r"C:\Coding Projects\models\WIP Models\RTICrafting Station.blend"
FILES = {
    "known_visible_ee": r"C:\Coding Projects\Testing\RemasteredFrameworkSystems0854-ee\Objects\Mesh\rfs_crafting_station.fbx",
    "prior_ef": r"C:\Coding Projects\Testing\RemasteredFrameworkSystems0854-ef\Objects\Mesh\rfs_crafting_station.fbx",
    "current_eg": r"C:\Coding Projects\Testing\RemasteredFrameworkSystems0854-eg\Objects\Mesh\rfs_crafting_station.fbx",
    "working": r"C:\Coding Projects\RemasteredFrameworkSystems\Objects\Mesh\rfs_crafting_station.fbx",
}
OUT = r"C:\Coding Projects\RemasteredFrameworkSystems\Art\diagnose_crafting_station_exports.json"

def summary(label):
    rows = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        signed = 0.0
        degenerate = 0
        for poly in mesh.polygons:
            area = poly.area
            if area <= 1e-10:
                degenerate += 1
            signed += poly.center.dot(poly.normal) * area / 3.0
        points = [obj.matrix_world @ v.co for v in mesh.vertices]
        mn = [min(p[a] for p in points) for a in range(3)]
        mx = [max(p[a] for p in points) for a in range(3)]
        rows.append({
            "name": obj.name,
            "vertices": len(mesh.vertices),
            "edges": len(mesh.edges),
            "polygons": len(mesh.polygons),
            "loops": len(mesh.loops),
            "triangles": sum(max(0, len(p.vertices)-2) for p in mesh.polygons),
            "ngons": sum(1 for p in mesh.polygons if len(p.vertices)>4),
            "degenerate": degenerate,
            "signed_volume_proxy": round(signed, 6),
            "bounds": [[round(v,4) for v in mn], [round(v,4) for v in mx]],
            "scale": [round(v,6) for v in obj.scale],
            "determinant": round(obj.matrix_world.to_3x3().determinant(), 6),
            "uv_layers": [x.name for x in mesh.uv_layers],
            "attributes": [(x.name, x.data_type, x.domain) for x in mesh.attributes],
            "materials": [m.name if m else None for m in mesh.materials],
        })
    return {"label": label, "objects": sorted(rows, key=lambda x:x["name"])}

report = {}
bpy.ops.wm.open_mainfile(filepath=SOURCE)
report["source"] = summary("source")
for key, path in FILES.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path, use_anim=False)
    report[key] = summary(key)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
print("RFS_CRAFT_EXPORT_DIAG_OK", OUT)