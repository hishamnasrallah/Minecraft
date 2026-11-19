import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import i18n  # noqa: E402
import ui_icons  # noqa: E402
import inventory as inv  # noqa: E402


def test_every_item_has_an_arabic_name():
    data = i18n.export()
    assert set(data["names_ar"]) == {str(i) for i in inv.ITEMS}
    for name in data["names_ar"].values():
        assert name and any("؀" <= ch <= "ۿ" for ch in name)


def test_ui_strings_have_both_languages_and_matching_placeholders():
    for key, (en, ar) in i18n.UI.items():
        assert en and ar, key
        for p in ("%s", "%d"):
            assert en.count(p) == ar.count(p), key


def test_every_tab_and_group_is_translated():
    assert set(inv.TABS) <= set(i18n.TABS_AR)
    assert set(inv.GROUPS) <= set(i18n.GROUPS_AR)


def test_icons_render():
    icons = ui_icons.render_all()
    for name, img in icons.items():
        assert img.size == (ui_icons.OUT, ui_icons.OUT)
        assert img.getbbox() is not None, f"{name} is empty"
