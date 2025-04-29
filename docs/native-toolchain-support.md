### Steps to generate the prebuilt native packages support in VM/docker:
- Build the required native packages using bitbake command. Example "bitbake opkg-native"
- Copy the native package prebuilts from build directory "${COMPONENTS_DIR}/${BUILD_ARCH}" to the Docker or VM path. <br />
     The default path is set to "/opt/staging-native/x86_64". <br /> 
     If we need to copy to a different path, we should update the path variable "DOCKER_NATIVE_SYSROOT" using new path. <br />
- Use the meta-stack-layering-support tag 2.0.0 or higher

### Standardize the TARGET_VENDOR variable
The TARGET_VENDOR variable is used to generate the folder structure for toolchain components. <br />

STAGING_BINDIR_TOOLCHAIN = "${STAGING_DIR_NATIVE}${bindir_native}/${TARGET_ARCH}${TARGET_VENDOR}-${TARGET_OS}" <br />

To ensure that the prebuilt libraries are usable across all stack layers, we should standardize the TARGET_VENDOR value across the entire system.<br />
If we do not use a common value for this variable, we won't be able to use the toolchain's prebuilt libraries, such as libgcc.<br />

### Advantages
- Will use the prebuilt native packages and toolchain from the Docker path instead of building them from source. If any native package is missing in the Docker path, it will be built from source.
- Ensures consistent native packages and toolchain across different stack layer projects.
- Significantly reduces both build time and build server disk usage.
