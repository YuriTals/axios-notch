# dmgbuild settings for the installer window. Run through scripts/make-dmg.sh, which passes
# `app` (the .app to ship) and `icon` (the volume icon) with `-D`.
import os

app = defines["app"]                                   # noqa: F821  (provided by dmgbuild)
root = os.path.dirname(os.path.abspath(defines["settings_dir"] if "settings_dir" in defines else "."))  # noqa: F821

format = "UDZO"                                        # compressed, read-only
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
badge_icon = defines.get("icon")                       # noqa: F821
background = os.path.join(defines["packaging"], "dmg-background.png")  # noqa: F821

window_rect = ((200, 120), (660, 400))
icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (165, 190),
    "Applications": (495, 190),
}
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
arrange_by = None
