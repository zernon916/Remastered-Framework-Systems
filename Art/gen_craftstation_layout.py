# Generate Rfs_CraftStation.layout
# Art lives on ArtLayer (NeedMouse=false). Real buttons sit on top and stay clickable.
# Never nest controls inside the workshop photo ImageBox.
# Layouts: Gui/menu/layouts  Images: Gui/menu/images
import io

CELLS = 28
COLS = 7
CW, CH = 0.1180, 0.2100
SX, SY = 0.1280, 0.2300
X0, Y0 = 0.0020, 0.0100
QUEUE_ROWS = 4
IMG = "$CONTENT_DATA/Gui/menu/images/craftstation/"
BG = "$CONTENT_DATA/Gui/menu/images/rfs_craftstation_bg.png"


def f(x):
	return ("%.4f" % x).rstrip("0").rstrip(".")


def artbox(name, x, y, w, h, keep=True, image=None):
	tex = ""
	if image:
		if not image.startswith("$"):
			image = IMG + image
		tex = '\t\t\t\t\t<Property key="ImageTexture" value="%s"/>\n' % image
	return (
		'\t\t\t\t<Widget type="ImageBox" skin="ImageBox" position_real="%s %s %s %s" name="%s">\n'
		'\t\t\t\t\t<Property key="NeedMouse" value="false"/>\n'
		'\t\t\t\t\t<Property key="NeedKey" value="false"/>\n'
		'\t\t\t\t\t<Property key="InheritsPick" value="true"/>\n'
		'\t\t\t\t\t<Property key="ImageKeepAspect" value="%s"/>\n'
		'%s'
		'\t\t\t\t</Widget>'
	) % (f(x), f(y), f(w), f(h), name, "true" if keep else "false", tex)


def hitbtn(name, x, y, w, h, caption=""):
	return (
		'\t\t\t\t<Widget type="Button" skin="PanelEmpty" position_real="%s %s %s %s" name="%s">\n'
		'\t\t\t\t\t<Property key="Caption" value="%s"/>\n'
		'\t\t\t\t\t<Property key="FontName" value="SM_Button"/>\n'
		'\t\t\t\t\t<Property key="NeedMouse" value="true"/>\n'
		'\t\t\t\t</Widget>'
	) % (f(x), f(y), f(w), f(h), name, caption)


def cell_art(i):
	c = i % COLS
	r = i // COLS
	x = X0 + c * SX
	y = Y0 + r * SY
	return artbox("ArtCell%d" % i, x, y, CW, CH, image="slot_frame.png")


def cell_hit(i):
	c = i % COLS
	r = i // COLS
	x = X0 + c * SX
	y = Y0 + r * SY
	return (
		'\t\t\t\t<Widget type="Button" skin="PanelEmpty" position_real="%s %s %s %s" name="Cell%d">\n'
		'\t\t\t\t\t<Property key="Caption" value=""/>\n'
		'\t\t\t\t\t<Property key="FontName" value="SM_Button"/>\n'
		'\t\t\t\t\t<Property key="NeedMouse" value="true"/>\n'
		'\t\t\t\t\t<Widget type="ImageBox" skin="ImageBox" position_real="0.14 0.12 0.72 0.72" name="Icon%d">\n'
		'\t\t\t\t\t\t<Property key="NeedMouse" value="false"/>\n'
		'\t\t\t\t\t\t<Property key="NeedKey" value="false"/>\n'
		'\t\t\t\t\t\t<Property key="ImageKeepAspect" value="true"/>\n'
		'\t\t\t\t\t</Widget>\n'
		'\t\t\t\t</Widget>'
	) % (f(x), f(y), f(CW), f(CH), i, i)


