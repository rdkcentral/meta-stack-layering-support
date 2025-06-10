# -----------------------------------------------------------------------
# File: classes/staging-ipk.bbclass
# Author: Sreejith Ravi
# Date: 2024-06-23
#
# Description : Identify the packages available as IPK and install them
# into a common staging folder.
# -----------------------------------------------------------------------

IPK_DESTDIR = "${WORKDIR}/ipk-destdir"
IPK_SYSDIR = "${WORKDIR}/ipk-sysroot-dir"

# Directories excluded from common ipk sysroot.
IPK_COMMON_DIRS_EXCLUSIONLIST = " \
    ${mandir} ${docdir} ${infodir} ${datadir}/fonts ${datadir}/locale \
    ${datadir}/pixmaps ${datadir}/terminfo ${datadir}/X11/locale \
    ${datadir}/applications ${datadir}/bash-completion \
    ${libdir}/${BPN}/ptest \
"
# List of directories to generate common ipk sysroot.
# /var/lib/opkg is required to get the opkg info.
IPK_COMMON_DIRS = "${includedir} ${libdir} ${base_libdir} ${bindir} ${nonarch_base_libdir} ${datadir} /var/lib/opkg /usr/lib/opkg /kernel-source /kernel-build /boot"

do_populate_ipk_sysroot[depends] += "pseudo-native:do_populate_sysroot"
do_populate_ipk_sysroot[depends] += "opkg-utils-native:do_populate_sysroot"
do_populate_ipk_sysroot[depends] += "shadow-native:do_populate_sysroot"
do_populate_ipk_sysroot[depends] += "opkg-native:do_populate_sysroot"

ipk_staging_dirs() {
    src="$1"
    dest="$2"
    comdir="$3"

    for dir in $comdir; do
        # Stage directory if it exists
        if [ -d "$src$dir" ]; then
            mkdir -p "$dest$dir"
            (
                cd "$src$dir" || exit
                find . -print0 | cpio --null -pdlu "$dest$dir"
            )
        fi
    done

    for dir in ${IPK_COMMON_DIRS_EXCLUSIONLIST}; do
        rm -rf "$dest$dir"
    done
}

create_ipk_common_staging() {
    ipk_staging_dirs ${IPK_DESTDIR} ${IPK_SYSDIR} "${IPK_COMMON_DIRS}"
    rm -rf ${IPK_DESTDIR}
}

# Function reads indirect build and runtime dependencies
# from the pkgdata directory
def read_ipk_depends(d, pkg):
    pkgdata = {}
    deps = []
    def decode(str):
        import codecs
        c = codecs.getdecoder("unicode_escape")
        return c(str)[0]
    pkgdata_path = d.getVar("DEPS_IPK_DIR")
    pkg_path = os.path.join(pkgdata_path,pkg)
    if os.path.exists(pkg_path):
        import re
        ldep = bb.utils.lockfile(pkgdata_path + "/%s.lock"%pkg)
        with open(pkg_path,"r") as fd:
            lines = fd.readlines()
        bb.utils.unlockfile(ldep)
        r = re.compile(r"(^.+?):\s+(.*)")
        for l in lines:
            m = r.match(l)
            if m:
                pkgdata[m.group(1)] = decode(m.group(2))
        if "Depends" in pkgdata:
            ipkdeps = pkgdata["Depends"].split(", ")
            for dep in ipkdeps:
                dep = dep.split(" ")[0]
                if dep not in deps:
                    deps.append(dep)
        if "Rdepends" in pkgdata:
            ipkrdeps = pkgdata["Rdepends"].split(", ")
            for dep in ipkrdeps:
                dep = dep.split(" ")[0]
                if dep not in deps:
                    deps.append(dep)
        bb.note("[staging-ipk] pkg %s depends on ipk : %s"%(pkg,deps))
    return deps

def cmdline(command, path):
    import subprocess
    bb.process.run(command, stderr=subprocess.STDOUT, cwd=path)

