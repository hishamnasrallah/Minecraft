"""Blocky 3D models for the animals in animals.py (drawing only, no behaviour)."""
import math

from ursina import Entity, Mesh, Color, Vec3, BoxCollider, destroy
from ursina.shaders import unlit_shader

from world import FACE_VERTS
from animals import cell

# shapes are lists of (name, position, scale, colour); positions are relative to the
# centre of the feet with the animal facing +z. Parts named "leg*" swing while walking
# and are given as (hip position, size): they hang down from the hip.
FUR, CREAM, DARK = (0.56, 0.46, 0.36), (0.88, 0.83, 0.74), (0.12, 0.1, 0.09)
TAN, BELLY, HOOF = (0.63, 0.45, 0.28), (0.86, 0.76, 0.6), (0.25, 0.18, 0.12)
FEATHER, GREEN, ORANGE, WING = (0.6, 0.53, 0.42), (0.13, 0.45, 0.22), (0.95, 0.6, 0.15), (0.45, 0.4, 0.32)

MODELS = {
    "rabbit": dict(size=(0.4, 0.55, 0.6), parts=[
        ("body", (0, 0.22, 0), (0.32, 0.28, 0.46), FUR),
        ("head", (0, 0.4, 0.24), (0.24, 0.22, 0.22), FUR),
        ("ear", (0.06, 0.6, 0.21), (0.06, 0.22, 0.04), FUR),
        ("ear", (-0.06, 0.6, 0.21), (0.06, 0.22, 0.04), FUR),
        ("eye", (0.121, 0.43, 0.29), (0.02, 0.05, 0.05), DARK),
        ("eye", (-0.121, 0.43, 0.29), (0.02, 0.05, 0.05), DARK),
        ("tail", (0, 0.27, -0.26), (0.12, 0.12, 0.08), CREAM),
        ("leg", (0.09, 0.1, 0.15), (0.08, 0.1, 0.1), FUR),
        ("leg", (-0.09, 0.1, 0.15), (0.08, 0.1, 0.1), FUR),
        ("leg", (0.12, 0.12, -0.15), (0.1, 0.12, 0.16), FUR),
        ("leg", (-0.12, 0.12, -0.15), (0.1, 0.12, 0.16), FUR),
    ]),
    "deer": dict(size=(0.55, 1.55, 1.1), parts=[
        ("body", (0, 0.88, 0), (0.45, 0.42, 0.95), TAN),
        ("belly", (0, 0.68, 0), (0.4, 0.04, 0.8), BELLY),
        ("neck", (0, 1.14, 0.42), (0.2, 0.42, 0.2), TAN),
        ("head", (0, 1.36, 0.55), (0.24, 0.24, 0.34), TAN),
        ("nose", (0, 1.32, 0.735), (0.12, 0.1, 0.04), HOOF),
        ("ear", (0.15, 1.48, 0.5), (0.12, 0.07, 0.04), TAN),
        ("ear", (-0.15, 1.48, 0.5), (0.12, 0.07, 0.04), TAN),
        ("eye", (0.121, 1.4, 0.62), (0.02, 0.05, 0.05), DARK),
        ("eye", (-0.121, 1.4, 0.62), (0.02, 0.05, 0.05), DARK),
        ("tail", (0, 0.98, -0.5), (0.1, 0.14, 0.06), BELLY),
        ("leg", (0.15, 0.67, 0.36), (0.11, 0.67, 0.11), TAN),
        ("leg", (-0.15, 0.67, 0.36), (0.11, 0.67, 0.11), TAN),
        ("leg", (0.15, 0.67, -0.36), (0.11, 0.67, 0.11), TAN),
        ("leg", (-0.15, 0.67, -0.36), (0.11, 0.67, 0.11), TAN),
    ]),
    "duck": dict(size=(0.4, 0.6, 0.6), parts=[
        ("body", (0, 0.22, 0), (0.3, 0.25, 0.42), FEATHER),
        ("tail", (0, 0.3, -0.24), (0.18, 0.08, 0.1), WING),
        ("wing", (0.16, 0.24, -0.02), (0.04, 0.16, 0.3), WING),
        ("wing", (-0.16, 0.24, -0.02), (0.04, 0.16, 0.3), WING),
        ("head", (0, 0.46, 0.17), (0.18, 0.2, 0.18), GREEN),
        ("beak", (0, 0.42, 0.3), (0.1, 0.05, 0.1), ORANGE),
        ("eye", (0.091, 0.5, 0.21), (0.02, 0.04, 0.04), DARK),
        ("eye", (-0.091, 0.5, 0.21), (0.02, 0.04, 0.04), DARK),
        ("leg", (0.07, 0.1, 0.02), (0.05, 0.1, 0.05), ORANGE),
        ("leg", (-0.07, 0.1, 0.02), (0.05, 0.1, 0.05), ORANGE),
    ]),
}


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
        self.root = Entity()
        self.root.animal = animal                 # lets a raycast hit find the animal
        w, h, length = model["size"]
        self.root.collider = BoxCollider(self.root, center=Vec3(0, h / 2, 0), size=Vec3(w, h, length))
        self.body = Entity(parent=self.root)      # bobs up and down for hopping
        self.parts, self.legs = [], []
        for name, pos, scale, col in model["parts"]:
            if name == "leg":
                hip = Entity(parent=self.body, position=pos)
                part = Entity(parent=hip, model=box_mesh(), scale=scale, y=-scale[1] / 2, shader=unlit_shader)
                self.legs.append(hip)
            else:
                part = Entity(parent=self.body, model=box_mesh(), position=pos, scale=scale, shader=unlit_shader)
            self.parts.append((part, col))
        self._light_timer = 0
        self.sync(0, 1.0, Vec3(1, 1, 1), None)

    def sync(self, dt, daylight, tint, world):
        a = self.animal
        self.root.position = (a.x, a.y, a.z)
        self.root.rotation_y = a.yaw
        swing = math.sin(a.walk_phase) if a.moving else 0
        for i, hip in enumerate(self.legs):
            hip.rotation_x = swing * 35 * (1 if i % 2 == (i // 2) % 2 else -1)
        if a.kind == "rabbit":                   # rabbits hop instead of walking
            self.body.y = abs(math.sin(a.walk_phase * 0.5)) * 0.18 if a.moving else 0
            for hip in self.legs:
                hip.rotation_x = 0
        self._light_timer -= dt
        if a.hurt_time > 0:                      # flash red when hit
            for part, _ in self.parts:
                part.color = Color(1, 0.25, 0.25, 1)
            self._light_timer = 0
        elif world is not None and self._light_timer <= 0:
            self._light_timer = 0.3
            col = world.column(cell(a.x), cell(a.z))
            open_sky = col is not None and cell(a.y + 0.3) > col[0]
            b = max(daylight * (1.0 if open_sky else 0.3), 0.07)
            for part, (r, g, bl) in self.parts:
                part.color = Color(r * b * tint[0], g * b * tint[1], bl * b * tint[2], 1)

    def destroy(self):
        destroy(self.root)
