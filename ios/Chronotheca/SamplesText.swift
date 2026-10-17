import Foundation

/// Тексты образцов дней на восьми языках, кроме русского и английского
/// (P471): на них образцы стоят прямо в `Samples.swift`. Названия кнопок —
/// те же, что в переводах приложения (`<язык>.lproj/App.strings`). Служебное
/// в тексте не переводится: «## How did it go?», «(remind 18:45)», ссылки
/// `geo:` — по ним приложение узнаёт итоги дня, напоминание и место. Ответы
/// в итогах дня начинаются ровно с названий вчерашних дел.
enum SamplesText {

    enum Key { case yesterdayPlan, walk, walkTitle, todayPlan, todayDiary, todayTitle, tomorrowPlan }

    /// Текст образца на языке приложения; нет такого языка — `nil`, и
    /// `Samples` берёт русский или английский.
    static func text(_ key: Key) -> String? {
        table[Lang.code]?[key]
    }

    private static let table: [String: [Key: String]] = [
        "de": de, "es": es, "fr": fr, "it": it, "nl": nl, "pt": pt, "uk": uk, "ja": ja,
    ]

    // MARK: - Deutsch

    private static let de: [Key: String] = [
        .yesterdayPlan: """
        - [x] 08:30 Brot und Kaffee kaufen
        - [x] 19:00 Mama anrufen (remind 18:45)
        - [ ] Das Kapitel zu Ende lesen
        """,
        .walk: """
        ## How did it go?

        - Brot und Kaffee kaufen: dazu noch Croissants — hat sich gelohnt
        - Mama anrufen: wir haben eine ganze Stunde geredet
        - Das Kapitel zu Ende lesen: hat nicht geklappt — verschiebe ich auf heute

        18:20 Vor Sonnenuntergang in den Park. Die Blätter sind schon gelb, die Luft noch sommerlich.

        [Hyde Park](geo:51.50731,-0.16573)

        Das ist ein Beispiel: So sieht ein gelebter Tag aus — abgehakte Aufgaben, der Rückblick auf den Tag, ein Foto und ein Ort.
        """,
        .walkTitle: "Ein Spaziergang",
        .todayPlan: """
        - [ ] 09:00 Das ist eine Beispielaufgabe: tippen Sie darauf und schreiben Sie Ihre eigene
              Die Eingabetaste führt zur nächsten Aufgabe. Die Uhrzeit links: tippen für Zeit und Wiederholung. Die Glocke ist eine Erinnerung.
        - [ ] Tippen Sie links auf die Nummer — die Aufgabe ist erledigt
              Noch einmal tippen — wieder offen.
        - [ ] Halten Sie eine Aufgabe und bewegen Sie den Finger
              Hoch oder runter zum Umsortieren. Nach rechts auf einen anderen Tag. Nach links löschen.
        - [ ] Eine Aufgabe wiederholen — täglich, wöchentlich, monatlich, jährlich
              Tippen Sie auf die Uhrzeit der Aufgabe: unten „Wiederholen“. Die Wiederholung wird ein Jahr im Voraus eingetragen.
        - [ ] Jeden Tag finden — „Kalender“ unten
              Punkte unter einem Datum bedeuten Einträge an diesem Tag. „Suche“ durchsucht Wörter, Fotos und Orte.
        """,
        .todayDiary: """
        Heute beginnt meine Graphomanus. Morgens ein Plan, abends der Rückblick auf den Tag: unter jeder Aufgabe eine Zeile, wie es gelaufen ist.

        Orte. Unten — „Karte“. Halten Sie den Finger auf die Karte, und eine Nadel erscheint: benennen Sie sie, wählen Sie ein Symbol und fügen Sie sie dem Tag hinzu. Der Schalter oben rechts: „Meine Orte“ zeigt alle Ihre Nadeln, „Einträge“ die Tage auf der Karte mit Fotovorschau. In einem Eintrag fügen Sie einen Ort mit der Taste „Ort“ in der Anhangsleiste hinzu — so:

        [Hyde Park](geo:51.50731,-0.16573)

        Anhänge. Die Leiste unten auf der Seite und über der Tastatur: Kamera, Fotos, Sprache, Dateien. Eine Sprachnotiz lässt sich in Text umwandeln, und ein Foto lässt sich direkt in den Text oder unter eine Aufgabe ziehen.

        Wo Ihre Einträge liegen. Alles sind gewöhnliche Dateien in Ihrem Ordner: Sie sehen sie in „Dateien“, öffnen sie mit jedem Editor, und sie bleiben, selbst wenn Sie die App löschen. Die Sicherung ist in den Einstellungen, mit einer Taste.

        Die Beispiele sind gestern, heute und morgen. Löschen Sie sie wie jeden Text oder legen Sie den ganzen Tag in den Papierkorb: die drei Punkte oben rechts → „Tag in den Papierkorb“.
        """,
        .todayTitle: "Meine Graphomanus beginnt!",
        .tomorrowPlan: """
        - [ ] Abends den Rückblick auf den Tag schreiben
              Er steht im Tagebuch unter jeder Aufgabe — je eine Zeile.
        - [ ] Auf der Karte unter „Einträge“ nachsehen
        """,
    ]

