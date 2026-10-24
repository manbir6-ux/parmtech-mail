import base64
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GRADLE = ROOT / "android/app/build.gradle.kts"
KEYSTORE = ROOT / "android/app/upload-keystore.jks"
PROPERTIES = ROOT / "android/key.properties"


def configure_signing(root: Path = ROOT, environ: dict[str, str] | None = None) -> bool:
    env = os.environ if environ is None else environ
    required = {
        "ANDROID_KEYSTORE_BASE64": env.get("ANDROID_KEYSTORE_BASE64", ""),
        "ANDROID_KEYSTORE_PASSWORD": env.get("ANDROID_KEYSTORE_PASSWORD", ""),
        "ANDROID_KEY_ALIAS": env.get("ANDROID_KEY_ALIAS", ""),
        "ANDROID_KEY_PASSWORD": env.get("ANDROID_KEY_PASSWORD", ""),
    }
    if not all(required.values()):
        print("Stable Android signing is not configured; this APK uses the runner's temporary debug key.")
        print("Set the four ANDROID_* GitHub Actions secrets to make future APKs upgrade-compatible.")
        return False

    gradle_path = root / "android/app/build.gradle.kts"
    keystore_path = root / "android/app/upload-keystore.jks"
    properties_path = root / "android/key.properties"
    if not gradle_path.is_file():
        raise FileNotFoundError(f"Android app Gradle file not found: {gradle_path}")
    keystore_path.write_bytes(base64.b64decode(required["ANDROID_KEYSTORE_BASE64"], validate=True))
    properties_path.write_text(
        "storeFile=app/upload-keystore.jks\n"
        f"storePassword={required['ANDROID_KEYSTORE_PASSWORD']}\n"
        f"keyAlias={required['ANDROID_KEY_ALIAS']}\n"
        f"keyPassword={required['ANDROID_KEY_PASSWORD']}\n"
    )
    gradle = gradle_path.read_text()
    if "keystorePropertiesFile" not in gradle:
        bootstrap = (
            "import java.io.FileInputStream\n"
            "import java.util.Properties\n\n"
            "val keystoreProperties = Properties()\n"
            'val keystorePropertiesFile = rootProject.file("key.properties")\n'
            "if (keystorePropertiesFile.exists()) {\n"
            "    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }\n"
            "}\n\n"
        )
        gradle = bootstrap + gradle
    if "create(\"release\")" not in gradle:
        gradle = gradle.replace(
            "android {\n",
            "android {\n    signingConfigs {\n        create(\"release\") {\n"
            '            keyAlias = keystoreProperties["keyAlias"] as String\n'
            '            keyPassword = keystoreProperties["keyPassword"] as String\n'
            '            storeFile = file(keystoreProperties["storeFile"] as String)\n'
            '            storePassword = keystoreProperties["storePassword"] as String\n'
            "        }\n    }\n",
            1,
        )
    gradle = gradle.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("release")',
        1,
    )
    if 'signingConfig = signingConfigs.getByName("release")' not in gradle:
        raise ValueError("Could not configure the generated Android release signing block")
    gradle_path.write_text(gradle)
    return True


if __name__ == "__main__":
    configure_signing()
