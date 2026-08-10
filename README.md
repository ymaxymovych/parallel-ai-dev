# Parallel AI Dev — паралельна AI-розробка з зовнішньою пам'яттю

**Версія: 2.0.0** · [що нового](CHANGELOG.md) · найкоротший шлях до запуску — [QUICKSTART.md](QUICKSTART.md)

> **EN (short):** A working system for running **several Claude Code chats in parallel on one
> repository** without them overwriting each other, and with a **persistent memory** that survives
> between sessions (Karpathy-style distillation layers). One orchestrator chat gates risky merges
> and deploys; worker chats live in isolated git worktrees and ship via PR; everything important
> lives in git files, not in a chat's head. Includes a ready-to-copy `CLAUDE.md` constitution,
> the memory file structure, starter prompts, and a one-command installer.
> Not theory — it mirrors a system that runs 7+ parallel chats daily in production.

Один чат Claude — це один розробник з амнезією: геніальний усередині сесії і забуває все
між сесіями. Коли задач стає більше, ніж влазить в один чат, з'являються дві проблеми,
яких **не** розв'язує «просто відкрию ще один чат»:

1. **Паралельні чати затирають роботу одне одного.** Два чати в одній теці — це два
   розробники за однією клавіатурою.
2. **Ніхто нічого не пам'ятає.** Рішення, прийняте у вівторок у чаті №3, у середу в чаті
   №5 приймається заново — інакше. Так проєкти будуються по два і по три рази.

Цей репозиторій — готова відповідь на обидві: **розподіл ролей** (хто що має право робити)
+ **зовнішня пам'ять** (усе важливе живе у файлах у git).

```
власник (людина)
   └── чат-КООРДИНАТОР ── гейт ризикових змін, деплой, спільні ресурси
         ├── робочий чат 1 ── власний worktree ── PR
         ├── робочий чат 2 ── власний worktree ── PR
         └── робочий чат N ── власний worktree ── PR
                    ↕
            пам'ять у git: рішення / граблі / карта проєкту / беклог / інбокс / журнал
```

## Що всередині

| Файл | Що це |
| --- | --- |
| [`QUICKSTART.md`](QUICKSTART.md) | Від нуля до «✅ СИСТЕМА ГОТОВА» за 9 кроків. Починати звідси. |
| [`docs/00_JOB_DESCRIPTION.md`](docs/00_JOB_DESCRIPTION.md) | Опис РОБОТИ: ролі, чотири шари пам'яті, ключові протоколи, як виглядає робочий день системи. |
| [`docs/01_STARTER_KIT.md`](docs/01_STARTER_KIT.md) | Розгорнуте встановлення + таблиця «найчастіші способи все зламати». |
| [`docs/MANIFEST.md`](docs/MANIFEST.md) | Що кому належить: kit-owned / user-owned / append-only; довідник перевірок R1–R9; `.selfcheck.conf`. |
| [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) | Симптом → причина → ремонт. |
| [`template/CLAUDE.parallel-ai-dev.md`](template/CLAUDE.parallel-ai-dev.md) | Правила кіту (оновлюються кітом). Під'єднуються одним рядком у твоєму `CLAUDE.md`. |
| [`template/CLAUDE.md`](template/CLAUDE.md) | Твоя «конституція»: рядок імпорту + зони твого проєкту. Кіт її ніколи не перезаписує. |
| [`template/coordination/`](template/coordination) | Структура пам'яті: `SETUP` / `DECISIONS` / `MISTAKES` / `PROJECT_MAP` / `BACKLOG` / `WORKSTREAMS` / `inbox` / `log`. |
| [`prompts/`](prompts) | Стартові промпти координатора і робочого чату. |
| [`scripts/init-memory.sh`](scripts/init-memory.sh) | Розгортає структуру у твоєму репозиторії однією командою. Нічого не перезаписує. |
| [`scripts/self-check.sh`](scripts/self-check.sh) | Нормативні перевірки R1–R9 з вердиктом «✅ СИСТЕМА ГОТОВА / ❌ ЛИШИЛОСЬ: N» + розширена діагностика (`--full`). Тільки читає. |
| [`scripts/check-publication-risk.sh`](scripts/check-publication-risk.sh) | Скан пам'яті на секрети/адреси перед тим, як репозиторій стане публічним. |
| [`scripts/update-kit.sh`](scripts/update-kit.sh) | «Чи свіжий у мене кіт?» — дві ланки: GitHub→клон і клон→твоя інсталяція. |

