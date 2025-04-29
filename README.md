# meta-stack-layering-support

*Stack layering module with IPK package management system.*

**Maintainer:**  
Sreejith Ravi

---
## Directory Layout Sketch

```bash
├── CHANGELOG.md
├── classes
│   ├── base-deps-resolver.bbclass
│   ├── custom-rootfs-creation.bbclass
│   ├── gir-ipk-qemuwrapper.bbclass
│   ├── kernel-devel.bbclass
│   ├── staging-ipk.bbclass
│   └── update-base-files-hostname.bbclass
├── conf
│   ├── include
│   │   └── pkg-resolver.conf
│   └── layer.conf
├── CONTRIBUTING.md
├── COPYING -> LICENSE
├── docs
│   ├── ipk-mode-support.md
│   ├── native-toolchain-support.md
│   ├── prerequisite.md
│   ├── stack-layering-support.md
│   └── variables.md
├── lib
│   └── oe
│       └── sls_utils.py
├── LICENSE
├── NOTICE
├── README.md
└── recipes-core
    └── staging-ipk-pkgs.bb
```
## Introduction

The **meta-stack-layering-support** layer enhances our Yocto-based (`yotco`) build process by enabling a modular, IPK-driven workflow. Instead of rebuilding every component from source in a monolithic fashion, this layer allows you to:

- **Consume prebuilt IPKs** from other stack layers without using package recipes. It also helps with IPK consumption within the same stack layer when versions match — speeding up builds and saving disk space.  
- **Rebuild from source** based on version changes, ensuring traceability and consistency.  
- **Assemble custom rootfs images** by using both in IPK mode and source mode packages.

Central to this functionality are several BBClasses that automate dependency resolution, metadata generation, and sysroot population. The sections below explain their roles and how to configure and use them.

---

## Table of Contents

