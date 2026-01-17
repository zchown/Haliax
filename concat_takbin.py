import argparse
import struct

MAGIC = b"TAKDATA1"

def read_header(f):
    magic = f.read(8)
    if magic != MAGIC:
        raise ValueError(f"Bad magic: {magic!r}")
    channels = struct.unpack("<I", f.read(4))[0]
    _count = struct.unpack("<I", f.read(4))[0]
    return channels

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("inputs", nargs="+")
    args = ap.parse_args()

    channels0 = None
    bodies = []

    for path in args.inputs:
        with open(path, "rb") as f:
            ch = read_header(f)
            if channels0 is None:
                channels0 = ch
            elif ch != channels0:
                raise ValueError(f"Channel mismatch: {path} has {ch}, expected {channels0}")
            bodies.append(f.read())

    with open(args.out, "wb") as out:
        out.write(MAGIC)
        out.write(struct.pack("<I", channels0))
        out.write(struct.pack("<I", 0))
        for b in bodies:
            out.write(b)

    print("Wrote", args.out)

if __name__ == "__main__":
    main()

