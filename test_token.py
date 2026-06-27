import requests
import json

resp = requests.post("https://oiss.onrender.com/api/auth/verify_token", json={
    "id_token": "asdfasdf",
    "mac_address": "test",
    "device_name": "test"
})
print("Status:", resp.status_code)
print("Body:", resp.text)
