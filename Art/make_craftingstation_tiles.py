# Status-light tiles for the crafting station.
# Each lamp is a 4-frame horizontal strip so one setUvFrameIndex can drive
# both lamps independently:
#   frame = (storageFull and 2 or 0) + (wirelessOn and 1 or 0)
# light_01 (top / storage):  G G R R
# light_02 (bot / wireless): R G R G
import struct
import zlib
import os

DST = r"C:\Coding Projects\RemasteredFrameworkSystems\Objects\Textures\craftstation"
os.makedirs(DST, exist_ok=True)

TILE = 64
GREEN = (0, 255, 40)
RED = (255, 30, 20)
MAGENTA = (255, 0, 255)


def chunk(tag, data):
    c = struct.pack(">I", len(data)) + tag + data
    c += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    return c


def png_bytes(pixels, width, height):
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = b""
    i = 0
    for y in range(height):
        raw += b"\x00"
        for x in range(width):
            raw += bytes(pixels[i])
            i += 1
    idat = zlib.compress(raw, 9)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", idat)
        + chunk(b"IEND", b"")
    )


def write_solid(name, rgb, width=TILE, height=TILE):
    pixels = [rgb] * (width * height)
    path = os.path.join(DST, name)
    with open(path, "wb") as f:
        f.write(png_bytes(pixels, width, height))
    print("WROTE", path, os.path.getsize(path), "bytes")


def write_strip(name, frames):
    width = TILE * len(frames)
    height = TILE
    pixels = []
    for y in range(height):
        for x in range(width):
            pixels.append(frames[x // TILE])
    path = os.path.join(DST, name)
    with open(path, "wb") as f:
        f.write(png_bytes(pixels, width, height))
    print("WROTE", path, os.path.getsize(path), "bytes")


write_solid("craftingstation_light01_dif.png", GREEN)
write_solid("craftingstation_light02_dif.png", RED)
write_solid("craftingstation_light_asg.png", MAGENTA)
write_solid("craftingstation_screen_dif.png", (30, 34, 44))
print("RFS_LIGHT_TILES_OK")
