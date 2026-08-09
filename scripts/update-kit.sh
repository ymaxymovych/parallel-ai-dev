#!/usr/bin/env bash
# update-kit.sh — «чи в мене свіжий комплект?» і оновлення.
#
#   bash /шлях/до/parallel-ai-dev/scripts/update-kit.sh --check   # лише перевірити
#   bash /шлях/до/parallel-ai-dev/scripts/update-kit.sh           # оновити клон і звірити
#
# ЧОМУ ПЕРЕВІРКА З ДВОХ ЛАНОК. Комплект ставиться КОПІЮВАННЯМ шаблонів у твій
# проєкт, тому «чи свіжа в мене версія» — це два різні питання:
#   1) чи свіжий сам клон комплекту (його оновлює git pull);
#   2) чи бачив ти зміни шаблонів, що прийшли в клон після твого встановлення.
# Перевірка, яка дивиться лише на друге, зелена НАЗАВЖДИ: старий клон вічно
# «відповідає» старій інсталяції, і людина роками сидить на торішній версії,
# впевнена, що все гаразд. Тому ланка 1 завжди ходить на GitHub, а якщо не
# достукалась — каже про це прямо і виходить помилкою, а не «все свіже».
#
# ЩО ЦЕЙ СКРИПТ НІКОЛИ НЕ РОБИТЬ: не перезаписує твої файли. Скопійовані
# шаблони ти заповнив своїм змістом — машина не знає, де твоє, а де наше.
# Тому ланка 2 не «оновлює», а НАЗИВАЄ файли, які змінилися в комплекті після
# твого встановлення, щоб ти переніс зміни свідомо.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(pwd)"
STAMP="$PROJECT_DIR/coordination/.kit-version"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

say() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit "${2:-1}"; }

# ── Ланка 1: GitHub → клон ───────────────────────────────────────────────

[ -d "$KIT_DIR/.git" ] || die "❌ Не можу перевірити свіжість: $KIT_DIR — не git-клон.
   Схоже, комплект завантажено архівом. Постав його клоном:
   git clone https://github.com/ymaxymovych/parallel-ai-dev.git ~/parallel-ai-dev" 2

BRANCH="$(git -C "$KIT_DIR" rev-parse --abbrev-ref HEAD)"

if ! git -C "$KIT_DIR" fetch --quiet origin "$BRANCH" 2>/dev/null; then
  die "❌ Не можу перевірити свіжість: не достукався до GitHub (немає мережі
   або репозиторій недоступний). Це НЕ означає «все свіже» — спробуй пізніше." 2
fi

LOCAL="$(git -C "$KIT_DIR" rev-parse HEAD)"
REMOTE="$(git -C "$KIT_DIR" rev-parse "origin/$BRANCH")"

rc=0
if [ "$LOCAL" = "$REMOTE" ]; then
  say "1/2 ✅ Клон свіжий (гілка $BRANCH)."
else
  behind="$(git -C "$KIT_DIR" rev-list --count "HEAD..origin/$BRANCH")"
  if [ "$CHECK_ONLY" -eq 1 ]; then
    say "1/2 ⚠️  Клон ВІДСТАВ від GitHub на $behind коміт(ів) — запусти оновлення."
    rc=3
  else
    say "1/2 ↻ Клон відстав на $behind коміт(ів) — підтягую…"
    git -C "$KIT_DIR" pull --ff-only --quiet origin "$BRANCH" \
      || die "❌ git pull не пройшов (найімовірніше, ти правив файли в самому
   комплекті). Розберись із конфліктом у $KIT_DIR і повтори.
   Скіли НЕ перевстановлено — краще стара робоча версія, ніж половина нової."
    LOCAL="$(git -C "$KIT_DIR" rev-parse HEAD)"
    say "1/2 ✅ Клон оновлено."
  fi
fi

# ── Ланка 2: клон → твоя інсталяція ──────────────────────────────────────

if [ ! -d "$PROJECT_DIR/coordination" ]; then
  say "2/2 —  Комплект у цій теці ще не розгорнуто."
  say "       Постав його: bash $KIT_DIR/scripts/init-memory.sh"
  exit "$rc"
fi

if [ ! -f "$STAMP" ]; then
  say "2/2 ⚠️  Не знаю, з якої версії комплекту ти ставився: немає"
  say "       coordination/.kit-version (інсталяція старша за цю перевірку)."
  say "       Звірся з нашими шаблонами вручну один раз, а потім постав мітку:"
  say "       git -C \"$KIT_DIR\" rev-parse HEAD > \"$STAMP\""
  exit 3
fi

INSTALLED="$(tr -d '[:space:]' < "$STAMP")"

if [ "$INSTALLED" = "$LOCAL" ]; then
  say "2/2 ✅ Інсталяція відповідає клону — усе свіже."
  exit "$rc"
fi

if ! git -C "$KIT_DIR" cat-file -e "$INSTALLED^{commit}" 2>/dev/null; then
  say "2/2 ⚠️  Мітка версії ($INSTALLED) не знайдена в історії комплекту."
  say "       Звірся з шаблонами вручну і перепиши мітку в coordination/.kit-version."
  exit 3
fi

CHANGED="$(git -C "$KIT_DIR" diff --name-only "$INSTALLED" "$LOCAL" -- template/ || true)"

if [ -z "$CHANGED" ]; then
  say "2/2 ✅ Шаблони не змінювались від твого встановлення — переносити нічого."
  if [ "$CHECK_ONLY" -eq 0 ]; then
    printf '%s\n' "$LOCAL" > "$STAMP"
    say "       Мітку версії оновлено."
  fi
  exit "$rc"
fi

say "2/2 ⚠️  Інсталяція ВІДСТАЛА: у комплекті змінились шаблони, які ти вже"
say "       скопіював до себе. Твої файли я НЕ чіпаю — вони заповнені тобою."
say ""
say "       Що змінилось (перенеси потрібне вручну):"
printf '%s\n' "$CHANGED" | sed 's|^template/|         • |'
say ""
say "       Подивитись самі зміни:"
say "         git -C \"$KIT_DIR\" diff $INSTALLED $LOCAL -- template/"
say ""
say "       Перенесеш — постав мітку, щоб перевірка знову стала зеленою:"
say "         printf '%s\\n' \"$LOCAL\" > \"$STAMP\""
exit 3
