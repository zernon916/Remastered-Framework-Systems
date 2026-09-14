# Export RTI Crafting Station with armature + independent slider/screen clips.
# Lamps are skinned to int_root (same lod as the body) and colored with
# SkelUVAnimDifAsgNor + setUvFrameIndex. Extra unskinned instance_geometry is
# dropped by SM on a SkelAnim mesh.
# Run: "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" --background --python Art\export_rti_crafting_station_skel.py
import os
import shutil
import sys

import bpy
from mathutils import Vector

BLEND = r"C:\Coding Projects\models\WIP Models\RTICrafting Station.blend"
ROOT = r"C:\Coding Projects\RemasteredFrameworkSystems"
OUT_MESH = os.path.join(ROOT, "Objects", "Mesh", "rfs_crafting_station.fbx")
OUT_MESH_DAE = os.path.join(ROOT, "Objects", "Mesh", "rfs_crafting_station.dae")
OUT_SLIDER = os.path.join(ROOT, "Objects", "Mesh", "ani_rfs_crafting_station_int_slider.dae")
OUT_SCREEN = os.path.join(ROOT, "Objects", "Mesh", "ani_rfs_crafting_station_int_screen_rotate.dae")
METRES_TO_BLOCKS = 4.0
PIECES = (
    "craftingstation_body",
    "craftingstation_screen",
    "craftingstation_slider",
    "submesh_light_01",
    "submesh_light_02",
)
BONE_FOR = {
    "craftingstation_body": "int_root",
    "craftingstation_screen": "int_screen_rotate",
    "craftingstation_slider": "int_slider",
    "submesh_light_01": "int_root",
    "submesh_light_02": "int_root",
}


def copy_bone_world(src_arm, src_name, dst_arm, dst_name):
    src = src_arm.data.bones[src_name]
    head = src_arm.matrix_world @ src.head_local
    tail = src_arm.matrix_world @ src.tail_local
    bpy.context.view_layer.objects.active = dst_arm
    dst_arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = dst_arm.data.edit_bones.get(dst_name)
    if eb is None:
        eb = dst_arm.data.edit_bones.new(dst_name)
    inv = dst_arm.matrix_world.inverted()
    eb.head = inv @ head
    eb.tail = inv @ tail
    if (eb.tail - eb.head).length < 0.001:
        eb.tail = eb.head + Vector((0.0, 0.0, 0.1))
    bpy.ops.object.mode_set(mode="OBJECT")


def bone_parent_to_weights(mesh_obj, arm_obj, bone_name):
    mw = mesh_obj.matrix_world.copy()
    mesh_obj.parent = None
    mesh_obj.matrix_world = mw
    keep = [g.name for g in mesh_obj.vertex_groups]
    for name in keep:
        mesh_obj.vertex_groups.remove(mesh_obj.vertex_groups[name])
    vg = mesh_obj.vertex_groups.new(name=bone_name)
    vg.add(list(range(len(mesh_obj.data.vertices))), 1.0, "REPLACE")
    for mod in list(mesh_obj.modifiers):
        if mod.type == "ARMATURE":
            mesh_obj.modifiers.remove(mod)
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    mod.use_vertex_groups = True
    mod.use_bone_envelopes = False


def ensure_uv(obj):
    mesh = obj.data
    if mesh.uv_layers:
        return
    uv = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uv.data[loop.index].uv = (0.5, 0.5)


def split_action(src, bone, name):
    act = src.copy()
    act.name = name
    for fc in list(act.fcurves):
        if ('pose.bones["%s"]' % bone) not in fc.data_path:
            act.fcurves.remove(fc)
    if len(act.fcurves) == 0:
        raise RuntimeError("No fcurves for " + bone)
    return act


