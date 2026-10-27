#!/usr/bin/env python3

import argparse
import base64
import json
import os
import re
import sys
from html.parser import HTMLParser
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


MIRROR = "https://pkg.opnsense.org/"
IMAGE = "koichirok/docker-opnsense"


def fetch_text(url, headers=None):
    request = Request(url, headers={
        "User-Agent": "docker-opnsense-release-check", **(headers or {}),
    })
    with urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


class Links(HTMLParser):
    def __init__(self, page):
        super().__init__()
        self.hrefs = []
        self.feed(page)

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.hrefs.extend(value for key, value in attrs if key == "href" and value)


def latest_series():
    page = fetch_text("https://opnsense.org/download/")
    versions = re.findall(
        r"/releases/(\d+\.\d+)/OPNsense-\1-dvd-amd64\.iso\.bz2", page
    )
    if not versions:
        raise ValueError("Could not determine the Production series from the download page")
    return max(versions, key=version_key)


def version_key(version):
    return tuple(map(int, version.split(".")))


def latest_version(series):
    abis = set()
    for href in Links(fetch_text(MIRROR)).hrefs:
        match = re.fullmatch(r"(?:\./)?FreeBSD:(\d+):amd64/", href)
        if match:
            abis.add(int(match.group(1)))
    if not abis:
        raise ValueError("Could not find any amd64 ABI directories on the package mirror")
    for abi in sorted(abis, reverse=True):
        url = f"{MIRROR}FreeBSD:{abi}:amd64/"
        if f"{series}/" not in Links(fetch_text(url)).hrefs:
            continue
        versions = set()
        for href in Links(fetch_text(f"{url}{series}/latest/All/")).hrefs:
            match = re.fullmatch(r"opnsense-(\d+\.\d+(?:\.\d+)?)(?:_\d+)?\.pkg", href)
            if match:
                version = match.group(1)
                if version == series or version.startswith(f"{series}."):
                    versions.add(version)
        if not versions:
            raise ValueError(f"No stable OPNsense package found for series {series}")
        # Ignore package revisions, matching the version tags produced by the build.
        return max(versions, key=version_key)
    raise ValueError(f"No amd64 package repository found for series {series}")


def tag_exists(version):
    headers = {}
    if os.environ.get("GH_TOKEN"):
        actor = os.environ.get("GITHUB_ACTOR")
        if not actor:
            raise ValueError("GITHUB_ACTOR is required when GH_TOKEN is set")
        credentials = base64.b64encode(
            f"{actor}:{os.environ['GH_TOKEN']}".encode("utf-8")
        ).decode("ascii")
        headers["Authorization"] = f"Basic {credentials}"
    query = urlencode({"service": "ghcr.io", "scope": f"repository:{IMAGE}:pull"})
    auth = json.loads(fetch_text(f"https://ghcr.io/token?{query}", headers=headers))
    if not isinstance(auth, dict) or not isinstance(auth.get("token"), str) or not auth["token"]:
        raise ValueError("GHCR token response did not contain a valid token")
    url = f"https://ghcr.io/v2/{IMAGE}/manifests/{version}"
    headers = {
        "Authorization": f"Bearer {auth['token']}",
        "Accept": ", ".join((
            "application/vnd.oci.image.manifest.v1+json",
            "application/vnd.oci.image.index.v1+json",
            "application/vnd.docker.distribution.manifest.v2+json",
            "application/vnd.docker.distribution.manifest.list.v2+json",
        )),
    }
    try:
        manifest = json.loads(fetch_text(url, headers=headers))
    except HTTPError as error:
        if error.code == 404:
            return False
        raise
    if not isinstance(manifest, dict) or manifest.get("schemaVersion") != 2:
        raise ValueError(f"Unexpected GHCR manifest for {IMAGE}:{version}")
    return True


def check(series, force=False):
    version = latest_version(series)
    return {
        "series": series,
        "version": version,
        "should_build": str(force or not tag_exists(version)).lower(),
    }


def main():
    parser = argparse.ArgumentParser(description="Check for an unpublished OPNsense version")
    parser.add_argument("--series", default=os.environ.get("OPNSENSE_SERIES", ""))
    parser.add_argument("--series-only", action="store_true")
    parser.add_argument("--force", choices=("true", "false"), default="false")
    args = parser.parse_args()
    series = args.series or latest_series()
    if not re.fullmatch(r"\d+\.\d+", series):
        raise ValueError(f"Invalid OPNsense series: {series}")
    if args.series_only:
        print(series)
        return
    outputs = check(series, args.force == "true")
    print(json.dumps(outputs))
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            for key, value in outputs.items():
                output.write(f"{key}={value}\n")


if __name__ == "__main__":
    try:
        main()
    except (OSError, URLError, ValueError) as error:
        sys.exit(f"OPNsense release check failed: {error}")
