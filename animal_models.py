"""Blocky 3D models for the creatures in animals.py (drawing only, no behaviour).

Same shapes as godot/scripts/animal_view.gd (tests check they stay in step). Parts are
(name, position, size, colour); positions are relative to the centre of the feet (the body
centre for flyers) with the animal facing +z. "leg" parts hang down from the given hip and
swing while walking; "wing" / "tailfin" parts flap / wag in the Godot version and are drawn
still here. Colours are 0-255 RGB; VAR / VAR2 stand for the animal's colour variant and a
darker shade of it (wool colour for woollies, see PALETTES).
"""
import math

from ursina import Entity, Mesh, Color, Vec3, BoxCollider, destroy
from ursina.shaders import unlit_shader

from world import FACE_VERTS
from blocks import DYES
from animals import cell, SPECIES

CREAM = (224, 212, 189)
DARK = (31, 26, 23)
TAN = (161, 115, 71)
BELLY = (219, 194, 153)
HOOF = (64, 46, 31)
FEATHER = (153, 135, 107)
GREEN = (33, 115, 56)
ORANGE = (242, 153, 38)
WING = (115, 102, 82)
SHADOW = (38, 30, 56)
SHADOW_EDGE = (62, 48, 92)
GLOW = (150, 255, 225)
HORN = (196, 164, 112)
SOOT = (58, 50, 48)
SOOT_LIGHT = (92, 80, 74)
HEN = (190, 118, 62)
HEN_DARK = (112, 64, 34)
COMB = (204, 44, 44)
GOAT = (206, 200, 188)
GOAT_DARK = (120, 110, 98)
AMBER = (214, 168, 46)
FROG = (84, 152, 62)
FROG_BELLY = (206, 214, 146)
SHELL = (92, 112, 58)
SHELL_DARK = (66, 84, 42)
SHELL_RIM = (160, 146, 92)
TURTLE_SKIN = (128, 156, 96)
LIZARD = (204, 166, 96)
LIZARD_DARK = (150, 112, 60)
DEWLAP = (64, 126, 210)
BEAK = (236, 176, 52)
FIREGLOW = (214, 255, 110)
WING_PALE = (220, 225, 230)
BRAMBLE = (64, 82, 40)
BRAMBLE_DARK = (44, 58, 28)
THORN = (214, 200, 150)
EMBER = (255, 86, 60)
GLOB = (92, 142, 70)
GLOB_TOP = (130, 176, 84)
EYE_WHITE = (236, 232, 214)
PUPIL = (255, 216, 60)
VAR, VAR2 = "VAR", "VAR2"
PALETTES = {
    "rabbit": [(143, 117, 92), (236, 236, 240)],
    "fish": [(240, 138, 40), (184, 198, 208), (70, 122, 204)],
    "bird": [(66, 116, 204), (204, 66, 52), (134, 102, 70)],
    "butterfly": [(250, 210, 50), (246, 132, 36), (80, 150, 250), (244, 244, 236)],
}
SAME_AS = {"globlet": "glob"}          # drawn as a smaller copy of another species
SCALES = {"globlet": 0.5}