## Швидкий старт

```bash
# 1. Клонувати цей репозиторій кудись поруч
git clone https://github.com/ymaxymovych/parallel-ai-dev.git ~/parallel-ai-dev

# 2. Перейти у СВІЙ проєкт (він має бути git-репозиторієм) і розгорнути пам'ять
cd ~/my-project
bash ~/parallel-ai-dev/scripts/init-memory.sh

# 3. Заповнити coordination/SETUP.md (три декларації) і <...> у CLAUDE.md,
#    наповнити PROJECT_MAP.md і DECISIONS.md, закомітити
git add -A && git commit -m "chore: структура пам'яті проєкту" && git push

# 4. Перевірити готовність (нічого не змінює, тільки читає)
bash ~/parallel-ai-dev/scripts/self-check.sh   # ціль: «✅ СИСТЕМА ГОТОВА»

# 5. Відкрити перший чат промптом з prompts/coordinator.md, решту — з prompts/worker.md
```

Покроково з поясненнями — у [QUICKSTART.md](QUICKSTART.md).

## Найважливіше правило: запобіжник «анти-кола»

Механізм із трьох частин, і всі три обов'язкові — інакше він не працює:

1. **Рішення записуються з поясненням «чому».** Без причини наступний чат не може оцінити,
   чи вона ще актуальна, і перевирішує заново.
2. **Є карта того, що вже існує** — з позначкою, який із дублікатів канон.
3. **Кожен новий чат звіряється ПЕРЕД стартом.** «Грепни, перш ніж специфікувати».

**Тест, що працює:** дай новому чату задачу «збудуй X», яка в проєкті вже частково зроблена.
Правильна перша відповідь — «X уже є отут» / «X відхилено тоді-то, бо…» / «X у беклозі, бо…»
/ «в пам'яті чисто, будую». Якщо чат одразу кинувся будувати — запобіжник не налаштований.

## Поруч: перевірка технічних завдань

Цей репозиторій відповідає на питання **«як організувати багато чатів і пам'ять між ними»**.
Сусідній — [**tz-skills**](https://github.com/ymaxymovych/tz-skills) — відповідає на питання
**«як зробити, щоб один чат не збрехав, що виконав завдання»**: конвеєр скілів
`/tz-draft → /tz-review → /tz-verify` з трьома незалежними LLM-критиками різних вендорів.

Разом вони закривають дві різні дірки й добре працюють у парі: `tz-skills` тримає якість
однієї задачі, `parallel-ai-dev` — порядок між багатьма чатами і пам'ять між сесіями.

## Звідки це взялось

Це не теоретична модель, а дзеркало робочої системи, у якій щодня працює 7+ паралельних
чатів над одним монорепозиторієм. Кожне правило тут оплачене реальною втратою: зниклою
роботою, зламаною збіркою в усіх чатах одразу, «успішним» деплоєм, який нічого не задеплоїв,
проєктом, збудованим двічі. Деталі інцидентів — у [`docs/00_JOB_DESCRIPTION.md`](docs/00_JOB_DESCRIPTION.md).

## Навчання

Цей репозиторій — **матеріал бонусного уроку курсу «Основи роботи з АІ-агентами»**
(AI Advisory Board). Він написаний так, щоб його можна було пройти самостійно: швидкий
старт, самоперевірка, приклади. Але якщо десь застрягнеш — у курсі є живі сесії, де це
розбирають руками. Тобто самостійність тут не обов'язок, а зручність.

- 🎓 [Курси та програми](https://course.aiadvisoryboard.me/courses) — навчання роботі з AI-агентами
- 💳 [Ціни](https://course.aiadvisoryboard.me/pricing)
- 🏢 [Для компаній](https://course.aiadvisoryboard.me/corporate) — навчання команд
- 🌐 [aiadvisoryboard.me](https://aiadvisoryboard.me/uk) — про нас

## Ліцензія

Див. [LICENSE](LICENSE): користуватись і адаптувати у своїх проєктах — вільно, зокрема
комерційно; перепродавати або перепаковувати самі ці матеріали як навчальний продукт — ні.
