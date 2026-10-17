# Graphomanus в App Store — тексты и порядок (17.10)

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
Plan the morning. Remember the evening. Your notebook, your files — one page a day, no account, no subscription.

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
• “Do you remember?” — what happened on this day before.
• A PDF book of any period.

SAFE BY DESIGN
• Backup with byte-for-byte check.
• A 30-day trash for days, photos and files.
• Your entries are never overwritten: if a file was changed elsewhere, both versions are kept.
• Face ID / passcode lock.

MOVE IN, MOVE OUT
Import from Day One, Diarium, Journey, Markdown and text files. Because your entries are files, leaving is as easy.

FAIR PRICE
The first 30 days are the whole app for free. After that, one purchase — like a notebook. No subscription. What you wrote always stays readable, even without the purchase.

Ten languages: English, Русский, Українська, Deutsch, Français, Español, Italiano, Português, Nederlands, 日本語.

**What’s New (первый выпуск):**
First release.

## 3. Тексты (русский)

**Рекламный текст:**
Утром — план, вечером — как прошло. Тетрадь дня, где записи — ваши файлы: без учётной записи и без подписки.

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
• «А помнишь?» — что было в этот день раньше.
• PDF-книга за любой срок.

СОХРАННОСТЬ
• Резервная копия со сверкой байт в байт.
• Корзина на 30 дней — для дней, снимков и файлов.
• Записи не затираются: если файл изменили в другом месте, целы обе версии.
• Замок Face ID / код.

ПЕРЕЕХАТЬ — И УЕХАТЬ
Перенос из Day One, Diarium, Journey, Markdown и текстовых файлов. А уйти так же просто — записи и так файлы.

ЧЕСТНАЯ ЦЕНА
Первые 30 дней — всё приложение бесплатно. Дальше разовая покупка, как блокнот. Без подписки. Написанное читается всегда, даже без покупки.

Десять языков: English, Русский, Українська, Deutsch, Français, Español, Italiano, Português, Nederlands, 日本語.

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
   - Price: £14.99 (Tier по сетке Apple)
   - Display Name: `Graphomanus for good` / «Graphomanus навсегда»
   - Description: `One purchase, no subscription.` / «Разовая покупка, без подписки.»
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
The first 30 days are free (non-consumable "30-day Trial");
afterwards a one-time purchase "Graphomanus for good" unlocks writing.
Existing entries always stay readable without a purchase.
Permissions (camera, photos, microphone, location, calendar, Health,
notifications, Face ID) are optional and asked only when the feature is used.
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
4. Через год — «А помнишь?».
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

## 9. «Письмо» тестировщикам (TestFlight)

Это не одно письмо, а три текста, которые видят тестировщики:

1. **Beta App Description** (на странице приложения в TestFlight):
   > Graphomanus is a diary and day planner on one page: a plan in the morning, “How did it go?” in the evening. Your entries are plain files in a folder you choose. Free during testing — purchases cost nothing in TestFlight.
2. **What to Test** (по каждой сборке; пример для 128):
   > Please try writing in the diary: when the keyboard opens, the line you type should stay visible. Also: open and close Settings (feel and look), and the page strip above the bottom bar.
3. **Письмо-приглашение** (от вас, с публичной ссылкой TestFlight):
   > Hi! I am testing a diary app called Graphomanus. It is free in TestFlight. Install TestFlight from the App Store, open this link: [ссылка]. Your entries are your own files; updates never delete them. To send feedback: take a screenshot in the app and tap “Share Beta Feedback”. Thank you!

Письма влияют на то, как люди понимают приложение и какие отзывы пришлют;
к проверке Apple отношение имеет только **Beta App Description** и контакты.
Адрес для отзывов — `support@graphomanus.com`.

## 10. Чего нельзя обещать

iPad, Mac, Android, веб; собственная синхронизация (только iCloud Drive);
шифрование записей (нарочно нет — замок приложения); несколько дневников,
шаблоны, ИИ; **погода** — пока не подтверждено, что WeatherKit включён у
знака приложения: в описание вынесено только «Photos, videos, voice, files,
places» — слово «погода» там нарочно не стоит.
