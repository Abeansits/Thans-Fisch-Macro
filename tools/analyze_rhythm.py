"""Measure Fisch musical-rod rhythm-game geometry from screenshots.

Mac-side dev/validation tool. Emits the lane/ring constants the AHK macro
uses and renders annotated overlays so detection can be verified without
running the game. Detection is brightness-based and rod-color agnostic:
an empty ring interior is dark (~21-35); a filled note or ring stroke is
bright (~243-255).
"""
from collections import deque, namedtuple
from PIL import Image, ImageDraw

Ring = namedtuple("Ring", "cx cy r color")


def brightness(rgb):
    return max(rgb[0], rgb[1], rgb[2])


def colorfulness(rgb):
    return max(rgb[0], rgb[1], rgb[2]) - min(rgb[0], rgb[1], rgb[2])


def _colorful_bright(p, cf=55, br=90):
    return colorfulness(p) > cf and brightness(p) > br


def interior_brightness(pix, cx, cy, box=12):
    total = 0
    n = 0
    for y in range(cy - box, cy + box + 1):
        for x in range(cx - box, cx + box + 1):
            total += brightness(pix[x, y])
            n += 1
    return total / n


def find_rings(img, region_top=0.55, dark_interior_max=50):
    """Connected-component scan of the bottom region for ring-sized blobs of
    bright, colorful pixels; keep only those with a DARK interior (hollow
    target rings). Filled notes have bright interiors and are rejected."""
    W, H = img.size
    pix = img.load()
    y_start = int(H * region_top)
    step = 2
    seen = set()
    rings = []
    for sy in range(y_start, H, step):
        for sx in range(0, W, step):
            if (sx, sy) in seen or not _colorful_bright(pix[sx, sy]):
                continue
            q = deque([(sx, sy)])
            seen.add((sx, sy))
            xs, ys = [], []
            while q:
                x, y = q.popleft()
                xs.append(x)
                ys.append(y)
                for dx, dy in ((step, 0), (-step, 0), (0, step), (0, -step)):
                    nx, ny = x + dx, y + dy
                    if (0 <= nx < W and y_start <= ny < H
                            and (nx, ny) not in seen
                            and _colorful_bright(pix[nx, ny])):
                        seen.add((nx, ny))
                        q.append((nx, ny))
            w = max(xs) - min(xs)
            h = max(ys) - min(ys)
            if not (90 <= w <= 200 and 90 <= h <= 200):
                continue  # wrong size: clipped note, merged notes, speck
            cx = (min(xs) + max(xs)) // 2
            cy = (min(ys) + max(ys)) // 2
            if interior_brightness(pix, cx, cy) > dark_interior_max:
                continue  # filled note, not a hollow ring
            color = pix[cx, max(0, cy - h // 2)]  # bright stroke at ring top
            rings.append(Ring(cx, cy, max(w, h) // 2, color))
    rings.sort(key=lambda r: r.cx)
    return rings


def lane_geometry(img):
    W, H = img.size
    rings = find_rings(img)
    geo = {
        "width": W,
        "height": H,
        "n_rings": len(rings),
        "lane_fx": [round(r.cx / W, 4) for r in rings],
        "ring_fy": round(sum(r.cy for r in rings) / len(rings) / H, 4) if rings else None,
        "radius_fy": round(sum(r.r for r in rings) / len(rings) / H, 4) if rings else None,
        "ring_colors": [r.color for r in rings],
    }
    return geo


def emit_constants(geo):
    keys = ["D", "F", "J", "K"]
    lines = []
    for k, fx in zip(keys, geo["lane_fx"]):
        lines.append("Lane%sFrac=%s" % (k, fx))
    lines.append("RingFracY=%s" % geo["ring_fy"])
    lines.append("RadiusFracY=%s" % geo["radius_fy"])
    lines.append("BrightnessThreshold=110")
    lines.append("HitOffsetPixels=15")
    return "\n".join(lines)


def note_present(img, ring, hit_offset_px=15, box=12, threshold=110):
    pix = img.load()
    return interior_brightness(pix, ring.cx, ring.cy + hit_offset_px, box) > threshold
