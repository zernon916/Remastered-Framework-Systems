# Blender 4.4: studio render of the in-game Colba (Helley) for Craftbot/inventory.
# Same scale/sit as export_rfs_colba_v9 so the icon matches the placed mesh.
# Run: blender --background --python Art/render_rfs_colba_icon.py
import bpy
import math
import mathutils
import os

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
GLB = os.path.join(ROOT, "Art", "sketchfab_colba", "source", "the_science_fiction_colba.glb")
OUT_SRC = os.path.join(ROOT, "Art", "icon_deepsleep_src.png")
TARGET_GLASS_H_M = 2.75
MAT_RENAME = {
    "colb_down": "down",
    "colb_up": "up",
    "colb_colba": "glass",
    "colb_decals": "decals",
}


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
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def apply_tr(objs):
    if not objs:
        return
    select_meshes(objs)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def clear_parents_keep():
    objs = mesh_objects()
    select_meshes(objs)
    try:
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    except Exception:
        pass


def rename_materials(objs):
    for o in objs:
        if not o.data:
            continue
        for mat in o.data.materials:
            if not mat:
                continue
            base = mat.name.split(".")[0]
            new = MAT_RENAME.get(mat.name, MAT_RENAME.get(base, mat.name))
            mat.name = new


def join_by_material(objs):
    buckets = {}
    for o in objs:
        mname = "down"
        if o.data and o.data.materials and o.data.materials[0]:
            mname = o.data.materials[0].name
        buckets.setdefault(mname, []).append(o)
    joined = []
    for mname, group in buckets.items():
        select_meshes(group)
        if len(group) > 1:
            bpy.ops.object.join()
        body = bpy.context.view_layer.objects.active
        body.name = mname
        if body.data:
            body.data.name = mname
        joined.append(body)
    return joined


def principled(mat):
    if not mat or not mat.use_nodes:
        return None
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    return None


def set_sock(node, name, value):
    sock = node.inputs.get(name)
    if sock is not None:
        sock.default_value = value


def tune_glass(mat):
    n = principled(mat)
    if not n:
        return
    # Read at 96px: slight cyan glass, not invisible.
    set_sock(n, "Base Color", (0.62, 0.90, 0.98, 1.0))
    set_sock(n, "Metallic", 0.05)
    set_sock(n, "Roughness", 0.06)
    set_sock(n, "IOR", 1.45)
    if "Transmission Weight" in n.inputs:
        set_sock(n, "Transmission Weight", 0.82)
    elif "Transmission" in n.inputs:
        set_sock(n, "Transmission", 0.82)
    if "Alpha" in n.inputs:
        set_sock(n, "Alpha", 0.42)
    mat.blend_method = "HASHED"
    if hasattr(mat, "shadow_method"):
        mat.shadow_method = "HASHED"
    mat.use_screen_refraction = True


def add_fill(glass):
    gmins, gmaxs = world_bounds([glass])
    gsize = gmaxs - gmins
    gcenter = (gmins + gmaxs) * 0.5
    fill_r = min(gsize.x, gsize.y) * 0.42
    fill_h = max(gsize.z * 0.82, 1.2)
    fill_z0 = gmins.z + (gsize.z - fill_h) * 0.08
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=24,
        radius=fill_r,
        depth=fill_h,
        location=(gcenter.x, gcenter.y, fill_z0 + fill_h * 0.5),
    )
    fill = bpy.context.view_layer.objects.active
    fill.name = "chemfill"
    mat = bpy.data.materials.new("chemfill")
    mat.use_nodes = True
    n = principled(mat)
    # In-game fill ~7a28c8 / chemfill_dif purple.
    col = (0.48, 0.16, 0.78, 1.0)
    set_sock(n, "Base Color", col)
    set_sock(n, "Roughness", 0.22)
    if "Transmission Weight" in n.inputs:
        set_sock(n, "Transmission Weight", 0.35)
    if n.inputs.get("Emission Color"):
        n.inputs["Emission Color"].default_value = col
    if n.inputs.get("Emission Strength"):
        n.inputs["Emission Strength"].default_value = 3.6
    elif n.inputs.get("Emission"):
        n.inputs["Emission"].default_value = (0.48, 0.16, 0.78, 1.0)
    fill.data.materials.append(mat)
    return fill


def add_area(name, loc, energy, size, color=(1.0, 0.98, 0.94)):
    bpy.ops.object.light_add(type="AREA", location=loc)
    lit = bpy.context.view_layer.objects.active
    lit.name = name
    lit.data.energy = energy
    lit.data.size = size
    lit.data.color = color
    return lit


