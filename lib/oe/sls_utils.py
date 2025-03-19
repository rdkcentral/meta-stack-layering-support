
# Create the opkg configuration with remote feeds
def sls_opkg_conf (d, conf):
    import re
    archs = d.getVar("ALL_MULTILIB_PACKAGE_ARCHS")
    with open(conf, "w") as file:
        priority = 5
        arch_priority = {}
        for arch in archs.split():
            if d.getVar('OPKG_ARCH_PRIORITY:%s'%arch):
                custom_priority = int(d.getVar('OPKG_ARCH_PRIORITY:%s'%arch))
                if custom_priority in arch_priority:
                    bb.fatal("Archs %s and %s having same priority %d. Should provide unique priority for each archs"%(arch, arch_priority[custom_priority],custom_priority))
                else:
                    arch_priority[custom_priority] = arch
            else:
                if priority in arch_priority:
                    bb.fatal("Archs %s and %s having same priorityi %d. Should provide unique priority for each archs"%(arch, arch_priority[custom_priority],priority))
                    # This is to store different archs have same priority
                else:
                    arch_priority[priority] = arch
                priority += 5

        if arch_priority:
            sorted_arch = sorted(arch_priority.items())
            for priority, arch in sorted_arch:
                file.write("arch %s %d\n" % (arch, priority))

        for line in (d.getVar('IPK_FEED_URIS') or "").split():
            feed = re.match(r"^[ \t]*(.*)##([^ \t]*)[ \t]*$", line)
            if feed is not None:
                arch_name = feed.group(1)
                arch_uri = feed.group(2)
                bb.note("[deps-resolver] Add %s feed with URL %s" % (arch_name, arch_uri))
                file.write("src/gz %s %s\n" % (arch_name, arch_uri))

