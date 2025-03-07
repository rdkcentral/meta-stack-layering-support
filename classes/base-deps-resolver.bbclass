# -----------------------------------------------------------------------
# File: classes/base-deps-resolver.bbclass
# Author: Sreejith Ravi
# Date: 2024-06-06
#
# Description : Identify packages available as IPK, generate metadata 
# from IPK packages, and create hard links with required IPK files in the 
# recipe sysroot.
# -----------------------------------------------------------------------

STACK_LAYER_SYSROOT_DIRS = "${includedir} ${libdir} ${base_libdir} ${nonarch_base_libdir} ${datadir} "
SYSROOT_DIRS_BIN_REQUIRED = "${MLPREFIX}gobject-introspection"

# Pkgdata directory to store runtime IPK dependency details.
IPK_PKGDATA_RUNTIME_DIR = "${WORKDIR}/pkgdata/ipk"

do_install_ipk_recipe_sysroot[depends] += "opkg-native:do_populate_sysroot"

inherit gir-ipk-qemuwrapper

def decode(str):
    import codecs
    c = codecs.getdecoder("unicode_escape")
    return c(str)[0]

def is_excluded_pkg(d, pkg):
    is_excluded = False
    if not pkg:
        return is_excluded
    pkg = pkg.strip()
    prefix = d.getVar('MLPREFIX') or ""
    if prefix and pkg.startswith(prefix):
        pkg = pkg[len(prefix):]
    if pkg in (d.getVar("IPK_EXCLUSION_LIST") or "").split():
        is_excluded = True
    return is_excluded

# Function reads indirect build and runtime dependencies 
# from the pkgdata directory
def read_ipk_depends(d, pkg):
    pkgdata = {}
    ldeps, lrdeps = ([] for i in range(2))
    if os.path.exists(pkg):
        import re
        ldep = bb.utils.lockfile("%s.lock"%pkg)
        with open(pkg,"r") as fd:
            lines = fd.readlines()
        bb.utils.unlockfile(ldep)
        r = re.compile(r"(^.+?):\s+(.*)")
        for l in lines:
            m = r.match(l)
            if m:
                pkgdata[m.group(1)] = decode(m.group(2))
        if "Depends" in pkgdata:
            ldeps = pkgdata["Depends"].split(", ")
        if "Rdepends" in pkgdata:
            lrdeps = pkgdata["Rdepends"].split(", ")
    return (ldeps,lrdeps)

def create_deps_list_from_ipk(d, pkg_path,extension,pkgdict,archs):
    ldeps = []
    
    for x in pkgdict:
        pkgdata = {}
        if not pkgdict[x] and x and x != " ":
            provider = get_provider(d,x, archs)
            pkg = os.path.join(pkg_path,provider+extension)

            if os.path.exists(pkg):
                import re
                ldep = bb.utils.lockfile("%s.lock"%pkg)
                with open(pkg,"r") as fd:
                    lines = fd.readlines()
                bb.utils.unlockfile(ldep)
                r = re.compile(r"(^.+?):\s+(.*)")
                for l in lines:
                    m = r.match(l)
                    if m:
                        pkgdata[m.group(1)] = decode(m.group(2))
                if "Depends" in pkgdata:
                    for pkg in pkgdata["Depends"].split(", "):
                        if pkg not in ldeps:
                            ldeps.append(pkg)
                pkgdict[x] = True
    return ldeps

def add_indirect_deps(d,dep):
    recipesysrootnative = d.getVar("RECIPE_SYSROOT_NATIVE")
    depdir = recipesysrootnative + "/installeddeps"
    taskindex = depdir + "/" + "index." + "do_prepare_recipe_sysroot"
    if os.path.exists(taskindex):
        with open(taskindex, "r") as f:
            devlines = f.readlines()
        for l in devlines:
            if l.startswith("TaskDeps") or l.strip().endswith("-native"):
                continue
            if l.strip() not in dep:
                dep.append(l.strip())
    return dep

# Update the ipk dependencies and store the details
# in the pkgdata directory for each packages
python update_ipk_deps () {
    import re
    archs = []
    pkgdata_path = d.getVar("DEPS_IPK_DIR")
    deps = d.getVar('DEPENDS').split(" ")
    pkg_pn = d.getVar("PN", True)
    layer_pkgs = (d.getVar('INSTALL_DEPENDS') or "").split(",")

    for line in (d.getVar('IPK_FEED_URIS') or "").split():
        feed = re.match(r"^[ \t]*(.*)##([^ \t]*)[ \t]*$", line)
        if feed is not None:
            archs.append(feed.group(1))

    bb.note("[deps-resolver] Direct depends IPK list : %s " % layer_pkgs)
    feed_info_dir = d.getVar("FEED_INFO_DIR")
    deps = add_indirect_deps(d, deps)
    for pkg in deps:
        ipk_found = False
        if pkg.startswith("virtual/"):
            preferred_provider = d.getVar('PREFERRED_PROVIDER_%s' % pkg, True)
            if preferred_provider is not None:
                pkg = preferred_provider

        for arch in archs:
            skipped_pkg = os.path.join(feed_info_dir,"%s/skipped/%s"%(arch,pkg))
            if os.path.exists(skipped_pkg):
                d.appendVar("INSTALL_DEPENDS", ",%s" % pkg)
                ipk_found = True
                break
        if ipk_found:
            continue

        pkg_path = os.path.join(pkgdata_path,pkg)
        if not os.path.exists(pkg_path) or pkg=="" or pkg==" ":
            bb.note("[deps-resolver] No IPK dependency from %s"%pkg)
            continue

        bb.note("[deps-resolver] IPK dependency from %s"%pkg)
        ldeps,lrdeps = read_ipk_depends(d, pkg_path)
        for dep in ldeps:
            if dep == " " or  dep == "\n":
                continue
            dep = dep.strip()
            (ipk_mode, version_check, arch_check) = check_deps_ipk_mode(d, dep)
            if dep not in layer_pkgs and ipk_mode :
                d.appendVar("INSTALL_DEPENDS", ",%s" % dep)
        for dep in lrdeps:
            if dep == " " or  dep == "\n":
                continue
            dep = dep.strip()
            rdeps_ipk = (d.getVar('INSTALL_RDEPENDS:%s'%pkg_pn) or "").split(",")
            (ipk_mode, version_check, arch_check) = check_deps_ipk_mode(d, dep)
            if dep not in rdeps_ipk and ipk_mode :
                d.appendVar("INSTALL_RDEPENDS:%s"%pkg_pn, ",%s" % dep)
}

def staging_copy_ipk_file(c, dest, seendirs):
    import errno

    if not os.path.exists(c):
        return dest

    destdir = os.path.dirname(dest)
    if destdir not in seendirs:
        bb.utils.mkdirhier(destdir)
        seendirs.add(destdir)
    if os.path.islink(c):
        linkto = os.readlink(c)
        if os.path.lexists(dest):
            if not os.path.islink(dest):
                raise OSError(errno.EEXIST, "Link %s already exists as a file" % dest, dest)
            if os.readlink(dest) == linkto:
                return dest
            raise OSError(errno.EEXIST, "Link %s already exists to a different location? (%s vs %s)" % (dest, os.readlink(dest), linkto), dest)
        os.symlink(linkto, dest)
    else:
        try:
            if not os.path.exists(dest):
                os.link(c, dest)
        except OSError as err:
            if err.errno == errno.EXDEV:
                bb.utils.copyfile(c, dest)
            else:
                raise
    return dest

def staging_copy_ipk_dir(c, dest, seendirs):
    if os.path.exists(c):
        if dest not in seendirs:
           bb.utils.mkdirhier(dest)
           seendirs.add(dest)

