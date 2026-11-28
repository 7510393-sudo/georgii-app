import Foundation

/// Образцы дней для первого знакомства (P452).
///
/// Новый архив не пуст: по два дня в прошлом и в будущем и сегодня (P1035).
/// Позавчера — как листать картотеку и где что; вчера — как выглядит
/// прожитая страница: отметки, итоги дня, снимок, место; сегодня — запись
/// «Начинаю RollingDays!» про карту, вложения и хранение; завтра и
/// послезавтра — как обращаться с делами.
///
/// Это обычные файлы дней — стираются, как любая запись, или весь день
/// уходит в корзину. Ложатся только туда, где файла дня ещё нет: поверх
/// чужого ничего не пишется. Русский и английский — здесь, ещё восемь
/// языков — в `SamplesText.swift` (P471).
enum Samples {

    static func seed(_ vault: Vault) {
        // Проверки заводят свои папки и считают в них файлы — образцы им
        // только мешали бы.
        guard NSClassFromString("XCTestCase") == nil, !Vault.isPreview else { return }
        let cal = Calendar.current
        let today = DayStore.today()
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        // По два дня в прошлое и в будущее (P1035, автор: «чтобы получить
        // представление, как устроено, — несколько карточек прошлого и
        // будущего»): в прошлом — как листать и где что, в будущем — дела.
        let before = cal.date(byAdding: .day, value: -2, to: today) ?? today
        let after = cal.date(byAdding: .day, value: 2, to: today) ?? today

        put(vault, .diary, before, body: Samples.howto, title: Samples.howtoTitle)

        put(vault, .planner, yesterday, body: Samples.yesterdayPlan)

        var walk = Samples.walk
        if let link = vault.addPhoto(Photo.sample(), for: yesterday) {
            walk = walk.replacingOccurrences(of: "\n\n[", with: "\n\n" + Diary.line(link) + "\n\n[")
        }
        put(vault, .diary, yesterday, body: walk, title: Samples.walkTitle)

        put(vault, .planner, today, body: Samples.todayPlan)

        put(vault, .diary, today, body: Samples.todayDiary, title: Samples.todayTitle)

        put(vault, .planner, tomorrow, body: Samples.tomorrowPlan)

        put(vault, .planner, after, body: Samples.laterPlan)
    }

    // MARK: - Тексты образцов — и для мультфильма первого запуска (P1065)

    static var howto: String {
        SamplesText.text(.howto) ?? T("""
        Это образец прошлого дня. Каждый день — карточка в картотеке.

        Картотека. Потяните лист «Сегодня» вниз — откроется прошлое, вверх — будущее. Коснитесь карточки — откроется её день. Смахните открытый день вверх или вниз — он ляжет карточкой на своё место. «Сегодня» у края экрана вернёт в сегодняшний день.

        Разделы. Смахните вбок: слева — карта, справа — календарь. Кнопки внизу ведут туда же.

        Поиск. Лупа внизу картотеки ищет по словам, снимкам и местам.

        Снимки. Подержите снимок и ведите пальцем — он встанет в другое место текста или под дело.

        Меню дня. Коснитесь названия дня наверху: «Поделиться днём», «PDF дня», «Убрать день в корзину».
        """, """
        This is a sample past day. Every day is a card in the card file.

        The card file. Pull the “Today” sheet down to open the past, up to open the future. Tap a card to open its day. Swipe an open day up or down and it goes back to its place as a card. “Today” at the edge of the screen takes you back to today.

        Sections. Swipe sideways: the map is on the left, the calendar on the right. The buttons at the bottom lead there too.

        Search. The magnifier at the bottom of the card file searches words, photos and places.

        Photos. Hold a photo and move your finger — it goes to another spot in the text or under a task.

        The day menu. Tap the day’s name at the top: “Share the day”, “PDF of the day”, “Move the day to the trash”.
        """)
    }

    static var howtoTitle: String {
        SamplesText.text(.howtoTitle) ?? T("Как здесь всё устроено", "How it all works")
    }

    static var yesterdayPlan: String {
        SamplesText.text(.yesterdayPlan) ?? T("""
        - [x] 08:30 Купить хлеб и кофе
        - [x] 19:00 Позвонить маме (remind 18:45)
        - [ ] Дочитать главу
        """, """
        - [x] 08:30 Buy bread and coffee
        - [x] 19:00 Call Mum (remind 18:45)
        - [ ] Finish the chapter
        """)
    }

    static var walk: String {
        SamplesText.text(.walk) ?? T("""
        ## How did it go?

        - Купить хлеб и кофе: взяли ещё круассаны — и не зря
        - Позвонить маме: проговорили целый час
        - Дочитать главу: не вышло — перенесу на сегодня

        18:20 Вышли в парк до заката. Листья уже жёлтые, а воздух ещё летний.

        [Гайд-парк](geo:51.50731,-0.16573)

        Это образец: так выглядит прожитый день — дела с отметками, итоги дня, снимок и место.
        """, """
        ## How did it go?

        - Buy bread and coffee: got croissants too — worth it
        - Call Mum: we talked for a whole hour
        - Finish the chapter: didn't happen — moving it to today

        18:20 Went out to the park before sunset. The leaves are already yellow, but the air is still summery.

        [Hyde Park](geo:51.50731,-0.16573)

        This is a sample: this is what a lived day looks like — ticked tasks, the day's outcome, a photo and a place.
        """)
    }

