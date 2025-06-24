- DEPLOY_IPK_FEED <br>
DEPLOY_IPK_FEED to "1", which will generate local deploy ipk feed. This will generate the Packages.gz for all the archs present in the ${TMPDIR}/deploy/ipk/ folder.

- GENERATE_IPK_VERSION_DOC <br>
GENERATE_IPK_VERSION_DOC to "1" to generate ipk feed specific version information documentation of respective packages.

- FEED_INFO_DIR <br>
Pkgdata directory to store all the ipk feed information

- IPK_PKGGROUP_VER_INFO <br>
Store packagegroup version details to create version info in the final image

- SYSROOT_IPK <br>
Common staging directory to store the IPK package files

- IPK_CACHE_DIR <br>
IPK Cache/download directory

- IPKGCONF_LAYERING <br>
opkg configuration for stack layering support

- IPK_EXCLUSION_LIST <br>
List of packages to be excluded from IPK consumption.

- OPKG_ARCH_PRIORITY <br>
configure the priority of the IPK feed. Ex. OPKG_ARCH_PRIORITY:[arch] = "[priority]".<br/>
Example: OPKG_ARCH_PRIORITY:armv7at2hf-neon = "100"

- DOCKER_NATIVE_SYSROOT <br>
Path to the prebuilt toolchain and native packages.

- KERNEL_IMAGEDEST <br>
Kernel image destination folder which is required for prebuilt consumption.

- FIRMWARE_IMAGEDEST <br> 
Firmware destination folder which is required for prebuilt consumption.

- EXCLUDE_IPK_FEEDS <br>
Set this option with archs to exclude specific feeds from the IPK package check. The corresponding feeds will then be excluded from IPK consumption.

- STACK_LAYER_EXTENSION <br>
Set this option with archs to enable IPK consumption of packages through recipe processing. It will check the package versions in the recipes and the feeds, and if the versions match, all Yocto build tasks will be skipped and the IPKs from the feeds will be used for populating sysroot.

- SKIP_RECIPE_IPK_PKGS <br>
Set this option will skip the depends arch from STACK_LAYER_EXTENSION check. This will directly install the IPKs to the common staging area instead of processing through recipes.

- DEPENDS_ON_TARGET <br>
Setting this option to '1' will check if the package has dependencies on the target packages. If so, it will build the package from source instead of using prebuilt IPKs.

- DEPENDS_VERSION_CHECK <br>
Setting this option to '1' will check if any dependency package's major version has changed. If so, it will build the package from source instead of using prebuilt IPKs.  This works only for packages that have global PV values set. Example: PV:pn-openssl = "1.1.1l"."
