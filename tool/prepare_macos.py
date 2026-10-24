from pathlib import Path
import plistlib


ENTITLEMENT = "com.apple.security.network.client"
PRINT_ENTITLEMENT = "com.apple.security.print"
ENTITLEMENT_FILES = (
    Path("macos/Runner/DebugProfile.entitlements"),
    Path("macos/Runner/Release.entitlements"),
)
ROOT = Path(__file__).resolve().parents[1]


def allow_outbound_network(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"macOS entitlements file not found: {path}")

    with path.open("rb") as source:
        entitlements = plistlib.load(source)
    if not isinstance(entitlements, dict):
        raise ValueError(f"Expected a plist dictionary in {path}")

    entitlements[ENTITLEMENT] = True
    entitlements[PRINT_ENTITLEMENT] = True
    with path.open("wb") as output:
        plistlib.dump(entitlements, output, sort_keys=True)


def prepare_macos(root: Path = ROOT) -> None:
    paths = [root / relative_path for relative_path in ENTITLEMENT_FILES]
    for path in paths:
        allow_outbound_network(path)

    for path in paths:
        with path.open("rb") as source:
            entitlements = plistlib.load(source)
        if entitlements.get(ENTITLEMENT) is not True:
            raise RuntimeError(f"macOS network entitlement was not enabled in {path}")
        if entitlements.get(PRINT_ENTITLEMENT) is not True:
            raise RuntimeError(f"macOS print entitlement was not enabled in {path}")


if __name__ == "__main__":
    prepare_macos()
