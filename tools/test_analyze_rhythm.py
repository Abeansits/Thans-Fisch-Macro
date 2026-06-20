import os
import sys
import pytest
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import analyze_rhythm as ar

FX = os.path.join(os.path.dirname(__file__), "fixtures")
CAVE = os.path.join(FX, "cave.png")
SWAMP = os.path.join(FX, "swamp.png")
STOP = os.path.join(FX, "stop.png")


def test_brightness_is_max_channel():
    assert ar.brightness((10, 20, 30)) == 30


def test_colorfulness_is_range():
    assert ar.colorfulness((10, 20, 35)) == 25


def test_find_four_rings_in_cave():
    rings = ar.find_rings(Image.open(CAVE).convert("RGB"))
    assert len(rings) == 4


def test_find_four_rings_in_swamp():
    rings = ar.find_rings(Image.open(SWAMP).convert("RGB"))
    assert len(rings) == 4


def test_stop_tolerates_note_occluding_a_ring():
    # In stop.png a note sits on the F ring, so its interior is filled and
    # that ring is not a hollow ring -> at least the other three are found.
    rings = ar.find_rings(Image.open(STOP).convert("RGB"))
    assert len(rings) >= 3


def test_rings_sorted_left_to_right():
    rings = ar.find_rings(Image.open(CAVE).convert("RGB"))
    xs = [r.cx for r in rings]
    assert xs == sorted(xs)


def test_empty_ring_interior_is_dark():
    img = Image.open(CAVE).convert("RGB")
    pix = img.load()
    for r in ar.find_rings(img):
        assert ar.interior_brightness(pix, r.cx, r.cy) < 50


def test_lane_fractions_match_measured():
    geo = ar.lane_geometry(Image.open(CAVE).convert("RGB"))
    assert geo["n_rings"] == 4
    for got, exp in zip(geo["lane_fx"], [0.3512, 0.4502, 0.5492, 0.6480]):
        assert abs(got - exp) < 0.01
    assert abs(geo["ring_fy"] - 0.7653) < 0.01
    assert abs(geo["radius_fy"] - 0.0486) < 0.01


def test_emit_constants_has_required_keys():
    geo = ar.lane_geometry(Image.open(CAVE).convert("RGB"))
    out = ar.emit_constants(geo)
    for key in ("LaneDFrac=", "LaneFFrac=", "LaneJFrac=", "LaneKFrac=",
                "RingFracY=", "RadiusFracY=", "BrightnessThreshold=110",
                "HitOffsetPixels=15"):
        assert key in out
