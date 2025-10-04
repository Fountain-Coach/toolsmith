# Distributing Toolsmith VM Images via GHCR (OCI)

This guide shows how to package the Toolsmith QCOW2 image as an OCI artifact in GitHub Container Registry (GHCR) and configure Toolsmith to hydrate it using the `oras` CLI.

## Publish to GHCR

Prerequisites:
- `oras` installed (https://oras.land/)
- `GHCR_TOKEN` with `write:packages` (and `read:packages` for consumption)
- `GITHUB_ACTOR` or `GHCR_USERNAME`

Steps:
1. Compute the checksum of the final QCOW2 file:
   - `sha256sum dist/image.qcow2`
2. Login to GHCR:
   - `oras login ghcr.io -u "$GITHUB_ACTOR" -p "$GHCR_TOKEN"`
3. Push the artifact (choose suitable OWNER/REPO:VERSION):
   - `oras push ghcr.io/OWNER/REPO:VERSION dist/image.qcow2:application/vnd.fountain.toolsmith.qcow2 \
       --annotation org.opencontainers.image.title=image.qcow2 \
       --artifact-type application/vnd.fountain.toolsmith.qcow2`
4. Save the SHA‑256 from step 1 for the consumer manifest.

Notes:
- You can include additional files (e.g. manifest fragments) by listing more `path:mediaType` pairs.
- To keep the artifact small, ensure the QCOW2 is sparsified/compressed before pushing.

## Consume with Toolsmith

In `.toolsmith/tools.json` (or whichever manifest you load), set:

```json
{
  "image": {
    "name": "fountainkit-toolsmith",
    "tarball": "",                 
    "sha256": "",                  
    "qcow2": "oci://ghcr.io/OWNER/REPO:VERSION",
    "qcow2_sha256": "<SHA256 of the QCOW2 file>"
  },
  "tools": {},
  "operations": []
}
```

Runtime requirements:
- Install `oras` and ensure it’s on PATH, or set `TOOLSMITH_ORAS=/path/to/oras`.
- For private artifacts, set either:
  - `GHCR_USERNAME` + `GHCR_TOKEN`, or
  - `GITHUB_ACTOR` + `GHCR_TOKEN`.

What Toolsmith does:
- Detects the `oci://` scheme, pulls the artifact into a temp directory using `oras pull`, locates a `.qcow2`, moves it to `.toolsmith/cache/<image>/<digest>/<qcow2>`, verifies `qcow2_sha256`, and proceeds with boot.

## Troubleshooting
- `oras not found`: install ORAS or set `TOOLSMITH_ORAS` to its path.
- `Unauthorized`/`Forbidden`: verify `GHCR_TOKEN` scope (`read:packages`) and username/actor.
- `No .qcow2 payload found`: ensure you pushed the QCOW2 file as a layer and used a `.qcow2` filename.

## GitHub Actions Workflow

This repository includes a reusable workflow to publish a QCOW2 to GHCR and verify availability by polling with `oras pull`:

- File: `.github/workflows/publish-oci.yml`
- Triggers: `workflow_dispatch` and `workflow_call`
- Inputs:
  - `qcow2_path` (default `dist/image.qcow2`)
  - `artifact_name` (optional; download a prior build artifact into `dist/`)
  - `image_ref` (default `ghcr.io/<owner>/<repo>:latest`)

The workflow pins `oras-project/setup-oras@v1` to `version: 1.3.0` (note: without the leading `v`). After pushing, it polls GHCR by running `oras pull` until a `.qcow2` is available, and writes details to the job summary.
