# Slice the CRAFTING STATION kit sheet into named PNGs (checkerboard = alpha).
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"C:\Coding Projects\RemasteredFrameworkSystems")
KIT = ROOT / "Art" / "craftstation_ui" / "kit_sheet.jpg"
OUT = ROOT / "Gui" / "Images" / "craftstation"
DEBUG = ROOT / "Art" / "craftstation_ui" / "kit_boxes.png"


def checker_mask(rgb):
	# JPG checker is light gray / near-white (not mid-gray).
	r = rgb[..., 0].astype(np.int16)
	g = rgb[..., 1].astype(np.int16)
	b = rgb[..., 2].astype(np.int16)
	mx = np.maximum(np.maximum(r, g), b)
	mn = np.minimum(np.minimum(r, g), b)
	chroma = mx - mn
	mean = (r + g + b) / 3
	return (chroma < 22) & (mean > 188)


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
			if cx < minx:
				minx = cx
			if cx > maxx:
				maxx = cx
			if cy < miny:
				miny = cy
			if cy > maxy:
				maxy = cy
			for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
				if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
					seen[ny, nx] = True
					stack.append((ny, nx))
		bw = maxx - minx + 1
		bh = maxy - miny + 1
		if count < 80 or bw < 8 or bh < 8:
			continue
		boxes.append((minx, miny, maxx + 1, maxy + 1, count))
	boxes.sort(key=lambda b: (b[1], b[0]))
	return boxes


def name_box(box, idx):
	x0, y0, x1, y1, _ = box
	w, h = x1 - x0, y1 - y0
	cx = (x0 + x1) * 0.5
	# Heuristic by row / size from the 1024x682 kit.
	if y0 < 90 and h < 80 and w > 180:
		if cx < 280:
			return "btn_craft"
		if cx < 620:
			return "btn_upgrades"
		return "btn_addqueue"
	if 90 <= y0 < 200 and h < 90:
		if w < 80:
			if cx < 120:
				return "btn_plus"
			if cx < 220:
				return "btn_minus"
			return "btn_cancel"
		return "search"
	if 200 <= y0 < 340:
		if h < 70 and w < 220:
			if cx < 220:
				return "pill_on"
			return "pill_off"
		if w < 280:
			return "panel_slot"
		return "panel_bar"
	if 340 <= y0 < 470:
		if w < 80 and h < 80:
			if cx < 140:
				return "dot_on"
			return "dot_off"
		if h < 40 and w > 200:
			if y1 - y0 < 28 and ((y0 + y1) / 2) < 420:
				return "bar_track"
			return "bar_fill"
		if w < 50 and h < 50:
			return "bar_knob"
	if y0 >= 450:
		if w > 140 and h > 140:
			return "slot_frame"
		if w < 40 and h > 80:
			if cx < 180:
				return "scroll_track"
			return "scroll_thumb"
		if w < 50 and h < 50:
			if y0 < 560:
				return "scroll_up"
			return "scroll_down"
	return "piece_%02d" % idx


def main():
	img = Image.open(KIT).convert("RGB")
	arr = np.asarray(img)
	bg = checker_mask(arr)
	fg = ~bg
	# Close small holes so widgets stay one blob.
	from scipy import ndimage
	fg = ndimage.binary_opening(fg, iterations=1)
	fg = ndimage.binary_closing(fg, iterations=1)
	boxes = components(fg)
	OUT.mkdir(parents=True, exist_ok=True)
	rgba = np.dstack([arr, np.where(fg, 255, 0).astype(np.uint8)])
	used = {}
	debug = img.copy()
	from PIL import ImageDraw
	draw = ImageDraw.Draw(debug)
	manifest = []
	for i, box in enumerate(boxes):
		name = name_box(box, i)
		if name in used:
			used[name] += 1
			name = "%s_%d" % (name, used[name])
		else:
			used[name] = 1
		x0, y0, x1, y1, _ = box
		crop = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
		path = OUT / ("%s.png" % name)
		crop.save(path)
		manifest.append((name, crop.size, (x0, y0, x1, y1)))
		draw.rectangle([x0, y0, x1 - 1, y1 - 1], outline=(255, 0, 0))
		draw.text((x0, max(0, y0 - 10)), name, fill=(255, 0, 0))
		print("WROTE", path.name, crop.size, (x0, y0, x1, y1))
	debug.save(DEBUG)
	print("BOXES", len(manifest), "DEBUG", DEBUG)


if __name__ == "__main__":
	main()
