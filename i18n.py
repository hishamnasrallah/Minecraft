"""Translations: Arabic names for every block and item, and the UI text of the Godot version.

    python tools/export_godot.py   ->  godot/data/i18n.json

Names are built from patterns where possible (colours, slabs, stairs, tool tiers) so new
variants get an Arabic name automatically; the rest are listed by hand below.
"""
import inventory as inv
from blocks import BLOCK_DEFS, DYES, WOOL, STAINED_GLASS, SLABS, STAIRS, WALLS

NAMES_AR = {
    "apple": "تفاحة", "basalt": "بازلت", "bed": "تخت", "bedrock": "صخر الأساس",
    "birch leaves": "ورق بتولا", "birch log": "جذع بتولا", "birch planks": "ألواح بتولا",
    "blue flower": "وردة زرقاء", "bookshelf": "رف كتب", "brick": "طوب", "bronze block": "بلوك برونز",
    "bronze ingot": "سبيكة برونز", "brown mushroom": "فطر بني", "bucket": "سطل", "cactus": "صبّار",
    "chest": "صندوق", "clay": "طين", "coal": "فحم", "coal ore": "خام فحم", "cobblestone": "حجر مرصوف",
    "cooked meat": "لحمة مشوية", "copper block": "بلوك نحاس", "copper ingot": "سبيكة نحاس",
    "copper ore": "خام نحاس", "diamond": "ألماس", "diamond block": "بلوك ألماس", "diamond ore": "خام ألماس",
    "dirt": "تراب", "door": "باب", "farmland": "أرض محروثة", "wheat": "قمح", "carrots": "جزر", "seeds": "بذور",
    "bread": "خبز", "carrot": "جزرة", "fern": "سرخس", "furnace": "فرن", "glass": "زجاج", "gold block": "بلوك ذهب",
    "gold ingot": "سبيكة ذهب", "gold ore": "خام ذهب", "granite": "غرانيت", "grass": "عشب", "gravel": "حصى",
    "ice": "جليد", "iron block": "بلوك حديد", "iron ingot": "سبيكة حديد", "iron ore": "خام حديد",
    "ladder": "سلّم", "lamp": "لمبة", "marble": "رخام", "mossy cobblestone": "حجر مرصوف بطحلب",
    "oak fence": "سياج بلوط", "oak leaves": "ورق بلوط", "oak log": "جذع بلوط", "oak planks": "ألواح بلوط",
    "pine leaves": "ورق صنوبر", "pine log": "جذع صنوبر", "pine planks": "ألواح صنوبر", "plaster": "جبس",
    "raw meat": "لحمة نيّة", "red flower": "وردة حمراء", "red mushroom": "فطر أحمر", "red sand": "رمل أحمر",
    "reeds": "قصب", "sand": "رمل", "sandstone": "حجر رملي", "sandstone bricks": "طوب رملي", "snow": "ثلج",
    "stick": "عصا", "stone": "حجر", "stone bricks": "طوب حجري", "tall grass": "عشب طويل", "tiles": "بلاط",
    "tin ingot": "سبيكة قصدير", "tin ore": "خام قصدير", "torch": "شعلة", "water": "ماء",
    "water bucket": "سطل ماء", "white flower": "وردة بيضاء", "workbench": "طاولة صنع",
    "yellow flower": "وردة صفراء",
}
COLORS_AR = ["أبيض", "رمادي فاتح", "رمادي", "أسود", "بني", "أحمر", "برتقالي", "أصفر", "ليموني", "أخضر",
             "سماوي", "أزرق فاتح", "أزرق", "بنفسجي", "أرجواني", "زهري"]
# ---------------------------------------------------------------- expanded catalogue
_WOODS_AR = {"oak": "بلوط", "birch": "بتولا", "pine": "صنوبر", "maple": "قيقب", "cherry": "كرز",
             "ashwood": "دردار", "ebony": "أبنوس"}
