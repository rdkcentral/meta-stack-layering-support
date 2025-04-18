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

# Add check for FILES_IPK_PKG:pkg in insane bbclass.
To skip qa check for the files from IPK packages.

package_qa_check_rdepends function in insane bbclass.
>            if filerdepends:
>                for key in filerdepends:
>                    if bb.data.inherits_class('base-deps-resolver', d):
>                        if key.split("(")[0] in (d.getVar("FILES_IPK_PKG:%s"%pkg) or ""):
>                            # Skip qa check for files from IPK
>                            bb.warn("Skipping qa check for file %s which is available in IPK"%key)
>                            continue
>                        else:
>                            # Check for non lib files from IPK
>                            ipk = check_file_provider_ipk(d, key.split("(")[0], rdepends)
>                            if ipk:
>                                bb.warn("Skipping qa check for file %s which is available in IPK %s"%(key, ipk))
>                                continue
>                    error_msg = "%s contained in package %s requires %s, but no providers found in RDEPENDS:%s?" %

# Requires the upstream patch "Add Requires.private field in process_pkgconfig".

https://github.com/openembedded/openembedded-core/commit/4b5c8b7006aae2162614ba810ecf4418ca3f36b4

# Add custom opkg configure function in meta/lib/oe/package_manager/ipk/__init__.py
To set the priority for the feeds.

>        self.from_feeds = (self.d.getVar('BUILD_IMAGES_FROM_FEEDS') or "") == "1"
>        if bb.data.inherits_class('custom-rootfs-creation', d):
>            from oe.sls_utils import sls_opkg_conf
>            sls_opkg_conf (d, self.config_file)
>        elif self.from_feeds:
>             self._create_custom_config()

