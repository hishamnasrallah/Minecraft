"""BlockWorld — a small voxel sandbox built with Ursina.

Controls:
  WASD / mouse   move / look        Space   jump
  Left click     break block        Right click  place block
  1-8 / scroll   choose block       F5      save
  Esc            save and quit
"""
import sys
from pathlib import Path

from ursina import Ursina, Entity, Mesh, Sky, Text, Color, Vec3, camera, color, raycast, destroy, application, window
from ursina.prefabs.first_person_controller import FirstPersonController

from world import World, BLOCKS, HOTBAR

SAVE_FILE = Path(__file__).with_name("save.json")
REACH = 6

app = Ursina(title="BlockWorld", borderless=False, development_mode=False)
window.fps_counter.enabled = True

if SAVE_FILE.exists() and "--new" not in sys.argv:
    world = World.load(SAVE_FILE)
else:
    world = World().generate()

chunk_entities = {}


def build_chunk(key):
    old = chunk_entities.pop(key, None)
    if old:
        destroy(old)
    verts, cols = world.chunk_mesh(*key)
    if not verts:
        return
    mesh = Mesh(vertices=verts, colors=[Color(*c) for c in cols], mode="triangle")
    chunk_entities[key] = Entity(model=mesh, collider="mesh")


for key in list(world.chunks):
    build_chunk(key)

Sky()
player = FirstPersonController(position=world.spawn_point(), speed=6, jump_height=1.2)
player.cursor.color = color.white

# ---------------------------------------------------------------- hotbar UI
selected = 0
slots = []
for i, block_id in enumerate(HOTBAR):
    x = (i - (len(HOTBAR) - 1) / 2) * 0.07
    frame = Entity(parent=camera.ui, model="quad", color=color.black66, scale=0.065, position=(x, -0.44))
    Entity(parent=frame, model="quad", color=Color(*BLOCKS[block_id][1], 1), scale=0.75, z=-0.01)
    slots.append(frame)
label = Text(parent=camera.ui, position=(0, -0.38), origin=(0, 0), scale=1.1)
status = Text(parent=camera.ui, position=(-0.85, 0.47), text="", scale=1)


def select(i):
    global selected
    selected = i % len(HOTBAR)
    for j, s in enumerate(slots):
        s.color = color.white if j == selected else color.black66
    label.text = BLOCKS[HOTBAR[selected]][0]


select(0)


def flash(msg):
    status.text = msg
    status.fade_out(delay=1.5, duration=0.5)
    status.alpha = 1


# ---------------------------------------------------------------- interaction
def target():
    hit = raycast(camera.world_position, camera.forward, distance=REACH, ignore=[player])
    if not hit.hit:
        return None, None
    p, n = hit.world_point, hit.world_normal
    inside = tuple(round(p[i] - n[i] * 0.5) for i in range(3))
    outside = tuple(round(p[i] + n[i] * 0.5) for i in range(3))
    return inside, outside


def overlaps_player(pos):
    px, py, pz = round(player.x), player.y, round(player.z)
    return pos[0] == px and pos[2] == pz and pos[1] in (round(py + 0.5), round(py + 1.5))


def edit(pos, block_id):
    for key in world.set(*pos, block_id):
        build_chunk(key)


def input(key):
    if key == "left mouse down":
        inside, _ = target()
        if inside:
            edit(inside, 0)
    elif key == "right mouse down":
        _, outside = target()
        if outside and not overlaps_player(outside):
            edit(outside, HOTBAR[selected])
    elif key in [str(i + 1) for i in range(len(HOTBAR))]:
        select(int(key) - 1)
    elif key == "scroll up":
        select(selected - 1)
    elif key == "scroll down":
        select(selected + 1)
    elif key == "f5":
        world.save(SAVE_FILE)
        flash("Saved")
    elif key == "escape":
        world.save(SAVE_FILE)
        application.quit()


def update():
    if player.y < -20:  # fell off the edge
        player.position = Vec3(*world.spawn_point())


app.run()