for _sp, _ar in _WOODS_AR.items():
    NAMES_AR.update({f"{_sp} log": "جذع " + _ar, f"{_sp} planks": "ألواح " + _ar, f"{_sp} leaves": "ورق " + _ar,
                     f"{_sp} fence": "سياج " + _ar, f"{_sp} sapling": "شتلة " + _ar})
NAMES_AR.update({
    "slate": "أردواز", "cobbled slate": "أردواز مرصوف", "limestone": "حجر كلسي",
    "polished stone": "حجر مصقول", "polished granite": "غرانيت مصقول", "polished basalt": "بازلت مصقول",
    "polished marble": "رخام مصقول", "smooth sandstone": "حجر رملي ناعم", "polished slate": "أردواز مصقول",
    "polished limestone": "حجر كلسي مصقول", "granite bricks": "طوب غرانيت", "basalt bricks": "طوب بازلت",
    "marble bricks": "طوب رخام", "slate bricks": "طوب أردواز", "limestone bricks": "طوب كلسي",
    "cracked stone bricks": "طوب حجري مشقّق", "mossy stone bricks": "طوب حجري بطحلب",
    "chiseled stone": "حجر منقوش", "chiseled sandstone": "حجر رملي منقوش", "chiseled marble": "رخام منقوش",
    "chiseled limestone": "حجر كلسي منقوش",
    "ruby": "ياقوت أحمر", "sapphire": "ياقوت أزرق", "amethyst shard": "شظية جمشت", "quartz": "كوارتز",
    "ruby ore": "خام ياقوت أحمر", "sapphire ore": "خام ياقوت أزرق", "amethyst ore": "خام جمشت",
    "quartz ore": "خام كوارتز", "ruby block": "بلوك ياقوت أحمر", "sapphire block": "بلوك ياقوت أزرق",
    "amethyst block": "بلوك جمشت", "quartz block": "بلوك كوارتز", "tin block": "بلوك قصدير",
    "coal block": "بلوك فحم", "glow crystal": "بلورة مضيئة",
    "hay bale": "رزمة قش", "pumpkin": "يقطين", "melon": "بطيخ", "mud": "وحل", "mud bricks": "طوب طيني",
    "moss block": "بلوك طحلب", "sponge": "إسفنج", "packed ice": "جليد مضغوط", "terracotta": "فخار",
    "lavender": "خزامى", "marigold": "قطيفة", "pink tulip": "توليب زهري", "orchid": "سحلبية", "daisy": "أقحوان",
    "bluebell": "جريس", "dark iris": "سوسن داكن", "sunflower": "دوّار الشمس",
    "leafy bush": "شجيرة", "berry bush": "شجيرة توت", "dry bush": "شجيرة يابسة",
})
# colour families: "<family word> <colour>"
DYED_AR = {"concrete": "خرسانة", "terracotta": "فخار", "glazed_tiles": "بلاط مزجّج", "carpet": "سجادة",
           "lamps": "لمبة"}
DYED_FEMININE = {"concrete", "carpet", "lamps"}          # these words take the feminine colour adjective
COLORS_F_AR = ["بيضاء", "رمادية فاتحة", "رمادية", "سوداء", "بنية", "حمراء", "برتقالية", "صفراء", "ليمونية",
               "خضراء", "سماوية", "زرقاء فاتحة", "زرقاء", "بنفسجية", "أرجوانية", "زهرية"]
