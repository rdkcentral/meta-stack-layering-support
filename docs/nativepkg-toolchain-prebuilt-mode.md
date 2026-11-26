# Native packages and toolchain prebuilt mode

The layer can consume prebuilt archives for native and cross recipes rather than running their normal build tasks. It can also generate these archives and package feeds for use by a later build. This mode is controlled by `PREBUILT_NATIVE_SUPPORT` and `GENERATE_NATIVE_PKG_PREBUILT`.

## Consume prebuilt archives

The defaults in `pkg-resolver.conf` are:

| Variable | Default | Purpose |
|---|---|---|
| `PREBUILT_NATIVE_SUPPORT` | `1` | Enables native/cross prebuilt lookup. |
| `PREBUILT_NATIVE_SYSROOT` | `/opt/staging-native-toolchain/prebuilts` | Directory containing versioned prebuilt archives and optional toolchain feeds. |
| `PREBUILT_NATIVE_PKG_TYPE` | `tar.gz` | Archive suffix supported by the current extraction code. |
| `PREBUILT_NATIVE_PKG_EXCLUSION_LIST` | Empty | Native/cross package names that must be built from source. |

For a recipe, the resolver looks for an archive whose name starts with `<recipe>_<PV-without-+suffix>` and ends in the configured archive type. If it finds one and the package is not excluded, it extracts the archive into the recipe sysroot and disables the usual build tasks. If the archive is missing, excluded, or unsupported, the recipe follows the source-build path. The current extraction implementation supports `tar.gz`.

For `gcc-initial`, the resolver can instead use `PREBUILT_GCC_TARGET_REMOTE_FEED` or `PREBUILT_GCC_TARGET_DOCKER_FEED`. GCC/glibc package architecture selection uses `GCC_LAYER_ARCH` and `GLIBC_LAYER_ARCH`.

## Generate prebuilt archives and feeds

Set `GENERATE_NATIVE_PKG_PREBUILT = "1"` in the build that produces the prebuilts. Its default is `"0"`. `NATIVE_PREBUILT_DIR` defaults to `${TOPDIR}/../native-pre-pkgs`.

The build writes version files into generated sysroot components. At build completion, it creates `tar.gz` archives for component directories identified as native or cross packages, copies the configured GCC/glibc IPK feeds when present, and packages `gcc-initial` components when available. The archive names include the package version and revision, for example `openssl-native_3.0.15-r0.tar.gz`.

Copy the generated archives to the directory configured by `PREBUILT_NATIVE_SYSROOT` for consuming builds. Keep the target vendor/toolchain layout consistent across layers; the current configuration sets `TARGET_VENDOR` to `-rdk`.

### GCC and glibc feeds

The layer derives `GCC_LAYER_ARCH` and `GLIBC_LAYER_ARCH` from the toolchain configuration and Linux headers version, appends those architectures to `STACK_LAYER_EXTENSION`, and assigns opkg priorities. By default, local feeds under the prebuilt sysroot are enabled with `ENABLE_DOCKER_TARGET_GCC_FEED` and `ENABLE_DOCKER_TARGET_GLIBC_FEED`. A non-empty `PREBUILT_GCC_TARGET_REMOTE_FEED` or `PREBUILT_GLIBC_TARGET_REMOTE_FEED` takes precedence for its corresponding feed.

## Notes

- `PREBUILT_NATIVE_SUPPORT = "0"` disables native/cross archive consumption.
- Packages in `PREBUILT_NATIVE_PKG_EXCLUSION_LIST` are built from source even when an archive is present.
- Native prebuilt generation and consumption are separate: enable generation in the producer build, and enable support and configure the archive path in the consumer build.
- Archives of types other than `tar.gz` are not currently extracted by the implementation.
