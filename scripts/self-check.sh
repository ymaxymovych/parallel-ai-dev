#!/usr/bin/env bash
# self-check.sh — перевірка «система готова?» для кіту parallel-ai-dev.
#
# Запускати з КОРЕНЯ свого репозиторію:
#     bash <шлях>/parallel-ai-dev/scripts/self-check.sh          # нормативні R1–R9
#     bash <шлях>/parallel-ai-dev/scripts/self-check.sh --full   # + розширена діагностика
#
# Скрипт нічого не змінює і не видаляє — тільки читає і друкує.
#
# ДВА ШАРИ:
#   1) НОРМАТИВНІ перевірки R1–R9 — вирішують код виходу. Друкуються ТІЛЬКИ
#      порушені (зелене мовчить: список на екрані = твій чек-лист, а не шум).
#   2) РОЗШИРЕНА діагностика (свіжість файлів, дисципліна PR, джанкшен-міни…) —
#      порада, а не вердикт. Показується при --full або якщо в проєкті є
#      coordination/.selfcheck.conf. Рядок STRICT_ADVISORY=1 у конфі робить
#      червоне з цього шару теж фатальним (для команд, що хочуть жорсткіше).
#
# Код виходу: 0 — R1–R9 чисті (✅ СИСТЕМА ГОТОВА); 1 — є порушення.
# Правило «тиха невдача заборонена» стосується і цього скрипта.
#
# Сумісність: bash 3.2 (macOS) — без mapfile, без асоціативних масивів.

set -uo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT_VER="?"
[ -f "$KIT_ROOT/VERSION" ] && KIT_VER="$(head -1 "$KIT_ROOT/VERSION" | tr -d '\r ')"

FULL=0
[ "${1:-}" = "--full" ] && FULL=1

# ─────────────────────────────────────────────────────────────── передумови ───
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "🔴 Це не git-репозиторій. Кіт без git не працює: пам'ять, якої нема в git, не існує."
  echo "   Полагодити: git init && git add -A && git commit -m 'початок'"
  echo "❌ ЛИШИЛОСЬ: 1"
  exit 1
fi
cd "$(git rev-parse --show-toplevel)" || exit 1

HAS_HEAD=1
git rev-parse -q --verify HEAD >/dev/null 2>&1 || HAS_HEAD=0

# ── шляхи файлів пам'яті: типова розкладка, перевизначувана .selfcheck.conf ──
# Проєкти рідко мають рівно шаблонну розкладку. Перевірка, що кричить на
# справному стані, вчить ігнорувати червоне — тому і нормативні R-перевірки,
# і діагностика читають той самий конфіг:
#     DECISIONS=docs/DECISIONS.md
#     PROJECT_MAP=coordination/PRODUCT_MAP.md
#     WORKSTREAMS=../_HQ/WORKSTREAMS.md      # можна й поза репо
DECISIONS=coordination/DECISIONS.md
MISTAKES=coordination/MISTAKES.md
PROJECT_MAP=coordination/PROJECT_MAP.md
BACKLOG=coordination/BACKLOG.md
WORKSTREAMS=coordination/WORKSTREAMS.md
STRICT_ADVISORY=0

CONF=coordination/.selfcheck.conf
HAS_CONF=0
if [ -f "$CONF" ]; then
  HAS_CONF=1
  # shellcheck disable=SC1090
  . "$CONF"
fi

# ── SETUP.md: три декларації (visibility / mode / constitution) ──────────────
SETUP=coordination/SETUP.md
VISIBILITY=""; MODE=""; CONSTITUTION="kit"
setup_val() { # $1 = ключ; друкує перше слово після «ключ:»
  sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" "$SETUP" 2>/dev/null \
    | head -1 | awk '{print $1}' | tr -d '\r'
}
if [ -f "$SETUP" ]; then
  VISIBILITY="$(setup_val visibility)"
  MODE="$(setup_val mode)"
  C="$(setup_val constitution)"; [ -n "$C" ] && CONSTITUTION="$C"
fi