def ipk_install(d, cmd, pkgs, sysroot_destdir):
    import subprocess

    command = cmd + " ".join(pkgs)
    env_bkp = os.environ.copy()
    os.environ['D'] = sysroot_destdir
    os.environ['OFFLINE_ROOT'] = sysroot_destdir
    os.environ['IPKG_OFFLINE_ROOT'] = sysroot_destdir
    os.environ['OPKG_OFFLINE_ROOT'] = sysroot_destdir
    os.environ['NATIVE_ROOT'] = d.getVar('STAGING_DIR_NATIVE')
    try:
        bb.note("[staging-ipk] Installing the following packages: %s" % ' '.join(pkgs))
        bb.note("Command: %s"%command)

        # Run the command and decode the result
        result = subprocess.check_output(command.split(), stderr=subprocess.STDOUT).decode("utf-8")
        bb.note(result)

        # Identify packages with failed postinstall scripts
        failed_pkgs = [
            line.split(".")[0]
            for line in result.splitlines()
            if line.endswith("configuration required on target.")
        ]

        if failed_pkgs:
            bb.note("Post installation of %s failed"%failed_pkgs)
    except subprocess.CalledProcessError as e:
        error_msg = e.output.decode("utf-8")
        bb.fatal("Packages installation failed. Command : %s \n%s"%(command, error_msg))
    os.environ.clear()
    os.environ.update(env_bkp)

def get_base_pkg_name(pkg_name):
    tmp_pkg_name = pkg_name
    if pkg_name.endswith('-dev') or pkg_name.endswith('-dbg') or pkg_name.endswith('-src') or pkg_name.endswith('-bin'):
        tmp_pkg_name = pkg_name[:-4]
    if pkg_name.endswith('-staticdev'):
        tmp_pkg_name = pkg_name[:-10]
    if pkg_name.endswith('-locale'):
        tmp_pkg_name = pkg_name[:-7]
    return tmp_pkg_name

python do_kernel_devel_create(){
    kernel_src = d.getVar('SYSROOT_IPK')+"/kernel-source"
    kernel_artifacts = d.getVar('SYSROOT_IPK')+"/kernel-build"
    kernel_src_staging = d.getVar('STAGING_KERNEL_DIR')
    kernel_build_staging = d.getVar('STAGING_KERNEL_BUILDDIR')
    if os.path.exists(kernel_src):
        if not os.path.exists(kernel_src_staging):
            parent_dir = os.path.dirname(kernel_src_staging)
            if not os.path.exists(parent_dir):
                bb.utils.mkdirhier(parent_dir)
            os.symlink(kernel_src, d.getVar('STAGING_KERNEL_DIR'))
    else:
        bb.note("kernel devel source is not present in IPK feeds")

    if os.path.exists(kernel_artifacts):
        if not os.path.exists(kernel_build_staging):
            parent_dir = os.path.dirname(kernel_build_staging)
            if not os.path.exists(parent_dir):
                bb.utils.mkdirhier(parent_dir)
            os.symlink(kernel_artifacts, d.getVar('STAGING_KERNEL_BUILDDIR'))
    else:
        bb.note("kernel devel build artifacts is not present in IPK feeds")
}

def check_staging_exclusion(d, pkg, pkg_path):
    is_excluded = False
    skip_pkgs = []
    if not pkg or not d.getVar("IPK_STAGING_EXCLUSION_LIST"):
        return is_excluded
    pkg = pkg.strip()
    prefix = d.getVar('MLPREFIX') or ""
    if prefix and pkg.startswith(prefix):
        pkg = pkg[len(prefix):]
    if pkg in (d.getVar("IPK_STAGING_EXCLUSION_LIST") or "").split():
        is_excluded = True
    else:
        import glob
        for skip_pkg in (d.getVar("IPK_STAGING_EXCLUSION_LIST") or "").split():
            recipe_info = glob.glob(pkg_path + "/source/%s_*"%(skip_pkg))
            if recipe_info:
                recipe_info = recipe_info[0]
                with open(recipe_info, 'r') as file:
                    lines = file.readlines()
                for line in lines:
                    skip_pkgs.append(line[:-1])
        if pkg in skip_pkgs:
            is_excluded = True
    return is_excluded

