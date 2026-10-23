import plistlib
import tempfile
import unittest
from pathlib import Path

from prepare_macos import ENTITLEMENT, ENTITLEMENT_FILES, prepare_macos


class MacOSBuildPreparationTests(unittest.TestCase):
    def test_adds_network_client_to_both_entitlement_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative_path in ENTITLEMENT_FILES:
                path = root / relative_path
                path.parent.mkdir(parents=True, exist_ok=True)
                with path.open("wb") as output:
                    plistlib.dump({"com.apple.security.app-sandbox": True}, output)

            prepare_macos(root)

            for relative_path in ENTITLEMENT_FILES:
                with (root / relative_path).open("rb") as source:
                    entitlements = plistlib.load(source)
                self.assertIs(entitlements[ENTITLEMENT], True)
                self.assertIs(entitlements["com.apple.security.app-sandbox"], True)

    def test_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative_path in ENTITLEMENT_FILES:
                path = root / relative_path
                path.parent.mkdir(parents=True, exist_ok=True)
                with path.open("wb") as output:
                    plistlib.dump({ENTITLEMENT: True}, output)

            prepare_macos(root)
            snapshots = [(root / path).read_bytes() for path in ENTITLEMENT_FILES]
            prepare_macos(root)

            self.assertEqual(
                snapshots,
                [(root / path).read_bytes() for path in ENTITLEMENT_FILES],
            )

    def test_missing_generated_entitlement_fails_clearly(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                prepare_macos(Path(directory))


if __name__ == "__main__":
    unittest.main()