# variant families shown collapsed in the creative menu: family -> (English, Arabic)
FAMILIES = {
    "concrete": ("Concrete", "خرسانة"), "terracotta": ("Terracotta", "فخار"),
    "glazed_tiles": ("Glazed tiles", "بلاط مزجّج"), "carpet": ("Carpets", "سجاد"), "wool": ("Wool", "صوف"),
    "stained_glass": ("Stained glass", "زجاج ملوّن"), "logs": ("Logs", "جذوع"), "planks": ("Planks", "ألواح"),
    "leaves": ("Leaves", "أوراق"), "fences": ("Fences", "أسيجة"), "saplings": ("Saplings", "شتلات"),
    "rocks": ("Rocks", "صخور"), "cobblestone": ("Cobblestone", "حجر مرصوف"),
    "polished_stone": ("Polished stone", "حجر مصقول"), "stone_bricks": ("Bricks", "طوب"),
    "chiseled_stone": ("Chiseled stone", "حجر منقوش"), "sand": ("Sand", "رمل"), "ores": ("Ores", "خامات"),
    "storage_blocks": ("Storage blocks", "بلوكات معادن وجواهر"), "farm_blocks": ("Farm blocks", "محاصيل"),
    "lamps": ("Lamps", "لمبات"), "flowers": ("Flowers", "ورود"), "grasses": ("Grass and bushes", "عشب وشجيرات"),
    "mushrooms": ("Mushrooms", "فطر"), "slabs": ("Slabs", "بلاطات"), "stairs": ("Stairs", "أدراج"),
    "walls": ("Walls", "أسوار"), "ingots": ("Ingots", "سبائك"), "gems": ("Gems", "جواهر"),
    "pickaxes": ("Pickaxes", "معاول"), "axes": ("Axes", "فؤوس"), "shovels": ("Shovels", "مجارف"),
    "swords": ("Swords", "سيوف"), "hoes": ("Hoes", "معازق"), "neon_pink": ("Pink neon letters", "حروف نيون وردية"),
    "neon_blue": ("Blue neon letters", "حروف نيون زرقاء"), "doors": ("Doors", "أبواب"),
}
FAMILIES_EN = {f: en for f, (en, _ar) in FAMILIES.items()}
FAMILIES_AR = {f: ar for f, (_en, ar) in FAMILIES.items()}
_DYE_INDEX = {tuple(rgb): i for i, (_name, rgb) in enumerate(DYES)}

TOOL_KINDS_AR = {"pickaxe": "معول", "axe": "فأس", "shovel": "مجرفة", "sword": "سيف", "hoe": "معزقة"}
TIERS_AR = {"wooden": "خشبي", "stone": "حجري", "iron": "حديدي", "diamond": "ألماسي"}
GROUPS_AR = {"planks": "ألواح", "rock": "صخر", "wool": "صوف", "logs": "جذوع", "flowers": "ورود", "fuel": "وقود"}
TABS_AR = {"all": "الكل", "natural": "طبيعي", "building": "بناء", "colored": "ملوّن", "plants": "نباتات",
           "functional": "مفيد", "tools": "أدوات", "food": "أكل", "materials": "مواد"}

