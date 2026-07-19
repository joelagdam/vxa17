#!/usr/bin/env python3
"""Unpack/repack Android boot images (v0/v1/v2)."""

import argparse
import os
import struct

def page_align(n, page_size):
    return (n + page_size - 1) // page_size * page_size

# v0 header offsets
O_MAGIC = 0       # 8 bytes
O_KERNEL_SZ = 8   # I
O_KERNEL_ADDR = 12# I
O_RAMDISK_SZ = 16 # I
O_RAMDISK_ADDR=20 # I
O_PAGE_SZ = 36    # I
O_HDR_VER = 40    # I
# v1 starts at 1632 (after extra_cmdline[1024])
O_REC_DTBO_SZ = 1632   # I
O_REC_DTBO_OFF = 1636  # Q
O_HDR_SZ = 1644        # I
# v2 starts at 1648
O_DTB_SZ = 1648         # I
O_DTB_ADDR = 1652       # Q

def read_header(data):
    magic = data[O_MAGIC:O_MAGIC+8]
    kernel_sz = struct.unpack_from('<I', data, O_KERNEL_SZ)[0]
    ramdisk_sz = struct.unpack_from('<I', data, O_RAMDISK_SZ)[0]
    page_sz = struct.unpack_from('<I', data, O_PAGE_SZ)[0]
    hdr_ver = struct.unpack_from('<I', data, O_HDR_VER)[0]
    if hdr_ver >= 1:
        hdr_sz = struct.unpack_from('<I', data, O_HDR_SZ)[0]
    else:
        hdr_sz = page_sz
    return magic, kernel_sz, ramdisk_sz, page_sz, hdr_ver, hdr_sz


def unpack(args):
    with open(args.bootimg, 'rb') as f:
        data = f.read()
    
    magic, kernel_sz, ramdisk_sz, page_sz, hdr_ver, hdr_sz = read_header(data)
    
    os.makedirs(args.out, exist_ok=True)
    
    off = page_align(hdr_sz, page_sz)
    kernel = data[off:off + kernel_sz]
    off = page_align(off + kernel_sz, page_sz)
    ramdisk = data[off:off + ramdisk_sz]
    off = page_align(off + ramdisk_sz, page_sz)
    trailer = data[off:]
    
    open(os.path.join(args.out, 'kernel'), 'wb').write(kernel)
    open(os.path.join(args.out, 'ramdisk'), 'wb').write(ramdisk)
    open(os.path.join(args.out, 'trailer'), 'wb').write(trailer)
    open(os.path.join(args.out, 'header.bin'), 'wb').write(data[:hdr_sz])
    
    kernel_addr = struct.unpack_from('<I', data, O_KERNEL_ADDR)[0]
    ramdisk_addr = struct.unpack_from('<I', data, O_RAMDISK_ADDR)[0]
    
    with open(os.path.join(args.out, 'meta.txt'), 'w') as f:
        f.write(f'page_size={page_sz}\n')
        f.write(f'header_version={hdr_ver}\n')
        f.write(f'hdr_size={hdr_sz}\n')
        f.write(f'kernel_size={kernel_sz}\n')
        f.write(f'kernel_addr=0x{kernel_addr:x}\n')
        f.write(f'ramdisk_size={ramdisk_sz}\n')
        f.write(f'ramdisk_addr=0x{ramdisk_addr:x}\n')
        f.write(f'trailer_size={len(trailer)}\n')
    
    print(f'Unpacked to {args.out}/')
    print(f'  header: v{hdr_ver} ({hdr_sz} bytes)')
    print(f'  kernel: {len(kernel)} bytes')
    print(f'  ramdisk: {len(ramdisk)} bytes')
    print(f'  trailer: {len(trailer)} bytes')
    print(f'  page_size: {page_sz}')


