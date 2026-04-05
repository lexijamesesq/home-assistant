#!/usr/bin/env python
# coding=utf-8
import sys

from lifxlan import LifxLAN
from lifxlan import MultiZoneLight

def main():
    # get devices
    strip = MultiZoneLight("d0:73:d5:2d:bd:b6", "10.0.40.54")

    colors = strip.get_color_zones()
    print(colors)
    if strip.get_power() == 0:
        strip.set_power("on")

if __name__=="__main__":
    main()
