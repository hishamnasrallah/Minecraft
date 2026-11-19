"""BlockWorld — a small voxel sandbox built with Ursina.

Controls:
  WASD / mouse   move / look            Space        jump (double-tap in creative: fly)
  Hold left      mine / hit animal      Right click  place / use (doors, chests, beds, buckets) / eat
  Middle click   pick block             1-9 / scroll choose hotbar slot
  E              inventory & crafting / creative menu
  Ctrl           sprint (fly faster)    Shift        fly down
  N              noclip while flying    G            switch creative / survival
  T              fast-forward time      F1           hide the HUD
  F5             save                   Esc          close screen / save and quit

  python main.py --new        start a new world
  python main.py --creative   start in creative mode
"""
import math
import sys
from pathlib import Path

from ursina import (Ursina, Entity, Mesh, Sky, Text, Texture, Color, Vec3, Button, camera, color,
                    raycast, destroy, application, window, held_keys, time, scene, lerp, clamp, mouse)
from ursina.shaders import unlit_shader
from ursina.prefabs.first_person_controller import FirstPersonController
from ursina.prefabs.input_field import InputField

from world import World, WATER, TRANSPARENT
from blocks import BLOCK_DEFS, NON_SOLID, DOORS, STAIRS, facing_from_yaw, toggled_door
from inventory import (Inventory, ITEMS, ITEM_ICONS, PLACEABLE, RECIPES, HOTBAR_SIZE, TOOLS, NEEDS_TOOL, FOOD,
                       TABS, BUCKET, WATER_BUCKET, attack_damage, drop_for, mining, recipe_text, creative_items,
                       max_stack, new_stack, ingredient_name)
from textures import load_atlas, tile_image, crack_stages, hud_icons
import survival as sv
from survival import Survival, icons as bar_icons
from lighting import block_shader
from animals import Wildlife
from animal_models import AnimalView

SAVE_FILE = Path(__file__).with_name("save.json")
SURVIVAL_REACH, CREATIVE_REACH = 6, 10
RENDER_DISTANCE = 4       # chunks around the player that are drawn
CHUNKS_PER_FRAME = 1      # how many chunk meshes to build per frame (avoids stutter)
DAY_LENGTH = 600          # seconds for a full day + night
DAY_SKY = Color(0.62, 0.78, 0.95, 1)
NIGHT_SKY = Color(0.02, 0.03, 0.09, 1)
DUSK_SKY = Color(0.95, 0.55, 0.32, 1)
WALK_SPEED, SPRINT_SPEED, SWIM_SPEED, FLY_SPEED = 6, 8.5, 3.5, 10
STAIR_BASES = {stairs[0]: stairs for stairs in STAIRS.values()}

app = Ursina(title="BlockWorld", borderless=False, development_mode=False)
window.fps_counter.enabled = True
window.color = DAY_SKY

if SAVE_FILE.exists() and "--new" not in sys.argv:
    world = World.load(SAVE_FILE)
else:
    world = World()

creative = "--creative" in sys.argv or world.player_data.get("mode") == "creative"
inventory = Inventory.from_data(world.player_data.get("inventory"))
if creative and not any(inventory.slots):
    for item in [1, 22, 4, 7, 41, 12, 50, 48, 510]:
        inventory.add(item, max_stack(item))
health = Survival.from_data(world.player_data.get("survival"))
spawn_point = tuple(world.player_data.get("spawn") or world.spawn_point())

atlas_image = load_atlas()
atlas = Texture(atlas_image)
atlas.filtering = None    # crisp pixels

# ---------------------------------------------------------------- chunks
terrain = Entity()        # everything the player collides with lives under here
noclip_target = Entity()  # an empty collision world, used for noclip
chunk_entities = {}
build_queue = []
current_center = None


def build_chunk(key):
    """A chunk is a parent with up to four meshes: solid and translucent blocks collide,
    water and plants don't."""
    old = chunk_entities.pop(key, None)
    if old:
        destroy(old)
    parts = world.chunk_mesh(*key)
    root = Entity(parent=terrain)
    for kind, (verts, cols, uvs) in parts.items():
        if not verts:
            continue
        mesh = Mesh(vertices=verts, colors=[Color(*c) for c in cols], uvs=uvs, mode="triangle")
        if kind == "solid":
            Entity(parent=root, model=mesh, texture=atlas, shader=block_shader, collider="mesh")
        elif kind == "translucent":
            e = Entity(parent=root, model=mesh, texture=atlas, shader=block_shader, collider="mesh")
            e.set_shader_input("alpha_cut", 0.02)
        elif kind == "plants":                     # no collider: walk through plants, torches, ladders
            Entity(parent=root, model=mesh, texture=atlas, shader=block_shader)
        else:
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


