def base_cmdline(d,cmd):
    import subprocess
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    msg = process.communicate()[0]
    if process.returncode == 0:
        bb.note("CMD : %s : Sucess"%(cmd))
    else:
        msg = process.stderr.read()
        bb.fatal("CMD : %s : Failed %s"%(cmd,str(msg)))

python do_ipk_download (){
    import subprocess
    import shutil
    import re

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

    if server_path:
        download_ipks_in_parallel(d, ipk_list, server_path)
}

def ipk_sysroot_creation(d):
    install_dir = d.expand("${D}${base_prefix}")
    arch = d.getVar('PACKAGE_ARCH')
    download_dir =  d.getVar("IPK_CACHE_DIR", True)
    if not os.path.exists(install_dir):
        bb.utils.mkdirhier(install_dir)
    ipk_list = get_ipk_list(d,arch)
    for ipk in ipk_list:
        source_name = os.path.join(download_dir, ipk)
        if "-dbg_" not in ipk:
            if not os.path.exists(source_name):
                bb.warn("[ipk_sysroot_creation] %s has not been downloaded. Check ..."%source_name)
            cmd = "ar x %s && tar -C %s --no-same-owner -xpf data.tar.xz && rm data.tar.xz && rm -rf control.tar.gz && rm -rf debian-binary"%(source_name, install_dir)
            base_cmdline(d, cmd)

    bb.build.exec_func("sysroot_stage_all", d)
    multiprov = d.getVar("BB_MULTI_PROVIDER_ALLOWED").split()
    provdir = d.expand("${SYSROOT_DESTDIR}${base_prefix}/sysroot-providers/")
    bb.utils.mkdirhier(provdir)
    pn = d.getVar("PN")
    for p in d.getVar("PROVIDES").split():
        if p in multiprov:
            continue
        p = p.replace("/", "_")
        with open(provdir + p, "w") as f:
            f.write(pn)

# Function to download multiple ipk files in parallel
def download_ipks_in_parallel(d, ipk_list, server_path):
    import multiprocessing

    def split_into_batches(lst, batch_size=10):
        for i in range(0, len(lst), batch_size):
            yield lst[i:i + batch_size]

    if len(ipk_list) == 0:
        return

    batch_size = 100
    for ipk_batch in split_into_batches(ipk_list, batch_size=batch_size):
        processes = []
        for ipk in ipk_batch:
            p = multiprocessing.Process(target=download_ipk, args=(d, ipk, server_path, ))
            processes.append(p)
            p.start()
        for process in processes:
            process.join()

# Do sequential ipk download
def download_ipk(d, ipk, server_path):
    download_dir = d.getVar("IPK_CACHE_DIR", True)
    if not os.path.exists(download_dir):
        bb.utils.mkdirhier(download_dir)
    ipk_dl_path = os.path.join(download_dir,ipk)
    if not os.path.exists(ipk_dl_path):
        if server_path.startswith("file:"):
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
