#!/usr/bin/env python3
"""一次性联调脚本: 复刻 FNISG 前端登录加密(user.js RSAKeyEncrypt), 经设备本地 web
(/api_1, MQTT 走设备自身 loopback 不受外网 1883 限制) 切运行模式到学习模式。
用法: python fnisg_switch_mode.py <设备IP> <模式 learning|checking>
"""
import base64
import hashlib
import json
import random
import sys
from urllib.parse import quote

import requests
from Crypto.Cipher import AES, PKCS1_v1_5
from Crypto.PublicKey import RSA
from Crypto.Util.Padding import pad

CHARSET = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678'
# JS encodeURI 的不转义集合(A-Z a-z 0-9 恒不转义)
URI_SAFE = ";,/?:@&=+$-_.!~*'()#"


def js_encode_uri(s):
    return quote(s, safe=URI_SAFE)


def getrandom():
    return ''.join(random.choice(CHARSET) for _ in range(32))


def rsa_key_encrypt(public_key, date, password):
    private_key = getrandom()
    password_new = hashlib.md5(js_encode_uri(password + date).encode()).hexdigest()
    cipher = AES.new(private_key.encode(), AES.MODE_ECB)
    secret_key = base64.b64encode(cipher.encrypt(pad(password_new.encode(), 16))).decode()
    rsa_key = RSA.import_key(base64.b64decode(public_key))
    seed = base64.b64encode(PKCS1_v1_5.new(rsa_key).encrypt(private_key.encode())).decode()
    return secret_key, seed


def main(ip, mode):
    base = 'https://{}'.format(ip)
    s = requests.Session()
    s.verify = False
    requests.packages.urllib3.disable_warnings()

    r = s.post(base + '/api_1/member/getPublicKey',
               data={'username': 'admin'}, timeout=15)
    res = r.json()
    if res.get('status') != 0:
        print(ip, 'getPublicKey 失败:', json.dumps(res, ensure_ascii=False)[:200])
        return 1
    info = res['info'][0]
    pub, date = info['key'], info['date']
    key_info, date_info = info.get('key_info'), info.get('date_info')
    print(ip, '拿到公钥+date ok, 双侧' if key_info else '拿到公钥+date ok, 单侧')

    headers = {}
    # BOTH_SIDE: 先登信息侧拿 sessioninfo, 再登控制侧 (与前端 user.js 登录时序一致)
    if key_info:
        sk_i, sd_i = rsa_key_encrypt(key_info, date_info, 'hc@20190')
        r = s.post(base + '/api_1/member/loginInfo',
                   data={'username': 'admin', 'password': sk_i, 'seed': sd_i},
                   timeout=30)
        res = r.json()
        if res.get('status') != 0:
            print(ip, 'loginInfo 失败:', json.dumps(res, ensure_ascii=False)[:200])
            return 1
        headers['sessioninfo'] = res['info'][0]['session']
        print(ip, 'info login ok')

    secret_key, seed = rsa_key_encrypt(pub, date, 'hc@20190')
    r = s.post(base + '/api_1/member/login',
               data={'username': 'admin', 'password': secret_key, 'seed': seed},
               timeout=30)
    res = r.json()
    if res.get('status') != 0:
        print(ip, 'login 失败:', json.dumps(res, ensure_ascii=False)[:200])
        return 1
    headers['session'] = res['info'][0]['session']
    print(ip, 'ctrl login ok')

    r = s.post(base + '/api_1/run/switchRunMode',
               data={'mode': mode}, headers=headers, timeout=30)
    try:
        res = r.json()
    except ValueError:
        print(ip, 'switchRunMode 非 JSON 响应:', r.status_code, r.text[:200])
        return 1
    print(ip, 'switchRunMode({}) →'.format(mode),
          json.dumps(res, ensure_ascii=False)[:200])
    return 0 if res.get('status') == 0 else 1


if __name__ == '__main__':
    rc = 0
    for dev_ip in sys.argv[1:-1]:
        rc |= main(dev_ip, sys.argv[-1])
    sys.exit(rc)
