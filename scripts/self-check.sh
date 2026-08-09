#!/usr/bin/env bash
# self-check.sh — перевірка, чи твій проєкт справді живе за правилами кіту.
#
# Запускати з КОРЕНЯ свого репозиторію:
#     bash <шлях>/parallel-ai-dev/scripts/self-check.sh
#
# Скрипт нічого не змінює і нічого не видаляє. Він тільки читає і друкує таблицю
# «правило → так/ні → чим доведено». Колонка «чим доведено» існує навмисно:
# перевірка без доказу — це така сама думка, як і спогад «начебто робимо».
#
# Код виходу: 0 — критичних порушень немає; 1 — є хоча б одне 🔴.
# (Правило «тиха невдача заборонена» стосується і цього скрипта.)

set -uo pipefail

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
  # Роздільник — табуляція, а не «|»: докази часто містять саме «|»
  # (наприклад конструкцію, через яку ковтається код виходу), і на «|» таблиця
  # розсипається. Це не гіпотетично — саме так зламався перший прогін.
  e="${e//$'\t'/ }"
  ROWS+="$s"$'\t'"$r"$'\t'"$e"$'\n'
}

have() { git ls-files --error-unmatch "$1" >/dev/null 2>&1; }
count_files() { git ls-files "$1" 2>/dev/null | wc -l | tr -d ' '; }

# Проєкти рідко мають рівно ту саму розкладку, що в шаблоні. Якщо твої файли
# лежать інакше — створи coordination/.selfcheck.conf і перевизнач шляхи:
#     DECISIONS=docs/DECISIONS.md
#     BACKLOG=.ai-context/BACKLOG.md
#     PROJECT_MAP=coordination/PRODUCT_MAP.md
#     WORKSTREAMS=../_HQ/WORKSTREAMS.md      # можна й поза репо
# Інакше скрипт кричатиме «файлу немає» на файл, який просто лежить деінде —
# а перевірка, що кричить на справному стані, вчить ігнорувати червоне.
DECISIONS=coordination/DECISIONS.md
MISTAKES=coordination/MISTAKES.md
PROJECT_MAP=coordination/PROJECT_MAP.md
BACKLOG=coordination/BACKLOG.md
WORKSTREAMS=coordination/WORKSTREAMS.md

# ─────────────────────────────────────────────────────────────── передумови ───
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "🔴 Це не git-репозиторій. Кіт без git не працює: пам'ять, якої нема в git, не існує."
  echo "   Полагодити: git init && git add -A && git commit -m 'початок'"
  exit 1
fi
cd "$(git rev-parse --show-toplevel)" || exit 1

CONF=coordination/.selfcheck.conf
if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF"
  CONF_NOTE="(шляхи перевизначено у $CONF)"
else
  CONF_NOTE="(типова розкладка; свої шляхи задай у $CONF)"
fi

echo
echo "Самоперевірка кіту паралельної AI-розробки"
echo "Проєкт: $(pwd)"
echo "Дата:   $(date '+%Y-%m-%d %H:%M')  $CONF_NOTE"
echo

# ───────────────────────────────────────────────────────────── 1. основа ──────
if git remote -v | grep -q .; then
  row ok "Є remote (push як страховка)" "$(git remote | head -1)"
else
  row bad "Є remote (push як страховка)" "git remote порожній — робота застрахована лише локальним диском"
fi

if have CLAUDE.md; then
  L=$(wc -l < CLAUDE.md | tr -d ' ')
  if [ "$L" -gt 400 ]; then
    row warn "CLAUDE.md у git і не роздутий" "є, але $L рядків — він у контексті КОЖНОЇ сесії; винось об'ємне нижче"
  else
    row ok "CLAUDE.md у git і не роздутий" "$L рядків"
  fi
else
  row bad "CLAUDE.md у git" "файлу немає або він не закомічений — чати не бачать правил"
fi

# Шукаємо НЕ будь-яке <…>: у здоровому CLAUDE.md повно законних <шлях>, <PR#>,
# <TASK_ID> усередині прикладів команд. Ловимо рівно ті рядки-заготовки, які
# лишає шаблон кіту, — інакше перевірка червоніє на нормальному файлі.
# (Наш власний прогін дав 19 «порушень», усі до одного хибні. Тому й переписано.)
PH_TOKENS='<НАЗВА>|<перелічи шляхи|<напр\. |<\.\.\.>'
# Обережно з `grep -c … || echo 0`: grep без збігів САМ друкує «0» і виходить з
# кодом 1, тож запасне `echo 0` дописує другий рядок і порівняння падає з
# «integer expression expected». Правильно — `|| true`.
PH=$(grep -cE "$PH_TOKENS" CLAUDE.md 2>/dev/null || true)
if [ "${PH:-0}" -gt 0 ]; then
  row bad "Заготовки шаблону в CLAUDE.md заповнені" "лишилось $PH рядків-заготовок — ризикові зони чи команди перевірки/деплою не вписані"