    // MARK: - Español

    private static let es: [Key: String] = [
        .yesterdayPlan: """
        - [x] 08:30 Comprar pan y café
        - [x] 19:00 Llamar a mamá (remind 18:45)
        - [ ] Terminar el capítulo
        """,
        .walk: """
        ## How did it go?

        - Comprar pan y café: también cruasanes, y valió la pena
        - Llamar a mamá: hablamos una hora entera
        - Terminar el capítulo: no pudo ser — lo paso a hoy

        18:20 Salimos al parque antes del atardecer. Las hojas ya están amarillas, pero el aire aún es de verano.

        [Hyde Park](geo:51.50731,-0.16573)

        Esto es un ejemplo: así se ve un día vivido — tareas marcadas, el resumen del día, una foto y un lugar.
        """,
        .walkTitle: "Un paseo",
        .todayPlan: """
        - [ ] 09:00 Esta es una tarea de ejemplo: tóquela y escriba la suya
              Intro le lleva a la siguiente tarea. La hora a la izquierda: tóquela para la hora y la repetición. La campana es un recordatorio.
        - [ ] Toque el número de la izquierda — la tarea está hecha
              Tóquelo otra vez — pendiente de nuevo.
        - [ ] Mantenga pulsada una tarea y mueva el dedo
              Arriba o abajo para reordenar. A la derecha, a otro día. A la izquierda, borrar.
        - [ ] Repetir una tarea — cada día, semana, mes o año
              Toque la hora de la tarea: abajo, «Repetir». La repetición se escribe en los días de un año por delante.
        - [ ] Encontrar cualquier día — «Calendario» abajo
              Los puntos bajo una fecha indican entradas ese día. «Buscar» busca en palabras, fotos y lugares.
        """,
        .todayDiary: """
        Hoy empieza mi Graphomanus. Por la mañana, un plan; por la noche, el resumen del día: bajo cada tarea, una línea sobre cómo fue.

        Lugares. Abajo — «Mapa». Mantenga el dedo sobre el mapa y aparece una chincheta: póngale nombre, elija un icono y añádala al día. El selector arriba a la derecha: «Mis lugares» muestra todas sus chinchetas, «Entradas» muestra los días en el mapa con miniaturas de fotos. En una entrada, añada un lugar con el botón «Lugar» de la barra de adjuntos — así:

        [Hyde Park](geo:51.50731,-0.16573)

        Adjuntos. La barra al pie de la página y sobre el teclado: cámara, fotos, voz, archivos. Una nota de voz puede pasarse a texto, y una foto puede arrastrarse al texto o bajo una tarea.

        Dónde viven sus entradas. Todo son archivos normales en su carpeta: los ve en «Archivos», se abren con cualquier editor y se quedan aunque borre la app. La copia de seguridad está en los ajustes, con un botón.

        Los ejemplos son ayer, hoy y mañana. Bórrelos como cualquier texto o mande el día entero a la papelera: los tres puntos arriba a la derecha → «Mover el día a la papelera».
        """,
        .todayTitle: "¡Empiezo mi Graphomanus!",
        .tomorrowPlan: """
        - [ ] Por la noche, escribir el resumen del día
              Va al diario bajo cada tarea, una línea por tarea.
        - [ ] Mirar «Entradas» en el mapa
        """,
    ]

