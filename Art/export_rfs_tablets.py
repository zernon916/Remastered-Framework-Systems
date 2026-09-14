# Export tablet nameplate blends to SM tool FBX + solid-color textures.
# Blender 5.2: blender --background --python Art/export_rfs_tablets.py
import json
import os
import struct

import bpy
from mathutils import Matrix, Vector

ROOT = r"C:\Coding Projects\RemasteredFrameworkSystems"
WIP = r"C:\Coding Projects\models\WIP Models"
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
METRES_TO_BLOCKS = 4.0

JOBS = (
    {
        "blend": os.path.join(WIP, "mobile_crafting_tablet_nameplate_test.blend"),
        "stem": "rfs_mobile_crafting_tablet",
    },
    {
        "blend": os.path.join(WIP, "farmers_tablet_nameplate_test.blend"),
        "stem": "rfs_farmers_tablet",
    },
)

OUT_TOOLS = os.path.join(ROOT, "Tools")
OUT_TEX = os.path.join(ROOT, "Objects", "Textures", "tablets")
OUT_ART = os.path.join(ROOT, "Art")


def rounded(vector, digits=4):
    return [round(float(value), digits) for value in vector]


def write_tga(path, rgb):
    # Match pack shared TGAs: 16x16 uncompressed truecolor + alpha.
    r, g, b = [max(0, min(255, int(c * 255 + 0.5))) for c in rgb]
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0, 0, 2, 0, 0, 0, 0, 0, 16, 16, 32, 8,
    )
    pixel = bytes((b, g, r, 255))
    with open(path, "wb") as fh:
        fh.write(header)
        fh.write(pixel * (16 * 16))


def material_rgb(material):
    if material is None:
        return (0.2, 0.2, 0.2)
    if material.use_nodes and material.node_tree:
        for node in material.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                col = node.inputs["Base Color"].default_value
                return (float(col[0]), float(col[1]), float(col[2]))
    col = material.diffuse_color
    return (float(col[0]), float(col[1]), float(col[2]))


def safe_mat_name(name, used):
    cleaned = "".join(ch if ch.isalnum() else "_" for ch in (name or "mat"))
    cleaned = cleaned.strip("_") or "mat"
    if cleaned[0].isdigit():
        cleaned = "m_" + cleaned
    base = cleaned
    n = 2
    while cleaned in used:
        cleaned = "%s_%d" % (base, n)
        n += 1
    used.add(cleaned)
    return cleaned


def convert_fonts():
    for obj in list(bpy.data.objects):
        if obj.type == "FONT":
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            bpy.ops.object.convert(target="MESH")


def bake_mesh(obj, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    temporary = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    if temporary is None:
        raise RuntimeError("Could not evaluate " + obj.name)
    try:
        mesh = temporary.copy()
    finally:
        evaluated.to_mesh_clear()
    mesh.transform(obj.matrix_world)
    mesh.transform(Matrix.Scale(METRES_TO_BLOCKS, 4))
    mesh.name = obj.name
    mesh.update(calc_edges=True)
    return mesh


def export_job(job):
    blend = job["blend"]
    stem = job["stem"]
    if not os.path.isfile(blend):
        raise RuntimeError("Missing blend: " + blend)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.open_mainfile(filepath=blend)
    convert_fonts()
    depsgraph = bpy.context.evaluated_depsgraph_get()

    sources = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not sources:
        raise RuntimeError("No mesh in " + blend)

    baked = []
    for obj in sources:
        src_mat = obj.data.materials[0] if obj.data.materials else None
        baked.append((material_rgb(src_mat), src_mat.name if src_mat else obj.name, bake_mesh(obj, depsgraph)))

    points = [v.co for _, _, mesh in baked for v in mesh.vertices]
    minimum = Vector(tuple(min(p[axis] for p in points) for axis in range(3)))
    maximum = Vector(tuple(max(p[axis] for p in points) for axis in range(3)))
    center = (minimum + maximum) * 0.5
    size = maximum - minimum
    for _, _, mesh in baked:
        mesh.transform(Matrix.Translation(-center))
        mesh.update(calc_edges=True)

    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    used = set()
    color_to_name = {}
    materials_meta = []
    exported = []
    for rgb, src_name, mesh in baked:
        color_key = tuple(round(c, 3) for c in rgb)
        if color_key in color_to_name:
            mat_name = color_to_name[color_key]
        else:
            mat_name = safe_mat_name(src_name, used)
            color_to_name[color_key] = mat_name
            tex_name = mat_name + ".tga"
            write_tga(os.path.join(OUT_TEX, tex_name), rgb)
            materials_meta.append({
                "name": mat_name,
                "rgb": [round(c, 4) for c in rgb],
                "texture": tex_name,
            })
        material = bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name)
        mesh.materials.clear()
        mesh.materials.append(material)
        for polygon in mesh.polygons:
            polygon.material_index = 0
        if not mesh.uv_layers:
            mesh.uv_layers.new(name="UVMap")
        new_obj = bpy.data.objects.new(mat_name, mesh)
        bpy.context.scene.collection.objects.link(new_obj)
        exported.append(new_obj)

    for obj in exported:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=1.15192, island_margin=0.02)
        bpy.ops.object.mode_set(mode="OBJECT")

    bpy.ops.object.select_all(action="DESELECT")
    for obj in exported:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = exported[0]
    if len(exported) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = stem
    joined.data.name = stem + "_mesh"

    fbx = os.path.join(OUT_TOOLS, stem + ".fbx")
    bpy.ops.export_scene.fbx(
        filepath=fbx,
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
        use_triangles=False,
    )

    rend = {
        "_comment": stem + " from WIP nameplate blend. Solid-color DifAsgNor.",
        "lodList": [
            {
                "mesh": PREFIX + "/Tools/" + stem + ".fbx",
                "maxViewDistance": 1000.0,
                "subMeshMap": {},
            }
        ],
    }
    for row in materials_meta:
        rend["lodList"][0]["subMeshMap"][row["name"]] = {
            "material": "DifAsgNor",
            "textureList": [
                PREFIX + "/Objects/Textures/tablets/" + row["texture"],
                PREFIX + "/Objects/Textures/shared/rfs_asg_paint.tga",
                PREFIX + "/Objects/Textures/shared/rfs_nor.tga",
            ],
        }
    rend_path = os.path.join(OUT_TOOLS, stem + ".rend")
    with open(rend_path, "w", encoding="utf-8") as fh:
        json.dump(rend, fh, indent="\t")
        fh.write("\n")

    meta = {
        "blend": blend,
        "fbx": fbx,
        "rend": rend_path,
        "size_blocks": rounded(size),
        "materials": materials_meta,
        "vertices": len(joined.data.vertices),
        "polygons": len(joined.data.polygons),
    }
    with open(os.path.join(OUT_ART, "sm_export_" + stem + "_meta.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)
    print("EXPORTED", stem, "size", rounded(size), "mats", len(materials_meta))


def main():
    os.makedirs(OUT_TOOLS, exist_ok=True)
    os.makedirs(OUT_TEX, exist_ok=True)
    for job in JOBS:
        export_job(job)


if __name__ == "__main__":
    main()