def look_at(obj, target):
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def setup_render(scene):
    scene.render.engine = "CYCLES"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = OUT_SRC
    scene.render.use_file_extension = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.15
    scene.view_settings.gamma = 1.0
    cycles = scene.cycles
    cycles.samples = 96
    cycles.use_denoising = True
    try:
        cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    prefs = bpy.context.preferences.addons.get("cycles")
    if prefs:
        cprefs = prefs.preferences
        try:
            cprefs.compute_device_type = "CUDA"
            cprefs.get_devices()
            any_gpu = False
            for dev in cprefs.devices:
                use = dev.type != "CPU"
                dev.use = use
                any_gpu = any_gpu or use
            if any_gpu:
                cycles.device = "GPU"
        except Exception:
            cycles.device = "CPU"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("icon_world")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.018, 0.022, 0.028, 1.0)
        bg.inputs[1].default_value = 1.0


def main():
    if not os.path.isfile(GLB):
        raise SystemExit("missing glb: " + GLB)
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=GLB)
    clear_parents_keep()
    objs = mesh_objects()
    apply_tr(objs)
    objs = mesh_objects()
    rename_materials(objs)
    parts = join_by_material(objs)
    apply_tr(parts)
    print("PARTS", [(o.name, [m.name for m in (o.data.materials or []) if m]) for o in parts])

    glass = down = None
    for o in parts:
        if o.name == "glass":
            glass = o
        if o.name == "down":
            down = o
        mat = o.data.materials[0] if o.data and o.data.materials else None
        if mat and o.name in ("glass",) or (mat and "glass" in mat.name.lower()):
            tune_glass(mat)
            mat.blend_method = "HASHED"

    gmins, gmaxs = world_bounds([glass] if glass else parts)
    gsize = gmaxs - gmins
    s = TARGET_GLASS_H_M / max(gsize.z, 1e-6)
    for o in parts:
        o.scale = (s, s, s)
    apply_tr(parts)

    dmins, dmaxs = world_bounds([down] if down else parts)
    omins, omaxs = world_bounds(parts)
    base_z = dmins.z
    cx = (omins.x + omaxs.x) * 0.5
    cy = (omins.y + omaxs.y) * 0.5
    for o in parts:
        o.location.x -= cx
        o.location.y -= cy
        o.location.z -= base_z
    apply_tr(parts)

    glass = down = None
    for o in parts:
        if o.name == "glass":
            glass = o
        if o.name == "down":
            down = o
    fill = add_fill(glass if glass else parts[0])

    # Frame glass + circular base + upper grippers (ignore dangling AABB below plate).
    frame = [o for o in parts if o.name in ("glass", "down", "up", "decals")]
    if not frame:
        frame = list(parts)
    frame.append(fill)
    mins, maxs = world_bounds(frame)
    center = (mins + maxs) * 0.5
    size = maxs - mins
    radius = size.length * 0.5

    setup_render(bpy.context.scene)

    cam_data = bpy.data.cameras.new("icon_cam")
    cam_data.lens = 50
    cam_data.clip_start = 0.05
    cam_data.clip_end = 80.0
    cam = bpy.data.objects.new("icon_cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    yaw = math.radians(44)
    pitch = math.radians(18)
    dist = max(size.x, size.y, size.z) * 1.88
    cam.location = center + mathutils.Vector(
        (
            math.cos(pitch) * math.sin(yaw) * dist,
            -math.cos(pitch) * math.cos(yaw) * dist,
            math.sin(pitch) * dist + size.z * 0.08,
        )
    )
    look_at(cam, center + mathutils.Vector((0.0, 0.0, size.z * 0.02)))

    key = add_area(
        "key",
        cam.location + mathutils.Vector((1.6, 0.4, 2.2)),
        energy=900,
        size=3.2,
        color=(1.0, 0.98, 0.94),
    )
    look_at(key, center)
    fill_l = add_area(
        "fill",
        center + mathutils.Vector((-3.4, -1.2, 1.6)),
        energy=280,
        size=4.0,
        color=(0.82, 0.90, 1.0),
    )
    look_at(fill_l, center)
    rim = add_area(
        "rim",
        center + mathutils.Vector((-0.4, 3.6, 2.4)),
        energy=420,
        size=2.4,
        color=(0.95, 0.98, 1.0),
    )
    look_at(rim, center)

    bpy.ops.render.render(write_still=True)
    print("WROTE", OUT_SRC, "radius", float(radius), "size", [float(size.x), float(size.y), float(size.z)])


if __name__ == "__main__":
    main()
