#!/usr/bin/env python3
# Builds the twenty dungeons from chapters.py. Created by: Adrian Blackshire and Claude.
#
#   python3 tools/dungeons/gen.py --art2d DIR     (DIR holds the 2D game's art/*.webp)
#
# Writes scripts/explore/dungeons.gd, scripts/tactics/gen_boards.gd and art/pieces/tok_*.webp.
# Every maze and board is checked as it's made (the way through exists, every foe can be
# reached), and a seed is retried until it passes, so the output is the same each run.
import argparse, os, random, sys
from collections import deque

sys.path.insert(0, os.path.dirname(__file__))
from chapters import THEMES, FOES, CHAPTERS

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DIRS = [(0, -1), (1, 0), (0, 1), (-1, 0)]


# ------------------------------------------------------------------ pieces
def make_tokens(art2d):
    from PIL import Image, ImageOps, ImageEnhance, ImageDraw, ImageFont, ImageFilter
    out = os.path.join(ROOT, "art", "pieces")
    crops = {  # (cx, cy, size) as fractions of width/height/min side, for paintings that need it
        "sc_wleye": (0.62, 0.72, 0.62), "sc_varro_mire": (0.5, 0.32, 0.8), "sc_curator": (0.5, 0.25, 0.85),
        "sc_bw_brimling": (0.43, 0.42, 0.95), "p_pike": (0.5, 0.5, 0.9), "b_mites": (0.5, 0.5, 0.9),
        "bloom": (0.52, 0.55, 0.55), "b_skimmer": (0.5, 0.62, 0.62), "p_wringer": (0.68, 0.5, 0.8), "b_ticks": (0.45, 0.4, 0.8),
    }
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", 300)

    def painted(name, dst, pid=None):
        im = Image.open(os.path.join(art2d, name + ".webp")).convert("RGB")
        w, h = im.size
        if pid in crops or name in crops:
            cx, cy, s = crops.get(pid) or crops[name]
            side = int(min(w, h) * s)
            x0 = int(w * cx - side / 2)
            y0 = int(h * cy - side / 2)
        elif h > w * 1.1:  # a portrait: the face is near the top
            side = w
            x0, y0 = 0, int(h * 0.05)
        else:
            side = min(w, h)
            x0, y0 = (w - side) // 2, (h - side) // 2
        x0 = max(0, min(w - side, x0))
        y0 = max(0, min(h - side, y0))
        im = im.crop((x0, y0, x0 + side, y0 + side)).resize((512, 512), Image.LANCZOS)
        im = ImageOps.autocontrast(im, cutoff=1)
        im = ImageEnhance.Brightness(im).enhance(1.25)
        im = ImageEnhance.Contrast(im).enhance(1.1)
        im.save(dst, "WEBP", quality=86)

    def medallion(glyph, tint, dst):
        # a stand-in until the painting arrives: a tinted disc with the creature's letter
        t = tuple(int(tint[i:i + 2], 16) for i in (0, 2, 4))
        im = Image.new("RGB", (512, 512), (20, 16, 12))
        d = ImageDraw.Draw(im)
        for r in range(256, 0, -4):
            k = 0.35 + 0.65 * (1 - r / 256)
            d.ellipse((256 - r, 256 - r, 256 + r, 256 + r), fill=tuple(int(c * k) for c in t))
        d.ellipse((40, 40, 472, 472), outline=(200, 170, 100), width=10)
        bb = d.textbbox((0, 0), glyph, font=font)
        d.text((256 - (bb[0] + bb[2]) / 2 + 4, 256 - (bb[1] + bb[3]) / 2 + 6), glyph, font=font, fill=(0, 0, 0))
        d.text((256 - (bb[0] + bb[2]) / 2, 256 - (bb[1] + bb[3]) / 2), glyph, font=font, fill=(236, 222, 190))
        im = im.filter(ImageFilter.SMOOTH)
        im.save(dst, "WEBP", quality=86)

    made = {}
    def piece(pid, art, glyph=None, tint=None):
        if art == "tok_spider":
            return "res://art/pieces/tok_spider.png"
        dst = os.path.join(out, "tok_%s.webp" % pid)
        if art:
            painted(art, dst, pid)
        else:
            medallion(glyph, tint, dst)
        made[pid] = art or "placeholder"
        return "res://art/pieces/tok_%s.webp" % pid
    return piece, made


