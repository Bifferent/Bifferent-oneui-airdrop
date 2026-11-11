
import struct, sys, os

GEOM_OFF = 4096
LP_GEOM_MAGIC = 0x616c4467

class Extent:
    __slots__=("num_sectors","target_type","target_data","target_source")

def read_geometry(f):
    f.seek(GEOM_OFF)
    d = f.read(4096)
    magic, struct_size = struct.unpack_from('<II', d, 0)
    if magic != LP_GEOM_MAGIC:
        raise SystemExit("bad geometry magic %08x" % magic)
    metadata_max_size, metadata_slot_count, logical_block_size = struct.unpack_from('<III', d, 40)
    return dict(max_size=metadata_max_size, slots=metadata_slot_count, lbs=logical_block_size)

def read_metadata(f, g, slot=0):
    off = 12288 + g['max_size']*slot
    f.seek(off)
    d = f.read(g['max_size'])
    magic, major, minor, header_size = struct.unpack_from('<IHHI', d, 0)
    if magic != 0x414c5030:
        raise SystemExit("bad metadata magic %08x at slot %d" % (magic, slot))
    tables_size = struct.unpack_from('<I', d, 44)[0]
    toff = 80
    tables = {}
    for name in ("partitions","extents","groups","block_devices"):
        o,n,es = struct.unpack_from('<III', d, toff)
        toff += 12
        tables[name] = (o,n,es)
    base = header_size
    parts = []
    o,n,es = tables['partitions']
    for i in range(n):
        p = d[base+o+i*es: base+o+(i+1)*es]
        nm = p[:36].split(b'\0')[0].decode()
        attrs, first, num, grp = struct.unpack_from('<IIII', p, 36)
        parts.append(dict(name=nm, attrs=attrs, first=first, num=num, group=grp))
    exts = []
    o,n,es = tables['extents']
    for i in range(n):
        e = d[base+o+i*es: base+o+(i+1)*es]
        ns, tt, td, ts = struct.unpack_from('<QIQI', e, 0)
        x = Extent.__new__(Extent)
        x.num_sectors, x.target_type, x.target_data, x.target_source = ns, tt, td, ts
        exts.append(x)
    return parts, exts

def main():
    img = sys.argv[1]
    cmd = sys.argv[2] if len(sys.argv)>2 else "list"
    f = open(img,'rb')
    g = read_geometry(f)
    parts, exts = read_metadata(f, g)
    if cmd == "list":
        print("geometry:", g, "partitions:", len(parts))
        for p in parts:
            sectors = sum(exts[p['first']+i].num_sectors for i in range(p['num']))
            print("%-24s attrs=%08x extents=%d size=%.1f MiB group=%d" % (p['name'], p['attrs'], p['num'], sectors*512/1048576, p['group']))
    elif cmd == "extract":
        want = sys.argv[3]; out = sys.argv[4]
        p = next((x for x in parts if x['name']==want), None)
        if not p: raise SystemExit("no such partition "+want)
        with open(out,'wb') as o:
            for i in range(p['num']):
                e = exts[p['first']+i]
                if e.target_type != 0: raise SystemExit("non-linear extent")
                f.seek(e.target_data*512)
                remaining = e.num_sectors*512
                while remaining:
                    chunk = f.read(min(remaining, 8*1024*1024))
                    if not chunk: raise SystemExit("short read")
                    o.write(chunk); remaining -= len(chunk)
        print("wrote", out, os.path.getsize(out))
    f.close()

main()
