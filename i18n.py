"""Translations: Arabic names for every block and item, and the UI text of the Godot version.

    python tools/export_godot.py   ->  godot/data/i18n.json

Names are built from patterns where possible (colours, slabs, stairs, tool tiers) so new
variants get an Arabic name automatically; the rest are listed by hand below.
"""
import inventory as inv
from blocks import BLOCK_DEFS, DYES, WOOL, STAINED_GLASS, SLABS, STAIRS

NAMES_AR = {
    "apple": "تفاحة", "basalt": "بازلت", "bed": "تخت", "bedrock": "صخر الأساس",
    "birch leaves": "ورق بتولا", "birch log": "جذع بتولا", "birch planks": "ألواح بتولا",
    "blue flower": "وردة زرقاء", "bookshelf": "رف كتب", "brick": "طوب", "bronze block": "بلوك برونز",
    "bronze ingot": "سبيكة برونز", "brown mushroom": "فطر بني", "bucket": "سطل", "cactus": "صبّار",
    "chest": "صندوق", "clay": "طين", "coal": "فحم", "coal ore": "خام فحم", "cobblestone": "حجر مرصوف",
    "cooked meat": "لحمة مشوية", "copper block": "بلوك نحاس", "copper ingot": "سبيكة نحاس",
    "copper ore": "خام نحاس", "diamond": "ألماس", "diamond block": "بلوك ألماس", "diamond ore": "خام ألماس",
    "dirt": "تراب", "door": "باب", "fern": "سرخس", "furnace": "فرن", "glass": "زجاج", "gold block": "بلوك ذهب",
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
TOOL_KINDS_AR = {"pickaxe": "معول", "axe": "فأس", "shovel": "مجرفة", "sword": "سيف"}
TIERS_AR = {"wooden": "خشبي", "stone": "حجري", "iron": "حديدي", "diamond": "ألماسي"}
GROUPS_AR = {"planks": "ألواح", "rock": "صخر", "wool": "صوف"}
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
    if d.get("door"):
        return NAMES_AR["door"]
    if d.get("shape") == "ladder":
        return NAMES_AR["ladder"]
    raise KeyError(f"no Arabic name for {item} ({name})")


def export():
    assert len(DYES) == len(COLORS_AR)
    return {
        "ui": {k: {"en": en, "ar": ar} for k, (en, ar) in UI.items()},
        "names_ar": {str(i): arabic_name(i) for i in inv.ITEMS},
        "groups_ar": GROUPS_AR,
        "tabs_ar": TABS_AR,
    }
