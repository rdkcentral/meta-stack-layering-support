# ------------------------------------------------------------------------
# File: classes/custom-rootfs-creation.bbclass
# Author: Sreejith Ravi
# Date: 2024-06-21
# Description : Create custom opkg configuration and generate version info 
# for the packagegroups set in the IMAGE_INSTALL
# ------------------------------------------------------------------------
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
                pkgdata[m.group(1)] = decode(m.group(2))
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
            prefix = d.getVar('MLPREFIX') or ""
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
                        pkgdata[m.group(1)] = decode(m.group(2))
                if "PV" in pkgdata and "PR" in pkgdata:
                    pv = pkgdata["PV"]
                    pr = pkgdata["PR"]
                    if "PE" in pkgdata:
                        pe = pkgdata["PE"]
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
    deploy_dir = oe.path.join(d.getVar('WORKDIR'), "oe-rootfs-repo")
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
        if feed_from_server:
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

do_rootfs[prefuncs] += "do_update_opkg_config"
do_rootfs[depends] += "shadow-native:do_populate_sysroot"
