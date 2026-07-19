import struct, os

# Re-extract original first
os.system('python tools/bootimg.py unpack "outputs/stock-boot-img/boot.img" -o outputs/stock-boot-img/unpacked 2>nul')

# Read the full trailer
trailer = open('outputs/stock-boot-img/unpacked/trailer', 'rb').read()
print(f'Original trailer: {len(trailer)} bytes')

# dtb_size from v2 header
hdr = open('outputs/stock-boot-img/unpacked/header.bin', 'rb').read()
dtb_sz = struct.unpack('<I', hdr[1648:1652])[0]
print(f'dtb_size from header: {dtb_sz}')

# DTB is at relative offset 4096 in trailer
# Keep: 4096 byte Qualcomm header + dtb_size bytes
min_trailer = 4096 + dtb_sz
aligned = (min_trailer + 4095) // 4096 * 4096
print(f'Min trailer: {min_trailer} -> aligned: {aligned}')

# Verify DTB at offset 4096
assert trailer[4096:4100] == b'\xd0\x0d\xfe\xed', 'DTB magic not at 4096'
print('DTB magic at offset 4096: OK')

# Truncate
open('outputs/stock-boot-img/unpacked/trailer', 'wb').write(trailer[:aligned])

# Repack
os.system('python tools/bootimg.py repack -d outputs/stock-boot-img/unpacked -k outputs/kernel/Image.gz -o outputs/boot_new.img 2>nul')

# Verify
with open('outputs/boot_new.img', 'rb') as f:
    d = f.read()

hdr_sz = struct.unpack('<I', d[1644:1648])[0]
k_sz = struct.unpack('<I', d[8:12])[0]
r_sz = struct.unpack('<I', d[16:20])[0]
ps = struct.unpack('<I', d[36:40])[0]

def align(n, p): return (n + p - 1) // p * p
k_pad = align(hdr_sz + k_sz, ps)
r_pad = align(k_pad + r_sz, ps)
trailer_start = r_pad
dtb_off = trailer_start + 4096
dtb_magic = d[dtb_off:dtb_off+4]
print(f'\nVerification:')
print(f'  hdr_sz={hdr_sz} k_sz={k_sz} r_sz={r_sz}')
print(f'  trailer_start={trailer_start}')
print(f'  DTB at offset {dtb_off}')
print(f'  DTB magic: {dtb_magic.hex()} (expect d00dfeed)')
print(f'  Match: {dtb_magic == b"\\xd0\\x0d\\xfe\\xed"}')
print(f'  File size: {len(d)} bytes ({len(d)/1024/1024:.1f} MB)')
print(f'  Partition limit: 134217728 bytes (128 MB)')
print(f'  Fits: {len(d) <= 134217728}')
