import wave
import serial
import sys

# set according to your system!
# CHANGE ME
SERIAL_PORTNAME = "COM4"
BAUD = 115200
ser = serial.Serial(SERIAL_PORTNAME,BAUD)
ser.timeout=0.1
print("Serial port initialized")

def write(inp):
    ser.write(inp.encode('utf-8'))
def read():
    res=""
    while True:
        val = ser.read()
        if(len(val)==0):
            break
        res+=val.decode('utf-8')
    return res

write("uci\n")
print(read())
        

if __name__ == "__main__":
    #if (len(sys.argv)<2):
    #    print("Usage: python3 send_wav.py <filename>")
    #    exit()
    #filename = sys.argv[1]
    #send_wav(filename)
    pass