def get_provider(d,pkg, archs):
    provides = ""
    feed_info_dir = d.getVar("FEED_INFO_DIR")
    for arch in archs:
        src_path = os.path.join(feed_info_dir, arch)
        if os.path.exists(src_path + "/package/%s"%pkg):
            provides = pkg
            break
        elif os.path.exists(src_path + "/rprovides/%s"%pkg):
            target = os.readlink(src_path + "/rprovides/%s"%pkg)
            provides = os.path.basename(target)
            break
        else:
            prefix = d.getVar('MLPREFIX') or ""
            if prefix and pkg.startswith(prefix):
                ml_pkg = "%slib%s"%(prefix,pkg[len(prefix):])
            else:
                ml_pkg = "lib"+pkg
            if os.path.exists(src_path + "/package/%s"%ml_pkg):
                provides = ml_pkg
                break

    if provides and pkg != provides:
        bb.note("[deps-resolver] PKG - %s , PROVIDER - %s "%(pkg,provides))
    return provides

# Install the dev ipks to the component sysroot
python do_install_ipk_recipe_sysroot () {
    import shutil
    import re
    ildeps = []
    seendirs = set()
    counts, devpkgcount = ({} for i in range(2))

    pkg_pn = d.getVar('PN')
    staging_bin_pkgs = d.getVar('SYSROOT_DIRS_BIN_REQUIRED').split(" ")
    layer_sysroot = d.getVar("SYSROOT_IPK")
    recipe_sysroot = d.getVar("RECIPE_SYSROOT")
    lpkgopkg_path = os.path.join(layer_sysroot,"var/lib/opkg")
    lpkginfo_path = os.path.join(lpkgopkg_path,"info")
    pkgdata_path = d.getVar("DEPS_IPK_DIR")
    for walkroot, dirs, files in os.walk(lpkgopkg_path):
        for file in files:
            srcfile = os.path.join(walkroot, file)
            if not srcfile.endswith(".lock"):
                dstfile = srcfile.replace(layer_sysroot, recipe_sysroot)
                staging_copy_ipk_file(srcfile,dstfile,seendirs)
        for dir in dirs:
            srcdir = os.path.join(walkroot, dir)
            dstdir = srcdir.replace(layer_sysroot, recipe_sysroot)
            staging_copy_ipk_dir(srcdir,dstdir,seendirs)

    ldeps = (d.getVar('INSTALL_DEPENDS') or "").split(",")
    bb.note("[deps-resolver] Updated with indirect IPK depends list : %s " % ldeps)
    pkgs = d.getVar('PACKAGES').split(" ")
    for pkg in pkgs:
        ipk_rdeps = d.getVar('INSTALL_RDEPENDS:' + pkg)
        if ipk_rdeps is not None:
            ldeps.extend(ipk_rdeps.split(","))
    bb.note("[deps-resolver] Updated with indirect depends + rdepends list : %s " % ldeps)
    archs = []
    for line in (d.getVar('IPK_FEED_URIS') or "").split():
        feed = re.match(r"^[ \t]*(.*)##([^ \t]*)[ \t]*$", line)
        if feed is not None:
            archs.append(feed.group(1))

    dev_list = ["-dev","-staticdev"]
    for ldep in ldeps:
        if ldep == " " or ldep == "":
            continue
        for dev in dev_list:
            pkg = ldep.strip().split(" ")[0]
            pkg = pkg+dev if get_provider(d,pkg+dev,archs) else pkg
            if pkg in ildeps:
                continue
            ildeps.append(pkg)

            devpkgcount[pkg] = False
            while True:
                ldeps = create_deps_list_from_ipk(d,lpkginfo_path,".control",devpkgcount,archs)
                if ldeps:
                    for dep in ldeps:
                        dep = dep.strip().split(" ")[0]
                        if dep not in devpkgcount:
                            devpkgcount[dep] = False
                        if dep in ildeps:
                            continue
                        ildeps.append(dep)
                else :
                    break
        recipe_info = ""
        feed_info_dir = d.getVar("FEED_INFO_DIR")
        for arch in archs:
            pkg_path = feed_info_dir+"%s/"%arch
            if os.path.exists(pkg_path + "source/%s.customised"%ldep):
                recipe_info = pkg_path + "source/%s.customised"%ldep
                break;
        if recipe_info:
            with open(recipe_info, 'r') as file:
                lines = file.readlines()
            for line in lines:
                check_true = False
                if line[:-1].endswith("-dev"):
                    if line[:-1] in ildeps:
                        continue
                    check_true = True
                    ildeps.append(line[:-1])
                if line[:-1].endswith("-staticdev"):
                    if line[:-1] in ildeps:
                        continue
                    ildeps.append(line[:-1])
                if check_true:
                    if line[:-1] not in devpkgcount:
                        devpkgcount[line[:-1]] = False
                        while True:
                            ldeps = create_deps_list_from_ipk(d,lpkginfo_path,".control",devpkgcount,archs)
                            if ldeps:
                                for dep in ldeps:
                                    dep = dep.strip().split(" ")[0]
                                    if dep not in devpkgcount:
                                        devpkgcount[dep] = False
                                    ildeps.append(dep)
                            else :
                                break

    for pkg in ildeps:
        if pkg == " " or pkg == "":
            continue
           
        pkg = pkg.strip().split(" ")[0]
        if pkg in counts:
            continue
        else:
            counts[pkg] = 0
        pkg = get_provider(d,pkg,archs)
        lpkglist_path = os.path.join(lpkginfo_path,pkg+".list")
        if os.path.exists(lpkglist_path):
            if not os.path.exists(pkgdata_path):
                bb.utils.mkdirhier(pkgdata_path)
            packagedfile = os.path.join(pkgdata_path,'%s.ldep' % pkg_pn)
            open(packagedfile, 'w').close()

            bb.note("[deps-resolver] Added PKG - %s - files to the recipe sysroot"%pkg)
            with open(lpkglist_path,"r") as fd:
                devlines = fd.readlines()

            d.setVar('SYSROOT_REQ_DIRS',d.getVar("STACK_LAYER_SYSROOT_DIRS"))
            for ipkdeps in staging_bin_pkgs:
                if pkg == ipkdeps:
                    d.appendVar('SYSROOT_REQ_DIRS',d.getVar("bindir"))
                    break
            for l in devlines:
                file = l.split("\t")[0]
                perm = l.split("\t")[1]
                for dir in d.getVar('SYSROOT_REQ_DIRS').strip().split(" "):
                    if dir == " ":
                        continue
                    if file.startswith(dir):
                        if str(perm)[1] == "4":
                            bb.note("[deps-resolver] pkg : %s - creating dir : %s in recipe sysroot"%(pkg,dir))
                            staging_copy_ipk_dir(layer_sysroot+file,recipe_sysroot+file,seendirs)
                        else:
                            bb.note("[deps-resolver] pkg : %s - copying file : %s in recipe sysroot"%(pkg,file))
                            staging_copy_ipk_file(layer_sysroot+file,recipe_sysroot+file,seendirs)
                        break

            if pkg == f"{d.getVar('MLPREFIX')}gobject-introspection":
                bb.note(" [deps-resolver] gobject-introspection requires cross compilation support")
                g_ir_cc_support(d,recipe_sysroot,pkg_pn)
            if bb.data.inherits_class('useradd', d):
                p =  d.getVar('SYSROOT_IPK')+"/var/lib/opkg/info/base-passwd.preinst"
                if os.path.exists(p):
                    bb.note(" [deps-resolver] base-passwd files requires for useradd support")
                    import subprocess
                    os.environ['D'] = d.getVar('RECIPE_SYSROOT')
                    subprocess.check_output(p, shell=True, stderr=subprocess.STDOUT)
        else:
            bb.note("[deps-resolver] Skipped PKG - %s - from recipe sysroot"%pkg)
}

