FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://aie.cdo.device.partition.reset.bin \
            file://aie.merged.cdo.bin"

python do_configure:append() {
    #import os
    #import shutil

    workdir = d.getVar('WORKDIR')
    b = d.getVar('B')

    for f in ['aie.cdo.device.partition.reset.bin', 'aie.merged.cdo.bin']:
        src = os.path.join(workdir, f)
        dst = os.path.join(b, f)
        shutil.copyfile(src, dst)
        bb.note('VD100 AIE: copied %s -> %s' % (src, dst))

    fp = d.getVar('BIF_FILE_PATH')
    with open(fp, 'r') as fh:
        content = fh.read()

    content = content.rstrip()
    if content.endswith('}'):
        content = content[:-1]

    content += """
\timage {
\t\tname=aie_dev_part, id=0x18800000
\t\t{ type=cdo, file=aie.cdo.device.partition.reset.bin }
\t}
\timage {
\t\tname=aie_image, id=0x18800000
\t\t{ type=cdo, file=aie.merged.cdo.bin }
\t}
}"""

    with open(fp, 'w') as fh:
        fh.write(content)

    bb.note('VD100 AIE: BIF updated with aie_dev_part and aie_image')
}
