#!/usr/bin/env python3

import requests as req

resp = req.post("http://10.0.1.20:2375/containers/sonarr/restart")