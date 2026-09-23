#!/bin/bash
# Multi-subscriber test matrix: ipc (inproc threads) + tcp-loopback (+tc).
# Subs: 2/4/8 | sizes: 1000/4000/16000 | runs: 3 | libs: std + survey.
#
# Usage: ./run-multi-test.sh            (full matrix)
# Env overrides: COUNT_IDEAL / COUNT_D10 / COUNT_D50, PUB_TIMEOUT,
#                PORT, OUTDIR
set -u
cd "$(dirname "$0")"

PORT=${PORT:-5555}
OUTDIR=${OUTDIR:-../hasil-multi}
mkdir -p "$OUTDIR"

COUNT_IDEAL=${COUNT_IDEAL:-5000}
COUNT_D10=${COUNT_D10:-1000}
COUNT_D50=${COUNT_D50:-500}
# Big payloads (>=16KB) cost far more per message under netem
# (multi-packet x N replies x delay), so they get smaller counts.
COUNT_D10_BIG=${COUNT_D10_BIG:-500}
COUNT_D50_BIG=${COUNT_D50_BIG:-100}
PUB_TIMEOUT=${PUB_TIMEOUT:-900}
# Comma-separated subset of blocks to run, e.g. BLOCKS=D or BLOCKS=B,C
BLOCKS=${BLOCKS:-A,B,C,D}
want() { case ",$BLOCKS," in *",$1,"*) return 0;; *) return 1;; esac; }

for b in bml-pub-sub-std bml-pub-sub-survey; do
  [ -x "$b" ] || { echo "MISSING binary: $b (build std + survey first!)"; exit 1; }
done

run_ipc() { # $1=lib $2=nsubs $3=dp $4=count $5=tag
  local lib=$1 n=$2 dp=$3 cnt=$4 tag=$5 i
  rm -f data/s*.json
  local subs="" ids=""
  for i in $(seq 1 "$n"); do subs="$subs --sub"; ids="$ids s$i"; done
  echo "### IPC $tag (lib=$lib n=$n dp=$dp cnt=$cnt)"
  # shellcheck disable=SC2086
  [ "$lib" = survey ] && export NNG_SURVEY_QUORUM=$n
  timeout "$PUB_TIMEOUT" ./bml-pub-sub-$lib nng $subs \
    --sub_ids $ids --pub --count "$cnt" --rate 0 --dp-len "$dp" --delay 1000 \
    --endpoint "inproc://mp-$n" > "$OUTDIR/$tag.log" 2>&1
  echo "exit=$? (124 = hit PUB_TIMEOUT, investigate!)"
  unset NNG_SURVEY_QUORUM
  for i in $(seq 1 "$n"); do
    [ -f "data/s$i.json" ] && cp "data/s$i.json" "$OUTDIR/$tag-s$i.json"
  done
}

run_tcp() { # $1=lib $2=nsubs $3=dp $4=count $5=tag
  local lib=$1 n=$2 dp=$3 cnt=$4 tag=$5 i pids=""
  rm -f data/s*.json
  echo "### TCP $tag (lib=$lib n=$n dp=$dp cnt=$cnt)"
  for i in $(seq 1 "$n"); do
    ./bml-pub-sub-$lib nng --sub --sub_ids "s$i" --count "$cnt" \
      --endpoint "tcp://127.0.0.1:$PORT" > "$OUTDIR/$tag-s$i.log" 2>&1 &
    pids="$pids $!"
  done
  sleep 0.5
  [ "$lib" = survey ] && export NNG_SURVEY_QUORUM=$n
  timeout "$PUB_TIMEOUT" ./bml-pub-sub-$lib nng --pub --count "$cnt" --rate 0 \
    --dp-len "$dp" --delay 1000 \
    --endpoint "tcp://:$PORT" > "$OUTDIR/$tag-pub.log" 2>&1
  echo "pub exit=$? (124 = hit PUB_TIMEOUT, investigate!)"
  unset NNG_SURVEY_QUORUM
  # shellcheck disable=SC2086
  wait $pids 2>/dev/null
  for i in $(seq 1 "$n"); do
    [ -f "data/s$i.json" ] && cp "data/s$i.json" "$OUTDIR/$tag-s$i.json"
  done
}

# ---------------- A. IPC, no impairment ----------------
if want A; then
for dp in 1000 4000 16000; do
  for n in 2 4 8; do
    for lib in std survey; do
      for r in 1 2 3; do
        run_ipc "$lib" "$n" "$dp" "$COUNT_IDEAL" "${dp}-${lib}-ipc${n}sub-r$r"
      done
    done
  done
done
fi

# ---------------- B. TCP-lo, ideal ----------------
if want B; then
sudo tc qdisc del dev lo root 2>/dev/null
for dp in 1000 4000 16000; do
  for n in 2 4 8; do
    for lib in std survey; do
      for r in 1 2 3; do
        run_tcp "$lib" "$n" "$dp" "$COUNT_IDEAL" "${dp}-${lib}-lo${n}sub-r$r"
      done
    done
  done
done
fi

# ---------------- C. TCP-lo, delay 10ms ----------------
if want C; then
sudo tc qdisc del dev lo root 2>/dev/null
sudo tc qdisc add dev lo root netem delay 10ms
for dp in 1000 4000 16000; do
  cnt=$COUNT_D10; [ "$dp" -ge 16000 ] && cnt=$COUNT_D10_BIG
  for n in 2 4 8; do
    for lib in std survey; do
      for r in 1 2 3; do
        run_tcp "$lib" "$n" "$dp" "$cnt" "${dp}-${lib}-lod10-${n}sub-r$r"
      done
    done
  done
done
sudo tc qdisc del dev lo root
fi

# ---------------- D. TCP-lo, delay 50ms 10ms loss 2% ----------------
if want D; then
sudo tc qdisc del dev lo root 2>/dev/null
sudo tc qdisc add dev lo root netem delay 50ms 10ms loss 2%
for dp in 1000 4000 16000; do
  cnt=$COUNT_D50; [ "$dp" -ge 16000 ] && cnt=$COUNT_D50_BIG
  for n in 2 4 8; do
    for lib in std survey; do
      for r in 1 2 3; do
        run_tcp "$lib" "$n" "$dp" "$cnt" "${dp}-${lib}-lod50l2-${n}sub-r$r"
      done
    done
  done
done
sudo tc qdisc del dev lo root
fi

echo "ALL DONE -> results in $OUTDIR"
