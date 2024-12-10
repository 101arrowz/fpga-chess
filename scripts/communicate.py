# WIP

import wave
import serial
import sys
from threading import Thread

# set according to your system!
# CHANGE ME
SERIAL_PORTNAME = "/dev/cu.usbserial-210292AE394A1"
BAUD = 115200
ser = serial.Serial(SERIAL_PORTNAME,BAUD)
ser.timeout = 0.1
killed = False
print("Serial port initialized")

def write(inp):
    ser.write(inp.encode('utf-8'))

def read():
    while not killed:
        val = ser.read()
        if(len(val)==0):
            continue
        sys.stdout.write(val.decode('utf-8'))

Thread(target=read, daemon=True).start()

try:
    while True:
        line = sys.stdin.readline()
        write(line)
finally:
    killed = True
