from libpurecool.dyson import DysonAccount

USER = "user@example.com"
PASS = "dsMUfKTcTFXJ4iCr-6ok"
LANG = "GB"

dyson_account = DysonAccount(USER, PASS, LANG)
logged = dyson_account.login()

devices = dyson_account.devices()
connected = devices[0].auto_connect()
