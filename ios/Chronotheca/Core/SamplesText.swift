import Foundation

/// Тексты образцов дней на восьми языках, кроме русского и английского
/// (P471): на них образцы стоят прямо в `Samples.swift`. Названия кнопок —
/// те же, что в переводах приложения (`<язык>.lproj/App.strings`). Служебное
/// в тексте не переводится: «## How did it go?», «(remind 18:45)», ссылки
/// `geo:` — по ним приложение узнаёт итоги дня, напоминание и место. Ответы
/// в итогах дня начинаются ровно с названий вчерашних дел.
enum SamplesText {

    enum Key { case yesterdayPlan, walk, walkTitle, todayPlan, todayDiary, todayTitle, tomorrowPlan,
                    howto, howtoTitle, laterPlan }

    /// Текст образца на языке приложения; нет такого языка — `nil`, и
    /// `Samples` берёт русский или английский.
    static func text(_ key: Key) -> String? {
        table[Lang.code]?[key]
    }

    private static let table: [String: [Key: String]] = [
        "de": de, "es": es, "fr": fr, "it": it, "nl": nl, "pt": pt, "uk": uk, "ka": ka, "ja": ja,
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
              Die Eingabetaste führt zur nächsten Aufgabe.
        - [ ] Ziehen Sie das Blatt nach oben — die kommenden Tage erklären alles über Aufgaben
        """,
        .todayDiary: """
        Heute beginnt meine RollingDays. Morgens ein Plan, abends der Rückblick auf den Tag: unter jeder Aufgabe eine Zeile, wie es gelaufen ist.

        Orte. Unten — „Karte“. Halten Sie den Finger auf die Karte, und eine Nadel erscheint: benennen Sie sie und fügen Sie sie dem Tag hinzu. Der Schalter oben rechts: „Meine Orte“ zeigt alle Ihre Nadeln, „Einträge“ die Tage auf der Karte mit Fotovorschau. In einem Eintrag fügt „＋“ → „Wo ich bin“ einen Ort hinzu — so:

        [Hyde Park](geo:51.50731,-0.16573)

        Anhänge. „＋“ unten rechts auf der Seite und über der Tastatur: Kamera, Fotos, Stimme, Datei. Anhänge kommen unter den letzten Text des Eintrags, vier in einer Reihe. Eine Sprachnotiz lässt sich in Text umwandeln, und ein Foto lässt sich direkt in den Text oder unter eine Aufgabe ziehen.

        Wo Ihre Einträge liegen. Alles sind gewöhnliche Dateien in Ihrem Ordner: Sie sehen sie in „Dateien“, öffnen sie mit jedem Editor, und sie bleiben, selbst wenn Sie die App löschen. Die Sicherung ist in den Einstellungen, mit einer Taste.

        Die Beispiele sind zwei Tage in der Vergangenheit und zwei in der Zukunft. Löschen Sie sie wie jeden Text oder legen Sie den ganzen Tag in den Papierkorb: Tippen Sie oben auf den Namen des Tages → „Tag in den Papierkorb“.
        """,
        .todayTitle: "Meine RollingDays beginnt!",
        .tomorrowPlan: """
        - [ ] Tippen Sie links auf die Nummer — die Aufgabe ist erledigt
              Noch einmal tippen — wieder offen.
        - [ ] Halten Sie die Nummer und bewegen Sie den Finger
              Hoch oder runter zum Umsortieren. Nach rechts auf einen anderen Tag. Nach links löschen.
        - [ ] 10:00 Tippen Sie links auf die Uhrzeit — Zeit und Wiederholung
              Wiederholen täglich, wöchentlich, monatlich oder jährlich. Die Glocke ist eine Erinnerung.
        """,
        .howto: """
        Das ist ein Beispiel für einen vergangenen Tag. Jeder Tag ist eine Karte in der Kartei.

        Die Kartei. Ziehen Sie das Blatt „Heute“ nach unten — die Vergangenheit öffnet sich, nach oben — die Zukunft. Tippen Sie auf eine Karte — ihr Tag öffnet sich. Wischen Sie einen geöffneten Tag nach oben oder unten — er kehrt als Karte an seinen Platz zurück. „Heute“ am Bildschirmrand bringt Sie zurück zu heute.

        Bereiche. Wischen Sie zur Seite: links die Karte, rechts der Kalender. Die Tasten unten führen ebenfalls dorthin.

        Suche. Die Lupe unten in der Kartei sucht nach Wörtern, Fotos und Orten.

        Fotos. Halten Sie ein Foto und bewegen Sie den Finger — es wandert an eine andere Stelle im Text oder unter eine Aufgabe.

        Das Tagesmenü. Tippen Sie oben auf den Namen des Tages: „Tag teilen“, „PDF des Tages“, „Tag in den Papierkorb“.
        """,
        .howtoTitle: "So funktioniert alles",
        .laterPlan: """
        - [ ] Abends sagen, wie es gelaufen ist
              Unter jeder Aufgabe eine Zeile, wie es ausgegangen ist. Sie kommt ins Tagebuch des Tages.
        - [ ] Ein Foto oder eine Sprachnotiz in den Plan legen
              „＋“ unten auf der Seite: An einem kommenden Tag kommt der Anhang unter eine Aufgabe.
        - [ ] Die Beispiele entfernen, wenn Sie sie nicht mehr brauchen
              Löschen Sie sie wie jeden Text oder tippen Sie auf den Namen des Tages → „Tag in den Papierkorb“.
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
        - [ ] 09:00 Esta es una tarea de ejemplo: tócala y escribe la tuya
              Intro te lleva a la siguiente tarea.
        - [ ] Desliza la hoja hacia arriba: los próximos días lo explican todo sobre las tareas
        """,
        .todayDiary: """
        Hoy empieza mi RollingDays. Por la mañana, un plan; por la noche, el resumen del día: bajo cada tarea, una línea sobre cómo fue.

        Lugares. Abajo — «Mapa». Mantenga el dedo sobre el mapa y aparece una chincheta: póngale nombre y añádala al día. El selector arriba a la derecha: «Mis lugares» muestra todas sus chinchetas, «Entradas» muestra los días en el mapa con miniaturas de fotos. En una entrada, «＋» → «Dónde estoy» añade un lugar — así:

        [Hyde Park](geo:51.50731,-0.16573)

        Adjuntos. «＋» abajo a la derecha de la página y sobre el teclado: cámara, fotos, voz, archivo. Los adjuntos quedan bajo el último texto de la entrada, cuatro por fila. Una nota de voz puede pasarse a texto, y una foto puede arrastrarse al texto o bajo una tarea.

        Dónde viven sus entradas. Todo son archivos normales en su carpeta: los ve en «Archivos», se abren con cualquier editor y se quedan aunque borre la app. La copia de seguridad está en los ajustes, con un botón.

        Los ejemplos son dos días en el pasado y dos en el futuro. Bórralos como cualquier texto o lleva el día entero a la papelera: toca el nombre del día arriba → «Mover el día a la papelera».
        """,
        .todayTitle: "¡Empiezo mi RollingDays!",
        .tomorrowPlan: """
        - [ ] Toca el número de la izquierda: la tarea está hecha
              Tócalo otra vez: sin hacer.
        - [ ] Mantén pulsado el número y mueve el dedo
              Arriba o abajo para reordenar. A la derecha, a otro día. A la izquierda, eliminar.
        - [ ] 10:00 Toca la hora de la izquierda: hora y repetición
              Repetir cada día, semana, mes o año. La campana es un recordatorio.
        """,
        .howto: """
        Este es un ejemplo de un día pasado. Cada día es una tarjeta en el fichero.

        El fichero. Desliza la hoja «Hoy» hacia abajo y se abre el pasado; hacia arriba, el futuro. Toca una tarjeta y se abre su día. Desliza un día abierto hacia arriba o hacia abajo y vuelve a su sitio como tarjeta. «Hoy» en el borde de la pantalla te devuelve al día de hoy.

        Secciones. Desliza hacia un lado: a la izquierda el mapa, a la derecha el calendario. Los botones de abajo llevan al mismo sitio.

        Búsqueda. La lupa de abajo en el fichero busca palabras, fotos y lugares.

        Fotos. Mantén pulsada una foto y mueve el dedo: pasa a otro sitio del texto o debajo de una tarea.

        El menú del día. Toca el nombre del día arriba: «Compartir el día», «PDF del día», «Mover el día a la papelera».
        """,
        .howtoTitle: "Cómo funciona todo",
        .laterPlan: """
        - [ ] Por la noche, contar cómo fue
              Una línea bajo cada tarea sobre cómo salió. Va al diario del día.
        - [ ] Poner una foto o una nota de voz en el plan
              «＋» abajo en la página: en un día futuro el adjunto va debajo de una tarea.
        - [ ] Quitar los ejemplos cuando ya no los necesites
              Bórralos como cualquier texto, o toca el nombre del día → «Mover el día a la papelera».
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
              Retour passe à la tâche suivante.
        - [ ] Tirez la feuille vers le haut : les jours à venir expliquent tout sur les tâches
        """,
        .todayDiary: """
        Aujourd’hui commence ma RollingDays. Le matin, un plan ; le soir, le bilan du jour : sous chaque tâche, une ligne sur la façon dont elle s’est passée.

        Lieux. En bas — « Carte ». Gardez le doigt sur la carte et une épingle apparaît : nommez-la et ajoutez-la au jour. Le sélecteur en haut à droite : « Mes lieux » montre toutes vos épingles, « Notes » montre les jours sur la carte avec des aperçus de photos. Dans une note, « ＋ » → « Où je suis » ajoute un lieu — comme ceci :

        [Hyde Park](geo:51.50731,-0.16573)

        Pièces jointes. « ＋ » en bas à droite de la page et au-dessus du clavier : appareil photo, photos, voix, fichier. Les pièces jointes se placent sous le dernier texte de la note, quatre par rang. Une note vocale peut être transcrite en texte, et une photo peut être glissée dans le texte ou sous une tâche.

        Où vivent vos notes. Ce sont de simples fichiers dans votre dossier : vous les voyez dans « Fichiers », ils s’ouvrent avec n’importe quel éditeur et restent même si vous supprimez l’app. La sauvegarde est dans les réglages, en un bouton.

        Les exemples sont deux jours dans le passé et deux à venir. Effacez-les comme n’importe quel texte, ou mettez tout le jour à la corbeille : touchez le nom du jour en haut → « Mettre le jour à la corbeille ».
        """,
        .todayTitle: "Je commence ma RollingDays !",
        .tomorrowPlan: """
        - [ ] Touchez le numéro à gauche : la tâche est faite
              Touchez encore : pas faite.
        - [ ] Maintenez le numéro et déplacez le doigt
              Haut ou bas pour réordonner. À droite, vers un autre jour. À gauche, supprimer.
        - [ ] 10:00 Touchez l’heure à gauche : heure et répétition
              Répéter chaque jour, semaine, mois ou année. La cloche est un rappel.
        """,
        .howto: """
        Voici un exemple de jour passé. Chaque jour est une fiche dans le fichier.

        Le fichier. Tirez la feuille « Aujourd’hui » vers le bas : le passé s’ouvre ; vers le haut : l’avenir. Touchez une fiche : son jour s’ouvre. Faites glisser un jour ouvert vers le haut ou le bas : il retourne à sa place sous forme de fiche. « Aujourd’hui » au bord de l’écran vous ramène à aujourd’hui.

        Les sections. Balayez sur le côté : à gauche la carte, à droite le calendrier. Les boutons du bas y mènent aussi.

        La recherche. La loupe en bas du fichier cherche dans les mots, les photos et les lieux.

        Les photos. Maintenez une photo et déplacez le doigt : elle va ailleurs dans le texte ou sous une tâche.

        Le menu du jour. Touchez le nom du jour en haut : « Partager le jour », « PDF du jour », « Mettre le jour à la corbeille ».
        """,
        .howtoTitle: "Comment tout fonctionne",
        .laterPlan: """
        - [ ] Le soir, dire comment ça s’est passé
              Une ligne sous chaque tâche sur ce qu’il en est sorti. Elle va dans le journal du jour.
        - [ ] Mettre une photo ou une note vocale dans le plan
              « ＋ » en bas de la page : un jour à venir, la pièce jointe va sous une tâche.
        - [ ] Retirer les exemples quand ils ne servent plus
              Effacez-les comme du texte, ou touchez le nom du jour → « Mettre le jour à la corbeille ».
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
        - [ ] 09:00 Questo è un impegno di esempio: toccalo e scrivi il tuo
              Invio passa all’impegno successivo.
        - [ ] Trascina il foglio verso l’alto: i prossimi giorni spiegano tutto sugli impegni
        """,
        .todayDiary: """
        Oggi comincia la mia RollingDays. Al mattino un piano, la sera il bilancio del giorno: sotto ogni attività, una riga su com’è andata.

        Luoghi. In basso — «Mappa». Tieni il dito sulla mappa e compare una puntina: dalle un nome e aggiungila al giorno. Il selettore in alto a destra: «I miei luoghi» mostra tutte le tue puntine, «Note» mostra i giorni sulla mappa con le anteprime delle foto. In una nota, «＋» → «Dove sono» aggiunge un luogo — così:

        [Hyde Park](geo:51.50731,-0.16573)

        Allegati. «＋» in basso a destra della pagina e sopra la tastiera: fotocamera, foto, voce, file. Gli allegati vanno sotto l’ultimo testo della nota, quattro per riga. Una nota vocale si può trascrivere in testo, e una foto si può trascinare nel testo o sotto un’attività.

        Dove stanno le tue note. Sono normali file nella tua cartella: li vedi in «File», si aprono con qualsiasi editor e restano anche se elimini l’app. Il backup è nelle impostazioni, con un pulsante.

        Gli esempi sono due giorni nel passato e due nel futuro. Cancellali come qualsiasi testo o sposta l’intero giorno nel cestino: tocca il nome del giorno in alto → «Sposta il giorno nel cestino».
        """,
        .todayTitle: "Comincio la mia RollingDays!",
        .tomorrowPlan: """
        - [ ] Tocca il numero a sinistra: l’impegno è fatto
              Toccalo di nuovo: non fatto.
        - [ ] Tieni premuto il numero e muovi il dito
              Su o giù per riordinare. A destra, a un altro giorno. A sinistra, eliminare.
        - [ ] 10:00 Tocca l’ora a sinistra: ora e ripetizione
              Ripeti ogni giorno, settimana, mese o anno. La campanella è un promemoria.
        """,
        .howto: """
        Questo è un esempio di giorno passato. Ogni giorno è una scheda nello schedario.

        Lo schedario. Trascina il foglio «Oggi» verso il basso e si apre il passato; verso l’alto, il futuro. Tocca una scheda e si apre il suo giorno. Scorri un giorno aperto verso l’alto o il basso e torna al suo posto come scheda. «Oggi» sul bordo dello schermo ti riporta a oggi.

        Sezioni. Scorri di lato: a sinistra la mappa, a destra il calendario. Ci portano anche i pulsanti in basso.

        Ricerca. La lente in basso nello schedario cerca parole, foto e luoghi.

        Foto. Tieni premuta una foto e muovi il dito: va in un altro punto del testo o sotto un impegno.

        Il menu del giorno. Tocca il nome del giorno in alto: «Condividi il giorno», «PDF del giorno», «Sposta il giorno nel cestino».
        """,
        .howtoTitle: "Come funziona tutto",
        .laterPlan: """
        - [ ] La sera, dire com’è andata
              Una riga sotto ogni impegno su com’è finita. Va nel diario del giorno.
        - [ ] Mettere una foto o una nota vocale nel piano
              «＋» in basso nella pagina: in un giorno futuro l’allegato va sotto un impegno.
        - [ ] Togliere gli esempi quando non servono più
              Cancellali come qualsiasi testo, o tocca il nome del giorno → «Sposta il giorno nel cestino».
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
        - [ ] 09:00 Dit is een voorbeeldtaak: tik erop en schrijf je eigen
              Return gaat naar de volgende taak.
        - [ ] Trek het blad omhoog: de komende dagen vertellen alles over taken
        """,
        .todayDiary: """
        Vandaag begint mijn RollingDays. ’s Ochtends een plan, ’s avonds de terugblik op de dag: onder elke taak een regel over hoe het ging.

        Plekken. Onderaan — „Kaart”. Houd je vinger op de kaart en er verschijnt een speld: geef hem een naam en voeg hem toe aan de dag. De schakelaar rechtsboven: „Mijn plekken” toont al je spelden, „Aantekeningen” toont de dagen op de kaart met fotovoorbeelden. In een aantekening voegt „＋” → „Waar ik ben” een plek toe — zo:

        [Hyde Park](geo:51.50731,-0.16573)

        Bijlagen. „＋” rechtsonder op de pagina en boven het toetsenbord: camera, foto’s, stem, bestand. Bijlagen komen onder de laatste tekst van de aantekening, vier op een rij. Een spraakmemo kan worden omgezet in tekst, en een foto kun je zo in de tekst of onder een taak slepen.

        Waar je aantekeningen staan. Alles zijn gewone bestanden in je map: je ziet ze in „Bestanden”, ze openen in elke editor en ze blijven, ook als je de app verwijdert. De back-up staat in de instellingen, met één knop.

        De voorbeelden zijn twee dagen in het verleden en twee in de toekomst. Wis ze als gewone tekst of zet de hele dag in de prullenmand: tik bovenaan op de naam van de dag → ‘Dag naar de prullenmand’.
        """,
        .todayTitle: "Mijn RollingDays begint!",
        .tomorrowPlan: """
        - [ ] Tik links op het nummer: de taak is klaar
              Nog eens tikken: niet klaar.
        - [ ] Houd het nummer vast en beweeg je vinger
              Omhoog of omlaag om te ordenen. Naar rechts naar een andere dag. Naar links verwijderen.
        - [ ] 10:00 Tik links op de tijd: tijd en herhaling
              Herhaal elke dag, week, maand of jaar. Het belletje is een herinnering.
        """,
        .howto: """
        Dit is een voorbeeld van een voorbije dag. Elke dag is een kaart in de kaartenbak.

        De kaartenbak. Trek het blad ‘Vandaag’ omlaag en het verleden gaat open; omhoog, de toekomst. Tik op een kaart en de dag gaat open. Veeg een geopende dag omhoog of omlaag en hij gaat als kaart terug naar zijn plek. ‘Vandaag’ aan de rand van het scherm brengt je terug naar vandaag.

        Onderdelen. Veeg opzij: links de kaart, rechts de agenda. De knoppen onderaan gaan er ook heen.

        Zoeken. Het vergrootglas onder in de kaartenbak zoekt in woorden, foto’s en plaatsen.

        Foto’s. Houd een foto vast en beweeg je vinger: hij gaat naar een andere plek in de tekst of onder een taak.

        Het dagmenu. Tik bovenaan op de naam van de dag: ‘Dag delen’, ‘PDF van de dag’, ‘Dag naar de prullenmand’.
        """,
        .howtoTitle: "Hoe alles werkt",
        .laterPlan: """
        - [ ] ’s Avonds zeggen hoe het ging
              Eén regel onder elke taak over hoe het afliep. Die gaat in het dagboek van de dag.
        - [ ] Een foto of spraakmemo in het plan zetten
              ‘＋’ onderaan de pagina: op een komende dag komt de bijlage onder een taak.
        - [ ] De voorbeelden weghalen als je ze niet meer nodig hebt
              Wis ze als gewone tekst, of tik op de naam van de dag → ‘Dag naar de prullenmand’.
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
              Enter passa para a tarefa seguinte.
        - [ ] Puxe a folha para cima: os próximos dias explicam tudo sobre as tarefas
        """,
        .todayDiary: """
        Hoje começa a minha RollingDays. De manhã, um plano; à noite, o balanço do dia: sob cada tarefa, uma linha sobre como foi.

        Lugares. Embaixo — «Mapa». Mantenha o dedo no mapa e aparece um alfinete: dê-lhe um nome e adicione-o ao dia. O seletor no canto superior direito: «Meus lugares» mostra todos os seus alfinetes, «Anotações» mostra os dias no mapa com miniaturas de fotos. Numa anotação, «＋» → «Onde estou» adiciona um lugar — assim:

        [Hyde Park](geo:51.50731,-0.16573)

        Anexos. «＋» no canto inferior direito da página e acima do teclado: câmara, fotos, voz, arquivo. Os anexos ficam sob o último texto da anotação, quatro por fila. Uma nota de voz pode ser transcrita em texto, e uma foto pode ser arrastada para o texto ou para baixo de uma tarefa.

        Onde ficam as suas anotações. Tudo são ficheiros comuns na sua pasta: aparecem em «Arquivos», abrem em qualquer editor e ficam mesmo que apague a app. A cópia de segurança está nos ajustes, com um botão.

        Os exemplos são dois dias no passado e dois no futuro. Apague-os como qualquer texto ou mande o dia inteiro para o lixo: toque no nome do dia em cima → «Mover o dia para o lixo».
        """,
        .todayTitle: "Começo a minha RollingDays!",
        .tomorrowPlan: """
        - [ ] Toque no número à esquerda: a tarefa está feita
              Toque outra vez: por fazer.
        - [ ] Mantenha premido o número e mova o dedo
              Para cima ou para baixo para reordenar. Para a direita, para outro dia. Para a esquerda, apagar.
        - [ ] 10:00 Toque na hora à esquerda: hora e repetição
              Repetir todos os dias, semanas, meses ou anos. O sino é um lembrete.
        """,
        .howto: """
        Este é um exemplo de um dia passado. Cada dia é um cartão no ficheiro.

        O ficheiro. Puxe a folha «Hoje» para baixo e abre-se o passado; para cima, o futuro. Toque num cartão e o seu dia abre-se. Deslize um dia aberto para cima ou para baixo e ele volta ao seu lugar como cartão. «Hoje» na margem do ecrã leva-o de volta ao dia de hoje.

        Secções. Deslize para o lado: à esquerda o mapa, à direita o calendário. Os botões em baixo levam ao mesmo sítio.

        Pesquisa. A lupa em baixo no ficheiro procura palavras, fotos e lugares.

        Fotos. Mantenha premida uma foto e mova o dedo: ela vai para outro ponto do texto ou para debaixo de uma tarefa.

        O menu do dia. Toque no nome do dia em cima: «Compartilhar o dia», «PDF do dia», «Mover o dia para o lixo».
        """,
        .howtoTitle: "Como tudo funciona",
        .laterPlan: """
        - [ ] À noite, dizer como correu
              Uma linha debaixo de cada tarefa sobre como correu. Vai para o diário do dia.
        - [ ] Pôr uma foto ou uma nota de voz no plano
              «＋» em baixo na página: num dia futuro o anexo fica debaixo de uma tarefa.
        - [ ] Tirar os exemplos quando já não precisar deles
              Apague-os como qualquer texto, ou toque no nome do dia → «Mover o dia para o lixo».
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
        - [ ] 09:00 Це справа-зразок: торкніться її і пишіть свою
              «Ввід» — до наступної справи.
        - [ ] Потягніть аркуш угору — у майбутніх днях усе про справи
        """,
        .todayDiary: """
        Сьогодні починається RollingDays. Уранці — план, увечері — підсумки дня: під кожною справою рядок про те, що вийшло.

        Місця. Унизу — «Мапа». Притримайте палець на мапі — з’явиться точка: назвіть її і запишіть у день. Праворуч угорі перемикач: «Мої місця» — усі ваші точки, «Записи» — дні на мапі з прев’ю знімків. У записі точку ставить «＋» → «Де я зараз» — ось так:

        [Гайд-парк](geo:51.50731,-0.16573)

        Вкладення. «＋» праворуч унизу сторінки і над клавіатурою: камера, фото, голос, файл. Вкладення лягають під останнім текстом запису, по чотири в ряд. Голосовий запис можна розшифрувати в текст, а знімок — перенести пальцем просто в текст або під справу.

        Де лежать записи. Усе — звичайні файли у вашій теці: їх видно у «Файлах», вони відкриваються будь-яким редактором і лишаються, навіть якщо видалити застосунок. Резервна копія — в налаштуваннях, однією кнопкою.

        Зразки — два дні в минулому і два в майбутньому. Зітріть їх, як звичайний текст, або приберіть день цілком: торкніться назви дня вгорі → «Прибрати день у кошик».
        """,
        .todayTitle: "Починаю RollingDays!",
        .tomorrowPlan: """
        - [ ] Торкніться номера ліворуч — справу зроблено
              Торкніться ще раз — знову не зроблено.
        - [ ] Притримайте номер і ведіть пальцем
              Угору чи вниз — переставити. Праворуч — на інший день. Ліворуч — видалити.
        - [ ] 10:00 Торкніться часу ліворуч — час і повтор
              Повторювати щодня, щотижня, щомісяця чи щороку. Дзвіночок — нагадування.
        """,
        .howto: """
        Це зразок минулого дня. Кожен день — картка в картотеці.

        Картотека. Потягніть аркуш «Сьогодні» вниз — відкриється минуле, вгору — майбутнє. Торкніться картки — відкриється її день. Змахніть відкритий день угору чи вниз — він ляже карткою на своє місце. «Сьогодні» біля краю екрана поверне до сьогоднішнього дня.

        Розділи. Змахніть убік: ліворуч — мапа, праворуч — календар. Кнопки внизу ведуть туди ж.

        Пошук. Лупа внизу картотеки шукає за словами, знімками й місцями.

        Знімки. Притримайте знімок і ведіть пальцем — він стане в інше місце тексту або під справу.

        Меню дня. Торкніться назви дня вгорі: «Поділитися днем», «PDF дня», «Прибрати день у кошик».
        """,
        .howtoTitle: "Як тут усе влаштовано",
        .laterPlan: """
        - [ ] Увечері відповісти, як минуло
              Під кожною справою — один рядок про те, що вийшло. Він ляже в щоденник дня.
        - [ ] Покласти в план знімок або голос
              «＋» унизу сторінки: у майбутньому дні вкладення стає під справу.
        - [ ] Прибрати зразки, коли стануть не потрібні
              Зітріть їх, як текст, або торкніться назви дня → «Прибрати день у кошик».
        """,
    ]

    // MARK: - ქართული

    private static let ka: [Key: String] = [
        .yesterdayPlan: """
        - [x] 08:30 პურისა და ყავის ყიდვა
        - [x] 19:00 დედასთან დარეკვა (remind 18:45)
        - [ ] თავის ბოლომდე წაკითხვა
        """,
        .walk: """
        ## How did it go?

        - პურისა და ყავის ყიდვა: კრუასანებიც ვიყიდეთ — და ტყუილად არა
        - დედასთან დარეკვა: მთელი საათი ვილაპარაკეთ
        - თავის ბოლომდე წაკითხვა: ვერ მოვასწარი — დღევანდელზე გადავდებ

        18:20 მზის ჩასვლამდე პარკში გავედით. ფოთლები უკვე ყვითელია, ჰაერი კი ჯერ კიდევ ზაფხულისაა.

        [ჰაიდ-პარკი](geo:51.50731,-0.16573)

        ეს ნიმუშია: ასე გამოიყურება განვლილი დღე — საქმეები ნიშნებით, დღის შედეგები, ფოტო და ადგილი.
        """,
        .walkTitle: "გასეირნება",
        .todayPlan: """
        - [ ] 09:00 ეს ნიმუში საქმეა: შეეხეთ და დაწერეთ თქვენი
              „Enter“ — შემდეგ საქმეზე.
        - [ ] გადაწიეთ ფურცელი ზემოთ — მომავალ დღეებში ყველაფერია საქმეებზე
        """,
        .todayDiary: """
        დღეს იწყება RollingDays. დილით — გეგმა, საღამოს — დღის შედეგები: ყოველი საქმის ქვეშ ერთი სტრიქონი იმაზე, რა გამოვიდა.

        ადგილები. ქვემოთ — „რუკა“. დაიჭირეთ თითი რუკაზე — გაჩნდება წერტილი: დაარქვით სახელი და ჩაწერეთ დღეში. ზემოთ მარჯვნივ გადამრთველია: „ჩემი ადგილები“ — ყველა თქვენი წერტილი, „ჩანაწერები“ — დღეები რუკაზე ფოტოების ესკიზებით. ჩანაწერში წერტილს სვამს „＋“ → „სად ვარ ახლა“ — აი ასე:

        [ჰაიდ-პარკი](geo:51.50731,-0.16573)

        დანართები. „＋“ გვერდის ქვემოთ მარჯვნივ და კლავიატურის ზემოთ: კამერა, ფოტო, ხმა, ფაილი. დანართები ჩანაწერის ბოლო ტექსტის ქვეშ დგება, ოთხი ერთ რიგში. ხმოვანი ჩანაწერი შეიძლება ტექსტად გაიშიფროს, ფოტო კი თითით პირდაპირ ტექსტში ან საქმის ქვეშ გადაიტანოთ.

        სად ინახება ჩანაწერები. ყველაფერი ჩვეულებრივი ფაილებია თქვენს საქაღალდეში: ისინი ჩანს „ფაილებში“, იხსნება ნებისმიერი რედაქტორით და რჩება, აპის წაშლის შემთხვევაშიც კი. სარეზერვო ასლი — პარამეტრებში, ერთი ღილაკით.

        ნიმუშები ორი დღეა წარსულში და ორი მომავალში. წაშალეთ ისინი როგორც ჩვეულებრივი ტექსტი, ან მთელი დღე სანაგვეში გადაიტანეთ: შეეხეთ დღის სახელს ზემოთ → „დღის სანაგვეში გადატანა“.
        """,
        .todayTitle: "ვიწყებ RollingDays-ს!",
        .tomorrowPlan: """
        - [ ] შეეხეთ ნომერს მარცხნივ — საქმე შესრულებულია
              კიდევ ერთხელ შეხება — ისევ შეუსრულებელი.
        - [ ] დააჭირეთ ნომერს და გადაიტანეთ თითით
              ზემოთ ან ქვემოთ — გადალაგება. მარჯვნივ — სხვა დღეზე. მარცხნივ — წაშლა.
        - [ ] 10:00 შეეხეთ დროს მარცხნივ — დრო და გამეორება
              გამეორება ყოველდღე, ყოველკვირა, ყოველთვე ან ყოველწლიურად. ზარი — შეხსენებაა.
        """,
        .howto: """
        ეს წარსული დღის ნიმუშია. ყოველი დღე ბარათია ბარათების კარადაში.

        ბარათების კარადა. გადაწიეთ ფურცელი „დღეს“ ქვემოთ — გაიხსნება წარსული, ზემოთ — მომავალი. შეეხეთ ბარათს — გაიხსნება მისი დღე. გახსნილი დღე გადასვით ზემოთ ან ქვემოთ — ის ბარათად დაბრუნდება თავის ადგილზე. „დღეს“ ეკრანის კიდესთან დღევანდელ დღეს დაგიბრუნებთ.

        განყოფილებები. გადასვით გვერდზე: მარცხნივ — რუკა, მარჯვნივ — კალენდარი. ქვედა ღილაკებიც იქ მიგიყვანთ.

        ძებნა. ლუპა ბარათების კარადის ქვემოთ ეძებს სიტყვებში, ფოტოებსა და ადგილებში.

        ფოტოები. დააჭირეთ ფოტოს და გადაიტანეთ თითით — ის ტექსტის სხვა ადგილას ან საქმის ქვეშ დადგება.

        დღის მენიუ. შეეხეთ დღის სახელს ზემოთ: „დღის გაზიარება“, „დღის PDF“, „დღის სანაგვეში გადატანა“.
        """,
        .howtoTitle: "როგორ არის აქ ყველაფერი მოწყობილი",
        .laterPlan: """
        - [ ] საღამოს თქვით, როგორ ჩაიარა
              ყოველი საქმის ქვეშ — ერთი სტრიქონი იმაზე, რა გამოვიდა. ის დღის დღიურში ჩაიწერება.
        - [ ] გეგმაში ფოტოს ან ხმოვანი ჩანაწერის ჩადება
              „＋“ გვერდის ქვემოთ: მომავალ დღეში დანართი საქმის ქვეშ დგება.
        - [ ] ნიმუშების მოშორება, როცა აღარ დაგჭირდებათ
              წაშალეთ ისინი როგორც ტექსტი, ან შეეხეთ დღის სახელს → „დღის სანაგვეში გადატანა“.
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
        - [ ] 09:00 これはサンプルの予定です：タップして自分の予定を書きましょう
              リターンで次の予定へ。
        - [ ] 紙を上に引くと、これからの日に予定の使い方があります
        """,
        .todayDiary: """
        今日から私のRollingDaysが始まる。朝は予定、夜は一日のふり返り: それぞれの予定の下に、どうだったかを一行。

        場所。下の「地図」。地図を長押しするとピンが立ちます: 名前をつけて、その日に加えましょう。右上の切り替え: 「自分の場所」はすべてのピン、「記録」は写真のプレビュー付きで日々を地図に表示します。記録の中では「＋」の「現在地」で場所を加えます — このように:

        [ハイドパーク](geo:51.50731,-0.16573)

        添付。ページの右下とキーボードの上の「＋」: カメラ、写真、音声、ファイル。添付は記録の最後の文の下に、一列に四つずつ並びます。音声メモは文字に起こせ、写真は指で本文や予定の下へそのまま移せます。

        記録の保存場所。すべてあなたのフォルダの普通のファイルです: 「ファイル」で見え、どんなエディタでも開け、アプリを削除しても残ります。バックアップは設定からボタンひとつで。

        サンプルは過去の二日と未来の二日です。ふつうの文字と同じく消すか、日をまるごとゴミ箱へ：上の日の名前をタップ →「この日をゴミ箱へ」。
        """,
        .todayTitle: "RollingDaysを始めます!",
        .tomorrowPlan: """
        - [ ] 左の番号をタップ — 予定が完了
              もう一度タップ — 未完了に戻ります。
        - [ ] 番号を長押しして指を動かす
              上下で並べ替え。右で別の日へ。左で削除。
        - [ ] 10:00 左の時刻をタップ — 時刻と繰り返し
              毎日・毎週・毎月・毎年の繰り返し。ベルはリマインダーです。
        """,
        .howto: """
        これは過去の日のサンプルです。一日一日がカードボックスの一枚のカードです。

        カードボックス。「今日」の紙を下に引くと過去が、上に引くと未来が開きます。カードをタップするとその日が開きます。開いた日を上か下にスワイプすると、カードになって元の場所に戻ります。画面の端の「今日」で今日に戻ります。

        セクション。横にスワイプ：左に地図、右にカレンダー。下のボタンからも行けます。

        検索。カードボックスの下の虫眼鏡で、言葉・写真・場所を検索できます。

        写真。写真を長押しして指を動かすと、本文の別の場所や予定の下に移せます。

        日のメニュー。上の日の名前をタップ：「この日を共有」「この日のPDF」「この日をゴミ箱へ」。
        """,
        .howtoTitle: "しくみの紹介",
        .laterPlan: """
        - [ ] 夜にどうだったかを書く
              各予定の下に、結果を一行。その日の日記に入ります。
        - [ ] 予定に写真やボイスメモを入れる
              ページ下の「＋」：これからの日では添付が予定の下に入ります。
        - [ ] 要らなくなったらサンプルを片づける
              ふつうの文字と同じく消すか、日の名前をタップ →「この日をゴミ箱へ」。
        """,
    ]
}
