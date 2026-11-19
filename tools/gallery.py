# CurseForge gallery images (1280x720) and the GitHub social preview (1280x640) from the owner's
# in-game screenshots (English addon texts), in the gallery style of the Forever series.
# Usage: python3 tools/gallery.py <work dir>/   (needs Pillow and the Inter fonts; not in the zip)
# The work dir holds images/<name>.jpg and the icon as icon.png; the results go to <work dir>/out/.
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont
BASE = sys.argv[1].rstrip("/") + "/" if len(sys.argv) > 1 else "./"
W, H = 1280, 720
FONTS = "/usr/share/fonts/opentype/inter/"
HEAD, SUBF, NAME = FONTS + "InterDisplay-Bold.otf", FONTS + "Inter-Medium.otf", FONTS + "Inter-SemiBold.otf"
TOP, BOTTOM = (0x0D, 0x10, 0x18), (0x14, 0x1B, 0x2B)
ACCENT, WHITE, SUB = (0x9B, 0x5C, 0xFF), (246, 244, 252), (0xA9, 0xB6, 0xD3)

def background(h, glow_box):
    bg = Image.new("RGB", (W, h))
    d = ImageDraw.Draw(bg)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (W, y)], fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    # a glow in the addon's colour behind the main shot
    g = Image.new("L", (W, h), 0)
    x0, y0, x1, y1 = glow_box
    ImageDraw.Draw(g).ellipse((x0 - 60, y0 - 40, x1 + 60, y1 + 40), fill=95)
    g = g.filter(ImageFilter.GaussianBlur(90))
    return Image.composite(Image.new("RGB", (W, h), ACCENT), bg, g)

def shot(name, box, scale, blur=()):
    im = Image.open(BASE + "images/%s.jpg" % name).convert("RGB")
    for b in blur: # names of real characters
        im.paste(im.crop(b).filter(ImageFilter.GaussianBlur(7)), b[:2])
    im = im.crop(box)
    return im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)

def framed(bg, im, x, y):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), 18, fill=255)
    sh = Image.new("RGBA", (im.width + 60, im.height + 60), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((30, 38, im.width + 30, im.height + 38), 18, fill=(0, 0, 0, 170))
    sh = sh.filter(ImageFilter.GaussianBlur(14))
    bg.paste(sh, (x - 30, y - 30), sh)
    bg.paste(im, (x, y), mask)
    ImageDraw.Draw(bg).rounded_rectangle((x - 1, y - 1, x + im.width, y + im.height), 19, outline=ACCENT, width=3)

def brand(bg, h):
    icon = Image.open(BASE + "icon.png").convert("RGBA").resize((36, 36), Image.LANCZOS)
    bg.paste(icon, (40, h - 56), icon)
    ImageDraw.Draw(bg).text((86, h - 48), "Last Breath Forever", font=ImageFont.truetype(NAME, 18), fill=WHITE)

def make(out, title, subtitle, im, feature=False):
    size = 84 if feature else 58
    head_h = 40 + size + (44 if subtitle else 18)
    x, y = (W - im.width) // 2, head_h + (H - 70 - head_h - im.height) // 2
    bg = background(H, (x, y, x + im.width, y + im.height))
    d = ImageDraw.Draw(bg)
    d.text((56, 34), title, font=ImageFont.truetype(HEAD, size), fill=WHITE)
    if subtitle:
        d.text((58, 40 + size + 6), subtitle, font=ImageFont.truetype(SUBF, 26), fill=SUB)
    framed(bg, im, x, y)
    brand(bg, H)
    bg.save(BASE + "out/" + out, optimize=True)

def social(im):
    h = 640
    bg = background(h, (80, 40, 1200, 600))
    d = ImageDraw.Draw(bg)
    av = Image.open(BASE + "icon.png").convert("RGBA").resize((200, 200), Image.LANCZOS)
    bg.paste(av, (64, 48), av)
    d.text((300, 62), "Last Breath Forever", font=ImageFont.truetype(HEAD, 72), fill=WHITE)
    d.text((304, 160), "About how many seconds each enemy has left", font=ImageFont.truetype(SUBF, 30), fill=SUB)
    d.text((304, 202), "Target, focus and nameplates  ·  WoW: Forever", font=ImageFont.truetype(SUBF, 30), fill=SUB)
    framed(bg, im, (W - im.width) // 2, 300)
    bg.save(BASE + "out/social-preview.png", optimize=True)

# 19 Nov, Razorfen Kraul (priest 34). Crops keep the enemies, the frames and the seconds; party
# names below the crops are cut off, the target-of-target frame is blurred
pull = shot("172220", (800, 175, 1300, 330), 2.4)
make("01_nameplates.png", "Which mob dies first?", None, pull, feature=True)
pack = shot("172254", (880, 175, 1350, 345), 2.2, [(1212, 208, 1305, 242), (1200, 318, 1292, 345)])
make("02_boss_and_adds.png", "Switch targets, keep the seconds",
     "Every enemy of the pull is counted, also while it is not your target.", pack)
tgt = shot("171701", (1050, 200, 1290, 330), 2.6, [(1205, 315, 1290, 335)])
make("03_time_to_die.png", "Know when your target dies",
     "About how many seconds it has left, right next to its frame.", tgt)
# 17 Nov, the Stockade: target in red and the focus frame (the in-game icon is the old one)
both = shot("41", (1040, 205, 1560, 360), 2.0, [(1210, 321, 1282, 333), (1466, 346, 1538, 358)])
make("04_last_seconds_focus.png", "Save the cooldown for the end",
     "The last seconds turn red. A second frame for your focus: healers keep the boss there.", both)
opts = shot("165052", (0, 178, 1110, 630), 1.06)
make("05_settings.png", "Target, focus, nameplates: your way", None, opts)
social(shot("172220", (760, 172, 1300, 335), 1.2))
