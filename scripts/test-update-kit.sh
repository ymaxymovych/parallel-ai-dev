#!/usr/bin/env bash
# test-update-kit.sh — пісочниця для ланки 2 `update-kit.sh`.
#
#   bash scripts/test-update-kit.sh
#
# ЩО ПЕРЕВІРЯЄМО. Повідомлення про відсталу інсталяцію мусить розкладати
# змінені шаблони на дві групи з РІЗНИМИ порадами: файли комплекту (kit-owned —
# їх пишемо ми, оновлюються копіюванням) і файли користувача (він їх заповнив
# сам — переносить руками). Порожня група не друкується взагалі.
#
# ЯК. Піднімаємо в системному tmp одноразовий «комплект» (git-репо з origin,
# щоб ланка 1 мала куди сходити fetch-ем) і поруч «проєкт» із міткою старої
# версії. Далі ганяємо справжній update-kit.sh і читаємо його вивід.
# Нічого поза створеною tmp-текою не чіпається.

set -uo pipefail

KIT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNDER_TEST="$KIT_SRC/scripts/update-kit.sh"

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/pad-update-kit-XXXXXX")"
cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

pass=0
fail=0

ok()   { pass=$((pass + 1)); printf '  ✅ %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  ❌ %s\n' "$1"; }

check_has()  { case "$OUT" in *"$2"*) ok "$1" ;; *) bad "$1 — не знайшов у виводі: $2" ;; esac; }
check_lacks(){ case "$OUT" in *"$2"*) bad "$1 — зайве у виводі: $2" ;; *) ok "$1" ;; esac; }

git_q() { git -c user.name=test -c user.email=test@test -c commit.gpgsign=false "$@" >/dev/null 2>&1; }

KIT_FILE="template/CLAUDE.parallel-ai-dev.md"
USER_FILE="template/coordination/DECISIONS.md"

# Будує окрему пісочницю: комплект на версії 2.0.1, інсталяція — з 2.0.0.
# Аргументи — які шаблони змінились між цими версіями.
# Друкує шлях до теки «проєкту»; сам комплект — поруч, у ../kit.
build_case() {
  local name="$1"; shift
  local root="$TMPROOT/$name"
  local kit="$root/kit" proj="$root/project" f

  mkdir -p "$kit/template/coordination" "$kit/scripts" "$proj/coordination"

  # Скрипт рахує KIT_DIR від власного розташування — тому тестуємо КОПІЮ
  # всередині пісочниці, інакше ланка 1 піде на справжній GitHub.
  cp "$UNDER_TEST" "$kit/scripts/update-kit.sh"

  printf 'правила комплекту, версія 1\n' > "$kit/$KIT_FILE"
  printf 'твоя конституція\n'            > "$kit/template/CLAUDE.md"
  printf 'рішення проєкту\n'             > "$kit/$USER_FILE"
  printf '2.0.0\n'                       > "$kit/VERSION"

  git_q init "$kit"
  git_q -C "$kit" add -A
  git_q -C "$kit" commit -m "v2.0.0"
  git_q -C "$kit" tag v2.0.0

  # origin поруч — щоб `git fetch origin <branch>` у ланці 1 не ходив у мережу
  git_q init --bare "$root/origin.git"
  git_q -C "$kit" remote add origin "$root/origin.git"
  git_q -C "$kit" push -u origin HEAD

  for f in "$@"; do
    printf 'ЗМІНЕНО у 2.0.1\n' >> "$kit/$f"
  done
  printf '2.0.1\n' > "$kit/VERSION"
  git_q -C "$kit" add -A
  git_q -C "$kit" commit -m "v2.0.1"
  git_q -C "$kit" tag v2.0.1
  git_q -C "$kit" push origin HEAD

  printf '2.0.0\n' > "$proj/coordination/.kit-version"
  printf '%s\n' "$proj"
}