    // MARK: - Français

    private static let fr: [Key: String] = [
        .yesterdayPlan: """
        - [x] 08:30 Acheter du pain et du café
        - [x] 19:00 Appeler maman (remind 18:45)
        - [ ] Finir le chapitre
        """,
        .walk: """
        ## How did it go?

        - Acheter du pain et du café: des croissants en plus — ça valait le coup
        - Appeler maman: on a parlé une heure entière
        - Finir le chapitre: pas réussi — je le reporte à aujourd’hui

        18:20 Sortis au parc avant le coucher du soleil. Les feuilles sont déjà jaunes, mais l’air est encore estival.

        [Hyde Park](geo:51.50731,-0.16573)

        Ceci est un exemple : voilà à quoi ressemble une journée vécue — tâches cochées, le bilan du jour, une photo et un lieu.
        """,
        .walkTitle: "Une promenade",
        .todayPlan: """
        - [ ] 09:00 Ceci est une tâche d’exemple : touchez-la et écrivez la vôtre
              Retour passe à la tâche suivante. L’heure à gauche : touchez-la pour l’heure et la répétition. La cloche est un rappel.
        - [ ] Touchez le numéro à gauche — la tâche est faite
              Touchez encore — de nouveau à faire.
        - [ ] Maintenez une tâche et déplacez le doigt
              En haut ou en bas pour réordonner. À droite, vers un autre jour. À gauche, supprimer.
        - [ ] Répéter une tâche — chaque jour, semaine, mois ou année
              Touchez l’heure de la tâche : en bas, « Répéter ». La répétition s’inscrit dans les jours d’une année à l’avance.
        - [ ] Trouver n’importe quel jour — « Calendrier » en bas
              Les points sous une date signalent des notes ce jour-là. « Recherche » parcourt les mots, les photos et les lieux.
        """,
        .todayDiary: """
        Aujourd’hui commence ma Graphomanus. Le matin, un plan ; le soir, le bilan du jour : sous chaque tâche, une ligne sur la façon dont elle s’est passée.

        Lieux. En bas — « Carte ». Gardez le doigt sur la carte et une épingle apparaît : nommez-la, choisissez une icône et ajoutez-la au jour. Le sélecteur en haut à droite : « Mes lieux » montre toutes vos épingles, « Notes » montre les jours sur la carte avec des aperçus de photos. Dans une note, ajoutez un lieu avec le bouton « Lieu » de la barre des pièces jointes — comme ceci :

        [Hyde Park](geo:51.50731,-0.16573)

        Pièces jointes. La barre en bas de la page et au-dessus du clavier : appareil photo, photos, voix, fichiers. Une note vocale peut être transcrite en texte, et une photo peut être glissée dans le texte ou sous une tâche.

        Où vivent vos notes. Ce sont de simples fichiers dans votre dossier : vous les voyez dans « Fichiers », ils s’ouvrent avec n’importe quel éditeur et restent même si vous supprimez l’app. La sauvegarde est dans les réglages, en un bouton.

        Les exemples sont hier, aujourd’hui et demain. Effacez-les comme n’importe quel texte, ou mettez le jour entier à la corbeille : les trois points en haut à droite → « Mettre le jour à la corbeille ».
        """,
        .todayTitle: "Je commence ma Graphomanus !",
        .tomorrowPlan: """
        - [ ] Le soir, écrire le bilan du jour
              Il va dans le journal sous chaque tâche, une ligne chacune.
        - [ ] Jeter un œil aux « Notes » sur la carte
        """,
    ]

    // MARK: - Italiano

