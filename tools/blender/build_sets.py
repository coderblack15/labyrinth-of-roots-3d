# Builds the diorama sets (the scenery each part is played in) as .glb files.
# Same tools as build_models.py; run it the same way:
#
#   python tools/blender/build_sets.py models
#
# Coordinates: Blender X = Godot X, Blender Y = Godot -Z (forward), Blender Z = up.
# Each surface carries a material name (cliff, ground, flag, rock, root, gatestone)
# that the game swaps for its painted-surface shader and, when present, a texture.
#
# Created by: Adrian Blackshire and Claude
import math
import os
import random
import sys

os.environ["MODELS_AS_LIBRARY"] = "1"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_models import Part, mat, reset, empty, export, OUT  # noqa: E402
from mathutils import Vector, noise  # noqa: E402


def fbm(p, octaves=4, lac=2.03, gain=0.5):
    s, a, f = 0.0, 0.5, 1.0
    for i in range(octaves):
        s += a * noise.noise(p * f + Vector((i * 7.1, i * 3.3, i * 1.9)))
        f *= lac
        a *= gain
    return s


def ridged(p, octaves=4):
    s, a, f = 0.0, 0.5, 1.0
    for i in range(octaves):
        n = 1.0 - abs(noise.noise(p * f + Vector((i * 5.3, i * 2.9, i * 8.1))))
        s += a * n * n
        f *= 2.1
        a *= 0.5
    return s


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def grid(p, m, nu, nv, fn):
    """A (nu+1)x(nv+1) quad sheet; fn(u, v) -> Vector or None (None leaves a hole)."""
    rows = []
    for j in range(nv + 1):
        row = []
        for i in range(nu + 1):
            c = fn(i / nu, j / nv)
            row.append(p.bm.verts.new(c) if c is not None else None)
        rows.append(row)
    verts = []
    for j in range(nv):
        for i in range(nu):
            q = (rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i])
            if all(q):
                p.bm.faces.new(q)
    for row in rows:
        verts += [v for v in row if v]
    p._tag(verts, m, True)
    return rows


# ---------------------------------------------------------------- Part I: the pathway
Y0, Y1 = -14.0, 31.0   # path runs from behind the start (Godot z=+14) to the gate face (Godot z=-31)
GATE_Y = 31.0
DOOR_W, DOOR_H = 1.55, 5.2


def gate_y(x, z):
    q = Vector((x * 0.5, z * 0.14, 77))
    return GATE_Y + 0.5 - ridged(q) * 0.9 - 0.5 * fbm(Vector((x * 0.2, z * 0.2, 5))) + abs(x) * 0.06 + z * 0.05


def cliff_height(y):
    t = (y - Y0) / (Y1 - Y0)
    return 2.6 + 11.0 * t ** 1.4


