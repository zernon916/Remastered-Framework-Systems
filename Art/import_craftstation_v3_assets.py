# Copy cleaned individual PNGs + slice leftover tilesets into Gui/menu/images/craftstation.
from pathlib import Path
import shutil

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(r"C:\Coding Projects\RemasteredFrameworkSystems")
ASSETS = Path(
	r"C:\Users\benko\.cursor\projects\c-Coding-Projects-RemasteredFrameworkSystems\assets"
)
OUT = ROOT / "Gui" / "menu" / "images" / "craftstation"
OUT_ALT = ROOT / "Gui" / "Images" / "craftstation"
SRC = ROOT / "Art" / "craftstation_ui" / "v3"
OUT.mkdir(parents=True, exist_ok=True)
OUT_ALT.mkdir(parents=True, exist_ok=True)
SRC.mkdir(parents=True, exist_ok=True)

SINGLES = {
	"capacity_checkbox_empty": "capacity_checkbox_empty-82f568d9-9a3b-4b34-90d8-dd5fe9a16a89.png",
	"btn_close_oct": "button_close-242eb5f8-1d51-487e-84b7-867824a9aaee.png",
	"kit_purple": "component_kit_purple-beeebd12-7406-4b20-9e33-55c518c9bcb3.png",
	"kit_orange": "component_kit_orange-d469ed18-3df3-4c8e-b101-826010a02757.png",
	"capacity_checkbox_full": "capacity_checkbox_full-2139816a-ba30-4f4e-b55e-164ace644e53.png",
	"status_wireless_online": "status_wireless_online-3079e842-d47b-485f-a7cb-651884b6109a.png",
	"kit_yellow": "component_kit_yellow-3fddfc25-13c6-4970-a89f-3b1cb329bd16.png",
	"header_station_upgrades": "header_station_upgrades-9303480c-7813-47a3-9b64-f46d7099d281.png",
	"upg_check_3_empty": "upgrade_3_checkbox_empty-5239d5ec-7772-4013-9d6f-a78b8fd23526.png",
	"upg_check_2_empty": "upgrade_2_checkbox_empty-a559de6b-e17a-4b3f-bb4a-a0964646f460.png",
	"upg_check_2_full": "upgrade_2_checkbox_full-b6450d8c-cdaf-4dbb-9890-c63f2819e374.png",
	"tab_upgrades_badge": "tab_upgrades-83dd4dba-a2f1-45c3-9e29-4fbd371eba48.png",
	"status_connected_tablets": "status_connected_tablets-59ba59ea-a1f8-44b9-9e71-8a954f959366.png",
	"status_craft_speed": "status_craft_speed-b0a80d4d-68a7-4b4f-ae61-7491e413d961.png",
	"kit_red": "component_kit_red-ee9c558a-037c-4eb6-9e4b-90ea5bf867f7.png",
	"title_crafting_station": "title_crafting_station-b54856b8-2a5d-46b3-8ee5-82170f2769c7.png",
	"upg_check_4_empty": "upgrade_4_checkbox_empty-5a7c8326-c9a8-4b84-880f-e2227e90d1b8.png",
	"status_current_capacity": "status_current_capacity-01f5f630-64a7-4869-b9e8-ff4ed045a293.png",
	"upg_check_1_full": "upgrade_1_checkbox_full-0fc84681-a5b6-4c1d-a0f6-16deccd34dc5.png",
	"upg_check_3_full": "upgrade_3_checkbox_full-4f063e09-24bd-44da-8b5e-8fb972614b70.png",
	"upg_check_1_empty": "upgrade_1_checkbox_empty-0ea01d9a-d09c-499e-aeac-7a6e5dd08e30.png",
	"tab_craft_badge": "tab_craft-b5adf02b-6c48-4da1-99e2-7967cf57f8bc.png",
	"upg_check_4_full": "upgrade_4_checkbox_full-2affed1b-5bae-458e-be9b-e4e680dbdf3e.png",
	"bottom_status_full": "bottom_status_full-a37cd407-1c4d-4965-9ab6-00ae716968f7.png",
	"upgrade_card_2": "upgrade_card_2-cac556b4-0083-4c88-9893-14c23ce904cb.png",
	"upgrade_card_3": "upgrade_card_3-58855fb8-3c58-4ce1-912b-32054228f57b.png",
	"upgrade_card_1": "upgrade_card_1-e47fd227-ef7c-44e2-9dd3-540ac092ff65.png",
	"upgrade_card_4": "upgrade_card_4-0ff24f7f-64de-4b44-98cc-d2c0439f9c54.png",
	"top_header_full": "top_header_full-c7f89816-cc5d-4be9-848e-22aae7362320.png",
}