    private static let it: [Key: String] = [
        .yesterdayPlan: """
        - [x] 08:30 Comprare pane e caffè
        - [x] 19:00 Chiamare la mamma (remind 18:45)
        - [ ] Finire il capitolo
        """,
        .walk: """
        ## How did it go?

        - Comprare pane e caffè: presi anche i cornetti — ne valeva la pena
        - Chiamare la mamma: abbiamo parlato un’ora intera
        - Finire il capitolo: non ce l’ho fatta — lo sposto a oggi

        18:20 Usciti al parco prima del tramonto. Le foglie sono già gialle, ma l’aria è ancora estiva.

        [Hyde Park](geo:51.50731,-0.16573)

        Questo è un esempio: ecco com’è un giorno vissuto — attività spuntate, il bilancio del giorno, una foto e un luogo.
        """,
        .walkTitle: "Una passeggiata",
        .todayPlan: """
        - [ ] 09:00 Questa è un’attività di esempio: toccala e scrivi la tua
              Invio porta all’attività successiva. L’ora a sinistra: toccala per l’ora e la ripetizione. La campanella è un promemoria.
        - [ ] Tocca il numero a sinistra — l’attività è fatta
              Tocca di nuovo — di nuovo da fare.
        - [ ] Tieni premuta un’attività e muovi il dito
              Su o giù per riordinare. A destra, su un altro giorno. A sinistra, eliminare.
        - [ ] Ripetere un’attività — ogni giorno, settimana, mese o anno
              Tocca l’ora dell’attività: in basso, «Ripeti». La ripetizione viene scritta nei giorni di un anno in avanti.
        - [ ] Trovare qualsiasi giorno — «Calendario» in basso
              I puntini sotto una data indicano note quel giorno. «Cerca» cerca tra parole, foto e luoghi.
        """,
        .todayDiary: """
        Oggi comincia la mia Graphomanus. Al mattino un piano, la sera il bilancio del giorno: sotto ogni attività, una riga su com’è andata.

        Luoghi. In basso — «Mappa». Tieni il dito sulla mappa e compare una puntina: dalle un nome, scegli un’icona e aggiungila al giorno. Il selettore in alto a destra: «I miei luoghi» mostra tutte le tue puntine, «Note» mostra i giorni sulla mappa con le anteprime delle foto. In una nota, aggiungi un luogo con il pulsante «Luogo» nella barra degli allegati — così:

        [Hyde Park](geo:51.50731,-0.16573)

        Allegati. La barra in fondo alla pagina e sopra la tastiera: fotocamera, foto, voce, file. Una nota vocale si può trascrivere in testo, e una foto si può trascinare nel testo o sotto un’attività.

        Dove stanno le tue note. Sono normali file nella tua cartella: li vedi in «File», si aprono con qualsiasi editor e restano anche se elimini l’app. Il backup è nelle impostazioni, con un pulsante.

        Gli esempi sono ieri, oggi e domani. Cancellali come qualsiasi testo, o sposta l’intero giorno nel cestino: i tre puntini in alto a destra → «Sposta il giorno nel cestino».
        """,
        .todayTitle: "Comincio la mia Graphomanus!",
        .tomorrowPlan: """
        - [ ] La sera, scrivere il bilancio del giorno
              Va nel diario sotto ogni attività, una riga ciascuna.
        - [ ] Dare un’occhiata alle «Note» sulla mappa
        """,
    ]

    // MARK: - Nederlands

