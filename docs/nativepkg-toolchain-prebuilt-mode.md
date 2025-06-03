In the stack layering model, we have separate build projects for each layer, along with an additional IA Assembler project for creating the full stack image. However, in all projects, the toolchain and native packages are built from source, which is a drawback of our layered model approach.<br/>

To address this, we have designed and integrated a new feature that allows consuming native packages and the toolchain from Docker/VM as prebuilts. This feature helps avoid building the toolchain and packages from source.

### Standardize the TARGET_VENDOR variable
The TARGET_VENDOR variable is used to generate the folder structure for toolchain components. <br />

STAGING_BINDIR_TOOLCHAIN = "${STAGING_DIR_NATIVE}${bindir_native}/${TARGET_ARCH}${TARGET_VENDOR}-${TARGET_OS}" <br />

To ensure that the prebuilt libraries are usable across all stack layers, we should standardize the TARGET_VENDOR value across the entire system.<br />
If we do not use a common value for this variable, we won't be able to use the toolchain's prebuilt libraries, such as libgcc.<br />

### Steps to generate the prebuilt native packages support in VM/docker:
- Set GENERATE_NATIVE_PKG_PREBUILT to "1"
- Default its value is "0"
- Build the required native packages using bitbake command. Example "bitbake opkg-native"
- It will generate the <pkg-name>-<version>.tar.gz file in ${NATIVE_PREBUILT_DIR}
- Default path is NATIVE_PREBUILT_DIR = "${TMPDIR}/native-pre-pkgs
- Ex: build-rdk-arm64/tmp/native-pre-pkgs/openssl-native_3.0.15-r0.tar.gz
- Copy the native prebuilt package tar files from build directory "${NATIVE_PREBUILT_DIR}" to the Docker or VM path. <br />
     The default path is set to "/opt/staging-native/x86_64". <br /> 
     If you need to copy to a different path, you should update the path variable "DOCKER_NATIVE_SYSROOT" using new path. <br />
- Use the meta-stack-layering-support tag 2.0.3 or higher

### Advantages
- Traceability. We can track the packages using version info
- Easy update. We can independetly update each package 
- Will use the prebuilt native packages and toolchain from the Docker path instead of building them from source. If any native package is missing in the Docker path, it will be built from source.
- Ensures consistent native packages and toolchain across different stack layer projects.
- Significantly reduces both build time and build server disk usage.
