"""BlockWorld — a small voxel sandbox built with Ursina.

Controls:
  WASD / mouse   move / look        Space   jump
  Left click     break block        Right click  place block
  1-9 / scroll   choose block       F5      save
  T              fast-forward time  Esc     save and quit
"""
import math
import sys
from pathlib import Path

from ursina import (Ursina, Entity, Mesh, Sky, Text, Texture, Color, Vec3, camera, color,
                    raycast, destroy, application, window, held_keys, time, scene, lerp, clamp)
from ursina.shaders import unlit_shader
from ursina.prefabs.first_person_controller import FirstPersonController

from world import World, BLOCKS, BLOCK_TILES, HOTBAR, WATER
from textures import load_atlas, tile_image
from lighting import block_shader

SAVE_FILE = Path(__file__).with_name("save.json")
REACH = 6
RENDER_DISTANCE = 4       # chunks around the player that are drawn
CHUNKS_PER_FRAME = 1      # how many chunk meshes to build per frame (avoids stutter)
DAY_LENGTH = 600          # seconds for a full day + night
DAY_SKY = Color(0.62, 0.78, 0.95, 1)
NIGHT_SKY = Color(0.02, 0.03, 0.09, 1)
DUSK_SKY = Color(0.95, 0.55, 0.32, 1)
WALK_SPEED, SWIM_SPEED = 6, 3.5

app = Ursina(title="BlockWorld", borderless=False, development_mode=False)
window.fps_counter.enabled = True
window.color = DAY_SKY

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
    """A chunk is an empty parent with a solid mesh (with collider) and a see-through water mesh."""
    old = chunk_entities.pop(key, None)
    if old:
        destroy(old)
    parts = world.chunk_mesh(*key)
    root = Entity()
    for kind, (verts, cols, uvs) in parts.items():
        if not verts:
            continue
        mesh = Mesh(vertices=verts, colors=[Color(*c) for c in cols], uvs=uvs, mode="triangle")
        if kind == "solid":
            Entity(parent=root, model=mesh, texture=atlas, shader=block_shader, collider="mesh")
        else:
            # no collider: you can swim through it and aim at blocks behind it
            Entity(parent=root, model=mesh, texture=atlas, shader=block_shader,
                   color=Color(1, 1, 1, 0.72), double_sided=True)
    chunk_entities[key] = root


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

# shader inputs set on the scene root are inherited by every chunk
scene.set_shader_input("daylight", 1.0)
scene.set_shader_input("sky_tint", Vec3(1, 1, 1))
sky = Sky(color=DAY_SKY, texture=None)
sun = Entity(model="quad", color=Color(1, 0.95, 0.7, 1), scale=40, shader=unlit_shader, billboard=True)
moon = Entity(model="quad", color=Color(0.85, 0.88, 1, 1), scale=25, shader=unlit_shader, billboard=True)
clock = Text(parent=camera.ui, position=(0.78, 0.47), text="", scale=1)
time_speed = 1
player = FirstPersonController(position=spawn, speed=WALK_SPEED, jump_height=1.2)
player.cursor.color = color.white
underwater = Entity(parent=camera.ui, model="quad", scale=(3, 2), color=Color(0.1, 0.3, 0.7, 0.45), z=1, enabled=False)


def cell(v):
    """Integer block coordinate containing the point v (blocks are centred on integers)."""
    return math.floor(v + 0.5)


def water_at(x, y, z):
    return world.get(cell(x), cell(y), cell(z)) == WATER

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


relight_queue = []


def edit(pos, block_id):
    changed = world.set(*pos, block_id)
    for key in changed:
        if key in chunk_entities:
            build_chunk(key)
    # light can reach into the surrounding chunks too; update those over the next frames
    cx, cz = world.chunk_key(pos[0], pos[2])
    for key in [(cx + dx, cz + dz) for dx in (-1, 0, 1) for dz in (-1, 0, 1)]:
        if changed and key not in changed and key in chunk_entities and key not in relight_queue:
            relight_queue.append(key)


def input(key):
    global time_speed
    if key == "left mouse down":
        inside, _ = target()
        if inside:
            edit(inside, 0)
    elif key == "right mouse down":
        _, outside = target()
        if outside and not overlaps_player(outside):
            edit(outside, HOTBAR[selected])
    elif key == "t":
        time_speed = 1 if time_speed > 1 else 40
        flash("Time x40" if time_speed > 1 else "Time x1")
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


def update_sky():
    """Advance the clock and move the sun, moon, sky colour and daylight level."""
    world.time_of_day = (world.time_of_day + time.dt * time_speed / DAY_LENGTH) % 1
    angle = world.time_of_day * 2 * math.pi
    sun_height = math.sin(angle)
    day = clamp((sun_height + 0.15) / 0.45, 0, 1)            # 0 at night, 1 in daytime
    dusk = clamp(1 - abs(sun_height) / 0.35, 0, 1)            # orange glow near the horizon

    sky_color = lerp(lerp(NIGHT_SKY, DAY_SKY, day), DUSK_SKY, dusk * 0.7 * max(day, 0.5))
    sky.color = sky_color
    window.color = sky_color
    scene.set_shader_input("daylight", 0.16 + 0.84 * day)
    tint = lerp(Vec3(0.65, 0.75, 1.0), Vec3(1, 1, 1), day)
    scene.set_shader_input("sky_tint", lerp(tint, Vec3(1.0, 0.78, 0.6), dusk * 0.5))

    direction = Vec3(math.cos(angle), sun_height, 0.3).normalized()
    sun.world_position = camera.world_position + direction * 300
    moon.world_position = camera.world_position - direction * 300

    hours = (world.time_of_day * 24 + 6) % 24
    clock.text = f"{int(hours):02d}:{int(hours % 1 * 60):02d}"


def update():
    global current_center
    center = player_chunk()
    if center != current_center:
        current_center = center
        refresh_chunks(center)
    for _ in range(CHUNKS_PER_FRAME):
        if relight_queue:
            build_chunk(relight_queue.pop(0))
        elif build_queue:
            build_chunk(build_queue.pop(0))
    update_sky()
    # swimming: sink slowly, hold Space to rise; checking below the feet too lets you climb out onto the shore
    swimming = water_at(player.x, player.y + 0.6, player.z) or water_at(player.x, player.y - 1.1, player.z)
    player.speed = SWIM_SPEED if swimming else WALK_SPEED
    if swimming:
        player.air_time = min(player.air_time, 0.012)
        if held_keys["space"]:
            player.y += 4 * time.dt
            player.air_time = 0
    underwater.enabled = water_at(*camera.world_position)
    if player.y < -20:  # fell through the world somehow
        player.position = Vec3(*world.spawn_point())


app.run()