def apply_object(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def mesh_bounds(objs):
    pts = []
    for obj in objs:
        for v in obj.data.vertices:
            pts.append(obj.matrix_world @ v.co)
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def assign_named_material(obj, name):
    mesh = obj.data
    mesh.materials.clear()
    mat = bpy.data.materials.new(name)
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.material_index = 0


def join_named(scene_objs, names):
    body = scene_objs[names[0]]
    for name in names[1:]:
        bpy.ops.object.select_all(action="DESELECT")
        body.select_set(True)
        scene_objs[name].select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()
        scene_objs[name] = body
    return body


def collada_anim(path, arm):
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.wm.collada_export(
        filepath=path,
        selected=True,
        apply_modifiers=False,
        include_animations=True,
        include_all_actions=False,
        include_armatures=True,
        include_children=False,
        include_shapekeys=False,
        triangulate=False,
        deform_bones_only=True,
        export_global_forward_selection="-Z",
        export_global_up_selection="Y",
        apply_global_orientation=True,
        use_blender_profile=True,
        use_object_instantiation=False,
        limit_precision=False,
        sampling_rate=1,
    )
    print("WROTE", path)


def main():
    if not os.path.isfile(BLEND):
        raise RuntimeError("Missing " + BLEND)
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    bpy.context.scene.frame_set(1)
    scene_objs = {o.name: o for o in bpy.context.scene.objects}
    for name in PIECES:
        if name not in scene_objs:
            raise RuntimeError("Missing mesh " + name)
    anim_arm = scene_objs["jnt_craftingstation"]
    body_arm = scene_objs["jnt_body_anchor"]
    copy_bone_world(body_arm, "int_root", anim_arm, "int_root")
    for name, bone in BONE_FOR.items():
        bone_parent_to_weights(scene_objs[name], anim_arm, bone)
        ensure_uv(scene_objs[name])

    src = anim_arm.animation_data.action
    if src is None or src.name != "unlocked":
        src = bpy.data.actions.get("unlocked")
    if src is None:
        raise RuntimeError("Missing action unlocked")
    act_slider = split_action(src, "int_slider", "int_slider")
    act_screen = split_action(src, "int_screen_rotate", "int_screen_rotate")

    skin = [scene_objs[n] for n in PIECES]
    for obj in skin + [anim_arm]:
        apply_object(obj)
    for obj in skin + [anim_arm]:
        obj.scale = (METRES_TO_BLOCKS, METRES_TO_BLOCKS, METRES_TO_BLOCKS)
        apply_object(obj)
    mn, mx = mesh_bounds(skin)
    center = (mn + mx) * 0.5
    for obj in skin + [anim_arm]:
        obj.location -= center
        apply_object(obj)

    for name in PIECES:
        assign_named_material(scene_objs[name], name)

    joined = join_named(scene_objs, PIECES)
    joined.name = "craftingstation_body"
    names = [m.name for m in joined.data.materials]
    if names != list(PIECES):
        raise RuntimeError("Material order " + repr(names))
    if joined.modifiers.get("Armature") is None:
        mod = joined.modifiers.new("Armature", "ARMATURE")
        mod.object = anim_arm
        mod.use_vertex_groups = True

    os.makedirs(os.path.dirname(OUT_MESH), exist_ok=True)
    if os.path.isfile(OUT_MESH):
        shutil.copy2(OUT_MESH, OUT_MESH + ".pre_skel.bak")

    bpy.ops.object.select_all(action="DESELECT")
    joined.select_set(True)
    anim_arm.select_set(True)
    bpy.context.view_layer.objects.active = joined
    bpy.ops.export_scene.fbx(
        filepath=OUT_MESH,
        use_selection=True,
        object_types={"MESH", "ARMATURE"},
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=True,
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="STRIP",
        embed_textures=False,
        use_triangles=False,
    )
    print("WROTE", OUT_MESH)

    bpy.ops.object.select_all(action="DESELECT")
    joined.select_set(True)
    anim_arm.select_set(True)
    bpy.context.view_layer.objects.active = joined
    bpy.ops.wm.collada_export(
        filepath=OUT_MESH_DAE,
        selected=True,
        apply_modifiers=True,
        include_animations=False,
        include_all_actions=False,
        include_armatures=True,
        include_children=False,
        include_shapekeys=False,
        triangulate=False,
        deform_bones_only=True,
        export_global_forward_selection="-Z",
        export_global_up_selection="Y",
        apply_global_orientation=True,
        use_blender_profile=True,
        use_object_instantiation=False,
        limit_precision=False,
    )
    print("WROTE", OUT_MESH_DAE)

    if anim_arm.animation_data is None:
        anim_arm.animation_data_create()
    anim_arm.animation_data.action = act_slider
    bpy.context.scene.frame_start = int(act_slider.frame_range[0])
    bpy.context.scene.frame_end = int(act_slider.frame_range[1])
    collada_anim(OUT_SLIDER, anim_arm)
    anim_arm.animation_data.action = act_screen
    bpy.context.scene.frame_start = int(act_screen.frame_range[0])
    bpy.context.scene.frame_end = 45
    collada_anim(OUT_SCREEN, anim_arm)
    art = os.path.join(ROOT, "Art")
    if art not in sys.path:
        sys.path.insert(0, art)
    import fix_sm_collada
    fix_sm_collada.fix_dae(OUT_MESH_DAE)
    fix_sm_collada.fix_dae(OUT_SLIDER, clip_name="int_slider")
    fix_sm_collada.fix_dae(OUT_SCREEN, clip_name="int_screen_rotate")
    print("RFS_SKEL_EXPORT_OK")


if __name__ == "__main__":
    main()
