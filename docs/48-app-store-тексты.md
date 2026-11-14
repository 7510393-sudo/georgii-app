# Graphomanus в App Store — тексты и порядок (17.10, сверено 14.11)

**Сверено 14.11 с приложением после сборки 289** (P950): цена по P908
(£14,99 — цена первого года, £24,99 с iPad; одна покупка на все
устройства Apple), проба — с нажатия «Начать бесплатный месяц» (P908),
копия сама раз в неделю (P902), снимок с камеры — и в «Фото» (P903),
места в корзине (P904). Убранного в тексте не было: граница суток (P915)
и перевод папок (P920) нигде не упоминались. Письмо тестировщикам и
«What to Test» — отдельным файлом `docs/80-тестировщики-письмо.md`.

Готовые тексты для App Store Connect. Названия полей — как в самом сайте
(на английском). Лимиты Apple: имя — 30 знаков, подзаголовок — 30,
рекламный текст — 170, ключевые слова — 100 (через запятую, без пробелов),
описание — 4000.

**Не проверено:** тексты не видел Apple; в сайте полей могут быть мелкие
отличия по названиям. Чего приложение не умеет — в конце, это нельзя
обещать (`docs/40-преимущества.md`).

## 1. Запись приложения (App Information)

| Поле | Значение |
|---|---|
| Name | `Graphomanus` — имя должно быть свободно в магазине; если занято, Apple скажет сразу, тогда `Graphomanus Diary` |
| Subtitle (EN) | `Plan, diary, your own files` (27) |
| Подзаголовок (RU) | `План, дневник, ваши файлы` (24) |
| Bundle ID | не менять: `com.kobiashvili.diary` |
| Primary category | Lifestyle |
| Secondary category | Productivity |
| Support URL | `https://graphomanus.com/` |
| Marketing URL | `https://graphomanus.com/` |
| Privacy Policy URL | `https://graphomanus.com/privacy/` |
| Contact e-mail | `support@graphomanus.com` |
| Copyright | `2026 Georgii Kobiashvili` |

## 2. Тексты (English — основной)

**Promotional Text (170):**
Plan the morning. Remember the evening. One page a day in your own files — no account, no subscription. Launch price for the first year.

**Keywords (100):**
`diary,journal,planner,day planner,notebook,notes,markdown,habit,to do,private,photo journal,files`

**Description:**

Graphomanus is a diary and a day planner on one page.

Plan the day in the morning. Answer “How did it go?” in the evening. Write, add a photo, a voice note or a place. Turn the page.

YOUR ENTRIES ARE YOUR FILES
Every day is a plain text file in a folder you choose — iCloud Drive or On My iPhone. No account, no server of ours, no special format. Delete the app and your entries stay. Open them in any text editor, on a Mac, in Obsidian — in twenty years.

ONE PAGE FOR THE WHOLE DAY
• A plan with numbered tasks: tap the number to mark done, swipe to move to another day, long-press to reorder.
• Time and a reminder for a task.
• “How did it go?” — a short answer under every task.
• Repeating tasks and habits.
• Your iPhone Calendar events shown in the plan.
• Below the plan — the diary of the day.

WHAT GOES INTO A DAY
• Photos, videos, voice notes (with text), files.
• Places: a point in the text, your own map with icons.
• Steps and sleep from Health, if you allow it.

FIND AND REMEMBER
• Search across everything — only plans, only diary, only photos, only places.
• Calendar by year, month and list.
• “Back then…” — what happened on this day in earlier years.
• A PDF book of any period.

SAFE BY DESIGN
• Backup with byte-for-byte check — once you pick the place, it updates itself every week.
• A 30-day trash for days, photos, files and places.
• A photo you take in the app also goes to your Photos at full size.
• Your entries are never overwritten: if a file was changed elsewhere, both versions are kept.
• Face ID / passcode lock.

MOVE IN, MOVE OUT
Import from Day One, Diarium, Journey, Markdown and text files. Because your entries are files, leaving is as easy.

FAIR PRICE
Start a free month — the whole app, from the day you choose. After that, one purchase, like a notebook. No subscription. One purchase for all your Apple devices: when the iPad version comes, it is included. This is the launch price; it will go up with the iPad version. Without the purchase you can always read, search and take your entries with you.

Eleven languages: English, Русский, Українська, Deutsch, Français, Español, Italiano, Português, Nederlands, 日本語, ქართული.

**What’s New (первый выпуск):**
First release.

## 3. Тексты (русский) — не применяются (P765: страница App Store только по-английски)

**Рекламный текст:**
Утром — план, вечером — как прошло. Тетрадь дня, где записи — ваши файлы: без учётной записи и без подписки. Цена первого года.

**Описание:**

Graphomanus — дневник и планировщик дня на одной странице.

