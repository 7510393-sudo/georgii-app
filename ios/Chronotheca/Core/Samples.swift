import Foundation

/// Образцы дней для первого знакомства (P452).
///
/// Новый архив не пуст: вчера, сегодня и завтра уже заполнены. В делах
/// плана — как с ним обращаться, в дневнике сегодняшнего дня — запись
/// «Начинаю Graphomanus!» про карту, вложения и хранение. Вчерашний день
/// показывает, как выглядит прожитая страница: отметки, итоги дня, снимок,
/// место.
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

        put(vault, .planner, yesterday, body: SamplesText.text(.yesterdayPlan) ?? T("""
        - [x] 08:30 Купить хлеб и кофе
        - [x] 19:00 Позвонить маме (remind 18:45)
        - [ ] Дочитать главу
        """, """
        - [x] 08:30 Buy bread and coffee
        - [x] 19:00 Call Mum (remind 18:45)
        - [ ] Finish the chapter
        """))

        var walk = SamplesText.text(.walk) ?? T("""
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
        if let link = vault.addPhoto(Photo.sample(), for: yesterday) {
            walk = walk.replacingOccurrences(of: "\n\n[", with: "\n\n" + Diary.line(link) + "\n\n[")
        }
        put(vault, .diary, yesterday, body: walk, title: SamplesText.text(.walkTitle) ?? T("Прогулка", "A walk"))

        put(vault, .planner, today, body: SamplesText.text(.todayPlan) ?? T("""
        - [ ] 09:00 Это дело-образец: коснитесь его и пишите своё
              «Ввод» — к следующему делу. Время слева: коснитесь — время и повтор. Колокольчик — напоминание.
        - [ ] Коснитесь номера слева — дело сделано
              Коснитесь ещё раз — снова не сделано.
        - [ ] Подержите дело и ведите пальцем
              Вверх-вниз — переставить. Вправо — на другой день. Влево — удалить.
        - [ ] Повторять дело — каждый день, неделю, месяц, год
              Коснитесь времени дела: внизу — «Повторять». Повтор впишется в дни на год вперёд.
        - [ ] Найти любой день — «Календарь» внизу
              Точки под числом — в этот день есть записи. «Поиск» ищет по словам, снимкам и местам.
        """, """
        - [ ] 09:00 This is a sample task: tap it and write your own
              Return takes you to the next task. The time on the left: tap it for the time and repeats. The bell is a reminder.
        - [ ] Tap the number on the left — the task is done
              Tap again — not done.
        - [ ] Hold a task and move your finger
              Up or down to reorder. Right to move it to another day. Left to delete.
        - [ ] Repeat a task — every day, week, month or year
              Tap the task's time: at the bottom, “Repeat”. The repeat is written into the days a year ahead.
        - [ ] Find any day — “Calendar” at the bottom
              Dots under a date mean entries that day. “Search” looks through words, photos and places.
        """))

        put(vault, .diary, today, body: SamplesText.text(.todayDiary) ?? T("""
        Сегодня начинается Graphomanus. Утром — план, вечером — итоги дня: под каждым делом строка о том, что вышло.

        Места. Внизу — «Карта». Подержите палец на карте — встанет точка: назовите её и запишите в день. Справа сверху переключатель: «Мои места» — все ваши точки, «Записи» — дни на карте с превью снимков. В записи точку ставит «＋» → «Где я сейчас» — вот так:

        [Гайд-парк](geo:51.50731,-0.16573)

        Вложения. «＋» справа внизу страницы и над клавиатурой: камера, фото, голос, файл. Вложения ложатся под последним текстом записи, по четыре в ряд. Голосовую запись можно расшифровать в текст, а снимок — перенести пальцем прямо в текст или под дело.

        Где лежат записи. Всё — обычные файлы в вашей папке: их видно в «Файлах», они открываются любым редактором и остаются, даже если удалить приложение. Резервная копия — в настройках, одной кнопкой.

        Образцы — вчера, сегодня и завтра. Сотрите их, как обычный текст, или уберите день целиком: три точки справа сверху → «Убрать день в корзину».
        """, """
        Today my Graphomanus begins. In the morning, a plan; in the evening, the day's outcome: a line under each task about how it went.

        Places. At the bottom — “Map”. Hold your finger on the map and a pin appears: name it and add it to the day. The switch at the top right: “My places” shows all your pins, “Entries” shows days on the map with photo previews. In an entry, “＋” → “Where I am” adds a place — like this:

        [Hyde Park](geo:51.50731,-0.16573)

        Attachments. The “＋” at the bottom right of the page and above the keyboard: camera, photos, voice, file. Attachments go under the last text of the entry, four in a row. A voice note can be transcribed to text, and a photo can be dragged straight into the text or under a task.

        Where your entries live. Everything is plain files in your folder: you can see them in Files, open them in any editor, and they stay even if you delete the app. Backup is in the settings, one button.

        The samples are yesterday, today and tomorrow. Erase them like any text, or move the whole day to the trash: the three dots at top right → “Move the day to the trash”.
        """), title: SamplesText.text(.todayTitle) ?? T("Начинаю Graphomanus!", "Starting my Graphomanus!"))

        put(vault, .planner, tomorrow, body: SamplesText.text(.tomorrowPlan) ?? T("""
        - [ ] Вечером записать итоги дня
              Они встанут в дневник под каждым делом — одной строкой.
        - [ ] Заглянуть в «Записи» на карте
        """, """
        - [ ] Write down the day's outcome in the evening
              It goes into the diary under each task — one line each.
        - [ ] Have a look at “Entries” on the map
        """))
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