- [Key BBClasses & Their Roles](#key-bbclasses--their-roles)  
- [Recipes (.bb)](#recipes-bb)  
- [IPK Mode Support](#ipk-mode-support)  
- [Native Toolchain Support](#native-toolchain-support)  
- [Custom Rootfs Creation & IPK Dependency Resolution](#custom-rootfs-creation--ipk-dependency-resolution)  
- [Configuration Variables](#configuration-variables)  
- [Prerequisites](#prerequisites)  
- [Further Reading](#further-reading)

---

## Key BBClasses & Their Roles

These classes drive the IPK-based layering logic. They are globally inherited or applied to specific recipes to manage metadata, staging, and installation.

- **base-deps-resolver**  
  Parses `DEPENDS` and `RDEPENDS` in each recipe, generates IPK metadata files (`.pcdeps`, `.shlibdeps`), and creates hardlinks for required files in the recipe sysroot. This ensures broken or missing dependencies are captured and later resolved.
  It is globally inherited.

- **staging-ipk**  
  Installs IPKs identified by `base-deps-resolver` into a shared staging directory. It uses caching flags (`--no-install-recommends`, `--host-cache-dir`) to minimize disk usage and speed up repeated operations.

- **custom-rootfs-creation**  
  Manages installation of layer-provided IPKs into the final rootfs. 

- **gir-ipk-qemuwrapper**  
  Provides QEMU wrapper functions to support GObject Introspection tools when cross-staging IPKs.

- **update-base-files-hostname**  
  Updates `/etc/hostname` and `/etc/hosts` entries in IPK-mode images to match the `MACHINE` name, ensuring consistency in network configuration.

- **kernel-devel**  
  Generates a `kernel-devel` IPK containing kernel headers and build artifacts. This package enables out-of-tree kernel module builds without the full kernel source.

---

## Recipes (.bb)

| Recipe Name             | Inherits        | Purpose                                                                         |
|-------------------------|-----------------|---------------------------------------------------------------------------------|
| `staging-ipk-pkgs.bb`   | `staging-ipk`   | Applies `staging-ipk` logic to install IPK packages into individual recipe sysroots. |

---

## IPK Mode Support experimental

**Purpose:** Dynamically switch between source builds and IPK consumption based on version continuity.

- Skip BitBake tasks and fetch prebuilt `.ipk` feeds when package versions align with previous releases.  
- Trigger a rebuild from source if a package or any dependency experiences a major version bump, providing clear parse-time errors with guidance for resolution.

_For detailed steps and examples, see [IPK Mode Support](https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/ipk-mode-support.md)._

---

## Native Toolchain Support

**Purpose:** Prebuild and reuse native packages within VM/Docker workflows.

In the stack layering model, we have separate build projects for each layer, along with an additional IA Assembler project for creating the full stack image. However, in all projects, the toolchain and native packages are built from source, which is a drawback of our layered model approach.<br/>

To address this, we have designed and integrated a new feature that allows consuming native packages and the toolchain from Docker/VM as prebuilts. This feature helps avoid building the toolchain and packages from source.

This approach standardizes the host toolchain and dramatically reduces rebuild times in containerized builds.

_For a full walkthrough, see [Native Toolchain Support](https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/native-toolchain-support.md)._

---

## Custom Rootfs Creation & IPK Dependency Resolution

**Purpose:** Create custom opkg configuration and generate version info for the packagegroups set in the IMAGE_INSTALL. This will support rootfs genration using both in IPK mode and source mode packages

_For design details and log locations, see [Stack Layering Support](https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/stack-layering-support.md)._

---

## Configuration Variables

Add these settings to `local.conf` or your layer’s `conf/layer.conf` under an “IPK Layering” section:

  | Variable                  | Purpose                                                                             | Usage/path                                                           |
|---------------------------|-------------------------------------------------------------------------------------|-------------------------------------------------------------------|
| `DEPLOY_IPK_FEED`         | Generate a local IPK feed (set to `"1"`).                                           | `DEPLOY_IPK_FEED = "1"`                                           |
| `FEED_INFO_DIR`           | Directory for generated IPK feed metadata.                                          | `FEED_INFO_DIR = "${TMPDIR}/ipk-feed-info"`                      |
| `IPK_PKGGROUP_VER_INFO`   | Store packagegroup version details for final image metadata.                        | `IPK_PKGGROUP_VER_INFO = "${WORKDIR}/pkggroup-versions"`         |
| `SYSROOT_IPK`             | Path to the common staging directory for IPK files.                                 | `SYSROOT_IPK = "${TOPDIR}/staging-ipk"`                          |
| `IPK_CACHE_DIR`           | Directory to cache downloaded IPKs before staging.                                  | `IPK_CACHE_DIR = "${DL_DIR}/ipk-cache"`                          |
| `IPKGCONF_LAYERING`       | Path to a custom `opkg.conf` used for stack-layering operations.                    | `IPKGCONF_LAYERING = "${LAYERDIR}/conf/opkg-layering.conf"`      |
| `IPK_EXCLUSION_LIST`      | Space-separated list of recipes to force source builds.                             | `IPK_EXCLUSION_LIST = "busybox libssl"`                          |
| `OPKG_ARCH_PRIORITY`      | Define IPK feed priority per architecture (format: `<arch> = "<prio>"`).           | `OPKG_ARCH_PRIORITY:x86_64 = "5"`                                |

_Refer to the full variable guide: [Variables](https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/variables.md)._

---

## Prerequisites

Before enabling stack layering, verify with prerequisites checklist:

_See the detailed prerequisites checklist: [Prerequisite](https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/prerequisite.md)._

---

## Further Reading

- **IPK Mode Support**: Version-based source vs. IPK builds.  
  https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/ipk-mode-support.md  
- **Native Toolchain Support**: VM/Docker native package staging.  
  https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/native-toolchain-support.md  
- **Prerequisite**: Yocto version and layer setup.  
  https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/prerequisite.md  
- **Stack Layering Support**: Core bbclass extensions and flow.  
  https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/stack-layering-support.md  
- **Variables**: Complete list of config variables.  
  https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/variables.md