else
  row ok "Заготовки шаблону в CLAUDE.md заповнені" "незаповнених заготовок шаблону не знайдено"
fi

# ──────────────────────────────────────────────────── 2. файли пам'яті ────────
for f in "$DECISIONS" "$MISTAKES" "$PROJECT_MAP" "$BACKLOG" "$WORKSTREAMS"; do
  n=$(basename "$f")
  if have "$f" || [ -f "$f" ]; then
    # Файл може лежати поза цим репо (у нас так із WORKSTREAMS — він у спільному
    # штабному репозиторії). Тоді git тут про нього нічого не знає й мовчки
    # віддає порожньо, а вік рахується від нуля — тобто «мертвий» на живому
    # файлі. Тому за відсутності коміта беремо час зміни на диску.
    TS=$(git log -1 --format=%at -- "$f" 2>/dev/null)
    if [ -n "$TS" ]; then
      LAST=$(git log -1 --format=%ad --date=short -- "$f")
      SRC="останній коміт"
    else
      TS=$(date -r "$f" +%s 2>/dev/null || echo 0)
      LAST=$(date -r "$f" '+%Y-%m-%d' 2>/dev/null || echo "невідомо")
      SRC="змінено на диску (поза цим репо)"
    fi
    AGE_D=$(( ( $(date +%s) - TS ) / 86400 ))
    if [ "$AGE_D" -gt 30 ]; then
      row warn "$n живий" "$SRC $LAST — понад 30 днів тому; файл є, але мертвий"
    else
      row ok "$n живий" "$SRC $LAST"
    fi
  else
    row bad "$n існує" "файлу немає в git"
  fi
done

# DECISIONS: у кожного запису має бути «Чому»
if [ -f "$DECISIONS" ]; then
  H=$(grep -c '^## ' "$DECISIONS" || true)
  W=$(grep -c '^\*\*Чому' "$DECISIONS" || true)
  if [ "$H" -eq 0 ]; then
    row bad "У DECISIONS є записи" "жодного запису — це порожній шаблон, запобіжник анти-кіл не працює"
  elif [ "$W" -lt "$H" ]; then
    row warn "Кожне рішення має «Чому»" "записів $H, полів «Чому» $W — рішення без причини не рятує від повторного будівництва"
  else
    row ok "Кожне рішення має «Чому»" "записів $H, полів «Чому» $W"
  fi
fi

# MISTAKES: у кожного запису має бути корінь і правило
if [ -f "$MISTAKES" ]; then
  H=$(grep -c '^## ' "$MISTAKES" || true)
  R=$(grep -c 'Правило на майбутнє' "$MISTAKES" || true)
  if [ "$H" -eq 0 ]; then
    row bad "У MISTAKES є записи" "жодного запису — ті самі помилки повертатимуться під новими назвами"
  elif [ "$R" -lt "$H" ]; then
    row warn "Кожна помилка має правило" "записів $H, правил $R — запис без правила це щоденник, а не запобіжник"
  else
    row ok "Кожна помилка має правило" "записів $H, правил $R"
  fi
fi

# ─────────────────────────────────────────────── 3. запобіжник анти-кіл ───────
# Шукаємо РЕАЛЬНІ імена файлів (з .selfcheck.conf, якщо він є), а не шаблонні
# ключі. Інакше проєкт, у якого карта зветься PRODUCT_MAP, вічно червонітиме на
# правилі, яке насправді виконує.
MISS=""
for f in "$DECISIONS" "$PROJECT_MAP" "$BACKLOG"; do
  k=$(basename "$f" .md)
  grep -q "$k" CLAUDE.md 2>/dev/null || MISS="$MISS $k"
done
if [ -n "$MISS" ]; then
  row bad "Звірка перед задачею описана в CLAUDE.md" "у конституції не названо:$MISS — чат не знатиме, де звірятись"
else
  row ok "Звірка перед задачею описана в CLAUDE.md" "названо всі три файли звірки"
fi

# ──────────────────────────────────────────────────────── 4. координація ──────
IN=$(count_files 'coordination/inbox/*')
if [ "$IN" -eq 0 ]; then
  row warn "Інбокс використовується" "0 листів у git — або чат один, або листування йде повз git і не переживе перезапуск"
