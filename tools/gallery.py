# CurseForge gallery images (1280x720), the GitHub social preview (1280x640) and the README
# images, from the owner's in-game screenshots (English addon texts).
# Usage: python3 tools/gallery.py <work dir>/   (needs Pillow; not part of the addon zip)
# The work dir holds images/<n>.jpg and the icon as icon.png; the results go to gallery/out/.
# Same layout as Full Mana Forever's gallery, in this addon's colour.
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont
BASE = sys.argv[1].rstrip("/") + "/" if len(sys.argv) > 1 else "./"
W, H = 1280, 720
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
GOLD, ACCENT, WHITE, SUB = (242, 201, 76), (200, 90, 235), (246, 240, 252), (196, 170, 214)
FOOT = "Last Breath Forever  ·  WoW: Forever"

def background(h=H):
    bg = Image.new("RGB", (W, h))
    d = ImageDraw.Draw(bg)
    for y in range(h):
        t = y / h
        d.line([(0, y), (W, y)], fill=(int(22 + 14 * t), int(12 + 8 * t), int(34 + 26 * t)))
    glow = Image.new("L", (W, h), 0)
    ImageDraw.Draw(glow).ellipse((W * 0.15, h * 0.25, W * 0.85, h * 1.25), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    return Image.composite(Image.new("RGB", (W, h), (110, 40, 140)), bg, glow)

def shot(n, box, scale, blur=()):
    im = Image.open(BASE + "images/%d.jpg" % n).convert("RGB")
    # names of real characters are blurred out
    for b in blur:
        im.paste(im.crop(b).filter(ImageFilter.GaussianBlur(6)), b[:2])
    im = im.crop(box)
    return im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)

def rounded(im, r=14):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), r, fill=255)
    return mask

def panel(bg, im, x, y):
    d = ImageDraw.Draw(bg)
    sh = Image.new("RGBA", (im.width + 40, im.height + 40), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((20, 24, im.width + 20, im.height + 24), 16, fill=(0, 0, 0, 150))
    bg.paste(sh.filter(ImageFilter.GaussianBlur(10)), (x - 20, y - 20), sh.filter(ImageFilter.GaussianBlur(10)))
    bg.paste(im, (x, y), rounded(im))
    d.rounded_rectangle((x - 2, y - 2, x + im.width + 1, y + im.height + 1), 15, outline=ACCENT, width=2)

def make(out, title, subtitle, im, top=None):
    bg = background()
    d = ImageDraw.Draw(bg)
    d.text((60, 44), title, font=ImageFont.truetype(BOLD, 40), fill=WHITE)
    d.text((62, 100), subtitle, font=ImageFont.truetype(REG, 22), fill=SUB)
    if top is None:
        top = 150 + (H - 150 - 50 - im.height) // 2
    panel(bg, im, (W - im.width) // 2, top)
    foot = ImageFont.truetype(REG, 16)
    d.text((W - 40 - d.textlength(FOOT, font=foot), H - 36), FOOT, font=foot, fill=(150, 120, 170))
    bg.save(BASE + "gallery/out/" + out, optimize=True)

def social(im):
    bg = background(640)
    d = ImageDraw.Draw(bg)
    av = Image.open(BASE + "icon.png").convert("RGBA").resize((230, 230), Image.LANCZOS)
    bg.paste(av, (70, 50), av)
    d.text((340, 78), "Last Breath Forever", font=ImageFont.truetype(BOLD, 64), fill=WHITE)
    d.text((344, 164), "Time to die for WoW Forever: about how", font=ImageFont.truetype(REG, 30), fill=SUB)
    d.text((344, 204), "many seconds your target has left", font=ImageFont.truetype(REG, 30), fill=SUB)
    panel(bg, im, (W - im.width) // 2, 330)
    bg.save(BASE + "gallery/out/social-preview.png", optimize=True)

# 40, 41: Stockade, priest 24; the target-of-target frames carry the player's name
NAMES40 = [(1210, 321, 1282, 333)]
NAMES41 = [(1210, 321, 1282, 333), (1466, 346, 1538, 358)]
hero = shot(40, (1040, 205, 1320, 345), 2.8, NAMES40)
make("01_time_to_die.png", "Time to die, live in combat",
     "About how many seconds your target has left, right next to its frame.", hero)
both = shot(41, (1040, 205, 1560, 360), 2.15, NAMES41)
make("02_last_seconds_focus.png", "The last seconds in red, the focus too",
     "Red when your cooldowns matter. A second frame for your focus: healers keep the boss there.", both)
opts = shot(39, (672, 150, 1412, 545), 1.32)
make("03_settings.png", "Settings for the target and the focus",
     "When to show, when to turn red, size, icon, only elites and bosses, 9 languages.", opts)
social(shot(41, (1040, 205, 1560, 360), 1.05, NAMES41))
