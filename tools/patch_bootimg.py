#!/usr/bin/env python3
"""
Auto-patch a stock boot.img with our compiled kernel (Image.gz).
Usage:
    python tools/patch_bootimg.py stock_boot.img -o patched_boot.img
"""
import argparse, os, shutil, struct, sys

DIR = os.path.dirname(os.path.abspath(__file__))
KERNEL_PATH = os.path.join(DIR, '..', 'outputs', 'kernel', 'Image.gz')

def page_align(n, p):
    return (n + p - 1) // p * p

def patch_bootimg(stock_img, kernel_path, output_path, keep_workdir=False):
    workdir = os.path.join(os.path.dirname(output_path) or '.', '.bootimg_work')
    if os.path.exists(workdir):
        shutil.rmtree(workdir)

    # Unpack stock boot
    ret = os.system(f'python "{DIR}/bootimg.py" unpack "{stock_img}" -o "{workdir}"')
    if ret != 0:
        print('ERROR: Failed to unpack boot image')
        sys.exit(1)

    # Read stock header info
    with open(os.path.join(workdir, 'meta.txt')) as f:
        meta = {}
        for line in f:
            k, v = line.strip().split('=', 1)
            meta[k] = v

    # Read new kernel
    with open(kernel_path, 'rb') as f:
        new_kernel = f.read()
    print(f'New kernel: {len(new_kernel)} bytes ({kernel_path})')

    # Check size: kernel must not exceed original
    orig_kernel_sz = int(meta['kernel_size'])
    if len(new_kernel) > orig_kernel_sz:
        print(f'WARNING: New kernel ({len(new_kernel)}) is larger than original ({orig_kernel_sz})')
        print(f'  Boot image may exceed partition size!')
        page_sz = int(meta['page_size'])
        hdr_sz = int(meta.get('hdr_size', page_sz))
        ramdisk_sz = int(meta['ramdisk_size'])
        trailer_sz = int(meta.get('trailer_size', 0))
        total = (
            hdr_sz +
            page_align(len(new_kernel), page_sz) +
            ramdisk_sz +
            trailer_sz
        )
        print(f'  Estimated total: {total} bytes ({total/1024/1024:.1f} MB)')

    # Repack with new kernel
    ret = os.system(
        f'python "{DIR}/bootimg.py" repack '
        f'-d "{workdir}" '
        f'-k "{kernel_path}" '
        f'-o "{output_path}"'
    )
    if ret != 0:
        print('ERROR: Failed to repack boot image')
        sys.exit(1)

    # Verify
    with open(output_path, 'rb') as f:
        data = f.read()
    hdr = data[:struct.unpack('<I', data[1644:1648])[0]]
    k_sz = struct.unpack('<I', data[8:12])[0]
    print(f'\nPatched boot image: {output_path}')
    print(f'  Size: {len(data)} bytes ({len(data)/1024/1024:.1f} MB)')
    print(f'  Kernel: {k_sz} bytes')
    print(f'  Ramdisk: {struct.unpack("<I", data[16:20])[0]} bytes')
    page_sz = struct.unpack('<I', data[36:40])[0]
    hdr_sz = struct.unpack('<I', data[1644:1648])[0]
    kernel_off = page_align(hdr_sz, page_sz)
    kernel_magic = data[kernel_off:kernel_off+2]
    print(f'  Kernel offset: {kernel_off} (magic: {kernel_magic.hex()})')
    if kernel_magic == b'\x1f\x8b':
        print(f'  Kernel format: gzip (correct)')
    else:
        print(f'  WARNING: Kernel doesn\'t start with gzip magic!')

    if not keep_workdir:
        shutil.rmtree(workdir)

def main():
    p = argparse.ArgumentParser(description='Patch a stock boot.img with our compiled kernel')
    p.add_argument('stock_boot', help='Path to stock boot.img')
    p.add_argument('-k', '--kernel', default=KERNEL_PATH,
                   help=f'Path to kernel Image.gz (default: {KERNEL_PATH})')
    p.add_argument('-o', '--output', default='boot_patched.img',
                   help='Output patched boot image (default: boot_patched.img)')
    p.add_argument('--keep-workdir', action='store_true',
                   help='Keep temporary work directory')
    args = p.parse_args()

    if not os.path.exists(args.stock_boot):
        print(f'ERROR: Stock boot image not found: {args.stock_boot}')
        sys.exit(1)
    if not os.path.exists(args.kernel):
        print(f'ERROR: Kernel not found: {args.kernel}')
        print(f'  Build the kernel first with build.sh')
        sys.exit(1)

    patch_bootimg(args.stock_boot, args.kernel, args.output, args.keep_workdir)

if __name__ == '__main__':
    main()
