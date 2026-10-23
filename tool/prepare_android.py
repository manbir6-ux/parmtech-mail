from pathlib import Path
import re


INTERNET_PERMISSION = (
    '<uses-permission android:name="android.permission.INTERNET" />'
)
DESUGARING_DEPENDENCY = (
    'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
)
ROOT = Path(__file__).resolve().parents[1]


def ensure_internet_permission(manifest: str) -> str:
    permission_pattern = r"<uses-permission\b[^>]*android:name=[\"']android\.permission\.INTERNET[\"']"
    if re.search(permission_pattern, manifest):
        return manifest

    root = re.search(r"<manifest\b[^>]*>", manifest)
    if root is None:
        raise ValueError("Could not find the Android manifest root element")
    return (
        manifest[: root.end()]
        + "\n    "
        + INTERNET_PERMISSION
        + manifest[root.end() :]
    )


def enable_core_library_desugaring(gradle: str) -> str:
    options = re.search(r"(?m)^([ \t]*)compileOptions[ \t]*\{[ \t]*$", gradle)
    if options is None:
        raise ValueError("Could not find Android compileOptions block")
    if "isCoreLibraryDesugaringEnabled = true" not in gradle:
        gradle = (
            gradle[: options.end()]
            + f"\n{options.group(1)}    isCoreLibraryDesugaringEnabled = true"
            + gradle[options.end() :]
        )

    if DESUGARING_DEPENDENCY not in gradle:
        dependencies = re.search(
            r"(?m)^([ \t]*)dependencies[ \t]*\{[ \t]*$", gradle
        )
        if dependencies is None:
            gradle = (
                gradle.rstrip()
                + "\n\ndependencies {\n    "
                + DESUGARING_DEPENDENCY
                + "\n}\n"
            )
        else:
            gradle = (
                gradle[: dependencies.end()]
                + f"\n{dependencies.group(1)}    {DESUGARING_DEPENDENCY}"
                + gradle[dependencies.end() :]
            )
    return gradle


def prepare_android(root: Path = ROOT) -> None:
    manifest_path = root / "android/app/src/main/AndroidManifest.xml"
    gradle_path = root / "android/app/build.gradle.kts"
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Android manifest not found: {manifest_path}")
    if not gradle_path.is_file():
        raise FileNotFoundError(f"Android Gradle file not found: {gradle_path}")

    manifest = ensure_internet_permission(manifest_path.read_text())
    gradle = enable_core_library_desugaring(gradle_path.read_text())
    manifest_path.write_text(manifest)
    gradle_path.write_text(gradle)
    if INTERNET_PERMISSION not in manifest_path.read_text():
        raise RuntimeError("Android INTERNET permission was not added")
    if DESUGARING_DEPENDENCY not in gradle_path.read_text():
        raise RuntimeError("Android core library desugaring was not enabled")


if __name__ == "__main__":
    prepare_android()
