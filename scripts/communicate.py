#!/Users/arjunb/.pyenv/versions/3.11.5/envs/6.205/bin/python
# WIP

import wave
import serial
import sys
from threading import Thread
from time import sleep

# set according to your system!
# CHANGE ME
SERIAL_PORTNAME = "/dev/cu.usbserial-210292AE394A1"
BAUD = 115200
ser = serial.Serial(SERIAL_PORTNAME,BAUD)
ser.timeout = 0
killed = False

def write(inp):
    ser.write(inp.encode('utf-8'))

# log = open('hwlog', 'a+')
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
            print(buf)
            sys.stdout.flush()
            buf = ''
            # log.write(f'[HWRES]: {buf}')
            # log.flush()
            if "\n" in s:
                num_nl += 1

Thread(target=read, daemon=True).start()

is_waiting = False

# write("position startpos\n")
while True:
    line = input() + "\n"
    # log.write(line)
    # log.flush()
    if line.strip() == "quit":
        break
    if line.strip() == "isready":
        print("readyok")
        continue
    if line.strip() == "uci":
        print("id name River")
        print("id author Arjun Barrett and Dylan Isaac")
        print("uciok")
        continue
    if line.strip() == "ucinewgame":
        continue
    if line.strip().startswith("position"):
        write(line)
    if line.strip().startswith("go"):
        write("go\n")