python do_kernel_devel_create(){
    import shutil
    kernel_src = d.getVar('SYSROOT_IPK')+"/kernel-source"
    kernel_artifacts = d.getVar('SYSROOT_IPK')+"/kernel-build"
    staging_shared_dir = d.getVar("STAGING_SHARED_DIR")
    if os.path.exists(staging_shared_dir):
        shutil.rmtree(staging_shared_dir)
    bb.utils.mkdirhier(staging_shared_dir)
    if os.path.exists(kernel_src):
        os.symlink(kernel_src, d.getVar('STAGING_KERNEL_DIR'))
    else:
        bb.fatal("kernel devel is missing please check")
    if os.path.exists(kernel_artifacts):
        os.symlink(kernel_artifacts, d.getVar('STAGING_KERNEL_BUILDDIR'))
}
do_kernel_devel_create[depends] += "${MLPREFIX}staging-ipk-pkgs:do_populate_ipk_sysroot"

python do_ipk_download(){
    import subprocess
    import shutil
    import re
    arch = d.getVar('PACKAGE_ARCH')
    deploy_dir = d.getVar("DEPLOY_DIR_IPK")
    ipk_deploy_path = os.path.join(deploy_dir, arch)
    if not os.path.exists(ipk_deploy_path):
        bb.utils.mkdirhier(ipk_deploy_path)
    ipk_list = get_ipk_list(d,arch)

    download_dir = d.getVar("IPK_CACHE_DIR", True)
    if not os.path.exists(download_dir):
        bb.utils.mkdirhier(download_dir)
    server_path = ""
    for line in (d.getVar('IPK_FEED_URIS') or "").split():
        feed = re.match(r"^[ \t]*(.*)##([^ \t]*)[ \t]*$", line)
        if feed is not None:
            arch_name = feed.group(1)
            arch_uri = feed.group(2)
            if arch == arch_name:
                server_path = arch_uri

    if server_path:
        for ipk in ipk_list:
            ipk_dl_path = os.path.join(download_dir,ipk)
            if not os.path.exists(ipk_dl_path):
                if server_path.startswith("file:"):
                    shutil.copy(server_path[5:]+"/"+ipk, download_dir)
                else:
                    bb.process.run("wget %s --directory-prefix=%s"%(server_path+"/"+ipk, download_dir), stderr=subprocess.STDOUT)
            if os.path.exists(ipk_deploy_path+"/%s"%ipk):
                os.unlink(ipk_deploy_path+"/%s"%ipk)
            os.link(ipk_dl_path, ipk_deploy_path+"/%s"%ipk)
}
def disable_build_tasks(d, task_name, arch):
    pn = d.getVar('PN', True)
    task_stack = []
    task_stack.append(task_name)
    processed_tasks = []
    while task_stack:
        cur_task = task_stack.pop()
        deps = d.getVarFlag(cur_task, 'deps', False)
        if cur_task != "do_build":
            d.setVarFlag(cur_task,'noexec',"1")
        processed_tasks.append(cur_task)
        if deps != None:
            for dep in deps:
                if not (dep in task_stack or dep in processed_tasks):
                    task_stack.append(dep)
    d.setVarFlag('do_package_write_ipk','noexec',"1")
    d.setVarFlag('do_packagedata','noexec',"1")
    d.setVarFlag('do_deploy','noexec',"1")
    manifest_path = d.getVar("SSTATE_MANIFESTS", True)
    if not os.path.exists(manifest_path):
        bb.utils.mkdirhier(manifest_path)

    manifest_name = d.getVar("SSTATE_MANFILEPREFIX", True) + ".populate_sysroot"
    open(manifest_name, 'w').close()
    manifest_name = d.getVar("SSTATE_MANFILEPREFIX", True) + ".packagedata"
    open(manifest_name, 'w').close()
    manifest_name = d.getVar("SSTATE_MANFILEPREFIX", True) + ".package_write_ipk"
    open(manifest_name, 'w').close()
    ipk_list = get_ipk_list(d,arch)
    if ipk_list and arch in (d.getVar("STACK_LAYER_EXTENSION") or "").split(" "):
        deploy_dir = d.getVar("DEPLOY_DIR_IPK")
        pkg_path_ipk = os.path.join(deploy_dir, arch)
        with open(manifest_name, "w") as fp:
            for ipk in ipk_list:
                fp.write(os.path.join(pkg_path_ipk, ipk) + "\n")
    bb.build.addtask("do_ipk_download", "do_build", None, d)
    if arch in (d.getVar("STACK_LAYER_EXTENSION") or "").split(" ") and bb.data.inherits_class('kernel', d):
        bb.build.addtask("do_kernel_devel_create", "do_build", None, d)

# Get the list of IPKs generated from a package
def get_ipk_list(d, pkg_arch):
    import glob
    import shutil
    ipk_list = []
    pn = d.getVar("PN")
    pkg_arch = d.getVar("PACKAGE_ARCH")
    version = "%s-%s" % (d.getVar('PV'), d.getVar('PR'))
    version = version.replace("AUTOINC","0")
    pkg_ver = "%s:%s" % (d.getVar('PE'), version) if d.getVar('PE') else version
    feed_info_dir = d.getVar("FEED_INFO_DIR")
    src_path = os.path.join(feed_info_dir, pkg_arch)
    recipe_info = glob.glob(src_path + "/source/%s_*"%(pn))
    if recipe_info:
        recipe_info = recipe_info[0]
        if os.path.exists(recipe_info):
            with open(recipe_info, 'r') as file:
                pkgs = file.readlines()
            for pkg in pkgs:
                pkg_ipk = "%s_%s_%s.ipk"%(pkg[:-1],pkg_ver,pkg_arch)
                ipk_list.append(pkg_ipk)
    return ipk_list

def get_target_list(d):
    import bb.main
    feed_info_dir = d.getVar("FEED_INFO_DIR")
    target_list = os.path.join(feed_info_dir,"target/pkg_list")
    if not os.path.exists(target_list):
        options, targets = bb.main.BitBakeConfigParameters.parseCommandLine(None)
        # Above fn return non bitbake targets in kirkstone
        if "decafbad" in targets:
            options, targets = bb.main.BitBakeConfigParameters.parseCommandLine(d, d.getVar("BB_CMDLINE"))
        if not os.path.exists(feed_info_dir+"target/"):
            bb.utils.mkdirhier(feed_info_dir+"target/")
        with open(target_list, 'w') as file:
            for target in targets:
                file.write("%s\n"%target)

    with open(target_list,"r") as fd:
        targets = fd.readlines()

    return targets

def check_targets(d, pkg):
    is_target = False
    targets = get_target_list(d)
    for target in targets:
        if pkg == target[:-1]:
            is_target = True
            break
    return is_target