    private static let nl: [Key: String] = [
        .yesterdayPlan: """
        - [x] 08:30 Brood en koffie kopen
        - [x] 19:00 Mama bellen (remind 18:45)
        - [ ] Het hoofdstuk uitlezen
        """,
        .walk: """
        ## How did it go?

        - Brood en koffie kopen: ook croissants — de moeite waard
        - Mama bellen: we hebben een heel uur gepraat
        - Het hoofdstuk uitlezen: lukte niet — ik schuif het naar vandaag

        18:20 Voor zonsondergang naar het park. De bladeren zijn al geel, maar de lucht is nog zomers.

        [Hyde Park](geo:51.50731,-0.16573)

        Dit is een voorbeeld: zo ziet een geleefde dag eruit — afgevinkte taken, de terugblik op de dag, een foto en een plek.
        """,
        .walkTitle: "Een wandeling",
        .todayPlan: """
        - [ ] 09:00 Dit is een voorbeeldtaak: tik erop en schrijf je eigen taak
              Enter brengt je naar de volgende taak. De tijd links: tik voor tijd en herhaling. De bel is een herinnering.
        - [ ] Tik links op het nummer — de taak is klaar
              Tik nog eens — weer open.
        - [ ] Houd een taak vast en beweeg je vinger
              Omhoog of omlaag om te ordenen. Naar rechts naar een andere dag. Naar links verwijderen.
        - [ ] Een taak herhalen — elke dag, week, maand of elk jaar
              Tik op de tijd van de taak: onderaan „Herhalen”. De herhaling wordt een jaar vooruit ingevuld.
        - [ ] Elke dag terugvinden — „Agenda” onderaan
              Stippen onder een datum betekenen aantekeningen op die dag. „Zoek” zoekt in woorden, foto’s en plekken.
        """,
        .todayDiary: """
        Vandaag begint mijn Graphomanus. ’s Ochtends een plan, ’s avonds de terugblik op de dag: onder elke taak een regel over hoe het ging.

        Plekken. Onderaan — „Kaart”. Houd je vinger op de kaart en er verschijnt een speld: geef hem een naam, kies een pictogram en voeg hem toe aan de dag. De schakelaar rechtsboven: „Mijn plekken” toont al je spelden, „Aantekeningen” toont de dagen op de kaart met fotovoorbeelden. In een aantekening voeg je een plek toe met de knop „Plek” in de bijlagenbalk — zo:

        [Hyde Park](geo:51.50731,-0.16573)

        Bijlagen. De balk onderaan de pagina en boven het toetsenbord: camera, foto’s, spraak, bestanden. Een spraakmemo kan worden omgezet in tekst, en een foto kun je zo in de tekst of onder een taak slepen.

        Waar je aantekeningen staan. Alles zijn gewone bestanden in je map: je ziet ze in „Bestanden”, ze openen in elke editor en ze blijven, ook als je de app verwijdert. De back-up staat in de instellingen, met één knop.

        De voorbeelden zijn gisteren, vandaag en morgen. Wis ze als gewone tekst of zet de hele dag in de prullenmand: de drie puntjes rechtsboven → „Dag naar de prullenmand”.
        """,
        .todayTitle: "Mijn Graphomanus begint!",
        .tomorrowPlan: """
        - [ ] ’s Avonds de terugblik op de dag schrijven
              Die komt in het dagboek onder elke taak, één regel per taak.
        - [ ] Een kijkje nemen bij „Aantekeningen” op de kaart
        """,
    ]

    // MARK: - Português

