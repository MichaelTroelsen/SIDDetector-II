import re, sys
target = int(sys.argv[1], 16)
syms = {}
with open("siddetector.sym") as f:
    for line in f:
        m = re.match(r"\.label\s+(\S+)\s*=\s*\$([0-9a-f]+)", line)
        if m:
            syms[m.group(1)] = int(m.group(2), 16)
sorted_syms = sorted(syms.items(), key=lambda x: x[1])
for name, addr in sorted_syms:
    if abs(addr - target) < 0x40:
        print(f"${addr:04x} {name}")
