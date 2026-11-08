# Quizice: как работает приложение

Справочник для разработчика и агента. База: `main`, коммит `7ba9320` (24.09.2026); разделы статистики, прогресса и replay обновлены вместе с исправлениями синхронизации.

## Содержание

- [Устройство и точки входа](#устройство-и-точки-входа)
- [Источники данных](#источники-данных)
- [Пользовательские сценарии](#пользовательские-сценарии)
- [API](#api)
- [Хранение и синхронизация](#хранение-и-синхронизация)
- [Настройки, подписка и аналитика](#настройки-подписка-и-аналитика)
- [Отличия Debug](#отличия-debug)
- [Сборка, проверки и поддержка документа](#сборка-проверки-и-поддержка-документа)

## Устройство и точки входа

iOS 18+, Swift (language mode 5), UIKit + SwiftUI, SwiftData. Навигацией управляет coordinator, игровыми экранами — presenters, состоянием карточек Home — reducers. Основные пакеты: AppMetrica 6.4.0, Pulse 5.2.3, SnapshotTesting 1.19.2, SwiftLintPlugins 0.65.0; закреплены в [Package.resolved](../Quizice.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved).

| Задача | Точка входа |
| --- | --- |
| Сборка зависимостей, SwiftData, аналитика | [AppDelegate](../Quizice/App/Lifecycle/AppDelegate.swift), [SceneDelegate](../Quizice/App/Lifecycle/SceneDelegate.swift) |
| Переходы Home → игра → результат, replay, onboarding, sheets | [QuizFlowCoordinator](../Quizice/App/Navigation/QuizFlowCoordinator.swift) |
| Загрузка каталога, выбор локальных/серверных вопросов | [ThemeCatalogRepository](../Quizice/Core/Persistence/ThemeCatalogRepository.swift) |
| Выбранная тема и количество вопросов в текущем процессе | [QuizSessionStore](../Quizice/Core/Session/QuizSessionStore.swift) |
| Карточки Home, состояния, эффекты | [HomeFeatureStore](../Quizice/Features/Home/State/HomeFeatureStore.swift), [HomeThemeCardReducer](../Quizice/Features/Home/State/HomeThemeCardReducer.swift), [HomeAIThemeCardState](../Quizice/Features/Home/State/HomeAIThemeCardState.swift) |
| Таймер, ответы, счёт, завершение | [QuizQuestionPresenter](../Quizice/Features/QuizPlay/Presentation/QuizQuestionPresenter.swift) |
| AI: выбор runtime и запрос к бэкенду | [AIQuizRuntimeDependencies](../Quizice/App/Lifecycle/AIQuizRuntimeDependencies.swift), [BackendAIQuizThemeService](../Quizice/Features/AIQuiz/Data/BackendAIQuizThemeService.swift) |
| Авторизация и синхронизация итогов | [GameCenterAuthenticationService](../Quizice/Core/Authentication/GameCenterAuthenticationService.swift) |

`App` связывает `Features` с `Core`/`Domain`. `Domain` содержит модели и интерфейсы без UI/сетевых SDK. `QuizFactory` — compatibility alias/forwarder к `ThemeCatalogRepository`, не отдельное хранилище. Подробнее о каталогах: [project-structure.md](project-structure.md).

## Источники данных

| Данные / поведение | Откуда берётся |
| --- | --- |
| Серверные темы: ID, название, описание, SF Symbol, emoji, цвет, признак избранного | `GET /v1/themes`; весь каталог заменяется, не дополняется встроенным |
| Вопросы серверной темы и межтематической подборки | Отдельный GET при старте; `/themes` содержит только метаданные |
| Встроенные темы, вопросы, ответы и объяснения | `Quizice/<locale>.lproj/data.json`; резервный файл `Quizice/data.json` |
| Правильный ответ | Приходит вместе с вопросом либо лежит в JSON; немедленная проверка и счёт выполняются на клиенте |
| AI-викторина | В обычной сборке — результат `POST /v1/quizzes/generate`; Debug описан отдельно |
| Избранные темы | Локальный выбор в onboarding + синхронизация с бэкендом по языку |
| Итоговая статистика | Серверный baseline + ещё не отправленные локальные завершённые попытки + legacy-данные |
| Учёт отвеченных вопросов для фильтрации повторов | Отдельные события ответов отправляются на бэкенд; фильтрация следующей выдачи выполняется сервером |
| Описания результата квиза | Публичный `GET /v1/result-messages`; кеш по языку; встроенные `result.description.*` как fallback |
| Остальные тексты интерфейса, заголовок счёта и ошибки | `L10n.swift` и `*.lproj/Localizable.strings` |
| Число вопросов, таймер, перемешивание, оформление, звуки, анимации | Правила и ресурсы клиента |
| Цена и преимущества в paywall | Пока локальная модель `SubscriptionOffer.planned`, не ответ магазина/бэкенда |

В каждом из шести локализованных JSON сейчас 4 темы: `music` — 82 вопроса, `technology` — 86, `history_culture` — 101, `politics_business` — 107. Серверный каталог может содержать другие ID и больше тем: эти четыре значения не являются полным списком допустимых серверных тем.

### Каталог и offline

1. `loadData()` сначала восстанавливает непустой серверный SwiftData-каталог, если его язык совпадает с текущим. Иначе загружает локальный JSON или его SwiftData-кэш; актуальность встроенного кэша проверяется по языку и SHA-256.
2. На запуске `prepareInitialCatalog()` обновляет серверный каталог и затем предпочтения. Launch overlay ждёт подготовку не более 2 с. По таймауту подготовка отменяется, а overlay закрывается коротким fade (0,18 с), без ожидания ответа сервера и zoom-анимации. Уже загруженный каталог остаётся доступным. При быстрой подготовке сохраняются обычный показ логотипа (1,15 с) и анимация выхода.
3. При успешном обновлении сохраняются серверные метаданные **без вопросов**, `catalogOrigin` становится `backend`. При ошибке текущий каталог остаётся активным.
4. В режиме `bundled` вопросы выбираются из локального пула. В режиме `backend` старт требует сетевого запроса; ошибка **не переключает** тему на встроенные вопросы. Кэш серверных карточек сам по себе не обеспечивает offline-игру.
5. При смене языка локальные данные принудительно перезагружаются, Home обновляет серверный каталог. Ответы для устаревшей локали не применяются. Замена каталога сбрасывает выбранную тему в session.

Источники: [репозиторий](../Quizice/Core/Persistence/ThemeCatalogRepository.swift), [SwiftData-кэш](../Quizice/Core/Persistence/SwiftDataThemeStore.swift), [загрузчик JSON](../Quizice/Core/Persistence/LocalizedThemeDataLoader.swift), [launch overlay](../Quizice/App/Launch/LaunchOverlayPresenter.swift).

## Пользовательские сценарии

### Первый запуск и Home

- Onboarding показывается, пока сохранённая версия прохождения меньше `1`. Его можно повторно открыть кнопкой помощи на Home. Список тем берётся из текущего каталога.
- Выбор тем сохраняется для текущего языка; выбранные темы идут первыми на Home, остальные остаются доступны. При pending-изменениях выполняется PUT предпочтений, иначе GET; после авторизации синхронизация повторяется.
- Home содержит каталог, промобаннер подписки, AI, «Мне повезёт» и статистику. Описание/настройка темы и статистика раскрываются внутри карточек Home. Настройки и подписка открываются отдельными sheets.

Источники: [coordinator](../Quizice/App/Navigation/QuizFlowCoordinator.swift), [OnboardingProgressStore](../Quizice/Core/Persistence/OnboardingProgressStore.swift), [ThemesCollectionService](../Quizice/Features/Home/Collection/ThemesCollectionService.swift).

### Обычная игра

- Пользователь выбирает тему, число вопросов `5 / 10 / 15` и сложность `easy / medium / hard` (начальная — `medium`). Для встроенной темы доступны только размеры, помещающиеся в её пригодный пул; для серверной показываются все три размера.
- На обороте карточки «Политика и бизнес», рядом со сложностью и количеством, выбирается страна раунда. Выбор показывается только для `politics_business` с непустым `countries`; названия стран локализует iOS. «Международные вопросы» — выбор по умолчанию, без `country`. Последний выбор сохраняется отдельно от языка и может меняться перед каждым раундом; в настройках и на других карточках этого поля нет.
- В серверный запрос уходят сложность, язык, новый `seed` (UUID в lowercase), выбранный `country` и при необходимости `progressMode`. Локальный пул по сложности не фильтруется: выбранная сложность сохраняется как параметр.
- Клиент дополнительно перемешивает вопросы и варианты ответа. Поэтому серверный `seed` не фиксирует конечный порядок отображения.
- На экране 4 варианта. Обычный таймер — 20 с на вопрос, шаг обновления 0,02 с. После первого ответа повторный ввод блокируется; timeout засчитывается как неверный ответ.
- После обратной связи пользователь переходит к следующему вопросу; после последнего сохраняется одна завершённая попытка и открывается результат. Выход до завершения не добавляет итоговую попытку, но уже поставленные в очередь события ответов остаются.
- Если сервер прислал меньше вопросов, клиент выбирает наибольший доступный размер из `5/10/15` (например, 7 → 5). При остатке 1–4 показывает сообщение и не запускает раунд. Пустой список показывает состояние недоступности/завершённого прогресса, а не результат `0/0`.
- При VoiceOver или Switch Control на старте викторины таймер скрыт и отключён на всю попытку; в итоговую попытку записывается `accessibilityMode`. Это действует и в Release.

Правила: [QuizQuestionCountPolicy](../Quizice/Domain/Quiz/QuizQuestionCountPolicy.swift), [presenter](../Quizice/Features/QuizPlay/Presentation/QuizQuestionPresenter.swift), [AccessibilityModeClient](../Quizice/Core/Accessibility/AccessibilityModeMonitor.swift).

### Тексты результата

Каталог фраз общий для всех тем, сложностей и размеров викторины, поэтому загружается в фоне при запуске приложения, независимо от Game Center и подготовки каталога тем. При открытии каждого квиза (включая AI, случайный и replay) проверяется свежесть: запрос нужен только без кеша или спустя 24 часа после успешной загрузки/проверки. Смена языка запускает такую же проверку для нового языка. Одновременные запросы одной локали объединяются; старт квиза и показ результата сеть не ожидают.

Клиент сохраняет каталог, `ETag` и время проверки по языку и адресу backend. Просроченный кеш проверяется через `If-None-Match`: `304` продлевает свежесть сохранённого тела, `200` заменяет его после валидации. Если при `304` нет пригодного тела, выполняется один повтор без `If-None-Match`. Ошибка сети/старый сервер сохраняют последний пригодный каталог того же языка; при отсутствии нужной категории используются прежние встроенные строки `result.description.*`. Каталог другого языка не используется. Региональные локали нормализуются через `AppLocalizationStore`, как для тем.

Категорию определяет клиент: `<15%`, `15–<30%`, `30–<50%`, `50–<75%`, `75–<100%`, `100%`. Для пустой попытки используется `no_questions`, для некорректных счётчиков — `invalid_score`. Правила подсчёта ответов не изменены. Случайная фраза фиксируется при создании presenter результата и не меняется при перерисовке или завершении фонового запроса. Последняя выбранная фраза той же категории/языка исключается при наличии альтернатив; история выбора хранится в памяти процесса.

Источники: [ResultMessagesRepository](../Quizice/Core/Persistence/ResultMessagesRepository.swift), [HTTPResultMessagesAPI](../Quizice/Core/Networking/HTTPResultMessagesAPI.swift), [категории](../Quizice/Domain/Quiz/ResultMessage.swift), [QuizResultPresenter](../Quizice/Features/QuizResult/Presentation/QuizResultPresenter.swift).

### «Мне повезёт» и повтор игры

- «Мне повезёт»: 5 вопросов, сложность `medium`, служебная тема `random-selection`. Для серверного каталога клиент случайно выбирает endpoint `random` или `random_balanced`. Как сервер балансирует темы, в этом репозитории не определено.
- Локальная подборка смешивает вопросы всех тем. При локальном replay сначала предпочитаются вопросы, не встречавшиеся в предыдущей подборке, затем допускаются повторы.
- Replay обычной темы пытается получить новую пачку с прежними количеством/сложностью. При ошибке остаётся экран результата с сообщением; прежние вопросы не запускаются.
- Replay случайной подборки серверного каталога всегда запрашивает новую выдачу, даже если локального пула вопросов нет. Для встроенного каталога строится локальная подборка.
- Replay «Политики и бизнеса» с доступным выбором стран открывает оборот карточки для настройки следующего раунда. Смена страны отбрасывает подготовленную пачку; ответ на запрос с прежней страной не принимается. Прогресс ответов сохраняется по прежним `questionId`/`questionVersion`.
- Случайные режимы используют последний выбор страны; отдельного выбора страны на их карточке нет. HTTP-кеш пачек отключён, query с `country` также разделяет URL запросов.
- Replay AI выполняет новую генерацию по сохранённым теме, количеству, сложности и локали. При ошибке остаётся экран результата с сообщением.

Источники: [Home actions](../Quizice/Features/Home/Presentation/QuizViewController+Actions.swift), [RandomQuizSelection](../Quizice/Domain/Quiz/QuizTheme.swift), [replay в coordinator](../Quizice/App/Navigation/QuizFlowCoordinator.swift).

### AI

Обычный путь: Game Center → backend session → ввод темы → backend generation → проверка результата → игра. Наличие Game Center без действующей серверной сессии недостаточно.

- Тема после обрезки пробелов: 1–120 символов; число вопросов `5 / 10 / 15`, сложность `easy / medium / hard`, язык приложения.
- Перед запросом токен должен быть действителен ещё более 30 с. Смена сессии во время запроса делает ответ непригодным; UI также отбрасывает генерацию для старого языка.
- Успех создаёт временную тему `ai-<UUID>` в session. Она не добавляется в постоянный каталог/SwiftData. Её вопросы не имеют серверных `questionId`/`questionVersion` и не попадают в очередь прогресса ответов; завершённая игра учитывается в общей статистике.
- Статусы прогресса «анализ / отправка / генерация / почти готово» переключаются локальными задержками; это не серверные progress-события и не streaming.
- Отказ AI показывается локализованным сообщением клиента. Ошибки сети/сервиса/формата позволяют повторить запрос; отказ предлагает изменить тему. Автоматического повторного POST генерации нет.

Источники: [backend AI](../Quizice/Features/AIQuiz/Data/BackendAIQuizThemeService.swift), [AI workflow](../Quizice/Features/Home/Presentation/QuizViewController+AIWorkflow.swift), [ошибки и фазы](../Quizice/Features/AIQuiz/Presentation/AIQuizThemePresentationSupport.swift).

## API

В таблице пути **относительно `BackendBaseURL`**. Например, если base заканчивается на `/api`, итоговый путь — `/api/v1/themes`. В Release base берётся из `BACKEND_BASE_URL` → `Info.plist: BackendBaseURL`; допустим HTTPS. Не настроенное/пустое значение или нераскрытый `$(...)` отключает создание backend-клиентов. Особенности Debug — ниже.

Запросы используют JSON (`Accept`, для body также `Content-Type: application/json`). Авторизация — `Authorization: Bearer <accessToken>`. Даты auth/statistics/answer-events в сетевом JSON — ISO-8601. Общая ошибка бэкенда: `{code, message, requestId?}`; AI-сервис обрабатывает HTTP status и собственный generation envelope.

| Метод и путь | Авторизация | Запрос | Ответ / назначение |
| --- | --- | --- | --- |
| `POST /v1/auth/game-center` | Game Center proof в body | `teamPlayerId`, `bundleId`, `publicKeyUrl`, `signature`, `salt`, `timestamp` (строки) | `userId`, `accessToken`, `expiresAt` |
| `GET /v1/result-messages` | Не нужна; Bearer не отправляется | query `locale`, опциональный `If-None-Match` | `200 {locale, messages: {category: [String]}}` + `ETag`; `304` без тела |
| `GET /v1/themes` | Bearer, если есть | query `locale` | `{locale, themes: [{id, name, description, sfSymbol, emoji, colorHex, isFavorite}]}` |
| `GET /v1/me/theme-preferences` | Обязательна | query `locale` | `{locale, favoriteThemeIds: [String]}` |
| `PUT /v1/me/theme-preferences` | Обязательна | body `{locale, favoriteThemeIds}` | Тот же envelope; заменяет список |
| `GET /v1/themes/{themeID}/questions` | Bearer, если есть; обязателен для `progressMode` | query `count`, `locale`, `difficulty`, `seed`, опционально `progressMode`, `country` | Пачка вопросов, формат ниже |
| `GET /v1/questions/random` | Аналогично вопросам темы | Те же query-параметры | Межтематическая пачка |
| `GET /v1/questions/random_balanced` | Аналогично вопросам темы | Те же query-параметры | Альтернативная межтематическая пачка |
| `POST /v1/me/question-answers` | Обязательна | `{events: [{eventId, questionId, questionVersion, locale, answer, answeredAt}]}`; 1–100 событий | `{processedEventIds: [UUID]}`; `answer` — выбранный текст, `null` при timeout |
| `POST /v1/me/statistics/sync` | Обязательна | `{migrationId, legacySummary?, attempts: [{id, correctAnswers, totalQuestions, completedAt, accessibilityMode}]}`; до 100 попыток | `{summary, acceptedAttemptIds, legacySummaryAccepted}` |
| `POST /v1/quizzes/generate` | Обязательна + AI access | `{topic, count, locale, difficulty}` | AI envelope, формат ниже |

Источники: [HTTPAuthAPI](../Quizice/Core/Authentication/HTTPAuthAPI.swift), [HTTPBackendContentAPI](../Quizice/Core/Networking/BackendContentAPI.swift), [DTO](../Quizice/Core/Networking/BackendContentModels.swift), [BackendAIQuizThemeService](../Quizice/Features/AIQuiz/Data/BackendAIQuizThemeService.swift).

### Контракты и клиентская валидация

**Каталог.** `locale` должен совпасть с запросом; список непустой; ID уникальны; название, описание, SF Symbol и emoji непустые; `colorHex` уже в нормализованном формате. Невалидная тема отклоняет весь ответ. `countries` — список кодов `DE`, `US`, `ES`, `FR`, `IT`, `RU` без дублей; отсутствие поля совместимо со старым каталогом и означает `[]`. Список сохраняется вместе с метаданными в SwiftData.

**Тексты результата.** Язык ответа должен совпадать с запросом. Неизвестные категории, пустые массивы и строки после обрезки пробелов игнорируются, дубликаты фраз удаляются. Каталог без единой пригодной фразы отклоняется; частичный каталог допускается с локальным fallback для пропущенных категорий. Число и порядок фраз не фиксированы.

**Пачка вопросов:**

```text
{ locale, seed, country?, progressMode?, availableCount?, questions: [
  { questionId, questionVersion, question, answers: [String], correctAnswer, explanation? }
] }
```

`locale`, `seed` и `country` обязаны совпадать с запросом. Без страны поле `country` отсутствует. Язык не определяет страну; все 36 комбинаций поддерживаются. Вопросов может быть от 0 до запрошенного количества; `availableCount` не меньше их числа (при отсутствии принимается равным числу вопросов). Каждый вопрос требует уникальный непустой ID, версию > 0, уникальный непустой текст ≤ 500 символов, ровно 4 уникальных непустых ответа ≤ 300 символов и ровно одно совпадение с `correctAnswer`. `progressMode` декодируется, но совпадение с запросом отдельно не проверяется. `availableCount` не используется для предварительного ограничения кнопок размера викторины.

**Стратегии повторов** хранятся на клиенте; запрос меняют только при наличии действующего backend token:

| Настройка | Query | Смысл запрошенной фильтрации |
| --- | --- | --- |
| `showAll` (по умолчанию) | Без `progressMode` | Все вопросы |
| `hideAnswered` | `progressMode=all_answered` | Исключить уже отвеченные |
| `retryIncorrect` | `progressMode=correct_only` | Исключить правильно отвеченные |

Для гостя эффективная стратегия — `showAll`. Локальный JSON по истории ответов не фильтруется.

**AI envelope:** `{locale, status, message, theme, themeDescription, questions}`. При `status=success`: язык совпадает, `message` пустой, название/описание непустые, вопросов ровно сколько запрошено, тексты вопросов уникальны, ограничения вопросов/ответов — 500/300 символов и 4 уникальных варианта. Каждый вопрос содержит `question`, `answers`, `correctAnswer`, `explanation`; **`explanation` должен быть пустой строкой**. При `status=refused`: `message` непустой и ≤ 500 символов, название/описание и массив вопросов пустые. Это контракт backend AI; Debug direct AI имеет отдельный парсер.

**Статистика.** `summary` содержит `playedQuizzes`, `correctAnswers`, `totalQuestions`, `bestCorrectAnswers`, `bestTotalQuestions`. Проверяются неотрицательность и согласованность счётчиков; `acceptedAttemptIds` должен точно соответствовать всем ID отправленного batch без дублей. Для answer-events принимается подмножество отправленных ID.

### Таймауты, ошибки и повторы

- Auth/content/statistics: request timeout 15 с; backend AI: 30 с.
- GET/PUT content-запросы во всех сборках используют `reloadIgnoringLocalCacheData`; это не сбрасывает SwiftData.
- Content и AI отклоняют тело > 10 MiB до JSON-декодирования и успешный ответ с указанным не-JSON `Content-Type`. Проверка размера происходит после получения тела.
- Content-запрос с Bearer при `401` один раз пытается восстановить сессию и повторить запрос. Восстановление ждёт новый токен до 15 с; отдельного refresh-token endpoint нет, выполняется новая авторизация.
- AI при `401` очищает сессию и инициирует переавторизацию; сам запрос генерации не повторяет. При `403` отключает AI access. `429`/`5xx` дают ошибку сервиса с ручным повтором.
- Statistics sync повторяет transport/`5xx` ошибки до 3 попыток: задержки 300 и 600 мс + jitter до 75 мс. `401` может вызвать один цикл повторной авторизации; повторный отказ переводит в guest. Неотправленные попытки сохраняются.

Источники: [content transport](../Quizice/Core/Networking/HTTPBackendContentAPI.swift), [auth recovery](../Quizice/Core/Networking/BackendContentModels.swift), [retry](../Quizice/Core/Networking/BackendRetry.swift), [auth service](../Quizice/Core/Authentication/GameCenterAuthenticationService.swift).

## Хранение и синхронизация

| Хранилище | Что сохраняется / срок жизни |
| --- | --- |
| SwiftData | Один текущий каталог с `locale`/`origin`; встроенные темы с вопросами либо серверные метаданные без пачек вопросов. Замена удаляет прежние записи |
| Память, `QuizSessionStore` | Выбранная тема, вопросы, размер игры; текущий AI-конфиг для replay. После перезапуска игры не восстанавливаются |
| Keychain, `KeychainSessionStore` | `userID`, `teamPlayerID`, `accessToken`, `expiresAt`; доступ `WhenUnlockedThisDeviceOnly` |
| UserDefaults, `quizice.statistics.attempts` и `.user.<encodedID>` | Гостевая и отдельные пользовательские статистики: baseline, pending attempts, local-only attempts, migration ID, legacy summary; `.active-user` выбирает текущую |
| UserDefaults, `quizice.onboarding.*` | Версия onboarding, упорядоченные preferred IDs и pending-флаг по локали |
| UserDefaults, `quizice.settings.*` | Дизайн (`designStyle`), светлая/тёмная тема (`theme`), язык (`language`), UI-выбор иконки (`icon`) |
| UserDefaults, `quizice.question-repeat-strategy` | Стратегия повторов |
| UserDefaults, `quizice.localizedDataHashKey` | Язык и SHA-256 встроенного JSON |
| Application Support / `Quizice/result-messages/<SHA256 backend URL>/<locale>.json` | Каталог фраз, ETag и время успешной проверки; атомарная запись, пригоден офлайн после истечения суток |
| Application Support / `Quizice/question-answer-outbox.json` | События ответов до подтверждения сервером; атомарная запись файла |

**Авторизация.** После launch overlay запускается Game Center. При необходимости его системное окно ждёт окончания onboarding. Валидная Keychain-сессия переиспользуется только для того же `teamPlayerID`; иначе клиент получает proof GameKit и обменивает его на backend token. Гостевой режим оставляет обычные викторины доступными, AI закрыт. При смене игрока устаревший результат авторизации не применяется.

**Статистика.** Завершение игры сохраняет попытку сразу и запускает sync. Также sync вызывается после авторизации и при активации сцены. При входе гостевые pending/legacy-данные переносятся в кэш вошедшего пользователя; кэши других пользователей сохраняются отдельно. Ответ сервера заменяет baseline и удаляет подтверждённые pending; legacy-миграция считается завершённой при успешном ответе даже при `legacySummaryAccepted=false`.

Карточка статистики показывает число игр, долю верных ответов (общие верные / общие вопросы, округление до целого процента) и лучший результат. Лучший выбирается по числу правильных ответов; при равенстве сохраняется прежний результат, включая подтверждённый сервером. Ниже итогов доступны графики точности ответов и количества игр по дням для аккаунта со всех устройств. Старые попытки с длиной вне `5/10/15` сохраняются в локальной истории, но не отправляются на сервер и не блокируют остальные; поэтому эта часть истории остаётся только на устройстве. Старую агрегированную legacy-сводку без отдельных попыток пересчитать по новому правилу рекорда невозможно.

Графики используют `GET /v1/me/statistics/history?period=week|month|all&timeZone=Europe/Moscow`. Ответ содержит `period`, `timeZone`, `periodStart`, `periodEnd` (исключительная граница), `days: [{date, playedQuizzes, correctAnswers, totalQuestions}]` и `undatedPlayedQuizzes`. «Неделя» и «Месяц» — последние 7 и 30 календарных дней, включая сегодня; «Всё время» — все доступные даты. Сервер группирует игры по переданному IANA-часовому поясу устройства. Точность за день и период взвешена по числу вопросов; пропуски не превращаются в нулевую точность и не соединяются линией. При наличии старых агрегатов без даты карточка поясняет, что они остаются только в итоговых показателях. Ещё не синхронизированные и локальные несовместимые попытки не смешиваются с дневными серверными агрегатами, чтобы не создавать дубликаты.

История загружается при открытии, смене периода и возвращении на передний план; открытые графики обновляются после подтверждённой синхронизации и изменения часового пояса. Ошибка оставляет кнопку повтора. Закрытие карточки и смена аккаунта отменяют запрос; поздний ответ проверяет поколение запроса и аккаунт. История не сохраняется в общий дисковый кэш. Swift Charts встроены в существующую прокручиваемую UIKit-карточку через `UIHostingConfiguration`. Все оформления и локализации используют общие токены; VoiceOver получает даты и значения точек, при accessibility-размерах шрифта переключатель периода становится меню.

**Прогресс ответов.** Событие создаётся только для вопроса с `questionID`, `questionVersion` и `locale`; владелец фиксируется при старте раунда. В файле очередь разделена по user ID. Отправка использует сессию владельца, включая проверку аккаунта после переавторизации. События без известного владельца (guest и старый формат очереди) сохраняются, но автоматически не присваиваются вошедшему пользователю.

Очередь отправляется при добавлении события, запуске приложения, активации сцены, восстановлении сети и успешной авторизации. Параллельные вызовы ожидают общую отправку. Перед персональной выдачей тем, random и random_balanced клиент ждёт завершения синхронизации; временная ошибка останавливает выдачу. HTTP-кэш не используется, ответы для сменившегося аккаунта отбрасываются. Дефолт остаётся `showAll`.

Transport/`429`/`5xx` повторяются до 3 попыток с задержкой и неизменными событиями. Из pending удаляются только подтверждённые ID. Пакеты с `409/422` делятся для выявления ошибочных событий: они сохраняются отдельно с HTTP status/code, а остальные продолжают отправляться. Неизвестные ошибки сохраняют очередь для следующего запуска. Предпочтения тем по-прежнему разделены по языку, а не по аккаунту.

При ошибке открытия постоянной SwiftData базы приложение пытается создать in-memory контейнер, затем может продолжить без контейнера с данными в памяти.

Источники: [StatisticsStore](../Quizice/Core/Persistence/StatisticsStore.swift), [KeychainSessionStore](../Quizice/Core/Authentication/KeychainSessionStore.swift), [outbox](../Quizice/Core/Persistence/QuestionAnswerOutbox.swift), [OnboardingProgressStore](../Quizice/Core/Persistence/OnboardingProgressStore.swift).

## Настройки, подписка и аналитика

**Язык и оформление.** Языки: `ru`, `en`, `es`, `de`, `it`, `fr` и системный выбор; fallback — `en`. Язык интерфейса и запросов определяется `AppLocalizationStore`. Дизайны `classic` (по умолчанию), `radar`, `clean` реализованы на клиенте; `clean` дополнительно поддерживает system/light/dark. Цвета, шрифты, fallback-иконки, звуки ответа, reduced-motion и accessibility-поведение также клиентские. [Локализация](../Quizice/Core/Localization/AppLocalization.swift), [настройки оформления](../Quizice/Core/DesignSystem/Appearance/AppAppearancePreferences.swift), [визуальные fallback темы](../Quizice/Features/Home/Collection/ThemeVisualCatalog.swift).

**Подписка — частично реализована.** Release читает проверенные StoreKit entitlements для `quizice.plus.monthly`, учитывает срок и отзыв, слушает `Transaction.updates`. Наличие Plus скрывает промобаннер Home. Кнопки покупки и восстановления пока показывают «скоро»; purchase/restore flow не подключён. Paywall рисует зашитые `$1.99`, 5/15 вопросов и ×20 генераций. Эти цифры не ограничивают текущие quiz/AI policies: там доступны 5/10/15 без проверки подписки. [SubscriptionPaywallView](../Quizice/Features/Subscription/UI/SubscriptionPaywallView.swift), [coordinator](../Quizice/App/Navigation/QuizFlowCoordinator.swift).

**Другие заглушки.** Профиль и обратная связь в Settings показывают информационные alerts. Альтернативные иконки dark/ice недоступны; полноценной смены системной иконки нет. [QuizSettingsView](../Quizice/Features/Settings/UI/QuizSettingsView.swift).

**Аналитика.** AppMetrica включается только с настроенным `APPMETRICA_API_KEY`, отключена в XCTest/Previews. Передаются события экранов, выбора тем, игр/ответов/результатов, AI, настроек, подписки, а также сетевые метрики: операция, результат, длительность, HTTP status, размер ответа. В продуктовые события не включаются тексты вопросов/ответов/AI prompt и сырые сообщения ошибок. Это ограничение аналитики: backend answer-events отдельно содержат выбранный ответ, а AI endpoint получает тему. Location, IDFA и automatic revenue tracking отключены; crash tracking включён. [AnalyticsService](../Quizice/Core/Analytics/AnalyticsService.swift), [таксономия событий](analytics-taxonomy.md), [PrivacyInfo](../Quizice/PrivacyInfo.xcprivacy).

## Отличия Debug

Этот раздел описывает только отличия от обычного пути выше. Debug может обращаться к реальному бэкенду и отправлять аналитику: сама конфигурация Debug не означает mock/offline.

### Меню и выбор backend

Меню разработчика открывается **долгим нажатием 0,5 с на кнопку настроек Home**. Есть скрытие интерфейса, localhost, локальный контент, direct AI, имитация Plus, Pulse и варианты фона для `classic`.

Приоритет `BackendConfiguration.load()` в Debug:

1. `quizice.debug.backend.use-local-content-only=true` → backend configuration отсутствует.
2. `quizice.debug.backend.use-localhost=true` → `http://localhost:8000/api`.
3. Валидная переменная окружения `API_BASE_URL`.
4. Значение `BackendBaseURL` из Info.plist.

HTTP разрешён только для host `localhost`; остальные адреса должны быть HTTPS. На физическом устройстве `localhost` указывает на само устройство. Переключатели localhost/local-content выключают друг друга. Изменение backend/direct AI сохраняется в UserDefaults и требует перезапуска приложения, поскольку зависимости создаются при запуске.

**Нюанс local-content:** флаг отключает backend-клиенты, но `loadData()` сначала может восстановить уже сохранённый серверный каталог того же языка. Флаг сам не очищает SwiftData и не гарантирует переход на JSON при таком кэше. Direct AI выбирается независимо от backend configuration.

Источники: [DebugMenuView](../Quizice/App/Debug/DebugMenuView.swift), [обработчики переключателей](../Quizice/Features/Home/Presentation/QuizViewController+Restoration.swift), [BackendConfiguration](../Quizice/Core/Authentication/BackendConfiguration.swift).

### Авторизация и AI

| Механизм | Поведение Debug |
| --- | --- |
| Dev auth | При `DEV_AUTH_ENABLED=1/true/yes`, доступном backend configuration и `DEV_AUTH_SECRET` выбирается dev provider вместо Game Center |
| Dev endpoint | `POST /v1/auth/dev`, body `{developerUserId: UUID}`, header `X-Dev-Auth-Secret`; ответ `{userId, accessToken, expiresAt}` |
| Dev identity | Стабильный UUID хранится отдельно в Keychain; сессия использует `teamPlayerID=dev:<UUID>`. Ошибка входа переводит в guest |
| Direct AI в Simulator | В Debug Simulator включён принудительно, даже если тумблер direct AI выключен |
| Direct AI на устройстве | Выбирается при `quizice.debug.ai.use-direct-service=true`; без него используется backend AI |
| Доступ к direct AI | Game Center/backend session не требуются; нужен локальный API key. Включение тумблера проверяет наличие ключа |
| Ключ direct AI | `YANDEX_AI_API_KEY` из Run Scheme → Debug Keychain. Environment имеет приоритет; отвергнутый ключ удаляется из Keychain |
| Provider endpoint | `POST https://ai.api.cloud.yandex.net/v1/responses`; `Authorization: Api-Key <key>`, `OpenAI-Project`, `x-data-logging-enabled: false` |
| Direct body | `{prompt: {id}, input: <JSON-строка с theme, locale, questionCount, difficulty>, store: false}`. Project/prompt ID — константы `YandexAIQuizThemeService` |
| Release | Direct service бросает `unavailableInRelease`; dev provider/ключи Debug не используются |

Direct-парсер читает Responses envelope и вложенный JSON викторины; проверки не полностью совпадают с backend AI (например, допускается непустой `explanation`). Успех direct-запроса не проверяет доступность backend generation.

Источники: [выбор runtime](../Quizice/App/Lifecycle/AIQuizRuntimeDependencies.swift), [direct service](../Quizice/Features/AIQuiz/Data/AIQuizThemeService.swift), [Debug key store](../Quizice/App/Debug/DebugYandexAIAPIKeyStore.swift), [dev auth](../Quizice/Core/Authentication/GameCenterAuthenticationService.swift), [HTTP auth](../Quizice/Core/Authentication/HTTPAuthAPI.swift).

### Диагностика и визуальные переключатели

- **Pulse:** Debug включает сетевой proxy и встроенную network console. В `AppDelegate` задан список маскируемых заголовков/полей, но он не покрывает все данные: например, `X-Dev-Auth-Secret`, AI input и answer-events не указаны в этом списке. Сырые дампы не переносить в документацию.
- **Индикаторы источника:** на Home/onboarding/экране вопросов доступны Debug-подписи источника данных; для XCTest они подавляются. Каталог текстов результата управляет кешем самостоятельно и использует `reloadIgnoringLocalCacheData` также в Release; в XCTest/Previews его live-загрузка отключена.
- **AppMetrica:** Debug пишет компактные имена событий в лог; `QUIZICE_APPMETRICA_VERBOSE_LOGS=1` включает подробные SDK logs. Release игнорирует этот флаг.
- **Plus:** `quizice.debug.subscription.active` полностью определяет отображаемое состояние подписки в Debug, независимо от StoreKit; меняется сразу, без покупки.
- **Оформление:** можно скрыть интерфейс и переключать фон `classic`: `legacySlate`, `slate4x4`, `slate5x5` (по умолчанию). Фон хранится в `quizice.experimental.backgroundStyle`.
- **Ошибки AI:** отсутствующий/отвергнутый provider key отображается как ошибка конфигурации; в Release такие ошибки представлены общей недоступностью.

## Сборка, проверки и поддержка документа

Открыть `Quizice.xcodeproj`, схема `Quizice`. Необязательный локальный конфиг:

```sh
cp Configurations/Secrets.xcconfig.template Configurations/Secrets.xcconfig
```

Файл исключён из Git. Имена параметров — `BACKEND_BASE_URL`, `APPMETRICA_API_KEY`; реальные значения здесь не фиксировать. Без конфига приложение собирается, аналитика отключена, на чистой установке используется встроенный каталог. Подпись приложения настраивается средствами Xcode отдельно.

Проверки из корня репозитория:

```sh
# Статические контракты без сборки
QUIZICE_SKIP_XCODEBUILD=1 ./scripts/verify-s04-tests-and-failure-states.sh --checks-only

# Категории XCTest (нужны соответствующие simulator runtimes)
./scripts/run-ios-test-category.sh unit "iPhone 17" 26.2
./scripts/run-ios-test-category.sh ui "iPhone SE (3rd generation)" 26.2
./scripts/run-ios-test-category.sh snapshots "iPhone 16e" 26.2
```

[CI](../.github/workflows/ios-tests.yml) использует Xcode 26.2, дополнительно гоняет UI на iPhone 17 Pro Max и объединяет coverage. SwiftLint подключён как build-tool plugin. Live API тесты включаются отдельно через `QUIZICE_RUN_LIVE_BACKEND_TESTS=1`; обычные unit-тесты не должны зависеть от сети. Snapshot-запись — `QUIZICE_RECORD_SNAPSHOTS=1`, после неё нужно проверить изменённые PNG и повторить без записи.

Для проверки изменений начинать с профильных тестов: [backend](../QuiziceTests/Unit/BackendClientTests.swift), [тексты результата](../QuiziceTests/Unit/ResultMessagesTests.swift), [auth](../QuiziceTests/Unit/AuthServiceTests.swift), [AI session](../QuiziceTests/Unit/BackendAIClientSessionTests.swift), [статистика](../QuiziceTests/Unit/StatisticsStoreTests.swift), [игра](../QuiziceTests/Unit/QuizQuestionPresenterTests.swift), [app flow](../QuiziceTests/Features/AppFlow/Unit), [Home](../QuiziceTests/Features/Home).

**Как поддерживать:** при изменении endpoint/DTO обновлять таблицу API и ограничения; при переносе логики клиент ↔ сервер — источники данных и offline-поведение; при смене ключей хранения — таблицу persistence; при изменении `#if DEBUG` — только отдельный Debug-раздел. После сверки обновлять коммит/дату в начале. Планы в соседних `*-plan.md` не считать доказательством уже реализованного поведения: окончательный источник — код и тесты.
