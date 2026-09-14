# Build skinned eat-tool held DAEs for tablets + radio.
# Blender 5.2: blender --background --python Art/export_rfs_held_tools.py
# Engine ignores FBX skinning; GPS / Eat.lua need Collada + root_item weights.
import json
import math
import os
import struct
import zlib

import bpy
from mathutils import Matrix, Vector

ROOT = r"C:\Coding Projects\RemasteredFrameworkSystems"
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
OUT_OBJ = os.path.join(ROOT, "Objects")
OUT_TOOLS = os.path.join(ROOT, "Tools")
OUT_ART = os.path.join(ROOT, "Art")
TEX_TAB = os.path.join(ROOT, "Objects", "Textures", "tablets")

# GPS-sized first-person hold. TP matches SpikeHand's accepted GPS offset.
FP_MAX = 1.45
TP_SCALE = 0.75
TP_OFFSET = Vector((-0.393, 0.078, -0.014))


def write_png(path, rgb):
    r, g, b = [max(0, min(255, int(c * 255 + 0.5))) for c in rgb]
    w = h = 16
    raw = b"".join(b"\x00" + bytes((r, g, b)) * w for _ in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def tga_to_rgb(path):
    with open(path, "rb") as fh:
        header = fh.read(18)
        w, h, bpp = struct.unpack_from("<HHB", header, 12)
        px = fh.read(w * h * (bpp // 8))
    if bpp == 32:
        return (px[2] / 255.0, px[1] / 255.0, px[0] / 255.0)
    if bpp == 24:
        return (px[2] / 255.0, px[1] / 255.0, px[0] / 255.0)
    return (0.4, 0.4, 0.4)


def fmt_floats(values):
    return " ".join("%.6f" % float(v) for v in values)


def write_held_dae(path, stem, materials, positions, normals, uvs, triangles):
    nvert = len(positions) // 3
    weights = " ".join("1" for _ in range(nvert))
    vcount = " ".join("1" for _ in range(nvert))
    vpairs = " ".join("0 %d" % i for i in range(nvert))
    mat_xml = []
    fx_xml = []
    img_xml = []
    tri_xml = []
    bind_xml = []
    for mat in materials:
        name = mat["name"]
        img = mat.get("image") or (name + ".png")
        img_xml.append(
            '  <image id="%s-image" name="%s"><init_from>%s</init_from></image>' % (name, name, img)
        )
        mat_xml.append(
            '  <material id="%s" name="%s"><instance_effect url="#%s-fx"/></material>' % (name, name, name)
        )
        fx_xml.append(
            '  <effect id="%s-fx" name="%s"><profile_COMMON><technique sid="standard"><lambert>'
            '<emission><color sid="emission">0 0 0 1</color></emission>'
            '<ambient><color sid="ambient">0 0 0 1</color></ambient>'
            '<diffuse><texture texture="%s-image" texcoord="CHANNEL0"/></diffuse>'
            "</lambert></technique></profile_COMMON></effect>" % (name, name, name)
        )
        bind_xml.append('<instance_material symbol="%s" target="#%s"/>' % (name, name))
        idxs = triangles[name]
        p = " ".join(str(i) for i in idxs)
        count = len(idxs) // 9
        tri_xml.append(
            '<triangles count="%d" material="%s">'
            '<input semantic="VERTEX" offset="0" source="#%s-VERTEX"/>'
            '<input semantic="NORMAL" offset="1" source="#%s-Normal0"/>'
            '<input semantic="TEXCOORD" offset="2" set="0" source="#%s-UV0"/>'
            "<p>%s</p></triangles>" % (count, name, stem, stem, stem, p)
        )

    xml = []
    xml.append('<?xml version="1.0" encoding="utf-8"?>')
    xml.append('<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">')
    xml.append(
        "<asset><contributor><authoring_tool>rfs export_rfs_held_tools.py</authoring_tool></contributor>"
        '<unit meter="0.010000" name="centimeter"></unit><up_axis>Y_UP</up_axis></asset>'
    )
    xml.append("<library_images>")
    xml.extend(img_xml)
    xml.append("</library_images>")
    xml.append("<library_materials>")
    xml.extend(mat_xml)
    xml.append("</library_materials>")
    xml.append("<library_effects>")
    xml.extend(fx_xml)
    xml.append("</library_effects>")
    xml.append("<library_geometries>")
    xml.append('  <geometry id="%s-lib" name="%s">' % (stem, stem))
    xml.append("    <mesh>")
    xml.append(
        '      <source id="%s-POSITION"><float_array id="%s-POSITION-array" count="%d">%s</float_array>'
        '<technique_common><accessor source="#%s-POSITION-array" count="%d" stride="3">'
        '<param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/>'
        "</accessor></technique_common></source>"
        % (stem, stem, len(positions), fmt_floats(positions), stem, nvert)
    )
    xml.append(
        '      <source id="%s-Normal0"><float_array id="%s-Normal0-array" count="%d">%s</float_array>'
        '<technique_common><accessor source="#%s-Normal0-array" count="%d" stride="3">'
        '<param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/>'
        "</accessor></technique_common></source>"
        % (stem, stem, len(normals), fmt_floats(normals), stem, len(normals) // 3)
    )
    xml.append(
        '      <source id="%s-UV0"><float_array id="%s-UV0-array" count="%d">%s</float_array>'
        '<technique_common><accessor source="#%s-UV0-array" count="%d" stride="2">'
        '<param name="S" type="float"/><param name="T" type="float"/>'
        "</accessor></technique_common></source>"
        % (stem, stem, len(uvs), fmt_floats(uvs), stem, len(uvs) // 2)
    )
    xml.append(
        '      <vertices id="%s-VERTEX"><input semantic="POSITION" source="#%s-POSITION"/></vertices>'
        % (stem, stem)
    )
    xml.extend("      " + row for row in tri_xml)
    xml.append("    </mesh>")
    xml.append("  </geometry>")
    xml.append("</library_geometries>")
    xml.append("<library_controllers>")
    xml.append('  <controller id="%sController"><skin source="#%s-lib">' % (stem, stem))
    xml.append("    <bind_shape_matrix>1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1</bind_shape_matrix>")
    xml.append(
        '    <source id="%sController-Joints"><Name_array id="%sController-Joints-array" count="1">root_item</Name_array>'
        '<technique_common><accessor source="#%sController-Joints-array" count="1"><param type="name"/></accessor></technique_common></source>'
        % (stem, stem, stem)
    )
    xml.append(
        '    <source id="%sController-Matrices"><float_array id="%sController-Matrices-array" count="16">1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1</float_array>'
        '<technique_common><accessor source="#%sController-Matrices-array" count="1" stride="16"><param type="float4x4"/></accessor></technique_common></source>'
        % (stem, stem, stem)
    )
    xml.append(
        '    <source id="%sController-Weights"><float_array id="%sController-Weights-array" count="%d">%s</float_array>'
        '<technique_common><accessor source="#%sController-Weights-array" count="%d"><param type="float"/></accessor></technique_common></source>'
        % (stem, stem, nvert, weights, stem, nvert)
    )
    xml.append(
        "    <joints><input semantic=\"JOINT\" source=\"#%sController-Joints\"/>"
        "<input semantic=\"INV_BIND_MATRIX\" source=\"#%sController-Matrices\"/></joints>" % (stem, stem)
    )
    xml.append(
        '    <vertex_weights count="%d"><input semantic="JOINT" offset="0" source="#%sController-Joints"/>'
        '<input semantic="WEIGHT" offset="1" source="#%sController-Weights"/>'
        "<vcount>%s</vcount><v>%s</v></vertex_weights>" % (nvert, stem, stem, vcount, vpairs)
    )
    xml.append("  </skin></controller>")
    xml.append("</library_controllers>")
    xml.append("<library_visual_scenes>")
    xml.append('  <visual_scene id="%s" name="%s">' % (stem, stem))
    xml.append(
        '    <node name="%s" id="%s" sid="%s"><instance_controller url="#%sController">'
        "<bind_material><technique_common>%s</technique_common></bind_material></instance_controller></node>"
        % (stem, stem, stem, stem, "".join(bind_xml))
    )
    xml.append(
        '    <node name="jnt_right_weapon" id="jnt_right_weapon" sid="jnt_right_weapon" type="JOINT">'
        '<matrix sid="matrix">1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1</matrix>'
        '<node name="root_item" id="root_item" sid="root_item" type="JOINT">'
        '<matrix sid="matrix">1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1</matrix></node></node>'
    )
    xml.append("  </visual_scene>")
    xml.append("</library_visual_scenes>")
    xml.append('<scene><instance_visual_scene url="#%s"/></scene>' % stem)
    xml.append("</COLLADA>")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(xml))
        fh.write("\n")


def gather_mesh(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    try:
        mesh.calc_normals_split()
    except Exception:
        pass
    uv_layer = mesh.uv_layers.active
    positions = []
    for vertex in mesh.vertices:
        positions.extend((vertex.co.x, vertex.co.y, vertex.co.z))
    normals = []
    uvs = []
    triangles = {}
    nloop = 0
    for tri in mesh.loop_triangles:
        mat = mesh.materials[tri.material_index] if mesh.materials else None
        name = mat.name if mat else "mat"
        bucket = triangles.setdefault(name, [])
        for i, loop_index in enumerate(tri.loops):
            loop = mesh.loops[loop_index]
            nrm = loop.normal
            normals.extend((nrm.x, nrm.y, nrm.z))
            if uv_layer:
                uv = uv_layer.data[loop_index].uv
                uvs.extend((uv.x, uv.y))
            else:
                uvs.extend((0.0, 0.0))
            bucket.extend((tri.vertices[i], nloop, nloop))
            nloop += 1
    materials = []
    seen = set()
    for mat in mesh.materials:
        if mat and mat.name not in seen:
            seen.add(mat.name)
            materials.append({"name": mat.name})
    if not materials:
        materials = [{"name": "mat"}]
        triangles.setdefault("mat", [])
    return materials, positions, normals, uvs, triangles


def import_fbx(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("No mesh in " + path)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def pose_mesh(obj, tp):
    mesh = obj.data
    points = [v.co.copy() for v in mesh.vertices]
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    center = (minimum + maximum) * 0.5
    size = maximum - minimum
    longest = max(size.x, size.y, size.z, 0.001)
    scale = FP_MAX / longest
    # Thin axis (X on the tablet export) toward the camera so the screen faces the player.
    rot = Matrix.Rotation(math.radians(90.0), 4, "Y") @ Matrix.Rotation(math.radians(-10.0), 4, "X")
    xform = rot @ Matrix.Scale(scale, 4) @ Matrix.Translation(-center)
    if tp:
        xform = Matrix.Translation(TP_OFFSET) @ Matrix.Scale(TP_SCALE, 4) @ xform
    mesh.transform(xform)
    mesh.update(calc_edges=True)
    return size, scale


def write_rend(path, comment, mesh_rel, submeshes):
    rend = {
        "_comment": comment,
        "lodList": [
            {
                "mesh": PREFIX + mesh_rel,
                "maxViewDistance": 1000.0,
                "subMeshMap": submeshes,
            }
        ],
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(rend, fh, indent="\t")
        fh.write("\n")


def tablet_job(stem):
    fbx = os.path.join(OUT_TOOLS, stem + ".fbx")
    obj = import_fbx(fbx)
    # Preview PNGs from the solid TGA already used by the inventory rend.
    preview_map = {}
    for mat in obj.data.materials:
        if not mat:
            continue
        tga = os.path.join(TEX_TAB, mat.name + ".tga")
        png = os.path.join(TEX_TAB, mat.name + ".png")
        rgb = tga_to_rgb(tga) if os.path.isfile(tga) else (0.3, 0.3, 0.3)
        write_png(png, rgb)
        preview_map[mat.name] = {
            "material": "DifAsgNor",
            "textureList": [
                PREFIX + "/Objects/Textures/tablets/" + mat.name + ".png",
                PREFIX + "/Objects/Textures/shared/rfs_asg_paint.tga",
                PREFIX + "/Objects/Textures/shared/rfs_nor.tga",
            ],
        }
    write_rend(
        os.path.join(OUT_TOOLS, stem + "_preview_v1.rend"),
        stem + " hotbar preview (PNG + FBX, cache-bust v1).",
        "/Tools/" + stem + ".fbx",
        preview_map,
    )

    held_map = {}
    for name, row in preview_map.items():
        held_map[name] = {
            "material": "DifAsgNor",
            "textureList": list(row["textureList"]),
        }

    for suffix, tp in (("_held_v1", False), ("_held_tp_v1", True)):
        posed = import_fbx(fbx)
        size, scale = pose_mesh(posed, tp)
        materials, positions, normals, uvs, triangles = gather_mesh(posed)
        dae_name = stem + suffix + ".dae"
        write_held_dae(
            os.path.join(OUT_OBJ, dae_name),
            stem + suffix,
            [{"name": m["name"], "image": m["name"] + ".png"} for m in materials],
            positions,
            normals,
            uvs,
            triangles,
        )
        write_rend(
            os.path.join(OUT_TOOLS, stem + suffix + ".rend"),
            stem + " eat-tool held mesh " + suffix + ". Bump suffix if the mesh changes.",
            "/Objects/" + dae_name,
            held_map,
        )
        print("HELD", stem + suffix, "verts", len(positions) // 3, "srcSize", [round(c, 4) for c in size], "fpScale", round(scale, 4))


def radio_job():
    stem = "rfs_radio_handheld"
    fbx = os.path.join(OUT_TOOLS, stem + ".fbx")
    if not os.path.isfile(fbx):
        print("SKIP radio, missing", fbx)
        return
    tex = {
        "military_comm_set": {
            "material": "DifAsgNor",
            "textureList": [
                PREFIX + "/Objects/Textures/radio/fbx_kit/Military_communication_D.dds",
                PREFIX + "/Objects/Textures/shared/rfs_asg_paint.tga",
                PREFIX + "/Objects/Textures/radio/fbx_kit/Military_communication_N.dds",
            ],
        }
    }
    for suffix, tp in (("_held_v1", False), ("_held_tp_v1", True)):
        posed = import_fbx(fbx)
        size, scale = pose_mesh(posed, tp)
        materials, positions, normals, uvs, triangles = gather_mesh(posed)
        # Keep the kit material name the rend already uses.
        if materials and materials[0]["name"] != "military_comm_set":
            old = materials[0]["name"]
            if old in triangles:
                triangles["military_comm_set"] = triangles.pop(old)
            materials[0]["name"] = "military_comm_set"
        dae_name = stem + suffix + ".dae"
        write_held_dae(
            os.path.join(OUT_OBJ, dae_name),
            stem + suffix,
            [{"name": "military_comm_set", "image": "Military_communication_D.dds"}],
            positions,
            normals,
            uvs,
            triangles,
        )
        write_rend(
            os.path.join(OUT_TOOLS, stem + suffix + ".rend"),
            "handheld radio eat-tool held mesh " + suffix,
            "/Objects/" + dae_name,
            tex,
        )
        print("HELD radio", suffix, "verts", len(positions) // 3, "srcSize", [round(c, 4) for c in size], "fpScale", round(scale, 4))


def main():
    os.makedirs(OUT_OBJ, exist_ok=True)
    tablet_job("rfs_mobile_crafting_tablet")
    tablet_job("rfs_farmers_tablet")
    radio_job()
    print("DONE held exports")


if __name__ == "__main__":
    main()
