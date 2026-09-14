# Precise crops from kit_v2 (1024x682) for tablet 1-4 and the wide cover plate.
from pathlib import Path

from PIL import Image

KIT = Path(r"C:\Coding Projects\RemasteredFrameworkSystems\Art\craftstation_ui\kit_v2.jpg")
OUT = Path(r"C:\Coding Projects\RemasteredFrameworkSystems\Gui\Images\craftstation")

# Measured from kit_v2_boxes.png / source.
CROPS = {
	"num_1_off.png": (73, 120, 158, 202),
	"num_2_off.png": (181, 120, 266, 202),
	"num_3_off.png": (289, 120, 374, 202),
	"num_4_off.png": (397, 120, 482, 202),
	"num_1_on.png": (541, 119, 625, 203),
	"num_2_on.png": (649, 119, 733, 203),
	"num_3_on.png": (757, 119, 841, 203),
	"num_4_on.png": (865, 119, 949, 203),
	"tab_craft_off.png": (18, 18, 253, 91),
	"tab_craft_on.png": (271, 16, 513, 91),
	"tab_upgrades_off.png": (531, 18, 777, 91),
	"tab_upgrades_on.png": (795, 16, 1041, 91),
	"btn_locked.png": (543, 230, 712, 302),
	"panel_wide.png": (579, 438, 1010, 608),
	"panel_hex.png": (428, 446, 566, 605),
	"panel_square.png": (216, 419, 419, 618),
}


def main():
	img = Image.open(KIT).convert("RGBA")
	# Drop near-white checker so overlays don't flash gray.
	px = img.load()
	w, h = img.size
	for y in range(h):
		for x in range(w):
			r, g, b, a = px[x, y]
			chroma = max(r, g, b) - min(r, g, b)
			mean = (r + g + b) / 3
			if chroma < 22 and mean > 200:
				px[x, y] = (0, 0, 0, 0)
	for name, box in CROPS.items():
		img.crop(box).save(OUT / name)
		print("WROTE", name, img.crop(box).size)


if __name__ == "__main__":
	main()
