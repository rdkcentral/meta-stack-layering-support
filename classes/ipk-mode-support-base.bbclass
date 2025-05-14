def base_cmdline(d,cmd):
    import subprocess
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    msg = process.communicate()[0]
    if process.returncode == 0:
        bb.note("CMD : %s : Sucess"%(cmd))
    else:
        msg = process.stderr.read()
        bb.fatal("CMD : %s : Failed %s"%(cmd,str(msg)))

def ipk_download(d):
    import subprocess
    import shutil
    import re

    arch = d.getVar('PACKAGE_ARCH')
    deploy_dir = d.getVar("DEPLOY_DIR_IPK")
    ipk_deploy_path = os.path.join(deploy_dir, arch)
    if not os.path.exists(ipk_deploy_path):
        bb.utils.mkdirhier(ipk_deploy_path)

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
        download_ipks_in_parallel(d, ipk_list, server_path, arch, ipk_deploy_path)
        manifest_name = d.getVar("SSTATE_MANFILEPREFIX", True) + ".package_write_ipk"
        bb.utils.mkdirhier(os.path.dirname(manifest_name))
        manifest_file = open(manifest_name, "w")

        for ipk in ipk_list:
            manifest_file.write(os.path.join(ipk_deploy_path, ipk) + "\n")

        manifest_file.close()

# Function to download multiple ipk files in parallel
def download_ipks_in_parallel(d, ipk_list, server_path, arch, ipk_deploy_path):
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
            p = multiprocessing.Process(target=download_ipk, args=(d, ipk, server_path, arch, ipk_deploy_path, ))
            processes.append(p)
            p.start()
        for process in processes:
            process.join()

# Do sequential ipk download
def download_ipk(d, ipk, server_path, arch, ipk_deploy_path):
    deploy_dir = d.getVar("DEPLOY_DIR_IPK")
    download_dir = d.getVar("IPK_CACHE_DIR", True)
    if not os.path.exists(download_dir):
        bb.utils.mkdirhier(download_dir)
    ipk_dl_path = os.path.join(download_dir,ipk)
    if not os.path.exists(ipk_dl_path):
        if server_path.startswith("file:"):
            shutil.copy(server_path[5:]+"/"+ipk, download_dir)
        else:
            ipk_url = server_path+"/"+ipk
            cmd = ["wget", ipk_url, f"--directory-prefix={download_dir}"]
            base_cmdline(d, cmd)
    if os.path.exists(ipk_deploy_path+"/%s"%ipk):
        os.unlink(ipk_deploy_path+"/%s"%ipk)
    os.link(ipk_dl_path, ipk_deploy_path+"/%s"%ipk)