def cat_rows():
	# Even pills across the category strip (labels come from kit art where we have it).
	w = 0.158
	gap = 0.008
	labs = [
		("CatAll", ""),
		("CatTool", ""),
		("CatBlock", "BLOCKS"),
		("CatInteractive", "INTERACTIVE"),
		("CatPart", "PARTS"),
		("CatConsumable", "CONSUMABLE"),
	]
	rows = []
	for i, (n, lab) in enumerate(labs):
		rows.append((n, lab, i * (w + gap), w))
	return rows


def cat_art():
	off = {
		"CatAll": "pill_on.png",
		"CatTool": "pill_tools_off.png",
		"CatBlock": "pill_blocks_off.png",
		"CatInteractive": "pill_interactive_off.png",
		"CatPart": "pill_parts_off.png",
		"CatConsumable": "pill_consumable_off.png",
	}
	out = []
	for n, _lab, x, w in cat_rows():
		out.append(artbox("Art" + n, x, 0.000, w, 0.92, keep=False, image=off[n]))
	return "\n".join(out)


def cat_hits():
	out = []
	for n, lab, x, w in cat_rows():
		out.append(hitbtn(n, x, 0.000, w, 0.92, lab))
	return "\n".join(out)


def queue_art():
	out = []
	for i in range(QUEUE_ROWS):
		y = 0.070 + i * 0.160
		out.append(artbox("ArtQIcon%d" % i, 0.000, y, 0.155, 0.140, image="slot_frame.png"))
		out.append(artbox("ArtQTrack%d" % i, 0.185, y + 0.040, 0.520, 0.070, keep=False, image="bar_track.png"))
		for s in range(1, 11):
			fw = 0.520 * s / 10.0
			out.append(artbox("ArtQFill%d_%d" % (i, s), 0.185, y + 0.040, fw, 0.070, keep=False, image="bar_fill.png"))
			kx = 0.185 + fw - 0.030
			out.append(artbox("ArtQKnob%d_%d" % (i, s), kx, y + 0.028, 0.058, 0.094, keep=True, image="bar_knob.png"))
		out.append(artbox("ArtQCancel%d" % i, 0.845, y + 0.010, 0.100, 0.120, image="btn_cancel.png"))
	for i in range(4):
		x = 0.02 + i * 0.245
		out.append(artbox("ArtView%d" % i, x, 0.800, 0.220, 0.170, image="num_%d_off.png" % (i + 1)))
	return "\n".join(out)