python () {
    pn = d.getVar('PN')
    pe = d.getVar('PE')
    pv = d.getVar('PV')
    pr = d.getVar('PR')
    arch = d.getVar('PACKAGE_ARCH')
    version = "%s:%s-%s"%(pe,pv,pr) if pe else "%s-%s"%(pv,pr)
    feed_info_dir = d.getVar("FEED_INFO_DIR")

    if d.getVar('IPK_MODE') == "1":
        raise bb.parse.SkipRecipe("SKIPPED %s"%pn)

    pref_version = d.getVar("PREFERRED_VERSION_%s"%pn)
    pv_overrides = d.getVar("PV_pn-%s"%pn)
    version = version.replace("AUTOINC","0")

    if not bb.data.inherits_class('native', d):
        # Skipping unrequired version of recipes
        if d.getVar("STACK_LAYER_EXTENSION") and pref_version and not pv_overrides and not is_excluded_pkg(d, pn):
            pref_version = pref_version.split("%")[0]
            if pref_version not in version :
                raise bb.parse.SkipRecipe("Skipped different version of recipe %s"%pn)

        if arch in (d.getVar("STACK_LAYER_EXTENSION") or "").split(" "):
            d.appendVarFlag('do_package_write_ipk', 'prefuncs', ' do_clean_deploy')
            d.appendVarFlag('do_package_write_ipk_setscene', 'prefuncs', ' do_clean_deploy')
            d.appendVarFlag('do_deploy', 'prefuncs', ' do_clean_deploy_images')
            d.appendVarFlag('do_deploy_setscene', 'prefuncs', ' do_clean_deploy_images')

        if d.getVar("STACK_LAYER_EXTENSION") and check_targets(d, pn):
            d.appendVarFlag('do_build', 'recrdeptask', " do_ipk_download")

        if d.getVar("STACK_LAYER_EXTENSION") and bb.data.inherits_class('image', d):
            d.appendVarFlag('do_rootfs', 'recrdeptask', " do_ipk_download")

        if d.getVar("STACK_LAYER_EXTENSION") and bb.data.inherits_class('linux-kernel-base', d):
            d.appendVarFlag('do_configure', 'recrdeptask', " do_kernel_devel_create")
            d.appendVarFlag('do_kernel_devel_create', 'recrdeptask', " do_populate_ipk_sysroot")

        (ipk_mode, version_check, arch_check) = check_deps_ipk_mode(d, pn, False, version)
        if ipk_mode and not check_targets(d, pn):
            skipped_pkg_dir = os.path.join(feed_info_dir,"%s/skipped/"%arch)
            if not os.path.exists(skipped_pkg_dir):
                bb.utils.mkdirhier(skipped_pkg_dir)

            open(skipped_pkg_dir+pn, 'w').close()
            disable_build_tasks(d,'do_build', arch)
        else:
            if arch in (d.getVar("STACK_LAYER_EXTENSION") or "").split(" ") and bb.data.inherits_class('kernel', d):
                d.appendVarFlag('do_packagedata', 'prefuncs', ' do_clean_pkgdata')
                d.appendVarFlag('do_packagedata_setscene', 'prefuncs', ' do_clean_pkgdata')
            if arch in (d.getVar("STACK_LAYER_EXTENSION") or "").split(" "):
                if not os.path.exists(feed_info_dir+"src_mode/"):
                    bb.utils.mkdirhier(feed_info_dir+"src_mode/")
                open(feed_info_dir+"src_mode/%s"%pn, 'w').close()
                if version_check and not check_targets(d, pn):
                    open(feed_info_dir+"src_mode/%s.major"%pn, 'w').close()
            d.appendVar("DEPENDS", " opkg-native ")
            bb.build.addtask('do_install_ipk_recipe_sysroot','do_configure','do_prepare_recipe_sysroot',d)
            d.appendVarFlag('do_install_ipk_recipe_sysroot', 'prefuncs', ' update_ipk_deps')
            # Moving the prepare_recipe_sysroot post function to run after install_ipk_recipe_sysroot
            postfuncs = (d.getVarFlag('do_prepare_recipe_sysroot', 'postfuncs') or "").split()
            if postfuncs:
                for fn in postfuncs:
                    d.appendVarFlag('do_install_ipk_recipe_sysroot', 'postfuncs', " %s"%fn)
                d.setVarFlag('do_prepare_recipe_sysroot', 'postfuncs', "")
}

python do_clean_pkgdata(){
    kernel_abi_ver_file = oe.path.join(d.getVar('PKGDATA_DIR'), "kernel-depmod",
                                           'kernel-abiversion')
    if os.path.exists(kernel_abi_ver_file):
        os.remove(kernel_abi_ver_file)
}

python do_clean_deploy(){
    deploy_dir = d.getVar("DEPLOY_DIR_IPK")
    pkg_arch = d.getVar("PACKAGE_ARCH")
    pkg_path_ipk = os.path.join(deploy_dir, pkg_arch)
    ipk_list = get_ipk_list(d, pkg_arch)
    if ipk_list:
        for ipk in ipk_list:
            if os.path.exists(pkg_path_ipk + "/%s"%ipk):
                os.unlink(pkg_path_ipk + "/%s"%ipk)
}

python do_clean_deploy_images(){
    import glob
    files = []
    packages = d.getVar("PACKAGES").split()
    ipk_sysroot = d.getVar('SYSROOT_IPK')
    for pkg in packages:
        src_list = glob.glob(ipk_sysroot + "/var/lib/opkg/info/%s*.list"%(pkg))
        if src_list:
            for p in src_list :
                if os.path.exists(p):
                    with open(p,"r") as fd:
                        lines = fd.readlines()
                    for line in lines:
                        line = (line.split("\t")[0]).split("/")[-1]
                        if line not in files:
                            files.append(line)
    bb.note("[deps-resolver] Removing %s"%files)
    if files:
        img_deploy_dir = d.getVar("DEPLOY_DIR_IMAGE")
        for file in files:
            file_path = os.path.join(img_deploy_dir,file)
            if os.path.exists(file_path):
                os.remove(file_path)
}

def create_ipk_deps_pkgdata(e,pn):

    ipk_pkg_dir = e.data.getVar("DEPS_IPK_DIR")
    if not os.path.exists(ipk_pkg_dir):
        bb.utils.mkdirhier(ipk_pkg_dir)

    if bb.data.inherits_class('image', d):
        pkgs = pn.split(" ")
    else:
        pkgs = e.data.getVar('PACKAGES').split(" ")

    for pkg in pkgs:
        if pkg == " " or pkg == "":
            continue
        lines = ""
        depslist, rdepslist = ([] for i in range(2))
        if e.data.getVar('INSTALL_RDEPENDS:%s'%pkg) is not None:
            for rdep in e.data.getVar("INSTALL_RDEPENDS:%s"%pkg).split(","):
                if rdep not in rdepslist:
                    rdepslist.append(rdep)
            if rdepslist:
                lines += "Rdepends: " + ', '.join(rdepslist)+"\n"
        if pkg == pn and e.data.getVar('INSTALL_DEPENDS') is not None :
            for dep in e.data.getVar("INSTALL_DEPENDS").split(","):
                if dep not in depslist:
                    depslist.append(dep)
            if depslist:
                lines += "Depends: " + ', '.join(depslist)+"\n"
        if lines == "":
            continue
        pkg_path = os.path.join(ipk_pkg_dir,pkg)
        le = bb.utils.lockfile(ipk_pkg_dir + "/%s.lock"%pkg)
        with open(pkg_path, "w") as f:
            f.writelines(lines)
        bb.utils.unlockfile(le)

def get_base_pkg_name(pkg_name):
    tmp_pkg_name = pkg_name
    if pkg_name.endswith('-dev') or pkg_name.endswith('-dbg') or pkg_name.endswith('-src') or pkg_name.endswith('-bin'):
        tmp_pkg_name = pkg_name[:-4]
    if pkg_name.endswith('-staticdev'):
        tmp_pkg_name = pkg_name[:-10]
    if pkg_name.endswith('-locale'):
        tmp_pkg_name = pkg_name[:-7]
    return tmp_pkg_name

# Handle multiple conditions to check the IPK consumption. 
# Once we start consuming all packages as IPK except those in the 
# same stack layer, we can optimize this condition check
def check_deps_ipk_mode(d, dep_bpkg, rrecommends = False, version = None):
    import re
    import glob
    version_mismatch = True
    same_arch = False
    pkg_arch = d.getVar("PACKAGE_ARCH")
    ipkmode = False

    # Check dep package is in IPK mode
    ipkmode = True if d.getVar('IPK_MODE:pn-%s' %dep_bpkg) == "1" else False
    if ipkmode:
        return (ipkmode, version_mismatch, same_arch)

    if is_excluded_pkg(d, dep_bpkg):
        return (ipkmode, version_mismatch, same_arch)

    feed_info_dir = d.getVar("FEED_INFO_DIR")
    archs = []
    oss_ipk_mode = True if "1" == d.getVar('OSS_IPK_MODE') or d.getVar("STACK_LAYER_EXTENSION") else False
    for line in (d.getVar('IPK_FEED_URIS') or "").split():
        feed = re.match(r"^[ \t]*(.*)##([^ \t]*)[ \t]*$", line)
        if feed is not None:
            if not oss_ipk_mode:
                if "oss" in feed.group(1):
                    continue
            archs.append(feed.group(1))

    for arch in archs:
        pkg_path = feed_info_dir+"%s/"%arch
        if version:
            src_path = pkg_path + "source/%s_%s"%(dep_bpkg,version)
            if os.path.exists(src_path):
                ipkmode = True
                break
            # Check only the major version number
            src_list = glob.glob(pkg_path + "source/%s_%s*"%(dep_bpkg,version.split(".")[0]))
            if src_list:
                src_path = src_list[0]
                if os.path.exists(src_path):
                    # Build from source
                    version_mismatch = False
                    break
        else:
            src_path = pkg_path + "source/%s"%dep_bpkg
            src_list = glob.glob(pkg_path + "source/%s_*"%dep_bpkg)
            if src_list:
               src_path = src_list[0]

            if os.path.exists(src_path) or os.path.exists(pkg_path + "rprovides/%s"%dep_bpkg) or os.path.exists(pkg_path + "package/%s"%dep_bpkg) or os.path.exists(pkg_path + "package/lib%s"%dep_bpkg):
                if arch in (d.getVar("STACK_LAYER_EXTENSION") or "").split(" "):
                    same_arch = True
                else:
                    ipkmode = True
                break
            if rrecommends and dep_bpkg.startswith("kernel-module") and os.path.exists(pkg_path + "package/kernel"):
                ipkmode = True
                break
    return (ipkmode, version_mismatch, same_arch)