Утром — план. Вечером — «Как прошло?». Запись, снимок, голос, место. Страница перевёрнута.

ЗАПИСИ — ВАШИ ФАЙЛЫ
Каждый день — обычный текстовый файл в папке, которую выбрали вы: iCloud Drive или «На iPhone». Без учётной записи, без нашего сервера, без особого формата. Удалили приложение — записи остались. Их откроет любой текстовый редактор, Mac, Obsidian — и через двадцать лет.

ВЕСЬ ДЕНЬ НА ОДНОЙ СТРАНИЦЕ
• План с номерами: касание по номеру — сделано, вправо — на другой день, долгое нажатие — переставить.
• Время и напоминание у дела.
• «Как прошло?» — короткий ответ под каждым делом.
• Повторяющиеся дела и привычки.
• События Календаря iPhone — в плане.
• Ниже плана — дневник дня.

ЧТО ПОПАДАЕТ В ДЕНЬ
• Снимки, видео, голосовые записи (с расшифровкой), файлы.
• Места: точка в тексте, своя карта со значками.
• Шаги и сон из «Здоровья» — если вы разрешите.

НАЙТИ И ВСПОМНИТЬ
• Поиск по всему — только по плану, только по дневнику, только снимки, места.
• Календарь: год, месяц, список.
• «А вот когда-то…» — запись этого же числа в прошлые годы.
• PDF-книга за любой срок.

СОХРАННОСТЬ
• Резервная копия со сверкой байт в байт — место выбираете раз, дальше она обновляется сама раз в неделю.
• Корзина на 30 дней — для дней, снимков, файлов и мест.
• Снимок с камеры приложения ложится и в «Фото» — в полном размере.
• Записи не затираются: если файл изменили в другом месте, целы обе версии.
• Замок Face ID / код.

ПЕРЕЕХАТЬ — И УЕХАТЬ
Перенос из Day One, Diarium, Journey, Markdown и текстовых файлов. А уйти так же просто — записи и так файлы.

ЧЕСТНАЯ ЦЕНА
Бесплатный месяц всего приложения — с того дня, когда вы его начнёте. Дальше разовая покупка, как блокнот. Без подписки. Одна покупка на все ваши устройства Apple: выйдет версия для iPad — она уже ваша. Это цена первого года; с версией для iPad она вырастет. Без покупки всегда можно читать, искать и забрать записи с собой.

Одиннадцать языков: English, Русский, Українська, Deutsch, Français, Español, Italiano, Português, Nederlands, 日本語, ქართული.

## 4. Покупки (Monetization → In-App Purchases)

Коды покупок **не меняются** — приложение обращается к ним по коду. Меняются
только названия, которые видит человек:

1. **Пробный месяц** — Non-Consumable
   - Reference Name: `30-day Trial`
   - Product ID: `com.kobiashvili.diary.trial30`
   - Price: Free
   - Display Name: `30-day Trial` / «Пробный месяц»
   - Description: `A month of the whole app for free.` / «Месяц всего приложения бесплатно.»
2. **Полная версия** — Non-Consumable
   - Reference Name: `Graphomanus Full`
   - Product ID: `com.kobiashvili.diary.full`
   - Price: £14.99 (Tier по сетке Apple) — цена первого года (P908); с
     выходом iPad поднять до £24.99 в той же покупке, код не меняется
   - Display Name: `Graphomanus for good` / «Graphomanus навсегда»
   - Description: `One purchase for all your Apple devices.` / «Одна покупка на все устройства Apple.» (до 55 знаков)
   - Одна покупка на iPhone, iPad и Mac получается сама: покупка привязана
     к приложению и учётной записи Apple, а iPad и Mac будут тем же
     приложением (тот же Bundle ID). Отдельное приложение для iPad её бы
     не унаследовало — так не делать.
3. Каждой нужен **Review Screenshot** — снимок листка покупки из приложения
   (Настройки → «Graphomanus навсегда»).

Цены по странам Apple переводит сама; править по каждой стране можно потом.

## 5. App Privacy (анкета о данных)

Приложение не собирает ничего на свои серверы: серверов нет.
Ответ на главный вопрос: **«Data Not Collected»** (мы ничего не собираем).
Но Apple считает «сбором» любую передачу данных за пределы устройства; у вас
такая передача только внутри служб Apple (погода по месту, расшифровка
голоса). Если форма начнёт спрашивать про это отдельно, отвечайте по правде и
сверяйте со справкой «App Privacy Details» — я не могу проверить это отсюда.

Страницы политики — `https://graphomanus.com/privacy/` (две языковые версии).

## 6. Возрастной рейтинг и прочее

