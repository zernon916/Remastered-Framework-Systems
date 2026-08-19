# Blender 4.4: Render object-specific 96x96 icons for RFS radio station parts.
#
# Outputs:
#   Art/icon_hackbeacon_96.png
#   Art/icon_radio_handheld_96.png
#   Art/icon_radio_brick_96.png
#   Art/icon_radio_antenna_96.png
#   Art/icon_radio_lock_96.png
#
# Run (from repo root):
#   "<BlenderPath>/blender.exe" --background --python Art/render_rfs_radio_icons.py
#
# Why: IconMap.xml must map uuid->cell, but our previous radio icons were cropped
# from UV diff sheets (1024px atlases) which show "random station map tiles".
# Blender renders the actual mesh with UVs, producing distinct thumbnails.

import bpy
import os
import math
import mathutils

ROOT = r"C:\Users\benko\Desktop\RecipeFrameworkSurvival"
OUT_DIR = os.path.join(ROOT, "Art")

SM_DATA = r"C:\Steam\steamapps\common\Scrap Mechanic\Data"
HACK_GATE_OFF_FBX = os.path.join(
    SM_DATA,
    "Objects",
    "Mesh",
    "interactive",
    "obj_interactive_logicgate_off.fbx",
)

RADIO_BRICK_FBX = os.path.join(ROOT, "Objects", "Mesh", "rfs_radio_brick.fbx")
RADIO_ANTENNA_FBX = os.path.join(ROOT, "Objects", "Mesh", "rfs_radio_antenna.fbx")
RADIO_LOCK_FBX = os.path.join(ROOT, "Objects", "Mesh", "rfs_radio_lock.fbx")
RADIO_HANDHELD_FBX = os.path.join(ROOT, "Tools", "rfs_radio_handheld.fbx")

TILE_BG = (20.0 / 255.0, 24.0 / 255.0, 28.0 / 255.0, 1.0)

SM_TEX = os.path.join(SM_DATA, "Objects", "Textures")

RADIO_BRICK_DIF = os.path.join(ROOT, "Objects", "Textures", "radio", "brick", "radio_2_dif.png")
RADIO_ANTENNA_DIF = os.path.join(ROOT, "Objects", "Textures", "radio", "antenna", "handheltradio_dif.png")
RADIO_LOCK_DIF = os.path.join(ROOT, "Objects", "Textures", "radio", "lock", "ampfilter_first_dif.png")
RADIO_HANDHELD_DIF = os.path.join(ROOT, "Objects", "Textures", "radio", "handheld", "handheltradio_dif.png")

HACK_GATE_DIF = os.path.join(SM_TEX, "interactive", "obj_interactive_logicgate_dif.tga")

PARTS = [
    # (out_name, fbx, base_color_dif, target_size, rotate_deg_xyz)
    ("icon_hackbeacon_96.png", HACK_GATE_OFF_FBX, HACK_GATE_DIF, 4.6, (0.0, 0.0, 0.0)),
    ("icon_radio_handheld_96.png", RADIO_HANDHELD_FBX, RADIO_HANDHELD_DIF, 5.2, (90.0, 0.0, 0.0)),
    ("icon_radio_brick_96.png", RADIO_BRICK_FBX, RADIO_BRICK_DIF, 4.6, (0.0, 0.0, 0.0)),
    ("icon_radio_antenna_96.png", RADIO_ANTENNA_FBX, RADIO_ANTENNA_DIF, 8.0, (90.0, 90.0, 0.0)),
    ("icon_radio_lock_96.png", RADIO_LOCK_FBX, RADIO_LOCK_DIF, 4.6, (0.0, 0.0, 0.0)),
]


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH" and o.data]


def world_bounds(objs):
    mins = mathutils.Vector((1e9, 1e9, 1e9))
    maxs = mathutils.Vector((-1e9, -1e9, -1e9))
    any_ok = False
    for o in objs:
        if not o or not o.data:
            continue
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


def look_at(obj, target):
    direction = target - obj.location
    # Camera looks along -Z, with Y as "up".
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def setup_world_and_render(scene, out_path):
    scene.render.engine = "CYCLES"
    scene.render.resolution_x = 96
    scene.render.resolution_y = 96
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = out_path

    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    cycles = scene.cycles
    cycles.samples = 48
    cycles.use_denoising = True
    try:
        cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass

    if scene.world is None:
        scene.world = bpy.data.worlds.new("rfs_icon_world")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        # Principled/Blender expects RGB in [0..1]; alpha is ignored in Background node.
        bg.inputs[0].default_value = (TILE_BG[0], TILE_BG[1], TILE_BG[2], 1.0)
        bg.inputs[1].default_value = 1.0


