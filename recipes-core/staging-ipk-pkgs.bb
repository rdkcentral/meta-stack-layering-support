SUMMARY = "Install the IPK packages to the common staging directory."

LICENSE = "MIT"

inherit staging-ipk

# Since it is installing the prebuilt IPK, which is already
# stripped, we should skip the strip checking.
INSANE_SKIP:${PN} += " already-stripped "

# Disabling sstate, as this recipe needs to
# execute to install the IPKs.
SSTATE_SKIP_CREATION = "1"

#Enable nativesdk support for the recipe.
BBCLASSEXTEND = "nativesdk"
