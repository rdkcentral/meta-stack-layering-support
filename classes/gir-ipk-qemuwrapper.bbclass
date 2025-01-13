# -------------------------------------------
# File: classes/gir-ipk-qemuwrapper.bbclass
# Author: Sreejith Ravi
# Date: 2024-06-07
# Description : qemu wrapper functions
# -------------------------------------------

inherit qemu

def generate_wrapper(d):
    import os
    import stat

    # Generate qemu command line
    qemu_binary = qemu_wrapper_cmdline(
        d,
        d.getVar('STAGING_DIR_HOST'),
        [
            '$GIR_EXTRA_LIBS_PATH',
            '.libs',
            '%s/%s'%(d.getVar('STAGING_DIR_HOST'), d.getVar('libdir')),
            '%s/%s'%(d.getVar('STAGING_DIR_HOST'), d.getVar('base_libdir'))
        ]
    )

    # Generating g-ir-scanner-qemuwrapper
    wrapperfile = "%s/g-ir-scanner-qemuwrapper" %(d.getVar('STAGING_BINDIR'))
    with open (wrapperfile, 'w') as rsh:
       rsh.write("#!/bin/sh\n")
       rsh.write("export GIO_MODULE_DIR=%s/gio/modules-dummy\n"%d.getVar('STAGING_LIBDIR'))
       rsh.write("\n")
       rsh.write('''%s "$@"\n'''%qemu_binary)
       rsh.write('''if [ \$? -ne 0 ]; then\n''')
       rsh.write('''\t echo "If missing .so libraries, then set up GIR_EXTRA_LIBS_PATH in the recipe"\n''')
       rsh.write('''\t echo "(: GIR_EXTRA_LIBS_PATH=\"$""{B}/something/.libs\")"\n''')
       rsh.write('''\t exit 1\n''')
       rsh.write('''fi\n''')
    st = os.stat(wrapperfile)
    os.chmod(wrapperfile, st.st_mode | stat.S_IEXEC)

    # Generating g-ir-scanner-wrapper
    wrapperfile = "%s/g-ir-scanner-wrapper" %(d.getVar('STAGING_BINDIR'))
    with open (wrapperfile, 'w') as rsh:
       rsh.write("#!/bin/sh\n")
       rsh.write("export GI_SCANNER_DISABLE_CACHE=1\n")
       rsh.write("\n")
       rsh.write('''g-ir-scanner --lib-dirs-envvar=GIR_EXTRA_LIBS_PATH --use-binary-wrapper=%s/g-ir-scanner-qemuwrapper --use-ldd-wrapper=%s/g-ir-scanner-lddwrapper --add-include-path=%s/gir-1.0 --add-include-path=%s/gir-1.0 "$@"\n''' %(d.getVar('STAGING_BINDIR'), d.getVar('STAGING_BINDIR'), d.getVar('STAGING_DATADIR'), d.getVar('STAGING_LIBDIR')))

    st = os.stat(wrapperfile)
    os.chmod(wrapperfile, st.st_mode | stat.S_IEXEC)

    # Generating g-ir-compiler-qemuwrapper
    wrapperfile = "%s/g-ir-compiler-wrapper" %(d.getVar('STAGING_BINDIR'))
    with open (wrapperfile, 'w') as rsh:
       rsh.write("#!/bin/sh\n")
       rsh.write('''%s/g-ir-scanner-qemuwrapper %s/g-ir-compiler "$@"\n''' %(d.getVar('STAGING_BINDIR'),d.getVar('STAGING_BINDIR')))
    st = os.stat(wrapperfile)
    os.chmod(wrapperfile, st.st_mode | stat.S_IEXEC)
    
    # Generating g-ir-compiler-lddwrapper
    wrapperfile = "%s/g-ir-scanner-lddwrapper" %(d.getVar('STAGING_BINDIR'))
    with open (wrapperfile, 'w') as rsh:
       rsh.write("#!/bin/sh\n")
       rsh.write('''prelink-rtld --root=%s "$@"\n''' %(d.getVar('STAGING_DIR_HOST')))
    st = os.stat(wrapperfile)
    os.chmod(wrapperfile, st.st_mode | stat.S_IEXEC)


def generate_ldsoconf(d, ldsoconf):
    import os
    with open(ldsoconf, "w") as f:
        f.write("#!/bin/sh\n")
        f.write("mkdir -p %s%s\n"%(d.getVar('RECIPE_SYSROOT') , d.getVar('sysconfdir')))
        f.write("echo %s >> %s%s/ld.so.conf\n"%(d.getVar('base_libdir'),d.getVar('RECIPE_SYSROOT'),d.getVar('sysconfdir')))
        f.write("echo %s >> %s%s/ld.so.conf\n"%(d.getVar('libdir'),d.getVar('RECIPE_SYSROOT'),d.getVar('sysconfdir')))
    os.chmod(ldsoconf, 0o755)


def g_ir_cc_support(d, recipe_sysroot, pkg_pn):
    import subprocess
    ldsoconf = "%s%s/postinst-ldsoconf-%s" % (d.getVar('RECIPE_SYSROOT'),d.getVar('bindir'), d.getVar('PN'))
    cmd = "sed -i \
       -e \"s|g_ir_scanner=.*|g_ir_scanner=%s/g-ir-scanner-wrapper|\" \
       -e \"s|g_ir_compiler=.*|g_ir_compiler=%s/g-ir-compiler-wrapper|\" \
       %s%s/pkgconfig/gobject-introspection-1.0.pc" %(d.getVar('bindir'),d.getVar('bindir'), \
       d.getVar('RECIPE_SYSROOT'), d.getVar('libdir'))

    generate_wrapper(d)
    subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
    generate_ldsoconf(d,ldsoconf)
    subprocess.check_output(ldsoconf, shell=True, stderr=subprocess.STDOUT)
