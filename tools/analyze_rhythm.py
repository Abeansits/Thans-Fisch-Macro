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
