# ------------------------------------------------------------------------
# File: classes/custom-rootfs-creation.bbclass
# Author: Sreejith Ravi
# Date: 2024-06-21
# Description : Create custom opkg configuration and generate version info 
# for the packagegroups set in the IMAGE_INSTALL
# ------------------------------------------------------------------------

# This dependency is a work around. This pkg should be moved to 
# docker as native tools.
DEPENDS += "nss-native qemuwrapper-cross systemd-systemctl-native"

def get_pkg_install_version(d,release_data_file, pkggrp):
    import re
    version = ""
    pkgdata = {}
    ipk_version_info = d.getVar("IPK_PKGGROUP_VER_INFO")
    if not os.path.exists(ipk_version_info):
        return
    r = re.compile(r"(^.+?):\s+(.*)")
    with open(ipk_version_info,"r") as fr:
        lines = fr.readlines()
        r = re.compile(r"(^.+?):\s+(.*)")
        for l in lines:
            m = r.match(l)
            if m:
                pkgdata[m.group(1)] = m.group(2).encode()
    with open(release_data_file,"a") as fw:
        for pkg in pkggrp:
            if pkg in pkgdata:
                version = pkgdata[pkg]
                fw.write(pkg +"=" +pkgdata[pkg]+"\n")

python do_update_install_pkgs_with_version() {
    ipk_pkg_install = (d.getVar('IPK_IMAGE_INSTALL') or "").strip()
    m_pkggrp = []
    if ipk_pkg_install:
        ipk_install = ipk_pkg_install.split()
        for ipk in ipk_install:
            if ipk == " ":
                continue
            pkg_install = d.getVar("IMAGE_INSTALL")
            d.setVar('IMAGE_INSTALL', ipk +" " +pkg_install)
            bb.note("[custom-rootfs] Updated IMAGE_INSTALL with ipk pkgs : %s"%ipk)
    prefix = d.getVar('MLPREFIX') or ""
    gen_debugfs = d.getVar('IMAGE_GEN_DEBUGFS')
    if ipk_pkg_install and gen_debugfs == "1":
        pkgs_list = ipk_pkg_install.split()
        for pkg in pkgs_list:
            if prefix and not pkg.startswith(prefix):
                pkg = prefix+pkg
            d.appendVar("IMAGE_INSTALL_DEBUGFS", " %s-dbg"%pkg)

    ipk_pkg_install = (d.getVar('IPK_ROOTFS_BOOTSTRAP_INSTALL') or "").strip()
    if ipk_pkg_install:
        ipk_install = ipk_pkg_install.split()
        for ipk in ipk_install:
            if ipk == " ":
                continue
            pkg_install = d.getVar("ROOTFS_BOOTSTRAP_INSTALL")
            d.setVar('ROOTFS_BOOTSTRAP_INSTALL', ipk +" " +pkg_install)
            bb.note("[custom-rootfs] Updated ROOTFS_BOOTSTRAP_INSTALL with ipk pkgs : %s"%ipk)

    ipk_pkg_install = (d.getVar('IPK_FEATURE_INSTALL') or "").strip()
    if ipk_pkg_install:
        ipk_install = ipk_pkg_install.split()
        for ipk in ipk_install:
            if ipk == " ":
                continue
            pkg_install = d.getVar("FEATURE_INSTALL")
            d.setVar('FEATURE_INSTALL', ipk +" " +pkg_install)
            bb.note("[custom-rootfs] Updated FEATURE_INSTALL with ipk pkgs : %s"%ipk)

    # Generate the version info from the stack layer packageroups
    release_data_file = d.getVar("RELEASE_LAYER_VERSIONS", True)
    if release_data_file is None:
        bb.note("[custom-rootfs] RELEASE_LAYER_VERSIONS is not defined")
        return
    pkgdata = {}
    pkgdatadir = d.getVar('PKGDATA_DIR')
    runtime = pkgdatadir + "/runtime"
    runtime_rrprovides = pkgdatadir + "/runtime-rprovides"
    import re
    with open(release_data_file,"w") as fw:
        inst_list = d.getVar("IMAGE_INSTALL").split()
        for pkg in inst_list:
            if "packagegroup-" not in pkg:
                continue
            if prefix and not pkg.startswith(prefix):
                pkg = prefix + pkg
            rprovides_check = os.path.join(runtime_rrprovides,pkg)
            if os.path.exists(rprovides_check):
                possibles = os.listdir("%s/" % (rprovides_check))
                if len(possibles) == 1:
                    pkg_ver_file = os.path.join(runtime,possibles[0])
                else:
                    for p in possibles:
                        if d.getVar("PREFERRED_PROVIDER_%s"%pkg) == p:
                            pkg_ver_file = os.path.join(runtime,p)
            else:
                pkg_ver_file = os.path.join(runtime,pkg)

            version = ""
            if os.path.exists(pkg_ver_file):
                bb.note("[custom-rootfs] Version details of %s is available"%pkg)
                with open(pkg_ver_file,"r") as fr:
                    lines = fr.readlines()
                r = re.compile(r"(^.+?):\s+(.*)")
                for l in lines:
                    m = r.match(l)
                    if m:
                        pkgdata[m.group(1)] = m.group(2).encode()
                if "PV" in pkgdata and "PR" in pkgdata:
                    pv = pkgdata["PV"].decode()
                    pr = pkgdata["PR"].decode()
                    if "PE" in pkgdata:
                        pe = pkgdata["PE"].decode()
                        version += pe+":"
                    version += pv + "-" + pr
                fw.write(pkg +"=" +version+"\n")
            else:
                bb.note("[custom-rootfs] Version details of %s are not avilable in runtime pkgdata"%pkg)
                bb.note("[custom-rootfs] Check from IPK info")
                m_pkggrp.append(pkg)
    if m_pkggrp:
        get_pkg_install_version(d,release_data_file, m_pkggrp)
}
do_rootfs[prefuncs] += "do_update_install_pkgs_with_version"