else
  OKN=$(git ls-files 'coordination/inbox/*' | grep -c 'from-.*-to-' || true)
  row ok "Інбокс використовується" "$IN листів, з них $OKN за форматом імен from-*-to-*"
fi

DEL=$(git log --diff-filter=D --name-only --format= -- coordination/inbox/ 2>/dev/null | grep -c 'coordination/inbox/' || true)
if [ "${DEL:-0}" -gt 0 ]; then
  row bad "Оброблені листи не видаляються" "знайдено $DEL видалень — інбокс це журнал, його не чистять"
else
  row ok "Оброблені листи не видаляються" "видалень в історії немає"
fi

if have coordination/WORKSTREAMS.md; then
  C=$(grep -c '\[COORD\]' coordination/WORKSTREAMS.md || true)
  TODAY=$(date '+%Y-%m-%d')
  if [ "$C" -eq 0 ]; then
    row warn "Рівно один координатор із сьогоднішньою датою" "рядків [COORD] немає — роль нічия, ризиковані PR нікому мерджити"
  elif [ "$C" -gt 1 ]; then
    row bad "Рівно один координатор" "рядків [COORD] $C — двоє координаторів це зіткнення на одному PR"
  elif grep '\[COORD\]' coordination/WORKSTREAMS.md | grep -q "$TODAY"; then
    row ok "Рівно один координатор із сьогоднішньою датою" "рядок [COORD] позначений $TODAY"
  else
    row warn "Дата координатора свіжа" "рядок [COORD] є, але дата не сьогоднішня — за протоколом роль вільна"
  fi
fi

# ───────────────────────────────────────────────────────── 5. дисципліна ──────
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
    row warn "Здача через PR, а не прямі коміти" "$VIAPR із $TOT останніх комітів у $MAIN прийшли через PR"
  else
    row ok "Здача через PR, а не прямі коміти" "$VIAPR із $TOT останніх комітів у $MAIN прийшли через PR"
  fi
fi

# ────────────────────────────────────── 6. гейти: проковтнуті коди виходу ─────
# \b навколо назв обов'язкові: без них «tsconfig.json» матчиться як «tsc» і скрипт
# репортує порушення там, де його немає. Перевірка, що бреше в бік «погано»,
# помирає так само швидко, як та, що бреше в бік «добре».
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

# ────────────────────────────────────────── 7. робочі дерева і джанкшен-міни ──
WT=$(git worktree list 2>/dev/null | wc -l | tr -d ' ')
MINES=0; MINELIST=""
while read -r d _; do
  [ -z "$d" ] && continue
  for nm in "$d/node_modules" "$d/vendor" "$d/.venv"; do
    if [ -L "$nm" ]; then MINES=$((MINES+1)); MINELIST="$MINELIST\n      $nm -> $(readlink "$nm" 2>/dev/null)"; fi
  done
done < <(git worktree list 2>/dev/null | awk '{print $1}')

# ⚠️ Чесне обмеження на Windows. Git-bash бачить як посилання ДАЛЕКО не кожен
# NTFS junction — на нашому ж репозиторії bash нарахував 19 мін, а PowerShell
# 39 на тих самих теках. Тому на Windows число нижче — це НИЖНЯ межа, і
# остаточну відповідь дає PowerShell-команда, яку скрипт друкує в кінці.
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
  row warn "Дерева без джанкшен-мін" "bash на Windows бачить не всі junction — перевір PowerShell-командою внизу, перш ніж вважати, що чисто"
else
  row ok "Дерева без джанкшен-мін" "посилань на спільні залежності в деревах не знайдено"
fi

# ───────────────────────────────────────────────────── 8. версія кіту ─────────
if [ -f coordination/.kit-version ]; then
  row ok "Відома версія кіту" "$(head -c 12 coordination/.kit-version)…"
else
  row warn "Відома версія кіту" "coordination/.kit-version немає — перевірка свіжості чесно скаже «не знаю»"
fi

# ───────────────────────────────────────────────────────────── друк ──────────
printf '%b' "$ROWS" | awk -F'\t' '
  BEGIN { printf "%-12s  %-44s  %s\n", "СТАН", "ПРАВИЛО", "ЧИМ ДОВЕДЕНО";
          printf "%-12s  %-44s  %s\n", "----", "-------", "------------" }
  NF>=3 { printf "%-12s  %-44s  %s\n", $1, $2, $3 }'

echo
echo "Підсумок: 🟢 $PASS   🟡 $WARN   🔴 $FAIL"
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

if [ "$FAIL" -gt 0 ]; then
  echo "Є критичні порушення. Це не привід переписувати документацію — це привід"
  echo "полагодити те, що вона описує."
  exit 1
fi
echo "Критичних порушень немає."
exit 0