def build_around(position):
    key = world.chunk_key(round(position[0]), round(position[2]))
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            if (key[0] + dx, key[1] + dz) not in chunk_entities:
                build_chunk((key[0] + dx, key[1] + dz))


# ground under the spawn point must exist before the player starts falling
start = tuple(world.player_data.get("position") or spawn_point)
build_around(start)

# shader inputs set on the scene root are inherited by every chunk
scene.set_shader_input("daylight", 1.0)
scene.set_shader_input("sky_tint", Vec3(1, 1, 1))
scene.set_shader_input("alpha_cut", 0.5)
sky = Sky(color=DAY_SKY, texture=None)
sun = Entity(model="quad", color=Color(1, 0.95, 0.7, 1), scale=40, shader=unlit_shader, billboard=True)
moon = Entity(model="quad", color=Color(0.85, 0.88, 1, 1), scale=25, shader=unlit_shader, billboard=True)
clock = Text(parent=camera.ui, position=(0.78, 0.47), text="", scale=1)
time_speed = 1
player = FirstPersonController(position=start, speed=WALK_SPEED, jump_height=1.2)
player.traverse_target = terrain
player.cursor.color = color.white
underwater = Entity(parent=camera.ui, model="quad", scale=(3, 2), color=Color(0.1, 0.3, 0.7, 0.45), z=1, enabled=False)
flying = noclip = False


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

    def __init__(self, parent, position, size=0.065, index=None, kind="slot"):
        x, y = position
        self.frame = Entity(parent=parent, model="quad", color=color.black66, scale=size, position=(x, y, 0),
                            collider="box" if index is not None else None)
        setattr(self.frame, kind + "_index", index)
        self.icon = Entity(parent=parent, model="quad", scale=size * 0.78, position=(x, y, -0.01), enabled=False)
        self.count = Text(parent=parent, text="", position=(x + size * 0.5, y - size * 0.3, -0.02),
                          origin=(0.5, -0.5), scale=0.8)
        # durability bar for tools
        self.size, self.x = size, x
        self.bar_back = Entity(parent=parent, model="quad", color=color.black, position=(x, y - size * 0.36, -0.02),
                               scale=(size * 0.8, size * 0.08), enabled=False)
        self.bar = Entity(parent=parent, model="quad", position=(x, y - size * 0.36, -0.03),
                          scale=(size * 0.8, size * 0.08), enabled=False)

    def show(self, stack, show_count=True):
        self.icon.enabled = bool(stack)
        if stack:
            self.icon.texture = ICONS[stack[0]]
        self.count.text = str(stack[1]) if stack and stack[1] > 1 and show_count else ""
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
label = Text(parent=camera.ui, position=(0, -0.345), origin=(0, 0), scale=1.1)
status = Text(parent=camera.ui, position=(-0.85, 0.47), text="", scale=1)
mode_text = Text(parent=camera.ui, position=(-0.85, 0.43), text="", scale=0.9, color=color.light_gray)

