# meta-stack-layering-support
Stack layering support with IPK package management system.

## Maintainer:
Sreejith Ravi <sreejith.ravi@sky.uk> <br />


### Introduction
This document provides a high-level overview of the enhancements to our Yocto-based build system (yotco) that first-time users need to understand. The goals are:
- Faster Builds: Leverage prebuilt layers and IPK packages to avoid unnecessary source compilation.
- Layered Architecture: Consume prebuilt layers (IPKs) into a final image, replacing a single monolithic build.
- Consistency & Traceability: Version-based rebuilds and clear dependency tracking.
Each section below summarizes a key feature; for full details, follow the links to the in-depth guides.

### IPK Mode Support
- Purpose: Switch individual components between building from source and consuming prebuilt .ipk packages based on version changes.
BitBake will skip default tasks and fetch .ipk feeds when versions match previous releases.
If a package or its dependency has a major version change, it triggers a source rebuild and surfaces parse-time errors with guidance.
For detailed steps and examples, see IPK Mode Support.

### Native Toolchain Support
Purpose: Generate and consume prebuilt native packages (e.g., opkg-native, kernel-devel) inside VM or Docker environments.
Build native recipes (e.g., bitbake opkg-native).
Copy outputs to a staging path (default /opt/staging-native/x86_64) or override via DOCKER_NATIVE_SYSROOT.
Inherit kernel-devel to produce kernel development IPKs for out-of-tree modules.
This ensures a consistent toolchain and minimizes rebuilds in container-based workflows.
For a full walkthrough, see Native Toolchain Support.

### Custom Rootfs Creation & IPK Dependency Resolution
Purpose: Seamlessly install IPK-only packages into both the final rootfs and individual recipe sysroots, resolving dependencies without source recipes.
custom-rootfs-creation.bbclass: Hooks (update_opkg_config, update_install_pkgs_with_version) adjust opkg.conf and ensure correct versions.
base-deps-resolver.bbclass: Parses DEPENDS/RDEPENDS, generates metadata (.pcdeps, .shlibdeps), and updates dependency lists.
staging-ipk.bbclass & staging-ipk-pkgs.bb: Stage IPKs into a shared sysroot using caching flags (--no-install-recommends, --host-cache-dir).
Recipe Sysroot Population: Create hardlinks for required files from the common staging directory instead of full installs.
For detailed design and per-stage logging paths, see Stack Layering Support.

### Configuration Variables
Below are the primary variables you can set in local.conf or conf/layer.conf to control IPK layering:
Variable	Purpose
DEPLOY_IPK_FEED	Enable generation of a local IPK feed (set to "1").
FEED_INFO_DIR	Directory for deployable IPK feed metadata.
IPK_PKGGROUP_VER_INFO	Record package group version data for inclusion in the final image.
SYSROOT_IPK	Common staging directory for all IPK files.
IPK_CACHE_DIR	Directory for IPK download/cache before staging.
IPKGCONF_LAYERING	Path to custom opkg.conf for stack layering.
IPK_EXCLUSION_LIST	Space-separated recipes to always build from source.
OPKG_ARCH_PRIORITY	Per-architecture feed priority (e.g., x86_64 = "5").
See the full variable reference and defaults: Variables.

### Prerequisites
Before using these features, ensure:
Yocto Version: Compatible with OpenEmbedded/OE-core patch 4b5c8b7 (Add Requires.private support).
meta-stack-layering-support: Version 2.0.0 or later.
Artifactory Feeds: Properly configured in STACK_LAYER_EXTENSION and IPK_FEED_URIS.
Environment: BitBake environment initialized (oe-init-build-env), and necessary directories (COMPONENTS_DIR, BUILD_ARCH) set.
For a detailed checklist, see Prerequisites.

### Further Reading
IPK Mode Support: Switching source vs. IPK builds.
https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/ipk-mode-support.md
Native Toolchain Support: Prebuilt native packages & toolchain layering.
https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/native-toolchain-support.md
Prerequisites: Yocto version, layer configuration, upstream patches.
https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/prerequisite.md
Stack Layering Support: Core bbclass extensions & staging flow.
https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/stack-layering-support.md
Variables: Complete list of configuration variables & defaults.
https://github.com/rdkcentral/meta-stack-layering-support/blob/main/docs/variables.md

