#! /usr/bin/python3
#https://github.com/BG47510/

from urllib.parse import unquote
import requests
import re
import sys

erreur = requests.get("https://raw.githubusercontent.com/BG47510/Zap/main/assets/error.m3u8").text
def snif(url):
    lien = s.get(url, timeout=15).text
    retour = re.findall(r'\"hlsManifestUrl\":\"(.*?)\"\}', lien)
    tri = unquote(''.join(retour))
    flux = requests.get(tri).text
   # print(flux)
    if '.m3u8' not in tri:
        print(erreur)
    else:
        print(flux)

s = requests.Session()
result = snif(str(sys.argv[1]))
print(result)
