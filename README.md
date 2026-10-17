# georgii-app

Приложение, объединяющее дневник и планировщик. Идеологическая основа —
максимальное приближение к бумажному носителю: данные хранятся обычными
файлами в открытых форматах и остаются читаемыми вне приложения.

## Документы

| Файл | Содержание |
|---|---|
| [docs/00-concept.md](docs/00-concept.md) | Исходная концепция автора, без правок. Источник истины по замыслу |
| [docs/01-competitive-analysis.md](docs/01-competitive-analysis.md) | Анализ рынка и конкурентов, оценка конкурентоспособности, разбор концепции: что нового, что лишнее, что недостаточно проявлено |
| [docs/02-roadmap-and-estimates.md](docs/02-roadmap-and-estimates.md) | Дорожная карта, приоритезация v1.0, трудозатраты и сроки, сценарии по бюджету, технологический выбор |
| [docs/03-architecture-principles.md](docs/03-architecture-principles.md) | Принцип независимости, почему конкуренты выбрали базу данных и неизбежен ли их путь |
| [docs/04-decisions.md](docs/04-decisions.md) | Журнал решений и открытые вопросы |
| [docs/05-review-2026-09-12.md](docs/05-review-2026-09-12.md) | Замечания ко второй редакции концепции |
| [docs/06-open-foundations.md](docs/06-open-foundations.md) | Что ещё стоит решить до начала разработки |
| [docs/07-name-candidates.md](docs/07-name-candidates.md) | Полный список вариантов названия с исходом разбора |
| [docs/08-build-and-release.md](docs/08-build-and-release.md) | Сборка в облаке, оформление аккаунта Apple, доставка через TestFlight |
| [docs/09-apple-setup-checklist.md](docs/09-apple-setup-checklist.md) | Пошаговый список: что нажимать в аккаунте Apple и в GitHub |
| [docs/10-monetisation.md](docs/10-monetisation.md) | Модель денег и почему по объёму брать нельзя |
| [docs/11-slices.md](docs/11-slices.md) | Порядок работ срезами и два правила про формат файлов |
| [docs/wireframes/](docs/wireframes/) | Эскизы экранов |
| [docs/prototype/today.html](docs/prototype/today.html) | Кликабельный прототип экрана «Сегодня» (открывается в браузере) |

## Код

| Каталог | Содержание |
|---|---|
| [ios/](ios/) | Приложение для iPhone. Проект Xcode собирается из `project.yml` программой XcodeGen |
| [.github/workflows/](.github/workflows/) | Сборка в облаке и доставка в TestFlight |

Рабочее название — **Graphomanus** (решение P514); внутри проекта имена прежние — Chronotheca.

Статус: каркас. Приложение выбирает папку пользователя, создаёт в ней структуру
подпапок, показывает один день с вкладками «План» и «Дневник» и пишет текст
обычными файлами Markdown, которые читаются вне приложения.