def get_inter_layer_pkgs(e, pkg, deps, rrecommends = False, skip_depends=False):
    pkgrdeps, ipkrdeps = ([] for i in range(2))
    import re
    pattern = r'(\S+)(\s*\([^\)]*\))?'
    matches = re.findall(pattern, deps)
    for match in matches:
        dep = match[0].strip()
        dep_ver = match[1].strip() if len(match) > 1 and match[1] else None
        dep_bpkg = get_base_pkg_name(dep)

        if dep.endswith("-native") or dep_bpkg == get_base_pkg_name(pkg):
            if dep_ver:
                pkgrdeps.append(dep +" " + dep_ver)
            else:
                pkgrdeps.append(dep)
            continue
        preferred_provider = e.data.getVar('PREFERRED_PROVIDER_%s' % dep_bpkg, True)
        if preferred_provider is not None:
            (ipk_mode, version_check, arch_check) = check_deps_ipk_mode(e.data, preferred_provider, rrecommends, None)
            if ipk_mode:
                dep = dep.replace(dep_bpkg,preferred_provider)
                dep_bpkg = preferred_provider
                dep_ver = None
        else:
            (ipk_mode, version_check, arch_check) = check_deps_ipk_mode(e.data, dep_bpkg, rrecommends, None)

        if ipk_mode or arch_check:
            if dep_ver:
                ipkrdeps.append(dep +" " + dep_ver)
            else:
                ipkrdeps.append(dep)
            if not arch_check:
                continue

        if preferred_provider == "noop":
            dep = preferred_provider
        if skip_depends:
            if arch_check:
                if dep_ver:
                    pkgrdeps.append(dep +" " + dep_ver)
                else:
                    pkgrdeps.append(dep)
        else:
            if dep_ver:
                pkgrdeps.append(dep +" " + dep_ver)
            else:
                pkgrdeps.append(dep)

    return (ipkrdeps,pkgrdeps)


# Create metadata for the direct dependent ipk packages.
def update_dep_pkgs(e):
    src_pkgs, ipk_pkgs = ([] for i in range(2))
    skip_depends = False

    pkg_pn = e.data.getVar('PN',  True) 
    arch = e.data.getVar('PACKAGE_ARCH',  True)
    have_ipk_deps = False

    pe = d.getVar('PE')
    pv = d.getVar('PV')
    pr = d.getVar('PR')
    version = "%s:%s-%s"%(pe,pv,pr) if pe else "%s-%s"%(pv,pr)
    feed_info_dir = d.getVar("FEED_INFO_DIR")
    version = version.replace("AUTOINC","0")
    (ipk_mode, version_check, arch_check) = check_deps_ipk_mode(d, pkg_pn, False, version)
    if ipk_mode and not check_targets(e.data, pkg_pn) :
        skip_depends = True

    # Handle DEPENDS which needs recipe to process
    deps = (e.data.getVar('DEPENDS') or "").strip()
    if deps:
        ipk_pkgs,src_pkgs = get_inter_layer_pkgs(e, pkg_pn, deps, False, skip_depends)
        e.data.setVar("DEPENDS", ' '.join(src_pkgs))
        if ipk_pkgs:
            have_ipk_deps = True
            e.data.setVar("INSTALL_DEPENDS", ','.join(ipk_pkgs))
    # Handle RDEPEND::<pkgs> which needs recipe to process
    if e.data.getVar('PACKAGES', True) is not None:
        pkgs = e.data.getVar('PACKAGES').split(" ")
        for pkg in pkgs:
            rdeps = (e.data.getVar('RDEPENDS:%s'%pkg) or "").strip()
            if rdeps:
                ipk_pkgs,src_pkgs = get_inter_layer_pkgs(e, pkg, rdeps, False, skip_depends)
                e.data.setVar("RDEPENDS:%s"%pkg, ' '.join(src_pkgs))
                if ipk_pkgs:
                    have_ipk_deps = True
                    e.data.setVar("INSTALL_RDEPENDS:%s"%pkg, ','.join(ipk_pkgs))

            rdeps = (e.data.getVar('RRECOMMENDS:%s'%pkg) or "").strip()
            if rdeps:
                ipk_pkgs,src_pkgs = get_inter_layer_pkgs(e, pkg, rdeps, True, skip_depends)
                e.data.setVar("RRECOMMENDS:%s"%pkg, ' '.join(src_pkgs))
                if ipk_pkgs:
                    have_ipk_deps = True
                    e.data.setVar("INSTALL_RRECOMMENDS:%s"%pkg, ','.join(ipk_pkgs))

    # Handle IMAGE_INSTALL which needs recipe to process
    if bb.data.inherits_class('image', d):

        ipk_pkg_inst = []
        pkgs_inst = (e.data.getVar('IMAGE_INSTALL') or "").strip()
        if pkgs_inst:
            ipk_pkgs,src_pkgs = get_inter_layer_pkgs(e, pkg_pn, pkgs_inst, False, skip_depends)
            e.data.setVar("IMAGE_INSTALL", ' '.join(src_pkgs))
            if ipk_pkgs:
                e.data.setVar('IPK_IMAGE_INSTALL',' '.join(ipk_pkgs))
        pkgs_inst = (e.data.getVar('RDEPENDS') or "").strip()
        if pkgs_inst:
            ipk_pkgs,src_pkgs = get_inter_layer_pkgs(e, pkg_pn, pkgs_inst, False, skip_depends)
            e.data.setVar("RDEPENDS", ' '.join(src_pkgs))
            if ipk_pkgs:
                e.data.setVar('IPK_RDEPENDS',' '.join(ipk_pkgs))
        pkgs_inst = (e.data.getVar('ROOTFS_BOOTSTRAP_INSTALL') or "").strip()
        if pkgs_inst:
            ipk_pkgs,src_pkgs = get_inter_layer_pkgs(e, pkg_pn, pkgs_inst, False, skip_depends)
            e.data.setVar("ROOTFS_BOOTSTRAP_INSTALL", ' '.join(src_pkgs))
            if ipk_pkgs:
                e.data.setVar('IPK_ROOTFS_BOOTSTRAP_INSTALL',' '.join(ipk_pkgs))
        pkgs_inst = (e.data.getVar('FEATURE_INSTALL') or "").strip()
        if pkgs_inst:
            ipk_pkgs,src_pkgs = get_inter_layer_pkgs(e, pkg_pn, pkgs_inst, False, skip_depends)
            e.data.setVar("FEATURE_INSTALL", ' '.join(src_pkgs))
            if ipk_pkgs:
                e.data.setVar('IPK_FEATURE_INSTALL',' '.join(ipk_pkgs))

    #Insert do_update_rdeps_ipk after read_shlibdeps pkg function.
    pkgfns = e.data.getVar('PACKAGEFUNCS')
    if pkgfns and not skip_depends:
        e.data.setVar('PACKAGEFUNCS',"")
        for f in (pkgfns or '').split():
            if f == "emit_pkgdata":
                e.data.appendVar('PACKAGEFUNCS'," do_update_auto_pr")
            e.data.appendVar('PACKAGEFUNCS'," %s"%f)
            if f == "read_shlibdeps":
                e.data.appendVar('PACKAGEFUNCS'," do_update_rdeps_ipk")

    if bb.data.inherits_class('multilib_global', d) and not d.getVar('MLPREFIX'):
        have_ipk_deps = False

    if arch in (d.getVar("STACK_LAYER_EXTENSION") or "").split(" "):
        if have_ipk_deps:
            e.data.appendVar("DEPENDS", " ${MLPREFIX}staging-ipk-pkgs")

    if have_ipk_deps:
        e.data.appendVar("DEPENDS", " ${MLPREFIX}staging-ipk-pkgs")
        create_ipk_deps_pkgdata(e,pkg_pn)
        have_ipk_deps = False

