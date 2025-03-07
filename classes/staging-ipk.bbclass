# -----------------------------------------------------------------------
# File: classes/staging-ipk.bbclass
# Author: Sreejith Ravi
# Date: 2024-06-23
#
# Description : Identify the packages available as IPK and install them
# into a common staging folder.
# -----------------------------------------------------------------------

IPK_DESTDIR = "${WORKDIR}/ipk-destdir"

# Directories excluded from common ipk sysroot.
IPK_COMMON_DIRS_EXCLUSIONLIST = " \
    ${mandir} ${docdir} ${infodir} ${datadir}/fonts ${datadir}/locale \
    ${datadir}/pixmaps ${datadir}/terminfo ${datadir}/X11/locale \
    ${datadir}/applications ${datadir}/bash-completion \
    ${libdir}/${BPN}/ptest \
"
# List of directories to generate common ipk sysroot.
# /var/lib/opkg is required to get the opkg info.
IPK_COMMON_DIRS = " \
    ${includedir} ${libdir} ${base_libdir} ${bindir}\
    ${nonarch_base_libdir} ${datadir} \
    "/var/lib/opkg" "/kernel-source" "/kernel-build"\
"

do_populate_ipk_sysroot[depends] += "pseudo-native:do_populate_sysroot"

ipk_staging_dirs() {
    src="$1"
    dest="$2"

    for dir in ${IPK_COMMON_DIRS}; do
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
    rm -rf ${SYSROOT_IPK}
    ipk_staging_dirs ${IPK_DESTDIR}  ${SYSROOT_IPK}
    rm -rf ${IPK_DESTDIR}
}

do_populate_ipk_sysroot[depends] += "opkg-native:do_populate_sysroot"

# Create the opkg configuration with remote feeds
def configure_opkg (d, conf):
    import re
    archs = d.getVar("ALL_MULTILIB_PACKAGE_ARCHS")
    feed_list = []
    with open(conf, "w+") as file:
        priority = 1
        for arch in archs.split():
            file.write("arch %s %d\n" % (arch, priority))
            priority += 5

        for line in (d.getVar('IPK_FEED_URIS') or "").split():
            feed = re.match(r"^[ \t]*(.*)##([^ \t]*)[ \t]*$", line)

            if feed is not None:
                arch_name = feed.group(1)
                arch_uri = feed.group(2)
                feed_list.append(arch_name)
                bb.note("[staging-ipk] Add %s feed with URL %s" % (arch_name, arch_uri))

                file.write("src/gz %s %s\n" % (arch_name, arch_uri))

    bb.note("[staging-ipk] IPK feed list : %s"%feed_list)
    return feed_list

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
            deps = pkgdata["Depends"].split(", ")
            bb.note("[staging-ipk] pkg %s depends on ipk : %s"%(pkg,deps))
    return deps

def cmdline(command, path):
    import subprocess
    bb.process.run(command, stderr=subprocess.STDOUT, cwd=path)

def ipk_install(d, cmd, pkgs):
    import subprocess
    command = cmd + " ".join(pkgs)

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
            bb.fatal("Post installation of %s failed"%failed_pkgs)

    except subprocess.CalledProcessError as e:
        error_msg = e.output.decode("utf-8")
        bb.fatal("Packages installation failed. Command : %s \n%s"%(command, error_msg))

def get_base_pkg_name(pkg_name):
    tmp_pkg_name = pkg_name
    if pkg_name.endswith('-dev') or pkg_name.endswith('-dbg') or pkg_name.endswith('-src') or pkg_name.endswith('-bin'):
        tmp_pkg_name = pkg_name[:-4]
    if pkg_name.endswith('-staticdev'):
        tmp_pkg_name = pkg_name[:-10]
    if pkg_name.endswith('-locale'):
        tmp_pkg_name = pkg_name[:-7]
    return tmp_pkg_name

