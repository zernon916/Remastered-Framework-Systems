# Export RTICrafting Station.blend for Scrap Mechanic.
# Evaluates modifiers/parents, preserves mesh data, converts metres to blocks,
# centers the visual, then reproduces the known-visible 0854-ee FBX structure:
# one geometry object with five named material/submesh partitions.
import json
import os

import bpy
from mathutils import Matrix, Vector

BLEND = r"C:\Coding Projects\models\WIP Models\RTICrafting Station.blend"
ROOT = r"C:\Coding Projects\RemasteredFrameworkSystems"
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh", "rfs_crafting_station.fbx")
META = os.path.join(ROOT, "Art", "sm_export_rti_crafting_meta.json")
METRES_TO_BLOCKS = 4.0

PIECES = (
    "craftingstation_body",
    "craftingstation_screen",
    "craftingstation_slider",
    "submesh_light_01",
    "submesh_light_02",
)

def rounded(vector, digits=4):
    return [round(float(value), digits) for value in vector]


def mesh_bounds(meshes):
    points = [vertex.co for mesh in meshes for vertex in mesh.vertices]
    if not points:
        raise RuntimeError("No vertices were produced")
    minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return minimum, maximum


def evaluated_mesh_copy(obj, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    temporary = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    if temporary is None:
        raise RuntimeError("Could not evaluate " + obj.name)
    try:
        mesh = temporary.copy()
    finally:
        evaluated.to_mesh_clear()
    mesh.transform(Matrix.Scale(METRES_TO_BLOCKS, 4) @ obj.matrix_world)
    mesh.name = obj.name
    # Replace source materials on the temporary copy. Scrap Mechanic uses the
    # material names as submesh keys and obtains shaders/textures from .rend.
    mesh.materials.clear()
    # Vertex colour is not consumed by this .rend and was absent from -ee.
    for attribute_name in ("Attribute",):
        attribute = mesh.attributes.get(attribute_name)
        if attribute is not None:
            mesh.attributes.remove(attribute)
    mesh.update(calc_edges=True)
    return mesh


def main():
    if not os.path.isfile(BLEND):
        raise RuntimeError("Missing Blender source: " + BLEND)

    bpy.ops.wm.open_mainfile(filepath=BLEND)
    bpy.context.scene.frame_set(1)
    source = {obj.name: obj for obj in bpy.context.scene.objects if obj.type == "MESH"}
    missing = [name for name in PIECES if name not in source]
    if missing:
        raise RuntimeError("Missing required mesh object(s): " + ", ".join(missing))

    depsgraph = bpy.context.evaluated_depsgraph_get()
    baked = [(name, evaluated_mesh_copy(source[name], depsgraph)) for name in PIECES]
    minimum, maximum = mesh_bounds([mesh for _, mesh in baked])
    size = maximum - minimum
    center = (minimum + maximum) * 0.5

    # Scrap Mechanic's shape origin is the center of its collision box.
    translation = Matrix.Translation(-center)
    for _, mesh in baked:
        mesh.transform(translation)
        mesh.update(calc_edges=True)
    centered_minimum, centered_maximum = mesh_bounds([mesh for _, mesh in baked])
    centered_center = (centered_minimum + centered_maximum) * 0.5

    # Guard against exporting a wrong file, wrong frame, or wrong scale.
    expected = Vector((6.56, 4.0, 5.0))  # Blender X width 1.64m, Y depth, Z height.
    for axis in range(3):
        if abs(size[axis] - expected[axis]) > 0.25:
            raise RuntimeError("Unexpected SM-block dimensions: " + str(rounded(size)))
    if centered_center.length > 0.0001:
        raise RuntimeError("Centering failed: " + str(rounded(centered_center, 6)))

    # Delete only from this temporary process. The source .blend is never saved.
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    exported = []
    piece_meta = []
    for name, mesh in baked:
        # One unique material per piece. Joining these objects below converts
        # them into five material partitions without changing any source face.
        material = bpy.data.materials.new(name)
        mesh.materials.append(material)
        for polygon in mesh.polygons:
            polygon.material_index = 0
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.select_set(True)
        exported.append(obj)
        piece_meta.append({
            "name": name,
            "vertices": len(mesh.vertices),
            "polygons": len(mesh.polygons),
            "uv_layers": [layer.name for layer in mesh.uv_layers],
            "submesh_material": name,
        })

    # Known-visible 0854-ee is one FBX geometry with five material partitions.
    # Blender's join operation concatenates mesh datablocks; it does not alter
    # individual polygon definitions. Make the body active to retain its name.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in exported:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = exported[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = "craftingstation_body"
    joined.data.name = "craftingstation_body_mesh"
    exported = [joined]

    if len(joined.data.vertices) != 1519 or len(joined.data.polygons) != 1046:
        raise RuntimeError(
            "Join changed expected topology: vertices=%d polygons=%d"
            % (len(joined.data.vertices), len(joined.data.polygons))
        )
    if [material.name for material in joined.data.materials] != list(PIECES):
        raise RuntimeError(
            "Incorrect submesh partitions: "
            + repr([material.name for material in joined.data.materials])
        )

    os.makedirs(os.path.dirname(OUT_MESH), exist_ok=True)
    options = dict(
        filepath=OUT_MESH,
        use_selection=True,
        object_types={"MESH"},
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=True,
        use_mesh_modifiers=False,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        path_mode="STRIP",
        embed_textures=False,
    )
    # Do not triangulate: known-visible -ee preserves the source's 1,046 faces.
    bpy.ops.export_scene.fbx(use_triangles=False, **options)

    metadata = {
        "blend": BLEND,
        "fbx": OUT_MESH,
        "metres_to_sm_blocks": METRES_TO_BLOCKS,
        "fbx_axes": {"forward": "-Z", "up": "Y"},
        "centered": True,
        "mesh_offset": [0.0, 0.0, 0.0],
        "source_bounds_blocks": {
            "minimum": rounded(minimum),
            "maximum": rounded(maximum),
            "center_removed": rounded(center),
        },
        "centered_bounds_blocks": {
            "minimum": rounded(centered_minimum),
            "maximum": rounded(centered_maximum),
        },
        "size_sm_blocks": {
            "x_width": round(size.x, 4),
            "y_height": round(size.z, 4),
            "z_depth": round(size.y, 4),
        },
        "pieces": piece_meta,
        "materials_from_rend": True,
        "source_faces_modified": False,
        "known_visible_structure": {
            "geometry_objects": 1,
            "vertices": 1519,
            "polygons": 1046,
            "submesh_partitions": list(PIECES),
        },
    }
    with open(META, "w", encoding="utf-8") as stream:
        json.dump(metadata, stream, indent=2)
        stream.write("\n")
    print("RFS_RTI_EXPORT_OK", json.dumps(metadata, sort_keys=True))


if __name__ == "__main__":
    main()