# ---- inventory screen (E): your inventory on the left, a panel on the right that is
# crafting (survival), the creative menu (creative) or a chest's contents
screen = Entity(parent=camera.ui, enabled=False)
Entity(parent=screen, model="quad", scale=(4, 2), color=Color(0, 0, 0, 0.45), z=0.2)
Entity(parent=screen, model="quad", scale=(0.74, 0.5), position=(-0.42, 0.03, 0.1), color=Color(0.15, 0.15, 0.18, 0.94))
Text(parent=screen, text="Inventory", position=(-0.77, 0.25), scale=1.2)
inventory_views = []
for i in range(len(inventory.slots)):
    col = i % HOTBAR_SIZE
    # storage rows on top, the hotbar row separated at the bottom (like the HUD)
    y = -0.15 if i < HOTBAR_SIZE else 0.17 - (i // HOTBAR_SIZE - 1) * 0.08
    inventory_views.append(SlotView(screen, (-0.74 + col * 0.08, y), size=0.072, index=i))
tooltip = Text(parent=screen, text="", position=(-0.77, -0.21), scale=1)

PANEL_X, PANEL_W = 0.4, 0.8
Entity(parent=screen, model="quad", scale=(PANEL_W, 0.76), position=(PANEL_X, 0.04, 0.1), color=Color(0.15, 0.15, 0.18, 0.94))
panel_title = Text(parent=screen, text="", position=(0.02, 0.4), scale=1.2)
search = InputField(parent=screen, default_value="", position=(0.53, 0.405), scale=(0.3, 0.04), character_limit=20)
search_hint = Text(parent=screen, text="search", position=(0.39, 0.413), scale=0.8, color=color.gray)
page_text = Text(parent=screen, text="", position=(PANEL_X, -0.255), origin=(0, 0), scale=0.9)
page = 0
tab = "all"
chest_pos = None
chest_inventory = None


def make_button(text, position, scale, on_click, parent=screen, text_size=0.8):
    return Button(parent=parent, text=text, position=position, scale=scale, color=Color(0.25, 0.25, 0.3, 1),
                  highlight_color=Color(0.35, 0.35, 0.45, 1), on_click=on_click, text_size=text_size)


# creative menu: tabs, a 9x5 palette, paging, trash, clear and time controls
creative_root = Entity(parent=screen)
tab_buttons = {}
for i, name in enumerate(TABS):
    tab_buttons[name] = make_button(name, (0.04 + i * 0.0805, 0.35), (0.077, 0.04),
                                    (lambda n: lambda: set_tab(n))(name), creative_root, 0.62)
PALETTE_COLS, PALETTE_ROWS = 9, 5
palette_views = [SlotView(creative_root, (0.08 + (i % PALETTE_COLS) * 0.08, 0.27 - (i // PALETTE_COLS) * 0.08),
                          size=0.072, index=i, kind="palette") for i in range(PALETTE_COLS * PALETTE_ROWS)]
make_button("prev", (0.2, -0.255), (0.05, 0.04), lambda: change_page(-1), creative_root)
make_button("next", (0.6, -0.255), (0.05, 0.04), lambda: change_page(1), creative_root)
trash = Entity(parent=creative_root, model="quad", scale=0.06, position=(0.76, -0.255), color=Color(0.5, 0.15, 0.15, 1),
               collider="box")
trash.trash = True
Text(parent=creative_root, text="X", position=(0.76, -0.255, -0.01), origin=(0, 0), scale=1.2)
make_button("clear inventory", (0.1, -0.31), (0.16, 0.04), lambda: clear_inventory(), creative_root)
for i, (name, value) in enumerate((("sunrise", 0.0), ("noon", 0.25), ("sunset", 0.5), ("midnight", 0.75))):
    make_button(name, (0.24 + i * 0.1, -0.31), (0.095, 0.04), (lambda v: lambda: set_time(v))(value), creative_root)
freeze_button = make_button("freeze time", (0.7, -0.31), (0.13, 0.04), lambda: toggle_freeze(), creative_root)

# survival: a paged recipe list (craftable recipes first)
crafting_root = Entity(parent=screen)
RECIPE_ROWS = 8
recipe_rows = []
for r in range(RECIPE_ROWS):
    y = 0.31 - r * 0.068
    row = Entity(parent=crafting_root, model="quad", scale=(0.76, 0.06), position=(PANEL_X, y, 0), collider="box")
    row.recipe_index = None
    icon = Entity(parent=crafting_root, model="quad", scale=0.048, position=(0.05, y, -0.01))
    text = Text(parent=crafting_root, text="", position=(0.085, y, -0.01), origin=(-0.5, 0), scale=0.8)
    recipe_rows.append((row, icon, text))
make_button("prev", (0.2, -0.255), (0.05, 0.04), lambda: change_page(-1), crafting_root)
make_button("next", (0.6, -0.255), (0.05, 0.04), lambda: change_page(1), crafting_root)
Text(parent=crafting_root, text="click a recipe to craft (shift = up to 16)", position=(0.02, -0.31), scale=0.8,
     color=color.light_gray)

# chests: 27 slots
chest_root = Entity(parent=screen)
chest_views = [SlotView(chest_root, (0.08 + (i % 9) * 0.08, 0.27 - (i // 9) * 0.08), size=0.072, index=i, kind="chest")
               for i in range(27)]

cursor_view = SlotView(camera.ui, (0, 0), size=0.06)
cursor_view.frame.enabled = False
cursor_stack = None


def visible_recipes():
    text = search.text.lower().strip()
    found = [r for r in RECIPES if not text or text in recipe_text(r).lower()]
    return sorted(found, key=lambda r: not inventory.can_craft(r))


def page_count(n, per_page):
    return max(1, -(-n // per_page))


def refresh_screen():
    global page
    creative_root.enabled = creative and chest_pos is None
    crafting_root.enabled = not creative and chest_pos is None
    chest_root.enabled = chest_pos is not None
    search.enabled = search_hint.enabled = chest_pos is None
    search_hint.enabled = search.enabled and not search.text
    for i, view in enumerate(inventory_views):
        view.show(inventory.slots[i], not creative)
    if chest_root.enabled:
        panel_title.text = "Chest"
        page_text.text = ""
        for i, view in enumerate(chest_views):
            view.show(chest_inventory.slots[i])
    elif creative_root.enabled:
        items = creative_items(tab, search.text)
        pages = page_count(len(items), len(palette_views))
        page = min(page, pages - 1)
        panel_title.text = "Creative"
        page_text.text = f"page {page + 1} / {pages}   ({len(items)} items)"
        shown = items[page * len(palette_views):(page + 1) * len(palette_views)]
        for i, view in enumerate(palette_views):
            item = shown[i] if i < len(shown) else None
            view.item = item
            view.frame.enabled = item is not None
            view.show((item, 1) if item else None)
        for name, b in tab_buttons.items():
            b.color = Color(0.3, 0.5, 0.75, 1) if name == tab else Color(0.25, 0.25, 0.3, 1)
        freeze_button.text = "unfreeze" if time_speed == 0 else "freeze time"
    else:
        recipes = visible_recipes()
        pages = page_count(len(recipes), RECIPE_ROWS)
        page = min(page, pages - 1)
        panel_title.text = "Crafting"
        page_text.text = f"page {page + 1} / {pages}"
        shown = recipes[page * RECIPE_ROWS:(page + 1) * RECIPE_ROWS]
        for r, (row, icon, text) in enumerate(recipe_rows):
            recipe = shown[r] if r < len(shown) else None
            row.enabled = icon.enabled = text.enabled = recipe is not None
            if recipe:
                row.recipe_index = RECIPES.index(recipe)
                icon.texture = ICONS[recipe[1][0]]
                text.text = recipe_text(recipe)
                row.color = Color(0.2, 0.45, 0.25, 1) if inventory.can_craft(recipe) else Color(0.25, 0.25, 0.28, 1)


def on_search():
    global page
    page = 0
    refresh_screen()


search.on_value_changed = on_search


def refresh_items():
    for i, view in enumerate(hotbar_views):
        view.show(inventory.slots[i], not creative)
        view.frame.color = color.white if i == selected else color.black66
    stack = inventory.slots[selected]
    label.text = ITEMS[stack[0]] if stack else ""
    if stack and len(stack) == 3:
        label.text += f"  ({stack[2]}/{TOOLS[stack[0]][2]})"
    mode_text.text = ("creative" + (" - flying" if flying else "") + (" - noclip" if noclip else "")) if creative else ""
    if screen.enabled:
        refresh_screen()
    cursor_view.show(cursor_stack, not creative)


def set_tab(name):
    global tab, page
    tab, page = name, 0
    refresh_screen()


def change_page(step):
    global page
    page = max(0, page + step)
    refresh_screen()


def clear_inventory():
    inventory.slots = [None] * len(inventory.slots)
    refresh_items()


def set_time(value):
    world.time_of_day = value
    flash(f"Time set to {['sunrise', 'noon', 'sunset', 'midnight'][int(value * 4)]}")


def toggle_freeze():
    global time_speed
    time_speed = 1 if time_speed == 0 else 0
    flash("Time frozen" if time_speed == 0 else "Time running")
    refresh_screen()


def select(i):
    global selected
    selected = i % HOTBAR_SIZE
    refresh_items()


def open_screen(chest=None):
    global chest_pos, chest_inventory, page
    chest_pos = chest
    if chest is not None:
        chest_inventory = Inventory.from_data(world.containers.get(chest) or [None] * 27)
    page = 0
    screen.enabled = True
    player.enabled = False          # frees the mouse while the screen is open
    refresh_items()


def close_screen():
    global cursor_stack, chest_pos
    if chest_pos is not None:
        world.containers[chest_pos] = chest_inventory.to_data()
        chest_pos = None
    screen.enabled = False
    search.active = False
    player.enabled = not health.dead
    if cursor_stack and not creative:       # put back whatever was held on the cursor
        give_stack(inventory, cursor_stack)
    cursor_stack = None
    refresh_items()


select(0)


def give_stack(inv, stack):
    """Put a whole stack into an inventory (tools keep their durability). Returns what didn't fit."""
    if len(stack) == 3:
        empty = next((i for i, s in enumerate(inv.slots) if s is None), None)
        if empty is None:
            return stack
        inv.slots[empty] = stack
        return None
    left = inv.add(stack[0], stack[1])
    return (stack[0], left) if left else None


def flash(msg):
    status.text = msg
    status.alpha = 1
    status.fade_out(delay=1.5, duration=0.5)


def save():
    if screen.enabled and chest_pos is not None:
        world.containers[chest_pos] = chest_inventory.to_data()
    world.save(SAVE_FILE, player={
        "inventory": inventory.to_data(),
        "survival": health.to_data(),
        "position": [player.x, player.y + 0.1, player.z],
        "spawn": list(spawn_point),
        "mode": "creative" if creative else "survival",
    })


# ---------------------------------------------------------------- health & hunger HUD
HUD_TEX = {}
for name, image in hud_icons().items():
    HUD_TEX[name] = Texture(image)
    HUD_TEX[name].filtering = None
ICON = 0.028
left_edge = -(HOTBAR_SIZE * 0.07) / 2 + ICON / 2
hearts = [Entity(parent=hud, model="quad", scale=ICON, position=(left_edge + i * ICON * 1.05, -0.385)) for i in range(10)]
food_icons = [Entity(parent=hud, model="quad", scale=ICON, position=(-left_edge - i * ICON * 1.05, -0.385))
              for i in range(10)]
bubbles = [Entity(parent=hud, model="quad", scale=ICON, texture=HUD_TEX["bubble"],
                  position=(-left_edge - i * ICON * 1.05, -0.355)) for i in range(10)]
hurt_overlay = Entity(parent=camera.ui, model="quad", scale=(3, 2), color=Color(0.8, 0, 0, 0), z=0.5)
death_root = Entity(parent=camera.ui, enabled=False)
Entity(parent=death_root, model="quad", scale=(3, 2), color=Color(0.45, 0, 0, 0.6), z=0.3)
Text(parent=death_root, text="You died", origin=(0, 0), y=0.1, scale=3)
death_cause = Text(parent=death_root, text="", origin=(0, 0), y=0.0, scale=1.3)
Text(parent=death_root, text="Press R to respawn", origin=(0, 0), y=-0.1, scale=1.3)


def refresh_bars():
    for e in hearts + food_icons:
        e.enabled = not creative
    if creative:
        for e in bubbles:
            e.enabled = False
        return
    for e, state in zip(hearts, bar_icons(health.health, sv.MAX_HEALTH)):
        e.texture = HUD_TEX[f"heart_{state}"]
    for e, state in zip(food_icons, bar_icons(health.hunger, sv.MAX_HUNGER)):
        e.texture = HUD_TEX[f"food_{state}"]
    under = health.air < sv.MAX_AIR
    for i, e in enumerate(bubbles):
        e.enabled = under and i < math.ceil(health.air / sv.MAX_AIR * 10)


def hurt(amount):
    if amount > 0:
        hurt_overlay.color = Color(0.8, 0, 0, 0.35)
        hurt_overlay.animate_color(Color(0.8, 0, 0, 0), duration=0.4)
    if health.dead and not death_root.enabled:
        death_cause.text = f"You {health.cause}."
        death_root.enabled = True
        player.disable()


def respawn():
    health.respawn()
    death_root.enabled = False
    build_around(spawn_point)
    player.enable()
    player.position = Vec3(*spawn_point)
    player.air_time = 0
    refresh_bars()


# ---------------------------------------------------------------- game mode, flying
def set_mode(to_creative):
    global creative
    creative = to_creative
    if not creative:
        set_flying(False)
    health.fall_top = None
    flash("Creative mode" if creative else "Survival mode")
    refresh_bars()
    refresh_items()


def set_flying(on):
    global flying, noclip
    flying = on and creative
    player.gravity = 0 if flying else 1
    player.air_time = 0
    if flying:
        player.grounded = False
    else:
        noclip = False
        player.traverse_target = terrain
    refresh_items()


def toggle_noclip():
    global noclip
    if not flying:
        flash("Noclip works while flying (double-tap Space)")
        return
    noclip = not noclip
    player.traverse_target = noclip_target if noclip else terrain
    refresh_items()


last_space = -1.0


# ---------------------------------------------------------------- animals
wildlife = Wildlife(world)
animal_views = {}
daylight, sky_tint = 1.0, Vec3(1, 1, 1)


def attack(animal):
    item = inventory.item_at(selected)
    drops = animal.hit(player.x, player.z, damage=attack_damage(item) if not creative else 100)
    if creative:
        return
    health.exert(sv.ATTACK)
    if item in TOOLS and inventory.wear(selected):
        flash(f"Your {ITEMS[item]} broke!")
    for drop, count in drops:
        if inventory.add(drop, count):
            flash("Inventory full")
        else:
            flash(f"+{count} {ITEMS[drop]}")
    refresh_items()


def update_animals():
    wildlife.update(time.dt, (player.x, player.y, player.z))
    alive = set(wildlife.animals)
    for animal in [a for a in animal_views if a not in alive]:
        animal_views.pop(animal).destroy()
    for animal in wildlife.animals:
        if animal not in animal_views:
            animal_views[animal] = AnimalView(animal)
        animal_views[animal].sync(time.dt, daylight, sky_tint, world)


# ---------------------------------------------------------------- interaction
def reach():
    return CREATIVE_REACH if creative else SURVIVAL_REACH


def target(hit_water=False):
    """The block you are looking at and the empty cell in front of the face you look at."""
    pos, normal, _ = world.raycast(camera.world_position, camera.forward, reach(), hit_water)
    if pos is None:
        return None, None
    return pos, (pos[0] + normal[0], pos[1] + normal[1], pos[2] + normal[2])


def looked_at_animal():
    """The animal in your crosshair, if it is closer than the block behind it."""
    hit = raycast(camera.world_position, camera.forward, distance=reach(), ignore=[player], traverse_target=scene)
    animal = getattr(hit.entity, "animal", None) if hit.hit else None
    if animal is None:
        return None
    _, _, block_distance = world.raycast(camera.world_position, camera.forward, reach())
    return animal if block_distance is None or hit.distance < block_distance + 0.3 else None


def overlaps_player(pos, block_id):
    if noclip or not BLOCK_DEFS[block_id]["solid"]:
        return False
    px, py, pz = round(player.x), player.y, round(player.z)
    return pos[0] == px and pos[2] == pz and pos[1] in (round(py + 0.5), round(py + 1.5))


relight_queue = []


def edit(pos, block_id, force=False, flood=True):
    changed = world.set(*pos, block_id, force=force, flood=flood)
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
    d = BLOCK_DEFS.get(block_id)
    if not d or block_id == WATER or (d["hardness"] < 0 and not creative):
        return
    if d["hardness"] < 0:                           # creative can remove bedrock too
        edit(pos, 0, force=True)
        return
    tool = inventory.item_at(selected)
    _, drops, wears = mining(block_id, tool)
    contents = world.containers.pop(pos, None)
    if not edit(pos, 0) or creative:
        return
    health.exert(sv.MINE)
    drop = drop_for(block_id) if drops else None
    for item, count in ([(drop, 1)] if drop else []) + [(s[0], s[1]) for s in (contents or []) if s]:
        if inventory.add(item, count):
            flash("Inventory full")
    if not drops and block_id in NEEDS_TOOL:
        flash(f"{ITEMS[block_id]} needs a better tool to drop anything")
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
    looking_at_animal = player.enabled and looked_at_animal() is not None
    inside, _ = target() if player.enabled and not looking_at_animal else (None, None)
    highlight.enabled = inside is not None
    if inside:
        highlight.position = inside
    block_id = world.get(*inside) if inside else 0
    breakable = block_id and BLOCK_DEFS.get(block_id, {}).get("hardness", -1) >= 0
    if not creative and held_keys["left mouse"] and breakable:
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


def replaceable(pos):
    return world.get(*pos) in (0, WATER, 51, 52)


def use_block(pos):
    """Right click on a block that does something. Returns True if it handled the click."""
    global spawn_point
    block_id = world.get(*pos)
    if block_id in DOORS:                          # open / close both halves
        other = (pos[0], pos[1] + (-1 if DOORS[block_id]["top"] else 1), pos[2])
        for p in (pos, other):
            b = world.get(*p)
            if b in DOORS:
                edit(p, toggled_door(b))
        return True
    if BLOCK_DEFS.get(block_id, {}).get("container"):
        open_screen(chest=pos)
        return True
    if block_id == 62:                             # bed: set spawn, sleep through the night
        spawn_point = (pos[0], pos[1] + 1.5, pos[2])
        if 0.5 < world.time_of_day < 0.97:
            world.time_of_day = 0.0
            flash("You slept until morning. Spawn point set.")
        else:
            flash("Spawn point set. You can only sleep at night.")
        return True
    return False


def place_block():
    item = inventory.item_at(selected)
    inside, outside = target()
    if inside is not None and not held_keys["shift"] and use_block(inside):
        return
    if item in FOOD and not creative:
        if health.eat(FOOD[item]):
            inventory.use_one(selected)
            flash(f"Ate {ITEMS[item]}")
            refresh_items()
            refresh_bars()
        else:
            flash("You're not hungry")
        return
    if item == BUCKET:                             # scoop up water
        water_cell, _ = target(hit_water=True)
        if water_cell and world.get(*water_cell) == WATER:
            edit(water_cell, 0, force=True, flood=False)
            if not creative:
                inventory.use_one(selected)
                if inventory.add(WATER_BUCKET):
                    flash("Inventory full")
            refresh_items()
        return
    if item == WATER_BUCKET:
        if outside and replaceable(outside) and edit(outside, WATER) and not creative:
            inventory.slots[selected] = (BUCKET, 1)
            refresh_items()
        return
    if item not in PLACEABLE or not outside or not replaceable(outside) or overlaps_player(outside, item):
        return
    below = world.get(outside[0], outside[1] - 1, outside[2])
    d = BLOCK_DEFS[item]
    if d["shape"] in ("cross", "torch") and below in NON_SOLID:
        return                                     # plants and torches need ground
    facing = facing_from_yaw(player.rotation_y)
    if item in STAIR_BASES:
        block_id = STAIR_BASES[item][facing]
    elif d["shape"] == "ladder":
        normal = (outside[0] - inside[0], outside[2] - inside[2])
        block_id = 500 + {(0, -1): 0, (-1, 0): 1, (0, 1): 2, (1, 0): 3}.get(normal, facing)
    elif d["shape"] == "door":
        above = (outside[0], outside[1] + 1, outside[2])
        if not replaceable(above) or overlaps_player(outside, 512) or overlaps_player(above, 512):
            return
        axis = 0 if facing in (0, 2) else 1
        if edit(outside, 510 + axis * 4) and edit(above, 510 + axis * 4 + 1) and not creative:
            inventory.use_one(selected)
            refresh_items()
        return
    else:
        block_id = item
    if edit(outside, block_id) and not creative:
        inventory.use_one(selected)
        refresh_items()


def pick_block():
    """Middle click: put the block you look at into your hand."""
    inside, _ = target()
    if inside is None:
        return
    block_id = world.get(*inside)
    item = block_id
    if block_id in DOORS:
        item = 510
    elif 500 <= block_id <= 503:
        item = 500
    for stairs in STAIRS.values():
        if block_id in stairs:
            item = stairs[0]
    if item not in PLACEABLE:
        return
    for i in range(HOTBAR_SIZE):
        if inventory.item_at(i) == item:
            select(i)
            return
    if creative:
        inventory.slots[selected] = new_stack(item, max_stack(item))
    else:
        where = next((i for i, s in enumerate(inventory.slots) if s and s[0] == item), None)
        if where is None:
            return
        inventory.slots[selected], inventory.slots[where] = inventory.slots[where], inventory.slots[selected]
    refresh_items()


def screen_click(right):
    """Clicks inside the inventory screen (inventory slots, creative palette, recipes, chest)."""
    global cursor_stack
    hovered = mouse.hovered_entity
    slot = getattr(hovered, "slot_index", None)
    chest_slot = getattr(hovered, "chest_index", None)
    palette = getattr(hovered, "palette_index", None)
    recipe = getattr(hovered, "recipe_index", None)
    if slot is not None:
        if held_keys["shift"] and not right:
            if chest_pos is not None:              # shift-click moves into the chest
                stack = inventory.slots[slot]
                if stack:
                    inventory.slots[slot] = give_stack(chest_inventory, stack)
            else:
                inventory.quick_move(slot)
        else:
            cursor_stack = inventory.click(slot, cursor_stack, right=right)
    elif chest_slot is not None:
        if held_keys["shift"] and not right:
            stack = chest_inventory.slots[chest_slot]
            if stack:
                chest_inventory.slots[chest_slot] = give_stack(inventory, stack)
        else:
            cursor_stack = chest_inventory.click(chest_slot, cursor_stack, right=right)
    elif palette is not None:
        item = palette_views[palette].item
        if item is not None:
            if cursor_stack:                       # clicking the palette with something held deletes it
                cursor_stack = None
            elif held_keys["shift"] and not right:
                inventory.add(item, max_stack(item))
            else:
                cursor_stack = new_stack(item, 1 if right else max_stack(item))
    elif getattr(hovered, "trash", False):
        if held_keys["shift"]:
            clear_inventory()
        cursor_stack = None
    elif recipe is not None:
        r = RECIPES[recipe]
        times = 16 if held_keys["shift"] else 1
        made = sum(1 for _ in range(times) if inventory.craft(r))
        if not made:
            flash("Missing ingredients" if not inventory.can_craft(r) else "Inventory full")
    refresh_items()


def screen_number_key(n):
    """Hover over an item and press 1-9 to put it in that hotbar slot."""
    hovered = mouse.hovered_entity
    slot = getattr(hovered, "slot_index", None)
    palette = getattr(hovered, "palette_index", None)
    if slot is not None:
        inventory.slots[n], inventory.slots[slot] = inventory.slots[slot], inventory.slots[n]
    elif palette is not None and palette_views[palette].item is not None:
        item = palette_views[palette].item
        inventory.slots[n] = new_stack(item, max_stack(item))
    refresh_items()


def input(key):
    global time_speed, last_space
    if death_root.enabled:
        if key == "r":
            respawn()
        elif key == "escape":
            save()
            application.quit()
        return
    if screen.enabled:
        if search.active:
            if key in ("escape", "enter"):
                search.active = False
            return
        if key in ("e", "escape"):
            close_screen()
        elif key in ("left mouse down", "right mouse down"):
            screen_click(right=key.startswith("right"))
        elif key in [str(i + 1) for i in range(HOTBAR_SIZE)]:
            screen_number_key(int(key) - 1)
        return
    if key == "space":
        if creative and time.time() - last_space < 0.3:   # double-tap: toggle flying
            set_flying(not flying)
            last_space = -1.0
        else:
            last_space = time.time()
            if player.grounded and not creative:
                health.exert(sv.JUMP)
    if key == "left mouse down" and looked_at_animal():
        attack(looked_at_animal())
    elif key == "left mouse down" and creative:
        inside, _ = target()
        if inside:
            break_at(inside)
    elif key == "right mouse down":
        place_block()
    elif key == "middle mouse down":
        pick_block()
    elif key == "e":
        open_screen()
    elif key == "g":
        set_mode(not creative)
    elif key == "n":
        toggle_noclip()
    elif key == "f1":
        hud.enabled = label.enabled = clock.enabled = mode_text.enabled = not hud.enabled
        player.cursor.enabled = hud.enabled
    elif key == "t":
        time_speed = 40 if time_speed != 40 else 1
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
    global daylight, sky_tint
    daylight = 0.16 + 0.84 * day
    tint = lerp(Vec3(0.65, 0.75, 1.0), Vec3(1, 1, 1), day)
    sky_tint = lerp(tint, Vec3(1.0, 0.78, 0.6), dusk * 0.5)
    scene.set_shader_input("daylight", daylight)
    scene.set_shader_input("sky_tint", sky_tint)

    direction = Vec3(math.cos(angle), sun_height, 0.3).normalized()
    sun.world_position = camera.world_position + direction * 300
    moon.world_position = camera.world_position - direction * 300

    hours = (world.time_of_day * 24 + 6) % 24
    clock.text = f"{int(hours):02d}:{int(hours % 1 * 60):02d}"


def update_movement():
    """Flying, swimming, ladders and sprinting."""
    swimming = water_at(player.x, player.y + 0.6, player.z) or water_at(player.x, player.y - 1.1, player.z)
    fast = held_keys["control"] or held_keys["left control"]
    if flying:
        player.speed = FLY_SPEED * (2.5 if fast else 1)
        rise = (held_keys["space"] - held_keys["shift"] - held_keys["left shift"]) * player.speed * time.dt
        if rise:
            player.y += rise
        player.grounded = False
        return False
    on_ladder = BLOCK_DEFS.get(world.get(cell(player.x), cell(player.y + 0.5), cell(player.z)), {}).get("climbable")
    player.speed = SWIM_SPEED if swimming else SPRINT_SPEED if fast else WALK_SPEED
    if on_ladder:
        player.air_time = 0
        if held_keys["w"] or held_keys["space"]:
            player.y += 3 * time.dt
        elif not player.grounded:
            player.y -= 1.5 * time.dt
    if swimming:
        player.air_time = min(player.air_time, 0.012)
        if held_keys["space"]:
            player.y += 4 * time.dt
            player.air_time = 0
    return swimming


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
    update_animals()
    update_mining()
    if screen.enabled:
        cursor_view.icon.position = (mouse.x, mouse.y, -0.2)
        cursor_view.count.position = (mouse.x + 0.028, mouse.y - 0.012, -0.21)
        hovered = mouse.hovered_entity
        index = getattr(hovered, "slot_index", None)
        palette = getattr(hovered, "palette_index", None)
        chest_slot = getattr(hovered, "chest_index", None)
        stack = (inventory.slots[index] if index is not None else
                 chest_inventory.slots[chest_slot] if chest_slot is not None and chest_inventory else
                 (palette_views[palette].item,) if palette is not None and palette_views[palette].item else None)
        tooltip.text = ITEMS[stack[0]] if stack else ""
        return
    swimming = update_movement()
    underwater.enabled = water_at(*camera.world_position)
    # safety net: a lag spike can make a fall skip past the ground; climb back out on top
    feet = (cell(player.x), cell(player.y + 0.3), cell(player.z))
    inside = world.get(*feet)
    if inside and inside not in TRANSPARENT and not noclip:
        player.y = feet[1] + 0.5
        player.air_time = 0
    if player.y < -20:  # fell through the world somehow
        player.position = Vec3(*spawn_point)
    update_health(swimming)


last_position = None


def update_health(swimming):
    """Hunger, healing, drowning and fall damage (survival mode only)."""
    global last_position
    if creative or health.dead:
        last_position = None
        return
    here = Vec3(player.x, player.y, player.z)
    moved = 0.0
    if last_position is not None:
        moved = math.hypot(here.x - last_position.x, here.z - last_position.z)
        if moved > 5:            # teleported / respawned, not walked
            moved = 0.0
            health.fall_top = None
    last_position = here
    on_ladder = BLOCK_DEFS.get(world.get(cell(player.x), cell(player.y + 0.5), cell(player.z)), {}).get("climbable")
    taken = health.tick(time.dt, moved=moved, head_under_water=water_at(*camera.world_position))
    taken += health.track_fall(player.y, on_ground=player.grounded or bool(on_ladder), in_water=swimming)
    hurt(taken)
    refresh_bars()


refresh_bars()
refresh_items()
app.run()
