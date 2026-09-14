# Generate Rfs_RecipeViewer.layout from the combined mockup.
# Art first, hits on top, same parent per region. Grid uses ArtSlots + PanelCells.
import os

OUT = os.path.join(
	os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
	"Gui", "menu", "layouts", "Rfs_RecipeViewer.layout",
)
IMG = "$CONTENT_DATA/Gui/menu/images/tablet/"
COLS = 6
ROWS = 4
CELLS = COLS * ROWS
QUEUE_ROWS = 6


def f(x):
	return ("%.4f" % x).rstrip("0").rstrip(".")


def art(name, x, y, w, h, image=None, keep=True, visible=True):
	tex = ""
	if image:
		if not image.startswith("$"):
			image = IMG + image
		tex = '\t\t\t\t<Property key="ImageTexture" value="%s"/>\n' % image
	vis = ""
	if not visible:
		vis = '\t\t\t\t<Property key="Visible" value="false"/>\n'
	return (
		'\t\t\t<Widget type="ImageBox" skin="ImageBox" position_real="%s %s %s %s" name="%s">\n'
		'%s'
		'\t\t\t\t<Property key="NeedMouse" value="false"/>\n'
		'\t\t\t\t<Property key="NeedKey" value="false"/>\n'
		'\t\t\t\t<Property key="InheritsPick" value="true"/>\n'
		'\t\t\t\t<Property key="ImageKeepAspect" value="%s"/>\n'
		'%s'
		'\t\t\t</Widget>'
	) % (f(x), f(y), f(w), f(h), name, vis, "true" if keep else "false", tex)


def hit(name, x, y, w, h):
	return (
		'\t\t\t<Widget type="Button" skin="PanelEmpty" position_real="%s %s %s %s" name="%s">\n'
		'\t\t\t\t<Property key="Caption" value=""/>\n'
		'\t\t\t\t<Property key="FontName" value="SM_Button"/>\n'
		'\t\t\t\t<Property key="NeedMouse" value="true"/>\n'
		'\t\t\t</Widget>'
	) % (f(x), f(y), f(w), f(h), name)


def text(name, x, y, w, h, caption="", align="Left VCenter", font="SM_Text"):
	return (
		'\t\t\t<Widget type="TextBox" skin="TextBox" position_real="%s %s %s %s" name="%s">\n'
		'\t\t\t\t<Property key="Caption" value="%s"/>\n'
		'\t\t\t\t<Property key="FontName" value="%s"/>\n'
		'\t\t\t\t<Property key="TextAlign" value="%s"/>\n'
		'\t\t\t</Widget>'
	) % (f(x), f(y), f(w), f(h), name, caption, font, align)


def indent_block(s, extra="\t"):
	return "\n".join(extra + line if line else line for line in s.split("\n"))


parts = []
parts.append('<?xml version="1.0" encoding="UTF-8"?>')
parts.append('<MyGUI type="Layout" version="3.2.0">')
parts.append('\t<!-- RFS tablet: combined recipes + remote queue. Kit=$CONTENT_DATA/Gui/menu/images/tablet -->')
parts.append('\t<Widget type="Widget" skin="PanelEmpty" position_real="0 0 1 1" name="Root">')
parts.append('\t\t<Property key="NeedKey" value="false"/>')
parts.append('\t\t<Property key="NeedMouse" value="true"/>')
parts.append('\t\t<Widget type="Widget" skin="PanelEmpty" position_real="0.02 0.02 0.96 0.96" name="MainPanel">')
parts.append('\t\t\t<Property key="NeedKey" value="false"/>')
parts.append('\t\t\t<Property key="NeedMouse" value="true"/>')

# Background + chrome
parts.append(art("BgPanel", 0, 0, 1, 1, "mobile_crafting_tablet_background_clean.png", keep=False))
parts.append(art("ArtTitle", 0.262, 0.012, 0.476, 0.082, "title_mobile_crafting_tablet.png"))
parts.append(art("ArtClose", 0.922, 0.014, 0.056, 0.088, "button_close_gold.png"))
parts.append(art("ArtWireless", 0.658, 0.096, 0.170, 0.074, "badge_wireless_online.png", visible=False))
parts.append(art("ArtWirelessOff", 0.658, 0.096, 0.170, 0.074, "badge_wireless_online.png", visible=False))
parts.append(art("ArtStationBadge", 0.838, 0.096, 0.118, 0.074, "badge_station_1.png", visible=False))
parts.append(art("ArtHint", 0.028, 0.174, 0.944, 0.048, "instruction_strip.png", keep=False))
parts.append(hit("CloseButton", 0.922, 0.014, 0.056, 0.088))
parts.append('\t\t\t<!-- Title art is the banner; hide duplicate text in Lua. -->')

