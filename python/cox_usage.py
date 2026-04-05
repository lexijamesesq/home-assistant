import mechanicalsoup
import re
import json

#Set script vars
login_url = "https://www.cox.com/content/dam/cox/okta/signin.html"
stats_url = "https://www.cox.com/internet/mydatausage.cox"
cox_user  = "alexbussa"
cox_pass  = "C3@x2*k)KgeWB2M^k9WU"
json_file = "/config/json/cox_usage.json"

#Setup browser
browser = mechanicalsoup.StatefulBrowser(
    soup_config={'features': 'lxml'},
    user_agent='Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.2.13) Gecko/20101206 Ubuntu/10.10 (maverick) Firefox/3.6.13',
)

#Request Cox login page. the result is a requests.Response object
login_page = browser.get(login_url)

#Similar to assert login_page.ok but with full status code in case of failure.
login_page.raise_for_status()

#Grab the login form. login_page.soup is a BeautifulSoup object
login_form = mechanicalsoup.Form(login_page.soup.select_one('form[name="form1"]'))

#Specify username and password
login_form.input({'username': cox_user, 'password': cox_pass})

#Submit form
browser.submit(login_form, login_page.url)

#Read the stats URL
stats_page = browser.get(stats_url)

#Grab the script with the stats in it
stats = stats_page.soup.findAll('script', string=re.compile('utag_data'))[0].string

#Split and RSplit on the first { and on the last } which is where the data object is located
jsonValue = '{%s}' % (stats.split('{', 1)[1].rsplit('}', 1)[0],)

#Load into json
data = json.loads(jsonValue)

#Print JSON to file
with open(json_file, 'w+') as outfile:
    json.dump(data, outfile, sort_keys=True)
