#!/usr/bin/env bash
# check-publication-risk.sh — «чи безпечно цьому репозиторію бути публічним?»
#
# Запускати з кореня свого репозиторію:
#     bash <шлях>/parallel-ai-dev/scripts/check-publication-risk.sh
#
# Робоча пам'ять (рішення, помилки, карта проєкту) — найвідвертіші файли в репо:
# саме в них осідають адреси серверів, імена клієнтів і «тимчасово вставлений»
# токен. Скрипт сканує пам'ять на такі сліди ПЕРЕД тим, як вони стануть
# публічними назавжди (видалене лишається в історії git).
#
# Скрипт нічого не змінює. Знахідки друкуються як «файл:рядок + категорія» —
# БЕЗ самого значення: якщо це справді секрет, друкувати його в термінал
# (і в логи CI) — це ще одна копія секрету.
#
# Код виходу: 0 — слідів не знайдено АБО репо задекларований private;
#             1 — є знахідки при public-accepted (або декларації немає).

set -uo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "🔴 Це не git-репозиторій — нічого сканувати." >&2
  exit 1
fi
cd "$(git rev-parse --show-toplevel)" || exit 1

SETUP=coordination/SETUP.md
VISIBILITY=""
if [ -f "$SETUP" ]; then
  VISIBILITY=$(sed -n 's/^[[:space:]]*visibility:[[:space:]]*//p' "$SETUP" \
    | head -1 | awk '{print $1}' | tr -d '\r')
fi

# Що скануємо: файли пам'яті (типові місця + перевизначені конфігом шляхи,
# якщо вони всередині репо) і конституції.
CONF=coordination/.selfcheck.conf
SCAN="CLAUDE.md CLAUDE.parallel-ai-dev.md coordination"
if [ -f "$CONF" ]; then
  EXTRA=$(sed -n 's/^[[:space:]]*[A-Z_]*[[:space:]]*=[[:space:]]*//p' "$CONF" | tr -d '"' | tr -d '\r' \
    | grep -v '^/' | grep -v '^\.\./' | grep '\.md$' || true)
  SCAN="$SCAN $EXTRA"
fi

# Категорії ризику. Патерни свідомо грубі: краще три хибні тривоги, які людина
# зніме очима за хвилину, ніж один токен, що поїхав у публічну історію назавжди.
FOUND=0
report() { # $1 назва категорії, $2 ERE-патерн
  local hits
  # shellcheck disable=SC2086
  hits=$(grep -rnE -l "$2" $SCAN 2>/dev/null | grep -v '^\.git/' || true)
  [ -z "$hits" ] && return 0
  local f
  for f in $hits; do
    # Друкуємо файл і номери рядків — НЕ вміст (див. шапку).
    # shellcheck disable=SC2086
    lines=$(grep -nE "$2" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
    echo "  🔴 $1: $f (рядки: $lines)"
    FOUND=$((FOUND+1))
  done
}

echo
echo "Сканування пам'яті проєкту на сліди, що не мають ставати публічними…"
echo

report "схоже на токен/ключ API"      '(api[_-]?key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_/+-]{12,}'
report "ключі відомих сервісів"       '(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[bap]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})'
report "приватний ключ"               'BEGIN (RSA|EC|OPENSSH|PGP) PRIVATE KEY'
report "адреса сервера (IPv4)"        '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'
report "рядок підключення до БД"      '(postgres|postgresql|mysql|mongodb(\+srv)?|redis)://[^[:space:]]+'
report "email (крім прикладів)"       '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
report "ssh до користувача@хоста"     'ssh[[:space:]]+[A-Za-z0-9_-]+@[A-Za-z0-9.-]+'

echo
# Декларація видимості перевіряється НЕЗАЛЕЖНО від результату скану: чистий скан
# без декларації раніше виходив нулем — і студент так і не заповнював SETUP.md
# (AC-27, зловлено рев'ю 2.0.1).
case "$VISIBILITY" in private|public-accepted) : ;; *)
  echo "❌ У coordination/SETUP.md не задекларовано visibility — заповни його"
  echo "   (private або public-accepted) і перезапусти."
  exit 1 ;;
esac

if [ "$FOUND" -eq 0 ]; then
  echo "✅ Слідів не знайдено."
  case "$VISIBILITY" in
    private)
      echo "   Нагадування: декларація private застаріває в мить зміни видимості — перед публікацією прожени скан ще раз." ;;
    public-accepted)
      echo "   Пам'ять цього репозиторію ВЖЕ публічна — і назавжди: git-історія пам'ятає навіть видалене." ;;
  esac
  exit 0
fi

echo "Знахідок: $FOUND. Що робити з кожною:"
echo "  • справжній секрет → прибери з файлу І вважай його скомпрометованим"
echo "    (ротуй ключ): git-історія пам'ятає видалене."
echo "  • службова адреса/пошта → винеси в приватний файл поза репо або"
echo "    заміни на нейтральний опис («прод-сервер», «пошта власника»)."
echo "  • хибна тривога (приклад у документації) → лишай, це нормально."
echo
case "$VISIBILITY" in
  private)
    echo "Репозиторій задекларовано private — публікації немає, це попередження."
    echo "Але перед зміною видимості на публічну цей скан мусить стати чистим."
    exit 0 ;;
  public-accepted)
    echo "❌ Репозиторій задекларовано ПУБЛІЧНИМ — ці сліди вже публічні і назавжди."
    echo "   Розберись зі знахідками зараз (ротуй справжні секрети!)."
    exit 1 ;;
esac