    private static let pt: [Key: String] = [
        .yesterdayPlan: """
        - [x] 08:30 Comprar pão e café
        - [x] 19:00 Ligar para a mãe (remind 18:45)
        - [ ] Terminar o capítulo
        """,
        .walk: """
        ## How did it go?

        - Comprar pão e café: levei croissants também — valeu a pena
        - Ligar para a mãe: conversamos uma hora inteira
        - Terminar o capítulo: não deu — passo para hoje

        18:20 Fomos ao parque antes do pôr do sol. As folhas já estão amarelas, mas o ar ainda é de verão.

        [Hyde Park](geo:51.50731,-0.16573)

        Isto é um exemplo: assim fica um dia vivido — tarefas marcadas, o balanço do dia, uma foto e um lugar.
        """,
        .walkTitle: "Um passeio",
        .todayPlan: """
        - [ ] 09:00 Esta é uma tarefa de exemplo: toque nela e escreva a sua
              Enter leva à próxima tarefa. A hora à esquerda: toque para a hora e a repetição. O sino é um lembrete.
        - [ ] Toque no número à esquerda — a tarefa está feita
              Toque de novo — pendente outra vez.
        - [ ] Segure uma tarefa e mova o dedo
              Para cima ou para baixo para reordenar. Para a direita, para outro dia. Para a esquerda, apagar.
        - [ ] Repetir uma tarefa — todo dia, semana, mês ou ano
              Toque na hora da tarefa: embaixo, «Repetir». A repetição é escrita nos dias de um ano à frente.
        - [ ] Encontrar qualquer dia — «Calendário» embaixo
              Pontos sob uma data indicam anotações nesse dia. «Busca» procura em palavras, fotos e lugares.
        """,
        .todayDiary: """
        Hoje começa a minha Graphomanus. De manhã, um plano; à noite, o balanço do dia: sob cada tarefa, uma linha sobre como foi.

        Lugares. Embaixo — «Mapa». Mantenha o dedo no mapa e aparece um alfinete: dê-lhe um nome, escolha um ícone e adicione-o ao dia. O seletor no canto superior direito: «Meus lugares» mostra todos os seus alfinetes, «Anotações» mostra os dias no mapa com miniaturas de fotos. Numa anotação, adicione um lugar com o botão «Lugar» na barra de anexos — assim:

        [Hyde Park](geo:51.50731,-0.16573)

        Anexos. A barra no pé da página e acima do teclado: câmara, fotos, voz, ficheiros. Uma nota de voz pode ser transcrita em texto, e uma foto pode ser arrastada para o texto ou para baixo de uma tarefa.

        Onde ficam as suas anotações. Tudo são ficheiros comuns na sua pasta: aparecem em «Arquivos», abrem em qualquer editor e ficam mesmo que apague a app. A cópia de segurança está nos ajustes, com um botão.

        Os exemplos são ontem, hoje e amanhã. Apague-os como qualquer texto ou mande o dia inteiro para o lixo: os três pontos no canto superior direito → «Mover o dia para o lixo».
        """,
        .todayTitle: "Começo a minha Graphomanus!",
        .tomorrowPlan: """
        - [ ] À noite, escrever o balanço do dia
              Vai para o diário sob cada tarefa, uma linha cada.
        - [ ] Dar uma olhada em «Anotações» no mapa
        """,
    ]

    // MARK: - Українська

    private static let uk: [Key: String] = [
        .yesterdayPlan: """
        - [x] 08:30 Купити хліб і каву
        - [x] 19:00 Подзвонити мамі (remind 18:45)
        - [ ] Дочитати розділ
        """,
        .walk: """
        ## How did it go?

        - Купити хліб і каву: взяли ще круасани — і недарма
        - Подзвонити мамі: проговорили цілу годину
        - Дочитати розділ: не вийшло — перенесу на сьогодні

        18:20 Вийшли в парк до заходу сонця. Листя вже жовте, а повітря ще літнє.

        [Гайд-парк](geo:51.50731,-0.16573)

        Це зразок: так виглядає прожитий день — справи з позначками, підсумки дня, знімок і місце.
        """,
        .walkTitle: "Прогулянка",
        .todayPlan: """
        - [ ] 09:00 Це справа-зразок: торкніться її і пишіть своє
              «Ввід» — до наступної справи. Час ліворуч: торкніться — час і повтор. Дзвіночок — нагадування.
        - [ ] Торкніться номера ліворуч — справу зроблено
              Торкніться ще раз — знову не зроблено.
        - [ ] Притримайте справу і ведіть пальцем
              Вгору-вниз — переставити. Праворуч — на інший день. Ліворуч — видалити.
        - [ ] Повторювати справу — щодня, щотижня, щомісяця, щороку
              Торкніться часу справи: внизу — «Повторювати». Повтор впишеться в дні на рік уперед.
        - [ ] Знайти будь-який день — «Календар» унизу
              Крапки під числом — у цей день є записи. «Пошук» шукає за словами, знімками і місцями.
        """,
        .todayDiary: """
        Сьогодні починається Graphomanus. Уранці — план, увечері — підсумки дня: під кожною справою рядок про те, що вийшло.

        Місця. Унизу — «Мапа». Притримайте палець на мапі — з’явиться точка: назвіть її, виберіть значок і запишіть у день. Праворуч угорі перемикач: «Мої місця» — усі ваші точки, «Записи» — дні на мапі з прев’ю знімків. У записі точка ставиться кнопкою «Точка» в рядку вкладень — ось так:

        [Гайд-парк](geo:51.50731,-0.16573)

        Вкладення. Рядок унизу сторінки і над клавіатурою: камера, фото, голос, файли. Голосовий запис можна розшифрувати в текст, а знімок — перенести пальцем просто в текст або під справу.

        Де лежать записи. Усе — звичайні файли у вашій теці: їх видно у «Файлах», вони відкриваються будь-яким редактором і лишаються, навіть якщо видалити застосунок. Резервна копія — в налаштуваннях, однією кнопкою.

        Зразки — вчора, сьогодні й завтра. Зітріть їх, як звичайний текст, або приберіть день цілком: три крапки праворуч угорі → «Прибрати день у кошик».
        """,
        .todayTitle: "Починаю Graphomanus!",
        .tomorrowPlan: """
        - [ ] Увечері записати підсумки дня
              Вони стануть у щоденник під кожною справою — одним рядком.
        - [ ] Зазирнути в «Записи» на мапі
        """,
    ]

