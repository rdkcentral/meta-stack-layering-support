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
Set this option to exclude specific feeds from the IPK package check. The corresponding feeds will then be excluded from IPK consumption.