# Install the dependent ipks to the component sysroot
python do_populate_ipk_sysroot(){
    import shutil
    import re
    deps, ipk_pkgs, ipk_list, inst_list= ([] for i in range(4))

    bb.note("[staging-ipk] Enter : do_populate_ipk_sysroot")
    listpath = d.getVar("DEPS_IPK_DIR")
    if not os.path.exists(listpath):
        bb.note("[staging-ipk] No pkgs listed for IPK dependency")
        return

    opkg_cmd = bb.utils.which(os.getenv('PATH'), "opkg")

    opkg_conf = d.getVar("IPKGCONF_LAYERING")

    feed_name = configure_opkg (d, opkg_conf)

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
    opkg_args_up = "-f %s -t %s -o %s --prefer-arch-to-version --no-install-recommends " % (opkg_conf, info_file_path, sysroot_destdir)

    cmd = '%s --volatile-cache %s update' % (opkg_cmd, opkg_args_up)
    cmdline(cmd, info_file_path)

    # Enable cache option for opkg install
    opkg_args = "--host-cache-dir --cache-dir %s %s " % (ipk_cache_dir, opkg_args_up)
    feed_info_dir = d.getVar("FEED_INFO_DIR")
    if not os.path.exists(feed_info_dir):
        return

    for file in os.listdir(listpath):
        deps = read_ipk_depends(d,file)
        if deps != []:
            for dep in deps:
                if dep == "" or dep == " " or dep in ipk_pkgs:
                    continue
                ipk_pkgs.append(dep)

    archs = []
    for line in (d.getVar('IPK_FEED_URIS') or "").split():
        feed = re.match(r"^[ \t]*(.*)##([^ \t]*)[ \t]*$", line)
        if feed is not None:
            archs.append(feed.group(1))
    for pkg in ipk_pkgs:
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
                    elif os.path.exists(pkg_path + "source/%s"%pkg):
                        recipe_info = pkg_path + "source/%s"%pkg
                        arch_check =  True
                    else:
                        prefix = d.getVar('MLPREFIX') or ""
                        if prefix and pkg.startswith(prefix):
                            ml_pkg = "%slib%s"%(prefix,pkg[len(prefix):])
                        else:
                            ml_pkg = "lib"+pkg
                        if os.path.exists(pkg_path + "package/%s"%ml_pkg):
                            recipe_info = pkg_path + "package/%s"%ml_pkg
                            arch_check =  True
                if arch_check:
                    break

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
                    if dev_pkg not in inst_list:
                        inst_list.append(dev_pkg)
            if staticdev_pkgs :
                for staticdev_pkg in staticdev_pkgs:
                    if pkg_ver:
                        staticdev_pkg = staticdev_pkg+pkg_ver.strip("()")
                    if staticdev_pkg not in inst_list:
                        inst_list.append(staticdev_pkg)
            if rel_pkgs:
                for rel_pkg in rel_pkgs:
                    if pkg_ver:
                        rel_pkg = rel_pkg+pkg_ver.strip("()")
                    if rel_pkg not in inst_list:
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
        ipk_install(d, cmd, inst_list)
        boot_dir = os.path.join(sysroot_destdir,"%s"%d.getVar("IMAGEDEST"))
        if os.path.exists(boot_dir):
            img_deploy_dir = d.getVar("DEPLOY_DIR_IMAGE")
            if not os.path.exists(img_deploy_dir):
                bb.utils.mkdirhier(img_deploy_dir)
            for item in os.listdir(boot_dir):
                src = os.path.join(boot_dir, item)
                dest = os.path.join(img_deploy_dir, item)
                shutil.copy(src,dest)
        # Generate the IPK staging directory for sysroot creation.
        bb.build.exec_func("create_ipk_common_staging", d)

    bb.note("[staging-ipk] Installed pkgs : %s"%inst_list)
}
python(){
   d.setVarFlag('do_populate_ipk_sysroot', 'fakeroot', '1')
}
do_populate_ipk_sysroot[umask] = "022"

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
