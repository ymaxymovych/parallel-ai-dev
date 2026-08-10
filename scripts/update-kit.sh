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
# твого встановлення, щоб ти переніс зміни свідомо. Виняток у ПОРАДІ (не в
# поведінці): для kit-owned файлів — тих, що пишемо ми, а не ти, — ланка 2
# одразу дає готову команду копіювання. Записує її все одно людина.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(pwd)"
STAMP="$PROJECT_DIR/coordination/.kit-version"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

say() { printf '%s\n' "$*"; }
die() { local msg="$1"; local code="${2:-1}"; printf '%s\n' "$msg" >&2; exit "$code"; }

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
behind="$(git -C "$KIT_DIR" rev-list --count "HEAD..origin/$BRANCH")"
ahead="$(git -C "$KIT_DIR" rev-list --count "origin/$BRANCH..HEAD")"

if [ "$LOCAL" = "$REMOTE" ]; then
  say "1/2 ✅ Клон свіжий (гілка $BRANCH)."
elif [ "$behind" -eq 0 ]; then
  # ТІЛЬКИ ПОПЕРЕДУ: ти комітив у сам комплект, але з GitHub тобі не бракує
  # НІЧОГО. Це не застарілість, і червоніти тут не можна: перевірка, що кричить
  # на справному стані, вчить людину ігнорувати червоне.
  say "1/2 ✅ Клон свіжий; поверх нього $ahead твій(іх) власний(их) коміт(ів)."
  say "       З GitHub тобі нічого не бракує. Але майбутні оновлення тут уже"
  say "       не автоматичні — свої зміни зливатимеш сам."
elif [ "$ahead" -gt 0 ]; then
  # РОЗІЙШЛИСЯ: і своє є, і чужого бракує. `git pull --ff-only` такого не
  # полагодить, тому навіть не пробуємо — чесна відмова краща за падіння.
  say "1/2 ⚠️  Клон РОЗІЙШОВСЯ з GitHub: $behind чужий(их) коміт(ів) тобі бракує,"
  say "       ще $ahead твій(іх) немає на GitHub. Автооновлення не пройде."
  say "       Перенеси свої зміни кудись, тоді:"
  say "         git -C \"$KIT_DIR\" reset --hard origin/$BRANCH"
  rc=3
else
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

# З версії 2.0.0 мітка — це НОМЕР ВЕРСІЇ («2.0.0», людиночитний і той самий,
# що в тегу і README), а не хеш коміту. Старі інсталяції несуть хеш — обидва
# формати підтримуються: номер мапиться на коміт через тег vX.Y.Z.
KIT_VER=""
[ -f "$KIT_DIR/VERSION" ] && KIT_VER="$(head -1 "$KIT_DIR/VERSION" | tr -d '\r ')"

INSTALLED_COMMIT="$INSTALLED"
if printf '%s' "$INSTALLED" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  if [ "$INSTALLED" = "$KIT_VER" ]; then
    say "2/2 ✅ Інсталяція відповідає версії комплекту ($KIT_VER) — усе свіже."
    exit "$rc"
  fi
  INSTALLED_COMMIT="$(git -C "$KIT_DIR" rev-parse -q --verify "v$INSTALLED^{commit}" 2>/dev/null || true)"
fi

if [ "$INSTALLED" = "$LOCAL" ]; then
  say "2/2 ✅ Інсталяція відповідає клону — усе свіже."
  exit "$rc"
fi

if [ -z "$INSTALLED_COMMIT" ] || ! git -C "$KIT_DIR" cat-file -e "$INSTALLED_COMMIT^{commit}" 2>/dev/null; then
  say "2/2 ⚠️  Мітка версії ($INSTALLED) не знайдена в історії комплекту."
  say "       Звірся з шаблонами вручну і перепиши мітку в coordination/.kit-version."
  exit 3
fi

CHANGED="$(git -C "$KIT_DIR" diff --name-only "$INSTALLED_COMMIT" "$LOCAL" -- template/ || true)"

NEW_STAMP="${KIT_VER:-$LOCAL}"

if [ -z "$CHANGED" ]; then
  say "2/2 ✅ Шаблони не змінювались від твого встановлення — переносити нічого."
  if [ "$CHECK_ONLY" -eq 0 ]; then
    printf '%s\n' "$NEW_STAMP" > "$STAMP"
    say "       Мітку версії оновлено ($NEW_STAMP)."
  fi
  exit "$rc"
fi

# Змінені шаблони діляться НЕ порівну. Один спільний текст «твої файли я не
# чіпаю, вони заповнені тобою» брехав про kit-owned файли: їх пишемо МИ, вони
# не заповнюються користувачем, і оновлюються звичайним копіюванням. Людина
# читала «доведеться переносити руками» — і не оновлювала правила комплекту
# роками. Тому групи друкуються окремо, з різними порадами.
#
# Список kit-owned шаблонів — явний: щоб додати новий, допиши рядок.
KIT_OWNED_TEMPLATES="
template/CLAUDE.parallel-ai-dev.md
"

is_kit_owned() {
  local needle="$1" p
  for p in $KIT_OWNED_TEMPLATES; do
    [ "$p" = "$needle" ] && return 0
  done
  return 1
}

CHANGED_KIT=""
CHANGED_USER=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if is_kit_owned "$f"; then
    CHANGED_KIT="$CHANGED_KIT$f
"
  else
    CHANGED_USER="$CHANGED_USER$f
"
  fi
done <<EOF
$CHANGED
EOF

say "2/2 ⚠️  Інсталяція ВІДСТАЛА: у комплекті змінились шаблони, які ти вже"
say "       скопіював до себе."

if [ -n "$CHANGED_KIT" ]; then
  say ""
  say "       ── ФАЙЛИ КОМПЛЕКТУ (пишемо їх ми, не ти) ──"
  printf '%s' "$CHANGED_KIT" | sed 's|^template/|         • |'
  say "       Це наші правила, ти їх не заповнюєш — тому їх можна просто"
  say "       перезаписати новою версією:"
  printf '%s' "$CHANGED_KIT" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    say "         cp \"$KIT_DIR/$f\" \"$PROJECT_DIR/${f#template/}\""
  done
  say "       Але якщо ти СВІДОМО правив цей файл під себе — копіювання затре"
  say "       твої правки. Тоді спершу глянь, що саме змінилось:"
  printf '%s' "$CHANGED_KIT" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    say "         git -C \"$KIT_DIR\" diff $INSTALLED_COMMIT $LOCAL -- $f"
  done
fi

if [ -n "$CHANGED_USER" ]; then
  say ""
  say "       ── ТВОЇ ФАЙЛИ (заповнені тобою) ──"
  say "       Їх я НЕ чіпаю. Перенеси потрібне вручну і свідомо:"
  printf '%s' "$CHANGED_USER" | sed 's|^template/|         • |'
  say "       Подивитись самі зміни:"
  say "         git -C \"$KIT_DIR\" diff $INSTALLED_COMMIT $LOCAL -- $(printf '%s' "$CHANGED_USER" | tr '\n' ' ')"
fi

say ""
say "       Оновиш — постав мітку, щоб перевірка знову стала зеленою:"
say "         printf '%s\\n' \"$NEW_STAMP\" > \"$STAMP\""
exit 3