# Determine which IPK provides the runtime dependency - sharedlib, pkgconfig.
def get_rdeps_provider_ipk(d, rdep):
    import re
    ipk_pkg = " "

    reciepe_sysroot = d.getVar("RECIPE_SYSROOT")
    opkg_cmd = bb.utils.which(os.getenv('PATH'), "opkg")

    if "/" in rdep:
        rdep = rdep.split("/")[-1]
    if rdep == "bash":
        rdep = rdep + ".bash"

    opkg_conf = d.getVar("IPKGCONF_LAYERING")
    if not os.path.exists(opkg_conf):
        import oe.sls_utils
        oe.sls_utils.sls_opkg_conf (d, opkg_conf)

    info_file_path = os.path.join(d.getVar("WORKDIR", True), "temp/ipktemp/")
    if not os.path.exists(info_file_path):
        bb.utils.mkdirhier(os.path.dirname(info_file_path))

    opkg_args = "-f %s -t %s -o %s " % (opkg_conf, info_file_path ,reciepe_sysroot)

    cmd = '%s %s search "'"*/%s"'"' % (opkg_cmd, opkg_args,rdep.strip()) + " 2>/dev/null"
    fd = os.popen(cmd)
    lines = fd.readlines()
    fd.close()
    for line in lines:
        pkg = line.split(" - ")[0]
        ver = line.split(" - ")[1]
        ver = ver.split("-")[0]
        ipk_pkg += pkg + " (>=" + ver + ") "

    if ipk_pkg == " ":
        bb.note("[deps-resolver] rdep - %s - not available in IPK pkgs "%rdep)
    else:
        bb.note("[deps-resolver] rdep - %s - available in IPK pkg %s"%(rdep, ipk_pkg))
    return ipk_pkg


# Function returns the ipk pkg name which contains the run-time dependent shared lib.
# This data is read from the metadata generated while executing the package_do_shlibs (do_package).
def update_rdeps_shlib(d,pkg):
    ipks = []
    # SHLIBSKIPLIST should set with missing sahred libs in package_do_shlibs
    if d.getVar('SHLIBSKIPLIST_%s'%pkg):
        pkg_dir = d.getVar("IPK_PKGDATA_RUNTIME_DIR")
        if not os.path.exists(pkg_dir):
            bb.utils.mkdirhier(pkg_dir)
        pkg_path = os.path.join(pkg_dir, pkg)
        with open(pkg_path, 'a') as file:
            shlib_skip = d.getVar('SHLIBSKIPLIST_%s'%pkg).split(" ")
            for shlib in shlib_skip:
                ipk = get_rdeps_provider_ipk(d,shlib)
                if ipk not in ipks and ipk != " ":
                    ipks.append(ipk)
                if ipk != " ":
                    file.write("%s\n"%shlib)
    return ipks

def update_rdeps_pkgconfig(d,pkg):
    ipks = []
    # PKGCONFIGSKIPLIST should set with missing pkgconfig modules in package_do_pkgconfig
    if d.getVar('PKGCONFIGSKIPLIST_%s'%pkg):
        pkgconfig_skip = d.getVar('PKGCONFIGSKIPLIST_%s'%pkg).split(" ")
        for pkgconfig in pkgconfig_skip:
            ipk = get_rdeps_provider_ipk(d, pkgconfig+".pc")
            if ipk not in ipks and ipk != " ":
                ipks.append(ipk)
    return ipks

# Fix Version issue with AUTOINC
python do_update_auto_pr () {
    # Adjust dependencies that are statically set with EXTENDPKGV
    vars = ["RDEPENDS","RRECOMMENDS"]
    packages = d.getVar('PACKAGES').split()
    for var in vars:
        for pkg in packages:
            val = d.getVar("%s:%s"%(var,pkg))
            if val and 'AUTOINC' in val and "PRSERV_PV_AUTOINC" not in val:
                d.setVar("%s:%s"%(var,pkg), val.replace("AUTOINC", "${PRSERV_PV_AUTOINC}"))
}

# Set RDEPENDS with runtime dependent ipk pkgs
python do_update_rdeps_ipk () {
    packages = d.getVar('PACKAGES').split(" ")
    pkgdata_path = d.getVar("DEPS_IPK_DIR")

    # "staging-ipk-pkgs" interface package should be removed from DEPENDS.
    # Otherwie it will be added to the RRECOMMENDS for the -dev ipk
    depends = []
    for dep in bb.utils.explode_deps(d.getVar('DEPENDS') or ""):
        if "staging-ipk-pkgs" not in dep and dep not in depends:
            depends.append(dep)
    for dep in (d.getVar("INSTALL_DEPENDS") or "").split(","):
        if dep not in depends:
            depends.append(dep)
    d.setVar('DEPENDS',' '.join(depends))

    for pkg in packages:
        lrdeps_check = False
        rdepends = []

        pkg_path = os.path.join(pkgdata_path,pkg)
        # Read runtime dependent ipk pkgs list from RDEPENDS meta data
        ldeps,lrdeps = read_ipk_depends(d,pkg_path)
        for rdeps in lrdeps:
            if rdeps == "" or rdeps == " ":
                continue
            if rdeps not in (d.getVar('RDEPENDS:' + pkg) or "").split(" "):
                lrdeps_check = True
                if rdeps not in rdepends:
                    rdepends.append(rdeps)
            bb.note("[deps-resolver] pkg %s has runtime dependency [from RDEPENDS] with IPK %s"%(pkg,rdeps))

        # Update with inter stack layer shared lib dependencies
        shlibrdeps = update_rdeps_shlib(d,pkg)
        if shlibrdeps:
            for shlib in shlibrdeps:
                if shlib not in (d.getVar('RDEPENDS:' + pkg) or "").split(" "):
                    lrdeps_check = True
                    if shlib not in rdepends:
                        rdepends.append(shlib)
                    bb.note("[deps-resolver] pkg %s has runtime dependency [from objdump] with IPK %s"%(pkg,shlib))

        # Update with inter stack layer pkgconfig dependencies
        devrdeps = update_rdeps_pkgconfig(d,pkg)
        if devrdeps:
            for devrdep in devrdeps:
                if devrdep not in (d.getVar('RDEPENDS:' + pkg) or "").split(" "):
                    lrdeps_check = True
                    if devrdep not in rdepends:
                        rdepends.append(devrdep)
                    bb.note("[deps-resolver] pkg %s has runtime dependency [from pkgconfig] with IPK %s"%(pkg, devrdep))

        for rdep in (d.getVar("INSTALL_RDEPENDS:"+ pkg) or "").split(","):
            if rdep not in rdepends:
                rdepends.append(rdep)

        if lrdeps_check:
            d.appendVar('RDEPENDS:' + pkg, ' ' + ' '.join(rdepends))
            if not os.path.exists(pkgdata_path):
                bb.utils.mkdirhier(pkgdata_path)
            packagedfile = os.path.join(pkgdata_path,'%s.lrdep' % pkg)
            open(packagedfile, 'w').close()
}