def pathway():
    reset()
    root = empty("set_pathway")
    cliff = mat("cliff", "#6a6660", 0.95)
    ground = mat("ground", "#3e3a30", 1.0)
    flag = mat("flag", "#6c665c", 0.9)
    rock = mat("rock", "#5a5650", 0.95)
    rootm = mat("root", "#4a3c2e", 0.9)
    gate = mat("gatestone", "#5e5a54", 0.95)

    # the ground: flat along the path, rising in folds toward the cliffs
    g = Part("Ground", 1)

    def gfn(u, v):
        x = -16 + 32 * u
        y = Y0 - 2 + (GATE_Y + 6 - Y0) * v
        q = Vector((x * 0.35, y * 0.35, 0))
        lift = smooth(1.4, 3.6, abs(x)) * (0.5 + 0.9 * fbm(q))
        if x < 0:
            lip = 3.4 + 1.2 * (1 - smooth(Y0, -2, y))
            lift -= 10.0 * smooth(lip + 0.6, lip + 4.0, -x) * (1 - smooth(22.0, 28.0, y))
        bump = 0.06 * fbm(Vector((x * 2.0, y * 2.0, 1.0)))
        return Vector((x, y, lift + bump - 0.02))
    grid(g, ground, 96, 150, gfn)
    g.done(root)

    # the cliffs either side: tall slabs of grey stone that close in toward the gate
    c = Part("Cliffs", 2)
    for side in (-1, 1):
        sd = side * 13.0

        def cfn(u, v, side=side, sd=sd):
            y = Y0 + (GATE_Y + 0.6 - Y0) * u
            h = cliff_height(y) + 2.2 * fbm(Vector((y * 0.18, sd, 0.0)))
            if side < 0:
                # the valley side, as in the painting: a low broken lip until the gate
                low = 0.9 + 1.4 * fbm(Vector((y * 0.3, 5.0, 2.0)))
                h = low + (h - low) * smooth(20.0, 29.0, y)
            z = h * v
            # vertical slabs: stretched noise, so cracks run up and down
            q = Vector((y * 0.55, z * 0.12, sd))
            slab = ridged(q) * 1.25
            bulge = 0.9 * fbm(Vector((y * 0.12, z * 0.18, sd + 3)))
            fine = 0.18 * fbm(Vector((y * 1.6, z * 1.6, sd + 9)))
            lean = z * 0.16  # leans back as it rises
            # close in toward the gate, open out near the start
            inner = 3.2 - 0.6 * smooth(22, 31, y) + 1.2 * (1 - smooth(Y0, -2, y))
            x = inner + slab + bulge + fine + lean
            return Vector((side * x, y, z))
        rows = grid(c, cliff, 180, 44, cfn)
        # a lid over the top that runs back, so no thin edge shows against the sky
        top = rows[-1]
        lid = []
        for v in top:
            if v is None:
                lid.append(None)
                continue
            co = v.co.copy()
            co.x += side * (3.0 + 2.0 * noise.noise(co * 0.4))
            rise = 0.4 + 1.2 * noise.noise(co * 0.3 + Vector((4, 4, 4)))
            if side < 0:
                drop = 1.0 - smooth(22.0, 28.0, co.y)  # the drop into the valley
                co.z += rise * (1 - drop) - 9.0 * drop
            else:
                co.z += rise
            lid.append(c.bm.verts.new(co))
        for i in range(len(top) - 1):
            q = (top[i], top[i + 1], lid[i + 1], lid[i]) if side > 0 else (top[i + 1], top[i], lid[i], lid[i + 1])
            if all(q):
                c.bm.faces.new(q)
        c._tag([v for v in lid if v], cliff, True)
    c.done(root)

    # the gate face: one great cliff across the end with a doorway, like the painting
    gf = Part("GateFace", 3)

    def door(x, z):
        if z < DOOR_H:
            return abs(x) < DOOR_W
        return (x / DOOR_W) ** 2 + ((z - DOOR_H) / 1.6) ** 2 < 1.0

    def gffn(u, v):
        x = -15 + 30 * u
        z = 18.0 * v
        if door(x, z):
            return None
        return Vector((x, gate_y(x, z), z))
    grid(gf, gate, 150, 90, gffn)
    gf.done(root)

    # roots poured over the gate, framing the doorway and running out over the ground
    r = Part("Roots", 4)
    rng = random.Random(9)
    for i in range(34):
        side = -1 if i % 2 == 0 else 1
        start_x = side * rng.uniform(0.3, 5.5)
        z = rng.uniform(9.0, 16.5)
        rad = rng.uniform(0.09, 0.3)
        pts = []
        x = start_x
        k = 0
        while z > -0.1 and k < 60:
            # keep clear of the doorway: hug its outline
            ring = DOOR_W + 0.25 + rad + rng.uniform(0.0, 0.5)
            if z > DOOR_H:
                dz = z - DOOR_H
                d = math.hypot(x / ring, dz / (1.6 + 0.4))
                if d < 1.0:
                    x = side * ring * math.sqrt(max(0.0, 1 - (dz / 2.0) ** 2)) if dz < 2.0 else x
            elif abs(x) < ring:
                x = side * ring
            y = min(GATE_Y - 0.15, gate_y(x, z)) - rad * 0.9 - 0.05
            pts.append((x, y, z, rad * (0.85 + 0.3 * noise.noise(Vector((x * 2, z * 2, i))))))
            z -= rng.uniform(0.3, 0.5)
            x += rng.uniform(-0.3, 0.3) + side * 0.04
            k += 1
        # out across the ground toward the path, thinning
        gx, gy = x, GATE_Y - 0.2
        for s in range(rng.randint(3, 9)):
            gy -= rng.uniform(0.4, 0.8)
            gx += side * rng.uniform(0.0, 0.35) + rng.uniform(-0.2, 0.2)
            if abs(gx) < 1.4:
                gx = side * 1.4
            rad *= 0.86
            pts.append((gx, gy, 0.04 + rad * 0.4, max(0.03, rad)))
        if len(pts) >= 3:
            r.tube(rootm, pts, seg=7, rough=0.25, freq=3.0, cap=True)
    r.done(root)

    # the path: worn flagstones, sunk and tilted
    f = Part("Flagstones", 5)
    y = Y0 + 4
    while y < GATE_Y - 0.4:
        x = -1.25
        while x < 1.25:
            w = rng.uniform(0.45, 0.8)
            d = rng.uniform(0.45, 0.7)
            cx = min(1.25 - w * 0.5, x + w * 0.5)
            if rng.random() > 0.22:
                f.sphere(flag, 0.5, loc=(cx + rng.uniform(-0.04, 0.04), y + d * 0.5, rng.uniform(-0.035, -0.005)),
                         scale=(w * 0.92, d * 0.92, 0.1), rot=(rng.uniform(-3, 3), rng.uniform(-3, 3), rng.uniform(-8, 8)),
                         seg=7, rings=4, rough=0.12, freq=3.0, smooth=False)
            x += w + 0.04
        y += rng.uniform(0.5, 0.75)
    f.done(root)

    # rubble along the foot of the cliffs and a few boulders
    rb = Part("Rubble", 6)
    for i in range(170):
        side = -1 if i % 2 == 0 else 1
        y = rng.uniform(Y0, GATE_Y - 0.5)
        inner = 3.2 - 0.6 * smooth(22, 31, y) + 1.2 * (1 - smooth(Y0, -2, y))
        x = side * (inner + rng.uniform(-1.4, 0.4))
        s = rng.uniform(0.08, 0.35) if rng.random() < 0.9 else rng.uniform(0.6, 1.1)
        rb.sphere(rock, s, loc=(x, y, s * 0.3), scale=(1.0, rng.uniform(0.7, 1.3), rng.uniform(0.5, 0.8)),
                  rot=(0, 0, rng.uniform(0, 360)), seg=8, rings=5, rough=0.25, freq=2.5, smooth=False)
    rb.done(root)
    export("set_pathway")


if __name__ == "__main__":
    pathway()
    print("sets built")
