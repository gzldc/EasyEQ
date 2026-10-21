# dmgbuild settings for the EasyEQ drag-to-install window (see scripts/package.sh).
# Run via:  dmgbuild -s scripts/dmg-settings.py -D app=dist/EasyEQ.app EasyEQ out.dmg
# Window content is 640x420 with 128 px icons; the artwork in Resources/DMG/background.tiff
# (scripts/make-dmg-background.swift) assumes the icon centres below.

import os

app = defines.get("app", "dist/EasyEQ.app")  # noqa: F821 (`defines` is injected by dmgbuild)
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppBundle/AppIcon.icns"  # volume icon
background = "Resources/DMG/background.tiff"

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

default_view = "icon-view"
# 420 pt of content plus the 28 pt title bar, so the 640x420 background fits the content area exactly.
window_rect = ((200, 120), (640, 448))
icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {app_name: (160, 200), "Applications": (480, 200)}