# Find ipk pkgs (recipes unavailabe) from the DEPENDS/RDEPENDS list.
python deps_update_handler () {
    pn = e.data.getVar('PN')
    # This needs to be updated once start using the prebuilt toolchain
    if not bb.data.inherits_class('native', d):
        update_dep_pkgs(e)
}
addhandler deps_update_handler
deps_update_handler[eventmask] = "bb.event.RecipeParsed"

python deps_taskhandler() {
    pn = d.getVar('PN')
    pe = d.getVar('PE')
    pv = d.getVar('PV')
    pr = d.getVar('PR')
    skip_depends = False
    version = "%s:%s-%s"%(pe,pv,pr) if pe else "%s-%s"%(pv,pr)
    feed_info_dir = d.getVar("FEED_INFO_DIR")
    version = version.replace("AUTOINC","0")
    (ipk_mode, version_check, arch_check) = check_deps_ipk_mode(d, pn, False, version)
    if ipk_mode and not check_targets(d, pn):
        skip_depends = True

    bbtasks = e.tasklist
    dep_list = ["depends","rdepends"]
    for task in bbtasks:
        for dep in dep_list:
            pkg_task_list = (e.data.getVarFlag(task, '%s'%dep)or"").split(" ")
            pkgs_list = []
            for pkg_task in pkg_task_list:
                dep_task = pkg_task
                pkg = pkg_task.split(":")[0]
                preferred_provider = e.data.getVar('PREFERRED_PROVIDER_%s' % pkg, True)
                if preferred_provider is not None:
                    pkg = preferred_provider
                (ipk_mode, version_check, arch_check) = check_deps_ipk_mode(e.data, pkg)
                if ipk_mode:
                    continue
                if skip_depends:
                    if arch_check:
                        pkgs_list.append(dep_task)
                else:
                    pkgs_list.append(dep_task)
            e.data.setVarFlag(task,'%s'%dep,' '.join(pkgs_list))
}
deps_taskhandler[eventmask] = "bb.event.RecipeTaskPreProcess"
addhandler deps_taskhandler

python do_skip_ipk_files_qa_check () {
    bb.build.exec_func("read_subpackage_metadata", d)
    packages = d.getVar('PACKAGES').split(" ")
    pkg_dir = d.getVar("IPK_PKGDATA_RUNTIME_DIR")
    for pkg in packages:
        pkg_path = os.path.join(pkg_dir,pkg)
        if os.path.isdir(pkg_path):
            continue
        if os.path.exists(pkg_path):
            with open(pkg_path,"r") as fd:
                lines = fd.readlines()
            for l in lines:
                d.appendVar("FILES_IPK_PKG:%s"%pkg, " %s"%l[:-1])
}
do_package_qa[prefuncs] += "do_skip_ipk_files_qa_check"

def create_abiversion(d,version):
    kernel_depmod = oe.path.join(d.getVar('PKGDATA_DIR'), "kernel-depmod")
    bb.utils.mkdirhier(kernel_depmod)
    kernel_abi_ver_file = oe.path.join(d.getVar('PKGDATA_DIR'), "kernel-depmod",
                                           'kernel-abiversion')
    with open(kernel_abi_ver_file, "w") as abi_ver_file:
        abi_ver_file.write(version)

def create_version_info(d,version,pkg):
    ipk_version_info = d.getVar("IPK_PKGGROUP_VER_INFO")
    with open(ipk_version_info,"a") as fv:
        fv.write(pkg + ": " +version +"\n")

def create_ipk_deps_tree(d, package_data):
    source_to_dependencies = {}
    local_pkgdataa = package_data
    for package, (source, dependencies) in package_data.items():
        # For each dependency of this source, add all the sources that depend on it
        for dependency in dependencies:
            for pkg_deps, (dependent_sources, deps) in local_pkgdataa.items():
                if dependency == dependent_sources or dependency == pkg_deps:
                    # Initialize the set for this source if not already present
                    if source not in source_to_dependencies:
                        source_to_dependencies[source] = set()
                    source_to_dependencies[source].add(dependent_sources)
                    break
    return source_to_dependencies

def create_ipk_pkgdata(d,file_path,ipk_pkgdata_dir,arch_name):
    import os
    package_info = {}
    dependencies = []
    source = None
    package = None
    provides = None
    version = None

    if not os.path.exists(ipk_pkgdata_dir+"%s/rprovides/virtual/"%arch_name):
        bb.utils.mkdirhier(ipk_pkgdata_dir+"%s/rprovides/virtual/"%arch_name)
    if not os.path.exists(ipk_pkgdata_dir+"%s/package/"%arch_name):
        bb.utils.mkdirhier(ipk_pkgdata_dir+"%s/package/"%arch_name)
    if not os.path.exists(ipk_pkgdata_dir+"%s/source/"%arch_name):
        bb.utils.mkdirhier(ipk_pkgdata_dir+"%s/source/"%arch_name)
    with open(file_path, 'r', encoding='utf-8') as file:
        for line in file:
            line = line.strip()
            if not line:  # Blank line indicates the end of a package entry
                if package != None:
                    if not package.endswith("-dev") and not package.endswith("-dbg") and not package.endswith("-staticdev") and not package.endswith("-doc") and not package.endswith("-src"):
                        package_info[package] = (source, dependencies)
                    if not package.endswith("-doc") and not package.endswith("-src"):
                        pkg_path = os.path.join(ipk_pkgdata_dir+"%s/"%arch_name, ("package/%s")%(package))
                        src_path = os.path.join(ipk_pkgdata_dir+"%s/"%arch_name, "source/%s"%source)
                        with open(src_path+"_%s"%version, 'a') as file:
                             file.write("%s\n"%package)
                        if package.endswith("-dev") or package.endswith("-staticdev"):
                            if get_base_pkg_name(package) != source and get_base_pkg_name(package) != "lib"+source and not os.path.exists(src_path+".customised"):
                                os.symlink("%s_%s"%(source,version),src_path+".customised")
                        if not os.path.islink(pkg_path):
                            os.symlink("../source/%s_%s"%(source,version),pkg_path)
                        if provides:
                            for provide in  provides.split(", "):
                                prov_path = os.path.join(ipk_pkgdata_dir+"%s/rprovides/"%arch_name, ("%s")%(provide))
                                if not os.path.islink(prov_path):
                                    if provide.startswith("virtual/"):
                                        os.symlink("../../package/%s"%package,prov_path)
                                    else:
                                        os.symlink("../package/%s"%package,prov_path)
                        if package == "kernel" or "kernel-base" in (provides or "").split(", "):
                            create_abiversion(d,version)
                        if "packagegroup-" in package and not package.endswith("-dev") and not package.endswith("-staticdev") and not package.endswith("-dbg"):
                            create_version_info(d,version,package)
                        package = provides = source = None
                continue

            if line.startswith('Package:'):
                package = line.split('Package: ', 1)[1]
            elif line.startswith('Provides:'):
                provides = line.split('Provides: ', 1)[1]
            elif line.startswith('Source:'):
                source = line.split('Source: ', 1)[1]
                if "_" in source:
                     source = source.split("_", 1)[0]
                else:
                     source = source[:-3]
            elif line.startswith('Version:'):
                version = line.split('Version: ', 1)[1]
            elif line.startswith('Depends:'):
                dependencies = [dep.strip().split(' ')[0] for dep in line.split('Depends: ')[1].split(',')]

    if arch_name in (d.getVar("STACK_LAYER_EXTENSION") or "").split(" "):
        ipk_deps_mapping = create_ipk_deps_tree(d, package_info)
        d.setVar("IPK_DEPS_MAPPING_LIST",ipk_deps_mapping)

    if package != None:
        if not package.endswith("-doc") and not package.endswith("-src"):
            pkg_path = os.path.join(ipk_pkgdata_dir+"%s/"%arch_name, ("package/%s")%(package))
            src_path = os.path.join(ipk_pkgdata_dir+"%s/"%arch_name, "source/%s"%source)
            with open(src_path+"_%s"%version, 'a') as file:
                file.write("%s\n"%package)
            if package.endswith("-dev") or package.endswith("-staticdev"):
                if get_base_pkg_name(package) != source and get_base_pkg_name(package) != "lib"+source and not os.path.exists(src_path+".customised"):
                    os.symlink("%s_%s"%(source,version),src_path+".customised")
            if not os.path.islink(pkg_path):
                os.symlink("../source/%s_%s"%(source,version),pkg_path)
            if provides:
                for provide in  provides.split(", "):
                    prov_path = os.path.join(ipk_pkgdata_dir+"%s/rprovides/"%arch_name, ("%s")%(provide))
                    if not os.path.islink(prov_path):
                        if provide.startswith("virtual/"):
                            os.symlink("../../package/%s"%package,prov_path)
                        else:
                            os.symlink("../package/%s"%package,prov_path)
            if package == "kernel" or "kernel-base" in (provides or "").split(", "):
                create_abiversion(d,version)
            if "packagegroup-" in package and not package.endswith("-dev") and not package.endswith("-staticdev") and not package.endswith("-dbg"):
                create_version_info(d,version,package)

