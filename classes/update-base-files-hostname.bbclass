# ------------------------------------------------------------------------
# File: classes/update-base-files-hostname.bbclass
# Author: Akhil Babu
# Date: 2024-06-30
# Description: Update the hostname entry in /etc/hostname and /etc/hosts 
# to MACHINE name. This is usefull in the cases where base-files is 
# precompiled based on a specific machine architecure and delivered as IPK 
# and that same IPK is shared between different products
# ------------------------------------------------------------------------

ROOTFS_POSTPROCESS_COMMAND += ' update_hostname; '

update_hostname() {
    HOSTNAMEFILE="/etc/hostname"
    HOSTSFILE="/etc/hosts"

    if [ -n "${IMAGE_ROOTFS}" -a -d "${IMAGE_ROOTFS}" ]; then
        if [ -f "${IMAGE_ROOTFS}${HOSTNAMEFILE}" ]; then
            CURRENTHOSTNAME=`cat ${IMAGE_ROOTFS}/etc/hostname`
            if [ -z "${CURRENTHOSTNAME}" ]; then
                bbnote "update_hostname : Not updating hostname as current hostname is empty"
            elif [ "${CURRENTHOSTNAME}" != "${MACHINE}" ]; then
                bbnote "update_hostname : Updating hostname $CURRENTHOSTNAME to ${MACHINE}"
                sed -i "s/${CURRENTHOSTNAME}/${MACHINE}/g" ${IMAGE_ROOTFS}/etc/hostname
                sed -i "s/${CURRENTHOSTNAME}/${MACHINE}/g" ${IMAGE_ROOTFS}/etc/hosts
            else
                bbnote "update_hostname : Not updating hostname as current hostname is ${CURRENTHOSTNAME} same as MACHINE name ${MACHINE}"
            fi
        else
            bbnote "update_hostname : ${HOSTNAMEFILE} not found in ${IMAGE_ROOTFS}"
        fi
    else
        bbnote "update_hostname : IMAGE_ROOTFS not found"
    fi
}
