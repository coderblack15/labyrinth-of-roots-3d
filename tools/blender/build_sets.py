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


def wrapdeg(d):
    return (d + 180.0) % 360.0 - 180.0


def ring_wall(p, m, r_fn, h, nu, nv, gaps=(), gap_w=9.0, dome_to=None, dome_h=0.0):
    """A wall all the way round, from angle 0 (Godot +Z, Blender -Y) clockwise as seen from
    above, with doorway gaps (degrees). r_fn(a_deg, z) gives the radius. dome_to closes the
    top in to that radius over dome_h metres."""
    def fn(u, v):
        a = 360.0 * u
        if any(abs(wrapdeg(a - g)) < gap_w for g in gaps) and v * (h + dome_h) < h - 0.2:
            return None
        zt = v * (h + dome_h)
        if zt <= h:
            z = zt
            r = r_fn(a, z)
        else:
            k = (zt - h) / max(0.01, dome_h)
            r0 = r_fn(a, h)
            r = r0 + (dome_to - r0) * math.sin(k * math.pi * 0.5)
            z = h + dome_h * math.sin(k * math.pi * 0.5) * 0.7
        ar = math.radians(a)
        return Vector((math.sin(ar) * r, -math.cos(ar) * r, z))
    return grid(p, m, nu, nv, fn)


def disc_floor(p, m, R, nu, nv, z_fn):
    def fn(u, v):
        a = math.tau * u
        r = R * v
        x, y = math.sin(a) * r, -math.cos(a) * r
        return Vector((x, y, z_fn(x, y, r)))
    return grid(p, m, nu, nv, fn)


def strip_floor(p, m, x0, x1, y0, y1, nu, nv, z_fn):
    def fn(u, v):
        x = x0 + (x1 - x0) * u
        y = y0 + (y1 - y0) * v
        return Vector((x, y, z_fn(x, y)))
    return grid(p, m, nu, nv, fn)


def side_wall(p, m, side, y0, y1, h, inner, nu, nv, seed, lean=0.1, amp=0.35):
    def fn(u, v):
        y = y0 + (y1 - y0) * u
        z = h * v
        q = Vector((y * 0.6, z * 0.25, seed))
        x = inner + amp * ridged(q) + 0.25 * fbm(Vector((y * 0.3, z * 0.3, seed + 4))) + z * lean
        return Vector((side * x, y, z))
    return grid(p, m, nu, nv, fn)


def root_curtain(p, m, rng, side, y0, y1, x_in, h, count, rmin=0.06, rmax=0.2):
    """Roots running down a wall: mostly vertical, some crossing."""
    for i in range(count):
        y = rng.uniform(y0, y1)
        z = h * rng.uniform(0.75, 1.05)
        rad = rng.uniform(rmin, rmax)
        drift = rng.uniform(-0.35, 0.35)
        pts = []
        while z > -0.05:
            pts.append((side * (x_in + rad * 0.9 + 0.06 * noise.noise(Vector((y, z, i)))), y, z, rad))
            z -= rng.uniform(0.3, 0.45)
            y += drift * 0.4 + rng.uniform(-0.12, 0.12)
            y = min(max(y, y0 - 0.5), y1 + 0.5)
        # foot: spread onto the floor a little
        fy = y
        for k in range(rng.randint(1, 3)):
            fy += rng.uniform(-0.4, 0.4)
            pts.append((side * (x_in - 0.15 * (k + 1)), fy, 0.03, rad * 0.7))
        if len(pts) >= 3:
            p.tube(m, pts, seg=6, rough=0.2, freq=3.0)


