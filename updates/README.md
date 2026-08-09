# CachyOS update integration

The native fixes replace modules that are tied to one exact kernel release.
This directory adds an ALPM/Pacman post-transaction hook which detects a newly
installed kernel and matching headers, compiles all enabled fixes before
replacing any module, installs them into that new kernel and regenerates the
initramfs once.

The global installer enables this automatically. For an existing manual
installation, refresh it from the repository root with:

```bash
sudo ./install.sh updates
```

The installer takes a clean source snapshot under
`/usr/local/src/galaxybook12-linux`, writes the selected components and active
kernel package to `/etc/galaxybook12-update.conf`, and installs the hook as
`/etc/pacman.d/hooks/95-galaxybook12-kernel.hook`.

Only the package family of the running kernel is managed. A separately
installed LTS kernel is intentionally left unchanged as a recovery path. Never
reboot into a new kernel until Pacman prints:

```text
Galaxy Book 12: kernel update integration completed successfully.
```

Run a manual rebuild for every installed release in the managed family with:

```bash
sudo /usr/local/libexec/galaxybook12-rebuild-kernels --all
```

If a future kernel changes an internal API and a patch no longer compiles, the
hook exits with an error before installing any of the newly built modules. Boot
the unmodified recovery kernel, update this repository, run
`sudo ./install.sh updates` to refresh the installed sources, and try again.

The hook covers kernel modules. Patched libcamera and Mutter packages use a
higher package release than the validated CachyOS packages, so ordinary
same-version updates do not replace them. A newer upstream version must be
reviewed and rebased in this repository before installation; the global
installer never silently downgrades a newer package.

Remove only the automatic integration with:

```bash
sudo ./updates/uninstall.sh
```
