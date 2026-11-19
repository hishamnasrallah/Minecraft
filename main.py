"""BlockWorld — a small voxel sandbox built with Ursina.

Controls:
  WASD / mouse   move / look        Space   jump
  Left click     break block        Right click  place block
  1-8 / scroll   choose block       F5      save
  Esc            save and quit
"""
import sys
from pathlib import Path

from ursina import (Ursina, Entity, Mesh, Sky, Text, Texture, Color, Vec3, camera, color,
                    raycast, destroy, application, window)
from ursina.prefabs.first_person_controller import FirstPersonController

from world import World, BLOCKS, BLOCK_TILES, HOTBAR
from textures import load_atlas, tile_image

SAVE_FILE = Path(__file__).with_name("save.json")
REACH = 6
RENDER_DISTANCE = 4       # chunks around the player that are drawn
CHUNKS_PER_FRAME = 2      # how many chunk meshes to build per frame (avoids stutter)
SKY_COLOR = Color(0.62, 0.78, 0.95, 1)

app = Ursina(title="BlockWorld", borderless=False, development_mode=False)
window.fps_counter.enabled = True
window.color = SKY_COLOR

if SAVE_FILE.exists() and "--new" not in sys.argv:
    world = World.load(SAVE_FILE)
else:
    world = World()

atlas_image = load_atlas()
atlas = Texture(atlas_image)
atlas.filtering = None    # crisp pixels

# ---------------------------------------------------------------- chunks
chunk_entities = {}
build_queue = []
current_center = None


def build_chunk(key):
    old = chunk_entities.pop(key, None)
    if old:
        destroy(old)
    verts, cols, uvs = world.chunk_mesh(*key)
    if not verts:
        return
    mesh = Mesh(vertices=verts, colors=[Color(*c) for c in cols], uvs=uvs, mode="triangle")
    chunk_entities[key] = Entity(model=mesh, texture=atlas, collider="mesh")


def chunk_distance(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def player_chunk():
    return world.chunk_key(round(player.x), round(player.z))


def refresh_chunks(center):
    """Queue missing chunks near the player (closest first) and drop far ones."""
    wanted = [(center[0] + dx, center[1] + dz)
              for dx in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1)
              for dz in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1)]
    wanted.sort(key=lambda k: (k[0] - center[0]) ** 2 + (k[1] - center[1]) ** 2)
    build_queue[:] = [k for k in wanted if k not in chunk_entities]

    for key in [k for k in chunk_entities if chunk_distance(k, center) > RENDER_DISTANCE + 1]:
        destroy(chunk_entities.pop(key))
    for key in [k for k in world.chunks if chunk_distance(k, center) > RENDER_DISTANCE + 3]:
        world.unload_chunk(key)


# ground under the spawn point must exist before the player starts falling
spawn = world.spawn_point()
for dx in (-1, 0, 1):
    for dz in (-1, 0, 1):
        build_chunk((dx, dz))

Sky(color=SKY_COLOR, texture=None)
player = FirstPersonController(position=spawn, speed=6, jump_height=1.2)
player.cursor.color = color.white

# ---------------------------------------------------------------- hotbar UI
selected = 0
slots = []
for i, block_id in enumerate(HOTBAR):
    x = (i - (len(HOTBAR) - 1) / 2) * 0.07
    frame = Entity(parent=camera.ui, model="quad", color=color.black66, scale=0.065, position=(x, -0.44))
    icon = Texture(tile_image(atlas_image, BLOCK_TILES[block_id][1]))
    icon.filtering = None
    Entity(parent=frame, model="quad", texture=icon, scale=0.8, z=-0.01)
    slots.append(frame)
label = Text(parent=camera.ui, position=(0, -0.38), origin=(0, 0), scale=1.1)
status = Text(parent=camera.ui, position=(-0.85, 0.47), text="", scale=1)


def select(i):
    global selected
    selected = i % len(HOTBAR)
    for j, s in enumerate(slots):
        s.color = color.white if j == selected else color.black66
    label.text = BLOCKS[HOTBAR[selected]]


select(0)


def flash(msg):
    status.text = msg
    status.alpha = 1
    status.fade_out(delay=1.5, duration=0.5)


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
        if key in chunk_entities:
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
    global current_center
    center = player_chunk()
    if center != current_center:
        current_center = center
        refresh_chunks(center)
    for _ in range(CHUNKS_PER_FRAME):
        if build_queue:
            build_chunk(build_queue.pop(0))
    if player.y < -20:  # fell through the world somehow
        player.position = Vec3(*world.spawn_point())


app.run()
