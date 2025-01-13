# meta-stack-layering-support
Stack layering support with IPK package management system.

## Maintainer:
Sreejith Ravi <sreejith.ravi@sky.uk>

## Table of Contents:
  1. .bbclass
  2. .bb (recipes)

### bbclass:
- base-deps-resolver : Process the DEPENDS and RDEPENDS variables, generate the metadata for the ipk packages, and create the hard links for the required files in the recipe sysroot. This is globally inherited for all the recipes.

- staging-ipk : Process the metadata for the ipk packages generated by base-deps-resolver, installing them into the staging directory to resolve build-time dependencies. This functionality is inherited in the staging-ipk-pkgs recipe and utilizes cache mechanism for component installation.

- custom-rootfs-creation : Create the target rootfs from layer deliveries. 

- gir-ipk-qemuwrapper : qemu wrapper to support IPK packages

- update-base-files-hostname : Update the hostname entry in /etc/hostname and /etc/hosts to MACHINE name in IPK mode.

### .bb (recipes):
- staging-ipk-pkgs : Inherit staging-ipk bbclass for installing the ipk packages to resolve the package dependencies.
