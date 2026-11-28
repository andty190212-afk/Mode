"""Approximate picture of the NPC avatars (R15 proportions + the same uniform details
as NPCUtil.lua). Schematic only - real avatars are loaded by Roblox at runtime."""
import json, math, subprocess, sys, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else "npc_mockup.png"
TMP = "/tmp/npc_mock"
os.makedirs(TMP, exist_ok=True)

I = [1,0,0, 0,1,0, 0,0,1]
VERT = [0,-1,0, 1,0,0, 0,0,1]  # rotate X axis to vertical (cylinder)
def rz(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return [c,-s,0, s,c,0, 0,0,1]

def part(parts, pos, size, color, shape="Block", r=I, neon=False):
    parts.append({"p": list(pos), "r": r, "s": list(size), "c": [c/255 for c in color], "t": 0, "shape": shape, "n": "", "neon": neon})

SKIN = (234,192,134); WHITE=(248,248,245); BLACK=(25,25,28)

def body(parts, skin, torso, arms, legs, x=0):
    P = lambda px, py, pz=0: (x+px, py, pz)
    for sx in (-0.5, 0.5):
        part(parts, P(sx, 0.15, -0.1), (0.95, 0.3, 1.15), legs)       # foot
        part(parts, P(sx, 0.9), (0.95, 1.2, 0.95), legs)             # lower leg
        part(parts, P(sx, 2.1), (0.98, 1.2, 0.98), legs)             # upper leg
    part(parts, P(0, 2.9), (2, 0.4, 1), legs)                        # lower torso
    part(parts, P(0, 3.9), (2, 1.6, 1), torso)                       # upper torso
    for sx in (-1.5, 1.5):
        part(parts, P(sx, 4.1), (0.95, 1.2, 0.95), arms)
        part(parts, P(sx, 3.0), (0.92, 1.0, 0.92), arms)
        part(parts, P(sx, 2.35), (0.9, 0.35, 0.9), skin)             # hand
    part(parts, P(0, 5.35), (1.25, 1.25, 1.25), skin, "Cylinder", VERT)  # classic round head
    # face
    for ex in (-0.22, 0.22):
        part(parts, P(ex, 5.5, -0.63), (0.14, 0.26, 0.05), BLACK)
    part(parts, P(0, 5.12, -0.63), (0.42, 0.08, 0.05), (90,40,40))
    for ex in (-0.13, 0.13):
        part(parts, P(ex, 5.08, -0.63), (0.18, 0.08, 0.05), (90,40,40), r=rz(25 if ex < 0 else -25))
    return P

def hair(parts, P, color, style):
    hs = 1.25
    if style == 1:
        part(parts, P(0, 5.35 + hs*0.3, hs*0.04), (hs*1.08, hs*0.55, hs*1.1), color, "Ball")
    elif style == 2:
        part(parts, P(0, 5.35 + hs*0.28, hs*0.05), (hs*1.1, hs*0.6, hs*1.12), color, "Ball")
        part(parts, P(0, 5.35 - hs*0.1, hs*0.45), (hs*1.0, hs*1.0, hs*0.35), color)
    elif style == 3:
        part(parts, P(0, 5.35 + hs*0.32, hs*0.04), (hs*1.06, hs*0.5, hs*1.08), color, "Ball")
        part(parts, P(0, 5.35 + hs*0.55, hs*0.35), (hs*0.45,)*3, color, "Ball")
    elif style == 4:
        part(parts, P(0, 5.35 + hs*0.34, 0), (hs*1.08, hs*0.45, hs*1.08), color, "Ball")
        part(parts, P(0, 5.35 + hs*0.28, -hs*0.6), (hs*0.8, 0.08, hs*0.5), color)

def tophat(parts, P, color):
    hs = 1.25
    part(parts, P(0, 5.35 + hs*0.5), (0.12, hs*1.5, hs*1.5), color, "Cylinder", VERT)
    part(parts, P(0, 5.35 + hs*0.9), (hs*0.75, hs*0.95, hs*0.95), color, "Cylinder", VERT)
    part(parts, P(0, 5.35 + hs*0.62), (0.15, hs*0.97, hs*0.97), (150,20,40), "Cylinder", VERT)

def uniform(parts, P, shirtFront=None, bow=None, apron=None, scarf=None):
    front = -(0.5 + 0.03)
    if shirtFront:
        part(parts, P(0, 3.92, front), (0.6, 1.44, 0.06), shirtFront)
        for i in (1,2,3):
            part(parts, P(0, 3.9 + 0.4 - i*0.29, front-0.04), (0.12,0.12,0.05), (60,60,60), "Ball")
    if bow:
        part(parts, P(-0.15, 3.9 + 0.67, front-0.05), (0.28,0.2,0.08), bow, r=rz(15))
        part(parts, P(0.15, 3.9 + 0.67, front-0.05), (0.28,0.2,0.08), bow, r=rz(-15))
    if apron:
        part(parts, P(0, 3.9 - 0.19, front), (1.6, 1.12, 0.06), apron)
        part(parts, P(0, 2.9 - 0.45, front-0.02), (1.8, 1.5, 0.06), apron)
        for i in (1,2,3):
            for x in (-0.25, 0.25):
                part(parts, P(x, 3.9 + 0.64 - i*0.22, front-0.05), (0.12,0.12,0.05), BLACK, "Ball")
    if scarf:
        part(parts, P(0, 3.9 + 0.75, 0), (0.9, 0.22, 1.05), scarf)

def chefhat(parts, P):
    hs = 1.25
    part(parts, P(0, 5.35 + hs*0.62), (hs*0.45, hs*1.02, hs*1.02), WHITE, "Cylinder", VERT)
    part(parts, P(0, 5.35 + hs*1.15), (hs*1.35, hs*1.05, hs*1.35), WHITE, "Ball")

chars = []
def make(name, build):
    parts = []
    build(parts)
    chars.append((name, parts))

def cook(parts):
    P = body(parts, SKIN, WHITE, WHITE, (45,45,50)); uniform(parts, P, apron=WHITE, scarf=(210,40,40)); chefhat(parts, P)
def waiter(parts):
    P = body(parts, (198,134,66), BLACK, WHITE, BLACK); uniform(parts, P, shirtFront=WHITE, bow=BLACK); hair(parts, P, (20,20,20), 1)
def bartender(parts):
    P = body(parts, (255,220,177), (120,25,40), WHITE, BLACK); uniform(parts, P, shirtFront=WHITE, bow=BLACK); hair(parts, P, (160,60,30), 3)
def guest1(parts):
    P = body(parts, (255,205,148), (52,120,220), (52,120,220), (40,50,80)); hair(parts, P, (90,60,30), 4)
def guest2(parts):
    P = body(parts, (141,85,36), (230,110,160), (141,85,36), (150,140,120)); hair(parts, P, (40,25,15), 2)
def vip(parts):
    P = body(parts, (234,192,134), (30,30,40), (30,30,40), (30,30,40)); hair(parts, P, (220,190,110), 1); tophat(parts, P, (212,175,55))

make("Повар (NPC)", cook)
make("Официант (NPC)", waiter)
make("Бармен (NPC)", bartender)
make("Гость", guest1)
make("Гостья", guest2)
make("VIP-гость", vip)

tiles = []
for i, (name, parts) in enumerate(chars):
    js = f"{TMP}/c{i}.json"; png = f"{TMP}/c{i}.png"
    json.dump(parts, open(js, "w"))
    subprocess.run([sys.executable, os.path.join(HERE, "render.py"), js, png, "15", "8", "0.95", "0", "3.3", "0"], check=True, capture_output=True)
    tiles.append((name, Image.open(png)))

W, H = 1400, 900
cw = 460
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 30)
small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
sheet = Image.new("RGB", (cw*3, 2*520 + 70), (135, 190, 235))
d = ImageDraw.Draw(sheet)
for i, (name, img) in enumerate(tiles):
    bg = Image.new("RGB", img.size, (135, 190, 235))
    from PIL import ImageChops
    bbox = ImageChops.difference(img.convert("RGB"), bg).getbbox()
    cx, cy = (bbox[0] + bbox[2]) // 2, (bbox[1] + bbox[3]) // 2
    half = max(bbox[3] - bbox[1], bbox[2] - bbox[0]) // 2 + 20
    crop = img.crop((cx - half, cy - half, cx + half, cy + half)).resize((440, 440))
    x, y = (i % 3) * cw, 50 + (i // 3) * 520
    sheet.paste(crop, (x + 10, y + 45))
    tw = d.textlength(name, font=font)
    d.text((x + (cw - tw)/2, y), name, fill=(20, 25, 40), font=font)
note = "Примерная схема (упрощённый рендер). В Roblox тело, лицо и освещение будут гладкими и красивее."
d.text((20, sheet.height - 40), note, fill=(20, 25, 40), font=small)
sheet.save(OUT)
print("saved", OUT)
