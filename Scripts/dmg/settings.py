import os

app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
background = defines["background"]
window_rect = ((200, 200), (640, 400))
icon_size = 112
icon_locations = {os.path.basename(app): (160, 192), "Applications": (480, 192)}
show_status_bar = show_tab_view = show_toolbar = show_pathbar = show_sidebar = False
format = "UDZO"
