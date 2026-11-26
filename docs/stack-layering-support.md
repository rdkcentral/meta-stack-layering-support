# Stack Layering Support

This layer combines source-built recipes and packages consumed from IPK feeds. Its main components are:

- `base-deps-resolver.bbclass`, enabled through `USER_CLASSES`, which reads feed metadata, routes eligible dependencies to IPK staging, and stages selected IPK files into recipe sysroots.
- `staging-ipk.bbclass`, inherited by `staging-ipk-pkgs.bb`, which installs the dependency IPKs into a common component sysroot.
- `ipk-mode-support-base.bbclass`, which provides IPK download and IPK-mode sysroot tasks.
- `custom-rootfs-creation.bbclass`, enabled through `IMAGE_CLASSES`, which configures rootfs and SDK feeds and records packagegroup versions.
- `kernel-devel.bbclass` and `gir-ipk-qemuwrapper.bbclass`, which provide kernel-module build artifacts and GObject Introspection cross-compilation support.

## Feed metadata and dependency resolution

Each feed entry in `IPK_FEED_URIS` has the form `<architecture>##<URI>`. During configuration parsing, the resolver reads each non-excluded feed's `Packages.gz` index and creates local package, source, and provider metadata under `FEED_INFO_DIR`. Local `file:` feeds are read directly; remote indexes are downloaded. A feed with no available index is skipped.

During recipe parsing and task preparation, the resolver checks dependencies against this metadata and the configured stack-layer architectures. IPK-eligible build and runtime dependencies are recorded as metadata for `staging-ipk-pkgs`; other dependencies remain recipe dependencies. Runtime dependencies can also be added after `read_shlibdeps` from IPK dependency metadata and missing shared-library or pkg-config provider information.

## Common IPK staging

`TARGET_BASED_IPK_STAGING` defaults to `"1"`. When the dependency list produced for the requested build targets exists, `do_populate_ipk_sysroot` stages IPKs required by that list. Otherwise it stages dependencies found in the IPK dependency metadata. Packagegroups are not installed as dependencies; the configured `IPK_INCLUSION_LIST` is also considered.

The staging task uses opkg with `--no-install-recommends` and a shared download cache. It installs runtime and development packages into a work directory, then copies the configured common directories into `SYSROOT_IPK`. Directories such as documentation, locale data, fonts, and test files are excluded from the common sysroot.

For recipes consuming these packages, `do_install_ipk_recipe_sysroot` runs after `do_prepare_recipe_sysroot` and before `do_configure`. It reads package file lists from the common sysroot and hard-links selected paths into the recipe sysroot, falling back to copying across filesystems. It also transfers package information files needed by the recipe sysroot.

## IPK-mode recipes

When a matching package is available and the source-build conditions do not apply, the resolver disables the recipe's normal build tasks and adds `do_ipk_download`. The downloaded IPKs are installed into the recipe sysroot by the IPK-mode `do_populate_sysroot` path. If the package is built from source, the resolver instead adds `do_install_ipk_recipe_sysroot` when IPK dependencies need to be added to the recipe sysroot.

For kernel recipes consumed in IPK mode, the kernel-devel IPK is required. `do_kernel_devel_create` extracts its kernel source and build artifacts for out-of-tree module builds. GObject Introspection dependencies receive generated QEMU scanner/compiler wrappers where required.

## Root filesystem and SDK feeds

Before `do_rootfs`, `do_update_opkg_config` selects feeds from dependency package manifests and available deploy directories, while retaining configured feeds for external or non-stack-layer architectures. It sets `BUILD_IMAGES_FROM_FEEDS` so the rootfs uses that configuration. The rootfs pre-function also writes packagegroup version information to `RELEASE_LAYER_VERSIONS`, taking versions from pkgdata or the feed metadata.

After rootfs creation, `do_copy_boot_files` copies files from the IPK common sysroot's `IMAGEDEST` directory into `DEPLOY_DIR_IMAGE`. The SDK pre-function prepares SDK feed configuration in the same way, using local SDK repositories where appropriate.

When `DEPLOY_IPK_FEED` is enabled, the build-completed handler generates `Packages` and `Packages.gz` indexes for deployed architectures. It can also generate per-architecture `PackagesAndVersions.md` files when `GENERATE_IPK_VERSION_DOC` is enabled.

## Useful logs

- `log.do_populate_ipk_sysroot` in the `staging-ipk-pkgs` work directory shows common IPK staging.
- `log.do_install_ipk_recipe_sysroot` in the recipe work directory shows recipe-sysroot population from the common IPK sysroot.
- `log.do_rootfs` in the image work directory shows rootfs creation and package installation.
- `log.do_package` in the recipe work directory includes runtime dependency processing.
