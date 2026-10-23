from pathlib import Path
import re


PROJECT = Path(__file__).resolve().parents[1] / "ios/Runner.xcodeproj/project.pbxproj"
MINIMUM_IOS = "14.0"


def prepare_ios() -> None:
    if not PROJECT.is_file():
        raise FileNotFoundError(f"iOS Xcode project not found: {PROJECT}")

    source = PROJECT.read_text()
    updated, count = re.subn(
        r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*[0-9.]+;",
        f"IPHONEOS_DEPLOYMENT_TARGET = {MINIMUM_IOS};",
        source,
    )
    if count == 0:
        raise ValueError("Could not find an iOS deployment target in the Xcode project")
    PROJECT.write_text(updated)
    if f"IPHONEOS_DEPLOYMENT_TARGET = {MINIMUM_IOS};" not in PROJECT.read_text():
        raise RuntimeError("Failed to set the iOS deployment target")


if __name__ == "__main__":
    prepare_ios()
