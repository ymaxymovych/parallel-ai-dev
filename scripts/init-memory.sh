#!/usr/bin/env bash
# init-memory.sh — розгортає структуру пам'яті у ТВОЄМУ проєкті.
#
# Запуск із кореня свого репозиторію:
#   bash /шлях/до/parallel-ai-dev/scripts/init-memory.sh
#
# Нічого НЕ перезаписує: якщо файл уже існує, він лишається як є,
# а скрипт про це каже. Безпечно запускати повторно.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/template"
DEST_DIR="$(pwd)"

if [ ! -d "$SRC_DIR" ]; then
  echo "❌ Не знайдено теку шаблонів: $SRC_DIR" >&2
  exit 1
fi

# Захист від «розгорнув кіт у самому кіті»: якщо в цільовій теці лежить маркер
# комплекту — це клон/форк parallel-ai-dev, а не робочий проєкт. Перевіряємо
# МАРКЕР-ФАЙЛ, а не назву теки чи адресу remote: теку перейменовують, remote
# у форків інший, а файл їде з клоном завжди.
if [ -f "$DEST_DIR/.parallel-ai-dev-kit" ]; then
  echo "❌ Це тека самого комплекту parallel-ai-dev (є маркер .parallel-ai-dev-kit)." >&2
  echo "   Перейди в корінь СВОГО проєкту і запусти звідти:" >&2
  echo "   cd /шлях/до/твого/проєкту && bash $SRC_DIR/../scripts/init-memory.sh" >&2
  exit 1
fi

# Перевіряти git через наявність ТЕКИ .git не можна: у git worktree (а саме туди
# цей комплект і відправляє робочі чати) `.git` — це ФАЙЛ із рядком «gitdir: …».
# Стара перевірка `[ -d .git ]` через це відмовлялася працювати рівно в тому
# режимі, який сама ж вчить використовувати. Знайдено, коли вперше запустили
# комплект на власному монорепо (10.08.2026).
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Поточна тека не є git-репозиторієм." >&2
  echo "   Пам'ять, якої нема в git, не існує — спершу: git init && git commit" >&2
  exit 1
fi

# «Я в корені репо?» питаємо в git, а не порівнюємо рядки шляхів: на Windows
# `git rev-parse --show-toplevel` віддає `D:/Temp/...`, а `pwd` у git-bash —
# `/tmp/...`, і буквальне порівняння одної й тої ж теки провалюється. Порожній
# `--show-prefix` означає рівно «поточна тека і є корінь» у будь-якій ОС.
if [ -n "$(git rev-parse --show-prefix)" ]; then
  echo "❌ Запускай із КОРЕНЯ репозиторію, а не з підтеки." >&2
  echo "   Зараз ти тут: $DEST_DIR" >&2
  echo "   Корінь репо:  $(git rev-parse --show-toplevel)" >&2
  echo "   Інакше пам'ять ляже в підтеку, і жоден чат її не знайде." >&2
  exit 1
fi

# Якщо в проєкті вже є `.selfcheck.conf`, він КАНОН: там записано, де насправді
# живуть рішення/карта/беклог у цьому репозиторії. Без цього кроку встановлення
# в непорожній проєкт створює мертві дублікати шаблонних файлів поруч із живими —
# тобто рівно те роздвоєння правди, проти якого весь комплект.
# (Свідомо БЕЗ асоціативних масивів: macOS досі несе bash 3.2, де `declare -A`
# просто падає, а комплект мусить ставитись і на маку.)
CONF="$DEST_DIR/coordination/.selfcheck.conf"
[ -f "$CONF" ] && echo "•  знайдено coordination/.selfcheck.conf — беру шляхи звідти"

