# Slice kit_v2: numbered 1-4, CRAFT/UPGRADES on/off, LOCKED, UPGRADE plates.
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

KIT = Path(r"C:\Coding Projects\RemasteredFrameworkSystems\Art\craftstation_ui\kit_v2.jpg")
OUT = Path(r"C:\Coding Projects\RemasteredFrameworkSystems\Gui\Images\craftstation")
DEBUG = Path(r"C:\Coding Projects\RemasteredFrameworkSystems\Art\craftstation_ui\kit_v2_boxes.png")


def fg_mask(rgb):
	r = rgb[..., 0].astype(np.int16)
	g = rgb[..., 1].astype(np.int16)
	b = rgb[..., 2].astype(np.int16)
	chroma = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
	mean = (r + g + b) / 3
	checker = (chroma < 22) & (mean > 188)
	return ~checker


def components(mask):
	h, w = mask.shape
	seen = np.zeros((h, w), dtype=bool)
	boxes = []
	ys, xs = np.where(mask)
	for y, x in zip(ys.tolist(), xs.tolist()):
		if seen[y, x]:
			continue
		stack = [(y, x)]
		seen[y, x] = True
		minx = maxx = x
		miny = maxy = y
		count = 0
		while stack:
			cy, cx = stack.pop()
			count += 1
			minx, maxx = min(minx, cx), max(maxx, cx)
			miny, maxy = min(miny, cy), max(maxy, cy)
			for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
				if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
					seen[ny, nx] = True
					stack.append((ny, nx))
		bw, bh = maxx - minx + 1, maxy - miny + 1
		if count < 80 or bw < 10 or bh < 10:
			continue
		boxes.append((minx, miny, maxx + 1, maxy + 1))
	boxes.sort(key=lambda b: (b[1], b[0]))
	return boxes


def name_box(box):
	x0, y0, x1, y1 = box
	w, h, cx = x1 - x0, y1 - y0, (x0 + x1) * 0.5
	if y0 < 95 and w > 160:
		if cx < 200:
			return "tab_craft_off"
		if cx < 430:
			return "tab_craft_on"
		if cx < 700:
			return "tab_upgrades_off"
		return "tab_upgrades_on"
	if 95 <= y0 < 200 and w < 90 and h < 90:
		# 1-4 off then 1-4 on
		if cx < 520:
			n = int(round((cx - 40) / 95))
			n = max(1, min(4, n + 1))
			return "num_%d_off" % n
		n = int(round((cx - 540) / 95))
		n = max(1, min(4, n + 1))
		return "num_%d_on" % n
	if 200 <= y0 < 310:
		if w > 160 and cx < 280:
			return "btn_upgrade_off"
		if w > 160 and cx < 560:
			return "btn_upgrade_on"
		if w > 120:
			return "btn_locked"
		if cx < 780:
			return "btn_plus_v2"
		if cx < 880:
			return "btn_minus_v2"
		return "btn_cancel_v2"
	if 310 <= y0 < 420:
		if w > 300:
			return "search_v2"
		if cx < 780:
			return "pill_all_v2"
		return "pill_tools_v2"
	return None


def main():
	img = Image.open(KIT).convert("RGB")
	arr = np.asarray(img)
	fg = ndimage.binary_opening(fg_mask(arr), iterations=1)
	fg = ndimage.binary_closing(fg, iterations=1)
	boxes = components(fg)
	rgba = np.dstack([arr, np.where(fg, 255, 0).astype(np.uint8)])
	from PIL import ImageDraw
	debug = img.copy()
	draw = ImageDraw.Draw(debug)
	used = {}
	for box in boxes:
		name = name_box(box)
		if not name:
			continue
		if name in used:
			used[name] += 1
			name = "%s_%d" % (name, used[name])
		else:
			used[name] = 1
		x0, y0, x1, y1 = box
		Image.fromarray(rgba[y0:y1, x0:x1], "RGBA").save(OUT / ("%s.png" % name))
		draw.rectangle([x0, y0, x1 - 1, y1 - 1], outline=(255, 0, 0))
		draw.text((x0, max(0, y0 - 10)), name, fill=(255, 0, 0))
		print("WROTE", name, (x1 - x0, y1 - y0))
	debug.save(DEBUG)
	print("DEBUG", DEBUG)


if __name__ == "__main__":
	main()