# Install the dependent ipks to the component sysroot
fakeroot python do_populate_ipk_sysroot(){
    import re
    deps, ipk_pkgs, ipk_list, inst_list= ([] for i in range(4))

    bb.note("[staging-ipk] Enter : do_populate_ipk_sysroot")
    listpath = d.getVar("DEPS_IPK_DIR")
    if not os.path.exists(listpath):
        bb.note("[staging-ipk] No pkgs listed for IPK dependency")
        return

    opkg_cmd = bb.utils.which(os.getenv('PATH'), "opkg")

    opkg_conf = d.getVar("IPKGCONF_LAYERING")
    import oe.sls_utils
    oe.sls_utils.sls_opkg_conf (d, opkg_conf)

    info_file_path = os.path.join(d.getVar("D", True), "ipktemp/")
    bb.utils.mkdirhier(os.path.dirname(info_file_path))

    # create cache directory
    ipk_cache_dir = d.getVar("IPK_CACHE_DIR")
    if not os.path.exists(ipk_cache_dir):
        bb.utils.mkdirhier(ipk_cache_dir)

    # Create the syroot destination directory 
    sysroot_destdir = d.getVar("IPK_DESTDIR")
    if not os.path.exists(sysroot_destdir):
        bb.utils.mkdirhier(sysroot_destdir)

    # Disable the recommends pkgs installation
    opkg_args_up = "-f %s -t %s -o %s --force_postinstall --prefer-arch-to-version --no-install-recommends " % (opkg_conf, info_file_path, sysroot_destdir)

    cmd = '%s --volatile-cache %s update' % (opkg_cmd, opkg_args_up)
    cmdline(cmd, info_file_path)

    # Enable cache option for opkg install
    opkg_args = "--host-cache-dir --cache-dir %s %s %s" %(ipk_cache_dir, opkg_args_up, (d.getVar("IPK_EXTRA_CONF_OPTIONS") or ""))
    feed_info_dir = d.getVar("FEED_INFO_DIR")
    if not os.path.exists(feed_info_dir):
        return
    target_list_path = d.getVar("TARGET_DEPS_LIST")
    if target_list_path and os.path.exists(target_list_path) and d.getVar("TARGET_BASED_IPK_INSTALL") == "1":
        bb.note("ipk installation based on target build only")
        with open(target_list_path,"r") as fd:
            files = fd.readlines()
    else:
        bb.note("ipk installation not based on target build. Installing depends ipk of all recipes")
        files = os.listdir(listpath)

    prefix = d.getVar('MLPREFIX') or ""

    for file in files:
        if "packagegroup-" in file:
            continue
        if file.endswith("\n"):
            file = file[:-1]
        deps = read_ipk_depends(d,file)
        if deps != []:
            for dep in deps:
                if dep == "" or dep == " " or dep in ipk_pkgs:
                    continue
                ipk_pkgs.append(dep)

    for ipk in (d.getVar("IPK_INCLUSION_LIST") or "").split():
        ipk_pkgs.append(ipk)

    archs = []
    for line in (d.getVar('IPK_FEED_URIS') or "").split():
        feed = re.match(r"^[ \t]*(.*)##([^ \t]*)[ \t]*$", line)
        if feed is not None:
            if d.getVar("EXCLUDE_IPK_FEEDS") and feed.group(1) in d.getVar("EXCLUDE_IPK_FEEDS").split():
                continue
            archs.append(feed.group(1))
    if not archs:
        return

    for pkg in ipk_pkgs:
        is_excluded = False
        dev_pkgs, staticdev_pkgs, rel_pkgs = ([] for i in range(3))
        pkg_ver = ""
        recipe_info = ""
        if pkg == "" or "-native" in pkg :
            continue
        parts = pkg.strip().split(" ")
        if len(parts) > 1:
            pkg = parts[0]
            pkg_ver = parts[1]
        if "virtual" in pkg:
            pkg = d.getVar('PREFERRED_PROVIDER_%s' % pkg, True)
            if not pkg:
                bb.warn("PREFERRED_PROVIDER is not set for %s" %pkg)
                continue

        pkg = get_base_pkg_name(pkg)
        if pkg not in ipk_list:
            ipk_list.append(pkg)
            for arch in archs:
                arch_check =  False
                pkg_path = feed_info_dir+"%s/"%arch
                if os.path.exists(pkg_path + "rprovides/%s-dev"%pkg):
                    if pkg+"-dev" not in dev_pkgs:
                        dev_pkgs.append(pkg + "-dev")
                    recipe_info = pkg_path + "rprovides/%s-dev"%pkg
                    arch_check =  True
                elif os.path.exists(pkg_path + "package/%s-dev"%pkg):
                    if pkg+"-dev" not in dev_pkgs:
                        dev_pkgs.append(pkg + "-dev")
                    recipe_info = pkg_path + "package/%s-dev"%pkg
                    arch_check =  True
                if os.path.exists(pkg_path + "rprovides/%s-staticdev"%pkg):
                    if pkg+"-staticdev" not in dev_pkgs:
                        staticdev_pkgs.append(pkg + "-staticdev")
                    recipe_info = pkg_path + "rprovides/%s-staticdev"%pkg
                    arch_check =  True
                elif os.path.exists(pkg_path + "package/%s-staticdev"%pkg):
                    if pkg+"-staticdev" not in dev_pkgs:
                        staticdev_pkgs.append(pkg + "-staticdev")
                    recipe_info = pkg_path + "package/%s-staticdev"%pkg
                    arch_check =  True
                if not dev_pkgs:
                    import glob
                    if os.path.exists(pkg_path + "rprovides/%s"%pkg):
                        recipe_info = pkg_path + "rprovides/%s"%pkg
                        if pkg not in rel_pkgs:
                            rel_pkgs.append(pkg )
                        arch_check =  True
                    elif os.path.exists(pkg_path + "package/%s"%pkg):
                        recipe_info = pkg_path + "package/%s"%pkg
                        if pkg not in rel_pkgs:
                            rel_pkgs.append(pkg )
                        arch_check =  True
                    elif glob.glob(pkg_path + "source/%s_*"%pkg):
                        recipe_info = glob.glob(pkg_path + "source/%s_*"%pkg)[0]
                        arch_check =  True
                    else:
                        if prefix and pkg.startswith(prefix):
                            ml_pkg = "%slib%s"%(prefix,pkg[len(prefix):])
                        else:
                            ml_pkg = "lib"+pkg
                        if os.path.exists(pkg_path + "package/%s"%ml_pkg):
                            recipe_info = pkg_path + "package/%s"%ml_pkg
                            arch_check =  True
                if arch_check:
                    break
            if check_staging_exclusion(d,pkg, pkg_path):
                is_excluded = True

            if recipe_info:
                with open(recipe_info, 'r') as file:
                    lines = file.readlines()
                for line in lines:
                    if line[:-1].endswith("-dev"):
                        if line[:-1] not in dev_pkgs:
                            dev_pkgs.append(line[:-1])
                    if line[:-1].endswith("-staticdev"):
                        if line[:-1] not in staticdev_pkgs:
                            staticdev_pkgs.append(line[:-1])

            if not dev_pkgs and not staticdev_pkgs and not rel_pkgs:
                continue
            if dev_pkgs:
                for dev_pkg in dev_pkgs:
                    if pkg_ver:
                        dev_pkg = dev_pkg+pkg_ver.strip("()")
                    if prefix and not dev_pkg.startswith(prefix) and "firmware" not in dev_pkg:
                            continue
                    if dev_pkg not in inst_list:
                        if not is_excluded:
                            inst_list.append(dev_pkg)
            if staticdev_pkgs :
                for staticdev_pkg in staticdev_pkgs:
                    if pkg_ver:
                        staticdev_pkg = staticdev_pkg+pkg_ver.strip("()")
                    if prefix and not staticdev_pkg.startswith(prefix) and "firmware" not in staticdev_pkg:
                            continue
                    if staticdev_pkg not in inst_list:
                        if not is_excluded:
                            inst_list.append(staticdev_pkg)
            if rel_pkgs:
                for rel_pkg in rel_pkgs:
                    if pkg_ver:
                        rel_pkg = rel_pkg+pkg_ver.strip("()")
                    if prefix and not rel_pkg.startswith(prefix) and "firmware" not in rel_pkg:
                            continue
                    if rel_pkg not in inst_list:
                        if not is_excluded:
                            inst_list.append(rel_pkg)

    #Check and Install kernel and device tree
    for arch in archs:
        arch_check =  False
        pkg_path = feed_info_dir+"%s/"%arch
        if os.path.exists(pkg_path + "rprovides/kernel-image"):
            inst_list.append("kernel-image")
            if os.path.exists(pkg_path + "package/kernel-devicetree"):
                inst_list.append("kernel-devicetree")
            if os.path.exists(pkg_path + "package/kernel-devel"):
                inst_list.append("kernel-devel")
            break

    if inst_list:
        cmd = '%s %s install ' % (opkg_cmd, opkg_args)
        ipk_install(d, cmd, inst_list, sysroot_destdir)
        # Generate the IPK staging directory for sysroot creation.
        bb.build.exec_func("create_ipk_common_staging", d)
    bb.note("[staging-ipk] Installed pkgs : %s"%inst_list)
}
python(){
   d.setVarFlag('do_populate_ipk_sysroot', 'fakeroot', '1')
}
do_populate_ipk_sysroot[umask] = "022"