do_update_opkg_config[vardepsexclude] = "BB_TASKDEPDATA"
# Customising the opkg configuartion to handle IPKSs from both
# remote server and the local build server
python do_update_opkg_config () {
    import re

    taskdepdata = d.getVar("BB_TASKDEPDATA", False)
    pkg_archs = d.getVar("ALL_MULTILIB_PACKAGE_ARCHS")
    current_taskname = d.getVar("BB_RUNTASK")
    pn = d.getVar("PN")
    begin = None
    deps_list = set()

    for dep in taskdepdata:
        data = taskdepdata[dep]
        if data[1] == current_taskname and data[0] == pn:
            begin = dep
            break
    if begin:
        begin = [begin]
        checked = set(begin)
        while begin:
            next_level = []
            for next_dep in begin:
                # Get the list of sub-dependencies from index 3
                sub_deps = taskdepdata[next_dep][3]
                # Iterate over sub-dependencies and process them
                for dep in sub_deps:
                    if taskdepdata[dep][0] != pn:
                        if "do_package_write_ipk" in dep:
                            deps_list.add(dep)
                    elif dep not in checked:
                        next_level.append(dep)
                        checked.add(dep)
            begin = next_level

    availabe_archs = []
    deploy_dir = d.getVar("DEPLOY_DIR_IPK")
    if os.path.exists(deploy_dir):
        entries = os.listdir(deploy_dir)
        for entry in entries:
            if os.path.isdir(os.path.join(deploy_dir, entry)):
                availabe_archs.append(entry)

    feed_arch_list = []
    for dep in sorted(deps_list):
        taskdata = taskdepdata[dep][0]
        for arch in pkg_archs.split():
             if arch == "all":
                 pkgarch = "allarch"
             else:
                 pkgarch = arch

             manifest = d.expand("${SSTATE_MANIFESTS}/manifest-%s-%s.%s" % (pkgarch, taskdata, "package_write_ipk"))
             if os.path.exists(manifest):
                 if arch not in feed_arch_list:
                     feed_arch_list.append(arch)
                 if arch in availabe_archs:
                     availabe_archs.remove(arch)
                     break
        if not availabe_archs:
             break

    bb.note("[update_opkg_config] feed arch list : %s"%feed_arch_list)
    ipk_feed_uris = []
    feed_uri = ""
    entry = (d.getVar("STACK_LAYER_EXTENSION") or "").split(" ")

    for arch in pkg_archs.split():
        feed_from_server = False
        for line in (d.getVar('IPK_FEED_URIS') or "").split():
            feed_match = re.match(r"^[ \t]*(.*)##([^ \t]*)[ \t]*$", line)
            if feed_match is not None:
                feed_name = feed_match.group(1)
                if feed_name == arch and  arch not in entry:
                    feed_from_server = True
                    ipk_feed_uris.append(line)
                    break
        if (arch not in feed_arch_list) or (feed_from_server):
            continue
        pkgs_dir = os.path.join(d.getVar("DEPLOY_DIR_IPK"), arch)
        if os.path.exists(pkgs_dir):
            pkgs_dir = os.path.join(d.getVar('WORKDIR'),"oe-rootfs-repo/%s"%arch)
            if not os.path.exists(pkgs_dir):
                bb.utils.mkdirhier(pkgs_dir)
            feed_uri = arch+"##"+"file:"+pkgs_dir+"\n"
            ipk_feed_uris.append(feed_uri)

    d.setVar("IPK_FEED_URIS"," ".join(ipk_feed_uris))

    d.setVar('BUILD_IMAGES_FROM_FEEDS', "1")
}

python do_copy_boot_files(){
    import shutil
    boot_dir = os.path.join(d.getVar("SYSROOT_IPK"),"%s"%d.getVar("IMAGEDEST"))
    if os.path.exists(boot_dir):
        img_deploy_dir = d.getVar("DEPLOY_DIR_IMAGE")
        if not os.path.exists(img_deploy_dir):
            bb.utils.mkdirhier(img_deploy_dir)
        for item in os.listdir(boot_dir):
            src_item = os.path.join(boot_dir, item)
            dst_item = os.path.join(img_deploy_dir, item)
            if not os.path.exists(dst_item):
                if os.path.isdir(src_item):
                    shutil.copytree(src_item, dst_item)
                    bb.note(f"Directory copied: {src_item} -> {dst_item}")
                else:
                    shutil.copy(src_item, dst_item)
                    bb.note(f"File copied: {src_item} -> {dst_item}")
            else:
                bb.note(f"Skipped (already exists): {dst_item}")
}
addtask do_copy_boot_files after do_rootfs before do_image_complete

do_rootfs[prefuncs] += "do_update_opkg_config"
do_rootfs[depends] += "shadow-native:do_populate_sysroot"
do_rootfs[network] = "1"
do_copy_boot_files[nostamp] = "1"