PARTS = {
    "rabbit": [
        ("body", (0.0, 0.22, 0.0), (0.32, 0.28, 0.46), VAR),
        ("head", (0.0, 0.4, 0.24), (0.24, 0.22, 0.22), VAR),
        ("ear", (0.06, 0.6, 0.21), (0.06, 0.22, 0.04), VAR),
        ("ear", (-0.06, 0.6, 0.21), (0.06, 0.22, 0.04), VAR),
        ("eye", (0.121, 0.43, 0.29), (0.02, 0.05, 0.05), DARK),
        ("eye", (-0.121, 0.43, 0.29), (0.02, 0.05, 0.05), DARK),
        ("tail", (0.0, 0.27, -0.26), (0.12, 0.12, 0.08), CREAM),
        ("paw", (0.09, 0.05, 0.15), (0.08, 0.1, 0.1), VAR),
        ("paw", (-0.09, 0.05, 0.15), (0.08, 0.1, 0.1), VAR),
        ("paw", (0.12, 0.06, -0.15), (0.1, 0.12, 0.16), VAR),
        ("paw", (-0.12, 0.06, -0.15), (0.1, 0.12, 0.16), VAR),
    ],
    "deer": [
        ("body", (0.0, 0.88, 0.0), (0.45, 0.42, 0.95), TAN),
        ("belly", (0.0, 0.68, 0.0), (0.4, 0.04, 0.8), BELLY),
        ("neck", (0.0, 1.14, 0.42), (0.2, 0.42, 0.2), TAN),
        ("head", (0.0, 1.36, 0.55), (0.24, 0.24, 0.34), TAN),
        ("nose", (0.0, 1.32, 0.735), (0.12, 0.1, 0.04), HOOF),
        ("ear", (0.15, 1.48, 0.5), (0.12, 0.07, 0.04), TAN),
        ("ear", (-0.15, 1.48, 0.5), (0.12, 0.07, 0.04), TAN),
        ("eye", (0.121, 1.4, 0.62), (0.02, 0.05, 0.05), DARK),
        ("eye", (-0.121, 1.4, 0.62), (0.02, 0.05, 0.05), DARK),
        ("patch", (0.0, 0.98, -0.5), (0.1, 0.14, 0.06), BELLY),
        ("leg", (0.15, 0.67, 0.36), (0.11, 0.67, 0.11), TAN),
        ("leg", (-0.15, 0.67, 0.36), (0.11, 0.67, 0.11), TAN),
        ("leg", (0.15, 0.67, -0.36), (0.11, 0.67, 0.11), TAN),
        ("leg", (-0.15, 0.67, -0.36), (0.11, 0.67, 0.11), TAN),
    ],
    "duck": [
        ("body", (0.0, 0.22, 0.0), (0.3, 0.25, 0.42), FEATHER),
        ("rump", (0.0, 0.3, -0.24), (0.18, 0.08, 0.1), WING),
        ("side", (0.16, 0.24, -0.02), (0.04, 0.16, 0.3), WING),
        ("side", (-0.16, 0.24, -0.02), (0.04, 0.16, 0.3), WING),
        ("head", (0.0, 0.46, 0.17), (0.18, 0.2, 0.18), GREEN),
        ("beak", (0.0, 0.42, 0.3), (0.1, 0.05, 0.1), ORANGE),
        ("eye", (0.091, 0.5, 0.21), (0.02, 0.04, 0.04), DARK),
        ("eye", (-0.091, 0.5, 0.21), (0.02, 0.04, 0.04), DARK),
        ("leg", (0.07, 0.1, 0.02), (0.05, 0.1, 0.05), ORANGE),
        ("leg", (-0.07, 0.1, 0.02), (0.05, 0.1, 0.05), ORANGE),
    ],
    "woolly": [
        ("fleece", (0.0, 0.58, 0.0), (0.86, 0.44, 0.9), VAR),
        ("fleece", (0.0, 0.86, -0.02), (0.7, 0.16, 0.76), VAR),
        ("bobble", (0.0, 0.98, -0.02), (0.36, 0.1, 0.4), VAR),
        ("puff", (0.0, 0.68, -0.5), (0.2, 0.2, 0.1), VAR),
        ("head", (0.0, 0.72, 0.54), (0.3, 0.3, 0.26), SOOT),
        ("forelock", (0.0, 0.9, 0.52), (0.34, 0.1, 0.3), VAR),
        ("horn", (0.2, 0.78, 0.5), (0.08, 0.2, 0.2), HORN),
        ("horn", (-0.2, 0.78, 0.5), (0.08, 0.2, 0.2), HORN),
        ("curl", (0.22, 0.66, 0.6), (0.08, 0.08, 0.1), HORN),
        ("curl", (-0.22, 0.66, 0.6), (0.08, 0.08, 0.1), HORN),
        ("eye", (0.08, 0.77, 0.671), (0.06, 0.05, 0.02), AMBER),
        ("eye", (-0.08, 0.77, 0.671), (0.06, 0.05, 0.02), AMBER),
        ("muzzle", (0.0, 0.64, 0.672), (0.14, 0.08, 0.02), SOOT_LIGHT),
        ("leg", (0.24, 0.3, 0.28), (0.12, 0.3, 0.12), SOOT),
        ("leg", (-0.24, 0.3, 0.28), (0.12, 0.3, 0.12), SOOT),
        ("leg", (0.24, 0.3, -0.28), (0.12, 0.3, 0.12), SOOT),
        ("leg", (-0.24, 0.3, -0.28), (0.12, 0.3, 0.12), SOOT),
    ],
    "hen": [
        ("body", (0.0, 0.34, 0.0), (0.34, 0.3, 0.42), HEN),
        ("breast", (0.0, 0.3, 0.21), (0.28, 0.22, 0.04), CREAM),
        ("head", (0.0, 0.58, 0.2), (0.2, 0.22, 0.2), HEN),
        ("comb", (0.0, 0.72, 0.2), (0.05, 0.08, 0.16), COMB),
        ("beak", (0.0, 0.56, 0.33), (0.08, 0.06, 0.08), BEAK),
        ("wattle", (0.0, 0.47, 0.31), (0.05, 0.07, 0.03), COMB),
        ("eye", (0.101, 0.62, 0.25), (0.02, 0.04, 0.04), DARK),
        ("eye", (-0.101, 0.62, 0.25), (0.02, 0.04, 0.04), DARK),
        ("plume", (0.0, 0.52, -0.22), (0.22, 0.26, 0.08), HEN_DARK),
        ("side", (0.18, 0.36, -0.02), (0.04, 0.2, 0.3), HEN_DARK),
        ("side", (-0.18, 0.36, -0.02), (0.04, 0.2, 0.3), HEN_DARK),
        ("leg", (0.08, 0.19, 0.0), (0.05, 0.19, 0.05), BEAK),
        ("leg", (-0.08, 0.19, 0.0), (0.05, 0.19, 0.05), BEAK),
    ],
    "goat": [
        ("body", (0.0, 0.76, 0.0), (0.42, 0.4, 0.8), GOAT),
        ("head", (0.0, 1.0, 0.48), (0.24, 0.26, 0.3), GOAT),
        ("horn", (0.08, 1.2, 0.42), (0.06, 0.18, 0.06), GOAT_DARK),
        ("horn", (-0.08, 1.2, 0.42), (0.06, 0.18, 0.06), GOAT_DARK),
        ("horn", (0.08, 1.27, 0.33), (0.06, 0.06, 0.14), GOAT_DARK),
        ("horn", (-0.08, 1.27, 0.33), (0.06, 0.06, 0.14), GOAT_DARK),
        ("beard", (0.0, 0.82, 0.6), (0.08, 0.14, 0.06), GOAT_DARK),
        ("ear", (0.17, 1.04, 0.44), (0.12, 0.05, 0.08), GOAT),
        ("ear", (-0.17, 1.04, 0.44), (0.12, 0.05, 0.08), GOAT),
        ("eye", (0.121, 1.05, 0.56), (0.02, 0.05, 0.06), AMBER),
        ("eye", (-0.121, 1.05, 0.56), (0.02, 0.05, 0.06), AMBER),
        ("nose", (0.0, 0.94, 0.632), (0.12, 0.06, 0.02), GOAT_DARK),
        ("scut", (0.0, 0.92, -0.42), (0.08, 0.1, 0.06), GOAT),
        ("leg", (0.13, 0.56, 0.3), (0.1, 0.56, 0.1), GOAT_DARK),
        ("leg", (-0.13, 0.56, 0.3), (0.1, 0.56, 0.1), GOAT_DARK),
        ("leg", (0.13, 0.56, -0.3), (0.1, 0.56, 0.1), GOAT_DARK),
        ("leg", (-0.13, 0.56, -0.3), (0.1, 0.56, 0.1), GOAT_DARK),
    ],
    "frog": [
        ("body", (0.0, 0.15, 0.0), (0.36, 0.2, 0.4), FROG),
        ("belly", (0.0, 0.05, 0.02), (0.32, 0.04, 0.36), FROG_BELLY),
        ("bulge", (0.1, 0.29, 0.12), (0.11, 0.1, 0.1), FROG),
        ("bulge", (-0.1, 0.29, 0.12), (0.11, 0.1, 0.1), FROG),
        ("eye", (0.1, 0.3, 0.171), (0.06, 0.06, 0.02), DARK),
        ("eye", (-0.1, 0.3, 0.171), (0.06, 0.06, 0.02), DARK),
        ("mouth", (0.0, 0.1, 0.201), (0.24, 0.02, 0.02), (50, 96, 40)),
        ("haunch", (0.2, 0.08, -0.12), (0.1, 0.12, 0.24), FROG),
        ("haunch", (-0.2, 0.08, -0.12), (0.1, 0.12, 0.24), FROG),
        ("foot", (0.14, 0.03, 0.15), (0.07, 0.06, 0.07), FROG),
        ("foot", (-0.14, 0.03, 0.15), (0.07, 0.06, 0.07), FROG),
    ],
    "turtle": [
        ("rim", (0.0, 0.15, 0.0), (0.66, 0.06, 0.76), SHELL_RIM),
        ("shell", (0.0, 0.26, 0.0), (0.58, 0.2, 0.68), SHELL),
        ("dome", (0.0, 0.4, 0.0), (0.42, 0.1, 0.5), SHELL_DARK),
        ("plate", (0.0, 0.456, 0.0), (0.2, 0.02, 0.24), SHELL),
        ("head", (0.0, 0.2, 0.44), (0.18, 0.16, 0.2), TURTLE_SKIN),
        ("eye", (0.091, 0.23, 0.5), (0.02, 0.04, 0.04), DARK),
        ("eye", (-0.091, 0.23, 0.5), (0.02, 0.04, 0.04), DARK),
        ("stub", (0.0, 0.15, -0.41), (0.06, 0.06, 0.1), TURTLE_SKIN),
        ("leg", (0.27, 0.14, 0.24), (0.14, 0.14, 0.14), TURTLE_SKIN),
        ("leg", (-0.27, 0.14, 0.24), (0.14, 0.14, 0.14), TURTLE_SKIN),
        ("leg", (0.27, 0.14, -0.24), (0.14, 0.14, 0.14), TURTLE_SKIN),
        ("leg", (-0.27, 0.14, -0.24), (0.14, 0.14, 0.14), TURTLE_SKIN),
    ],
    "lizard": [
        ("body", (0.0, 0.12, 0.0), (0.2, 0.12, 0.5), LIZARD),
        ("stripe", (0.0, 0.185, 0.0), (0.08, 0.01, 0.44), LIZARD_DARK),
        ("head", (0.0, 0.14, 0.33), (0.16, 0.1, 0.18), LIZARD),
        ("dewlap", (0.0, 0.07, 0.35), (0.08, 0.04, 0.12), DEWLAP),
        ("eye", (0.081, 0.17, 0.37), (0.02, 0.03, 0.04), DARK),
        ("eye", (-0.081, 0.17, 0.37), (0.02, 0.03, 0.04), DARK),
        ("tail", (0.0, 0.1, -0.44), (0.08, 0.06, 0.4), LIZARD_DARK),
        ("leg", (0.15, 0.08, 0.15), (0.12, 0.08, 0.06), LIZARD_DARK),
        ("leg", (-0.15, 0.08, 0.15), (0.12, 0.08, 0.06), LIZARD_DARK),
        ("leg", (0.15, 0.08, -0.15), (0.12, 0.08, 0.06), LIZARD_DARK),
        ("leg", (-0.15, 0.08, -0.15), (0.12, 0.08, 0.06), LIZARD_DARK),
    ],
    "fish": [
        ("body", (0.0, 0.15, 0.0), (0.14, 0.2, 0.4), VAR),
        ("belly", (0.0, 0.06, 0.02), (0.12, 0.04, 0.32), CREAM),
        ("fin", (0.0, 0.28, -0.02), (0.03, 0.08, 0.18), VAR2),
        ("eye", (0.071, 0.18, 0.12), (0.02, 0.04, 0.04), DARK),
        ("eye", (-0.071, 0.18, 0.12), (0.02, 0.04, 0.04), DARK),
        ("tailfin", (0.0, 0.15, -0.27), (0.03, 0.2, 0.14), VAR2),
    ],
    "bird": [
        ("body", (0.0, 0.0, 0.0), (0.16, 0.14, 0.3), VAR),
        ("head", (0.0, 0.06, 0.18), (0.13, 0.13, 0.13), VAR),
        ("beak", (0.0, 0.05, 0.28), (0.04, 0.04, 0.07), BEAK),
        ("tail", (0.0, 0.02, -0.22), (0.1, 0.03, 0.14), VAR2),
        ("eye", (0.066, 0.08, 0.21), (0.01, 0.03, 0.03), DARK),
        ("eye", (-0.066, 0.08, 0.21), (0.01, 0.03, 0.03), DARK),
        ("wing", (0.18, 0.03, 0.0), (0.22, 0.02, 0.16), VAR2),
        ("wing", (-0.18, 0.03, 0.0), (0.22, 0.02, 0.16), VAR2),
    ],
    "butterfly": [
        ("body", (0.0, 0.0, 0.0), (0.03, 0.03, 0.14), DARK),
        ("wing", (0.08, 0.0, 0.02), (0.14, 0.01, 0.14), VAR),
        ("wing", (-0.08, 0.0, 0.02), (0.14, 0.01, 0.14), VAR),
        ("wing", (0.06, 0.0, -0.07), (0.1, 0.01, 0.08), VAR2),
        ("wing", (-0.06, 0.0, -0.07), (0.1, 0.01, 0.08), VAR2),
    ],
    "firefly": [
        ("body", (0.0, 0.0, 0.02), (0.04, 0.04, 0.07), DARK),
        ("glow", (0.0, -0.005, -0.045), (0.07, 0.07, 0.07), FIREGLOW),
        ("wing", (0.03, 0.025, 0.01), (0.05, 0.005, 0.04), WING_PALE),
        ("wing", (-0.03, 0.025, 0.01), (0.05, 0.005, 0.04), WING_PALE),
    ],
    "gloom": [
        ("body", (0.0, 1.0, 0.0), (0.5, 0.8, 0.3), SHADOW),
        ("head", (0.0, 1.62, 0.0), (0.44, 0.4, 0.4), SHADOW_EDGE),
        ("glow", (0.1, 1.66, 0.205), (0.1, 0.06, 0.02), GLOW),
        ("glow", (-0.1, 1.66, 0.205), (0.1, 0.06, 0.02), GLOW),
        ("arm", (0.33, 1.0, 0.05), (0.12, 0.75, 0.12), SHADOW_EDGE),
        ("arm", (-0.33, 1.0, 0.05), (0.12, 0.75, 0.12), SHADOW_EDGE),
        ("leg", (0.12, 0.6, 0.0), (0.16, 0.6, 0.16), SHADOW),
        ("leg", (-0.12, 0.6, 0.0), (0.16, 0.6, 0.16), SHADOW),
    ],
    "bramble": [
        ("body", (0.0, 0.38, 0.0), (0.9, 0.4, 0.9), BRAMBLE),
        ("top", (0.0, 0.64, -0.04), (0.62, 0.16, 0.62), BRAMBLE_DARK),
        ("knot", (0.12, 0.76, 0.08), (0.22, 0.1, 0.22), BRAMBLE),
        ("thorn", (0.49, 0.42, 0.2), (0.1, 0.05, 0.05), THORN),
        ("thorn", (-0.49, 0.46, -0.12), (0.1, 0.05, 0.05), THORN),
        ("thorn", (0.49, 0.36, -0.26), (0.1, 0.05, 0.05), THORN),
        ("thorn", (-0.49, 0.34, 0.26), (0.1, 0.05, 0.05), THORN),
        ("thorn", (0.22, 0.76, -0.18), (0.05, 0.12, 0.05), THORN),
        ("thorn", (-0.18, 0.78, 0.14), (0.05, 0.12, 0.05), THORN),
        ("thorn", (0.04, 0.86, 0.1), (0.05, 0.1, 0.05), THORN),
        ("thorn", (-0.1, 0.44, -0.49), (0.05, 0.05, 0.1), THORN),
        ("glow", (0.2, 0.46, 0.451), (0.12, 0.07, 0.02), EMBER),
        ("glow", (-0.2, 0.46, 0.451), (0.12, 0.07, 0.02), EMBER),
        ("maw", (0.0, 0.28, 0.451), (0.36, 0.05, 0.02), (26, 20, 14)),
        ("leg", (0.36, 0.2, 0.3), (0.12, 0.2, 0.12), BRAMBLE_DARK),
        ("leg", (-0.36, 0.2, 0.3), (0.12, 0.2, 0.12), BRAMBLE_DARK),
        ("leg", (0.36, 0.2, 0.0), (0.12, 0.2, 0.12), BRAMBLE_DARK),
        ("leg", (-0.36, 0.2, 0.0), (0.12, 0.2, 0.12), BRAMBLE_DARK),
        ("leg", (0.36, 0.2, -0.3), (0.12, 0.2, 0.12), BRAMBLE_DARK),
        ("leg", (-0.36, 0.2, -0.3), (0.12, 0.2, 0.12), BRAMBLE_DARK),
    ],
    "glob": [
        ("base", (0.0, 0.25, 0.0), (1.0, 0.5, 0.9), GLOB),
        ("top", (0.0, 0.62, 0.0), (0.72, 0.26, 0.66), GLOB),
        ("moss", (0.0, 0.76, 0.0), (0.5, 0.04, 0.5), GLOB_TOP),
        ("stalk", (0.0, 0.84, 0.1), (0.08, 0.16, 0.08), GLOB_TOP),
        ("white", (0.0, 0.98, 0.12), (0.2, 0.16, 0.16), EYE_WHITE),
        ("glow", (0.0, 0.98, 0.205), (0.1, 0.1, 0.02), PUPIL),
        ("drip", (0.36, 0.3, 0.46), (0.1, 0.2, 0.04), GLOB_TOP),
        ("drip", (-0.4, 0.2, -0.46), (0.1, 0.2, 0.04), GLOB_TOP),
        ("mouth", (0.0, 0.3, 0.451), (0.5, 0.06, 0.02), (36, 52, 30)),
        ("tooth", (0.12, 0.255, 0.455), (0.06, 0.05, 0.02), THORN),
        ("tooth", (-0.12, 0.255, 0.455), (0.06, 0.05, 0.02), THORN),
    ],
}
MODELS = {kind: dict(size=(SPECIES[kind]["width"], SPECIES[kind]["height"], SPECIES[kind]["width"] * 1.4),
                     parts=PARTS[SAME_AS.get(kind, kind)])
          for kind in SPECIES}


