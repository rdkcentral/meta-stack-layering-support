meta-stack-layering module provides the additional functionalities to handle packages in the ipk format that do not have a corresponding recipe. It requires, below changes in Yocto to generate the proper runtime dependencies:
 
# Define PKGCONFIGSKIPLIST
To generate the broken stack layer's pkgconfig dependencies from packages that do not have a corresponding recipe.
This variable should be set with a list of pkgconfig modules that are not found in any recipe packages. It will be used in the stack layering module to identify the missing dependency from the ipk package.

do_pkgconfig function in package bbclass.
>             if found == False:
>                 bb.note("couldn't find pkgconfig module '%s' in any package" % n)
>                 if n not in (d.getVar('PKGCONFIGSKIPLIST_%s'%pkg) or "").split():
>                    d.appendVar('PKGCONFIGSKIPLIST_%s'%pkg,"%s "%(n))
>         deps_file = os.path.join(pkgdest, pkg + ".pcdeps")

# Define SHLIBSKIPLIST.
To generate the broken stack layer's shared library runtime dependencies from packages that do not have a corresponding recipe.
This variable should be set with a list of shared libraries that are not found in any recipe packages. It will be used in the stack layering module to identify the missing dependency from the ipk package.

do_shlibs function in package bbclass.
>             bb.note("Couldn't find shared library provider for %s, used by files: %s" % (n[0], n[1]))
>             if n[0] not in (d.getVar('SHLIBSKIPLIST_%s'%pkg) or "").split():
>                 d.appendVar('SHLIBSKIPLIST_%s'%pkg,"%s "%(n[0]))
>         deps_file = os.path.join(pkgdest, pkg + ".shlibdeps")


# Add "install_ipk_recipe_sysroot" in useradd bbclass.
To handle the use case where base files are in ipk format

useradd_sysroot_sstate function in useradd bbclass.
>         bb.build.exec_func("useradd_sysroot", d)
>     elif task == "prepare_recipe_sysroot" or task == "install_ipk_recipe_sysroot":

# Requires the upstream patch "Add Requires.private field in process_pkgconfig".

https://github.com/openembedded/openembedded-core/commit/4b5c8b7006aae2162614ba810ecf4418ca3f36b4
