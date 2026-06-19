from __future__ import annotations

import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
SCALE = 4
CANVAS = 24
OUT_SIZE = CANVAS * SCALE


def parse_color(value: str) -> tuple[int, int, int, int]:
    value = value.strip()
    if value.startswith("#") and len(value) == 7:
        return tuple(int(value[i : i + 2], 16) for i in (1, 3, 5)) + (255,)
    return (0, 58, 112, 255)


def tokenize_path(d: str) -> list[str]:
    return re.findall(r"[AaCcHhLlMmQqSsTtVvZz]|-?\d*\.?\d+(?:e[-+]?\d+)?", d)


def cubic(p0, p1, p2, p3, steps=20):
    return [
        (
            (1 - t) ** 3 * p0[0] + 3 * (1 - t) ** 2 * t * p1[0] + 3 * (1 - t) * t**2 * p2[0] + t**3 * p3[0],
            (1 - t) ** 3 * p0[1] + 3 * (1 - t) ** 2 * t * p1[1] + 3 * (1 - t) * t**2 * p2[1] + t**3 * p3[1],
        )
        for t in [i / steps for i in range(1, steps + 1)]
    ]


def quadratic(p0, p1, p2, steps=16):
    return [
        (
            (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t**2 * p2[0],
            (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t**2 * p2[1],
        )
        for t in [i / steps for i in range(1, steps + 1)]
    ]


def arc_points(start, rx, ry, rotation, large_arc, sweep, end, steps=24):
    if rx == 0 or ry == 0:
        return [end]

    x1, y1 = start
    x2, y2 = end
    phi = math.radians(rotation)
    cos_phi = math.cos(phi)
    sin_phi = math.sin(phi)

    dx = (x1 - x2) / 2
    dy = (y1 - y2) / 2
    x1p = cos_phi * dx + sin_phi * dy
    y1p = -sin_phi * dx + cos_phi * dy

    rx = abs(rx)
    ry = abs(ry)
    lam = (x1p**2) / (rx**2) + (y1p**2) / (ry**2)
    if lam > 1:
        scale = math.sqrt(lam)
        rx *= scale
        ry *= scale

    sign = -1 if large_arc == sweep else 1
    numerator = rx**2 * ry**2 - rx**2 * y1p**2 - ry**2 * x1p**2
    denominator = rx**2 * y1p**2 + ry**2 * x1p**2
    factor = sign * math.sqrt(max(0, numerator / denominator)) if denominator else 0
    cxp = factor * (rx * y1p / ry)
    cyp = factor * (-ry * x1p / rx)

    cx = cos_phi * cxp - sin_phi * cyp + (x1 + x2) / 2
    cy = sin_phi * cxp + cos_phi * cyp + (y1 + y2) / 2

    def angle(u, v):
        dot = u[0] * v[0] + u[1] * v[1]
        mag = math.hypot(*u) * math.hypot(*v)
        value = max(-1, min(1, dot / mag)) if mag else 1
        sign_angle = -1 if u[0] * v[1] - u[1] * v[0] < 0 else 1
        return sign_angle * math.acos(value)

    v1 = ((x1p - cxp) / rx, (y1p - cyp) / ry)
    v2 = ((-x1p - cxp) / rx, (-y1p - cyp) / ry)
    theta1 = angle((1, 0), v1)
    delta = angle(v1, v2)
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    elif sweep and delta < 0:
        delta += 2 * math.pi

    points = []
    for i in range(1, steps + 1):
        theta = theta1 + delta * i / steps
        x = cos_phi * rx * math.cos(theta) - sin_phi * ry * math.sin(theta) + cx
        y = sin_phi * rx * math.cos(theta) + cos_phi * ry * math.sin(theta) + cy
        points.append((x, y))
    return points


def path_points(d: str):
    tokens = tokenize_path(d)
    i = 0
    command = ""
    current = (0.0, 0.0)
    start = (0.0, 0.0)
    segments: list[list[tuple[float, float]]] = []
    segment: list[tuple[float, float]] = []

    def is_command(token: str) -> bool:
        return bool(re.match(r"^[A-Za-z]$", token))

    def number() -> float:
        nonlocal i
        value = float(tokens[i])
        i += 1
        return value

    while i < len(tokens):
        if is_command(tokens[i]):
            command = tokens[i]
            i += 1
        absolute = command.isupper()
        cmd = command.upper()

        if cmd == "M":
            if segment:
                segments.append(segment)
            x, y = number(), number()
            current = (x, y) if absolute else (current[0] + x, current[1] + y)
            start = current
            segment = [current]
            command = "L" if absolute else "l"
        elif cmd == "L":
            x, y = number(), number()
            current = (x, y) if absolute else (current[0] + x, current[1] + y)
            segment.append(current)
        elif cmd == "H":
            x = number()
            current = (x, current[1]) if absolute else (current[0] + x, current[1])
            segment.append(current)
        elif cmd == "V":
            y = number()
            current = (current[0], y) if absolute else (current[0], current[1] + y)
            segment.append(current)
        elif cmd == "C":
            c1 = (number(), number())
            c2 = (number(), number())
            end = (number(), number())
            if not absolute:
                c1 = (current[0] + c1[0], current[1] + c1[1])
                c2 = (current[0] + c2[0], current[1] + c2[1])
                end = (current[0] + end[0], current[1] + end[1])
            segment.extend(cubic(current, c1, c2, end))
            current = end
        elif cmd == "Q":
            c = (number(), number())
            end = (number(), number())
            if not absolute:
                c = (current[0] + c[0], current[1] + c[1])
                end = (current[0] + end[0], current[1] + end[1])
            segment.extend(quadratic(current, c, end))
            current = end
        elif cmd == "A":
            rx, ry, rot = number(), number(), number()
            large_arc, sweep = int(number()), int(number())
            end = (number(), number())
            if not absolute:
                end = (current[0] + end[0], current[1] + end[1])
            segment.extend(arc_points(current, rx, ry, rot, large_arc, sweep, end))
            current = end
        elif cmd == "Z":
            segment.append(start)
            segments.append(segment)
            segment = []
            current = start
        else:
            break

    if segment:
        segments.append(segment)
    return segments


def scaled(points):
    return [(x * SCALE, y * SCALE) for x, y in points]


def render_svg(svg_path: Path):
    tree = ET.parse(svg_path)
    root = tree.getroot()
    stroke = parse_color(root.attrib.get("stroke", "#003a70"))
    stroke_width = int(float(root.attrib.get("stroke-width", "2")) * SCALE)
    image = Image.new("RGBA", (OUT_SIZE, OUT_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    for elem in root.iter():
        tag = elem.tag.split("}")[-1]
        if tag == "path":
            for segment in path_points(elem.attrib["d"]):
                if len(segment) > 1:
                    draw.line(scaled(segment), fill=stroke, width=stroke_width, joint="curve")
        elif tag == "circle":
            cx = float(elem.attrib["cx"]) * SCALE
            cy = float(elem.attrib["cy"]) * SCALE
            r = float(elem.attrib["r"]) * SCALE
            draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=stroke, width=stroke_width)
        elif tag == "rect":
            x = float(elem.attrib.get("x", 0)) * SCALE
            y = float(elem.attrib.get("y", 0)) * SCALE
            w = float(elem.attrib["width"]) * SCALE
            h = float(elem.attrib["height"]) * SCALE
            r = float(elem.attrib.get("rx", 0)) * SCALE
            draw.rounded_rectangle((x, y, x + w, y + h), radius=r, outline=stroke, width=stroke_width)
        elif tag == "line":
            x1 = float(elem.attrib["x1"]) * SCALE
            y1 = float(elem.attrib["y1"]) * SCALE
            x2 = float(elem.attrib["x2"]) * SCALE
            y2 = float(elem.attrib["y2"]) * SCALE
            draw.line((x1, y1, x2, y2), fill=stroke, width=stroke_width)

    image = image.resize((24, 24), Image.Resampling.LANCZOS)
    image.save(svg_path.with_suffix(".png"))
    if svg_path.stem in {"grid-2x2", "badge-check", "pickaxe", "droplets", "monitor-cog", "trash-2"}:
        active = Image.new("RGBA", image.size, (0, 0, 0, 0))
        pixels = image.load()
        active_pixels = active.load()
        for y in range(image.height):
            for x in range(image.width):
                alpha = pixels[x, y][3]
                if alpha:
                    active_pixels[x, y] = (255, 255, 255, alpha)
        active.save(svg_path.with_name(f"{svg_path.stem}-active.png"))


def main():
    for svg in ASSETS.glob("*.svg"):
        render_svg(svg)


if __name__ == "__main__":
    main()