python create_stack_layer_info () {
    import subprocess
    import re
    import shutil
    import gzip
    feed_info_dir = e.data.getVar("FEED_INFO_DIR")
    index_check = os.path.join(e.data.getVar("TOPDIR")+"/index_created")
    if isinstance(e, bb.event.BuildCompleted) or isinstance(e, bb.event.TreeDataPreparationStarted):
        if os.path.exists(index_check):
            os.remove(index_check)
    if isinstance(e, bb.event.TreeDataPreparationCompleted):
        if not os.path.exists(index_check):
            open(index_check, 'w').close()
    if isinstance(e, bb.event.MultiConfigParsed):
        # For multiconfig builds.
        if not os.path.exists(index_check):
            open(index_check, 'w').close()
    if isinstance(e, bb.event.ConfigParsed) and not os.path.exists(index_check):
        if os.path.exists(feed_info_dir):
            shutil.rmtree(feed_info_dir)
        if not os.path.exists(feed_info_dir+"index/"):
            bb.utils.mkdirhier(feed_info_dir+"index/")
        if d.getVar("STACK_LAYER_EXTENSION"):
            # To skip cache parsing and start recipe parsing
            import random
            e.data.setVar("TARGET_PARSING",random.randint(1, 50))

        ml_config = e.data.getVar("BBMULTICONFIG") or ""
        if not ml_config:
            # For non multiconfig builds.
            if not os.path.exists(index_check):
                open(index_check, 'w').close()

        for line in (e.data.getVar('IPK_FEED_URIS') or "").split():
            feed = re.match(r"^[ \t]*(.*)##([^ \t]*)[ \t]*$", line)
            if feed is not None:
                arch_name = feed.group(1)
                arch_uri = feed.group(2)
                index_file = feed_info_dir+"index/"
                if arch_uri.startswith("file:"):
                    shutil.copy(arch_uri[5:]+"/Packages.gz", index_file)
                else:
                    bb.process.run("wget %s --directory-prefix=%s"%(arch_uri+"/Packages.gz", index_file), stderr=subprocess.STDOUT)
                with gzip.open(index_file+"Packages.gz", 'rb') as gz_file:
                    with open(index_file+arch_name, 'wb') as output_file:
                        shutil.copyfileobj(gz_file, output_file)
                os.remove(index_file+"/Packages.gz")
                create_ipk_pkgdata(e.data, index_file+arch_name ,feed_info_dir,arch_name)
}
addhandler create_stack_layer_info
create_stack_layer_info[eventmask] = "bb.event.ConfigParsed bb.event.BuildCompleted bb.event.TreeDataPreparationStarted bb.event.TreeDataPreparationCompleted bb.event.MultiConfigParsed"

def create_feed_index(arg):
    import subprocess
    cmd = arg
    bb.note("Executing '%s' ..." % cmd)
    result = subprocess.check_output(cmd, stderr=subprocess.STDOUT, shell=True).decode("utf-8")
    if result:
        bb.note(result)

# This is temporary. Once opkg-utils is part of Docker, we can remove it.
# Also, need to check if the recipe-native can be generated for the default package.
OPKG_UTILS_SYSROOT = "${COMPONENTS_DIR}/${BUILD_ARCH}/opkg-utils-native"
OPKG_INDEX_FILE = "${OPKG_UTILS_SYSROOT}${bindir_native}/opkg-make-index"

python feed_index_creation () {
    if e.data.getVar("DEPLOY_IPK_FEED") == "0":
        return
    cmds = set()
    opkg_index_cmd = bb.utils.which(os.getenv('PATH'), "opkg-make-index")
    if not opkg_index_cmd :
        opkg_index_cmd = e.data.getVar("OPKG_INDEX_FILE")
        if not os.path.exists(opkg_index_cmd) :
            return

    deploy_dir = e.data.getVar("DEPLOY_DIR_IPK")
    if not os.path.exists(deploy_dir):
        return

    archs = e.data.getVar("ALL_MULTILIB_PACKAGE_ARCHS")
    for arch in archs.split():
        pkgs_dir = os.path.join(deploy_dir, arch)
        pkgs_file = os.path.join(pkgs_dir, "Packages")
        pkgs_compres_file = os.path.join(pkgs_dir, "Packages.gz")
        pkgs_stamp_file = os.path.join(pkgs_dir, "Packages.stamps")
        if os.path.exists(pkgs_file):
            os.remove(pkgs_file)
        if os.path.exists(pkgs_compres_file):
            os.remove(pkgs_compres_file)
        if os.path.exists(pkgs_stamp_file):
            os.remove(pkgs_stamp_file)

        if not os.path.isdir(pkgs_dir):
            continue

        if not os.path.exists(pkgs_file):
            open(pkgs_file, "w").close()

        cmds.add('%s --checksum md5 --checksum sha256 -r %s -p %s -m %s' %
                     (opkg_index_cmd, pkgs_file, pkgs_file, pkgs_dir))

    if len(cmds) == 0:
        bb.note("There are no packages in %s!" % deploy_dir)
        return

    oe.utils.multiprocess_launch(create_feed_index, cmds, e.data)
}

addhandler feed_index_creation
feed_index_creation[eventmask] = "bb.event.BuildCompleted"

python get_pkgs_handler () {
    if not d.getVar("STACK_LAYER_EXTENSION"):
        return

    feed_info_dir = d.getVar("FEED_INFO_DIR")
    update_check = False
    if isinstance(e,bb.event.DepTreeGenerated):
        targetdeps = []
        for deps in e._depgraph['depends']:
            if deps.endswith("-native"):
                continue
            if deps not in targetdeps:
                targetdeps.append(deps)
        for deps in e._depgraph['rdepends-pn']:
            if deps.endswith("-native"):
                continue
            if deps not in targetdeps:
                targetdeps.append(deps)
        ipk_mapping = e.data.getVar("IPK_DEPS_MAPPING_LIST") or {}

        for source, dependencies in ipk_mapping.items():
             if os.path.exists(feed_info_dir+"src_mode/%s"%source):
                 continue

             if source not in targetdeps:
                 continue

             for dep in dependencies:
                 if os.path.exists(feed_info_dir+"src_mode/%s.major"%dep):
                     if not update_check:
                         update_check = True
                     bb.warn("%s version should update and rebuild. Dependency %s has changed with major version"%(source,dep))
    if update_check:
        index_check = os.path.join(e.data.getVar("TOPDIR")+"/index_created")
        if os.path.exists(index_check):
            os.remove(index_check)
        bb.fatal("Update version and required rebuild")
}
addhandler get_pkgs_handler
get_pkgs_handler[eventmask] = "bb.event.DepTreeGenerated"