# ── допоміжні ────────────────────────────────────────────────────────────────
in_repo() { case "$1" in /*|../*) return 1 ;; *) return 0 ;; esac; }
strip_noise() { # прибирає HTML-коменти і fenced-блоки коду — приклади в шаблонах
  # ОДНОРЯДКОВІ коменти вирізаємо ПЕРШИМИ (s///): sed-діапазон /<!--/,/-->/
  # НЕ закривається на тому ж рядку, де відкрився, — однорядковий комент
  # інакше з'їдає файл до кінця, і живі записи «зникають» (зловлено тестом T3).
  sed 's/<!--.*-->//' "$1" 2>/dev/null | sed '/<!--/,/-->/d' | sed '/^```/,/^```/d'
}

NFAIL=0
FAILS=""
rfail() { # $1 = "R2", $2 = повідомлення
  NFAIL=$((NFAIL+1))
  FAILS="${FAILS}${1} 🔴 ${2}"$'\n'
}

# ─────────────────────────────────────────────────────────── шапка звіту ─────
echo
echo "Самоперевірка кіту parallel-ai-dev (кіт v$KIT_VER)"
echo "Проєкт: $(basename "$(pwd)")"
echo "Дата:   $(date '+%Y-%m-%d %H:%M')"
# «Свіже розгортання?» — якщо пам'ять ще жодного разу не комітилась, червоні
# рядки нижче — не докір, а покроковий план. Скажемо це прямо, бо новачок,
# який щойно все встановив і одразу отримав шість 🔴, вирішує що зламав.
if [ "$HAS_HEAD" = 0 ] || ! git log -1 --format=%H -- coordination/ >/dev/null 2>&1 \
   || [ -z "$(git log -1 --format=%H -- coordination/ 2>/dev/null)" ]; then
  echo
  echo "Це очікувано на цьому кроці: система щойно розгорнута — рядки нижче і є"
  echo "твій чек-лист запуску, а не список поламок."
fi
echo

# ════════════════════════════════════ НОРМАТИВНІ ПЕРЕВІРКИ R1–R9 ═════════════

# R1 — обов'язкові файли існують (шляхи — з конфігу, якщо він є)
R1_MISS=""
for f in CLAUDE.md "$DECISIONS" "$MISTAKES" "$PROJECT_MAP" "$BACKLOG" "$WORKSTREAMS"; do
  [ -e "$f" ] || R1_MISS="$R1_MISS $f"
done
if [ "$CONSTITUTION" = "kit" ] && [ ! -e CLAUDE.parallel-ai-dev.md ]; then
  R1_MISS="$R1_MISS CLAUDE.parallel-ai-dev.md"
fi
[ -n "$R1_MISS" ] && rfail R1 "бракує файлів:$R1_MISS — запусти bash $KIT_ROOT/scripts/init-memory.sh"

# R2 — файли пам'яті ВІДСТЕЖУЮТЬСЯ git-ом (untracked = незастрахований)
if [ "$HAS_HEAD" = 0 ]; then
  rfail R2 "у репозиторії ще немає жодного коміту — зроби перший: git add -A && git commit -m 'початок'"
else
  R2_MISS=""
  for f in CLAUDE.md "$DECISIONS" "$MISTAKES" "$PROJECT_MAP" "$BACKLOG" "$WORKSTREAMS" "$SETUP"; do
    [ -e "$f" ] || continue
    in_repo "$f" || continue   # файл свідомо поза цим репо (конфіг) — git тут не суддя
    git ls-files --error-unmatch "$f" >/dev/null 2>&1 \
      || R2_MISS="$R2_MISS $f"
  done
  [ -e CLAUDE.parallel-ai-dev.md ] && ! git ls-files --error-unmatch CLAUDE.parallel-ai-dev.md >/dev/null 2>&1 \
    && R2_MISS="$R2_MISS CLAUDE.parallel-ai-dev.md"
  [ -n "$R2_MISS" ] && rfail R2 "не закомічені (untracked):$R2_MISS — git add + commit + push, інакше пам'ять не переживе чистку диска"
  # НОВІ файли пам'яті теж мусять бути застраховані: лист в інбоксі чи нотатка,
  # створена але не закомічена, — найчастіший студентський випадок втрати
  # (AC-16; канонічний список вище її не бачить, git diff untracked не показує).
  R2_NEW=$(git ls-files --others --exclude-standard -- coordination/ 2>/dev/null | grep -c . || true)
  [ "${R2_NEW:-0}" -gt 0 ] && rfail R2 "$R2_NEW нових файлів у coordination/ не закомічено — git add + commit + push (git status покаже, які саме)"
fi

# R3 — у ВІДСТЕЖУВАНИХ файлах пам'яті немає незакомічених правок
# (untracked — територія R2; тут ловимо саме «поправив і забув закомітити»)
if [ "$HAS_HEAD" = 1 ]; then
  R3_PATHS="coordination CLAUDE.md"
  [ -e CLAUDE.parallel-ai-dev.md ] && R3_PATHS="$R3_PATHS CLAUDE.parallel-ai-dev.md"
  for f in "$DECISIONS" "$PROJECT_MAP" "$BACKLOG" "$MISTAKES" "$WORKSTREAMS"; do
    in_repo "$f" && case "$f" in coordination/*) : ;; *) R3_PATHS="$R3_PATHS $f" ;; esac
  done
  # shellcheck disable=SC2086
  R3_N=$( { git diff --name-only -- $R3_PATHS; git diff --cached --name-only -- $R3_PATHS; } 2>/dev/null | sort -u | grep -c . || true)
  [ "${R3_N:-0}" -gt 0 ] && rfail R3 "$R3_N файлів пам'яті мають незакомічені правки — закоміть і запуш (git status покаже, які саме)"
fi

# R4 — файли пам'яті не задавлені .gitignore
# --no-index обов'язковий: без нього check-ignore МОВЧИТЬ про вже відстежуваний
# файл під ignore-правилом (перевірено емпірично, рев'ю 2.0.1) — а саме такий
# стан ховає всі МАЙБУТНІ файли поруч.
R4_BAD=""
for f in CLAUDE.md "$DECISIONS" "$MISTAKES" "$PROJECT_MAP" "$BACKLOG" "$WORKSTREAMS" "$SETUP"; do
  in_repo "$f" || continue
  git check-ignore --no-index -q "$f" 2>/dev/null && R4_BAD="$R4_BAD $f"
done
[ -n "$R4_BAD" ] && rfail R4 "гітігнор ховає файли пам'яті:$R4_BAD — прибери ці шляхи з .gitignore"

# R5 — конституція під'єднана
if [ "$CONSTITUTION" = "self-managed" ]; then
  # Проєкт задекларував ВЛАСНУ конституцію: перевіряємо не імпорт, а те, що
  # вона існує і згадує файли звірки (інакше анти-кола нема звідки взятись).
  if [ ! -e CLAUDE.md ]; then
    rfail R5 "constitution: self-managed, але CLAUDE.md відсутній — власна конституція мусить існувати"
  else
    R5_MISS=""
    for f in "$DECISIONS" "$PROJECT_MAP" "$BACKLOG"; do
      k=$(basename "$f" .md)
      grep -q "$k" CLAUDE.md 2>/dev/null || R5_MISS="$R5_MISS $k"
    done
    [ -n "$R5_MISS" ] && rfail R5 "власна конституція не згадує файли звірки:$R5_MISS — чат не знатиме, де звірятись перед задачею"
  fi
else
  if [ ! -e CLAUDE.md ]; then
    rfail R5 "CLAUDE.md відсутній — конституцію не бачить жоден чат; запусти інсталятор кіту"
  elif ! grep -q '^@CLAUDE\.parallel-ai-dev\.md' CLAUDE.md 2>/dev/null; then
    rfail R5 "CLAUDE.md не під'єднує правила кіту — додай ПЕРШИМ рядком після заголовка: @CLAUDE.parallel-ai-dev.md"
  fi
fi

# R6 — карта проєкту заповнена (не порожній шаблон)
if [ -e "$PROJECT_MAP" ]; then
  # Дві умови: (а) файл ВІДРІЗНЯЄТЬСЯ від чистого шаблону кіту (порівнюємо без
  # \r — Windows-переноси не мають вдавати «заповненість»); (б) має хоч один
  # змістовний рядок. Зміст міряємо «будь-яким непробільним символом», а НЕ
  # [[:alnum:]]: у C-локалі git-bash кирилиця — не alnum, і суто українська
  # карта рахувалась порожньою (зловлено тестом T3).
  R6_TPL="$KIT_ROOT/template/coordination/PROJECT_MAP.md"
  # Рядки, що дослівно збігаються з рядками чистого шаблону (шапка таблиці
  # тощо), — не зміст: файл «шапка + роздільник» інакше рахувався заповненим
  # (AC-17, зловлено рев'ю 2.0.1). grep -Fxv -f відсіює саме такі рядки.
  if [ -f "$R6_TPL" ]; then
    R6_N=$(strip_noise "$PROJECT_MAP" | tr -d '\r' | grep -v '^#' | grep -v '^[[:space:]]*>' \
           | grep -v '^[[:space:]]*|[-: |]*$' | grep '[^[:space:]]' \
           | grep -Fxv -f <(tr -d '\r' < "$R6_TPL") | grep -c . || true)
  else
    R6_N=$(strip_noise "$PROJECT_MAP" | grep -v '^#' | grep -v '^[[:space:]]*>' \
           | grep -v '^[[:space:]]*|[-: |]*$' | grep -c '[^[:space:]]' || true)
  fi
  R6_EMPTY=0
  if [ -f "$R6_TPL" ] && cmp -s <(tr -d '\r' < "$PROJECT_MAP") <(tr -d '\r' < "$R6_TPL"); then
    R6_EMPTY=1   # байт-у-байт чистий шаблон
  fi
  { [ "$R6_EMPTY" = 1 ] || [ "${R6_N:-0}" -lt 1 ]; } \
    && rfail R6 "$(basename "$PROJECT_MAP") порожній — впиши, що в проєкті ВЖЕ існує (це насіння анти-кіл: без карти чати будуватимуть уже збудоване)"
fi

# R7 — у рішеннях є хоч один запис
if [ -e "$DECISIONS" ]; then
  # Заголовки записів рахуємо ПІСЛЯ зрізання прикладів: шаблон містить формат
  # запису у fenced-блоці і датований приклад у HTML-коменті — обидва мають
  # НЕ зараховуватись, інакше порожній шаблон рапортує «є записи».
  R7_N=$(strip_noise "$DECISIONS" | grep -c '^## ' || true)
  [ "${R7_N:-0}" -lt 1 ] && rfail R7 "$(basename "$DECISIONS") без жодного запису — додай 3-5 УЖЕ прийнятих рішень з полем «Чому» (рішення без причини не рятує від повторного будівництва)"
fi

# R8 — SETUP.md заповнений допустимими значеннями
if [ ! -f "$SETUP" ]; then
  rfail R8 "нема coordination/SETUP.md — три декларації (visibility/mode/constitution) обов'язкові; запусти інсталятор кіту"
else
  case "$VISIBILITY" in
    private|public-accepted) : ;;
    *) rfail R8 "у SETUP.md поле visibility мусить бути: private або public-accepted" ;;
  esac
  case "$MODE" in
    team|solo) : ;;
    *) rfail R8 "у SETUP.md поле mode мусить бути: team або solo" ;;
  esac
  case "$CONSTITUTION" in
    kit|self-managed) : ;;
    *) rfail R8 "у SETUP.md поле constitution мусить бути: kit або self-managed" ;;
  esac
fi

# R9 — team-режим вимагає ізоляції worktree
# mode ще не задекларовано → рахуємо як team: безпечніше вимагати ізоляцію,
# ніж мовчки її не перевіряти.
if [ "$MODE" != "solo" ]; then
  WT_N=$(git worktree list 2>/dev/null | grep -c . || true)
  if [ "${WT_N:-1}" -lt 2 ]; then
    rfail R9 "паралельні чати без ізоляції — створи робоче дерево: git worktree add ../$(basename "$(pwd)")-chat2 -b chat2 (або задекларуй mode: solo)"
  fi
fi

# ─────────────────────────────────────────────── вердикт нормативного шару ───
if [ "$NFAIL" -eq 0 ]; then
  echo "Перевірено R1…R9: порушень немає."
else
  printf '%s' "$FAILS"
fi
echo

# ════════════════════════════════ РОЗШИРЕНА ДІАГНОСТИКА (порада, не вирок) ═══
ADV_SHOWN=0
ADV_FAIL=0
if [ "$FULL" = 1 ] || [ "$HAS_CONF" = 1 ]; then
  ADV_SHOWN=1
  PASS=0; WARN=0; FAIL=0
  ROWS=""
  row() { # <статус> <правило> <доказ>
    local s="$1" r="$2" e="$3"
    case "$s" in
      ok)   PASS=$((PASS+1)); s="🟢 так" ;;
      warn) WARN=$((WARN+1)); s="🟡 частково" ;;
      bad)  FAIL=$((FAIL+1)); s="🔴 ні" ;;
      skip) s="⚪ н/д" ;;
    esac
    # Роздільник — табуляція, а не «|»: докази часто містять саме «|», і на
    # «|» таблиця розсипається. Це не гіпотетично — так зламався перший прогін.
    e="${e//$'\t'/ }"
    ROWS+="$s"$'\t'"$r"$'\t'"$e"$'\n'
  }
  have() { git ls-files --error-unmatch "$1" >/dev/null 2>&1; }

  echo "── Розширена діагностика (не впливає на вердикт R1–R9$( [ "$STRICT_ADVISORY" = 1 ] && echo '; STRICT_ADVISORY=1 — впливає' )) ──"
  echo

  # 1. основа
  if git remote | grep -q .; then
    row ok "Є remote (push як страховка)" "$(git remote | head -1)"
  else
    row bad "Є remote (push як страховка)" "git remote порожній — робота застрахована лише локальним диском"
  fi

  if [ -e CLAUDE.md ]; then
    L=$(wc -l < CLAUDE.md | tr -d ' ')
    if [ "$L" -gt 400 ]; then
      row warn "CLAUDE.md не роздутий" "$L рядків — він у контексті КОЖНОЇ сесії; винось об'ємне в довідкові файли"
    else
      row ok "CLAUDE.md не роздутий" "$L рядків"
    fi
  fi

  # Шукаємо НЕ будь-яке <…>: у здоровому CLAUDE.md повно законних <шлях>, <PR#>
  # усередині прикладів команд. Ловимо рівно рядки-заготовки шаблону кіту.
  # (Наш власний прогін дав 19 «порушень», усі хибні. Тому й переписано.)
  PH_TOKENS='<НАЗВА>|<перелічи шляхи|<напр\. |<\.\.\.>'
  # Обережно: `grep -c` без збігів САМ друкує «0» і виходить з кодом 1 —
  # запасне `echo 0` дописало б другий рядок. Правильно — `|| true`.
  PH=$(grep -cE "$PH_TOKENS" CLAUDE.md 2>/dev/null || true)
  if [ "${PH:-0}" -gt 0 ]; then
    row bad "Заготовки шаблону в CLAUDE.md заповнені" "лишилось $PH рядків-заготовок — ризикові зони чи команди перевірки/деплою не вписані"
  else
    row ok "Заготовки шаблону в CLAUDE.md заповнені" "незаповнених заготовок не знайдено"
  fi

  # 2. свіжість файлів пам'яті
  for f in "$DECISIONS" "$MISTAKES" "$PROJECT_MAP" "$BACKLOG" "$WORKSTREAMS"; do
    n=$(basename "$f")
    if have "$f" || [ -f "$f" ]; then
      TS=$(git log -1 --format=%at -- "$f" 2>/dev/null)
      if [ -n "$TS" ]; then
        LAST=$(git log -1 --format=%ad --date=short -- "$f")
        SRC="останній коміт"
        NOCOMMIT=0
      else
        # Коміта немає з двох РІЗНИХ причин, і плутати їх не можна: файл або
        # щойно створений і незакомічений (попередження), або лежить в іншому
        # репозиторії (у нас так із WORKSTREAMS — тоді дивимось диск).
        TS=$(date -r "$f" +%s 2>/dev/null || echo 0)
        LAST=$(date -r "$f" '+%Y-%m-%d' 2>/dev/null || echo "невідомо")
        NOCOMMIT=1
        case "$f" in
          /*|../*) SRC="змінено на диску (файл поза цим репозиторієм)"; NOCOMMIT=0 ;;
          *)       SRC="створено $LAST, але ЩЕ НЕ ЗАКОМІЧЕНО" ;;
        esac
      fi
      AGE_D=$(( ( $(date +%s) - TS ) / 86400 ))
      if [ "$NOCOMMIT" = 1 ]; then
        row warn "$n живий" "$SRC — закоміть, інакше файл не застрахований"
      elif [ "$AGE_D" -gt 30 ]; then
        row warn "$n живий" "$SRC $LAST — понад 30 днів тому; файл є, але мертвий"
      else
        row ok "$n живий" "$SRC $LAST"
      fi
    else
      row bad "$n існує" "файлу немає"
    fi
  done

  # Якість записів: «Чому» в рішеннях, «Правило» в помилках
  if [ -f "$DECISIONS" ]; then
    H=$(strip_noise "$DECISIONS" | grep -c '^## ' || true)
    W=$(strip_noise "$DECISIONS" | grep -c '^\*\*Чому' || true)
    if [ "${H:-0}" -gt 0 ] && [ "${W:-0}" -lt "$H" ]; then
      row warn "Кожне рішення має «Чому»" "записів $H, полів «Чому» $W"
    elif [ "${H:-0}" -gt 0 ]; then
      row ok "Кожне рішення має «Чому»" "записів $H, полів «Чому» $W"
    fi
  fi
  if [ -f "$MISTAKES" ]; then
    H=$(strip_noise "$MISTAKES" | grep -c '^## ' || true)
    R=$(strip_noise "$MISTAKES" | grep -c 'Правило на майбутнє' || true)
    if [ "${H:-0}" -gt 0 ] && [ "${R:-0}" -lt "$H" ]; then
      row warn "Кожна помилка має правило" "записів $H, правил $R — запис без правила це щоденник, а не запобіжник"
    elif [ "${H:-0}" -gt 0 ]; then
      row ok "Кожна помилка має правило" "записів $H, правил $R"
    fi
  fi

  # 4. координація
  # README.md всередині інбоксу — інструкція, а не лист: без виключення порожній
  # інбокс щойно встановленого кіту рапортує «1 лист».
  IN=$(git ls-files 'coordination/inbox/*' 2>/dev/null | grep -vi '/readme\.md$' | grep -c . || true)
  if [ "${IN:-0}" -eq 0 ]; then
    row warn "Інбокс використовується" "0 листів у git — або чат один, або листування йде повз git"
  else
    OKN=$(git ls-files 'coordination/inbox/*' | grep -vi '/readme\.md$' | grep -c 'from-.*-to-' || true)
    row ok "Інбокс використовується" "$IN листів, з них $OKN за форматом from-*-to-*"
  fi

  DEL=$(git log --diff-filter=D --name-only --format= -- coordination/inbox/ 2>/dev/null | grep -c 'coordination/inbox/' || true)
  if [ "${DEL:-0}" -gt 0 ]; then
    row bad "Оброблені листи не видаляються" "знайдено $DEL видалень — інбокс це журнал, його не чистять"
  else
    row ok "Оброблені листи не видаляються" "видалень в історії немає"
  fi

  if [ -f "$WORKSTREAMS" ]; then
    # Рахуємо ТІЛЬКИ рядки таблиці: [COORD] законно стоїть і в тексті правила,
    # і в закоментованому прикладі — інакше свіжий шаблон рапортує «двоє координаторів».
    WS_ROWS=$(strip_noise "$WORKSTREAMS" | grep '^[[:space:]]*|' | grep '\[COORD\]' || true)
    C=$(printf '%s' "$WS_ROWS" | grep -c . || true)
    TODAY=$(date '+%Y-%m-%d')
    if [ "${C:-0}" -eq 0 ]; then
      row warn "Рівно один координатор із сьогоднішньою датою" "рядків [COORD] немає — роль нічия"
    elif [ "$C" -gt 1 ]; then
      row bad "Рівно один координатор" "рядків [COORD] $C — двоє координаторів це зіткнення на одному PR"
    elif printf '%s' "$WS_ROWS" | grep -q "$TODAY"; then
      row ok "Рівно один координатор із сьогоднішньою датою" "рядок [COORD] позначений $TODAY"
    else
      row warn "Дата координатора свіжа" "рядок [COORD] є, але дата не сьогоднішня — роль вільна"
    fi
  fi

  # 5. дисципліна
  U=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$U" -gt 0 ]; then
    row warn "Немає незакомічених змін" "$U файлів брудні — невідстежуваний файл це незастрахований файл"
  else
    row ok "Немає незакомічених змін" "робоче дерево чисте"
  fi

  UP=$(git log --oneline @{u}..HEAD 2>/dev/null | wc -l | tr -d ' ')
  if [ "${UP:-0}" -gt 0 ]; then
    row warn "Усе запушено" "$UP комітів не запушено — push і є страховка"
  else
    row ok "Усе запушено" "локальних незапушених комітів немає"
  fi

  MAIN=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')
  MAIN=${MAIN:-main}
  TOT=$(git log --first-parent "origin/$MAIN" --format='%s' -40 2>/dev/null | wc -l | tr -d ' ')
  VIAPR=$(git log --first-parent "origin/$MAIN" --format='%s' -40 2>/dev/null | grep -c '(#[0-9]' || true)
  if [ "${TOT:-0}" -gt 0 ]; then
    if [ "$VIAPR" -lt $(( TOT * 8 / 10 )) ]; then
      row warn "Здача через PR, а не прямі коміти" "$VIAPR із $TOT останніх комітів прийшли через PR"
    else
      row ok "Здача через PR, а не прямі коміти" "$VIAPR із $TOT останніх комітів прийшли через PR"
    fi
  fi

  # 6. гейти: проковтнуті коди виходу
  # \b навколо назв обов'язкові: без них «tsconfig.json» матчиться як «tsc» і
  # скрипт репортує порушення там, де його немає.
  GATE_RE='\b(tsc|eslint|vitest|jest|pytest|next build)\b[^|&]*(\|[[:space:]]*(tail|head)|\|\|[[:space:]]*true)'
  SW_LINES=$(grep -rnE "$GATE_RE" \
       --include='*.sh' --include='*.yml' --include='*.yaml' --include='package.json' . 2>/dev/null \
       | grep -v '^\./\.git/' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')
  SW=$(printf '%s' "$SW_LINES" | grep -c . || true)
  if [ "${SW:-0}" -gt 0 ]; then
    FIRST=$(printf '%s' "$SW_LINES" | head -1 | cut -c1-60)
    row bad "Коди виходу гейтів не ковтаються" "$SW місць, напр. $FIRST — гейт вимкнено, а виглядає ввімкненим"
  else
    row ok "Коди виходу гейтів не ковтаються" "конструкцій tail/head/true біля гейтів не знайдено"
  fi

  # 7. робочі дерева і джанкшен-міни
  WT=$(git worktree list 2>/dev/null | wc -l | tr -d ' ')
  MINES=0; MINELIST=""
  while read -r d _; do
    [ -z "$d" ] && continue
    for nm in "$d/node_modules" "$d/vendor" "$d/.venv"; do
      if [ -L "$nm" ]; then MINES=$((MINES+1)); MINELIST="$MINELIST\n      $nm -> $(readlink "$nm" 2>/dev/null)"; fi
    done
  done < <(git worktree list 2>/dev/null | awk '{print $1}')

  # ⚠️ Чесне обмеження: git-bash на Windows бачить як посилання ДАЛЕКО не кожен
  # NTFS junction (на нашому репо bash нарахував 19 мін, PowerShell — 39).
  # Число нижче на Windows — НИЖНЯ межа; остаточну відповідь дає
  # PowerShell-команда, яку скрипт друкує в кінці.
  IS_WIN=0
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) IS_WIN=1 ;; esac

  if [ "$WT" -gt 20 ]; then
    row warn "Дерева не накопичуються" "$WT дерев — прибирай завершені: git worktree remove <шлях>"
  else
    row ok "Дерева не накопичуються" "$WT дерев"
  fi

  if [ "$MINES" -gt 0 ]; then
    SUF=""; [ "$IS_WIN" = 1 ] && SUF=" (на Windows це НИЖНЯ межа, реально більше)"
    row bad "Дерева без джанкшен-мін" "$MINES дерев мають посилання на спільні залежності$SUF — рекурсивне видалення такої теки вигребе код головного проєкту"
  elif [ "$IS_WIN" = 1 ]; then
    row warn "Дерева без джанкшен-мін" "bash на Windows бачить не всі junction — перевір PowerShell-командою внизу"
  else
    row ok "Дерева без джанкшен-мін" "посилань на спільні залежності в деревах не знайдено"
  fi

  # 8. версія кіту
  if [ -f coordination/.kit-version ]; then
    row ok "Відома версія кіту" "$(head -1 coordination/.kit-version | cut -c1-12)"
  else
    row warn "Відома версія кіту" "coordination/.kit-version немає — перевірка свіжості чесно скаже «не знаю»"
  fi

  printf '%b' "$ROWS" | awk -F'\t' '
    BEGIN { printf "%-12s  %-44s  %s\n", "СТАН", "ПРАВИЛО", "ЧИМ ДОВЕДЕНО";
            printf "%-12s  %-44s  %s\n", "----", "-------", "------------" }
    NF>=3 { printf "%-12s  %-44s  %s\n", $1, $2, $3 }'
  echo
  echo "Діагностика: 🟢 $PASS   🟡 $WARN   🔴 $FAIL"
  if [ -n "$MINELIST" ]; then
    echo
    echo "  ⚠️  Дерева, які НЕ МОЖНА видаляти як звичайну папку:"
    printf '%b\n' "$MINELIST"
    echo "      Прибирати тільки: git worktree remove <шлях>"
  fi
  if [ "$IS_WIN" = 1 ]; then
    echo
    echo "  Windows: повний список мін дає лише PowerShell (bash бачить не всі junction) —"
    echo "  git worktree list | ForEach-Object { (\$_ -split '\\s+')[0] } | ForEach-Object {"
    echo "    \$n = Join-Path \$_ 'node_modules'"
    echo "    if (Test-Path \$n) { \$i = Get-Item \$n -Force; if (\$i.LinkType) { \"\$n -> \$(\$i.Target)\" } } }"
  fi
  echo
  ADV_FAIL=$FAIL
fi

# ═══════════════════════════════════════════════════ підсумковий вердикт ═════
if [ "$NFAIL" -eq 0 ] && { [ "$STRICT_ADVISORY" != 1 ] || [ "$ADV_FAIL" -eq 0 ]; }; then
  echo "✅ СИСТЕМА ГОТОВА"
  exit 0
fi
if [ "$NFAIL" -eq 0 ] && [ "$STRICT_ADVISORY" = 1 ] && [ "$ADV_FAIL" -gt 0 ]; then
  echo "R1–R9 чисті, але STRICT_ADVISORY=1 і в діагностиці $ADV_FAIL 🔴 — полагодь їх."
  echo "❌ ЛИШИЛОСЬ: $ADV_FAIL"
  exit 1
fi
echo "❌ ЛИШИЛОСЬ: $NFAIL"
exit 1
