# Rewrite Blender Collada so Scrap Mechanic can bind pose clips.
# Vanilla SM (FBX COLLADA) uses joint id == name == sid, matrix sid="matrix",
# and channel target "bone/matrix". Blender writes id="armature_bone",
# sid="transform", and target="armature_bone/transform", which never binds.
import os
import re
import sys

ROOT = r"C:\Coding Projects\RemasteredFrameworkSystems"
MESH = os.path.join(ROOT, "Objects", "Mesh", "rfs_crafting_station.dae")
ANIMS = (
    (os.path.join(ROOT, "Objects", "Mesh", "ani_rfs_crafting_station_int_slider.dae"), "int_slider"),
    (os.path.join(ROOT, "Objects", "Mesh", "ani_rfs_crafting_station_int_screen_rotate.dae"), "int_screen_rotate"),
    (os.path.join(ROOT, "Objects", "Mesh", "ani_rfs_crafting_station_int_light_top.dae"), "int_light_top"),
    (os.path.join(ROOT, "Objects", "Mesh", "ani_rfs_crafting_station_int_light_bot.dae"), "int_light_bot"),
)


def _remap_times(xml):
    def repl(m):
        nums = [float(x) for x in m.group(2).split() if x]
        if not nums:
            return m.group(0)
        lo, hi = min(nums), max(nums)
        span = hi - lo if hi > lo else 1.0
        mapped = " ".join("%.6f" % ((x - lo) / span) for x in nums)
        return m.group(1) + mapped + m.group(3)

    return re.sub(
        r'(<float_array id="[^"]*-input-array"[^>]*>)([^<]*)(</float_array>)',
        repl,
        xml,
    )


def fix_dae_text(xml, clip_name=None):
    xml = re.sub(
        r'id="jnt_craftingstation_(int_[^"]+)"',
        r'id="\1"',
        xml,
    )
    xml = xml.replace("#jnt_craftingstation_int_", "#int_")
    xml = re.sub(
        r'target="jnt_craftingstation_(int_[^"/]+)/transform"',
        r'target="\1/matrix"',
        xml,
    )
    xml = re.sub(
        r'target="(int_[^"/]+)/transform"',
        r'target="\1/matrix"',
        xml,
    )
    xml = xml.replace(
        '<node id="jnt_craftingstation" name="jnt_craftingstation" type="NODE">',
        '<node id="j_root" name="j_root" sid="j_root" type="JOINT">',
    )
    xml = re.sub(
        r'(type="JOINT">\s*<matrix sid=")transform(")',
        r"\1matrix\2",
        xml,
    )
    if clip_name:
        xml = xml.replace('name="jnt_craftingstation"', 'name="%s"' % clip_name)
        xml = xml.replace(
            'id="action_container-jnt_craftingstation"',
            'id="%s-anim"' % clip_name,
        )
        xml = _remap_times(xml)
        if "start_time" not in xml:
            xml = xml.replace(
                "</visual_scene>",
                '      <extra><technique profile="FCOLLADA">'
                "<start_time>0.000000</start_time>"
                "<end_time>1.000000</end_time>"
                "</technique></extra>\n    </visual_scene>",
                1,
            )
    return xml


def fix_dae(path, clip_name=None):
    if not os.path.isfile(path):
        print("SKIP missing", path)
        return False
    with open(path, "r", encoding="utf-8") as f:
        xml = f.read()
    out = fix_dae_text(xml, clip_name=clip_name)
    if out == xml:
        print("NOCHANGE", path)
        return False
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    print("FIXED", path)
    return True


def main():
    fix_dae(MESH)
    for path, name in ANIMS:
        fix_dae(path, clip_name=name)


if __name__ == "__main__":
    sys.exit(0 if main() is None else 0)
