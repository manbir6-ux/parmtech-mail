import base64
import tempfile
import unittest
from pathlib import Path

from configure_android_signing import configure_signing


class AndroidSigningTests(unittest.TestCase):
    def test_missing_secrets_keeps_build_unmodified(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertFalse(configure_signing(Path(directory), {}))
            self.assertFalse((Path(directory) / "android/app/build.gradle.kts").exists())

    def test_configures_a_stable_release_keystore(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "android/app"
            app.mkdir(parents=True)
            gradle = app / "build.gradle.kts"
            gradle.write_text('''plugins { id("com.android.application") }\nandroid {\n    buildTypes {\n        release {\n            signingConfig = signingConfigs.getByName("debug")\n        }\n    }\n}\n''')
            env = {
                "ANDROID_KEYSTORE_BASE64": base64.b64encode(b"test-keystore").decode(),
                "ANDROID_KEYSTORE_PASSWORD": "store-secret",
                "ANDROID_KEY_ALIAS": "release",
                "ANDROID_KEY_PASSWORD": "key-secret",
            }
            self.assertTrue(configure_signing(root, env))
            self.assertEqual((app / "upload-keystore.jks").read_bytes(), b"test-keystore")
            self.assertIn('signingConfig = signingConfigs.getByName("release")', gradle.read_text())
            self.assertTrue(configure_signing(root, env))
            self.assertEqual(gradle.read_text().count('create("release")'), 1)


if __name__ == "__main__":
    unittest.main()
