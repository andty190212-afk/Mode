"""Contact sheet of NPCs exported by npc_real.luau (real NPCUtil code)."""
import json, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont, ImageChops
HERE = os.path.dirname(os.path.abspath(__file__))
src = sys.argv[1]; out = sys.argv[2]
names = json.load(open(os.path.join(src, "index.json")))
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 17)
small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
cols, cw, ch = 6, 260, 330
rows = (len(names) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cw, rows * ch + 50), (135, 190, 235))
d = ImageDraw.Draw(sheet)
for i, name in enumerate(names):
    js = os.path.join(src, f"npc{i+1}.json"); png = os.path.join(src, f"npc{i+1}.png")
    subprocess.run([sys.executable, os.path.join(HERE, "render.py"), js, png, "18", "6", "1.0", "0", "3", "0"], check=True, capture_output=True)
    img = Image.open(png).convert("RGB")
    bbox = ImageChops.difference(img, Image.new("RGB", img.size, (135, 190, 235))).getbbox()
    cx, cy = (bbox[0] + bbox[2]) // 2, (bbox[1] + bbox[3]) // 2
    half = max(bbox[3] - bbox[1], bbox[2] - bbox[0]) // 2 + 10
    tile = img.crop((cx - half, cy - half, cx + half, cy + half)).resize((280, 280))
    x, y = (i % cols) * cw, (i // cols) * ch
    sheet.paste(tile.crop((10, 0, 270, 280)), (x, y + 40))
    # wrap label
    words, lines, cur = name.split(" "), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if d.textlength(t, font=font) > cw - 10:
            lines.append(cur); cur = w
        else:
            cur = t
    lines.append(cur)
    for k, ln in enumerate(lines[:2]):
        tw = d.textlength(ln, font=font)
        d.text((x + (cw - tw) / 2, y + 4 + k * 19), ln, fill=(20, 25, 45), font=font)
d.text((15, sheet.height - 35), "Собрано настоящим кодом NPC игры, упрощённый рендер. В Roblox тело и лицо будут гладкими, со светом и тенями.", fill=(20, 25, 45), font=small)
sheet.save(out)
print("saved", out)
