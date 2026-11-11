
import struct, sys, os

SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW=0xCAC1; CHUNK_FILL=0xCAC2; CHUNK_DONT=0xCAC3; CHUNK_CRC=0xCAC4

def main(src, dst):
    fi = open(src,'rb'); fo = open(dst,'wb')
    hdr = fi.read(28)
    magic, major, minor, fhs, chs, blk, total_blks, total_chunks, csum = struct.unpack('<IHHHHIIII', hdr)
    assert magic == SPARSE_MAGIC, hex(magic)
    print("sparse: blk=%d total_blks=%d chunks=%d" % (blk, total_blks, total_chunks))
    for i in range(total_chunks):
        ch = fi.read(12)
        ctype, res, chunk_sz, total_sz = struct.unpack('<HHII', ch)
        data_sz = total_sz - 12
        if ctype == CHUNK_RAW:
            remaining = chunk_sz*blk
            while remaining:
                b = fi.read(min(remaining, 8<<20))
                if not b: raise SystemExit("short raw")
                fo.write(b); remaining -= len(b)
        elif ctype == CHUNK_FILL:
            fill = fi.read(4)
            fo.write(fill * (chunk_sz*blk//4))
        elif ctype == CHUNK_DONT:
            fo.seek(chunk_sz*blk, 1)
        elif ctype == CHUNK_CRC:
            fi.read(4)
        else:
            raise SystemExit("unknown chunk %x" % ctype)
    fo.truncate(total_blks*blk)
    fo.close(); fi.close()
    print("done", os.path.getsize(dst))

main(sys.argv[1], sys.argv[2])
