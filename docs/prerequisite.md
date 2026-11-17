# Prerequisites

Add this layer to the build and configure the IPK feeds before enabling IPK consumption. The layer provides the resolver and staging classes, but it does not patch OpenEmbedded Core or other layers. The following integration changes are needed only when the corresponding code is not already present in the build.

## Capture unresolved pkg-config and shared-library dependencies

The resolver reads `PKGCONFIGSKIPLIST_<package>` and `SHLIBSKIPLIST_<package>` when `do_update_rdeps_ipk` runs after `read_shlibdeps`. Core's package dependency scanners must record unresolved modules/libraries in those variables, in addition to reporting them, so the resolver can locate their providers in the IPK sysroot and add runtime dependencies.

The integration points are the `do_pkgconfig` and `do_shlibs` functions in `package.bbclass`. Preserve the existing scanner behavior and append each unresolved item to the package-specific variable, avoiding duplicates. The resolver uses pkg-config module names to look for `.pc` files and shared-library names to look for library files.

## Allow useradd sysroot setup with IPK staging

If the build's `useradd.bbclass` only runs `useradd_sysroot` for `do_prepare_recipe_sysroot`, update its task check to also handle `do_install_ipk_recipe_sysroot`. This layer adds that task between `do_prepare_recipe_sysroot` and `do_configure`; the useradd hook must run for the newly staged recipe sysroot as well.

## Skip QA errors for files supplied by IPKs

Update the build's `insane.bbclass` runtime-dependency QA check to consult `FILES_IPK_PKG:<package>` for files recorded as coming from an IPK. For missing file dependencies not listed there, call `check_file_provider_ipk(d, file, rdepends)` before reporting an error. This lets QA distinguish files supplied by staged IPKs from genuinely unresolved dependencies.

## pkg-config private requirements

The build needs the OpenEmbedded Core change that preserves `Requires.private` while processing pkg-config metadata:

<https://github.com/openembedded/openembedded-core/commit/4b5c8b7006aae2162614ba810ecf4418ca3f36b4>

## Custom opkg configuration hook

Rootfs and SDK package-manager code must use the layer's configured feed data and priorities. The custom rootfs class prepares `IPK_FEED_URIS` and sets `BUILD_IMAGES_FROM_FEEDS`; the opkg package-manager path should call `oe.sls_utils.sls_opkg_conf(d, config_file)` for the `custom-rootfs-creation` class so feed priorities from `OPKG_ARCH_PRIORITY:<arch>` are included.

Verify these integrations against the Yocto/OpenEmbedded revision used by the build. Function names and task hooks can differ between releases; do not apply duplicate patches if the equivalent behavior is already present.
