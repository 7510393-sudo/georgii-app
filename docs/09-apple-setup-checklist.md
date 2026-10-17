# Настройка Apple: что нажимать

Пошаговый список для работы за компьютером. Порядок важен: первый шаг самый долгий
по ожиданию, поэтому он первый.

Зачем каждое из этих действий нужно — в `08-build-and-release.md`. Здесь только что делать.

**Приготовить заранее:** фотографию или скан паспорта с верным написанием.

---

## 1. Запрос на исправление имени

Apple записала `Georgi`, в паспорте `Georgii`. Имя участвует в договоре и в выплатах,
поэтому меняется не кнопкой, а запросом с документом. Рассматривают несколько дней —
пусть идёт фоном, пока делается остальное.

1. [developer.apple.com/account](https://developer.apple.com/account), войти.
2. Карточка **Membership details** ([прямая ссылка](https://developer.apple.com/account#MembershipDetailsCard)),
   там ссылка на подачу запроса. Если её не видно —
   [форма обращения напрямую](https://developer.apple.com/contact/request/update-company-information/).
3. Вставить текст запроса (ниже), приложить паспорт, отправить.

**Не менять имя в учётной записи Apple.** Для индивидуального членства это не меняет ни имя
членства, ни имя продавца —
[Apple пишет об этом прямо](https://developer.apple.com/help/account/membership/updating-your-account-information/).

### Текст запроса

> **Subject:** Correction of legal name on Individual membership
>
> My Apple Developer Program membership was enrolled on 18 September 2026 as an Individual.
> The account holder name was recorded automatically as **"Georgi Kobiashvili"**.
>
> The correct spelling of my legal name, as it appears on my passport and on all of my UK
> records including my bank account, is **"Georgii Kobiashvili"** — with a double "i" at the
> end of the first name. The second "i" is missing from the name currently on my membership.
>
> Please correct the name on my membership so that it matches my identity document. I have
> attached a copy of my passport showing the correct spelling.
>
> I have not yet completed the Agreements, Tax and Banking section. I would like the
> correction to be made before I enter my banking details, so that the payee name matches
> the name on my bank account.
>
> Team ID: [Team ID]
> Apple Account: [адрес почты]

---

## 2. Подписать бесплатное соглашение

Обычные условия пользования программой. Без него Apple не даст создать запись приложения.
Ни банка, ни налогов, ни юридического имени здесь нет.

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Business**
   (в старых версиях раздел называется Agreements, Tax and Banking).
2. Строка с действующим соглашением → **View and Agree to Terms** → галочка → **Agree**.
3. **Остановиться.** Ниже будет **Paid Applications** — его не трогать до исправления имени.

---

## 3. Завести опознавательный знак

`com.kobiashvili.diary` надо зарегистрировать, иначе на следующем шаге он не появится
в списке.

1. [developer.apple.com/account/resources/identifiers/list](https://developer.apple.com/account/resources/identifiers/list)
2. **+** рядом с заголовком Identifiers.
3. **App IDs** → **Continue**.
4. Тип **App** → **Continue**.
5. **Description:** `Diary` (для себя, не для магазина).
6. **Bundle ID:** переключатель **Explicit**, в поле `com.kobiashvili.diary`.
7. Capabilities не трогать.
8. **Continue** → **Register**.

---

## 4. Создать запись приложения

Дело на приложение у Apple: полка, на которую лягут сборки.

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**.
2. **Platforms:** iOS.
3. **Name:** `Chronotheca`. Должно быть уникально во всём магазине; занято — добавить слово.
   Меняется свободно до публикации.
4. **Primary Language:** English (U.K.).
5. **Bundle ID:** выбрать `com.kobiashvili.diary`.
6. **SKU:** `diary-2026`. Внутренний код, никому не виден, **не меняется**.
7. **User Access:** Full Access.
8. **Create**.

---

## 5. Переписать Team ID

[developer.apple.com/account](https://developer.apple.com/account) → **Membership details** →
строка **Team ID**, десять знаков.

---

## 6. Выпустить ключ для сборки

Пароль для машины: она не может ввести ваш пароль и дождаться кода на телефон.

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Users and Access** →
   вкладка **Integrations** → **App Store Connect API** → **Team Keys**.
2. **Issuer ID** — длинная строка вверху страницы. Первое из трёх.
3. **+** → **Name:** `GitHub Actions`, **Access:** **Admin** (по-русски «Администратор») → **Generate**.

   **Роль обязательно Admin.** «Менеджер приложения» умеет загружать сборки, но не умеет
   подписывать их в облаке — [Apple требует для этого права администратора](https://developer.apple.com/forums/thread/698117).
   Роль ключа **изменить нельзя**: ошиблись — заводите новый.
4. **Key ID** в появившейся строке, десять знаков. Второе.
5. **Download** → файл `AuthKey_XXXXXXXXXX.p8`. Третье.

**Файл скачивается один раз.** Потеряли — отозвать ключ и сделать новый.

---

## 7. Положить четыре секрета в GitHub

Сейф, из которого ключ выдаётся машине на время сборки. В записи о сборке не попадает
и обратно не читается.

Сначала открыть `.p8` как текст: правой кнопкой → **Open With** → **TextEdit**,
или в Терминале `cat ~/Downloads/AuthKey_*.p8`. Выглядит так:

```
-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49...
-----END PRIVATE KEY-----
```

Скопировать **целиком, вместе со строками `-----BEGIN` и `-----END`**. Здесь чаще всего
теряют последнюю строку.

Затем: репозиторий → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret**, четыре раза.

| Name | Secret |
|---|---|
| `APPSTORE_ISSUER_ID` | Issuer ID |
| `APPSTORE_KEY_ID` | Key ID |
| `APPSTORE_PRIVATE_KEY` | содержимое `.p8` целиком |
| `APPLE_TEAM_ID` | Team ID из шага 5 |

Имена — буква в букву, они прописаны в сборке.

**Файл `.p8` не пересылать никому, включая Claude.** Кто им владеет — тот выпускает
сборки от имени автора.

---

## 8. Поставить TestFlight

На iPhone — приложение **TestFlight** из App Store, войти тем же Apple ID.

---

## Готово

Дальше — команда «собери версию». Сборка идёт около пятнадцати минут и приходит в TestFlight.

---

## Куда не влезать до исправления имени

| Что | Почему |
|---|---|
| **Paid Applications Agreement** | имя попадёт в договор |
| **Payments and Financial Reports** — банковский счёт | имя получателя должно совпасть со счётом |
| **Налоговая форма W-8BEN** | юридическое имя |
| **Submit for Review** — отправка в магазин | имя продавца станет публичным |

И отдельно, не про имя: **Xcode Cloud** — не включать вообще. Это сборка от Apple,
альтернатива нашей; настраивается из Xcode, то есть требует Mac. Второй механизм только
запутает.