# ------------------------------------------------------------------ units
def foe_unit(fid, ci, art_path):
    f = FOES[fid]
    kind = f["kind"]
    u = {"name": f["name"], "side": "foe", "art": art_path}
    hit = min(f["atk"], 4 + ci // 5)
    s = min(f["s"], 10)
    if kind == "pack":
        u.update(kind="sol", hp=5 + ci // 4, hit=hit, ac=min(f["ac"], 13), die=[1, min(s, 6), 1], spd=7, mv=3)
    elif kind == "beast":
        u.update(kind="sol", hp=10 + ci // 3, hit=hit, ac=min(f["ac"], 14), die=[1, s, 1 if s < 10 else 0], spd=8, mv=3)
    else:  # elite: a named beast with a board to itself
        u.update(kind="sol", hp=18 + ci // 2, hit=hit + 1, ac=f["ac"], die=[1, s, 2], spd=8, mv=3, big=True)
    if f.get("fast"):
        u["spd"] += 2; u["mv"] += 1
    if f.get("slow"):
        u["spd"] -= 2; u["mv"] -= 1
    cards = ["strike"]
    if f.get("heavy") or kind == "elite":
        cards.append("heavy")
    if f.get("ranged"):
        cards.append(f["ranged"])
    u["cards"] = cards
    if f.get("climb"):
        u["climb"] = True
    if f.get("fly"):
        u["fly"] = True
    if f.get("wade"):
        u["wade"] = True
    if art_path.endswith(".png") or not f.get("art"):
        u["medal"] = True
    if kind == "pack":
        u["small"] = True
    return u


def boss_unit(b, ci, art_path):
    u = {"name": b["name"], "side": "foe", "kind": "cap", "hp": 28 + ci // 2, "hit": 5 + ci // 6,
         "ac": 13 + ci // 8, "die": [1, 8, 1 + ci // 8], "spd": 8, "mv": 3, "cards": ["strike", "heavy"],
         "art": art_path, "big": True}
    if b.get("climb"):
        u["climb"] = True
    if not b.get("art"):
        u["medal"] = True
    return u


# ------------------------------------------------------------------ boards
WALK = set(".cr=~io")


def board_ok(grid, hts, starts, foes, W, H):
    def walk(p):
        x, y = p
        return 0 <= x < W and 0 <= y < H and grid[y][x] in WALK
    for p in starts + foes:
        if grid[p[1]][p[0]] not in ".cr=":
            return False
    seen = {starts[0]}
    q = deque([starts[0]])
    while q:
        x, y = q.popleft()
        for dx, dy in DIRS:
            n = (x + dx, y + dy)
            if n in seen or not walk(n):
                continue
            dl = int(hts[n[1]][n[0]]) - int(hts[y][x])
            if dl >= 2 or dl <= -3:
                continue
            seen.add(n)
            q.append(n)
    floor = sum(1 for y in range(H) for x in range(W) if grid[y][x] in WALK)
    if len(seen) < floor * 0.8:
        return False
    for f in foes:
        if f not in seen:
            return False
    return True


def make_board(rng, W, H, weights, boss, n_foes):
    hts = [[0] * W for _ in range(H)]
    grid = [["."] * W for _ in range(H)]
    cx = W // 2
    you = (cx - 1, H - 1)
    burr = (cx, H - 1)
    reserved = {you, burr, (cx - 1, H - 2), (cx, H - 2)}
    foes = []
    if boss:
        # the boss's ledge at the back, a step down round it, cut steps up the middle
        for y in range(0, 2):
            for x in range(cx - 3, cx + 3):
                hts[y][x] = 2
        for x in range(cx - 4, cx + 4):
            hts[2][x] = max(hts[2][x], 1)
        for y in range(0, 2):
            hts[y][cx - 4] = max(hts[y][cx - 4], 1)
            hts[y][cx + 3] = max(hts[y][cx + 3], 1)
        grid[2][cx - 1] = "="
        grid[2][cx] = "="
        grid[1][cx - 4] = "="
        grid[1][cx + 3] = "="
        foes.append((cx - 1, 0))
        reserved |= {(cx - 1, 0), (cx, 0), (cx - 1, 1), (cx, 1), (cx - 1, 2), (cx, 2)}
        grid[0][cx - 3] = "P"
        grid[0][cx + 2] = "P"
    # rises: one or two raised shelves off to the sides
    for _ in range(rng.randint(2, 3)):
        w, h = rng.randint(2, 4), rng.randint(2, 3)
        x0 = rng.choice([0, W - w]) if rng.random() < 0.7 else rng.randint(1, W - w - 1)
        y0 = rng.randint(1 if not boss else 3, H - h - 2)
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                hts[y][x] = max(hts[y][x], 1)
        if w >= 3 and h >= 3 and rng.random() < 0.6:
            hts[y0 + 1][x0 + 1] = 2
        # a cut step on the edge facing the middle
        sx = x0 + w if x0 + w < W and x0 == 0 else x0 - 1
        sy = y0 + h // 2
        if 0 <= sx < W and (sx, sy) not in reserved:
            grid[sy][sx] = "="
    # foe spots: spread along the far rows
    spots = []
    for y in range(0, min(4, H)):
        for x in range(W):
            if (x, y) not in reserved and grid[y][x] == ".":
                spots.append((x, y))
    rng.shuffle(spots)
    for p in spots:
        if len(foes) >= n_foes:
            break
        if all(abs(p[0] - q[0]) + abs(p[1] - q[1]) >= 2 for q in foes):
            foes.append(p)
            reserved.add(p)
    # the ground: clustered pools of water and mire, scattered cover and pillars
    keys = [k for k in weights]
    total = sum(weights.values())
    n_feat = int(W * H * 0.3)
    placed = 0
    tries = 0
    while placed < n_feat and tries < 2000:
        tries += 1
        r = rng.random() * total
        for k in keys:
            r -= weights[k]
            if r <= 0:
                break
        x, y = rng.randrange(W), rng.randrange(H)
        if (x, y) in reserved or grid[y][x] != ".":
            continue
        if k in "w~i" and any(abs(x - f[0]) + abs(y - f[1]) <= 1 for f in foes + [you, burr]):
            continue
        if k == "w" and hts[y][x] > 0:
            continue
        if k in "P#" and any(grid[y + dy][x + dx] in "P#" for dx, dy in DIRS if 0 <= x + dx < W and 0 <= y + dy < H):
            continue
        cells = [(x, y)]
        if k in "w~i":
            for _ in range(rng.randint(1, 3)):
                bx, by = rng.choice(cells)
                dx, dy = rng.choice(DIRS)
                n = (bx + dx, by + dy)
                if 0 <= n[0] < W and 0 <= n[1] < H and n not in reserved and grid[n[1]][n[0]] == "." \
                        and hts[n[1]][n[0]] == hts[y][x] and n not in cells:
                    cells.append(n)
        for (a, b) in cells:
            grid[b][a] = k
            placed += 1
    return grid, hts, you, burr, foes


def board(rng, W, H, theme, boss, n_foes):
    for _ in range(400):
        seed = rng.randrange(1 << 30)
        r2 = random.Random(seed)
        grid, hts, you, burr, foes = make_board(r2, W, H, THEMES[theme]["ground"], boss, n_foes)
        if board_ok(grid, hts, [you, burr], foes, W, H):
            return ["".join(r) for r in grid], ["".join(str(v) for v in r) for r in hts], you, burr, foes
    raise SystemExit("no board for %s" % theme)


# ------------------------------------------------------------------ mazes
def make_maze(rng, cw, chh):
    W, H = cw * 2 + 1, chh * 2 + 1
    g = [["#"] * W for _ in range(H)]
    adj = {}
    start = (0, chh - 1)
    stack = [start]
    seen = {start}
    adj[start] = []
    while stack:
        c = stack[-1]
        opts = [(c[0] + dx, c[1] + dy) for dx, dy in DIRS if 0 <= c[0] + dx < cw and 0 <= c[1] + dy < chh and (c[0] + dx, c[1] + dy) not in seen]
        if not opts:
            stack.pop()
            continue
        n = rng.choice(opts)
        seen.add(n)
        adj.setdefault(c, []).append(n)
        adj.setdefault(n, []).append(c)
        stack.append(n)
    # a few extra openings, so it's a maze with loops, not a tree
    for _ in range(max(1, cw * chh // 10)):
        a = (rng.randrange(cw), rng.randrange(chh))
        dx, dy = rng.choice(DIRS)
        b = (a[0] + dx, a[1] + dy)
        if 0 <= b[0] < cw and 0 <= b[1] < chh and b not in adj[a]:
            adj[a].append(b)
            adj[b].append(a)
    for c, ns in adj.items():
        g[c[1] * 2 + 1][c[0] * 2 + 1] = "."
        for n in ns:
            g[c[1] + n[1] + 1][c[0] + n[0] + 1] = "."
    return g, adj, start


def gpos(c):
    return (c[0] * 2 + 1, c[1] * 2 + 1)


def between(a, b):
    return (a[0] + b[0] + 1, a[1] + b[1] + 1)


def maze_path(adj, a, b, blocked=()):
    prev = {a: None}
    q = deque([a])
    while q:
        c = q.popleft()
        if c == b:
            break
        for n in adj[c]:
            if n not in prev and n not in blocked:
                prev[n] = c
                q.append(n)
    if b not in prev:
        return None
    out = [b]
    while out[-1] != a:
        out.append(prev[out[-1]])
    return out[::-1]


def maze(rng, cw, chh):
    for _ in range(500):
        g, adj, start = make_maze(rng, cw, chh)
        dist = {c: len(maze_path(adj, start, c)) for c in adj}
        boss = max(adj, key=lambda c: (len(adj[c]) == 1, dist[c]))
        main = maze_path(adj, start, boss)
        if len(main) < 6:
            continue
        # the locked door sits on the way to the boss; nothing past it is reachable without it
        da, db = main[-3], main[-2]
        if len(adj[boss]) != 1 or len(adj[db]) > 2:
            continue
        behind = {db, boss}
        ok = all(c in behind or maze_path(adj, start, c, blocked={db}) for c in adj)
        if not ok:
            continue
        ends = [c for c in adj if len(adj[c]) == 1 and c not in behind and c != start and c not in main]
        if len(ends) < 2:
            continue
        ends.sort(key=lambda c: -dist[c])
        key = ends[0]
        chest = ends[1]
        # the chest's pocket is closed by a cracked wall
        cp = adj[chest][0]
        kpath = maze_path(adj, start, key, blocked={chest})
        if kpath is None or cp == start:
            continue
        mpath = maze_path(adj, start, da, blocked={chest})
        f1 = kpath[len(kpath) * 2 // 3]
        f2 = mpath[max(2, len(mpath) * 2 // 3)] if len(mpath) > 3 else None
        if f2 is None or f1 in (start, key) or f2 in (start, key, f1) or f1 == chest or f2 == chest:
            continue
        gx = lambda c, ch: g.__getitem__(gpos(c)[1]).__setitem__(gpos(c)[0], ch)
        # overgrowth and pools first, then the marks on top
        for y in range(len(g)):
            for x in range(len(g[0])):
                if g[y][x] == "." and rng.random() < 0.28:
                    g[y][x] = ","
        pools = [c for c in adj if c not in (start, key, chest, boss, f1, f2, db, da) and c not in main]
        rng.shuffle(pools)
        for c in pools[:2]:
            gx(c, "~")
        gx(start, "P")
        gx(key, "K")
        gx(chest, "C")
        gx(boss, "B")
        gx(f1, "1")
        gx(f2, "2")
        sx, sy = between(chest, cp)
        g[sy][sx] = "S"
        dx, dy = between(da, db)
        g[dy][dx] = "D"
        return ["".join(r) for r in g]
    raise SystemExit("no maze")


# ------------------------------------------------------------------ output
def col(h):
    return 'Color("%s")' % h


def gd(v, ind=0):
    pad = "\t" * ind
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        if v.startswith("Color("):
            return v
        return '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"')
    if isinstance(v, list):
        if all(isinstance(x, (int, float)) for x in v) or (all(isinstance(x, str) for x in v) and sum(len(x) for x in v) < 70):
            return "[" + ", ".join(gd(x) for x in v) + "]"
        return "[\n" + "".join(pad + "\t" + gd(x, ind + 1) + ",\n" for x in v) + pad + "]"
    if isinstance(v, dict):
        return "{\n" + "".join(pad + "\t" + gd(k) + ": " + gd(x, ind + 1) + ",\n" for k, x in v.items()) + pad + "}"
    raise TypeError(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--art2d", required=True)
    ap.add_argument("--no-art", action="store_true")
    a = ap.parse_args()
    piece, made = make_tokens(a.art2d)
    if a.no_art:
        piece = lambda pid, art, glyph=None, tint=None: "res://art/pieces/tok_%s.webp" % pid
    units, boards, dungeons = {}, {}, {}
    for ci, ch in enumerate(CHAPTERS):
        rng = random.Random("dungeon-" + ch["key"])
        th = ch["theme"]
        fa, fb = ch["foes"]
        for fid in (fa, fb) + ((ch["elite"],) if ch.get("elite") else ()):
            uid = "%s_%s" % (ch["key"], fid) if fid != "spider" else "spider"
            if uid not in units and fid != "spider":
                f = FOES[fid]
                units[uid] = foe_unit(fid, ci, piece(fid, f.get("art"), f.get("glyph"), f.get("tint")))
        def uid(fid):
            return "spider" if fid == "spider" else "%s_%s" % (ch["key"], fid)
        def group(fid, n_pack, n_beast):
            return [uid(fid)] * (n_pack if FOES[fid]["kind"] == "pack" else n_beast)
        fights = {}
        lines = {}
        # fight 1: a pack (or a pair) of the first foe
        f1 = group(fa, 3, 2)
        # fight 2: the second foe, with one of the first along
        f2 = [uid(ch["elite"])] + group(fa, 2, 1)[:2] if ch.get("elite") else group(fb, 3, 2) + [uid(fa)]
        for n, roster in (("1", f1), ("2", f2)):
            if ch["key"] == "roots" and n == "1":
                fights[n] = "gallery"
                lines[n] = ["Spiders!", "They drop from the dark."]
                continue
            bk = "%s_%s" % (ch["key"], n)
            grid, hts, you, burr, spots = board(rng, 12, 8, th, False, len(roster))
            us = [["you", you[0], you[1]], ["burr", burr[0], burr[1]]] + [[r, p[0], p[1]] for r, p in zip(roster, spots)]
            names = sorted(set(units[r]["name"] if r != "spider" else "Spider" for r in roster))
            boards[bk] = {"title": ch["title"], "blurb": "%s: %s." % (ch["title"], " and ".join(names)),
                          "stage": "void", "dress": th, "theme": th, "grid": grid, "heights": hts, "units": us, "captains": []}
            fights[n] = bk
            first = units[roster[0]]["name"] if roster[0] != "spider" else "Spider"
            lines[n] = [first + ("s!" if FOES[fa if n == "1" else (ch.get("elite") or fb)]["kind"] == "pack" else "!"),
                        "They come at you out of the dark."]
        if ch.get("boss"):
            b = ch["boss"]
            bid = "%s_boss" % ch["key"]
            units[bid] = boss_unit(b, ci, piece(b["id"], b.get("art"), b.get("glyph"), b.get("tint")))
            roster = [bid] + group(fb, 2, 1) + group(fa, 1, 1)
            grid, hts, you, burr, spots = board(rng, 14, 9, th, True, len(roster))
            us = [["you", you[0], you[1]], ["burr", burr[0], burr[1]]] + [[r, p[0], p[1]] for r, p in zip(roster, spots)]
            bk = "%s_boss" % ch["key"]
            boards[bk] = {"title": b["name"], "blurb": b["blurb"], "stage": "void", "dress": th, "theme": th,
                          "grid": grid, "heights": hts, "units": us, "captains": [bid]}
            boss_key, boss_line, outro = bk, [b["name"], b["line"]], b["outro"]
        else:
            boss_key, boss_line, outro = "nest", ["The Nest", "Ryytaa unfolds over her brood."], "The nest is yours, and the labyrinth goes on below."
        if ch["key"] == "roots":
            mz = ["###########", "#P.,#..,#K#", "#,#...#.#.#", "#.#####,#1#", "#.,.#.#.,.#",
                  "#####.###.#", "#,C.S2.,..#", "#########D#", "#,~.,.B.,.#", "###########"]
        else:
            cw = 5 + min(3, ci // 5)
            mz = maze(rng, cw, 4 + (ci % 2))
        dungeons[ch["key"]] = {
            "title": ch["title"], "chapter": ch["chapter"], "slug": ch["slug"], "intro": ch["intro"], "theme": th,
            "maze": mz, "fights": fights, "lines": lines, "boss": boss_key, "boss_line": boss_line, "outro": outro,
            "chest": {"name": "a healing draught", "heal": 12},
        }
    # write the dungeons and themes
    themes = {}
    for k, t in THEMES.items():
        themes[k] = {"floor": [t["floor"][0], col(t["floor"][1]), t["floor"][2]], "wall": [t["wall"][0], col(t["wall"][1]), t["wall"][2]],
                     "trim": [t["trim"][0], col(t["trim"][1]), t["trim"][2]], "light": col(t["light"]), "amb": col(t["amb"]),
                     "flora": t["flora"],
                     "plants": {"fern": col(t["plants"][0]), "moss": col(t["plants"][1]), "fungus": col(t["plants"][2]), "glow": col(t["plants"][3])},
                     "webs": t["webs"]}
    head = open(os.path.join(ROOT, "tools", "dungeons", "dungeons_head.gd")).read()
    with open(os.path.join(ROOT, "scripts", "explore", "dungeons.gd"), "w") as f:
        f.write(head)
        f.write("const DUNGEONS := " + gd(dungeons) + "\n\n")
        f.write("# How each theme dresses its maze and its boards.\nconst THEMES := " + gd(themes) + "\n\n")
        f.write("# The order the chapters come in.\nconst ORDER := " + gd([c["key"] for c in CHAPTERS]) + "\n")
    with open(os.path.join(ROOT, "scripts", "tactics", "gen_boards.gd"), "w") as f:
        f.write("# The dungeons' fight boards and foes, written by tools/dungeons/gen.py from chapters.py.\n"
                "# Don't edit by hand: change chapters.py and run gen.py again.\n"
                "# Created by: Adrian Blackshire and Claude.\nextends RefCounted\n\n")
        f.write("const BOARDS := " + gd(boards) + "\n\n")
        f.write("const UNITS := " + gd(units) + "\n")
    print("dungeons %d, boards %d, foes %d, pieces painted %d, placeholders %d" % (
        len(dungeons), len(boards), len(units), sum(1 for v in made.values() if v != "placeholder"),
        sum(1 for v in made.values() if v == "placeholder")))


if __name__ == "__main__":
    main()
