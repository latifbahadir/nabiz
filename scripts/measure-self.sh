#!/bin/bash
# Çalışan Nabız'ın kendi CPU tüketimini ölçer (panel kapalıyken çalıştırın).
# Kullanım: ./scripts/measure-self.sh [saniye=60] [bütçe_yüzde=0.3]
# Bütçe tek çekirdeğe göredir (Activity Monitor'deki % CPU gibi).
set -euo pipefail

DURATION="${1:-60}"
BUDGET="${2:-0.3}"

PID="$(pgrep -x Nabiz || true)"
if [[ -z "$PID" ]]; then
  echo "Nabız çalışmıyor. Önce: open \"build/Nabız.app\"" >&2
  exit 2
fi

# ps cputime biçimi: [[gg-]ss:]dd:ss.cc → saniye
to_seconds() {
  echo "$1" | awk -F'[:-]' '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'
}

start="$(to_seconds "$(ps -o cputime= -p "$PID" | tr -d ' ')")"
sleep "$DURATION"
end="$(to_seconds "$(ps -o cputime= -p "$PID" | tr -d ' ')")"
rss_kb="$(ps -o rss= -p "$PID" | tr -d ' ')"

percent="$(awk -v a="$start" -v b="$end" -v d="$DURATION" 'BEGIN { printf "%.3f", (b - a) / d * 100 }')"
echo "Süre: ${DURATION} sn · CPU: %${percent} (tek çekirdek) · RSS (paylaşılan sistem çerçeveleri dahil): $((rss_kb / 1024)) MB · Bütçe: %${BUDGET}"

if awk -v p="$percent" -v b="$BUDGET" 'BEGIN { exit !(p > b) }'; then
  echo "BÜTÇE AŞILDI" >&2
  exit 1
fi
echo "Bütçe içinde ✓"