# Ганяє пісочничну копію update-kit.sh у теці проєкту; наповнює $OUT і $RC.
run_case() {
  local proj="$1"
  local kit="$(dirname "$proj")/kit"
  OUT="$(cd "$proj" && bash "$kit/scripts/update-kit.sh" --check 2>&1)"
  RC=$?
}

HDR_KIT="ФАЙЛИ КОМПЛЕКТУ"
HDR_USER="ТВОЇ ФАЙЛИ"

# ── T1. Змінився ЛИШЕ kit-owned файл ─────────────────────────────────────
echo "T1: змінився лише файл комплекту"
PROJ="$(build_case only-kit "$KIT_FILE")"
run_case "$PROJ"
check_has   "друкує групу файлів комплекту"        "$HDR_KIT"
check_lacks "не друкує порожню групу файлів юзера" "$HDR_USER"
check_lacks "не називає наш файл заповненим тобою" "вони заповнені тобою"
[ "$RC" = 3 ] && ok "код виходу 3" || bad "код виходу $RC замість 3"

# ── T2. Готова команда копіювання з РЕАЛЬНИМИ шляхами ────────────────────
echo "T2: команда оновлення kit-owned файлу"
check_has "дає cp зі шляху комплекту" "cp \"$(dirname "$PROJ")/kit/$KIT_FILE\""
check_has "…у корінь проєкту"         "$PROJ/CLAUDE.parallel-ai-dev.md\""
check_has "попереджає, що cp затре свідомі правки" "затре"
check_has "радить спершу глянути діф"              "diff"

# ── T3. Змінився ЛИШЕ user-owned файл ────────────────────────────────────
echo "T3: змінився лише файл користувача"
PROJ="$(build_case only-user "$USER_FILE")"
run_case "$PROJ"
check_has   "друкує групу твоїх файлів"             "$HDR_USER"
check_lacks "не друкує порожню групу комплекту"     "$HDR_KIT"
check_lacks "не пропонує копіювати чужі файли"      "         cp \""
check_has   "називає сам файл"                      "DECISIONS.md"
[ "$RC" = 3 ] && ok "код виходу 3" || bad "код виходу $RC замість 3"

# ── T4. Змінилось і те, і те — обидві групи ──────────────────────────────
echo "T4: змінились обидва класи файлів"
PROJ="$(build_case both "$KIT_FILE" "$USER_FILE")"
run_case "$PROJ"
check_has "друкує групу комплекту"     "$HDR_KIT"
check_has "друкує групу твоїх файлів"  "$HDR_USER"
check_has "kit-owned у своїй групі"    "• CLAUDE.parallel-ai-dev.md"
check_has "user-owned у своїй групі"   "• coordination/DECISIONS.md"
[ "$RC" = 3 ] && ok "код виходу 3" || bad "код виходу $RC замість 3"

# ── T5. Шаблони не мінялись — жодних груп ────────────────────────────────
echo "T5: шаблони не змінювались (міняли лише VERSION)"
PROJ="$(build_case untouched)"
run_case "$PROJ"
check_has   "каже, що переносити нічого" "переносити нічого"
check_lacks "жодної групи комплекту"     "$HDR_KIT"
check_lacks "жодної групи твоїх файлів"  "$HDR_USER"
[ "$RC" = 0 ] && ok "код виходу 0" || bad "код виходу $RC замість 0"

# ── T6. Мітка збігається з версією — зелено, груп немає ──────────────────
echo "T6: інсталяція на поточній версії"
PROJ="$(build_case current "$KIT_FILE")"
printf '2.0.1\n' > "$PROJ/coordination/.kit-version"
run_case "$PROJ"
check_has   "зелений вердикт"        "усе свіже"
check_lacks "жодної групи комплекту" "$HDR_KIT"
[ "$RC" = 0 ] && ok "код виходу 0" || bad "код виходу $RC замість 0"

echo
printf 'Пройдено %s з %s\n' "$pass" "$((pass + fail))"
[ "$fail" -eq 0 ] || exit 1
echo "✅ update-kit.sh: групи власників розкладаються правильно"
