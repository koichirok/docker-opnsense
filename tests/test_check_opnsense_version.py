import contextlib
import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/check-opnsense-version.py"
spec = importlib.util.spec_from_file_location("release_check", SCRIPT)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def links(*hrefs):
    return "".join(f'<a href="{href}">{href}</a>' for href in hrefs)


def http_error(code):
    return HTTPError("https://example.invalid/", code, "test error", {}, None)


class ReleaseCheckTests(unittest.TestCase):
    def setUp(self):
        self.pages = {
            "https://opnsense.org/download/": links(
                "/releases/26.1/OPNsense-26.1-dvd-amd64.iso.bz2",
                "/releases/26.7/OPNsense-26.7-dvd-amd64.iso.bz2",
            ),
            release.MIRROR: links(
                "./FreeBSD:14:amd64/", "./FreeBSD:15:amd64/", "FreeBSD:15:aarch64/"
            ),
            f"{release.MIRROR}FreeBSD:15:amd64/": links("26.7/", "snapshots/"),
            f"{release.MIRROR}FreeBSD:14:amd64/": links("26.1/"),
            f"{release.MIRROR}FreeBSD:15:amd64/26.7/latest/All/": links(
                "opnsense-26.7.9.pkg", "opnsense-26.7.10_1.pkg",
                "opnsense-devel-27.1.a_483.pkg", "opnsense-update-26.7.99.pkg",
                "opnsense-26.7.r1.pkg", "opnsense-26.1.99.pkg",
            ),
            f"{release.MIRROR}FreeBSD:14:amd64/26.1/latest/All/": links(
                "opnsense-26.1.12.pkg"
            ),
        }
        self.fetch = patch.object(release, "fetch_text", side_effect=self.pages.__getitem__)
        self.fetch.start()
        self.addCleanup(self.fetch.stop)

    def test_latest_production_series(self):
        self.assertEqual(release.latest_series(), "26.7")

    def test_unparseable_download_page_fails(self):
        self.pages["https://opnsense.org/download/"] = "<html>changed</html>"
        with self.assertRaisesRegex(ValueError, "Production series"):
            release.latest_series()

    def test_numeric_version_order_ignores_revisions_and_other_packages(self):
        self.assertEqual(release.latest_version("26.7"), "26.7.10")

    def test_previous_series_discovers_older_abi(self):
        self.assertEqual(release.latest_version("26.1"), "26.1.12")

    def test_initial_series_release(self):
        self.pages[f"{release.MIRROR}FreeBSD:15:amd64/26.7/latest/All/"] = links(
            "opnsense-26.7.pkg"
        )
        self.assertEqual(release.latest_version("26.7"), "26.7")

    def test_missing_repository_fails(self):
        with self.assertRaisesRegex(ValueError, "No amd64 package repository"):
            release.latest_version("99.7")

    def test_missing_stable_package_fails(self):
        self.pages[f"{release.MIRROR}FreeBSD:15:amd64/26.7/latest/All/"] = links(
            "opnsense-devel-27.1.a_483.pkg"
        )
        with self.assertRaisesRegex(ValueError, "No stable OPNsense"):
            release.latest_version("26.7")

    def test_missing_abi_listing_fails(self):
        self.pages[release.MIRROR] = "<html>changed</html>"
        with self.assertRaisesRegex(ValueError, "ABI directories"):
            release.latest_version("26.7")

    def test_registry_existing_tag(self):
        with patch.dict(os.environ, {}, clear=True):
            with patch.object(release, "fetch_text", side_effect=(
                '{"token":"registry-token"}', '{"schemaVersion":2}',
            )) as fetch:
                self.assertTrue(release.tag_exists("26.7.10"))
        self.assertEqual(fetch.call_args_list[0].args, (
            "https://ghcr.io/token?service=ghcr.io&scope="
            "repository%3Akoichirok%2Fdocker-opnsense%3Apull",
        ))
        self.assertEqual(fetch.call_args_list[0].kwargs, {"headers": {}})
        request = fetch.call_args_list[1]
        self.assertEqual(
            request.args, ("https://ghcr.io/v2/koichirok/docker-opnsense/manifests/26.7.10",)
        )
        self.assertEqual(request.kwargs["headers"]["Authorization"], "Bearer registry-token")
        self.assertIn("application/vnd.oci.image.index.v1+json",
                      request.kwargs["headers"]["Accept"])

    def test_registry_authenticated_token_request(self):
        env = {"GH_TOKEN": "test-token", "GITHUB_ACTOR": "test-user"}
        with patch.dict(os.environ, env, clear=True):
            with patch.object(release, "fetch_text", side_effect=(
                '{"token":"registry-token"}', '{"schemaVersion":2}',
            )) as fetch:
                self.assertTrue(release.tag_exists("26.7.10"))
        authorization = fetch.call_args_list[0].kwargs["headers"]["Authorization"]
        self.assertEqual(base64.b64decode(authorization.removeprefix("Basic ")),
                         b"test-user:test-token")

    def test_registry_actor_required_with_token(self):
        with patch.dict(os.environ, {"GH_TOKEN": "test-token"}, clear=True):
            with self.assertRaisesRegex(ValueError, "GITHUB_ACTOR"):
                release.tag_exists("26.7.10")

    def test_registry_only_404_means_missing(self):
        with patch.object(release, "fetch_text", side_effect=(
            '{"token":"registry-token"}', http_error(404),
        )):
            self.assertFalse(release.tag_exists("26.7.10"))
        for code in (401, 403, 429, 500, 503):
            with self.subTest(code=code):
                with patch.object(release, "fetch_text", side_effect=(
                    '{"token":"registry-token"}', http_error(code),
                )):
                    with self.assertRaises(HTTPError):
                        release.tag_exists("26.7.10")

    def test_registry_token_errors_are_not_missing_tags(self):
        for code in (401, 403, 404, 429, 500):
            with self.subTest(code=code):
                with patch.object(release, "fetch_text", side_effect=http_error(code)):
                    with self.assertRaises(HTTPError):
                        release.tag_exists("26.7.10")

    def test_registry_malformed_token_fails(self):
        for response in ("{}", "[]", '{"token":""}', '{"token":123}', "<html>error</html>"):
            with self.subTest(response=response):
                with patch.object(release, "fetch_text", return_value=response):
                    with self.assertRaises(ValueError):
                        release.tag_exists("26.7.10")

    def test_registry_network_error_fails(self):
        with patch.object(release, "fetch_text", side_effect=URLError("offline")):
            with self.assertRaises(URLError):
                release.tag_exists("26.7.10")

    def test_registry_malformed_response_fails(self):
        for response in ("<html>error</html>", "{}", "[]", '{"schemaVersion":1}'):
            with self.subTest(response=response):
                with patch.object(release, "fetch_text", side_effect=(
                    '{"token":"registry-token"}', response,
                )):
                    with self.assertRaises(ValueError):
                        release.tag_exists("26.7.10")

    def test_build_decision(self):
        for exists, force, expected in (
            (False, False, "true"), (True, False, "false"), (True, True, "true")
        ):
            with self.subTest(exists=exists, force=force):
                with patch.object(release, "tag_exists", return_value=exists):
                    self.assertEqual(release.check("26.7", force), {
                        "series": "26.7", "version": "26.7.10", "should_build": expected,
                    })

    def test_force_skips_registry_for_first_publication(self):
        with patch.object(release, "tag_exists") as lookup:
            self.assertEqual(release.check("26.7", force=True)["should_build"], "true")
        lookup.assert_not_called()

    def test_github_output_shape(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            env = {"GITHUB_OUTPUT": str(output)}
            with patch.dict(os.environ, env, clear=True):
                with patch("sys.argv", [str(SCRIPT)]):
                    with patch.object(release, "tag_exists", return_value=False):
                        with contextlib.redirect_stdout(io.StringIO()) as stdout:
                            release.main()
            self.assertEqual(output.read_text(), (
                "series=26.7\nversion=26.7.10\nshould_build=true\n"
            ))
            self.assertEqual(json.loads(stdout.getvalue())["version"], "26.7.10")

    def test_manual_series_and_force(self):
        with patch.dict(os.environ, {"OPNSENSE_SERIES": "26.1"}, clear=True):
            with patch("sys.argv", [str(SCRIPT), "--force", "true"]):
                with patch.object(release, "tag_exists", return_value=True):
                    with contextlib.redirect_stdout(io.StringIO()) as stdout:
                        release.main()
        self.assertEqual(json.loads(stdout.getvalue()), {
            "series": "26.1", "version": "26.1.12", "should_build": "true",
        })

    def test_series_only_does_not_check_packages_or_registry(self):
        with patch.dict(os.environ, {}, clear=True):
            with patch("sys.argv", [str(SCRIPT), "--series-only"]):
                with contextlib.redirect_stdout(io.StringIO()) as stdout:
                    release.main()
        self.assertEqual(stdout.getvalue(), "26.7\n")

    def test_invalid_series_fails(self):
        with patch("sys.argv", [str(SCRIPT), "--series", "../26.7"]):
            with self.assertRaisesRegex(ValueError, "Invalid OPNsense series"):
                release.main()


if __name__ == "__main__":
    unittest.main()
