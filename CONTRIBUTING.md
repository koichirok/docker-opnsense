# Maintainer notes

This document covers publishing the image and maintaining its automated
build. User-oriented run and local build instructions are in [README.md](./README.md).

## Publishing to GHCR

The scheduled GitHub Actions workflow checks weekly for a new Production
release. A lightweight `check` job reads the stable `opnsense` package version
from the official package mirror (discovering the FreeBSD amd64 ABI for the
selected series), then checks for that version's manifest on GHCR. Only a
missing manifest (HTTP 404 after successful registry authentication) triggers
a build; network, authentication, and parsing errors fail the check instead
of being treated as "no update".

The build pushes the versioned image to GHCR using the automatically provided
`GITHUB_TOKEN`; no Docker Hub credentials or personal access token are needed.
The check job has `packages: read` permission and the build job has
`packages: write` permission. The `workflow_dispatch` trigger can be used to
run it manually; leave the series input empty for the latest Production
series. Enable `force` to skip the registry lookup and rebuild an already
published version.

Package revisions (such as `_1`) and dependency-only updates do not trigger
automatic rebuilds. There is no periodic forced rebuild. The actual updated
guest version must match the checked version before publishing; a mismatch
fails the build so the next run can check again. The current
`anyvm-org/opnsense-builder` release must contain a disk for the selected
series. The build uses KVM when available and falls back to QEMU TCG software
emulation otherwise; TCG can make the update take considerably longer.

For the first publication, run the workflow manually with `force: true`:
GHCR can deny registry token requests for a package that does not exist yet.
After the push, change the package visibility to **Public** in its GitHub
package settings so users can pull without logging in. The workflow links the
package to this repository. If a package with this name already exists,
ensure this repository has Actions access to it before running the workflow.
Outside Actions, the release check can access a public package anonymously;
for authenticated checks, set `GH_TOKEN` and `GITHUB_ACTOR` to credentials
with package read access.
