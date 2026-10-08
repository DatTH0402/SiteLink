"""
kmz_export.py - Google Earth (KMZ) visualisation of Sites and Cells 3G/4G/5G.

Ported from the standalone Tkinter "Telecom KMZ Converter Pro" tool.  The data
now comes from the database rows (ORM objects) instead of an Excel file.

Public API
    LAYERS                     per-layer configuration
    build_columns(model, spec_cols)
    layer_meta(layer_key, columns)       -> dict sent to the UI (options/defaults)
    build_kmz(layer_key, rows, columns, options) -> KmzResult
"""
from __future__ import annotations

import colorsys
import html
import io
import math
import re
import zipfile
import zlib
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

# -----------------------------------------------------------------------------
# 1. 1024-colour palette for PCI / PSC / TAC / LAC / RSI ...
# -----------------------------------------------------------------------------
def build_1024_distinct_palette():
    palette = []
    golden_ratio = 0.618033988749895
    for i in range(1024):
        h = (i * golden_ratio) % 1.0
        s = 0.65 + 0.35 * (((i * 7) % 11) / 10.0)     # saturation 0.65 -> 1.0
        v = 0.72 + 0.28 * (((i * 13) % 17) / 16.0)    # value      0.72 -> 1.0
        r, g, b = colorsys.hsv_to_rgb(h, s, v)
        palette.append((int(r * 255), int(g * 255), int(b * 255)))
    return palette


PALETTE_1024 = build_1024_distinct_palette()


def get_color_from_1024(val):
    if val is None or str(val).strip() == "":
        return (160, 160, 160)
    s = str(val).strip()
    try:
        idx = int(float(s))
    except (ValueError, OverflowError):
        # stable hash (python's hash() is randomised per process)
        idx = zlib.crc32(s.encode("utf-8"))
    return PALETTE_1024[idx % len(PALETTE_1024)]


# -----------------------------------------------------------------------------
# 2. Spectrum palettes per technology (UARFCN / EARFCN / GSCN)
# -----------------------------------------------------------------------------
COLOR_PALETTES = {
    '3g': [
        (230, 30, 30), (255, 180, 0), (255, 105, 0), (170, 25, 25),
        (240, 140, 20), (190, 85, 0), (255, 215, 30), (140, 10, 10)
    ],
    '4g': [
        (0, 105, 255), (45, 225, 10), (0, 235, 235), (0, 40, 160),
        (0, 200, 130), (70, 175, 255), (145, 220, 0), (0, 130, 150)
    ],
    '5g': [
        (160, 30, 245), (245, 20, 160), (90, 0, 170), (215, 80, 245),
        (255, 0, 120), (120, 40, 190), (255, 110, 180), (65, 0, 130)
    ],
    'site': [
        (255, 0, 0), (0, 102, 255), (0, 204, 0), (255, 180, 0),
        (255, 100, 0), (160, 30, 240), (240, 30, 160), (0, 220, 220)
    ]
}


def get_high_contrast_rgb(tech_key, index):
    palette = COLOR_PALETTES.get(tech_key, COLOR_PALETTES['site'])
    n = len(palette)
    if index < n:
        return palette[index]
    cycle = index // n
    sub_idx = index % n
    base_r, base_g, base_b = palette[sub_idx]
    factor = 0.85 ** (cycle % 3)
    return (int(base_r * factor), int(base_g * factor), int(base_b * factor))


