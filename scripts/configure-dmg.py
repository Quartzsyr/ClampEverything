"""Write Finder's installation layout without opening or automating Finder."""
import sys
import struct
from pathlib import Path
from ds_store import DSStore
from mac_alias import Alias

mount = Path(sys.argv[1])
background = mount / ".background" / "background.png"
alias = Alias.for_file(str(background)).to_bytes()
with DSStore.open(str(mount / ".DS_Store"), "w+") as store:
    store["."]["vSrn"] = ("long", 1)
    store["."]["icvl"] = ("type", b"icnv")
    store["."]["ICVO"] = ("bool", True)
    store["."]["BKGD"] = ("blob", b"PctB" + struct.pack(">I", len(alias)) + b"\0" * 4)
    store["."]["pict"] = ("blob", alias)
    store["."]["bwsp"] = {
        "ShowStatusBar": False, "ShowTabView": False, "ShowToolbar": False,
        "ShowPathbar": False, "ShowSidebar": False,
        "WindowBounds": "{{160, 120}, {640, 480}}", "ContainerShowSidebar": False,
    }
    store["."]["icvp"] = {
        "viewOptionsVersion": 1, "backgroundType": 2,
        "backgroundColorRed": 0.96, "backgroundColorGreen": 0.95, "backgroundColorBlue": 0.91,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0,
        "backgroundImageAlias": alias,
        "iconSize": 88.0, "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
        "arrangeBy": "none", "textSize": 12.0, "labelOnBottom": True,
        "showIconPreview": True, "showItemInfo": False,
    }
    store["."]["vstl"] = ("type", b"icnv")
    store["ClampEverything.app"]["Iloc"] = (110, 240)
    store["Applications"]["Iloc"] = (530, 240)
    store["安装说明.txt"]["Iloc"] = (320, 395)
# Decode what was written, including the background alias and native icon positions.
with DSStore.open(str(mount / ".DS_Store"), "r") as store:
    assert store["ClampEverything.app"]["Iloc"] == (110, 240)
    assert store["Applications"]["Iloc"] == (530, 240)
    assert store["."]["icvp"]["backgroundType"] == 2
    actual = Alias.from_bytes(store["."]["icvp"]["backgroundImageAlias"])
    expected = Alias.from_bytes(Alias.for_file(str(background)).to_bytes())
    assert actual.volume.name == expected.volume.name
    assert actual.target.cnid == expected.target.cnid
    assert store["."]["icvl"] == (b"type", b"icnv")
    if len(sys.argv) > 2:
        Path(sys.argv[2]).write_bytes(store["."]["icvp"]["backgroundImageAlias"])
print("Finder layout and background alias verified")