SSTATETASKS += "do_populate_ipk_sysroot"
do_populate_ipk_sysroot[dirs] = "${IPK_SYSDIR}"
do_populate_ipk_sysroot[sstate-inputdirs] = "${IPK_SYSDIR}"
do_populate_ipk_sysroot[sstate-outputdirs] = "${SYSROOT_IPK}"
do_populate_ipk_sysroot[cleandirs] = "${SYSROOT_IPK}"

python do_populate_ipk_sysroot_setscene () {
    sstate_setscene(d)
}
addtask do_populate_ipk_sysroot_setscene

python __anonymous() {
    feed_index_dir = os.path.join(d.getVar("FEED_INFO_DIR"),"index")
    checksum_combined = ""
    if os.path.exists(feed_index_dir):
        for file in os.listdir(feed_index_dir):
            checksum = bb.utils.sha256_file(os.path.join(feed_index_dir, file))
            checksum_combined += checksum
    d.setVar("IPK_INDEX_CHECKSUM", checksum_combined)
    bb.note("[staging-ipk] ipk index checksum %s"%(d.getVar("IPK_INDEX_CHECKSUM")))
}
do_populate_ipk_sysroot[vardeps] += "IPK_INDEX_CHECKSUM"
do_populate_ipk_sysroot[network] = "1"
deltask do_fetch
deltask do_unpack
deltask do_patch
deltask do_install
deltask do_configure
deltask do_compile
deltask do_package
deltask do_packagedata
deltask do_package_qa
deltask do_package_write_ipk

addtask do_populate_ipk_sysroot before do_populate_sysroot
addtask do_kernel_devel_create before do_build

do_kernel_devel_create[nostamp] = "1"