    // MARK: - 日本語

    private static let ja: [Key: String] = [
        .yesterdayPlan: """
        - [x] 08:30 パンとコーヒーを買う
        - [x] 19:00 母に電話する (remind 18:45)
        - [ ] 章を読み終える
        """,
        .walk: """
        ## How did it go?

        - パンとコーヒーを買う: クロワッサンも買った — 正解だった
        - 母に電話する: まる一時間話した
        - 章を読み終える: できなかった — 今日に回す

        18:20 日が沈む前に公園へ。葉はもう黄色いのに、空気はまだ夏のよう。

        [ハイドパーク](geo:51.50731,-0.16573)

        これは見本です。過ごした一日はこう見えます — チェックした予定、一日のふり返り、写真、そして場所。
        """,
        .walkTitle: "散歩",
        .todayPlan: """
        - [ ] 09:00 これは見本の予定です。タップして自分の予定を書いてください
              改行で次の予定へ。左の時刻をタップすると時刻と繰り返し。ベルはリマインダーです。
        - [ ] 左の番号をタップ — 予定が済みになります
              もう一度タップ — 未完了に戻ります。
        - [ ] 予定を長押しして指を動かす
              上下で並べ替え。右へで別の日へ。左へで削除。
        - [ ] 予定を繰り返す — 毎日、毎週、毎月、毎年
              予定の時刻をタップ: 下に「繰り返し」。繰り返しは一年先まで書き込まれます。
        - [ ] どの日でも探せる — 下の「カレンダー」
              日付の下の点はその日の記録があるしるし。「検索」は言葉、写真、場所から探します。
        """,
        .todayDiary: """
        今日から私のクロノテカが始まる。朝は予定、夜は一日のふり返り: それぞれの予定の下に、どうだったかを一行。

        場所。下の「地図」。地図を長押しするとピンが立ちます: 名前をつけ、アイコンを選び、その日に加えましょう。右上の切り替え: 「自分の場所」はすべてのピン、「記録」は写真のプレビュー付きで日々を地図に表示します。記録の中では、添付バーの「場所」ボタンで場所を加えます — このように:

        [ハイドパーク](geo:51.50731,-0.16573)

        添付。ページの下とキーボードの上のバー: カメラ、写真、音声、ファイル。音声メモは文字に起こせ、写真は指で本文や予定の下へそのまま移せます。

        記録の保存場所。すべてあなたのフォルダの普通のファイルです: 「ファイル」で見え、どんなエディタでも開け、アプリを削除しても残ります。バックアップは設定からボタンひとつで。

        見本は昨日、今日、明日です。普通の文字のように消すか、日ごと捨ててください: 右上の三つの点 →「この日をゴミ箱へ」。
        """,
        .todayTitle: "クロノテカを始めます!",
        .tomorrowPlan: """
        - [ ] 夜に一日のふり返りを書く
              日記の各予定の下に一行ずつ入ります。
        - [ ] 地図の「記録」をのぞいてみる
        """,
    ]
}
