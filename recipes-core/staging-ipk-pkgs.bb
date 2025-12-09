SUMMARY = "Install the IPK packages to the common staging directory."

LICENSE = "MIT"
PR = "r1"

inherit staging-ipk

# Since it is installing the prebuilt IPK, which is already
# stripped, we should skip the strip checking.
INSANE_SKIP:${PN} += " already-stripped "

#Enable nativesdk support for the recipe.
BBCLASSEXTEND = "nativesdk"
