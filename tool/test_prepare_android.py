import unittest

from prepare_android import (
    DESUGARING_DEPENDENCY,
    INTERNET_PERMISSION,
    enable_core_library_desugaring,
    ensure_internet_permission,
)


class AndroidBuildPreparationTests(unittest.TestCase):
    def test_manifest_permission_insertion_is_idempotent(self):
        manifest = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <application />\n</manifest>'
        prepared = ensure_internet_permission(manifest)
        self.assertIn(INTERNET_PERMISSION, prepared)
        self.assertEqual(ensure_internet_permission(prepared), prepared)
        self.assertEqual(prepared.count(INTERNET_PERMISSION), 1)

    def test_gradle_desugaring_configuration_is_idempotent(self):
        gradle = """android {
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
}
"""
        prepared = enable_core_library_desugaring(gradle)
        self.assertIn("isCoreLibraryDesugaringEnabled = true", prepared)
        self.assertIn(DESUGARING_DEPENDENCY, prepared)
        self.assertEqual(enable_core_library_desugaring(prepared), prepared)

    def test_missing_generated_android_structure_fails_clearly(self):
        with self.assertRaises(ValueError):
            ensure_internet_permission("<application />")
        with self.assertRaises(ValueError):
            enable_core_library_desugaring("android { }")


if __name__ == "__main__":
    unittest.main()