- Age Rating: во всех вопросах — «None»; итог ожидаемый **4+**.
- Content Rights: чужого содержимого нет.
- Export Compliance: приложение использует только шифрование, встроенное в
  систему (Face ID, HTTPS Apple) — ответ «нет собственного шифрования»
  (Exempt). В `Info.plist` можно поставить `ITSAppUsesNonExemptEncryption = NO`
  — скажете, добавлю.
- Advertising Identifier (IDFA): не используется.
- Страны: Pricing and Availability → выбрать нужные (см. разбор о странах;
  Россию включайте, только если согласны на трудности с оплатой).

## 7. Заметки для проверяющих Apple (App Review → Notes)

```
Graphomanus is a diary and day planner. No account is needed.
On first launch tap "Start" to create a folder (iCloud Drive or On My iPhone).
Sample days are added so every screen can be seen.
To write, tap "Start the free month" on the first sheet
(non-consumable "30-day Trial", free). After 30 days a one-time
purchase "Graphomanus for good" keeps writing open.
Reading, search, import and moving the folder never need a purchase.
Permissions (camera, adding to Photos, microphone, speech recognition,
location, calendar, Health, notifications, Face ID) are optional and
asked only when the feature is used. A photo taken with the in-app
camera is also added to Photos; the app never reads the Photos library
except for pictures the user picks.
Entries are plain files in the user's own folder; the app has no server.
Contact: support@graphomanus.com
```

## 8. Снимки экрана (Screenshots)

**Размеры.** Apple требует снимки для iPhone **6.9″ (1320×2868)** — или 6.5″
(1284×2778). Снимки, которые делает наша проверка, — **1206×2622 (6.3″)**:
в магазин в таком виде не принимаются, растягивать нельзя. Нужно запустить
съёмку на симуляторе iPhone 16 Pro Max (или Plus) — это отдельная
доработка сценария «Снимки экрана»; сделаю, когда скажете.

**Порядок (история одного дня, 5–6 снимков):**
1. Утро — план с делами и событиями Календаря.
2. День — снимок под делом, точка на карте.
3. Вечер — «Как прошло?» и запись.
4. Через год — «А вот когда-то…».
5. Календарь / поиск.
6. Папка в «Файлах» — «это всё ваше».

Подписи на снимках (короткие, по желанию):
«Plan the morning» / «Remember the evening» / «Your files, forever» /
«No subscription».

## 8а. Налоговая форма (Business → Agreements, Tax, and Banking)

Я не бухгалтер: это общий порядок, который Apple ведёт по шагам.

1. **Paid Apps Agreement** — «Request» → принять; заполнить контакты
   (имя как в паспорте: Georgii Kobiashvili).
2. **Bank Information:** британский счёт (sort code, номер счёта, IBAN,
   название банка). Имя владельца счёта должно совпадать с именем аккаунта.
3. **Tax Forms → U.S. Tax Forms → W-8BEN** (форма для физического лица
   не из США):
   - Name: как в паспорте.
   - Country of citizenship: ваше гражданство (как в паспорте).
   - Permanent residence address: ваш адрес в Англии; mailing address тот же.
   - Foreign tax identification number: британский — обычно National
     Insurance number или UTR.
   - Part II (договор): Country — United Kingdom; ставка по доходам в виде
     «royalties» — **0%** (по договору США–Великобритания; сверьте в
     подсказках мастера Apple).
   - Подписать и отправить; форма действует до конца третьего календарного
     года после подписи, потом Apple напомнит.
4. Если форма просит «Tax categories» по другим странам (Австралия,
   Бразилия и т. д.) — Apple покажет, что заполнить, для стран продаж.
5. Статус договора должен стать **Active**; до этого покупки в
   TestFlight/магазине не приходят.

## 9. Тестировщики (TestFlight)

Готовые тексты — **`docs/80-тестировщики-письмо.md`** (14.11): описание
для TestFlight, «What to Test» к ближайшей сборке, письмо-приглашение.

## 10. Чего нельзя обещать

Android, веб; iPad и Mac — только как «одна покупка их включит, когда
выйдут» (P908), без сроков и без снимков; собственная синхронизация (только iCloud Drive);
шифрование записей (нарочно нет — замок приложения); несколько дневников,
шаблоны, ИИ; **погода** — пока не подтверждено, что WeatherKit включён у
знака приложения: в описание вынесено только «Photos, videos, voice, files,
places» — слово «погода» там нарочно не стоит.

**Риск, о котором сказать автору (14.11):** Apple иногда отклоняет
описание, где упомянуто то, чего в приложении ещё нет (правило 2.3 —
«метаданные о том, что есть»). Фразы про iPad стоят только в разделе цены
и говорят о покупке, а не о функции. Если проверка придерётся — убрать
два предложения про iPad из описания, цена и покупка от этого не меняются.
