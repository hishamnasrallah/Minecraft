"""BlockWorld — a small voxel sandbox built with Ursina.

Controls:
  WASD / mouse   move / look        Space   jump
  Hold left      mine block         Right click  place block
  1-9 / scroll   choose hotbar slot E      inventory & crafting
  T              fast-forward time  F5     save
  Esc            close inventory / save and quit

  python main.py --new        start a new world
  python main.py --creative   unlimited blocks
"""
import math
import sys
from pathlib import Path

from ursina import (Ursina, Entity, Mesh, Sky, Text, Texture, Color, Vec3, camera, color,
                    raycast, destroy, application, window, held_keys, time, scene, lerp, clamp, mouse)
from ursina.shaders import unlit_shader
from ursina.prefabs.first_person_controller import FirstPersonController

from world import World, WATER, UNBREAKABLE, TRANSPARENT, WATER_LEVEL
from inventory import (Inventory, ITEMS, ITEM_ICONS, PLACEABLE, RECIPES, HOTBAR_SIZE, STACK_SIZE, TOOLS,
                       NEEDS_TOOL, drop_for, mining, recipe_text)
from textures import load_atlas, tile_image, crack_stages
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

CREATIVE = "--creative" in sys.argv

if SAVE_FILE.exists() and "--new" not in sys.argv:
    world = World.load(SAVE_FILE)
else:
    world = World()

if CREATIVE:
    inventory = Inventory()
    for item in [1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13]:
        inventory.add(item, STACK_SIZE)
else:
    inventory = Inventory.from_data(world.player_data.get("inventory"))

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
spawn = tuple(world.player_data.get("position") or world.spawn_point())
spawn_chunk = world.chunk_key(round(spawn[0]), round(spawn[2]))
for dx in (-1, 0, 1):
    for dz in (-1, 0, 1):
        build_chunk((spawn_chunk[0] + dx, spawn_chunk[1] + dz))

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

# ---------------------------------------------------------------- item UI
ICONS = {}
for item_id, tile in ITEM_ICONS.items():
    ICONS[item_id] = Texture(tile_image(atlas_image, tile))
    ICONS[item_id].filtering = None


class SlotView:
    """A square slot showing an item icon and a stack count. Clickable if it has an index."""

    def __init__(self, parent, position, size=0.065, index=None):
        x, y = position
        self.frame = Entity(parent=parent, model="quad", color=color.black66, scale=size, position=(x, y, 0),
                            collider="box" if index is not None else None)
        self.frame.slot_index = index
        self.icon = Entity(parent=parent, model="quad", scale=size * 0.78, position=(x, y, -0.01), enabled=False)
        self.count = Text(parent=parent, text="", position=(x + size * 0.5, y - size * 0.3, -0.02),
                          origin=(0.5, -0.5), scale=0.8)
        # durability bar for tools
        self.size, self.x = size, x
        self.bar_back = Entity(parent=parent, model="quad", color=color.black, position=(x, y - size * 0.36, -0.02),
                               scale=(size * 0.8, size * 0.08), enabled=False)
        self.bar = Entity(parent=parent, model="quad", position=(x, y - size * 0.36, -0.03),
                          scale=(size * 0.8, size * 0.08), enabled=False)

    def show(self, stack):
        self.icon.enabled = bool(stack)
        if stack:
            self.icon.texture = ICONS[stack[0]]
        self.count.text = str(stack[1]) if stack and stack[1] > 1 and not CREATIVE else ""
        worn = bool(stack) and len(stack) == 3 and stack[2] < TOOLS[stack[0]][2]
        self.bar_back.enabled = self.bar.enabled = worn
        if worn:
            left = stack[2] / TOOLS[stack[0]][2]
            self.bar.scale_x = self.size * 0.8 * left
            self.bar.x = self.x - self.size * 0.4 * (1 - left)
            self.bar.color = lerp(color.red, color.lime, left)


# hotbar along the bottom of the screen
selected = 0
hud = Entity(parent=camera.ui)
hotbar_views = [SlotView(hud, ((i - (HOTBAR_SIZE - 1) / 2) * 0.07, -0.44)) for i in range(HOTBAR_SIZE)]
label = Text(parent=camera.ui, position=(0, -0.38), origin=(0, 0), scale=1.1)
status = Text(parent=camera.ui, position=(-0.85, 0.47), text="", scale=1)

