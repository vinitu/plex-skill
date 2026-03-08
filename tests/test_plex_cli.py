import importlib.util
import io
import json
import pathlib
import sys
import types
import unittest
from unittest import mock


SCRIPT_PATH = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "plex_cli.py"
SPEC = importlib.util.spec_from_file_location("plex_cli", SCRIPT_PATH)
plex_cli = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(plex_cli)


class PlexCliTests(unittest.TestCase):
    def test_main_returns_json_error_for_missing_config(self) -> None:
        example_path = pathlib.Path("/tmp/plex-skill-test.env.example")

        with mock.patch.dict(plex_cli.os.environ, {"PLEX_BASE_URL": "", "PLEX_TOKEN": ""}, clear=False):
            with mock.patch.object(plex_cli, "DOTENV_PATH", pathlib.Path("/tmp/plex-skill-test.env")):
                with mock.patch.object(plex_cli, "DOTENV_EXAMPLE_PATH", example_path):
                    with mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
                        exit_code = plex_cli.main(["ping"])

        payload = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 1)
        self.assertEqual(payload["success"], False)
        self.assertIn(".env.example", payload["error"])

    def test_main_uses_flags_and_returns_success_json(self) -> None:
        fake_client = mock.Mock()
        fake_client.ping.return_value = {"success": True, "server": {"friendlyName": "Test"}}

        with mock.patch.object(plex_cli, "PlexClient", return_value=fake_client) as client_cls:
            with mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
                exit_code = plex_cli.main(
                    ["--base-url", "http://127.0.0.1:32400/", "--token", "secret", "ping"]
                )

        payload = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 0)
        self.assertEqual(payload["success"], True)
        client_cls.assert_called_once_with(
            base_url="http://127.0.0.1:32400",
            token="secret",
            timeout=20,
        )

    def test_watchlist_sanitizes_nan_rating_key(self) -> None:
        class FakeItem:
            type = "movie"
            title = "Demo"
            year = 2024
            guid = "plex://movie/demo"
            ratingKey = float("nan")
            summary = "summary"

        class FakeAccount:
            def __init__(self, token: str) -> None:
                self.token = token

            def watchlist(self, **kwargs):
                return [FakeItem()]

        fake_pkg = types.ModuleType("plexapi")
        fake_submodule = types.ModuleType("plexapi.myplex")
        fake_submodule.MyPlexAccount = FakeAccount
        fake_pkg.myplex = fake_submodule

        with mock.patch.dict(sys.modules, {"plexapi": fake_pkg, "plexapi.myplex": fake_submodule}):
            client = plex_cli.PlexClient("http://127.0.0.1:32400", "secret")
            result = client.watchlist(libtype="movie")

        self.assertIsNone(result["items"][0]["ratingKey"])


if __name__ == "__main__":
    unittest.main()
