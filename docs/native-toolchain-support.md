### Steps to generate the prebuilt native packages support in VM/docker:
- Build the required native packages using bitbake command
- Copy the native packages prebuilts from ${COMPONENTS_DIR}/${BUILD_ARCH}/ to the docker or VM path
	Default path set is "/opt/staging-native/x86_64"
        If you need to copy to different path, you shoud updatte that path with DOCKER_NATIVE_SYSROOT
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
