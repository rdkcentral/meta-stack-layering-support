# Configuration variables

The values below reflect `conf/include/pkg-resolver.conf` unless noted. Override settings in the build configuration where needed. Feed entries use the format `<architecture>##<URI>`.

## Feed selection and IPK staging

| Variable | Default | Description |
|---|---|---|
| `IPK_FEED_URIS` | No general feed default; GCC/glibc feeds may be appended automatically. | Feed architecture and URI pairs used to retrieve package indexes and IPKs. |
| `STACK_LAYER_EXTENSION` | GCC and glibc architectures are appended by the layer. | Architectures treated as stack-layer feeds for package lookup and source/IPK decisions. Add the target layer architecture here. |
| `EXCLUDE_IPK_FEEDS` | Unset. | Space-separated feed architectures excluded from feed metadata creation and IPK checks. |
| `IPK_EXCLUSION_LIST` | `libdevmapper gnutls libtasn1 make-mod-scripts` | Packages excluded from IPK consumption. |
| `IPK_INCLUSION_LIST` | `libgcc gcc-runtime gcc-sanitizers glibc` | Packages explicitly added to common IPK staging. |
| `SKIP_RECIPE_IPK_PKGS` | `"0"` | When set to `"1"`, skips the normal stack-architecture restriction during IPK availability checks. |
| `TARGET_BASED_IPK_STAGING` | `"1"` | Stages dependencies for the requested target dependency graph when available; otherwise uses the available dependency metadata. |
| `TARGET_DEPS_LIST` | `${TOPDIR}/target_deps_list` | File populated from the dependency graph and used for target-based staging. |
| `IPK_FEED_EXCLUDE_VARS` | `BUILD_VARIANT` | Variable names excluded from dependency tracking for variables referenced by `IPK_FEED_URIS`. |

## Source-build and version decisions

| Variable | Default | Description |
|---|---|---|
| `RECIPE_VER_LIST` | `${TOPDIR}/recipe_versions.txt` | Four-column, pipe-separated recipe version data: recipe, latest, preferred, and required version. Used for dependency-version comparisons. |
| `DEPENDS_REBUILD_VERSION_MATCH` | `"minor"` | Version granularity used for dependency-change source rebuild decisions: `major`, `minor`, `patch`, or empty/other for a full version comparison. |
| `DISABLE_DEPS_SRC_BUILD` | `"0"` | When set to `"1"`, disables dependency-target and dependency-version-based source rebuild decisions. Explicit targets are still handled. |
| `RECOMPILE_TOKEN` | `"None"` | Token used by an orchestrator to request recompilation through task signature dependencies. |

## Directories and rootfs/feed generation

| Variable | Default | Description |
|---|---|---|
| `IPK_PKGDATA_DIR` | `${TMPDIR}/ipk_pkgdata` | Root directory for generated feed and dependency metadata. |
| `FEED_INFO_DIR` | `${IPK_PKGDATA_DIR}/feed_info/` | Generated package, source, and provider metadata for feeds. |
| `DEPS_IPK_DIR` | `${IPK_PKGDATA_DIR}/pkg-deps-ipk` | Dependency metadata used by common IPK staging. |
| `SYSROOT_IPK` | `${STAGING_DIR}-ipk-components` | Common staged IPK sysroot. |
| `IPK_CACHE_DIR` | `${TOPDIR}/downloads-ipk/${BB_CURRENT_MC}` | Download/cache directory for common IPK staging. |
| `IPKGCONF_LAYERING` | `${WORKDIR}/opkg-layer.conf` | Generated opkg configuration for stack-layering operations. |
| `DEPLOY_IPK_FEED` | `"1"` | Generates `Packages` and `Packages.gz` indexes for deployed IPK architectures at build completion. |
| `GENERATE_IPK_VERSION_DOC` | `"0"` | Generates `PackagesAndVersions.md` in each deployed architecture directory. |
| `IPK_PKGGROUP_VER_INFO` | `${FEED_INFO_DIR}/ipk_pkggrp_version` | Packagegroup versions read from feed metadata when runtime pkgdata is unavailable. |
| `RELEASE_LAYER_VERSIONS` | `${TMPDIR}/release_versions` | Output file populated with packagegroup versions for the image. |
| `IMAGEDEST` | `boot` | Common sysroot directory from which boot files are copied to `DEPLOY_DIR_IMAGE`. |
| `KERNEL_IMAGEDEST` | `${IMAGEDEST}` | Kernel image destination setting. |
| `FIRMWARE_IMAGEDEST` | `${IMAGEDEST}` | Firmware image destination setting. |
| `OPKG_ARCH_PRIORITY:<arch>` | GCC: `290`; glibc: `295`. | Feed priority for the specified architecture. Other priorities can be set in the build configuration. |