# Left recipes region
parts.append('\t\t\t<Widget type="Widget" skin="PanelEmpty" position_real="0.028 0.226 0.560 0.508" name="PanelRecipes">')
parts.append('\t\t\t\t<Property key="NeedMouse" value="false"/>')
parts.append('\t\t\t\t<Property key="InheritsPick" value="true"/>')
parts.append(indent_block(art("ArtCraftPanel", 0, 0, 1, 1, "panel_craftable_gold_blank.png", keep=False), "\t"))

# Categories inside left panel
cats = [
	("ArtCatAll", "CatAll", "category_all_gold.png", 0.018, 0.018, 0.128, 0.100),
	("ArtCatTool", "CatTool", "category_tools.png", 0.154, 0.018, 0.154, 0.100),
	("ArtCatBlock", "CatBlock", "category_blocks.png", 0.314, 0.018, 0.154, 0.100),
	("ArtCatInteractive", "CatInteractive", "category_interactive.png", 0.474, 0.018, 0.186, 0.100),
	("ArtCatPart", "CatPart", "category_parts.png", 0.666, 0.018, 0.156, 0.100),
	("ArtCatConsumable", "CatConsumable", "category_consumable.png", 0.828, 0.018, 0.154, 0.100),
]
for artn, hitn, img, x, y, w, h in cats:
	parts.append(indent_block(art(artn, x, y, w, h, img, keep=False), "\t"))
	parts.append(indent_block(hit(hitn, x, y, w, h), "\t"))

