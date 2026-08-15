

[![Build](https://github.com/anyvm-org/debian-builder/actions/workflows/build.yml/badge.svg)](https://github.com/anyvm-org/debian-builder/actions/workflows/build.yml)

Latest: v2.0.0


The image builder for `debian`


All the supported releases are here:



| Release | x86_64 (amd64) | aarch64 (arm64) | riscv64 | ppc64le (ppc64el) |
|---------|---------|---------|---------|---------|
| 13 | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) |
| 12 | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) | — | ✅ (rsync,scp,sshfs,nfs,tar) |

<!-- arch-label: x86_64 = x86_64 (amd64) -->
<!-- arch-label: aarch64 = aarch64 (arm64) -->
<!-- arch-label: ppc64le = ppc64le (ppc64el) -->




How to build:

1. Use the [manual.yml](.github/workflows/manual.yml) to build manually.
   
    Run the workflow manually, you will get a view-only webconsole from the output of the workflow, just open the link in your web browser.
   
    You will also get an interactive VNC connection port from the output, you can connect to the vm by any vnc client.

2. Run the builder locally on your Ubuntu machine.

    Just clone the repo. and run:
    ```bash
    python3 build.py conf/debian-13.conf
    ```
   
