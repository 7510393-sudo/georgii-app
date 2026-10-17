"""Создать сертификат распространения и профиль, положить их на машину сборки.

Зачем это существует. Xcode умеет заводить подпись сам («облачная подпись»),
но только когда в него вошли живым человеком. Ключ App Store Connect такого
доступа не даёт, и ровно поэтому десять попыток подряд упирались в «профиль не
найден». Поэтому делаем то же самое руками, через служебный интерфейс Apple:

  1. создаём закрытый ключ и заявку на сертификат;
  2. просим Apple выдать по ней сертификат распространения;
  3. складываем ключ и сертификат в связку ключей машины;
  4. просим Apple выдать профиль для нашего приложения;
  5. кладём профиль туда, где Xcode его найдёт.

Скрипт печатает имя профиля — оно нужно сборке для экспорта.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.kobiashvili.diary"
CERT_NAME = "Chronotheca CI"
PROFILE_NAME = "Chronotheca CI App Store"
# Виджет «Сегодня» (P382) — свой знак и свой профиль.
WIDGET_ID = BUNDLE_ID + ".widget"
WIDGET_PROFILE = "Chronotheca CI Widget"
WORK = "/tmp/signing"
P12_PASSWORD = "chronotheca-ci"
KEYCHAIN = os.path.expanduser("~/Library/Keychains/chronotheca-ci-db")
KEYCHAIN_PASSWORD = "chronotheca-ci"


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ISSUER_ID"], "iat": now, "exp": now + 900,
         "aud": "appstoreconnect-v1"},
        open(os.environ["KEY_PATH"]).read(),
        algorithm="ES256",
        headers={"kid": os.environ["KEY_ID"], "typ": "JWT"})


def api(path, method="GET", body=None, tok=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        API + path, data=data, method=method,
        headers={"Authorization": "Bearer " + tok,
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        print(f"  {method} {path} → {e.code}\n  {detail[:800]}", file=sys.stderr)
        raise


def bundle_ref_of(identifier, tok):
    found = api(f"/v1/bundleIds?filter[identifier]={identifier}&limit=200", tok=tok)
    for b in found.get("data", []):
        if b["attributes"].get("identifier") == identifier:
            return b["id"]
    return None


def widget_profile(tok, cert_id):
    """Знак и профиль виджета (P382). Возвращает пути профиля и прав."""
    import plistlib
    ref = bundle_ref_of(WIDGET_ID, tok)
    if not ref:
        made = api("/v1/bundleIds", "POST", {
            "data": {"type": "bundleIds",
                     "attributes": {"identifier": WIDGET_ID, "name": "Chronotheca Widget",
                                    "platform": "IOS"}}}, tok)
        ref = made["data"]["id"]
        print(f"  заведён знак виджета {WIDGET_ID}")
    for p in api("/v1/profiles?limit=200", tok=tok).get("data", []):
        if p["attributes"]["name"] == WIDGET_PROFILE:
            api(f"/v1/profiles/{p['id']}", "DELETE", tok=tok)
    prof = api("/v1/profiles", "POST", {
        "data": {
            "type": "profiles",
            "attributes": {"name": WIDGET_PROFILE, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"id": ref, "type": "bundleIds"}},
                "certificates": {"data": [{"id": cert_id, "type": "certificates"}]},
            }}}, tok)["data"]
    raw = f"{WORK}/widget.mobileprovision"
    with open(raw, "wb") as f:
        f.write(base64.b64decode(prof["attributes"]["profileContent"]))
    decoded = f"{WORK}/widget.plist"
    subprocess.run(["security", "cms", "-D", "-i", raw, "-o", decoded], check=True)
    with open(decoded, "rb") as f:
        entitlements = plistlib.load(f)["Entitlements"]
    ent = f"{WORK}/widget-entitlements.plist"
    with open(ent, "wb") as f:
        plistlib.dump(entitlements, f)
    print(f"  права виджета: {sorted(entitlements)}")
    return raw, ent


def run(*args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kw)


def main():
    tok = token()
    os.makedirs(WORK, exist_ok=True)

    # 1. Закрытый ключ и заявка на сертификат
    print("Готовлю заявку на сертификат…")
    run("openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
        "-keyout", f"{WORK}/key.pem", "-out", f"{WORK}/csr.pem",
        "-subj", "/CN=Chronotheca CI/C=GB")
    csr = open(f"{WORK}/csr.pem").read()

    # 2. Сертификат распространения
    #
    # Apple разрешает не больше трёх сертификатов распространения на аккаунт,
    # а каждый запуск сборки заводит новый. Поэтому сначала убираем свои
    # прежние — узнаём их по имени, которое сами и ставили.
    existing_certs = api("/v1/certificates?limit=200", tok=tok).get("data", [])
    dist = [c for c in existing_certs
            if c["attributes"].get("certificateType") == "DISTRIBUTION"]
    # Отзываем все прежние сертификаты распространения.
    #
    # По имени своих не отличить: Apple подписывает их именем владельца
    # аккаунта, а не тем, что было в заявке. А закрытый ключ от прежнего
    # сертификата всё равно остался на уничтоженной машине сборки, то есть
    # пользоваться им никто не может. Поэтому проще отозвать все.
    #
    # Если вы когда-нибудь заведёте сертификат распространения вручную,
    # из Xcode на своём компьютере, — этот шаг его снесёт. Тогда исключите
    # его здесь по идентификатору.
    for c in dist:
        name = c["attributes"].get("displayName") or c["attributes"].get("name") or c["id"]
        print(f"  отзываю прежний сертификат: {name}")
        api(f"/v1/certificates/{c['id']}", "DELETE", tok=tok)

    print("Прошу у Apple сертификат распространения…")
    try:
        made = api("/v1/certificates", "POST", {
            "data": {"type": "certificates",
                     "attributes": {"certificateType": "DISTRIBUTION",
                                    "csrContent": csr}}}, tok)
    except urllib.error.HTTPError as e:
        if e.code == 409:
            print("::error::Apple отказала: исчерпан предел сертификатов "
                  "распространения. Отзовите лишние на developer.apple.com → "
                  "Certificates.")
        raise
    cert = made["data"]
    cert_id = cert["id"]
    print(f"  выдан сертификат {cert_id}")

    with open(f"{WORK}/cert.cer", "wb") as f:
        f.write(base64.b64decode(cert["attributes"]["certificateContent"]))
    run("openssl", "x509", "-inform", "DER", "-in", f"{WORK}/cert.cer",
        "-out", f"{WORK}/cert.pem")

    # 3. Связка ключей машины
    print("Кладу ключ и сертификат в связку ключей…")
    p12 = [
        "openssl", "pkcs12", "-export",
        "-inkey", f"{WORK}/key.pem", "-in", f"{WORK}/cert.pem",
        "-out", f"{WORK}/cert.p12", "-passout", f"pass:{P12_PASSWORD}",
        "-name", CERT_NAME,
    ]
    try:
        run(*p12, "-legacy")
    except subprocess.CalledProcessError:
        run(*p12)

    subprocess.run(["security", "delete-keychain", KEYCHAIN],
                   capture_output=True, text=True)
    run("security", "create-keychain", "-p", KEYCHAIN_PASSWORD, KEYCHAIN)
    run("security", "set-keychain-settings", "-lut", "21600", KEYCHAIN)
    run("security", "unlock-keychain", "-p", KEYCHAIN_PASSWORD, KEYCHAIN)
    run("security", "import", f"{WORK}/cert.p12", "-k", KEYCHAIN,
        "-P", P12_PASSWORD, "-A", "-T", "/usr/bin/codesign",
        "-T", "/usr/bin/security")
    run("security", "set-key-partition-list", "-S",
        "apple-tool:,apple:,codesign:", "-s", "-k", KEYCHAIN_PASSWORD, KEYCHAIN)

    # Связка должна быть в списке поиска, иначе codesign её не увидит.
    existing = run("security", "list-keychains", "-d", "user").stdout.split()
    existing = [k.strip().strip('"') for k in existing]
    run("security", "list-keychains", "-d", "user", "-s", KEYCHAIN, *existing)
    print(run("security", "find-identity", "-v", "-p", "codesigning",
              KEYCHAIN).stdout.strip())

    # 4. Профиль
    # Знак ищется точным совпадением: под тем же началом теперь лежит и
    # знак виджета (P382), а отбор Apple по имени — не точный.
    bundle_ref = bundle_ref_of(BUNDLE_ID, tok)
    if not bundle_ref:
        print(f"::error::Опознавательный знак {BUNDLE_ID} не заведён в аккаунте.")
        sys.exit(1)

    # Погода Apple (WeatherKit) — право, которое включается у самого знака
    # приложения. Включаем сами; не вышло — не беда: сборка идёт дальше,
    # а приложение скажет «погода недоступна» (решение P208).
    try:
        caps = api(f"/v1/bundleIds/{bundle_ref}/bundleIdCapabilities", tok=tok)
        have = [c["attributes"].get("capabilityType")
                for c in caps.get("data", [])]
        print(f"  права знака: {sorted(h for h in have if h)}")
        if "WEATHERKIT" not in have:
            api("/v1/bundleIdCapabilities", "POST", {
                "data": {
                    "type": "bundleIdCapabilities",
                    "attributes": {"capabilityType": "WEATHERKIT"},
                    "relationships": {
                        "bundleId": {"data": {"id": bundle_ref, "type": "bundleIds"}}},
                }}, tok)
            print("  погода Apple включена для знака")
    except Exception as e:  # noqa: BLE001 — погода не повод ронять сборку
        print(f"::warning::Погоду Apple включить не удалось ({e}). Сборка идёт "
              "без неё; включить можно вручную: developer.apple.com → "
              "Identifiers → com.kobiashvili.diary → WeatherKit.")

    # «Здоровье» (P378) — тоже право знака; без него приложение просто
    # не получит доступа, сборка от этого не падает.
    try:
        caps = api(f"/v1/bundleIds/{bundle_ref}/bundleIdCapabilities", tok=tok)
        have = [c["attributes"].get("capabilityType") for c in caps.get("data", [])]
        if "HEALTHKIT" not in have:
            api("/v1/bundleIdCapabilities", "POST", {
                "data": {
                    "type": "bundleIdCapabilities",
                    "attributes": {"capabilityType": "HEALTHKIT"},
                    "relationships": {
                        "bundleId": {"data": {"id": bundle_ref, "type": "bundleIds"}}},
                }}, tok)
            print("  «Здоровье» включено для знака")
    except Exception as e:  # noqa: BLE001
        print(f"::warning::«Здоровье» включить не удалось ({e}). Сборка идёт без него.")

    for p in api("/v1/profiles?limit=200", tok=tok).get("data", []):
        if p["attributes"]["name"] == PROFILE_NAME:
            print(f"  убираю прежний профиль {p['id']}")
            api(f"/v1/profiles/{p['id']}", "DELETE", tok=tok)

    print("Прошу у Apple профиль для App Store…")
    profile = api("/v1/profiles", "POST", {
        "data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"id": bundle_ref, "type": "bundleIds"}},
                "certificates": {"data": [{"id": cert_id, "type": "certificates"}]},
            }}}, tok)["data"]

    # 5. Профиль — туда, где его ищет Xcode.
    #
    # Папок две: старая и новая. Начиная с Xcode 16 профили читаются из
    # UserData, а прежняя папка осталась для совместимости. Кладём в обе,
    # чтобы не зависеть от версии на машине сборки.
    blob = base64.b64decode(profile["attributes"]["profileContent"])

    raw = f"{WORK}/profile.mobileprovision"
    with open(raw, "wb") as f:
        f.write(blob)

    # Имя файла — внутренний UUID профиля: так их называет сам Xcode.
    # Плист внутри бывает двоичным, поэтому читаем его файлом, а не строкой.
    import plistlib
    decoded = f"{WORK}/profile.plist"
    subprocess.run(["security", "cms", "-D", "-i", raw, "-o", decoded], check=True)
    with open(decoded, "rb") as f:
        uuid = plistlib.load(f)["UUID"]

    for folder in (
        "~/Library/Developer/Xcode/UserData/Provisioning Profiles",
        "~/Library/MobileDevice/Provisioning Profiles",
    ):
        d = os.path.expanduser(folder)
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, uuid + ".mobileprovision")
        with open(path, "wb") as f:
            f.write(blob)
        print(f"  профиль положен: {path}")

    # 6. Всё, что понадобится упаковщику: права из профиля и имя удостоверения.
    #
    # Дальше .ipa собирается вручную, а не через xcodebuild -exportArchive:
    # тот ищет профиль в своих папках и упорно его не находит, сколько бы папок
    # мы ни перепробовали. Подписать приложение можно и напрямую.
    with open(decoded, "rb") as f:
        entitlements = plistlib.load(f)["Entitlements"]
    # Своя папка в iCloud Drive (P452). Профиль перечисляет права iCloud
    # «на все случаи»: оба окружения и все службы. Приложению App Store
    # нужно одно окружение и одна служба — документы; лишнее Apple
    # отвергает при приёме сборки.
    if "com.apple.developer.icloud-container-environment" in entitlements:
        entitlements["com.apple.developer.icloud-container-environment"] = "Production"
    if "com.apple.developer.icloud-services" in entitlements:
        entitlements["com.apple.developer.icloud-services"] = ["CloudDocuments"]
    entitlements.pop("com.apple.developer.ubiquity-kvstore-identifier", None)
    # Пробная среда iCloud App Store не нужна — Apple отвергает сборку с ней
    # (90045, сборка 105).
    entitlements.pop("com.apple.developer.icloud-container-development-container-identifiers", None)
    ent_path = f"{WORK}/entitlements.plist"
    with open(ent_path, "wb") as f:
        plistlib.dump(entitlements, f)
    print(f"  права вынуты из профиля: {sorted(entitlements)}")

    identities = run("security", "find-identity", "-v", "-p", "codesigning",
                     KEYCHAIN).stdout
    identity = None
    for line in identities.splitlines():
        if '"' in line:
            identity = line.split('"')[1]
            break
    if not identity:
        print("::error::В связке ключей нет удостоверения для подписи.")
        sys.exit(1)
    print(f"  подписывать будем как: {identity}")

    # Виджет (P382): не вышло — приложение уходит без него, а не падает.
    widget_raw, widget_ent = "", ""
    try:
        widget_raw, widget_ent = widget_profile(tok, cert_id)
    except Exception as e:  # noqa: BLE001
        print(f"::warning::Профиль виджета получить не удалось ({e}). Сборка идёт без виджета.")

    with open(os.environ["GITHUB_ENV"], "a") as f:
        f.write(f"WIDGET_PROFILE_PATH={widget_raw}\n")
        f.write(f"WIDGET_ENTITLEMENTS_PATH={widget_ent}\n")
        f.write(f"PROFILE_NAME={PROFILE_NAME}\n")
        f.write(f"SIGNING_KEYCHAIN={KEYCHAIN}\n")
        f.write(f"SIGNING_IDENTITY={identity}\n")
        f.write(f"PROFILE_PATH={raw}\n")
        f.write(f"ENTITLEMENTS_PATH={ent_path}\n")
    print(f"Готово. Профиль «{PROFILE_NAME}».")


if __name__ == "__main__":
    main()
