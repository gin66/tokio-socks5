#!/usr/bin/env python3
import time
import struct
import random
import socket
import hashlib
import configparser

config=configparser.ConfigParser()
config.read("config.ini")
HEADER=bytes.fromhex(config['Common']['HEADER_MAGIC'])
SEED=bytes.fromhex(config['Common']['HEADER_SEED'])

# Persistent data for watermark
wm_hgen = hashlib.blake2b(SEED)
wm_xm = bytearray(8)
wm_xmq = memoryview(wm_xm).cast('Q')

def watermark(a):
    mq = memoryview(a).cast('Q')
    wm_xmq[0] = mq[0] ^ mq[1] ^ mq[2]
    s = wm_hgen.copy()
    s.update(wm_xm)
    h = memoryview(s.digest()).cast('Q')
    mq[0] ^= h[0]
    mq[1] ^= h[1]
    mq[2] ^= h[0] ^ h[1]
    h.release()
    mq.release()

def mk_header(oid,oport,crc_payload):
    tx = time.time()
    t_s = int(tx)
    tx -= t_s
    t_4ms = int(tx*250)
    r = random.getrandbits(64)
    m = struct.pack("<4sLBBBBLQ",HEADER,t_s,t_4ms,oid,oport,0,crc_payload,r)
    return m

def decode_header(m):
    magic,t_s,t_4ms,oid,oport,_,crc_payload = struct.unpack_from("<4sLBBBBL",m)
    if magic == HEADER:
        tx = time.time()
        te = t_s+t_4ms/250
        dt = tx-te
        if abs(dt) < 10:
            return dt,oid,oport,crc_payload

def run():
    sock = socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    sock.bind(('0.0.0.0', 19841))
    sock.setblocking(True)
    while True:
        buf,address = sock.recvfrom(2048)
        if len(buf) >= 24:
            h = bytearray(buf[:24])
            watermark(h)
            h = decode_header(h)
            if h is not None:
                dt,oid,oport,crc_payload = h
                print('decoded:',dt,oid,oport)
            else:
                print('Cannot decode',address)

h = mk_header(1,0,0)
print(decode_header(h))

run()

a = bytearray(b'abcdefghijklmnop12345678')
print('original', a)
watermark(a)
print('watermarked', a)
watermark(a)
print('reconstructed', a)

a = bytearray(b'abcdefghijklmnop12345679')
watermark(a)
print('must be completely different to above watermarked:', a)

