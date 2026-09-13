#!/usr/bin/env python3

import argparse

import requests as req

def main(argv=None):
    parser = argparse.ArgumentParser(description="Restart the Sonarr container.")
    parser.add_argument("url", help="Docker API restart endpoint")
    args = parser.parse_args(argv)
    req.post(args.url)


if __name__ == "__main__":
    main()