def fit_to_origin_and_scale(objs, target_size=2.0):
    gmins, gmaxs = world_bounds(objs)
    if gmins is None or gmaxs is None:
        return
    center = (gmins + gmaxs) * 0.5
    for o in objs:
        o.location = o.location - center
    gmins2, gmaxs2 = world_bounds(objs)
    if gmins2 is None or gmaxs2 is None:
        return
    size = gmaxs2 - gmins2
    m = max(size.x, size.y, size.z)
    if m <= 0.0:
        return
    factor = float(target_size) / float(m)
    for o in objs:
        o.scale = o.scale * factor

    # Apply scale so bounding/camera are stable after scaling.
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    try:
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    except Exception:
        pass


def apply_base_color_texture(objs, dif_path):
    """
    Force a known "Base Color" texture onto the imported meshes.
    This avoids magenta placeholder materials when the FBX importer
    can't auto-resolve Scrap Mechanic texture paths.
    """
    if not dif_path or not os.path.isfile(dif_path):
        return

    mat = bpy.data.materials.new(name="rfs_icon_base")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links

    # Reset nodes to a known layout.
    for n in list(nodes):
        nodes.remove(n)

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs.get("Metallic").default_value = 0.05
    bsdf.inputs.get("Roughness").default_value = 0.35

    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(dif_path)
    # Principled expects sRGB textures by default.

    links.new(tex.outputs.get("Color"), bsdf.inputs.get("Base Color"))
    links.new(bsdf.outputs.get("BSDF"), out.inputs.get("Surface"))

    for o in objs:
        if not o or not o.data:
            continue
        if len(o.data.materials) == 0:
            o.data.materials.append(mat)
        else:
            for i in range(len(o.data.materials)):
                o.data.materials[i] = mat


def render_part(fbx_path, out_path, dif_path, target_size, rotate_deg_xyz):
    if not os.path.isfile(fbx_path):
        raise SystemExit("missing fbx: " + fbx_path)

    reset_scene()

    scene = bpy.context.scene
    setup_world_and_render(scene, out_path)

    # Import.
    bpy.ops.import_scene.fbx(filepath=fbx_path)
    objs = mesh_objects()
    if not objs:
        raise SystemExit("no meshes after import: " + fbx_path)

    # Orientation tweak: a few parts import "standing up" and render like
    # a hairline from the icon camera.
    rx, ry, rz = rotate_deg_xyz
    rxr = math.radians(rx)
    ryr = math.radians(ry)
    rzr = math.radians(rz)
    for o in objs:
        o.rotation_euler = mathutils.Euler(
            (o.rotation_euler.x + rxr, o.rotation_euler.y + ryr, o.rotation_euler.z + rzr)
        )

    # Make the part fill most of the 96x96 icon frame.
    fit_to_origin_and_scale(objs, target_size=target_size)
    apply_base_color_texture(objs, dif_path)

    # Camera: diagonal top-down (matches style of icon_aimcore_96).
    cam_loc = mathutils.Vector((2.3, -5.0, 3.8))
    bpy.ops.object.camera_add(location=cam_loc)
    cam = bpy.context.active_object
    cam.data.lens = 28
    scene.camera = cam
    look_at(cam, mathutils.Vector((0.0, 0.0, 0.0)))

    # Lighting.
    bpy.ops.object.light_add(type="AREA", location=(3.0, -3.0, 5.0))
    key = bpy.context.active_object
    key.data.energy = 900
    key.data.size = 2.0

    bpy.ops.object.light_add(type="AREA", location=(-4.0, -1.0, 3.0))
    fill = bpy.context.active_object
    fill.data.energy = 350
    fill.data.size = 2.6

    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for out_name, fbx, dif, target_size, rotate_deg_xyz in PARTS:
        out_path = os.path.join(OUT_DIR, out_name)
        print("render", out_path, "from", fbx)
        render_part(fbx, out_path, dif, target_size, rotate_deg_xyz)
    print("done")


if __name__ == "__main__":
    main()