# -----------------------------------------------------------------------------
# 3. 32 Google Earth icons for Sites
# -----------------------------------------------------------------------------
GOOGLE_EARTH_ICONS = [
    "http://maps.google.com/mapfiles/kml/paddle/wht-circle.png",
    "http://maps.google.com/mapfiles/kml/paddle/wht-diamond.png",
    "http://maps.google.com/mapfiles/kml/paddle/wht-square.png",
    "http://maps.google.com/mapfiles/kml/paddle/wht-stars.png",
    "http://maps.google.com/mapfiles/kml/paddle/wht-blank.png",
    "http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png",
    "http://maps.google.com/mapfiles/kml/shapes/triangle.png",
    "http://maps.google.com/mapfiles/kml/shapes/square.png",
    "http://maps.google.com/mapfiles/kml/shapes/diamond.png",
    "http://maps.google.com/mapfiles/kml/shapes/star.png",
    "http://maps.google.com/mapfiles/kml/shapes/target.png",
    "http://maps.google.com/mapfiles/kml/shapes/donut.png",
    "http://maps.google.com/mapfiles/kml/shapes/cross-hairs.png",
    "http://maps.google.com/mapfiles/kml/shapes/shaded_dot.png",
    "http://maps.google.com/mapfiles/kml/shapes/arrow.png",
    "http://maps.google.com/mapfiles/kml/shapes/flag.png",
    "http://maps.google.com/mapfiles/kml/pushpin/ylw-pushpin.png",
    "http://maps.google.com/mapfiles/kml/pushpin/blue-pushpin.png",
    "http://maps.google.com/mapfiles/kml/pushpin/grn-pushpin.png",
    "http://maps.google.com/mapfiles/kml/pushpin/red-pushpin.png",
    "http://maps.google.com/mapfiles/kml/pushpin/wht-pushpin.png",
    "http://maps.google.com/mapfiles/kml/shapes/info_circle.png",
    "http://maps.google.com/mapfiles/kml/shapes/electronics.png",
    "http://maps.google.com/mapfiles/kml/shapes/homegardenbusiness.png",
    "http://maps.google.com/mapfiles/kml/shapes/library.png",
    "http://maps.google.com/mapfiles/kml/shapes/poi.png",
    "http://maps.google.com/mapfiles/kml/shapes/polygon.png",
    "http://maps.google.com/mapfiles/kml/shapes/caution.png",
    "http://maps.google.com/mapfiles/kml/shapes/camera.png",
    "http://maps.google.com/mapfiles/kml/shapes/capital.png",
    "http://maps.google.com/mapfiles/kml/shapes/post_office.png",
    "http://maps.google.com/mapfiles/kml/shapes/ranger_station.png",
]
DEFAULT_SITE_ICON = "http://maps.google.com/mapfiles/kml/paddle/wht-circle.png"


def get_site_icon_url(icon_index):
    return GOOGLE_EARTH_ICONS[icon_index % len(GOOGLE_EARTH_ICONS)]


NAMED_COLOR_MAP = {
    'red':       (255, 0, 0),     'blue':      (0, 102, 255),   'green':     (0, 204, 0),
    'yellow':    (255, 215, 0),   'orange':    (255, 128, 0),   'purple':    (153, 51, 255),
    'pink':      (255, 102, 178), 'cyan':      (0, 230, 230),   'magenta':   (255, 0, 255),
    'lime':      (50, 205, 50),   'brown':     (165, 42, 42),   'teal':      (0, 128, 128),
    'navy':      (0, 0, 128),     'gold':      (255, 190, 0),   'silver':    (192, 192, 192),
    'darkred':   (139, 0, 0),     'darkgreen': (0, 100, 0),     'darkblue':  (0, 0, 139),
    'gray':      (128, 128, 128), 'white':     (255, 255, 255), 'black':     (0, 0, 0)
}


# -----------------------------------------------------------------------------
# 4. Heatmap + geometry helpers
# -----------------------------------------------------------------------------
def get_heatmap_rgb(norm_val, reverse=False):
    v = max(0.0, min(1.0, float(norm_val)))
    if reverse:
        v = 1.0 - v
    if v < 0.25:
        r, g, b = 0, int(255 * (v / 0.25)), 255
    elif v < 0.5:
        r, g, b = 0, 255, int(255 * (1.0 - (v - 0.25) / 0.25))
    elif v < 0.75:
        r, g, b = int(255 * ((v - 0.5) / 0.25)), 255, 0
    else:
        r, g, b = 255, int(255 * (1.0 - (v - 0.75) / 0.25)), 0
    return r, g, b


def to_kml_color(rgb, alpha_hex="FF"):
    r, g, b = rgb
    return f"{alpha_hex}{b:02X}{g:02X}{r:02X}"


def get_geodesic_offset(base_lat, base_lon, bearing_deg, dist_m):
    if dist_m <= 0:
        return base_lat, base_lon
    R = 6378137.0
    brng = math.radians(bearing_deg)
    lat_rad = math.radians(base_lat)
    lon_rad = math.radians(base_lon)
    tgt_lat = math.asin(math.sin(lat_rad) * math.cos(dist_m / R) +
                        math.cos(lat_rad) * math.sin(dist_m / R) * math.cos(brng))
    tgt_lon = lon_rad + math.atan2(math.sin(brng) * math.sin(dist_m / R) * math.cos(lat_rad),
                                   math.cos(dist_m / R) - math.sin(lat_rad) * math.sin(tgt_lat))
    return math.degrees(tgt_lat), math.degrees(tgt_lon)


