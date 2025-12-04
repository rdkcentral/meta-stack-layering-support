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

def base_cmdline(d,cmd):
    import subprocess
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    stdout, stderr = process.communicate()
    if process.returncode == 0:
        bb.note("CMD : %s : Success" % cmd)
    else:
        bb.fatal("CMD : %s : Failed %s" % (cmd, stderr.decode('utf-8', errors='replace')))

python do_get_alternative_pkg (){
    import glob
    alternatives_path = d.expand("${ALTERNATIVES_PKGS_LIST}")
    sysroot_path = d.expand("${SYSROOT_DESTDIR}${base_prefix}/var/lib/opkg/info")
    postinst_list = glob.glob(sysroot_path + "/*.postinst")
    if postinst_list:
        for p in postinst_list:
            with open(p, 'r') as file:
                for line in file:
                    if "update-alternatives --install" in line:
                        parts = line.split()
                        alt = parts[3]
                        if not os.path.exists(alternatives_path):
                            bb.utils.mkdirhier(alternatives_path)
                        alter_file = os.path.join(alternatives_path, alt)
                        open(alter_file, 'w').close()
    else:
        bb.note("No alternative pkgs set for this")
}

SSTATETASKS += "do_get_alternative_pkg"
do_get_alternative_pkg[dirs] = "${ALTERNATIVES_PKGS_LIST}"
do_get_alternative_pkg[sstate-inputdirs] = "${ALTERNATIVES_PKGS_LIST}"
do_get_alternative_pkg[sstate-outputdirs] = "${SYSROOT_ALTERNATIVES}/${PN}"
do_get_alternative[cleandirs] = "${SYSROOT_ALTERNATIVES}/${PN}"

python do_get_alternative_pkg_setscene () {
    sstate_setscene(d)
}
addtask do_get_alternative_pkg_sysroot_setscene
do_package_qa[recrdeptask] += "do_get_alternative_pkg"
do_ipk_download[network] = "1"
python do_ipk_download (){
    import subprocess
    import shutil
    import re
    import os

    arch = d.getVar('PACKAGE_ARCH')

    ipk_list = get_ipk_list(d,arch)
    server_path = ""
    for line in (d.getVar('IPK_FEED_URIS') or "").split():
        feed = re.match(r"^[ \t]*(.*)##([^ \t]*)[ \t]*$", line)
        if feed is not None:
            arch_name = feed.group(1)
            arch_uri = feed.group(2)
            if arch == arch_name:
                server_path = arch_uri

    manifest_file = d.getVar("SSTATE_MANFILEPREFIX", True)+".packagedata"
    bb.utils.mkdirhier(os.path.dirname(manifest_file))
    open(manifest_file, 'w').close()
    manifest_file = d.getVar("SSTATE_MANFILEPREFIX", True)+".package_write_ipk"
    open(manifest_file, 'w').close()
    if server_path and ipk_list:
        oe.utils.multiprocess_launch(download_ipk, ipk_list, d, extraargs=(server_path, arch,d))
}

SSTATETASKS += "do_ipk_download"
do_ipk_download[dirs] = "${PKGWRITEDIRIPK}"
do_ipk_download[sstate-inputdirs] = "${PKGWRITEDIRIPK}"
do_ipk_download[sstate-outputdirs] = "${DEPLOY_DIR_IPK}"
do_ipk_download[cleandirs] = "${PKGWRITEDIRIPK}"
do_ipk_download[vardeps] += "PV PR"

python do_ipk_download_setscene () {
    manifest_file = d.getVar("SSTATE_MANFILEPREFIX", True)+".packagedata"
    bb.utils.mkdirhier(os.path.dirname(manifest_file))
    open(manifest_file, 'w').close()
    manifest_file = d.getVar("SSTATE_MANFILEPREFIX", True)+".package_write_ipk"
    open(manifest_file, 'w').close()
    sstate_setscene(d)
}
addtask do_ipk_download_setscene

