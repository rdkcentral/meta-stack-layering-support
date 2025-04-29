# meta-stack-layering-support

*Stack layering support with IPK package management system.*

**Maintainer:**  
Sreejith Ravi

---

## Introduction

The **meta-stack-layering-support** layer enhances our Yocto-based (`yotco`) build process by enabling a modular, IPK-driven workflow. Instead of rebuilding every component from source in a monolithic fashion, this layer allows you to:

- **Consume prebuilt IPKs** when versions match, speeding up builds and saving disk space.  
- **Rebuild from source** only on version changes, ensuring traceability and consistency.  
- **Assemble custom rootfs images** by staging IPKs into both final images and per-recipe sysroots.

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

- **staging-ipk**  
  Installs IPKs identified by `base-deps-resolver` into a shared staging directory. It uses caching flags (`--no-install-recommends`, `--host-cache-dir`) to minimize disk usage and speed up repeated operations.

- **custom-rootfs-creation**  
  Manages installation of layer-provided IPKs into the final rootfs. Hooks (`update_opkg_config`, `update_install_pkgs_with_version`) customize `opkg.conf` and pin versions for development vs. release workflows.

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

## IPK Mode Support

**Purpose:** Dynamically switch between source builds and IPK consumption based on version continuity.

- Skip BitBake tasks and fetch prebuilt `.ipk` feeds when package versions align with previous releases.  
- Trigger a rebuild from source if a package or any dependency experiences a major version bump, providing clear parse-time errors with guidance for resolution.

_For detailed steps and examples, see [IPK Mode Support](https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/ipk-mode-support.md)._

---

## Native Toolchain Support

**Purpose:** Prebuild and reuse native packages (e.g., `opkg-native`, `kernel-devel`) within VM/Docker workflows.

1. Run `bitbake <native-recipe>` (e.g., `bitbake opkg-native`).  
2. Copy native IPKs from `${COMPONENTS_DIR}/${BUILD_ARCH}` to a staging path (default `/opt/staging-native/x86_64`), or set a custom path via `DOCKER_NATIVE_SYSROOT`.  
3. Inherit `kernel-devel` to generate kernel development IPKs for module compilation.

This approach standardizes the host toolchain and dramatically reduces rebuild times in containerized builds.

_For a full walkthrough, see [Native Toolchain Support](https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/native-toolchain-support.md)._

---

## Custom Rootfs Creation & IPK Dependency Resolution

**Purpose:** Integrate IPK-only components into rootfs images and recipe sysroots without corresponding BitBake recipes.

- **`custom-rootfs-creation.bbclass`**: Adjusts `opkg.conf` and enforces versioned IPK installation for final images.  
- **`base-deps-resolver.bbclass`**: Captures missing dependencies during parsing, updates metadata, and injects `staging-ipk-pkgs` as a dependency.  
- **`staging-ipk.bbclass` & `staging-ipk-pkgs.bb`**: Populate a shared staging directory, then hardlink files into each recipe sysroot to satisfy `DEPENDS`/`RDEPENDS`.

This design ensures that only the minimal required files are staged, avoiding full installs and preserving build efficiency.

_For design details and log locations, see [Stack Layering Support](https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/stack-layering-support.md)._

---

## Configuration Variables

Add these settings to `local.conf` or your layer’s `conf/layer.conf` under an “IPK Layering” section:

| Variable                  | Purpose                                                                             | Example                                                           |
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

Before enabling stack layering, verify:

- **Yocto/OE-core** with patch `4b5c8b7` applied (`Requires.private` support).  
- `meta-stack-layering-support` at **v2.0.0** or later.  
- Artifactory feed URIs set via `STACK_LAYER_EXTENSION` and `IPK_FEED_URIS`.  
- BitBake environment sourced (`oe-init-build-env`) and variables like `${COMPONENTS_DIR}` defined.

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