canon_path() {
  # $1 — ключ (DECISIONS, PROJECT_MAP…). Друкує шлях із конфігу або нічого.
  [ -f "$CONF" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CONF" \
    | head -1 | tr -d '"' | tr -d "\r"
}

created=0
skipped=0
redirected=0

copy_one() {
  local rel="$1"
  local key="${2:-}"
  local src="$SRC_DIR/$rel"
  local dst="$DEST_DIR/$rel"

  if [ -n "$key" ]; then
    local canon; canon="$(canon_path "$key")"
    if [ -n "$canon" ] && [ "$canon" != "$rel" ]; then
      case "$canon" in /*|../*) : ;; *) canon="$DEST_DIR/$canon" ;; esac
      if [ -e "$canon" ]; then
        echo "↪  канон уже є, шаблон не створюю: $rel → $(canon_path "$key")"
        redirected=$((redirected + 1))
        return 0
      fi
      echo "⚠  .selfcheck.conf вказує на $(canon_path "$key"), але файлу там нема" >&2
    fi
  fi

  if [ -e "$dst" ]; then
    echo "•  вже є, не чіпаю: $rel"
    skipped=$((skipped + 1))
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo "✅ створено: $rel"
  created=$((created + 1))
}

# Якщо проєкт УЖЕ задекларував у SETUP.md власну конституцію
# (constitution: self-managed) — файли конституції кіту не потрібні:
# нав'язувати їх означало б створити другий потік правил поруч із живим.
SELF_MANAGED=0
if [ -f "$DEST_DIR/coordination/SETUP.md" ]; then
  grep -qE '^[[:space:]]*constitution:[[:space:]]*self-managed' "$DEST_DIR/coordination/SETUP.md" \
    && SELF_MANAGED=1
fi

# Конституція — ДВА файли з різними власниками:
#   CLAUDE.parallel-ai-dev.md — правила кіту, оновлюються кітом (не редагується);
#   CLAUDE.md                 — файл КОРИСТУВАЧА: інсталятор створює його лише
#                               якщо його НЕМАЄ, і ніколи не перезаписує наявний.
if [ "$SELF_MANAGED" = 1 ]; then
  echo "•  constitution: self-managed — файли конституції кіту не розгортаю"
else
copy_one "CLAUDE.parallel-ai-dev.md"
if [ -e "$DEST_DIR/CLAUDE.md" ]; then
  if grep -q '^@CLAUDE\.parallel-ai-dev\.md' "$DEST_DIR/CLAUDE.md" 2>/dev/null; then
    echo "•  вже є, не чіпаю: CLAUDE.md (імпорт правил кіту на місці)"
    skipped=$((skipped + 1))
  else
    echo "⚠  CLAUDE.md уже існує — я його НЕ чіпаю (він твій). Щоб під'єднати"
    echo "   правила кіту, додай у нього ОДИН рядок (окремим рядком, зверху):"
    echo
    echo "   @CLAUDE.parallel-ai-dev.md"
    echo
  fi
else
  copy_one "CLAUDE.md"
fi
fi
copy_one "coordination/WORKSTREAMS.md" WORKSTREAMS
copy_one "coordination/DECISIONS.md"   DECISIONS
copy_one "coordination/BACKLOG.md"     BACKLOG
copy_one "coordination/MISTAKES.md"    MISTAKES
copy_one "coordination/PROJECT_MAP.md" PROJECT_MAP
copy_one "coordination/SETUP.md"
copy_one "coordination/inbox/README.md"
copy_one "coordination/log/README.md"

# .gitattributes: shell-скрипти мусять жити з LF — git на Windows із
# core.autocrlf=true інакше підсуне CRLF, і bash упаде на першому ж рядку.
# ДОПИСУЄМО рядок, ніколи не перезаписуємо чужий файл.
GA="$DEST_DIR/.gitattributes"
GA_LINE='*.sh text eol=lf'
if [ -f "$GA" ] && grep -qF "$GA_LINE" "$GA"; then
  echo "•  вже є, не чіпаю: .gitattributes (правило LF для *.sh на місці)"
  skipped=$((skipped + 1))
else
  # Якщо чужий файл закінчується БЕЗ переводу рядка — спершу додаємо його,
  # інакше наше правило приклеїться до останнього рядка користувача і зламає
  # обидва (зловлено рев'ю 2.0.1: `tail -c1` віддає порожньо лише для \n).
  [ -s "$GA" ] && [ -n "$(tail -c1 "$GA")" ] && printf '\n' >> "$GA"
  printf '%s\n' "$GA_LINE" >> "$GA"
  echo "✅ дописано в .gitattributes: $GA_LINE"
  created=$((created + 1))
fi

# Мітка версії: з якої версії комплекту зроблено цю інсталяцію. Без неї
# update-kit.sh не може сказати, які шаблони змінились ПІСЛЯ твого встановлення,
# і чесно відповідає «не знаю» замість «все свіже».
# З 2.0.0 мітка — це номер версії (файл VERSION у корені кіту); для комплекту
# без VERSION (старий клон) лишається запасний варіант — хеш коміту.
KIT_DIR="$(cd "$SRC_DIR/.." && pwd)"
mkdir -p "$DEST_DIR/coordination"
if [ -f "$KIT_DIR/VERSION" ]; then
  head -1 "$KIT_DIR/VERSION" | tr -d '\r ' > "$DEST_DIR/coordination/.kit-version"
  echo "✅ мітка версії: coordination/.kit-version ($(cat "$DEST_DIR/coordination/.kit-version"))"
elif git -C "$KIT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$KIT_DIR" rev-parse HEAD > "$DEST_DIR/coordination/.kit-version"
  echo "✅ мітка версії: coordination/.kit-version"
else
  echo "•  мітку версії не ставлю: комплект не є git-клоном"
  echo "   (завантажений архівом — оновлюватись доведеться вручну)"
fi

echo
echo "Готово: створено $created, пропущено (вже існували) $skipped, канон уже на місці $redirected."
echo
echo "Наступні кроки:"
echo "  1. Заповни coordination/SETUP.md — три декларації (visibility/mode/constitution)."
echo "  2. Відкрий CLAUDE.md і заповни місця <...> — назву проєкту, ризикові"
echo "     зони, команду перевірки перед PR, команду деплою."
echo "  3. Заповни PROJECT_MAP.md тим, що в проєкті ВЖЕ є (це насіння анти-кіл),"
echo "     і DECISIONS.md — 3-5 уже прийнятими рішеннями з поясненням «чому»."
echo "  4. git add -A && git commit -m \"chore: структура пам'яті проєкту\" && git push"
echo "  5. bash $(cd "$SRC_DIR/.." && pwd)/scripts/self-check.sh — покаже, що лишилось."
echo
echo "Раз на місяць перевіряй свіжість комплекту:"
echo "  bash $(cd "$SRC_DIR/.." && pwd)/scripts/update-kit.sh --check"
echo
echo "Перевірка, що все працює: відкрий новий чат промптом із prompts/worker.md"
echo "і дай задачу, яка в проєкті вже частково зроблена. Перший рядок відповіді"
echo "має бути вердиктом звірки, а не початком роботи."
