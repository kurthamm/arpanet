#!/usr/bin/env python3
# Unpack a SIMH PDP-10 disk image (36-bit words) as TOPS-20 7-bit ASCII (5 chars/word)
# and find OPERATOR + nearby strings (to locate the plaintext password).
import sys,re
path="/home/deltaprism/arpanet/mini/host69-bbn-tenex/kit-cache/build-tenex/t20v3/dsk/kla_psv3_0.rp06"
# try several word encodings; pick whichever yields readable OPERATOR
def words_be8(buf):
    for i in range(0,len(buf)-7,8):
        yield int.from_bytes(buf[i:i+8],'big')
def words_le8(buf):
    for i in range(0,len(buf)-7,8):
        yield int.from_bytes(buf[i:i+8],'little')
def unpack7(w):
    # low 36 bits, 5 seven-bit bytes, high-to-low (TOPS-20 ASCII)
    w&=0o777777777777
    return bytes([(w>>29)&0x7f,(w>>22)&0x7f,(w>>15)&0x7f,(w>>8)&0x7f,(w>>1)&0x7f])
data=open(path,'rb').read()
for name,gen in (("be8",words_be8),("le8",words_le8)):
    txt=bytearray()
    for w in gen(data):
        txt+=unpack7(w)
    s=txt.decode('latin-1')
    n=s.count('OPERATOR')
    print(f"encoding {name}: OPERATOR occurrences = {n}")
    if n:
        for m in re.finditer('OPERATOR',s):
            ctx=s[max(0,m.start()-40):m.start()+80]
            ctx=''.join(c if 32<=ord(c)<127 else '.' for c in ctx)
            print("  ...",ctx)
        break
