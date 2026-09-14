# Split the cleaned kit tileset into panel_hex.png + panel_wide.png (alpha).
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(r"C:\Coding Projects\RemasteredFrameworkSystems")
KIT = Path(
	r"C:\Users\benko\.cursor\projects\c-Coding-Projects-RemasteredFrameworkSystems"
	r"\assets\c__Users_benko_AppData_Roaming_Cursor_User_workspaceStorage_"
	r"4a00a0a23aaaf4d4b8023b3849d5d024_images_Industrial_crafting_and_upgrade_"
	r"UI_sprites-3b0b5c7b-b032-40a6-8396-eb9efdc7fa3f.jpg"
)
SRC_COPY = ROOT / "Art" / "craftstation_ui" / "kit_v3_clean.jpg"
OUT = ROOT / "Gui" / "menu" / "images" / "craftstation"
OUT_ALT = ROOT / "Gui" / "Images" / "craftstation"
DEBUG = ROOT / "Art" / "craftstation_ui" / "kit_v3_panel_boxes.png"


def fg_mask(rgb):
	mx = rgb.max(axis=2).astype(np.int16)
	mn = rgb.min(axis=2).astype(np.int16)
	mean = rgb.mean(axis=2)
	# Near-black plate field is part of the sprite; only treat true void as bg.
	return (mx > 18) | ((mx - mn) > 8) | (mean > 12)


def boxes_from_mask(mask):
	labeled, n = ndimage.label(mask)
	out = []
	for i in range(1, n + 1):
		ys, xs = np.where(labeled == i)
		if xs.size < 400:
			continue
		x0, x1 = int(xs.min()), int(xs.max()) + 1
		y0, y1 = int(ys.min()), int(ys.max()) + 1
		w, h = x1 - x0, y1 - y0
		if w < 40 or h < 40:
			continue
		out.append((x0, y0, x1, y1, w, h, xs.size))
	return out


def main():
	img = Image.open(KIT).convert("RGB")
	SRC_COPY.parent.mkdir(parents=True, exist_ok=True)
	img.save(SRC_COPY, quality=95)
	arr = np.asarray(img)
	fg = ndimage.binary_opening(fg_mask(arr), iterations=1)
	fg = ndimage.binary_closing(fg, iterations=2)
	# Bottom row only: hex badge + wide plate live under y~400.
	bottom = np.zeros_like(fg)
	bottom[400:, :] = fg[400:, :]
	found = boxes_from_mask(bottom)
	found.sort(key=lambda b: b[0])
	print("BOTTOM BOXES")
	for b in found:
		print(" ", b)

	# Hex is the near-square mid/right plate; wide is the large rectangle.
	hex_box = None
	wide_box = None
	for b in found:
		x0, y0, x1, y1, w, h, _ = b
		ratio = w / float(h)
		if 0.85 <= ratio <= 1.25 and 90 <= w <= 220 and x0 > 300:
			hex_box = (x0, y0, x1, y1)
		elif ratio >= 1.8 and w >= 280:
			wide_box = (x0, y0, x1, y1)
	if not hex_box or not wide_box:
		raise SystemExit("failed to find hex/wide: %s" % (found,))

	alpha = np.where(fg, 255, 0).astype(np.uint8)
	rgba = np.dstack([arr, alpha])
	OUT.mkdir(parents=True, exist_ok=True)
	OUT_ALT.mkdir(parents=True, exist_ok=True)
	crops = {
		"panel_hex.png": hex_box,
		"panel_wide.png": wide_box,
	}
	debug = img.copy()
	from PIL import ImageDraw
	draw = ImageDraw.Draw(debug)
	for name, box in crops.items():
		x0, y0, x1, y1 = box
		crop = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
		crop.save(OUT / name)
		crop.save(OUT_ALT / name)
		draw.rectangle([x0, y0, x1 - 1, y1 - 1], outline=(255, 0, 0))
		draw.text((x0, max(0, y0 - 12)), name, fill=(255, 0, 0))
		print("WROTE", name, crop.size, box)
	debug.save(DEBUG)
	print("DEBUG", DEBUG)


if __name__ == "__main__":
	main()
