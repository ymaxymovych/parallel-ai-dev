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

if [ ! -d "$DEST_DIR/.git" ]; then
  echo "❌ Поточна тека не є git-репозиторієм." >&2
  echo "   Пам'ять, якої нема в git, не існує — спершу: git init && git commit" >&2
  exit 1
fi

created=0
skipped=0

copy_one() {
  local rel="$1"
  local src="$SRC_DIR/$rel"
  local dst="$DEST_DIR/$rel"

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
copy_one "coordination/WORKSTREAMS.md"
copy_one "coordination/DECISIONS.md"
copy_one "coordination/BACKLOG.md"
copy_one "coordination/MISTAKES.md"
copy_one "coordination/PROJECT_MAP.md"
copy_one "coordination/inbox/README.md"
copy_one "coordination/log/README.md"

echo
echo "Готово: створено $created, пропущено (вже існували) $skipped."
echo
echo "Наступні кроки:"
echo "  1. Відкрий CLAUDE.md і заповни місця <...> — назву проєкту, ризикові"
echo "     зони, команду перевірки перед PR, команду деплою."
echo "  2. Заповни PROJECT_MAP.md тим, що в проєкті ВЖЕ є (це насіння анти-кіл),"
echo "     і DECISIONS.md — 3-5 уже прийнятими рішеннями з поясненням «чому»."
echo "  3. git add -A && git commit -m \"chore: структура пам'яті проєкту\" && git push"
echo
echo "Перевірка, що все працює: відкрий новий чат промптом із prompts/worker.md"
echo "і дай задачу, яка в проєкті вже частково зроблена. Перший рядок відповіді"
echo "має бути вердиктом звірки, а не початком роботи."
