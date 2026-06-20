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
