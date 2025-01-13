do_devel_create() {
    kerneldir="${D}/kernel-build/"
    kernelsrcdir="${D}/kernel-source/"

    # create the directory structure
    rm -rf $kerneldir
    rm -rf $kernelsrcdir
    mkdir -p $kerneldir
    mkdir -p $kernelsrcdir
    mkdir -p $kernelsrcdir/drivers

    cd ${STAGING_KERNEL_DIR}
    cp --parents $(find  -type f -name "Makefile*" -o -name "Kconfig*") $kernelsrcdir
    cp --parents $(find  -type f -name "makefile" -o -name "*.sh") $kernelsrcdir
    cp --parents $(find  -type f -name "Build" -o -name "Build.include") $kernelsrcdir
    cd ${STAGING_KERNEL_DIR}/drivers
    cp --parents $(find  -type f -name "*.h") $kernelsrcdir/drivers

    rm -rf $kerneldir/Documentation
    rm -rf $kerneldir/scripts
    rm -rf $kerneldir/include

    (
	cd ${STAGING_KERNEL_BUILDDIR}
        if [ -d arch/${ARCH}/include/generated ]; then
            mkdir -p $kerneldir/arch/${ARCH}/include/generated/
            cp -fR arch/${ARCH}/include/generated/* $kerneldir/arch/${ARCH}/include/generated/
        fi

	cp Module.symvers $kerneldir
	cp System.map* $kerneldir
	cp -a .config $kerneldir
	cp -a ${KERNEL_PACKAGE_NAME}-abiversion $kerneldir

        if [ -d arch/${ARCH}/scripts ]; then
            cp -a arch/${ARCH}/scripts $kerneldir/arch/${ARCH}
        fi

        cp -a include $kerneldir/include
    )

    (
        cd ${STAGING_KERNEL_DIR}/arch/${ARCH}
        cp --parents $(find  -type f -name "*lds") $kernelsrcdir/arch/${ARCH}
	
        cd ${STAGING_KERNEL_DIR}
        cp --parents $(find  -type f -name "*lds") $kerneldir

	cp -a scripts $kernelsrcdir

	if [ -d arch/${ARCH}/include ]; then
	    cp -a --parents arch/${ARCH}/include $kernelsrcdir/
	fi

	cp -a include $kernelsrcdir/

	if [ -d arch/${ARCH}/tools ]; then
	    mkdir -p $kernelsrcdir/arch/${ARCH}/tools/
	    cp arch/${ARCH}/tools/*mach-types* $kernelsrcdir/arch/${ARCH}/tools/
	fi

	cp -a --parents tools/include/tools/le_byteshift.h $kernelsrcdir/
	cp -a --parents tools/include/tools/be_byteshift.h $kernelsrcdir/

	if [ -d security/selinux/include ]; then
            cp -a --parents security/selinux/include/* $kernelsrcdir/
	fi
	if [ -d arch/${ARCH}/kernel/vdso ]; then
	    cp -a --parents arch/${ARCH}/kernel/vdso/*gettimeofday.* $kernelsrcdir
	    cp -a --parents arch/${ARCH}/kernel/vdso/*.S $kernelsrcdir
	    cp -a --parents arch/${ARCH}/kernel/vdso/*.sh $kernelsrcdir
	fi
	if [ -d lib/vdso/ ]; then
	    cp -a --parents lib/vdso/* $kernelsrcdir
	fi
	if [ -f gki_ext_module_config ]; then
	    cp gki_ext_module_config $kernelsrcdir
	fi
	if [ -f gki_ext_module_predefine ]; then
	    cp gki_ext_module_predefine $kernelsrcdir
	fi
    )

    touch -r $kernelsrcdir/Makefile $kerneldir/include/generated/uapi/linux/version.h
    cp $kerneldir/.config $kerneldir/auto.conf
}

addtask devel_create before do_package after do_install
PACKAGES:append = " ${KERNEL_PACKAGE_NAME}-devel"
FILES:${KERNEL_PACKAGE_NAME}-devel = "/kernel-source /kernel-build/"