    static var walkTitle: String {
        SamplesText.text(.walkTitle) ?? T("Прогулка", "A walk")
    }

    static var todayPlan: String {
        SamplesText.text(.todayPlan) ?? T("""
        - [ ] 09:00 Это дело-образец: коснитесь его и пишите своё
              «Ввод» — к следующему делу.
        - [ ] Долистайте до конца и потяните лист вверх — в будущих днях всё о делах
        """, """
        - [ ] 09:00 This is a sample task: tap it and write your own
              Return takes you to the next task.
        - [ ] Scroll to the end and pull the sheet up — the days ahead tell you all about tasks
        """)
    }

    static var todayDiary: String {
        SamplesText.text(.todayDiary) ?? T("""
        Сегодня начинается RollingDays. Утром — план, вечером — итоги дня: под каждым делом строка о том, что вышло.

        Места. Внизу — «Карта». Подержите палец на карте — встанет точка: назовите её и запишите в день. Справа сверху переключатель: «Мои места» — все ваши точки, «Записи» — дни на карте с превью снимков. В записи точку ставит «＋» → «Где я сейчас» — вот так:

        [Гайд-парк](geo:51.50731,-0.16573)

        Вложения. «＋» справа внизу страницы и над клавиатурой: камера, фото, голос, файл. Вложения ложатся под последним текстом записи, по четыре в ряд. Голосовую запись можно расшифровать в текст, а снимок — перенести пальцем прямо в текст или под дело.

        Где лежат записи. Всё — обычные файлы в вашей папке: их видно в «Файлах», они открываются любым редактором и остаются, даже если удалить приложение. Резервная копия — в настройках, одной кнопкой.

        Образцы — два дня в прошлом и два в будущем. Сотрите их, как обычный текст, или уберите день целиком: коснитесь названия дня наверху → «Убрать день в корзину».

        Здесь страница кончается. Потяните лист вверх отсюда — в будущих днях всё о делах.
        """, """
        Today my RollingDays begins. In the morning, a plan; in the evening, the day's outcome: a line under each task about how it went.

        Places. At the bottom — “Map”. Hold your finger on the map and a pin appears: name it and add it to the day. The switch at the top right: “My places” shows all your pins, “Entries” shows days on the map with photo previews. In an entry, “＋” → “Where I am” adds a place — like this:

        [Hyde Park](geo:51.50731,-0.16573)

        Attachments. The “＋” at the bottom right of the page and above the keyboard: camera, photos, voice, file. Attachments go under the last text of the entry, four in a row. A voice note can be transcribed to text, and a photo can be dragged straight into the text or under a task.

        Where your entries live. Everything is plain files in your folder: you can see them in Files, open them in any editor, and they stay even if you delete the app. Backup is in the settings, one button.

        The samples are two days in the past and two ahead. Erase them like any text, or move the whole day to the trash: tap the day’s name at the top → “Move the day to the trash”.

        This is the end of the page. Pull the sheet up from here — the days ahead tell you all about tasks.
        """)
    }

    static var todayTitle: String {
        SamplesText.text(.todayTitle) ?? T("Начинаю RollingDays!", "Starting my RollingDays!")
    }

    static var tomorrowPlan: String {
        SamplesText.text(.tomorrowPlan) ?? T("""
        - [ ] Коснитесь номера слева — дело сделано
              Коснитесь ещё раз — снова не сделано.
        - [ ] Подержите номер и ведите пальцем
              Вверх или вниз — переставить. Вправо — на другой день. Влево — удалить.
        - [ ] 10:00 Коснитесь времени слева — время и повтор
              Повторять можно каждый день, неделю, месяц или год. Колокольчик — напоминание.
        """, """
        - [ ] Tap the number on the left — the task is done
              Tap again — not done.
        - [ ] Hold the number and move your finger
              Up or down to reorder. Right to move it to another day. Left to delete.
        - [ ] 10:00 Tap the time on the left for the time and repeats
              Repeat every day, week, month or year. The bell is a reminder.
        """)
    }

    static var laterPlan: String {
        SamplesText.text(.laterPlan) ?? T("""
        - [ ] Вечером ответить, как прошло
              Под каждым делом — одна строка о том, что вышло. Она ляжет в дневник дня.
        - [ ] Положить в план снимок или голос
              «＋» внизу страницы: в будущем дне вложение встаёт под дело.
        - [ ] Убрать образцы, когда станут не нужны
              Сотрите их, как текст, или коснитесь названия дня → «Убрать день в корзину».
        """, """
        - [ ] In the evening, say how it went
              One line under each task about how it turned out. It goes into the day’s diary.
        - [ ] Put a photo or a voice note into the plan
              “＋” at the bottom of the page: on a future day an attachment goes under a task.
        - [ ] Remove the samples when you no longer need them
              Erase them like any text, or tap the day’s name → “Move the day to the trash”.
        """)
    }

    /// Положить день — только если его файла ещё нет.
    private static func put(_ vault: Vault, _ folder: Vault.Folder, _ date: Date,
                            body: String, title: String? = nil) {
        guard let url = vault.file(folder, for: date),
              !FileManager.default.fileExists(atPath: url.path) else { return }
        var file = DayFile(body: body)
        file.set("date", Vault.stamp(date))
        if let title { file.set("title", title) }
        vault.write(file.text, to: folder, for: date)
    }
}