SHEETS = {
	"kit_items.jpg": "Transparent_industrial_health_icon_sprite_sheet-0977eff5-01de-433e-8684-ef7769215042.jpg",
	"hud_tiles.jpg": "Gold-Trimmed_Four-Icon_HUD_Tiles-06d26631-b817-41cd-8041-0379aa4e8a6b.jpg",
	"farmtablet_sheet.jpg": "Farmer_s_Tablet_Industrial_Sprite_Sheet-0186a40a-7a45-4fe9-bf28-0beeff406b3e.jpg",
	"upgrade_sheet.jpg": "Crafting_Station_Upgrade_UI_Sprite_Sheet-032d851b-735d-4d4b-bde9-6b467042519f.jpg",
	"cat_on_off.jpg": "Pixel-art_ON_OFF_button_reference_grid-58b419c7-75f0-44ea-8064-8598810b6b6c.jpg",
	"kit_v3.jpg": "Industrial_crafting_and_upgrade_UI_sprites-73683ffa-65e5-4f04-92b4-30cc5a90cf90.jpg",
	"kit_v1.jpg": "Industrial_crafting_UI_sprite_sheet-fe9d28b5-d588-46d8-afa0-3d230b54f2e4.jpg",
	"seed_bags.jpg": "Seed_bags_and_soil_icon_atlas-43a27b53-5793-4412-b3aa-da0c51402e1a.jpg",
	"upgrade_mockup.jpg": "Upgrade_Mockup-2213a995-7a9e-4f07-8da5-c4100d7c2072.jpg",
}


def find_asset(suffix):
	hits = list(ASSETS.glob("*" + suffix))
	if not hits:
		raise FileNotFoundError(suffix)
	return hits[0]


def save_png(img, name):
	path = OUT / ("%s.png" % name)
	img.save(path)
	img.save(OUT_ALT / ("%s.png" % name))
	print("WROTE", path.name, img.size)
	return path


def fg_mask(rgb):
	mx = rgb.max(axis=2).astype(np.int16)
	mn = rgb.min(axis=2).astype(np.int16)
	mean = rgb.mean(axis=2)
	return (mx > 18) | ((mx - mn) > 8) | (mean > 12)


def slice_sheet(src, prefix, min_w=40, min_h=24, min_count=200):
	img = Image.open(src).convert("RGB")
	arr = np.asarray(img)
	fg = ndimage.binary_closing(fg_mask(arr), iterations=2)
	labeled, n = ndimage.label(fg)
	saved = 0
	for i in range(1, n + 1):
		ys, xs = np.where(labeled == i)
		if xs.size < min_count:
			continue
		x0, x1 = int(xs.min()), int(xs.max()) + 1
		y0, y1 = int(ys.min()), int(ys.max()) + 1
		w, h = x1 - x0, y1 - y0
		if w < min_w or h < min_h:
			continue
		alpha = np.where(fg[y0:y1, x0:x1], 255, 0).astype(np.uint8)
		rgba = np.dstack([arr[y0:y1, x0:x1], alpha])
		save_png(Image.fromarray(rgba, "RGBA"), "%s_%02d" % (prefix, saved))
		saved += 1
	print("SLICED", prefix, saved)


def main():
	for name, suffix in SINGLES.items():
		src = find_asset(suffix)
		img = Image.open(src).convert("RGBA")
		save_png(img, name)
		shutil.copy2(src, SRC / (name + src.suffix))
	for dest_name, suffix in SHEETS.items():
		src = find_asset(suffix)
		shutil.copy2(src, SRC / dest_name)
		print("SRC", dest_name)
	slice_sheet(SRC / "cat_on_off.jpg", "catv3")
	print("DONE")


if __name__ == "__main__":
	main()
