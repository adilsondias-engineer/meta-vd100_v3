FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://bsp.cfg \
	   file://0002-debug-ai-engine-clock.patch \
    	   "
KERNEL_FEATURES:append = " bsp.cfg"

