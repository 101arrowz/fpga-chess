#!/Users/arjunb/.pyenv/versions/3.11.5/envs/6.205/bin/python
# WIP
from tendo import singleton
me = singleton.SingleInstance()

import wave
import serial
import os
import sys
from threading import Thread
from time import sleep

# set according to your system!
# CHANGE ME
SERIAL_PORTNAME = "/dev/cu.usbserial-210292AE394A1"
BAUD = 115200
ser = serial.Serial(SERIAL_PORTNAME,BAUD)
ser.timeout = 0.01
killed = False

def write(inp):
    ser.write(inp.encode('utf-8'))

log = open('hwlog', 'a+')
num_nl = 0

def read():
    global num_nl
    buf = ''
    while not killed:
        val = ser.read()
        if(len(val)==0):
            continue
        s = val.decode('utf-8')
        buf += s
        if "\n" in buf:
            print(buf, end='')
            sys.stdout.flush()
            log.write(f'[HWRES]: {list(buf)}\n')
            buf = ''
            log.flush()
            if "\n" in s:
                num_nl += 1

Thread(target=read, daemon=True).start()

is_waiting = False
log.write(f"[start pid {os.getpid()}]")
log.flush()
write("position startpos\n")
while True:
    line = input() + "\n"
    log.write(line)
    log.flush()
    if line.strip() == "quit":
        break
    if line.strip() == "isready":
        print("readyok")
        continue
    write(line)