def variant_colour(kind, variant):
    """0-255 RGB of an animal's colour variant."""
    if kind == "woolly":
        r, g, b = DYES[variant][1] if 0 <= variant < len(DYES) else (255, 255, 255)
        return tuple(int(c + (255 - c) * 0.12) for c in (r, g, b))
    palette = PALETTES.get(kind, [(255, 255, 255)])
    return palette[max(0, min(variant, len(palette) - 1))]


def part_colours(kind, variant):
    """Each part's colour (0..1 floats) with the variant filled in."""
    main = variant_colour(kind, variant)
    dark = tuple(int(c * 0.7) for c in main)
    out = []
    for _name, _pos, _size, col in MODELS[kind]["parts"]:
        rgb = main if col == VAR else dark if col == VAR2 else col
        out.append(tuple(c / 255 for c in rgb))
    return out


def box_mesh():
    """A unit cube whose faces are shaded like the terrain (top bright, bottom dark)."""
    verts, colors = [], []
    for _normal, shade, corners, _uvs in FACE_VERTS:
        verts.extend(corners)
        colors.extend([Color(shade, shade, shade, 1)] * 6)
    return Mesh(vertices=verts, colors=colors, mode="triangle")


class AnimalView:
    def __init__(self, animal):
        self.animal = animal
        model = MODELS[animal.kind]
        scale = SCALES.get(animal.kind, 1.0)
        self.root = Entity()
        self.root.animal = animal                 # lets a raycast hit find the animal
        w, h, length = model["size"]
        if not animal.ambient:
            self.root.collider = BoxCollider(self.root, center=Vec3(0, h / 2, 0), size=Vec3(w, h, length))
        self.body = Entity(parent=self.root, scale=scale)      # bobs up and down for hopping
        self.parts, self.legs = [], []
        for (name, pos, size, _col), col in zip(model["parts"], part_colours(animal.kind, animal.variant)):
            if name == "leg":
                hip = Entity(parent=self.body, position=pos)
                part = Entity(parent=hip, model=box_mesh(), scale=size, y=-size[1] / 2, shader=unlit_shader)
                self.legs.append(hip)
            else:
                part = Entity(parent=self.body, model=box_mesh(), position=pos, scale=size, shader=unlit_shader)
            self.parts.append((part, col, name == "glow"))
        self._light_timer = 0
        self.sync(0, 1.0, Vec3(1, 1, 1), None)

    def sync(self, dt, daylight, tint, world):
        a = self.animal
        self.root.position = (a.x, a.y, a.z)
        self.root.rotation_y = a.yaw
        self.root.scale = 0.55 if a.age > 0 else 1
        swing = math.sin(a.walk_phase) if a.moving else 0
        for i, hip in enumerate(self.legs):
            hip.rotation_x = swing * 35 * (1 if i % 2 == (i // 2) % 2 else -1)
        if a.kind == "rabbit":                   # rabbits hop instead of walking
            self.body.y = abs(math.sin(a.walk_phase * 0.5)) * 0.18 if a.moving else 0
        self._light_timer -= dt
        if a.hurt_time > 0:                      # flash red when hit
            for part, _, _ in self.parts:
                part.color = Color(1, 0.25, 0.25, 1)
            self._light_timer = 0
        elif world is not None and self._light_timer <= 0:
            self._light_timer = 0.3
            col = world.column(cell(a.x), cell(a.z))
            open_sky = col is not None and cell(a.y + 0.3) > col[0]
            b = max(daylight * (1.0 if open_sky else 0.3), 0.07)
            for part, (r, g, bl), glow in self.parts:
                k = 1.0 if glow else b
                part.color = Color(r * k * tint[0], g * k * tint[1], bl * k * tint[2], 1)

    def destroy(self):
        destroy(self.root)