def repack(args):
    header = open(os.path.join(args.dir, 'header.bin'), 'rb').read()
    
    meta = {}
    with open(os.path.join(args.dir, 'meta.txt')) as f:
        for line in f:
            k, v = line.strip().split('=', 1)
            meta[k] = v
    
    page_sz = int(meta['page_size'])
    hdr_sz = int(meta['hdr_size'])
    
    kernel_path = args.kernel or os.path.join(args.dir, 'kernel')
    ramdisk_path = args.ramdisk or os.path.join(args.dir, 'ramdisk')
    
    kernel = open(kernel_path, 'rb').read()
    ramdisk = open(ramdisk_path, 'rb').read()
    
    trailer_path = os.path.join(args.dir, 'trailer')
    trailer = b''
    if os.path.exists(trailer_path):
        trailer = open(trailer_path, 'rb').read()
    
    # Patch header with new sizes
    hdr = bytearray(header)
    struct.pack_into('<I', hdr, O_KERNEL_SZ, len(kernel))
    struct.pack_into('<I', hdr, O_RAMDISK_SZ, len(ramdisk))
    
    with open(args.output, 'wb') as f:
        # Write header and pad to page boundary
        f.write(bytes(hdr))
        pos = f.tell()
        pad = page_align(pos, page_sz) - pos
        if pad:
            f.write(b'\x00' * pad)
        # Write kernel (now starts at page-aligned offset)
        f.write(kernel)
        pos = f.tell()
        pad = page_align(pos, page_sz) - pos
        if pad:
            f.write(b'\x00' * pad)
        # Write ramdisk
        f.write(ramdisk)
        pos = f.tell()
        pad = page_align(pos, page_sz) - pos
        if pad:
            f.write(b'\x00' * pad)
        # Write trailer (DTB)
        f.write(trailer)
    
    print(f'Repacked to {args.output}')
    print(f'  kernel: {len(kernel)} bytes (was {meta["kernel_size"]})')
    print(f'  ramdisk: {len(ramdisk)} bytes')
    print(f'  trailer: {len(trailer)} bytes')


def info(args):
    with open(args.bootimg, 'rb') as f:
        data = f.read()
    magic, kernel_sz, ramdisk_sz, page_sz, hdr_ver, hdr_sz = read_header(data)
    kernel_addr = struct.unpack_from('<I', data, O_KERNEL_ADDR)[0]
    ramdisk_addr = struct.unpack_from('<I', data, O_RAMDISK_ADDR)[0]
    off = page_align(hdr_sz, page_sz)
    kernel = data[off:off + kernel_sz]
    off = page_align(off + kernel_sz, page_sz)
    ramdisk = data[off:off + ramdisk_sz]
    off = page_align(off + ramdisk_sz, page_sz)
    trailer = data[off:]
    cmdline = data[64:64+512].rstrip(b'\x00').decode('ascii', errors='replace')
    print(f'Magic: {"ANDROID!" if magic[:8] == b"ANDROID!" else magic[:8]!r}')
    print(f'Header: v{hdr_ver} ({hdr_sz} bytes)')
    print(f'Kernel: {kernel_sz} bytes @ 0x{kernel_addr:08x}')
    print(f'Ramdisk: {ramdisk_sz} bytes @ 0x{ramdisk_addr:08x}')
    print(f'Trailer: {len(trailer)} bytes')
    print(f'Page size: {page_sz}')
    print(f'Cmdline: {cmdline[:160]}...')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    sp = p.add_subparsers()
    up = sp.add_parser('unpack')
    up.add_argument('bootimg')
    up.add_argument('-o', '--out', default='bootimg_out')
    up.set_defaults(func=unpack)
    rp = sp.add_parser('repack')
    rp.add_argument('-d', '--dir', default='bootimg_out')
    rp.add_argument('-k', '--kernel')
    rp.add_argument('-r', '--ramdisk')
    rp.add_argument('-o', '--output', default='boot_new.img')
    rp.set_defaults(func=repack)
    ip = sp.add_parser('info')
    ip.add_argument('bootimg')
    ip.set_defaults(func=info)
    args = p.parse_args()
    if hasattr(args, 'func'):
        args.func(args)
    else:
        p.print_help()
