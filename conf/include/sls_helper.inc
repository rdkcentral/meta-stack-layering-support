# Temporary helper function get_toolchain_arch based on OSS get_oss_machine().
# TODO: Replace with a proper local implementation.
def get_toolchain_arch(d):
    arch = ""
    default_tune = d.getVar('DEFAULTTUNE') or ""

    multilib_support = d.getVar('MULTILIBS') or ""
    if multilib_support:
        arch = "rdk-arm64"
    elif "armv7athf-neon" in default_tune:
        arch = "rdk-arm7a"
    elif "cortexa15hf-neon" in default_tune:
        arch = "rdk-cortexa15"
    else:
        arch = "rdk-arm7ve"
    return arch