def calculate_cell_polygon_str(lat, lon, azimuth, beamwidth, radius_m, num_pts=5):
    half_bw = beamwidth / 2.0
    start_az = (azimuth - half_bw) % 360
    step = beamwidth / num_pts
    pts = []
    for i in range(num_pts + 1):
        az = (start_az + step * i) % 360
        p_lat, p_lon = get_geodesic_offset(lat, lon, az, radius_m)
        pts.append(f"{p_lon:.6f},{p_lat:.6f},0")
    base_coord = f"{lon:.6f},{lat:.6f},0"
    pts.append(base_coord)
    pts.append(pts[0])
    return f"<Polygon><outerBoundaryIs><LinearRing><coordinates>{' '.join(pts)}</coordinates></LinearRing></outerBoundaryIs></Polygon>"


def calculate_ibs_slice_polygon_str(lat, lon, r_inner, r_outer, start_angle, end_angle, num_pts=7):
    pts = []
    sweep = (end_angle - start_angle) % 360
    if sweep <= 0:
        sweep += 360.0
    step = sweep / num_pts

    for i in range(num_pts + 1):
        az = (start_angle + step * i) % 360
        p_lat, p_lon = get_geodesic_offset(lat, lon, az, r_outer)
        pts.append(f"{p_lon:.6f},{p_lat:.6f},0")

    if r_inner > 0:
        for i in range(num_pts, -1, -1):
            az = (start_angle + step * i) % 360
            p_lat, p_lon = get_geodesic_offset(lat, lon, az, r_inner)
            pts.append(f"{p_lon:.6f},{p_lat:.6f},0")
    else:
        pts.append(f"{lon:.6f},{lat:.6f},0")

    pts.append(pts[0])
    return f"<Polygon><outerBoundaryIs><LinearRing><coordinates>{' '.join(pts)}</coordinates></LinearRing></outerBoundaryIs></Polygon>"


def format_cell_value(val, header_name=""):
    if val is None:
        return ""
    if isinstance(val, bool):
        return "x" if val else ""
    header_lower = str(header_name).lower()
    if ('%' in header_lower or 'tỷ lệ' in header_lower or 'tỉ lệ' in header_lower) and isinstance(val, (int, float)):
        if 0 < val <= 1.0:
            return f"{round(val * 100)}%"
        elif val == 0:
            return "0%"
    if isinstance(val, float) and val.is_integer():
        return str(int(val))
    return str(val)


# -----------------------------------------------------------------------------
# 5. Value helpers (DB values are str / float / bool / None)
# -----------------------------------------------------------------------------
def _norm(v) -> str:
    """Normalised string used for grouping / colouring."""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "Có" if v else "Không"
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v).strip()


def _to_float(v) -> Optional[float]:
    if v is None or isinstance(v, bool):
        return None
    try:
        f = float(str(v).strip())
    except (TypeError, ValueError):
        return None
    return f if math.isfinite(f) else None


def _to_num(v) -> Optional[float]:
    """Numeric value for heatmaps: accepts '99.5%', '12 dBm' ..."""
    try:
        return float(str(v).replace('%', '').split()[0])
    except (ValueError, IndexError):
        return None


def _sort_key_val(x):
    f = _to_float(x)
    return (0, f, "") if f is not None else (1, 0.0, str(x))


# -----------------------------------------------------------------------------
# 6. Layer configuration + UI option lists (same wording as the Tkinter tool)
# -----------------------------------------------------------------------------
FOLDER_CHOICES = [
    {"value": "tinh",      "label": "Tỉnh"},
    {"value": "phuong_xa", "label": "Phường/Xã"},
]

COLOR_MODES = [
    {"value": "auto",
     "label": "Tự động (Tần số = Dải quang phổ chuẩn | PCI/TAC/RAC/PSC/RSI = Bảng 1024 Màu)"},
    {"value": "palette1024",
     "label": "Bắt buộc dùng Bảng 1024 Màu (Đa sắc, không trùng lặp)"},
    {"value": "heatmap",
     "label": "Heatmap Thuận (Xanh -> Đỏ: Dành cho Tải, Drop, Nghẽn, PRB)"},
    {"value": "heatmap_reverse",
     "label": "Heatmap Đảo chiều (Đỏ -> Xanh: Dành cho Accessibility, CSSR, Throughput, CQI)"},
]

OPACITIES = [
    {"value": "50",      "label": "50% (Khuyến nghị - Nhìn rõ đường sá, nhà cửa)"},
    {"value": "35",      "label": "35% (Siêu trong suốt - Tập trung xem địa hình)"},
    {"value": "70",      "label": "70% (Màu thân cell đậm hơn)"},
    {"value": "outline", "label": "Chỉ viền rỗng (Trong suốt 100% ruột)"},
]
# value -> (alpha hex, <fill> flag)
OPACITY_MAP = {"50": ("7F", "1"), "35": ("59", "1"), "70": ("B3", "1"), "outline": ("00", "0")}