# UI text: key -> (English, Arabic). %s / %d are filled in by the game.
UI = {
    # touch buttons
    "btn_jump": ("Jump", "قفز"), "btn_break": ("Break", "كسر"), "btn_place": ("Place", "وضع"),
    "btn_items": ("Items", "أغراض"), "btn_fly": ("Fly", "طيران"), "btn_build": ("Build", "بناء"),
    "btn_up": ("Up", "فوق"), "btn_down": ("Down", "تحت"), "btn_save": ("Save", "حفظ"),
    "btn_settings": ("Settings", "إعدادات"),
    # inventory screen
    "close": ("Close", "إغلاق"), "half": ("Half", "نص"), "quick": ("Quick", "سريع"),
    "crafting": ("Crafting", "الصنع"), "creative": ("Creative", "الإبداع"), "chest": ("Chest", "صندوق"),
    "to_survival": ("Survival mode", "وضع النجاة"), "to_creative": ("Creative mode", "وضع الإبداع"),
    "search": ("Search", "بحث"), "trash": ("Trash", "سلة"), "clear_inventory": ("Clear", "تفريغ"),
    "sunrise": ("Sunrise", "شروق"), "noon": ("Noon", "ظهر"), "sunset": ("Sunset", "غروب"),
    "midnight": ("Midnight", "ليل"), "freeze": ("Freeze time", "إيقاف الوقت"), "hotbars": ("Hotbars:", "الشرائط:"),
    "save_hotbar": ("Save", "حفظ"), "storage_hint": ("storage on top, hotbar below", "المخزن فوق والشريط تحت"),
    "any": ("any %s", "أي %s"),
    # messages
    "saved": ("Saved", "انحفظت"), "welcome_touch": ("Joystick on the left, drag on the right to look",
                                                     "العصا على اليسار، واسحب على اليمين لتتطلع"),
    "welcome_desktop": ("Click to play. WASD + mouse, E for items", "اكبس لتلعب. WASD والماوس، و E للأغراض"),
    "inventory_full": ("Inventory full", "الأغراض مليانة"), "not_hungry": ("You're not hungry", "إنت شبعان"),
    "ate": ("Ate %s", "أكلت %s"), "needs_tool": ("%s needs a better tool to drop anything", "%s بده أداة أقوى عشان يعطيك شي"),
    "tool_broke": ("Your %s broke!", "انكسر %s!"), "got_meat": ("+%d raw meat", "+%d لحمة نيّة"),
    "mode_creative": ("Creative mode", "وضع الإبداع"), "mode_survival": ("Survival mode", "وضع النجاة"),
    "fly_creative_only": ("Flying is a creative-mode thing", "الطيران بوضع الإبداع بس"),
    "time_frozen": ("Time frozen", "الوقت واقف"), "time_running": ("Time running", "الوقت ماشي"),
    "time_fast": ("Time x%d", "الوقت ×%d"),
    "missing_ingredients": ("Missing ingredients", "ناقصك مكوّنات"),
    "dropped": ("Inventory full - dropped %s", "الأغراض مليانة - وقع %s"),
    "hotbar_loaded": ("Loaded hotbar %d", "رجع الشريط %d"), "hotbar_saved": ("Saved hotbar %d", "انحفظ الشريط %d"),
    "hotbar_empty": ("Hotbar %d is empty - tap Save, then %d", "الشريط %d فاضي - اكبس حفظ وبعدين %d"),
    "slept": ("You slept until morning. Spawn point set.", "نمت للصبح. انحفظ مكان الإحياء."),
    "spawn_set": ("Spawn point set. You can only sleep at night.", "انحفظ مكان الإحياء. النوم بالليل بس."),
    "added": ("+ %s", "+ %s"),
    # building tools
    "corner1": ("Corner 1", "زاوية 1"), "corner2": ("Corner 2", "زاوية 2"), "fill": ("Fill", "تعبئة"),
    "hollow": ("Hollow", "مفرّغ"), "replace": ("Replace", "استبدال"), "clear": ("Clear", "مسح"),
    "copy": ("Copy", "نسخ"), "paste": ("Paste", "لصق"), "rotate": ("Rotate", "تدوير"), "mirror": ("Mirror", "عكس"),
    "undo": ("Undo", "تراجع"), "deselect": ("Deselect", "إلغاء التحديد"), "library": ("Library", "المكتبة"),
    "corner_at": ("Corner %s at %s", "الزاوية %s عند %s"), "hold_block": ("Hold a block to build with", "امسك بلوك لتبني فيه"),
    "hold_replace": ("Hold a block and look at the block type to replace", "امسك بلوك وتطلّع على النوع اللي بدك تستبدله"),
    "selection_cleared": ("Selection cleared", "انلغى التحديد"), "paste_aim": ("Aim, then tap Paste again", "أشّر، وبعدين اكبس لصق كمان مرة"),
    "loaded_building": ("Loaded %s - tap Paste", "انحمّل %s - اكبس لصق"),
    "loaded_building_desktop": ("Loaded %s - hold V to place it", "انحمّل %s - اضغط V مطوّل لتحطه"),
    "select_first": ("Select two corners first", "حدد زاويتين أول"),
    "too_big": ("Selection too big (%d blocks, max %d)", "التحديد كبير كتير (%d بلوك، الحد %d)"),
    "changed": ("Changed %d blocks", "تغيّر %d بلوك"), "copied": ("Copied %dx%dx%d (%d blocks)", "انتسخ %dx%dx%d (%d بلوك)"),
    "nothing_copied": ("Nothing copied yet", "ما في شي منسوخ"), "pasted": ("Pasted %d blocks", "انلصق %d بلوك"),
    "rotated": ("Rotated the copy 90 degrees", "النسخة لفّت 90 درجة"), "mirrored": ("Mirrored the copy", "النسخة انعكست"),
    "undid": ("Undid %d block changes", "رجعت %d تغيير"), "nothing_undo": ("Nothing to undo", "ما في شي ترجع عنه"),
    "selection": ("selection %dx%dx%d (%d)", "تحديد %dx%dx%d (%d)"), "copy_size": ("copy %dx%dx%d", "نسخة %dx%dx%d"),
    "buildings": ("Buildings", "البنايات"), "building_name": ("name for the current copy", "اسم النسخة الحالية"),
    "save_copy": ("Save copy", "احفظ النسخة"), "delete": ("Delete", "امسح"), "example": ("example", "مثال"),
    "cant_read": ("Could not read that file", "ما قدرت أقرا الملف"), "name_it": ("Give the building a name", "اعطِ البناية اسم"),
    "saved_file": ("Saved %s", "انحفظ %s"),
    # death
    "you_died": ("You died", "متت"), "respawn": ("Respawn", "ارجع"),
    "cause_starved": ("You starved.", "متت من الجوع."), "cause_drowned": ("You drowned.", "غرقت."),
    "cause_fell from a high place": ("You fell from a high place.", "وقعت من مكان عالي."),
    # settings
    "settings": ("Settings", "الإعدادات"), "language": ("Language", "اللغة"),
    "sensitivity": ("Look sensitivity", "حساسية النظر"), "view_distance": ("View distance", "مسافة الرؤية"),
    "show_fps": ("Show FPS", "إظهار FPS"), "done": ("Done", "تم"),
    "crashed_note": ("The game closed unexpectedly last time (at: %s). Running in safe mode - you can turn it off in Settings.",
                     "اللعبة سكّرت فجأة المرة الماضية (عند: %s). شغالة بالوضع الآمن - بتقدر تطفيه من الإعدادات."),
    "safe_mode": ("Safe mode (slower, more stable)", "الوضع الآمن (أبطأ وأثبت)"),
    # main menu and worlds
    "title": ("BlockWorld", "عالم البلوكات"), "worlds": ("Your worlds", "عوالمك"),
    "no_worlds": ("No worlds yet - create one", "ما في عوالم لسا - أنشئ واحد"),
    "new_world": ("New world", "عالم جديد"), "world_name": ("World name", "اسم العالم"),
    "seed_hint": ("Seed number (optional)", "رقم العالم (اختياري)"), "survival": ("Survival", "نجاة"),
    "creative_mode": ("Creative", "إبداع"), "create": ("Create and play", "أنشئ والعب"), "play": ("Play", "العب"),
    "delete_confirm": ("Delete \"%s\"? This can't be undone.", "تمسح \"%s\"؟ ما في رجعة."),
    "cancel": ("Cancel", "إلغاء"), "my_world": ("My world", "عالمي"), "my_world_n": ("My world %d", "عالمي %d"),
    "exit_to_menu": ("Save and go to the menu", "احفظ وارجع للقائمة"), "never_played": ("new", "جديد"),
    "days_ago": ("%d days ago", "من %d يوم"), "today": ("today", "اليوم"), "yesterday": ("yesterday", "مبارح"),
    "sound": ("Sound", "الصوت"),
    "monsters": ("Night monsters (glooms)", "وحوش الليل (الظلال)"),
    "cause_gloom": ("A gloom got you.", "ظلّ قتلك."),
    # touch actions, log, items screen
    "show_map": ("Mini map", "خريطة صغيرة"),
    "weather_clear": ("Clear sky", "صحو"), "weather_cloudy": ("Cloudy", "غيوم"), "weather_rain": ("Rain", "مطر"), "vibrate": ("Vibrate", "اهتزاز"),
    "hold_to_break": ("Aim the + at a block and hold your finger anywhere to break it", "وجّه علامة + على البلوك واضغط مطوّل بأي مكان لتكسره"),
    "touch_buttons": ("Separate break / place buttons", "أزرار منفصلة للكسر والوضع"),
    "show_log": ("Game log (for bug reports)", "سجل اللعبة (لإرسال الأخطاء)"),
    "copy_log": ("Copy", "نسخ"), "log_copied": ("Copied!", "انْسخ!"),
    "craftable_only": ("Can make", "اللي بقدر أصنعه"), "sort": ("Sort", "ترتيب"),
    "tab_favorites": ("Favourites", "المفضلة"), "tab_recent": ("Recent", "الأخيرة"),
    "quick_move": ("Move", "نقل سريع"), "split": ("Half", "نص"),
    "pick_first": ("Tap a slot first", "اختار خانة أول"), "cant_split": ("Only one - can't split", "وحدة بس - ما بتنقسم"),
    "furnace_title": ("Furnace", "فرن"),
    "items_hint_title": ("Your items", "أغراضك"),
    "items_hint": ("Tap a slot, then another to move it - or drag it. Double tap = quick move.",
                   "اكبس خانة وبعدين خانة تانية لتنقلها - أو اسحبها. كبستين = نقل سريع."),
    "items_hint_creative": ("Tap a block to put it in your hotbar. + opens colours and kinds. Hold to add to favourites.",
                            "اكبس بلوك ليصير بالشريط. علامة + بتفتح الألوان والأنواع. اضغط مطوّل ليصير بالمفضلة."),
    "info_tool": ("Tool, %d uses", "أداة، بتتحمل %d استعمال"), "info_food": ("Food, +%d hunger", "أكل، بيشبّع %d"),
    "info_light": ("Gives light", "بيضوّي"), "info_container": ("Stores items", "بيخزّن أغراض"),
    "info_mine_with": ("Faster with a %s", "أسرع بـ %s"), "info_variants": ("%d kinds", "%d أنواع"),
    "info_recipe": ("Made from:", "بينصنع من:"),
    "tool_pickaxe": ("pickaxe", "معول"), "tool_axe": ("axe", "فأس"), "tool_shovel": ("shovel", "مجرفة"),
    "tool_sword": ("sword", "سيف"), "tool_hoe": ("hoe", "معزقة"),
    "hoe_hint": ("Use a hoe on grass or dirt, then plant seeds", "استعمل المعزقة على عشب أو تراب، وبعدين ازرع بذور"),
    "needs_farmland": ("Plant it on farmland (use a hoe first)", "بينزرع بأرض محروثة (استعمل المعزقة أول)"),
    "tree_grew": ("A tree grew!", "كبرت شجرة!"),
    "no_favorites": ("Hold any block to add it here", "اضغط مطوّل على أي بلوك ليصير هون"),
    "nothing_found": ("Nothing here", "ما في شي هون"),
    "favorited": ("★ %s", "★ %s"), "unfavorited": ("Removed %s", "انشال %s"),
    "craft_n": ("Make %d (= %d)", "اصنع %d (= %d)"), "craft_all": ("Make all (%d)", "اصنع الكل (%d)"),
    "crafted": ("Made %d %s", "انصنع %d %s"),
    # first-time tutorial (_t = touch screen, _d = desktop)
    "tut_skip": ("Skip", "تخطي"), "tut_again": ("Show the tutorial again", "إعادة التعليم"),
    "tut_look_t": ("Drag on the right side of the screen to look around", "اسحب على يمين الشاشة لتتطلع حواليك"),
    "tut_look_d": ("Move the mouse to look around (click the screen first)", "حرّك الماوس لتتطلع حواليك (اكبس على الشاشة أول)"),
    "tut_walk_t": ("Move the joystick on the left to walk", "حرّك العصا على يسار الشاشة لتمشي"),
    "tut_walk_d": ("Walk with W A S D", "امشي بـ W A S D"),
    "tut_jump_t": ("Tap the jump button", "اكبس زر القفز"), "tut_jump_d": ("Press Space to jump", "اكبس Space لتنط"),
    "tut_fly_t": ("Tap the wing button to fly, then Up and Down", "اكبس زر الجناح لتطير، وبعدين فوق وتحت"),
    "tut_fly_d": ("Press Space twice quickly to fly", "اكبس Space مرتين بسرعة لتطير"),
    "tut_break_t": ("Aim the + at a block, then hold your finger on the screen to break it", "وجّه علامة + على بلوك، وبعدين اضغط مطوّل على الشاشة لتكسره"),
    "tut_break_d": ("Aim at a block and hold the left mouse button", "أشّر على بلوك واضغط مطوّل كليك يسار"),
    "tut_place_t": ("Pick a block on the hotbar, aim the + and tap the screen to place it", "اختار بلوك من الشريط، وجّه علامة + واكبس على الشاشة لتحطه"),
    "tut_place_d": ("Pick a block on the hotbar and right click to place it", "اختار بلوك من الشريط واكبس كليك يمين لتحطه"),
    "tut_items_t": ("Open your items with the bag button", "افتح الأغراض من زر الحقيبة"),
    "tut_items_d": ("Open your items with E", "افتح الأغراض بـ E"),
    "tut_done_survival": ("Well done! Glooms come out at night - place torches and build a shelter.",
                          "ممتاز! بالليل بيطلع الظلّ - حط شعلات وابنِ بيت لتحمي حالك."),
    "tut_done_creative": ("Well done! Try the hammer button for big building tools.",
                          "ممتاز! جرّب زر الشاكوش لأدوات البناء الكبيرة."),
    "creative_label": ("creative", "إبداع"), "flying_label": ("flying", "طيران"), "noclip_label": ("noclip", "عبر الجدران"),
}


