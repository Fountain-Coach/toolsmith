# Release Process

This project keeps the source of truth for the VM image build pipeline in the
Git repository while distributing the binary QCOW2 artifacts through GitHub
Releases. Follow this checklist to create a tagged release that includes the
corresponding VM image asset.

## 1. Prepare the QCOW2 image

1. Build the VM image using the automation from the manifest referenced by the
   repository. Ensure the resulting image has the expected OS configuration and
   Toolsmith agents pre-installed.
2. Convert the image to QCOW2 format if needed:

   ```bash
   qemu-img convert -c -O qcow2 source.img toolsmith-vm.qcow2
   ```

3. Compute the SHA-256 digest and record it in the manifest so Toolsmith can
   verify the artifact on hydration:

   ```bash
   shasum -a 256 toolsmith-vm.qcow2 > toolsmith-vm.qcow2.sha256
   ```

4. Store both files (`toolsmith-vm.qcow2` and `toolsmith-vm.qcow2.sha256`) in a
   staging directory ready for upload.

## 2. Tag the release

1. Update `Package.swift` and any documentation to reflect the new version
   number.
2. Commit the changes and create an annotated tag:

   ```bash
   git tag -a vX.Y.Z -m "Toolsmith vX.Y.Z"
   git push origin main --tags
   ```

## 3. Publish the GitHub Release

1. Draft a new release in the GitHub UI (or via `gh release create`) using the
   same tag (`vX.Y.Z`).
2. Attach the `toolsmith-vm.qcow2` and `toolsmith-vm.qcow2.sha256` files to the
   release. These assets provide the "true physics" of the VM referenced by the
   source tree.
3. Add release notes summarizing changes and the VM image provenance (base
   image, applied patches, etc.).
4. Publish the release.

## 4. Verify the release

1. Download the QCOW2 asset from the release page and validate the checksum
   against the `.sha256` file.
2. Hydrate the image using Toolsmith in a clean environment to ensure the new
   digest is recognized and the VM boots successfully.

Following this process keeps the repository tree authoritative for build logic
while ensuring consumers can fetch the matching VM binary from GitHub Releases.
