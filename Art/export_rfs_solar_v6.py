# Blender 4.x: HexaRay solar ONLY -> rfs_solar_v6.
# Merges Solar Mirror overlay into one opaque solar_cells material.
# Re-UVs each wing overlay to fill 0-1 on solar_cells_dif.png (4x6 cells).
# Does NOT export deepsleep. Placement: same scale/center as v5 (sticky -Y).
# Run: blender --background --python Art/export_rfs_solar_v6.py
import bpy
import os
import json
import mathutils

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh")
OUT_TEX = os.path.join(ROOT, "Objects", "Textures")
OUT_REND = os.path.join(ROOT, "Objects", "Renderable")
LID = "29c99287-1213-48c7-9471-19a4a5c12247"
PREFIX = "$CONTENT_" + LID
GLB = os.path.join(ROOT, "Art", "sketchfab_solar", "source", "HexaRay Node - For texturing.glb")
STEM = "rfs_solar_v6"
CELLS_PNG = os.path.join(OUT_TEX, "solar", "solar_cells_dif.png")
TARGET = (5.0, 5.0, 5.0)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def world_bounds(objs):
    mins = mathutils.Vector((1e9, 1e9, 1e9))
    maxs = mathutils.Vector((-1e9, -1e9, -1e9))
    any_ok = False
    for o in objs:
        for corner in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(corner)
            mins.x = min(mins.x, w.x)
            mins.y = min(mins.y, w.y)
            mins.z = min(mins.z, w.z)
            maxs.x = max(maxs.x, w.x)
            maxs.y = max(maxs.y, w.y)
            maxs.z = max(maxs.z, w.z)
            any_ok = True
    if not any_ok:
        return None, None
    return mins, maxs


def select_meshes(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def apply_tr(objs):
    select_meshes(objs)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def sanitize(name):
    out = []
    for ch in (name or "mesh"):
        if ch.isalnum():
            out.append(ch.lower())
        else:
            out.append("_")
    s = "".join(out).strip("_")
    while "__" in s:
        s = s.replace("__", "_")
    return s[:40] or "mesh"


def scale_and_center(objs, target):
    apply_tr(objs)
    mins, maxs = world_bounds(objs)
    if mins is None:
        return None
    size = maxs - mins
    tx, ty, tz = target
    s = min(tx / max(size.x, 1e-6), ty / max(size.z, 1e-6), tz / max(size.y, 1e-6))
    center = (mins + maxs) * 0.5
    for o in objs:
        o.scale = (s, s, s)
        o.location = o.location - center * s
    apply_tr(objs)
    mins2, maxs2 = world_bounds(objs)
    size2 = maxs2 - mins2
    return {
        "scale": s,
        "size_blender": [float(size2.x), float(size2.y), float(size2.z)],
        "size_sm": [float(size2.x), float(size2.z), float(size2.y)],
        "min": [float(mins2.x), float(mins2.y), float(mins2.z)],
        "max": [float(maxs2.x), float(maxs2.y), float(maxs2.z)],
    }


def find_bsdf(mat):
    if not mat or not mat.use_nodes:
        return None
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    return None


def linked_image(inp):
    if not inp or not inp.is_linked:
        return None
    node = inp.links[0].from_node
    if node.type == "TEX_IMAGE" and node.image:
        return node.image
    for sock in getattr(node, "inputs", []):
        if sock.is_linked:
            src = sock.links[0].from_node
            if src.type == "TEX_IMAGE" and src.image:
                return src.image
    return None


def albedo_from_material(mat):
    bsdf = find_bsdf(mat)
    if not bsdf:
        return None, [0.8, 0.8, 0.8, 1.0]
    img = linked_image(bsdf.inputs.get("Base Color"))
    if img:
        return img, None
    img = linked_image(bsdf.inputs.get("Emission Color"))
    if img:
        return img, None
    bc = bsdf.inputs.get("Base Color")
    col = [0.8, 0.8, 0.8, 1.0]
    if bc:
        col = [
            float(bc.default_value[0]),
            float(bc.default_value[1]),
            float(bc.default_value[2]),
            float(bc.default_value[3]),
        ]
    return None, col


def save_image_png(img, path, max_px=1024):
    copy = img.copy()
    w, h = int(copy.size[0]), int(copy.size[1])
    if w < 1 or h < 1:
        return False
    m = max(w, h)
    if m > max_px:
        s = max_px / float(m)
        nw = max(1, int(w * s))
        nh = max(1, int(h * s))
        copy.scale(nw, nh)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    copy.filepath_raw = path
    copy.file_format = "PNG"
    copy.save()
    return True


def linear_to_srgb(c):
    c = max(0.0, min(1.0, float(c)))
    if c <= 0.0031308:
        return 12.92 * c
    return 1.055 * (c ** (1.0 / 2.4)) - 0.055


def save_solid_png(color, path, px=16):
    img = bpy.data.images.new(os.path.basename(path), width=px, height=px)
    r = linear_to_srgb(color[0])
    g = linear_to_srgb(color[1])
    b = linear_to_srgb(color[2])
    a = color[3] if len(color) > 3 else 1.0
    img.pixels = [r, g, b, a] * (px * px)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def ensure_uv(obj):
    if not obj.data:
        return
    if obj.data.uv_layers:
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    try:
        bpy.ops.uv.smart_project(angle_limit=66.0, island_margin=0.02)
    except Exception:
        bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.001)
    bpy.ops.object.mode_set(mode="OBJECT")