## Native and toolchain prebuilts

| Variable | Default | Description |
|---|---|---|
| `PREBUILT_NATIVE_SUPPORT` | `"1"` | Enables native and cross prebuilt archive consumption. |
| `PREBUILT_NATIVE_SYSROOT` | `/opt/staging-native-toolchain/prebuilts` | Root directory containing native/cross archives and optional toolchain feeds. |
| `PREBUILT_NATIVE_PKG_TYPE` | `"tar.gz"` | Archive suffix accepted by the current extraction implementation. |
| `PREBUILT_NATIVE_PKG_EXCLUSION_LIST` | Empty | Native/cross packages forced to build from source. |
| `GENERATE_NATIVE_PKG_PREBUILT` | `"0"` | Enables generation of native/cross archives and toolchain feed copies. |
| `NATIVE_PREBUILT_DIR` | `${TOPDIR}/../native-pre-pkgs` | Output directory for generated archives. |
| `GCC_LAYER_ARCH` | Derived from the configured toolchain architecture. | Architecture used for GCC IPK packages and feeds. |
| `GLIBC_LAYER_ARCH` | Derived from toolchain architecture and Linux headers version. | Architecture used for glibc IPK packages and feeds. |
| `PREBUILT_GCC_TARGET_DOCKER_FEED` | `${PREBUILT_NATIVE_SYSROOT}/ipk-feeds/${GCC_LAYER_ARCH}` | Local GCC target feed directory. |
| `PREBUILT_GLIBC_TARGET_DOCKER_FEED` | `${PREBUILT_NATIVE_SYSROOT}/ipk-feeds/${GLIBC_LAYER_ARCH}` | Local glibc target feed directory. |
| `PREBUILT_GCC_TARGET_REMOTE_FEED` | Empty | Optional remote GCC target feed; when set, it takes precedence over the local feed. |
| `PREBUILT_GLIBC_TARGET_REMOTE_FEED` | Empty | Optional remote glibc target feed; when set, it takes precedence over the local feed. |
| `ENABLE_DOCKER_TARGET_GCC_FEED` | `"1"` | Enables use of the local GCC target feed when it exists. |
| `ENABLE_DOCKER_TARGET_GLIBC_FEED` | `"1"` | Enables use of the local glibc target feed when it exists. |
| `TARGET_VENDOR` | `"-rdk"` | Vendor component of the target tuple; keep consistent across layers sharing toolchain prebuilts. |
| `GENERATE_GLIBC_LOCALE_IPK` | `"1"` | Adds the glibc-locale package dependency for targeted packagegroup/image builds unless recipe IPK packages are being skipped. |

`IPK_FEED_URIS`, `STACK_LAYER_EXTENSION`, and feed exclusions affect several stages, including metadata generation, dependency checks, and rootfs feed selection. Configure these consistently for the same build.

The layer does not define `DOCKER_NATIVE_SYSROOT`, `DEPENDS_ON_TARGET`, or `DEPENDS_VERSION_CHECK`; use the `PREBUILT_NATIVE_*`, target-list, and `DEPENDS_REBUILD_VERSION_MATCH` variables documented above.