def queue_hits():
	out = []
	for i in range(QUEUE_ROWS):
		y = 0.070 + i * 0.160
		out.append('\t\t\t\t<Widget type="ImageBox" skin="ImageBox" position_real="0.018 %s 0.118 0.105" name="QItem%d">' % (f(y + 0.018), i))
		out.append('\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
		out.append('\t\t\t\t\t<Property key="NeedKey" value="false"/>')
		out.append('\t\t\t\t\t<Property key="ImageKeepAspect" value="true"/>')
		out.append('\t\t\t\t</Widget>')
		out.append('\t\t\t\t<Widget type="ProgressBar" skin="CraftbotProgressBar" position_real="0.185 %s 0.520 0.050" name="QBar%d">' % (f(y + 0.048), i))
		out.append('\t\t\t\t\t<Property key="Range" value="100"/>')
		out.append('\t\t\t\t\t<Property key="RangePosition" value="0"/>')
		out.append('\t\t\t\t\t<Property key="NeedKey" value="false"/>')
		out.append('\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
		out.append('\t\t\t\t</Widget>')
		out.append('\t\t\t\t<Widget type="TextBox" skin="TextBox" position_real="0.715 %s 0.125 0.140" name="QCount%d">' % (f(y), i))
		out.append('\t\t\t\t\t<Property key="Caption" value=""/>')
		out.append('\t\t\t\t\t<Property key="FontName" value="SM_Text"/>')
		out.append('\t\t\t\t\t<Property key="TextAlign" value="Center"/>')
		out.append('\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
		out.append('\t\t\t\t</Widget>')
		out.append(hitbtn("QCancel%d" % i, 0.845, y + 0.010, 0.100, 0.120, ""))
	for i in range(4):
		x = 0.02 + i * 0.245
		out.append(hitbtn("ViewSlot%d" % i, x, 0.800, 0.220, 0.170, ""))
	return "\n".join(out)


def bottom_art():
	out = [
		artbox("ArtSelected", 0.010, 0.16, 0.072, 0.68, image="slot_frame.png"),
	]
	for i in range(4):
		x = 0.100 + i * 0.062
		out.append(artbox("ArtIng%d" % i, x, 0.18, 0.055, 0.46, image="slot_frame.png"))
	out.append(artbox("ArtMinus", 0.400, 0.22, 0.028, 0.18, image="btn_minus.png"))
	out.append(artbox("ArtPlus", 0.472, 0.22, 0.028, 0.18, image="btn_plus.png"))
	out.append(artbox("ArtSpeed", 0.350, 0.60, 0.25, 0.22, keep=False, image="bar_track.png"))
	out.append(artbox("ArtBtnCraft", 0.640, 0.28, 0.340, 0.52, keep=False, image="btn_addqueue.png"))
	return "\n".join(out)


def ings():
	out = []
	for i in range(4):
		x = 0.100 + i * 0.062
		out.append('\t\t\t\t<Widget type="ImageBox" skin="ImageBox" position_real="%s 0.24 0.043 0.34" name="IngIcon%d">' % (f(x + 0.006), i))
		out.append('\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
		out.append('\t\t\t\t\t<Property key="NeedKey" value="false"/>')
		out.append('\t\t\t\t\t<Property key="ImageKeepAspect" value="true"/>')
		out.append('\t\t\t\t</Widget>')
		out.append('\t\t\t\t<Widget type="TextBox" skin="TextBox" position_real="%s 0.70 0.055 0.22" name="IngHave%d">' % (f(x), i))
		out.append('\t\t\t\t\t<Property key="Caption" value=""/>')
		out.append('\t\t\t\t\t<Property key="FontName" value="SM_NumberTiny"/>')
		out.append('\t\t\t\t\t<Property key="TextAlign" value="Center"/>')
		out.append('\t\t\t\t\t<Property key="NeedMouse" value="false"/>')
		out.append('\t\t\t\t</Widget>')
	return "\n".join(out)


def upgrade_art():
	out = [
		artbox("ArtUpgHex", 0.004, 0.714, 0.118, 0.286, image="panel_hex.png"),
		artbox("ArtUpgStats", 0.130, 0.714, 0.870, 0.286, keep=False, image="panel_wide.png"),
		artbox("ArtUpgSide", 0.775, 0.020, 0.215, 0.560, keep=False, image="panel_slot.png"),
		artbox("ArtUpgKit", 0.830, 0.145, 0.105, 0.165, image="slot_frame.png"),
		artbox("ArtBtnUpgrade", 0.785, 0.455, 0.195, 0.145, keep=False, image="btn_upgrade_on.png"),
	]
	for i in range(5):
		x = 0.015 + i * 0.128
		slot = "slot_frame.png" if i == 0 else "btn_locked.png"
		out.append(artbox("ArtUpgSlot%d" % i, x, 0.125, 0.115, 0.185, image=slot))
	return "\n".join(out)


xml = """<?xml version="1.0" encoding="UTF-8"?>
<MyGUI type="Layout" version="3.2.0">
	<!-- RFS: layouts=$CONTENT_DATA/Gui/menu/layouts  images=$CONTENT_DATA/Gui/menu/images -->
	<Widget type="Widget" skin="PanelEmpty" position_real="0 0 1 1" name="Root">
		<Property key="NeedKey" value="false"/>
		<Property key="NeedMouse" value="false"/>
		<Property key="InheritsPick" value="true"/>

		<Widget type="Widget" skin="PanelEmpty" position_real="0.03 0.025 0.94 0.95" name="MainPanel">
			<Property key="NeedKey" value="false"/>
			<Property key="NeedMouse" value="false"/>
			<Property key="InheritsPick" value="true"/>

			<Widget type="ImageBox" skin="ImageBox" position_real="0 0 1 1" name="BgPanel">
				<Property key="NeedMouse" value="false"/>
				<Property key="NeedKey" value="false"/>
				<Property key="InheritsPick" value="true"/>
				<Property key="ImageKeepAspect" value="false"/>
				<Property key="ImageTexture" value="$CONTENT_DATA/Gui/menu/images/rfs_craftstation_bg.png"/>

			<Widget type="Widget" skin="PanelEmpty" position_real="0 0 1 1" name="ArtLayer">
				<Property key="NeedMouse" value="false"/>
				<Property key="NeedKey" value="false"/>
				<Property key="InheritsPick" value="true"/>
				%(chrome_art)s
				<Widget type="Widget" skin="PanelEmpty" position_real="0.026 0.140 0.598 0.068" name="ArtCats">
					<Property key="NeedMouse" value="false"/>
					<Property key="InheritsPick" value="true"/>
%(cat_art)s
				</Widget>
				<Widget type="Widget" skin="PanelEmpty" position_real="0.026 0.208 0.598 0.504" name="ArtGrid">
					<Property key="NeedMouse" value="false"/>
					<Property key="InheritsPick" value="true"/>
%(cell_art)s
				</Widget>
				<Widget type="Widget" skin="PanelEmpty" position_real="0.755 0.148 0.218 0.564" name="ArtQueue">
					<Property key="NeedMouse" value="false"/>
					<Property key="InheritsPick" value="true"/>
%(queue_art)s
				</Widget>
				<Widget type="Widget" skin="PanelEmpty" position_real="0.026 0.140 0.942 0.830" name="ArtUpgrade">
					<Property key="Visible" value="false"/>
					<Property key="NeedMouse" value="false"/>
					<Property key="InheritsPick" value="true"/>
%(upgrade_art)s
				</Widget>
			</Widget>

			<Widget type="TextBox" skin="TextBox" position_real="0.030 0.010 0.55 0.062" name="Title">
				<Property key="Caption" value="CRAFTING STATION"/>
				<Property key="FontName" value="SM_HeaderLarge_Wide"/>
				<Property key="TextAlign" value="Left VCenter"/>
			</Widget>
			%(close_hit)s
			%(tab_craft_hit)s
			%(tab_upg_hit)s
			<Widget type="TextBox" skin="TextBox" position_real="0.385 0.084 0.230 0.046" name="StatusLine">
				<Property key="Caption" value="WIRELESS: OFFLINE"/>
				<Property key="FontName" value="SM_Text"/>
				<Property key="TextAlign" value="Left VCenter"/>
			</Widget>
			<Widget type="EditBox" skin="EditBox" position_real="0.655 0.082 0.300 0.050" name="SearchEdit">
				<Property key="Caption" value=""/>
				<Property key="FontName" value="SM_Text"/>
				<Property key="NeedKey" value="true"/>
			</Widget>

			<Widget type="Widget" skin="PanelEmpty" position_real="0.026 0.140 0.598 0.068" name="PanelCats">
				<Property key="NeedMouse" value="false"/>
				<Property key="InheritsPick" value="true"/>
%(cat_hits)s
			</Widget>

			<Widget type="Widget" skin="PanelEmpty" position_real="0.026 0.208 0.598 0.504" name="PanelGrid">
				<Property key="NeedMouse" value="false"/>
				<Property key="InheritsPick" value="true"/>
%(cell_hits)s
			</Widget>
			<Widget type="ScrollBar" skin="InventoryVSlider" position_real="0.626 0.208 0.018 0.504" name="ScrollBar">
				<Property key="Range" value="101"/>
				<Property key="RangePosition" value="0"/>
			</Widget>

			<Widget type="Widget" skin="PanelEmpty" position_real="0.755 0.148 0.218 0.564" name="PanelQueue">
				<Property key="NeedMouse" value="false"/>
				<Property key="InheritsPick" value="true"/>
				<Widget type="TextBox" skin="TextBox" position_real="0.00 0.000 1.00 0.055" name="QueueTitle">
					<Property key="Caption" value="ACTIVE QUEUE"/>
					<Property key="FontName" value="SM_Text"/>
					<Property key="TextAlign" value="Left VCenter"/>
				</Widget>
%(queue_hits)s
				<Widget type="ScrollBar" skin="InventoryVSlider" position_real="0.960 0.070 0.030 0.630" name="QueueScrollBar">
					<Property key="Range" value="1"/>
					<Property key="RangePosition" value="0"/>
				</Widget>
				<Widget type="TextBox" skin="TextBox" position_real="0.00 0.720 1.00 0.055" name="ViewLabel">
					<Property key="Caption" value="MOBILE TABLETS"/>
					<Property key="FontName" value="SM_Text"/>
					<Property key="TextAlign" value="Left VCenter"/>
				</Widget>
			</Widget>

			<Widget type="Widget" skin="PanelEmpty" position_real="0.026 0.720 0.942 0.250" name="PanelBottom">
				<Property key="NeedMouse" value="false"/>
				<Property key="InheritsPick" value="true"/>
%(bottom_art)s
				<Widget type="ImageBox" skin="ImageBox" position_real="0.020 0.24 0.052 0.50" name="SelectedIcon">
					<Property key="NeedMouse" value="false"/>
					<Property key="NeedKey" value="false"/>
					<Property key="ImageKeepAspect" value="true"/>
				</Widget>
%(ings)s
				<Widget type="TextBox" skin="TextBox" position_real="0.355 0.04 0.22 0.16" name="SelectedName">
					<Property key="Caption" value="Select a recipe"/>
					<Property key="FontName" value="SM_Text"/>
					<Property key="TextAlign" value="Center"/>
				</Widget>
%(minus_hit)s
				<Widget type="EditBox" skin="EditBox" position_real="0.432 0.23 0.036 0.16" name="QtyEdit">
					<Property key="Caption" value="1"/>
					<Property key="FontName" value="SM_Text"/>
					<Property key="TextAlign" value="Center"/>
					<Property key="NeedKey" value="true"/>
				</Widget>
%(plus_hit)s
				<Widget type="TextBox" skin="TextBox" position_real="0.345 0.42 0.26 0.16" name="SpeedLabel">
					<Property key="Caption" value="CRAFT SPEED  LOCKED"/>
					<Property key="FontName" value="SM_Text"/>
					<Property key="TextAlign" value="Center"/>
				</Widget>
				<Widget type="ScrollBar" skin="InventoryHSlider" position_real="0.350 0.60 0.25 0.22" name="SpeedBar">
					<Property key="Range" value="5"/>
					<Property key="RangePosition" value="0"/>
					<Property key="NeedKey" value="false"/>
					<Property key="NeedMouse" value="true"/>
				</Widget>
%(craft_hit)s
			</Widget>

			<Widget type="Widget" skin="PanelEmpty" position_real="0.026 0.140 0.942 0.830" name="PanelUpgrade">
				<Property key="Visible" value="false"/>
				<Property key="NeedMouse" value="false"/>
				<Property key="InheritsPick" value="true"/>
				<Widget type="TextBox" skin="TextBox" position_real="0.015 0.020 0.400 0.085" name="TierTitle">
					<Property key="Caption" value="TIER 1 / 5"/>
					<Property key="FontName" value="SM_HeaderLarge_Wide"/>
				</Widget>
%(upg_hits)s
				<Widget type="TextBox" skin="TextBox" position_real="0.110 0.725 0.820 0.070" name="StatsLabel">
					<Property key="Caption" value=""/>
					<Property key="FontName" value="SM_Text"/>
				</Widget>
				<Widget type="TextBox" skin="TextBox" position_real="0.110 0.800 0.820 0.065" name="SpeedPerkLabel">
					<Property key="Caption" value=""/>
					<Property key="FontName" value="SM_Text"/>
				</Widget>
				<Widget type="TextBox" skin="TextBox" position_real="0.785 0.040 0.195 0.080" name="UpgNextTitle">
					<Property key="Caption" value="NEXT TIER"/>
					<Property key="FontName" value="SM_Text"/>
					<Property key="TextAlign" value="Center"/>
				</Widget>
				<Widget type="ImageBox" skin="ImageBox" position_real="0.845 0.165 0.075 0.125" name="UpgKitIcon">
					<Property key="NeedMouse" value="false"/>
					<Property key="NeedKey" value="false"/>
					<Property key="ImageKeepAspect" value="true"/>
				</Widget>
				<Widget type="TextBox" skin="TextBox" position_real="0.785 0.325 0.195 0.100" name="KitsLabel">
					<Property key="Caption" value=""/>
					<Property key="FontName" value="SM_Text"/>
					<Property key="TextAlign" value="Center"/>
				</Widget>
%(upgrade_hit)s
				<Widget type="TextBox" skin="TextBox" position_real="0.110 0.870 0.820 0.080" name="PerksLabel">
					<Property key="Caption" value=""/>
					<Property key="FontName" value="SM_Text"/>
				</Widget>
			</Widget>
			</Widget>
		</Widget>
	</Widget>
</MyGUI>
"""

chrome = "\n".join([
	artbox("ArtClose", 0.940, 0.014, 0.040, 0.050, image="btn_cancel.png"),
	artbox("ArtTabCraft", 0.030, 0.078, 0.155, 0.058, keep=False, image="tab_craft_on.png"),
	artbox("ArtTabUpgrade", 0.195, 0.078, 0.175, 0.058, keep=False, image="tab_upgrades_off.png"),
	artbox("ArtSearch", 0.640, 0.078, 0.325, 0.058, keep=False, image="search.png"),
])

upg_hits = "\n".join(
	hitbtn("UpgSlot%d" % i, 0.015 + i * 0.128, 0.125, 0.115, 0.185, "T%d" % (i + 1))
	for i in range(5)
)

out = r"C:\Coding Projects\RemasteredFrameworkSystems\Gui\menu\layouts\Rfs_CraftStation.layout"
rendered = xml % {
	"chrome_art": chrome,
	"cat_art": cat_art(),
	"cell_art": "\n".join(cell_art(i) for i in range(CELLS)),
	"queue_art": queue_art(),
	"bottom_art": bottom_art(),
	"upgrade_art": upgrade_art(),
	"close_hit": hitbtn("CloseButton", 0.940, 0.014, 0.040, 0.050, ""),
	"tab_craft_hit": hitbtn("TabCraft", 0.030, 0.078, 0.155, 0.058, ""),
	"tab_upg_hit": hitbtn("TabUpgrade", 0.195, 0.078, 0.175, 0.058, ""),
	"cat_hits": cat_hits(),
	"cell_hits": "\n\n".join(cell_hit(i) for i in range(CELLS)),
	"queue_hits": queue_hits(),
	"ings": ings(),
	"minus_hit": hitbtn("BtnMinus", 0.400, 0.22, 0.028, 0.18, ""),
	"plus_hit": hitbtn("BtnPlus", 0.472, 0.22, 0.028, 0.18, ""),
	"craft_hit": hitbtn("BtnCraft", 0.640, 0.28, 0.340, 0.52, ""),
	"upg_hits": upg_hits,
	"upgrade_hit": hitbtn("BtnUpgrade", 0.785, 0.455, 0.195, 0.145, ""),
}
with io.open(out, "w", encoding="utf-8") as fh:
	fh.write(rendered)
print("WROTE", out)