def make_cells_material():
    mat = bpy.data.materials.new("solar_cells")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(CELLS_PNG)
    img.name = "solar_cells_dif.png"
    img.filepath = CELLS_PNG
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    spec = bsdf.inputs.get("Specular IOR Level") or bsdf.inputs.get("Specular")
    if spec:
        spec.default_value = 0.05
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = 0.0
    if "Roughness" in bsdf.inputs:
        bsdf.inputs["Roughness"].default_value = 1.0
    if "Transmission Weight" in bsdf.inputs:
        bsdf.inputs["Transmission Weight"].default_value = 0.0
    elif "Transmission" in bsdf.inputs:
        bsdf.inputs["Transmission"].default_value = 0.0
    return mat


def is_mirror_name(name):
    n = (name or "").lower()
    return "solar" in n and "mirror" in n


def remap_overlay_to_cells(objs, cells_mat):
    """Keep overlay geometry (the actual wing sheets). Re-UV each wing to 0-1."""
    import bmesh

    total_faces = 0
    for o in objs:
        mesh = o.data
        if not mesh:
            continue
        mirror_indices = []
        for i, mat in enumerate(mesh.materials):
            if mat and is_mirror_name(mat.name):
                mirror_indices.append(i)
        if not mirror_indices:
            continue
        if cells_mat.name not in [m.name for m in mesh.materials if m]:
            mesh.materials.append(cells_mat)
        cells_idx = None
        for i, mat in enumerate(mesh.materials):
            if mat and mat.name == cells_mat.name:
                cells_idx = i
                break
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.faces.ensure_lookup_table()
        uv_lay = bm.loops.layers.uv.verify()
        overlay = [f for f in bm.faces if f.material_index in mirror_indices]
        if not overlay:
            bm.free()
            continue
        # Split left/right wings by face centroid X.
        xs = [(f.calc_center_median().x, f) for f in overlay]
        mid = sum(x for x, _ in xs) / max(1, len(xs))
        groups = [[], []]
        for x, f in xs:
            groups[0 if x < mid else 1].append(f)
        pad = 0.04
        for group in groups:
            if not group:
                continue
            n = mathutils.Vector((0, 0, 0))
            for f in group:
                n += f.normal
            if n.length < 1e-6:
                n = mathutils.Vector((0, 0, 1))
            else:
                n.normalize()
            up = mathutils.Vector((0, 0, 1))
            if abs(n.dot(up)) > 0.9:
                up = mathutils.Vector((0, 1, 0))
            tangent = n.cross(up)
            if tangent.length < 1e-6:
                tangent = mathutils.Vector((1, 0, 0))
            tangent.normalize()
            bitangent = n.cross(tangent)
            bitangent.normalize()
            pts = []
            for f in group:
                for loop in f.loops:
                    p = loop.vert.co
                    pts.append((p.dot(tangent), p.dot(bitangent), loop))
            us = [p[0] for p in pts]
            vs = [p[1] for p in pts]
            umin, umax = min(us), max(us)
            vmin, vmax = min(vs), max(vs)
            du = max(umax - umin, 1e-6)
            dv = max(vmax - vmin, 1e-6)
            for u, v, loop in pts:
                loop[uv_lay].uv = (
                    pad + (u - umin) / du * (1.0 - 2 * pad),
                    pad + (v - vmin) / dv * (1.0 - 2 * pad),
                )
            for f in group:
                f.material_index = cells_idx
            total_faces += len(group)
        bm.to_mesh(mesh)
        bm.free()
        # Drop unused mirror slots (rebuild material list).
        used = set()
        for poly in mesh.polygons:
            used.add(poly.material_index)
        keep = []
        remap = {}
        for i, mat in enumerate(mesh.materials):
            if i in used and mat and not is_mirror_name(mat.name):
                remap[i] = len(keep)
                keep.append(mat)
            elif i in used and mat and is_mirror_name(mat.name):
                # should not happen after reassign
                remap[i] = len(keep)
                keep.append(mat)
        for poly in mesh.polygons:
            poly.material_index = remap.get(poly.material_index, 0)
        mesh.materials.clear()
        for mat in keep:
            mesh.materials.append(mat)
    print("remapped overlay faces", total_faces)
    return total_faces


