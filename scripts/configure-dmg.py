"""Write Finder's installation layout without opening or automating Finder."""
import sys
from pathlib import Path
from ds_store import DSStore
from mac_alias import Alias

mount = Path(sys.argv[1])
background = mount / ".background" / "background.png"
with DSStore.open(str(mount / ".DS_Store"), "w+") as store:
    store["."]["bwsp"] = {
        "ShowStatusBar": False, "ShowTabView": False, "ShowToolbar": False,
        "ShowPathbar": False, "ShowSidebar": False,
        "WindowBounds": "{{160, 120}, {640, 480}}", "ContainerShowSidebar": False,
    }
    store["."]["icvp"] = {
        "viewOptionsVersion": 1, "backgroundType": 2,
        "backgroundImageAlias": Alias.for_file(str(background)).to_bytes(),
        "iconSize": 88.0, "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
        "arrangeBy": "none", "textSize": 12.0, "labelOnBottom": True,
        "showIconPreview": True, "showItemInfo": False,
    }
    store["."]["vstl"] = ("type", b"icnv")
    store["ClampEverything.app"]["Iloc"] = (160, 215)
    store["Applications"]["Iloc"] = (480, 215)
    store["安装说明.txt"]["Iloc"] = (320, 380)
# Decode what was written, including the background alias and native icon positions.
with DSStore.open(str(mount / ".DS_Store"), "r") as store:
    assert store["ClampEverything.app"]["Iloc"] == (160, 215)
    assert store["Applications"]["Iloc"] == (480, 215)
    assert store["."]["icvp"]["backgroundType"] == 2
    Alias.from_bytes(store["."]["icvp"]["backgroundImageAlias"])
print("Finder layout and background alias verified")