# One grid parent: slot art, then Cell with Icon child (same pattern as the station).
gx, gy, gw, gh = 0.018, 0.130, 0.930, 0.840
parts.append('\t\t\t\t<Widget type="Widget" skin="PanelEmpty" position_real="%s %s %s %s" name="ArtSlots">' % (f(gx), f(gy), f(gw), f(gh)))
parts.append('\t\t\t\t\t<Property key="NeedMouse" value="true"/>')
parts.append('\t\t\t\t\t<Property key="InheritsPick" value="true"/>')
sw, sh, sx, sy = 0.155, 0.230, 0.164, 0.248
x0, y0 = 0.008, 0.010
for i in range(CELLS):
	c = i % COLS
	r = i // COLS
	x = x0 + c * sx
	y = y0 + r * sy
	parts.append(indent_block(art("ArtSlot%d" % i, x, y, sw, sh, "slot_empty.png", keep=True), "\t\t"))
	parts.append('\t\t\t\t\t<Widget type="Button" skin="PanelEmpty" position_real="%s %s %s %s" name="Cell%d">' % (f(x), f(y), f(sw), f(sh), i))
	parts.append('\t\t\t\t\t\t<Property key="Caption" value=""/>')
	parts.append('\t\t\t\t\t\t<Property key="FontName" value="SM_Button"/>')
	parts.append('\t\t\t\t\t\t<Property key="NeedMouse" value="true"/>')
	parts.append('\t\t\t\t\t\t<Widget type="ImageBox" skin="ImageBox" position_real="0.14 0.12 0.72 0.72" name="Icon%d">' % i)
	parts.append('\t\t\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
	parts.append('\t\t\t\t\t\t\t<Property key="NeedKey" value="false"/>')
	parts.append('\t\t\t\t\t\t\t<Property key="ImageKeepAspect" value="true"/>')
	parts.append('\t\t\t\t\t\t</Widget>')
	parts.append('\t\t\t\t\t</Widget>')
parts.append('\t\t\t\t</Widget>')
parts.append('\t\t\t\t<Widget type="Widget" skin="PanelEmpty" position_real="%s %s %s %s" name="PanelCells">' % (f(gx), f(gy), f(gw), f(gh)))
parts.append('\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
parts.append('\t\t\t\t\t<Property key="InheritsPick" value="true"/>')
parts.append('\t\t\t\t</Widget>')
parts.append(indent_block(art("ArtScrollRecipes", 0.958, 0.140, 0.036, 0.760, "scrollbar_recipes.png", keep=False), "\t"))
parts.append('\t\t\t\t<Widget type="ScrollBar" skin="SliderV" position_real="0.958 0.140 0.036 0.760" name="ScrollBar">')
parts.append('\t\t\t\t\t<Property key="NeedMouse" value="true"/>')
parts.append('\t\t\t\t</Widget>')
parts.append('\t\t\t</Widget>')

# Right remote queue
parts.append('\t\t\t<Widget type="Widget" skin="PanelEmpty" position_real="0.600 0.226 0.372 0.575" name="PanelQueue">')
parts.append('\t\t\t\t<Property key="NeedMouse" value="false"/>')
parts.append('\t\t\t\t<Property key="InheritsPick" value="true"/>')
parts.append(indent_block(art("ArtRemoteQueue", 0, 0, 1, 1, "panel_remote_queue_gold_blank.png", keep=False), "\t"))
qx, qy, qw, qh = 0.040, 0.105, 0.880, 0.820
parts.append('\t\t\t\t<Widget type="Widget" skin="PanelEmpty" position_real="%s %s %s %s" name="ArtQRows">' % (f(qx), f(qy), f(qw), f(qh)))
parts.append('\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
row_h = 0.155
row_gap = 0.162
for i in range(QUEUE_ROWS):
	y = i * row_gap
	parts.append(indent_block(art("ArtQRow%d" % i, 0, y, 1, row_h, "queue_row_empty.png", keep=False, visible=False), "\t\t"))
	parts.append('\t\t\t\t\t<Widget type="Button" skin="PanelEmpty" position_real="%s %s %s %s" name="QCell%d">' % (
		f(0.03), f(y + 0.02), f(0.16), f(row_h - 0.04), i))
	parts.append('\t\t\t\t\t\t<Property key="Caption" value=""/>')
	parts.append('\t\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
	parts.append('\t\t\t\t\t\t<Widget type="ImageBox" skin="ImageBox" position_real="0.08 0.08 0.84 0.84" name="QIcon%d">' % i)
	parts.append('\t\t\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
	parts.append('\t\t\t\t\t\t\t<Property key="NeedKey" value="false"/>')
	parts.append('\t\t\t\t\t\t\t<Property key="ImageKeepAspect" value="true"/>')
	parts.append('\t\t\t\t\t\t</Widget>')
	parts.append('\t\t\t\t\t</Widget>')
	parts.append(indent_block(text("QName%d" % i, 0.22, y + 0.01, 0.55, 0.07, "", "Left VCenter"), "\t\t"))
	parts.append(indent_block(text("QAmt%d" % i, 0.22, y + 0.07, 0.55, 0.07, "", "Left VCenter"), "\t\t"))
	parts.append(indent_block(art("ArtQX%d" % i, 0.86, y + 0.035, 0.12, 0.090, "button_remove_red.png"), "\t\t"))
parts.append('\t\t\t\t</Widget>')
parts.append('\t\t\t\t<Widget type="Widget" skin="PanelEmpty" position_real="%s %s %s %s" name="PanelQHits">' % (f(qx), f(qy), f(qw), f(qh)))
parts.append('\t\t\t\t\t<Property key="NeedMouse" value="true"/>')
for i in range(QUEUE_ROWS):
	y = i * row_gap
	parts.append(indent_block(hit("QCancel%d" % i, 0.86, y + 0.035, 0.12, 0.090), "\t\t"))
parts.append('\t\t\t\t</Widget>')
parts.append(indent_block(text("QueueLimit", 0.40, 0.930, 0.56, 0.055, "QUEUE LIMIT: 6", "Right VCenter"), "\t"))
parts.append('\t\t\t</Widget>')

# Selected recipe + amount
parts.append('\t\t\t<Widget type="Widget" skin="PanelEmpty" position_real="0.028 0.742 0.365 0.185" name="PanelSelected">')
parts.append('\t\t\t\t<Property key="NeedMouse" value="false"/>')
parts.append(indent_block(art("ArtSelected", 0, 0, 1, 1, "selected_recipe_blank.png", keep=False), "\t"))
parts.append('\t\t\t\t<Widget type="Button" skin="PanelEmpty" position_real="0.03 0.16 0.22 0.70" name="SelCell">')
parts.append('\t\t\t\t\t<Property key="Caption" value=""/>')
parts.append('\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
parts.append('\t\t\t\t\t<Widget type="ImageBox" skin="ImageBox" position_real="0.08 0.08 0.84 0.84" name="SelIcon">')
parts.append('\t\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
parts.append('\t\t\t\t\t\t<Property key="NeedKey" value="false"/>')
parts.append('\t\t\t\t\t\t<Property key="ImageKeepAspect" value="true"/>')
parts.append('\t\t\t\t\t</Widget>')
parts.append('\t\t\t\t</Widget>')
parts.append(indent_block(text("SelName", 0.26, 0.08, 0.70, 0.22, "SELECT A RECIPE", "Left VCenter", "SM_HeaderSmall"), "\t"))
for i in range(3):
	ix = 0.28 + i * 0.23
	parts.append(indent_block(art("ArtIng%d" % i, ix, 0.38, 0.20, 0.42, "ingredient_slot_empty.png", keep=True), "\t"))
	parts.append('\t\t\t\t<Widget type="Button" skin="PanelEmpty" position_real="%s %s %s %s" name="IngCell%d">' % (
		f(ix + 0.02), f(0.40), f(0.16), f(0.26), i))
	parts.append('\t\t\t\t\t<Property key="Caption" value=""/>')
	parts.append('\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
	parts.append('\t\t\t\t\t<Widget type="ImageBox" skin="ImageBox" position_real="0.08 0.08 0.84 0.84" name="IngIcon%d">' % i)
	parts.append('\t\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
	parts.append('\t\t\t\t\t\t<Property key="NeedKey" value="false"/>')
	parts.append('\t\t\t\t\t\t<Property key="ImageKeepAspect" value="true"/>')
	parts.append('\t\t\t\t\t</Widget>')
	parts.append('\t\t\t\t</Widget>')
	parts.append(indent_block(text("IngHave%d" % i, ix, 0.78, 0.20, 0.18, "", "Center"), "\t"))
parts.append('\t\t\t</Widget>')

parts.append('\t\t\t<Widget type="Widget" skin="PanelEmpty" position_real="0.400 0.742 0.198 0.185" name="PanelAmount">')
parts.append('\t\t\t\t<Property key="NeedMouse" value="false"/>')
parts.append(indent_block(art("ArtAmount", 0, 0, 1, 1, "panel_amount_full.png", keep=False), "\t"))
parts.append(indent_block(art("ArtMinus", 0.08, 0.38, 0.22, 0.42, "button_amount_minus.png"), "\t"))
parts.append(indent_block(art("ArtPlus", 0.70, 0.38, 0.22, 0.42, "button_amount_plus.png"), "\t"))
parts.append(indent_block(art("ArtQty", 0.34, 0.38, 0.32, 0.42, "amount_value.png"), "\t"))
parts.append(indent_block(text("SelectedQty", 0.34, 0.42, 0.32, 0.36, "1", "Center", "SM_HeaderSmall"), "\t"))
parts.append(indent_block(hit("BtnMinus", 0.08, 0.38, 0.22, 0.42), "\t"))
parts.append(indent_block(hit("BtnPlus", 0.70, 0.38, 0.22, 0.42), "\t"))
parts.append('\t\t\t</Widget>')

# Footer actions
parts.append(art("ArtAddQueue", 0.605, 0.812, 0.220, 0.076, "button_add_remote_queue_gold.png", keep=False))
parts.append(art("ArtSend", 0.832, 0.812, 0.161, 0.076, "button_send_to_crafter.png", keep=False))
parts.append(hit("BtnAddQueue", 0.605, 0.812, 0.220, 0.076))
parts.append(hit("BtnSend", 0.832, 0.812, 0.161, 0.076))

parts.append(art("ArtPrio1", 0.430, 0.905, 0.042, 0.055, "button_station_1_gold.png"))
parts.append(art("ArtPrio2", 0.478, 0.905, 0.040, 0.055, "button_station_2.png"))
parts.append(art("ArtPrio3", 0.524, 0.905, 0.040, 0.055, "button_station_3.png"))
parts.append(art("ArtPrio4", 0.570, 0.905, 0.040, 0.055, "button_station_4.png"))
parts.append(art("ArtPair", 0.618, 0.905, 0.094, 0.055, "button_pair_gold.png", keep=False))
parts.append(art("ArtClear", 0.840, 0.905, 0.150, 0.055, "button_clear_queue.png", keep=False))
parts.append(hit("BtnPrio1", 0.430, 0.905, 0.042, 0.055))
parts.append(hit("BtnPrio2", 0.478, 0.905, 0.040, 0.055))
parts.append(hit("BtnPrio3", 0.524, 0.905, 0.040, 0.055))
parts.append(hit("BtnPrio4", 0.570, 0.905, 0.040, 0.055))
parts.append(hit("BtnPair", 0.618, 0.905, 0.094, 0.055))
parts.append(hit("BtnClear", 0.840, 0.905, 0.150, 0.055))
parts.append(text("PairStatus", 0.028, 0.948, 0.390, 0.040, "", "Left VCenter"))

parts.append('\t\t</Widget>')
parts.append('\t</Widget>')
parts.append('</MyGUI>')

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
	fh.write("\n".join(parts) + "\n")
print("wrote", OUT)