# inventory + crafting screen (E)
inv_root = Entity(parent=camera.ui, enabled=False)
Entity(parent=inv_root, model="quad", scale=(4, 2), color=Color(0, 0, 0, 0.45), z=0.2)
Entity(parent=inv_root, model="quad", scale=(0.74, 0.5), position=(-0.33, 0.03, 0.1), color=Color(0.15, 0.15, 0.18, 0.92))
Entity(parent=inv_root, model="quad", scale=(0.74, 0.58), position=(0.44, 0.03, 0.1), color=Color(0.15, 0.15, 0.18, 0.92))
Text(parent=inv_root, text="Inventory", position=(-0.68, 0.25), scale=1.2)
Text(parent=inv_root, text="Crafting", position=(0.1, 0.29), scale=1.2)
inventory_views = []
for i in range(len(inventory.slots)):
    col = i % HOTBAR_SIZE
    # storage rows on top, the hotbar row separated at the bottom (like the HUD)
    y = -0.15 if i < HOTBAR_SIZE else 0.17 - (i // HOTBAR_SIZE - 1) * 0.08
    inventory_views.append(SlotView(inv_root, (-0.65 + col * 0.08, y), size=0.072, index=i))
tooltip = Text(parent=inv_root, text="", position=(-0.68, -0.21), scale=1)

recipe_rows = []
for r, recipe in enumerate(RECIPES):
    y = 0.22 - r * 0.075
    row = Entity(parent=inv_root, model="quad", scale=(0.7, 0.065), position=(0.44, y, 0), collider="box")
    row.recipe_index = r
    icon = Entity(parent=inv_root, model="quad", texture=ICONS[recipe[1][0]], scale=0.05, position=(0.125, y, -0.01))
    text = Text(parent=inv_root, text=recipe_text(recipe), position=(0.165, y, -0.01), origin=(-0.5, 0), scale=0.9)
    recipe_rows.append(row)
Text(parent=inv_root, text="click a recipe to craft (shift = up to 16)", position=(0.1, -0.25), scale=0.8,
     color=color.light_gray)

cursor_view = SlotView(camera.ui, (0, 0), size=0.06)
cursor_view.frame.enabled = False
cursor_stack = None


def refresh_items():
    for i, view in enumerate(hotbar_views):
        view.show(inventory.slots[i])
        view.frame.color = color.white if i == selected else color.black66
    stack = inventory.slots[selected]
    label.text = ITEMS[stack[0]] if stack else ""
    if stack and len(stack) == 3:
        label.text += f"  ({stack[2]}/{TOOLS[stack[0]][2]})"
    if inv_root.enabled:
        for i, view in enumerate(inventory_views):
            view.show(inventory.slots[i])
        for row, recipe in zip(recipe_rows, RECIPES):
            row.color = Color(0.2, 0.45, 0.25, 1) if inventory.can_craft(recipe) else Color(0.25, 0.25, 0.28, 1)
    cursor_view.show(cursor_stack)


def select(i):
    global selected
    selected = i % HOTBAR_SIZE
    refresh_items()


def toggle_inventory():
    global cursor_stack
    inv_root.enabled = not inv_root.enabled
    player.enabled = not inv_root.enabled          # frees the mouse while the screen is open
    if not inv_root.enabled and cursor_stack:      # put back whatever was held on the cursor
        inventory.add(*cursor_stack)
        cursor_stack = None
    refresh_items()


select(0)


def flash(msg):
    status.text = msg
    status.alpha = 1
    status.fade_out(delay=1.5, duration=0.5)


def save():
    world.save(SAVE_FILE, player={
        "inventory": world.player_data.get("inventory") if CREATIVE else inventory.to_data(),
        "position": [player.x, player.y + 0.1, player.z],
    })


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
    return bool(changed)


def break_at(pos):
    block_id = world.get(*pos)
    if not block_id or block_id in UNBREAKABLE:
        return
    tool = inventory.item_at(selected)
    _, drops, wears = mining(block_id, tool)
    if not edit(pos, 0) or CREATIVE:
        return
    drop = drop_for(block_id) if drops else None
    if drop and inventory.add(drop):
        flash("Inventory full")
    if not drops and block_id in NEEDS_TOOL:
        flash(f"{ITEMS[block_id]} needs a pickaxe to drop anything")
    if wears and inventory.wear(selected):
        flash(f"Your {ITEMS[tool]} broke!")
    refresh_items()


# mining: hold the left button; cracks grow until the block breaks
CRACKS = []
for image in crack_stages():
    CRACKS.append(Texture(image))
    CRACKS[-1].filtering = None
highlight = Entity(model="wireframe_cube", color=Color(0, 0, 0, 0.85), scale=1.004, enabled=False)
crack = Entity(model="cube", scale=1.008, enabled=False, shader=unlit_shader)
mine_pos, mine_progress = None, 0.0


def update_mining():
    global mine_pos, mine_progress
    inside, _ = target() if player.enabled else (None, None)
    highlight.enabled = inside is not None
    if inside:
        highlight.position = inside
    block_id = world.get(*inside) if inside else 0
    if not CREATIVE and held_keys["left mouse"] and block_id and block_id not in UNBREAKABLE:
        if inside != mine_pos:                    # started on a new block (or looked away)
            mine_pos, mine_progress = inside, 0.0
        seconds, _, _ = mining(block_id, inventory.item_at(selected))
        mine_progress += time.dt / max(seconds, 0.05)
        if mine_progress >= 1:
            break_at(inside)
            mine_pos, mine_progress = None, 0.0
    else:
        mine_pos, mine_progress = None, 0.0
    crack.enabled = mine_pos is not None and mine_progress > 0
    if crack.enabled:
        crack.position = mine_pos
        crack.texture = CRACKS[min(int(mine_progress * len(CRACKS)), len(CRACKS) - 1)]


def place_block():
    item = inventory.item_at(selected)
    _, outside = target()
    if item not in PLACEABLE or not outside or overlaps_player(outside):
        return
    if edit(outside, item) and not CREATIVE:
        inventory.use_one(selected)
        refresh_items()


def inventory_click(right):
    global cursor_stack
    hovered = mouse.hovered_entity
    if getattr(hovered, "slot_index", None) is not None:
        if held_keys["shift"] and not right:
            inventory.quick_move(hovered.slot_index)
        else:
            cursor_stack = inventory.click(hovered.slot_index, cursor_stack, right=right)
    elif getattr(hovered, "recipe_index", None) is not None:
        recipe = RECIPES[hovered.recipe_index]
        times = 16 if held_keys["shift"] else 1
        made = sum(1 for _ in range(times) if inventory.craft(recipe))
        if not made:
            flash("Missing ingredients" if not inventory.can_craft(recipe) else "Inventory full")
    refresh_items()


def input(key):
    global time_speed
    if inv_root.enabled:
        if key in ("e", "escape"):
            toggle_inventory()
        elif key in ("left mouse down", "right mouse down"):
            inventory_click(right=key.startswith("right"))
        return
    if key == "left mouse down" and CREATIVE:
        inside, _ = target()
        if inside:
            break_at(inside)
    elif key == "right mouse down":
        place_block()
    elif key == "e":
        toggle_inventory()
    elif key == "t":
        time_speed = 1 if time_speed > 1 else 40
        flash("Time x40" if time_speed > 1 else "Time x1")
    elif key in [str(i + 1) for i in range(HOTBAR_SIZE)]:
        select(int(key) - 1)
    elif key == "scroll up":
        select(selected - 1)
    elif key == "scroll down":
        select(selected + 1)
    elif key == "f5":
        save()
        flash("Saved")
    elif key == "escape":
        save()
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
    update_mining()
    if inv_root.enabled:
        cursor_view.icon.position = (mouse.x, mouse.y, -0.2)
        cursor_view.count.position = (mouse.x + 0.028, mouse.y - 0.012, -0.21)
        hovered = mouse.hovered_entity
        index = getattr(hovered, "slot_index", None)
        tooltip.text = ITEMS[inventory.slots[index][0]] if index is not None and inventory.slots[index] else ""
        return
    # swimming: sink slowly, hold Space to rise; checking below the feet too lets you climb out onto the shore
    swimming = water_at(player.x, player.y + 0.6, player.z) or water_at(player.x, player.y - 1.1, player.z)
    player.speed = SWIM_SPEED if swimming else WALK_SPEED
    if swimming:
        player.air_time = min(player.air_time, 0.012)
        if held_keys["space"]:
            player.y += 4 * time.dt
            player.air_time = 0
    underwater.enabled = water_at(*camera.world_position)
    # safety net: a lag spike can make a fall skip past the ground; climb back out on top
    feet = (cell(player.x), cell(player.y + 0.3), cell(player.z))
    inside = world.get(*feet)
    if inside and inside not in TRANSPARENT:
        player.y = feet[1] + 0.5
        player.air_time = 0
    if player.y < -20:  # fell through the world somehow
        player.position = Vec3(*world.spawn_point())


app.run()