def ipk_sysroot_creation(d):
    import subprocess
    import shutil
    install_dir = d.getVar("D", True)
    arch = d.getVar('PACKAGE_ARCH')
    pkgoutdir = d.getVar("PKGWRITEDIRIPK", True)
    download_dir = "%s/%s" % (pkgoutdir, arch)
    if os.path.exists(install_dir):
        shutil.rmtree(install_dir)
    ipk_install_list = []
    ipk_list = get_ipk_list(d,arch)
    opkg_cmd = bb.utils.which(os.getenv('PATH'), "opkg")
    for ipk in ipk_list:
        source_name = os.path.join(download_dir, ipk)
        if "-dbg_" not in ipk:
            if not os.path.exists(source_name):
                bb.fatal("[ipk_sysroot_creation] %s has not been downloaded. Check ..."%source_name)
            ipk_install_list.append(source_name)
    if not ipk_install_list:
        bb.note("[ipk_sysroot_creation] IPK list is empty")
        return
    opkg_conf = d.getVar("IPKGCONF_LAYERING")
    import oe.sls_utils
    oe.sls_utils.sls_opkg_conf (d, opkg_conf)
    opkg_args = "-f %s -o %s" %(opkg_conf,install_dir)
    cmd = '%s %s --volatile-cache --no-install-recommends --nodeps install ' % (opkg_cmd, opkg_args)
    ipk_install(d, cmd, ipk_install_list, install_dir)
    os.remove(opkg_conf)
    bb.build.exec_func("sysroot_stage_all", d)
    multiprov = d.getVar("BB_MULTI_PROVIDER_ALLOWED").split()
    provdir = d.expand("${SYSROOT_DESTDIR}${base_prefix}/sysroot-providers/")
    opkg_extra_src = d.expand("${D}${base_prefix}/var/lib/opkg/")
    if os.path.exists(opkg_extra_src):
        opkg_extra_dest = d.expand("${SYSROOT_DESTDIR}${base_prefix}/var/lib/opkg")
        bb.note("opkg_extra_dest : %s"%opkg_extra_dest)
        shutil.copytree(opkg_extra_src, opkg_extra_dest)
        old_name = d.expand("${SYSROOT_DESTDIR}${base_prefix}/var/lib/opkg/status")
        new_name = d.expand("${SYSROOT_DESTDIR}${base_prefix}/var/lib/opkg/${PN}.status")
        os.rename(old_name, new_name)
    bb.utils.mkdirhier(provdir)
    pn = d.getVar("PN")
    for p in d.getVar("PROVIDES").split():
        if p in multiprov:
            continue
        p = p.replace("/", "_")
        with open(provdir + p, "w") as f:
            f.write(pn)

# Do sequential ipk download
def download_ipk(ipk, server_path, arch, d):
    pkgoutdir = d.getVar("PKGWRITEDIRIPK", True)
    download_dir = "%s/%s" % (pkgoutdir, arch)
    if not os.path.exists(download_dir):
        bb.utils.mkdirhier(download_dir)
    ipk_dl_path = os.path.join(download_dir,ipk)
    if not os.path.exists(ipk_dl_path):
        if server_path.startswith("file:"):
            import shutil
            shutil.copy(server_path[5:]+"/"+ipk, download_dir)
        else:
            ipk_url = server_path+"/"+ipk
            cmd = "wget %s --directory-prefix=%s"%(ipk_url,download_dir)
            base_cmdline(d, cmd)

def copy_deploy_ipk(d):
    import shutil
    arch = d.getVar('PACKAGE_ARCH')
    ipk_outdir = os.path.join(d.getVar('PKGWRITEDIRIPK'),arch)
    if not os.path.exists(ipk_outdir):
        bb.utils.mkdirhier(ipk_outdir)

    download_dir = d.getVar("IPK_CACHE_DIR", True)

    ipk_list = get_ipk_list(d,arch)
    bb.note("[copy_deploy_ipk] ipk list : %s"%ipk_list)
    for ipk in ipk_list:
        src_path = os.path.join(download_dir,ipk)
        bb.note("[copy_deploy_ipk] ipk path : %s"%src_path)
        if os.path.exists(src_path):
            bb.note("[copy_deploy_ipk] copying : %s"%src_path)
            shutil.copy(src_path, ipk_outdir)
