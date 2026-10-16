"""Check the final read-only DMG without rewriting any Finder preferences."""
import sys
from pathlib import Path
from ds_store import DSStore
from mac_alias import Alias

mount = Path(sys.argv[1])
with DSStore.open(str(mount / ".DS_Store"), "r") as store:
    options = store["."]["icvp"]
    assert options["backgroundType"] == 2
    assert store["."]["icvl"] == (b"type", b"icnv")
    assert options["scrollPositionX"] == options["scrollPositionY"] == 0
    assert store["ClampEverything.app"]["Iloc"] == (110, 240)
    assert store["Applications"]["Iloc"] == (530, 240)
    assert not store["."]["bwsp"]["ShowStatusBar"]
    alias = options["backgroundImageAlias"]
    actual = Alias.from_bytes(alias)
    expected = Alias.from_bytes(Alias.for_file(str(mount / ".background" / "background.png")).to_bytes())
    assert actual.volume.name == expected.volume.name
    assert actual.target.cnid == expected.target.cnid
    Path(sys.argv[2]).write_bytes(alias)
assert (mount / "Applications").is_symlink()
assert (mount / ".VolumeIcon.icns").stat().st_size > 0
print("Final DMG Finder layout, icon, image identity and background metadata verified")
