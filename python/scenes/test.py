#!/usr/bin/env python
# coding=utf-8
import argparse

from lifxlan import MultiZoneLight


def main(argv=None):
    parser = argparse.ArgumentParser(description="Inspect a LIFX multizone device.")
    parser.add_argument("mac", help="LIFX device MAC address")
    parser.add_argument("address", help="LIFX device network address")
    args = parser.parse_args(argv)

    # get devices
    strip = MultiZoneLight(args.mac, args.address)

    colors = strip.get_color_zones()
    print(colors)
    if strip.get_power() == 0:
        strip.set_power("on")

if __name__ == "__main__":
    main()