NAMED_ID_KEYS = ('pci', 'rsi', 'psc', 'tac', 'lac', 'rac', 'rnc', 'bsic', 'bcch',
                 'scrambling', 'root_sequence')

IBS_RADIUS_TIERS = {'3g': (12.0, 24.0), '4g': (28.0, 44.0), '5g': (48.0, 66.0)}

LAYERS: Dict[str, Dict[str, Any]] = {
    "sites": dict(
        lkey="site", tech="", title="Site", file_label="Site", f2="Site",
        freq_attr=None, beam=0.0, min_len=0.0, max_len=0.0,
        default_color="mien", default_icon="phan_loai_tram",
        has_icon=True, has_opacity=False,
        color_label="📍 Cột MÀU Site (Mặc định: mien):",
        icon_label="🏷️ Cột ICON Site (Tự sinh 32 loại biểu tượng):",
        note="Site được vẽ dạng điểm (Placemark). Giá trị màu trùng tên chuẩn "
             "(red, blue, green...) sẽ dùng đúng màu đó.",
    ),
    "cells_3g": dict(
        lkey="3g", tech="3G", title="Cell 3G", file_label="Cell3G", f2="Cell 3G",
        freq_attr="uarfcn", beam=25.0, min_len=100.0, max_len=150.0,
        default_color="uarfcn", default_icon=None, has_icon=False, has_opacity=True,
        color_label="📡 Cột CELL 3G (Mặc định UARFCN / LAC / RAC / PSC):",
        icon_label="",
        note="Cánh cell 3G góc 25°. Độ dài cánh theo UARFCN; cell Indoor vẽ dạng vòng IBS; "
             "cell đồng sector (CA, CD) vẽ đồng tâm chống đè.",
    ),
    "cells_4g": dict(
        lkey="4g", tech="4G", title="Cell 4G", file_label="Cell4G", f2="Cell 4G",
        freq_attr="earfcn", beam=7.0, min_len=200.0, max_len=250.0,
        default_color="earfcn", default_icon=None, has_icon=False, has_opacity=True,
        color_label="📡 Cột CELL 4G (Mặc định EARFCN / TAC / RAC / PCI / RSI):",
        icon_label="",
        note="Cánh cell 4G góc 7°. Độ dài cánh theo EARFCN; cell Indoor vẽ dạng vòng IBS; "
             "cell đồng sector (CA, CD) vẽ đồng tâm chống đè.",
    ),
    "cells_5g": dict(
        lkey="5g", tech="5G", title="Cell 5G", file_label="Cell5G", f2="Cell 5G",
        freq_attr="gscn", beam=2.0, min_len=300.0, max_len=350.0,
        default_color="gscn", default_icon=None, has_icon=False, has_opacity=True,
        color_label="📡 Cột CELL 5G (Mặc định GSCN / TAC / PCI / RSI):",
        icon_label="",
        note="Cánh cell 5G góc 2°. Độ dài cánh theo GSCN; cell Indoor vẽ dạng vòng IBS; "
             "cell đồng sector (CA, CD) vẽ đồng tâm chống đè.",
    ),
}

_INTERNAL_COLS = {"id", "site_id", "created_by", "created_at", "updated_at"}


# -----------------------------------------------------------------------------
# 7. Columns (defined from the SQLAlchemy models)
# -----------------------------------------------------------------------------
def build_columns(model, spec_cols) -> List[Dict[str, Any]]:
    """
    Ordered column list = export-spec columns (same order / headers as the Excel
    export) + any remaining model columns (dump_date, baseband, ...), minus
    internal ones.  Only attributes that really exist on the model are kept.
    """
    table_cols = [c.name for c in model.__table__.columns]
    table_set = set(table_cols)
    cols: List[Dict[str, Any]] = []
    seen = set()
    for c in spec_cols:
        attr = c[2]
        if attr in seen or attr not in table_set or attr in _INTERNAL_COLS:
            continue
        cols.append({"attr": attr, "label": c[0], "conv": c[3] if len(c) > 3 else None})
        seen.add(attr)
    for name in table_cols:
        if name in _INTERNAL_COLS or name in seen:
            continue
        cols.append({"attr": name, "label": name, "conv": None})
        seen.add(name)
    return cols


def _choice_label(c) -> str:
    lbl, attr = c["label"], c["attr"]
    if lbl.lower().replace(" ", "_") == attr.lower():
        return lbl
    return f"{lbl} ({attr})"


