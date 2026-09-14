# Clean-room verification for the exported crafting-station FBX.
import json
import os

import bpy
from mathutils import Vector

FBX = r"C:\Coding Projects\RemasteredFrameworkSystems\Objects\Mesh\rfs_crafting_station.fbx"
REPORT = r"C:\Coding Projects\RemasteredFrameworkSystems\Art\sm_verify_rti_crafting_fbx.json"
EXPECTED_SUBMESHES = {
    "craftingstation_body", "craftingstation_screen", "craftingstation_slider",
    "submesh_light_01", "submesh_light_02",
}

def rounded(vector, digits=4):
    return [round(float(value), digits) for value in vector]

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=FBX, use_anim=False)
    objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(objects) != 1 or objects[0].name != "craftingstation_body":
        raise RuntimeError("Expected one craftingstation_body geometry object")
    names = {material.name for material in objects[0].data.materials if material}
    if names != EXPECTED_SUBMESHES:
        raise RuntimeError("Incorrect FBX submesh partitions: " + repr(sorted(names)))

    points, pieces = [], []
    for obj in objects:
        points.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        piece = {
            "name": obj.name,
            "vertices": len(obj.data.vertices),
            "polygons": len(obj.data.polygons),
            "uv_layers": len(obj.data.uv_layers),
            "materials": [material.name if material else None for material in obj.data.materials],
        }
        if piece["vertices"] != 1519 or piece["polygons"] != 1046:
            raise RuntimeError("FBX topology differs from known-visible -ee")
        if piece["uv_layers"] < 1:
            raise RuntimeError(obj.name + " lost its UV layer")
        pieces.append(piece)

    minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    size = maximum - minimum
    center = (minimum + maximum) * 0.5
    expected_size = Vector((6.0, 4.0, 5.0))
    for axis in range(3):
        if abs(size[axis] - expected_size[axis]) > 0.15:
            raise RuntimeError("Incorrect imported dimensions: " + repr(rounded(size)))
    if center.length > 0.001:
        raise RuntimeError("Imported FBX is not centered: " + repr(rounded(center, 6)))

    report = {
        "fbx": FBX,
        "file_bytes": os.path.getsize(FBX),
        "geometry_objects": [obj.name for obj in objects],
        "submeshes": sorted(names),
        "bounds": {"minimum": rounded(minimum), "maximum": rounded(maximum)},
        "size_blocks_blender_axes": rounded(size),
        "center": rounded(center, 6),
        "pieces": sorted(pieces, key=lambda value: value["name"]),
        "verified": True,
    }
    with open(REPORT, "w", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print("RFS_RTI_FBX_VERIFY_OK", json.dumps(report, sort_keys=True))

if __name__ == "__main__":
    main()