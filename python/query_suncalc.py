from suncalcPy import suncalc
import json
import math
from datetime import datetime, timedelta
import time
import calendar


#Set script vars
json_file = "/config/json/suncalc_data.json"

#Load into json
data = suncalc.getTimes(datetime.now(), 33.325380, -111.966348)

#Print JSON to file
with open(json_file, 'w+') as outfile:  
    json.dump(data, outfile, sort_keys=True)