# ---------------------------------------------------------------- Part II: the root corridors
def corridors():
    reset()
    root = empty("set_corridors")
    wall = mat("wallstone", "#3a3630", 0.95)
    rootm = mat("root", "#4a3c2e", 0.9)
    ground = mat("cavefloor", "#2e2a24", 1.0)
    ember = mat("ember", "#ff8a30", 0.5, emit="#ff7a20", es=4.0)
    rng = random.Random(21)
    w = Part("Walls", 11)
    for side in (-1, 1):
        side_wall(w, wall, side, -7.0, 24.4, 6.0, 1.95, 130, 26, 40 + side, lean=0.06)
    # the end wall
    def ew(u, v):
        x = -3.0 + 6.0 * u
        z = 6.0 * v
        return Vector((x, 24.1 - 0.35 * ridged(Vector((x * 0.6, z * 0.25, 9))), z))
    grid(w, wall, 30, 26, ew)
    w.done(root)
    r = Part("Roots", 12)
    for side in (-1, 1):
        root_curtain(r, rootm, rng, side, -6.5, 24.0, 1.62, 6.0, 70)
    # a few great roots arching overhead, high above the camera
    for k in range(5):
        y = rng.uniform(-2, 22)
        rad = rng.uniform(0.18, 0.32)
        pts = []
        for t in range(13):
            a = math.pi * t / 12
            pts.append((-1.9 * math.cos(a), y + 0.3 * math.sin(a * 2), 6.0 + 1.6 * math.sin(a), rad))
        r.tube(rootm, pts, seg=8, rough=0.25, freq=2.0)
    # roots crossing the floor, sunk flat
    for k in range(26):
        y = rng.uniform(-6, 23)
        pts = []
        x = rng.choice((-1.6, 1.6))
        for t in range(6):
            pts.append((x, y, 0.0, rng.uniform(0.05, 0.1)))
            x -= math.copysign(rng.uniform(0.3, 0.7), x)
            y += rng.uniform(-0.4, 0.4)
        r.tube(rootm, pts, seg=5, rough=0.2, freq=3.0)
    r.done(root)
    # amber light deep in the cracks behind the roots
    e = Part("Embers", 13)
    for k in range(40):
        side = rng.choice((-1, 1))
        y = rng.uniform(-6, 24)
        z = rng.uniform(0.3, 4.5)
        e.box(ember, (0.03, rng.uniform(0.05, 0.12), rng.uniform(0.3, 1.1)), loc=(side * 1.98, y, z), rot=(rng.uniform(-15, 15), 0, 0))
    e.done(root)
    f = Part("Floor", 14)
    strip_floor(f, ground, -2.2, 2.2, -7.0, 24.4, 22, 120, lambda x, y: 0.05 * fbm(Vector((x * 1.5, y * 1.5, 3))) - 0.03 + 0.25 * smooth(1.3, 2.0, abs(x)))
    f.done(root)
    export("set_corridors")


# ---------------------------------------------------------------- Part III: the Hollow Chamber
def chamber():
    reset()
    root = empty("set_chamber")
    bark = mat("bark", "#4a3a2a", 0.95)
    rootm = mat("root", "#4a3c2e", 0.9)
    ground = mat("ground", "#3a3024", 1.0)
    wall = mat("wallstone", "#3a3630", 0.95)
    thorn = mat("thorn", "#b8b49a", 0.8)
    rng = random.Random(31)
    w = Part("Bark", 21)

    def rfn(a, z):
        ar = math.radians(a)
        flute = 0.35 * abs(math.sin(ar * 22 + 1.5 * noise.noise(Vector((a * 0.05, z * 0.2, 1)))))
        return 9.7 + flute + 0.4 * fbm(Vector((math.sin(ar) * 2, math.cos(ar) * 2, z * 0.15))) - 1.2 * smooth(5.0, 8.5, z)
    ring_wall(w, bark, rfn, 8.5, 220, 34, gaps=(0.0, 180.0), gap_w=9.0, dome_to=2.2, dome_h=3.0)
    for side in (-1, 1):
        side_wall(w, wall, side, -14.2, -9.0, 4.4, 1.6, 20, 12, 70 + side)
        side_wall(w, bark, side, 9.0, 17.0, 4.4, 1.6, 30, 12, 80 + side)
    w.done(root)
    r = Part("Roots", 22)
    # buttress roots: down the wall, out across the floor
    for i in range(16):
        a = 360.0 * (i + 0.5) / 16
        if abs(wrapdeg(a)) < 16 or abs(wrapdeg(a - 180)) < 16:
            continue
        rad = rng.uniform(0.22, 0.36)
        pts = []
        for t in range(14):
            k = t / 13
            z = 9.6 - k * 9.6
            rr = 8.0 + 1.4 * k - 0.2 * math.sin(k * 6)
            aa = math.radians(a + 6 * math.sin(k * 3 + i))
            pts.append((math.sin(aa) * rr, -math.cos(aa) * rr, z, rad * (0.7 + 0.5 * k)))
        for t in range(1, 5):
            rr = 9.4 - t * 0.9
            aa = math.radians(a + rng.uniform(-4, 4))
            pts.append((math.sin(aa) * rr, -math.cos(aa) * rr, 0.05 + 0.15 / t, rad * (1.1 - t * 0.18)))
        r.tube(rootm, pts, seg=9, rough=0.25, freq=1.5)
    for i in range(40):
        a = rng.uniform(0, 360)
        if abs(wrapdeg(a)) < 12 or abs(wrapdeg(a - 180)) < 12:
            continue
        root_like = []
        z = rng.uniform(3, 9)
        rad = rng.uniform(0.05, 0.12)
        while z > 0:
            ar = math.radians(a)
            rr = rfn(a, z) - rad - 0.05
            root_like.append((math.sin(ar) * rr, -math.cos(ar) * rr, z, rad))
            z -= 0.4
            a += rng.uniform(-1.5, 1.5)
        if len(root_like) > 2:
            r.tube(rootm, root_like, seg=5, rough=0.2)
    r.done(root)
    t = Part("Thorns", 23)
    for i in range(18):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(3.8, 8.0)
        x, y = math.sin(a) * d, -math.cos(a) * d
        if abs(x) < 1.8 and y < 0:
            continue
        if abs(x) < 2.2 and abs(y - 2.0) < 2.4:
            continue  # clear of the trunk
        for k in range(9):
            b = rng.uniform(0, math.tau)
            l = rng.uniform(0.4, 0.9)
            pts = [(x, y, 0.0, 0.03)]
            for s in range(1, 5):
                q = s / 4
                pts.append((x + math.cos(b) * l * q, y + math.sin(b) * l * q, 0.7 * l * math.sin(q * 2.2), 0.03 * (1 - q * 0.8)))
            t.tube(thorn, pts, seg=4, cap=True, smooth=False)
    t.done(root)
    f = Part("Floor", 24)
    disc_floor(f, ground, 10.6, 96, 30, lambda x, y, r: 0.06 * fbm(Vector((x, y, 2))) + 0.4 * smooth(8.0, 10.5, r) - 0.02)
    strip_floor(f, ground, -1.8, 1.8, -17.0, -9.5, 8, 20, lambda x, y: 0.03 * fbm(Vector((x * 2, y * 2, 4))) - 0.02)
    strip_floor(f, ground, -1.8, 1.8, 9.5, 17.5, 8, 20, lambda x, y: 0.03 * fbm(Vector((x * 2, y * 2, 5))) - 0.02)
    f.done(root)
    export("set_chamber")


