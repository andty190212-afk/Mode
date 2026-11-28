"""Tiny software renderer for Roblox part dumps (preview only).
usage: python3 render.py parts.json out.png [yaw_deg] [pitch_deg] [zoom] [cx cy cz]"""
import json, sys, math
import numpy as np
from PIL import Image, ImageDraw

parts = json.load(open(sys.argv[1]))
out = sys.argv[2]
yaw = math.radians(float(sys.argv[3]) if len(sys.argv) > 3 else 35)
pitch = math.radians(float(sys.argv[4]) if len(sys.argv) > 4 else 30)
zoom = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
W, H = 1400, 900

def unit_box():
    v = np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)])
    faces = [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
    return v, faces
def unit_wedge():
    # Roblox wedge: slope from top-back (+Z? ) ; wedge occupies y in [-.5,.5], z in [-.5,.5]; high edge at -Z? Roblox: slope faces -Z (front), top edge at back (+Z)
    v = np.array([[-.5,-.5,-.5],[.5,-.5,-.5],[-.5,-.5,.5],[.5,-.5,.5],[-.5,.5,.5],[.5,.5,.5]])
    faces = [(0,1,3,2),(2,3,5,4),(0,4,5,1),(0,2,4),(1,5,3)]
    return v, faces
def unit_cyl(n=14):
    # axis along X
    v = []
    for side in (-.5, .5):
        for i in range(n):
            a = 2*math.pi*i/n
            v.append([side, .5*math.cos(a), .5*math.sin(a)])
    faces = [tuple(range(n)), tuple(range(2*n-1, n-1, -1))]
    for i in range(n):
        j = (i+1) % n
        faces.append((i, j, n+j, n+i))
    return np.array(v), faces
def unit_ball(n=10):
    v = []
    for i in range(n+1):
        th = math.pi*i/n
        for j in range(n):
            ph = 2*math.pi*j/n
            v.append([.5*math.sin(th)*math.cos(ph), .5*math.cos(th), .5*math.sin(th)*math.sin(ph)])
    faces = []
    for i in range(n):
        for j in range(n):
            a = i*n + j; b = i*n + (j+1) % n
            faces.append((a, b, b+n, a+n))
    return np.array(v), faces

SHAPES = {"Block": unit_box(), "Wedge": unit_wedge(), "Cylinder": unit_cyl(), "Ball": unit_ball()}

# camera
pts = np.array([p["p"] for p in parts])
if len(sys.argv) > 8:
    center = np.array([float(sys.argv[6]), float(sys.argv[7]), float(sys.argv[8])])
else:
    center = pts.mean(axis=0)
fwd = np.array([math.cos(pitch)*math.sin(yaw), -math.sin(pitch), math.cos(pitch)*math.cos(yaw)])
right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
up = np.cross(right, fwd)
extent = np.percentile(np.abs((pts - center) @ np.stack([right, up]).T), 98) * 2.4 + 10
scale = min(W, H) / extent * zoom
light = np.array([0.4, 0.8, 0.3]); light /= np.linalg.norm(light)

polys = []
for p in parts:
    if p["t"] >= 0.95: continue
    verts, faces = SHAPES.get(p["shape"], SHAPES["Block"])
    R = np.array(p["r"]).reshape(3, 3)
    S = np.array(p["s"])
    wv = (verts * S) @ R.T + np.array(p["p"])
    base = np.array(p["c"])
    for f in faces:
        fv = wv[list(f)]
        n = np.cross(fv[1] - fv[0], fv[2] - fv[0])
        nn = np.linalg.norm(n)
        if nn < 1e-9: continue
        n /= nn
        if np.dot(n, fwd) > 0:  # make normals face the camera for lighting
            n = -n
        shade = 0.55 + 0.45 * max(0, np.dot(n, light))
        if p["neon"]: shade = 1.15
        col = np.clip(base * shade, 0, 1)
        rel = fv - center
        sx = rel @ right * scale + W / 2
        sy = -(rel @ up) * scale + H / 2
        depth = (rel @ fwd).mean()
        alpha = int(255 * (1 - p["t"] * 0.85))
        polys.append((depth, list(zip(sx, sy)), tuple(int(c * 255) for c in col) + (alpha,)))

polys.sort(key=lambda x: -x[0])
img = Image.new("RGBA", (W, H), (135, 190, 235, 255))
draw = ImageDraw.Draw(img, "RGBA")
for d, pts2, col in polys:
    draw.polygon(pts2, fill=col)
img.convert("RGB").save(out)
print("rendered", len(polys), "faces ->", out)