def arabic_name(item):
    """Arabic name of a block or item id."""
    name = inv.ITEMS[item]
    if name in NAMES_AR:
        return NAMES_AR[name]
    if item in WOOL:
        return "صوف " + COLORS_AR[WOOL.index(item)]
    if item in STAINED_GLASS:
        return "زجاج " + COLORS_AR[STAINED_GLASS.index(item)]
    d = BLOCK_DEFS.get(item, {})
    if d.get("family") in DYED_AR and tuple(d.get("dye", ())) in _DYE_INDEX:
        colors = COLORS_F_AR if d["family"] in DYED_FEMININE else COLORS_AR
        return DYED_AR[d["family"]] + " " + colors[_DYE_INDEX[tuple(d["dye"])]]
    for material, wall in WALLS.items():
        if item == wall:
            return "سور " + arabic_name(material)
    for material, slab in SLABS.items():
        if item == slab:
            return "بلاطة " + arabic_name(material)
    for material, stairs in STAIRS.items():
        if item in stairs:
            return "درج " + arabic_name(material)
    if item in inv.TOOLS:
        kind = inv.TOOLS[item][0]
        tier = inv.TOOLS[item][3].split()[0]
        return TOOL_KINDS_AR[kind] + " " + TIERS_AR[tier]
    d = BLOCK_DEFS.get(item, {})
    if d.get("letter"):
        return "حرف نيون " + d["letter"] + (" وردي" if d["neon"][0] > 200 else " أزرق")
    if d.get("door"):
        species = name.replace(" door", "")
        return NAMES_AR["door"] + (" " + _WOODS_AR[species] if species in _WOODS_AR else "")
    if d.get("shape") == "ladder":
        return NAMES_AR["ladder"]
    raise KeyError(f"no Arabic name for {item} ({name})")


def export():
    assert len(DYES) == len(COLORS_AR)
    return {
        "ui": {k: {"en": en, "ar": ar} for k, (en, ar) in UI.items()},
        "names_ar": {str(i): arabic_name(i) for i in inv.ITEMS},
        "groups_ar": GROUPS_AR,
        "families_ar": FAMILIES_AR,
        "tabs_ar": TABS_AR,
    }