def prepare_materials(objs):
    tex_dir = os.path.join(OUT_TEX, "solar")
    os.makedirs(tex_dir, exist_ok=True)
    seen = set()
    name_count = {}
    mapping = []
    for o in objs:
        if not o.data:
            continue
        for mat in list(o.data.materials):
            if not mat:
                continue
            mid = mat.as_pointer()
            if mid in seen:
                continue
            seen.add(mid)
            original = mat.name
            base = sanitize(original)
            n = name_count.get(base, 0)
            name_count[base] = n + 1
            mname = base if n == 0 else ("%s_%d" % (base, n + 1))
            mat.name = mname
            png = os.path.join(tex_dir, mname + "_dif.png")
            if os.path.isfile(png):
                mapping.append({"material": mname, "png": png, "from": original, "kept": True})
                continue
            img, col = albedo_from_material(mat)
            if img:
                ok = save_image_png(img, png)
                if not ok:
                    save_solid_png(col or [0.8, 0.8, 0.8, 1.0], png)
            else:
                save_solid_png(col or [0.8, 0.8, 0.8, 1.0], png)
            mapping.append({"material": mname, "png": png, "from": original})
    return mapping


def join_keep_materials(objs, name):
    select_meshes(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    if body.data:
        body.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")
    bpy.ops.object.mode_set(mode="OBJECT")
    return body


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


def export_dae(path):
    bpy.ops.wm.collada_export(
        filepath=path,
        apply_modifiers=True,
        selected=True,
        include_children=False,
        include_armatures=False,
        include_shapekeys=False,
        triangulate=True,
        use_object_instantiation=False,
        use_blender_profile=False,
        limit_precision=True,
        keep_bind_info=False,
    )


def content_path(abs_path):
    rel = os.path.relpath(abs_path, ROOT).replace("\\", "/")
    return PREFIX + "/" + rel


def write_rend(mat_map):
    asg = PREFIX + "/Objects/Textures/shared/rfs_asg.tga"
    nor = PREFIX + "/Objects/Textures/shared/rfs_nor.tga"
    cells_asg = PREFIX + "/Objects/Textures/solar/solar_cells_asg.tga"
    sub = {}
    for rec in mat_map:
        mname = rec["material"]
        use_asg = cells_asg if mname == "solar_cells" else asg
        sub[mname] = {
            "textureList": [content_path(rec["png"]), use_asg, nor],
            "material": "DifAsgNor",
        }
    data = {
        "_comment": "v6: overlay merged to opaque solar_cells, 4x6 UV fill, no glass ASG.",
        "lodList": [
            {
                "mesh": PREFIX + "/Objects/Mesh/" + STEM + ".fbx",
                "subMeshMap": sub,
                "maxViewDistance": 1000.0,
            }
        ],
    }
    out = os.path.join(OUT_REND, "rfs_solar.rend")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent="\t")
        f.write("\n")
    return out


def main():
    reset_scene()
    print("IMPORT", GLB, "exists", os.path.isfile(GLB))
    bpy.ops.import_scene.gltf(filepath=GLB)
    objs = mesh_objects()
    print("meshes", len(objs), [o.name for o in objs])
    meta = scale_and_center(objs, TARGET)
    objs = mesh_objects()
    for o in objs:
        ensure_uv(o)
    cells_mat = make_cells_material()
    nfaces = remap_overlay_to_cells(objs, cells_mat)
    if nfaces < 1:
        raise RuntimeError("no solar mirror overlay faces found")
    objs = mesh_objects()
    mat_map = prepare_materials(objs)
    objs = mesh_objects()
    body = join_keep_materials(objs, STEM)
    mats = [m.name for m in body.data.materials if m]
    if "solar_mirror_material" in mats or any("mirror" in m.lower() for m in mats):
        print("WARN still has mirror mats", mats)
    fbx = os.path.join(OUT_MESH, STEM + ".fbx")
    dae = os.path.join(OUT_MESH, STEM + ".dae")
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    export_fbx(fbx)
    export_dae(dae)
    rend = write_rend(mat_map)
    result = {
        "name": "solar",
        "fbx": fbx,
        "dae": dae,
        "rend": rend,
        "object": body.name,
        "materials": mats,
        "mat_map": mat_map,
        "meta": meta,
        "verts": len(body.data.vertices),
        "polys": len(body.data.polygons),
        "overlay_faces": nfaces,
    }
    out = os.path.join(ROOT, "Art", "sm_export_v6_solar_meta.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    print("DONE", json.dumps({k: result[k] for k in result if k != "mat_map"}, indent=2))
    print("WROTE", out)


if __name__ == "__main__":
    main()
