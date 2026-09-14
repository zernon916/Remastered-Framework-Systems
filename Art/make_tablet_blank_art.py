# Blank tablet chrome: no baked mockup items (wood cube, spudgun, WOOD BLOCK row).
from PIL import Image, ImageDraw
import os

OUT = os.path.join(
	os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
	"Gui", "menu", "images", "tablet",
)
os.makedirs(OUT, exist_ok=True)

DARK = (28, 32, 36, 255)
WELL = (18, 20, 22, 255)
EDGE = (70, 78, 86, 255)
GOLD = (212, 160, 48, 220)


def rounded(size, fill, radius, outline=None, ow=2):
	im = Image.new("RGBA", size, (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	d.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=fill, outline=outline, width=ow)
	return im


def save(name, im):
	path = os.path.join(OUT, name)
	im.save(path, "PNG")
	print("wrote", name, im.size)


save("slot_empty.png", rounded((135, 85), DARK, 10, EDGE, 2))

row = rounded((584, 108), DARK, 12, EDGE, 2)
rd = ImageDraw.Draw(row)
rd.rounded_rectangle((10, 14, 98, 94), radius=10, fill=WELL, outline=EDGE, width=2)
save("queue_row_empty.png", row)

sel = rounded((610, 172), DARK, 12, GOLD, 3)
sd = ImageDraw.Draw(sel)
sd.rounded_rectangle((12, 18, 150, 154), radius=12, fill=WELL, outline=EDGE, width=2)
for i in range(3):
	x = 175 + i * 140
	sd.rounded_rectangle((x, 70, x + 118, 148), radius=10, fill=WELL, outline=EDGE, width=2)
save("selected_recipe_blank.png", sel)

save("ingredient_slot_empty.png", rounded((105, 71), WELL, 10, EDGE, 2))
print("done")