def layer_meta(layer_key: str, columns) -> Dict[str, Any]:
    cfg = LAYERS[layer_key]
    choices = [{"value": c["attr"], "label": _choice_label(c)} for c in columns]
    attrs = [c["value"] for c in choices]
    def_color = cfg["default_color"] if cfg["default_color"] in attrs else (attrs[0] if attrs else "")
    def_icon = cfg["default_icon"] if cfg["default_icon"] in attrs else None
    return {
        "layer": layer_key,
        "title": cfg["title"],
        "file_label": cfg["file_label"],
        "folders": FOLDER_CHOICES,
        "default_folder": "tinh",
        "color_columns": choices,
        "default_color": def_color,
        "color_label": cfg["color_label"],
        "has_icon": cfg["has_icon"],
        "icon_columns": choices if cfg["has_icon"] else [],
        "default_icon": def_icon,
        "icon_label": cfg["icon_label"],
        "color_modes": COLOR_MODES,
        "default_color_mode": "auto",
        "has_opacity": cfg["has_opacity"],
        "opacities": OPACITIES if cfg["has_opacity"] else [],
        "default_opacity": "50",
        "note": cfg["note"],
    }


# -----------------------------------------------------------------------------
# 8. Options normalisation + file name
# -----------------------------------------------------------------------------
def normalize_options(layer_key: str, options: Optional[Dict[str, Any]], valid_attrs) -> Dict[str, Any]:
    cfg = LAYERS[layer_key]
    o = options or {}

    folder = o.get("folder")
    if folder not in ("tinh", "phuong_xa"):
        folder = "tinh"

    color_col = o.get("color_col")
    if not (isinstance(color_col, str) and color_col in valid_attrs):
        color_col = cfg["default_color"] if cfg["default_color"] in valid_attrs else sorted(valid_attrs)[0]

    icon_col = None
    if cfg["has_icon"]:
        if "icon_col" in o:
            ic = o.get("icon_col")
            icon_col = ic if (isinstance(ic, str) and ic in valid_attrs) else None   # "" = no icon
        else:
            icon_col = cfg["default_icon"] if cfg["default_icon"] in valid_attrs else None

    mode = o.get("color_mode")
    if mode not in {m["value"] for m in COLOR_MODES}:
        mode = "auto"

    opacity = o.get("opacity")
    if opacity not in OPACITY_MAP:
        opacity = "50"

    date = str(o.get("date") or "")
    if not re.fullmatch(r"\d{8}", date):
        date = datetime.now().strftime("%Y%m%d")

    return dict(folder=folder, color_col=color_col, icon_col=icon_col,
                color_mode=mode, opacity=opacity, date=date)


def _safe(s) -> str:
    return re.sub(r"[^0-9A-Za-z_]+", "_", str(s)).strip("_") or "x"


def make_filename(layer_key: str, o: Dict[str, Any]) -> str:
    cfg = LAYERS[layer_key]
    parts = ["KMZ", cfg["file_label"], _safe(o["folder"]), _safe(o["color_col"])]
    if o.get("icon_col"):
        parts.append("icon_" + _safe(o["icon_col"]))
    parts.append(o["date"])
    return "-".join(parts) + ".kmz"


# -----------------------------------------------------------------------------
# 9. Main builder
# -----------------------------------------------------------------------------
@dataclass
class KmzResult:
    data: bytes
    filename: str
    total: int      # rows received
    valid: int      # rows with valid coordinates (= placemarks written)


def _folder_value(obj, folder: str) -> str:
    tinh = _norm(getattr(obj, "tinh", None))
    if folder == "phuong_xa":
        px = _norm(getattr(obj, "phuong_xa", None))
        if not px:
            return "Chưa phân nhóm"
        # ward names repeat across provinces -> keep the province for clarity
        return f"{px} - {tinh}" if tinh else px
    return tinh or "Chưa phân nhóm"


def _desc_html(prefix: str, name: str, obj, columns) -> str:
    parts = [f'<table border="1" style="font-size:12px;border-collapse:collapse;">'
             f'<tr style="background:#005A9E;color:#fff;"><th colspan="2" style="padding:2px;">'
             f'{prefix}: {html.escape(name)}</th></tr>']
    for c in columns:
        v = getattr(obj, c["attr"], None)
        if c["conv"] is not None:
            v = c["conv"](v)
        cv = format_cell_value(v, c["label"])
        if cv != "":
            parts.append(f'<tr><td style="padding:2px;font-weight:bold;background:#eee;">'
                         f'{html.escape(c["label"])}</td><td style="padding:2px;">{html.escape(cv)}</td></tr>')
    parts.append('</table>')
    return "".join(parts)


