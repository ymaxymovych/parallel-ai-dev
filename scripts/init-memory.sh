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

copy_one "CLAUDE.md"
copy_one "coordination/WORKSTREAMS.md" WORKSTREAMS
copy_one "coordination/DECISIONS.md"   DECISIONS
copy_one "coordination/BACKLOG.md"     BACKLOG
copy_one "coordination/MISTAKES.md"    MISTAKES
copy_one "coordination/PROJECT_MAP.md" PROJECT_MAP
copy_one "coordination/inbox/README.md"
copy_one "coordination/log/README.md"

# Мітка версії: з якого коміту комплекту зроблено цю інсталяцію. Без неї
# update-kit.sh не може сказати, які шаблони змінились ПІСЛЯ твого встановлення,
# і чесно відповідає «не знаю» замість «все свіже».
KIT_DIR="$(cd "$SRC_DIR/.." && pwd)"
if git -C "$KIT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mkdir -p "$DEST_DIR/coordination"
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
echo "  1. Відкрий CLAUDE.md і заповни місця <...> — назву проєкту, ризикові"
echo "     зони, команду перевірки перед PR, команду деплою."
echo "  2. Заповни PROJECT_MAP.md тим, що в проєкті ВЖЕ є (це насіння анти-кіл),"
echo "     і DECISIONS.md — 3-5 уже прийнятими рішеннями з поясненням «чому»."
echo "  3. git add -A && git commit -m \"chore: структура пам'яті проєкту\" && git push"
echo
echo "Раз на місяць перевіряй свіжість комплекту:"
echo "  bash $(cd "$SRC_DIR/.." && pwd)/scripts/update-kit.sh --check"
echo
echo "Перевірка, що все працює: відкрий новий чат промптом із prompts/worker.md"
echo "і дай задачу, яка в проєкті вже частково зроблена. Перший рядок відповіді"
echo "має бути вердиктом звірки, а не початком роботи."
