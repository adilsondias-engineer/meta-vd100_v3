# meta-vd100_v2/recipes-bsp/vd100-firmware/vd100-firmware.bb
SUMMARY = "VD100 PL LED firmware (PDI)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

DEPENDS = "sdt-artifacts"

do_install() {
    install -d ${D}/usr/lib/firmware/xilinx
    install -m 0644 ${RECIPE_SYSROOT}${datadir}/sdt/${MACHINE}/vpl_gen_fixed.pdi \
        ${D}/usr/lib/firmware/xilinx/vpl_gen_fixed.pdi
    install -m 0644 ${RECIPE_SYSROOT}${datadir}/sdt/${MACHINE}/vpl_gen_fixed.pdi \
        ${D}/usr/lib/firmware/vpl_gen_fixed.pdi
}

FILES:${PN} = "/usr/lib/firmware/vpl_gen_fixed.pdi \
               /usr/lib/firmware/xilinx/vpl_gen_fixed.pdi \
	      "