def build_kmz(layer_key: str, rows: list, columns, options: Optional[Dict[str, Any]] = None) -> KmzResult:
    cfg = LAYERS[layer_key]
    valid_attrs = {c["attr"] for c in columns}
    o = normalize_options(layer_key, options, valid_attrs)

    lkey = cfg["lkey"]
    is_site = lkey == "site"
    mode = o["color_mode"]
    is_heatmap = mode in ("heatmap", "heatmap_reverse")
    is_rev = mode == "heatmap_reverse"
    force_1024 = mode == "palette1024"
    alpha_hex, fill_mode = OPACITY_MAP[o["opacity"]]
    color_col, icon_col, folder = o["color_col"], o["icon_col"], o["folder"]
    filename = make_filename(layer_key, o)

    # ---- rows with usable coordinates --------------------------------------
    total = len(rows)
    points: List[Tuple[Any, float, float]] = []
    for r in rows:
        lat = _to_float(getattr(r, "lat", None))
        lon = _to_float(getattr(r, "long", None))
        if lat is None or lon is None:
            continue
        points.append((r, lat, lon))

    # ---- pre-pass: unique values / heatmap range / frequencies / icons ------
    raw_unique, raw_nums, freqs, icons = set(), [], set(), set()
    freq_attr = cfg["freq_attr"]
    for r, _la, _lo in points:
        if freq_attr:
            f = _to_float(getattr(r, freq_attr, None))
            if f is not None:
                freqs.add(f)
        cv = getattr(r, color_col, None)
        cs = _norm(cv)
        if cs != "":
            if is_heatmap:
                n = _to_num(cv)
                if n is not None:
                    raw_nums.append(n)
            else:
                raw_unique.add(cs)
        if icon_col:
            iv = _norm(getattr(r, icon_col, None))
            if iv:
                icons.add(iv)

    hm_min, hm_max = 0.0, 1.0
    if raw_nums:
        hm_min, hm_max = min(raw_nums), max(raw_nums)
        if hm_max == hm_min:
            hm_max = hm_min + 1.0

    def heat_ratio(n):
        return max(0.0, min(1.0, (n - hm_min) / (hm_max - hm_min)))

    icon_index = {val: i for i, val in enumerate(sorted(icons))}
    discrete = {val: i for i, val in enumerate(sorted(raw_unique, key=_sort_key_val))}

    # ---- styles --------------------------------------------------------------
    styles: Dict[str, str] = {}

    def cell_style(style_id, rgb):
        if style_id not in styles:
            styles[style_id] = (
                f'<Style id="{style_id}">'
                f'<LineStyle><color>{to_kml_color(rgb, "FF")}</color><width>2</width></LineStyle>'
                f'<PolyStyle><color>{to_kml_color(rgb, alpha_hex)}</color><fill>{fill_mode}</fill><outline>1</outline></PolyStyle>'
                f'</Style>')
        return style_id

    def site_style(style_id, rgb, icon_url):
        if style_id not in styles:
            styles[style_id] = (
                f'<Style id="{style_id}">'
                f'<IconStyle><color>{to_kml_color(rgb, "FF")}</color><scale>1.0</scale>'
                f'<Icon><href>{icon_url}</href></Icon></IconStyle>'
                f'</Style>')
        return style_id

    tree: Dict[str, Dict[str, list]] = {}

    def add_to_tree(f1, f2, item):
        tree.setdefault(f1, {}).setdefault(f2, []).append(item)

    placed = 0

    # =========================================================================
    # SITES
    # =========================================================================
    if is_site:
        for r, lat, lon in points:
            f1 = _folder_value(r, folder)
            s_id = _norm(getattr(r, "site_name", None)) or "Site"

            cur_icon_url, icon_tag = DEFAULT_SITE_ICON, "def"
            if icon_col:
                iv = _norm(getattr(r, icon_col, None))
                if iv in icon_index:
                    cur_icon_url = get_site_icon_url(icon_index[iv])
                    icon_tag = f"ic{icon_index[iv]}"

            val = getattr(r, color_col, None)
            vs = _norm(val)
            key = vs.lower()
            if key in NAMED_COLOR_MAP:
                style_id = site_style(f"sn_{key}_{icon_tag}", NAMED_COLOR_MAP[key], cur_icon_url)
            elif is_heatmap:
                n = _to_num(val)
                if n is None:
                    style_id = site_style(f"sdef_{icon_tag}", (255, 0, 0), cur_icon_url)
                else:
                    ratio = heat_ratio(n)
                    style_id = site_style(f"shm_{int(ratio * 100)}_{'rev' if is_rev else 'norm'}_{icon_tag}",
                                          get_heatmap_rgb(ratio, reverse=is_rev), cur_icon_url)
            elif force_1024:
                rgb = get_color_from_1024(vs or None)
                style_id = site_style(f"sp_{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}_{icon_tag}", rgb, cur_icon_url)
            else:
                c_idx = discrete.get(vs if vs else "Unset", 0)
                style_id = site_style(f"sd_{c_idx}_{icon_tag}", get_high_contrast_rgb('site', c_idx), cur_icon_url)

            add_to_tree(f1, cfg["f2"], ('point', s_id, style_id,
                                        _desc_html("TRẠM", s_id, r, columns),
                                        f"{lon:.6f},{lat:.6f},0"))
            placed += 1

    # =========================================================================
    # CELLS
    # =========================================================================
    else:
        fixed_bw, min_len, max_len = cfg["beam"], cfg["min_len"], cfg["max_len"]
        sorted_freqs = sorted(freqs)
        freq_pos = {f: i for i, f in enumerate(sorted_freqs)}
        n_freq = len(sorted_freqs)

        def freq_length(f):
            if n_freq <= 1 or f not in freq_pos:
                return (min_len + max_len) / 2.0
            step = (max_len - min_len) / (n_freq - 1)
            return round(min_len + freq_pos[f] * step, 1)

        col_lower = color_col.lower()
        is_named_id = any(k in col_lower for k in NAMED_ID_KEYS)
        use_1024 = force_1024 or is_named_id or (len(raw_unique) > 8)

        records = []
        for idx, (r, lat, lon) in enumerate(points, start=2):
            f1 = _folder_value(r, folder)
            c_id = _norm(getattr(r, "cell_name", None)) or f"{cfg['tech']}_Cell_{idx}"

            az_raw = _norm(getattr(r, "azimuth", None))
            az_num = _to_float(az_raw)
            azimuth = (az_num % 360) if az_num is not None else 0.0

            cov_val = (_norm(getattr(r, "vung_phu_song", None)) or "outdoor").lower()
            is_indoor = (any(k in cov_val for k in ("indoor", "ibs", "trong nhà"))
                         or (az_num is None and az_raw.upper() in ("IBC", "IBS")))

            freq_num = _to_float(getattr(r, freq_attr, None)) if freq_attr else None
            freq_num = freq_num if freq_num is not None else 0.0
            cell_len = freq_length(freq_num)

            tv = getattr(r, color_col, None)
            if is_heatmap:
                n = _to_num(tv)
                if n is None:
                    style_id = cell_style(f"hm_{lkey}_def", (255, 0, 0))
                else:
                    ratio = heat_ratio(n)
                    style_id = cell_style(f"hm_{lkey}_{int(ratio * 100)}_{'rev' if is_rev else 'norm'}",
                                          get_heatmap_rgb(ratio, reverse=is_rev))
            elif use_1024:
                rgb = get_color_from_1024(_norm(tv) or None)
                style_id = cell_style(f"p_{lkey}_{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}", rgb)
            else:
                c_idx = discrete.get(_norm(tv) or "Unset", 0)
                style_id = cell_style(f"d_{lkey}_{c_idx}", get_high_contrast_rgb(lkey, c_idx))

            records.append({
                'folder1': f1, 'folder2': cfg["f2"], 'cell_id': c_id,
                'lat': lat, 'lon': lon, 'azimuth': azimuth, 'is_indoor': is_indoor,
                'freq': freq_num, 'cell_len': cell_len, 'style_id': style_id,
                'desc': _desc_html("CELL", c_id, r, columns),
            })

        # group cells of the same site/sector
        cluster_map: Dict[tuple, list] = {}
        for rec in records:
            lat_k, lon_k = round(rec['lat'], 6), round(rec['lon'], 6)
            if rec['is_indoor']:
                grp_key = (rec['folder1'], rec['folder2'], lat_k, lon_k, True, 0.0)
            else:
                grp_key = (rec['folder1'], rec['folder2'], lat_k, lon_k, False, round(rec['azimuth'], 1))
            cluster_map.setdefault(grp_key, []).append(rec)

        for grp_key, group_cells in cluster_map.items():
            f1_target, f2_target, is_ind = grp_key[0], grp_key[1], grp_key[4]

            if is_ind:
                r_inner_tier, r_outer_tier = IBS_RADIUS_TIERS.get(lkey, (20.0, 40.0))
                num_sectors = len(group_cells)
                group_cells.sort(key=lambda x: (x['freq'], x['cell_id']))

                if num_sectors == 1:
                    cell = group_cells[0]
                    poly_xml = calculate_ibs_slice_polygon_str(cell['lat'], cell['lon'],
                                                               r_inner_tier, r_outer_tier, 0.0, 360.0)
                    add_to_tree(f1_target, f2_target, ('cell', cell['cell_id'], cell['style_id'], cell['desc'], poly_xml))
                    placed += 1
                else:
                    slice_angle = 360.0 / num_sectors
                    gap_angle = min(4.0, slice_angle * 0.12)
                    for s_idx, cell in enumerate(group_cells):
                        base_start = s_idx * slice_angle
                        st_deg = base_start + (gap_angle / 2.0)
                        en_deg = base_start + slice_angle - (gap_angle / 2.0)
                        poly_xml = calculate_ibs_slice_polygon_str(cell['lat'], cell['lon'],
                                                                   r_inner_tier, r_outer_tier, st_deg, en_deg)
                        add_to_tree(f1_target, f2_target, ('cell', cell['cell_id'], cell['style_id'], cell['desc'], poly_xml))
                        placed += 1
            else:
                n_c = len(group_cells)
                if n_c > 1:
                    group_cells.sort(key=lambda x: (x['cell_len'], x['cell_id']), reverse=True)
                    step_len = max(20.0, min_len * 0.12)
                    for idx_c, cell in enumerate(group_cells):
                        if idx_c > 0 and cell['cell_len'] >= group_cells[idx_c - 1]['cell_len']:
                            cell['cell_len'] = max(min_len * 0.6, group_cells[idx_c - 1]['cell_len'] - step_len)
                        dynamic_bw = fixed_bw + ((n_c - 1 - idx_c) * 3.0)
                        poly_xml = calculate_cell_polygon_str(cell['lat'], cell['lon'], cell['azimuth'],
                                                              dynamic_bw, cell['cell_len'])
                        draw_order_tag = f"<gx:drawOrder>{idx_c + 1}</gx:drawOrder>"
                        poly_xml = poly_xml.replace("<outerBoundaryIs>", f"{draw_order_tag}<outerBoundaryIs>")
                        add_to_tree(f1_target, f2_target, ('cell', cell['cell_id'], cell['style_id'], cell['desc'], poly_xml))
                        placed += 1
                else:
                    cell = group_cells[0]
                    poly_xml = calculate_cell_polygon_str(cell['lat'], cell['lon'], cell['azimuth'],
                                                          fixed_bw, cell['cell_len'])
                    add_to_tree(f1_target, f2_target, ('cell', cell['cell_id'], cell['style_id'], cell['desc'], poly_xml))
                    placed += 1

    # =========================================================================
    # KML assembly + KMZ zip
    # =========================================================================
    def sort_f2_order(name):
        low = name.lower()
        if low == 'site':
            return 0
        if '3g' in low:
            return 1
        if '4g' in low:
            return 2
        if '5g' in low:
            return 3
        return 4

    kml = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2"><Document>',
        f'<name>{html.escape(filename)}</name>',
    ]
    kml.extend(styles.values())

    for f1_name in sorted(tree.keys(), key=str):
        kml.append(f'<Folder><name>{html.escape(str(f1_name))}</name>')
        for f2_name in sorted(tree[f1_name].keys(), key=sort_f2_order):
            items = tree[f1_name][f2_name]
            if not items:
                continue
            kml.append(f'<Folder><name>{html.escape(str(f2_name))}</name>')
            for itype, i_id, i_style, i_desc, i_geo in items:
                if itype == 'point':
                    kml.append(
                        f'<Placemark><name>{html.escape(i_id)}</name><styleUrl>#{i_style}</styleUrl>'
                        f'<description><![CDATA[{i_desc}]]></description>'
                        f'<Point><coordinates>{i_geo}</coordinates></Point></Placemark>')
                else:
                    kml.append(
                        f'<Placemark><name>{html.escape(i_id)}</name><styleUrl>#{i_style}</styleUrl>'
                        f'<description><![CDATA[{i_desc}]]></description>{i_geo}</Placemark>')
            kml.append('</Folder>')
        kml.append('</Folder>')
    kml.append('</Document></kml>')

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, mode="w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        zf.writestr("doc.kml", "".join(kml).encode("utf-8"))
    return KmzResult(data=buf.getvalue(), filename=filename, total=total, valid=placed)
