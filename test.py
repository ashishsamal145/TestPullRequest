from threading import *
import time


def trafficpolice():
    while True:
        time.sleep(10)
        print("Traffic Police Giving GREEN Signal") #2
        event.set()
        time.sleep(20)
        print("Traffic Police Giving RED Signal")
        event.clear()

def driver():
    num=0
    while True:
        print("Drivers waiting for GREEN Signal") #1
        event.wait()
        print("Traffic Signal is GREEN...Vehicles can move") #3
        while event.is_set():
            num=num+1
            print("Vehicle No:",num,"Crossing the Signal") #4
            time.sleep(1)
        print("Traffic Signal is RED...Drivers have to wait") #5
event=Event()
t1=Thread(target=trafficpolice)
t2=Thread(target=driver)
t1.start()
t2.start()