# ---------------------------------------------------------------- Part IV: the nest
def nest():
    reset()
    root = empty("set_nest")
    rock = mat("caverock", "#3a3530", 0.95)
    ground = mat("cavefloor", "#2e2a24", 1.0)
    silk = mat("silk", "#c8c4b4", 0.9, alpha=0.55)
    rng = random.Random(41)
    w = Part("Cave", 31)

    def rfn(a, z):
        ar = math.radians(a)
        q = Vector((math.sin(ar) * 3, math.cos(ar) * 3, z * 0.18))
        return 12.0 + 1.6 * ridged(q) + 0.8 * fbm(q * 2.0) - 1.5 * smooth(5.0, 9.0, z)
    ring_wall(w, rock, rfn, 8.5, 240, 36, gaps=(0.0, 180.0), gap_w=7.5, dome_to=1.4, dome_h=4.0)
    for side in (-1, 1):
        side_wall(w, rock, side, -17.5, -10.5, 5.0, 1.65, 24, 14, 90 + side)
        side_wall(w, rock, side, 11.0, 18.0, 5.0, 1.65, 24, 14, 95 + side)
    # stalactites
    for i in range(46):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(3.0, 10.5)
        top = 8.8 + 2.6 * (1 - d / 11) ** 0.5
        l = rng.uniform(0.8, 2.6)
        w.cone(rock, rng.uniform(0.15, 0.45), 0.02, l, loc=(math.sin(a) * d, -math.cos(a) * d, top - l * 0.5), rot=(180, 0, 0), seg=7)
    w.done(root)
    # silk drapes from the dome
    s = Part("Silk", 32)
    for i in range(18):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(5.5, 10.0)
        x, y = math.sin(a) * d, -math.cos(a) * d
        top = 9.0
        bottom = rng.uniform(2.5, 5.5)
        wdt = rng.uniform(0.4, 1.0)
        tang = Vector((math.cos(a), math.sin(a), 0))
        def sfn(u, v, x=x, y=y, top=top, bottom=bottom, wdt=wdt, tang=tang, i=i):
            z = top - (top - bottom) * v
            c = Vector((x, y, z)) + tang * (u - 0.5) * wdt * (1 - v * 0.7) + Vector((0, 0, 0)) * 0
            c.x += 0.15 * math.sin(v * 5 + i)
            return c
        grid(s, silk, 3, 8, sfn)
    s.done(root)
    f = Part("Floor", 33)
    disc_floor(f, ground, 13.5, 110, 34, lambda x, y, r: 0.07 * fbm(Vector((x, y, 6))) + 0.8 * smooth(6.5, 12.5, r) - 0.02)
    strip_floor(f, ground, -2.0, 2.0, -18.0, -11.5, 8, 16, lambda x, y: 0.03 * fbm(Vector((x * 2, y * 2, 8))) - 0.02)
    strip_floor(f, ground, -2.0, 2.0, 11.5, 18.0, 8, 16, lambda x, y: 0.03 * fbm(Vector((x * 2, y * 2, 9))) - 0.02)
    # bones and husks in the grit, outside the fight squares
    bone = mat("bone", "#cfc7b0", 0.7)
    for i in range(60):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(5.2, 10.5)
        x, y = math.sin(a) * d, -math.cos(a) * d
        if abs(x) < 2.2 and abs(y) > 9:
            continue
        l = rng.uniform(0.15, 0.45)
        b = rng.uniform(0, math.tau)
        f.tube(bone, [(x, y, 0.04, 0.025), (x + math.cos(b) * l, y + math.sin(b) * l, 0.04, 0.02)], seg=5)
    f.done(root)
    export("set_nest")


if __name__ == "__main__":
    which = sys.argv[sys.argv.index("--sets") + 1].split(",") if "--sets" in sys.argv else ["pathway", "corridors", "chamber", "nest"]
    for name in which:
        globals()[name]()
    print("sets built")
