#!/bin/bash
# New Test Variations for RTT-lite NNG Benchmark
# Includes:
#   - Block A: Asymmetric Network / Slow-Peer Isolation
#   - Block B: Transient Dynamic Congestion
#   - Block C: Burst Traffic / Variable Rate Stress Test
#
# Usage: ./run-new-test-variations.sh
# Env overrides: BLOCKS, OUTDIR, PORT, PUB_TIMEOUT
set -u
cd "$(dirname "$0")"

PORT=${PORT:-5555}
OUTDIR=${OUTDIR:-../hasil-new-variations}
mkdir -p "$OUTDIR"

PUB_TIMEOUT=${PUB_TIMEOUT:-900}
BLOCKS=${BLOCKS:-A,B,C}

want() { case ",$BLOCKS," in *",$1,"*) return 0;; *) return 1;; esac; }

# Checking required binaries
for b in bml-pub-sub-std bml-pub-sub-survey; do
  [ -x "$b" ] || { echo "MISSING binary: $b (build std + survey first!)"; exit 1; }
done

cleanup_netem() {
  sudo tc qdisc del dev lo root 2>/dev/null || true
  sudo ip netns del slowsan 2>/dev/null || true
  sudo ip link del dev veth-fast 2>/dev/null || true
}
trap cleanup_netem EXIT

echo "=== STARTING NEW TEST VARIATIONS Benchmark ==="

# ==============================================================================
# BLOCK A: Asymmetric Network / Slow-Peer Isolation
# ==============================================================================
# Testing Per-Pipe Estimator: Sub 1 is Fast (loopback), Sub 2 is Slow
# (network namespace + veth with netem 50ms). Survey runs twice:
#   asym-q1-survey : NNG_SURVEY_QUORUM=1 (pace-to-fastest, s1 must stay fast)
#   asym-q2-survey : NNG_SURVEY_QUORUM=2 (wait-for-all, s1 gets dragged = HOL)
#
# VALIDITY FIX: the slow peer MUST live in a netns. Dialing a local IP
# from the same host is routed via loopback and never hits the veth
# qdisc, which silently voided the first version of this block
# (no ~50ms latency visible anywhere in the old asym-*.json files).
if want A; then
  echo ""
  echo "======================================================================"
  echo "--- BLOCK A: Asymmetric / Slow-Peer Isolation (Fast vs Slow Peer) ---"
  echo "======================================================================"

  # Drop stale same-host asym files (superseded by asym-q1-* below).
  rm -f "$OUTDIR"/asym-survey-r* 2>/dev/null || true

  NS=slowsan
  VHOST=10.200.1.1
  VNS=10.200.1.2
  cleanup_netem
  sudo ip link add dev veth-fast type veth peer name veth-slow
  sudo ip addr add $VHOST/24 dev veth-fast
  sudo ip link set dev veth-fast up
  sudo ip netns add $NS
  sudo ip link set dev veth-slow netns $NS
  sudo ip netns exec $NS ip addr add $VNS/24 dev veth-slow
  sudo ip netns exec $NS ip link set dev lo up
  sudo ip netns exec $NS ip link set dev veth-slow up

  # Apply 50ms delay on the namespace side (egress of the slow peer).
  sudo ip netns exec $NS tc qdisc add dev veth-slow root netem delay 50ms
  echo "### netns slow peer ready (ping check):"
  ping -c1 -W1 $VNS >/dev/null 2>&1 && echo "### veth ping OK" || echo "### veth ping FAILED, investigate!"

  cnt=1000
  dp=1000

  run_asym() { # $1=tag $2=lib $3=quorum-or-empty
    local tag=$1 lib=$2 q=$3 r
    rm -f data/s*.json
    echo "### Running $tag (lib=$lib cnt=$cnt dp=$dp quorum=${q:-n/a})"

    # Sub 1 (Fast Node via Loopback, host network).
    ./bml-pub-sub-$lib nng --sub --sub_ids "s1" --count "$cnt" \
      --endpoint "tcp://127.0.0.1:$PORT" > "$OUTDIR/$tag-s1.log" 2>&1 &
    pid1=$!

    # Sub 2 (Slow Node inside netns, via veth IP; netem applies here).
    sudo ip netns exec $NS ./bml-pub-sub-$lib nng --sub --sub_ids "s2" --count "$cnt" \
      --endpoint "tcp://$VHOST:$PORT" > "$OUTDIR/$tag-s2.log" 2>&1 &
    pid2=$!

    sleep 0.5

    if [ -n "$q" ]; then export NNG_SURVEY_QUORUM=$q; fi
    timeout "$PUB_TIMEOUT" ./bml-pub-sub-$lib nng --pub --count "$cnt" --rate 0 \
      --dp-len "$dp" --delay 1000 \
      --endpoint "tcp://0.0.0.0:$PORT" > "$OUTDIR/$tag-pub.log" 2>&1

    echo "pub exit=$? (124 = PUB_TIMEOUT)"
    unset NNG_SURVEY_QUORUM
    wait $pid1 $pid2 2>/dev/null

    [ -f "data/s1.json" ] && cp "data/s1.json" "$OUTDIR/$tag-s1.json"
    [ -f "data/s2.json" ] && cp "data/s2.json" "$OUTDIR/$tag-s2.json"
  }

  for r in 1 2 3; do
    run_asym "asym-std-r$r" std ""
  done
  for r in 1 2 3; do
    run_asym "asym-q1-survey-r$r" survey 1
  done
  for r in 1 2 3; do
    run_asym "asym-q2-survey-r$r" survey 2
  done
  cleanup_netem
fi

# ==============================================================================
# BLOCK B: Transient Dynamic Congestion
# ==============================================================================
# Inject netem (delay 50ms loss 1%) dynamically in the middle of transmission.
#
# VALIDITY FIX: the old version blasted 2000 msgs at --rate 0, finishing in
# ~0.2s, while the injection only started at t=2s. The impairment never
# touched the traffic (old transient-*.json are plain ideal runs). This
# version paces the publisher at --rate 5000 (5ms), stretching the run
# past 10s, and injects from t=3s to t=8s, well inside the run.
if want B; then
  echo ""
  echo "======================================================================"
  echo "--- BLOCK B: Transient Dynamic Congestion (Netem Injected Mid-Run) ---"
  echo "======================================================================"

  cleanup_netem
  for lib in std survey; do
    for r in 1 2 3; do
      tag="transient-${lib}-r$r"
      cnt=2000
      dp=1000
      rate=5000
      rm -f data/s*.json
      echo "### Running $tag (lib=$lib cnt=$cnt dp=$dp rate=$rate)"

      # Subscriber
      ./bml-pub-sub-$lib nng --sub --sub_ids "s1" --count "$cnt" \
        --endpoint "tcp://127.0.0.1:$PORT" > "$OUTDIR/$tag-s1.log" 2>&1 &
      sub_pid=$!

      sleep 0.5
      [ "$lib" = survey ] && export NNG_SURVEY_QUORUM=1

      # Start Publisher in background (paced: run lasts ~10s+, see above).
      timeout "$PUB_TIMEOUT" ./bml-pub-sub-$lib nng --pub --count "$cnt" --rate "$rate" \
        --dp-len "$dp" --delay 1000 \
        --endpoint "tcp://:$PORT" > "$OUTDIR/$tag-pub.log" 2>&1 &
      pub_pid=$!

      # Dynamic Netem Injection: wait 3s (run in progress), inject for 5s.
      sleep 3
      echo "  [NETEM INJECTED: 50ms delay, 1% loss]"
      sudo tc qdisc add dev lo root netem delay 50ms loss 1% 2>/dev/null || true
      sleep 5
      echo "  [NETEM REMOVED: back to normal]"
      sudo tc qdisc del dev lo root 2>/dev/null || true

      unset NNG_SURVEY_QUORUM
      wait $pub_pid 2>/dev/null
      echo "pub finished"
      wait $sub_pid 2>/dev/null

      [ -f "data/s1.json" ] && cp "data/s1.json" "$OUTDIR/$tag-s1.json"
    done
  done
  cleanup_netem
fi

# ==============================================================================
# BLOCK C: Burst Traffic / Variable Rate Stress Test
# ==============================================================================
# Simulates IoT sensor burst traffic using interval rate delays (--rate 200000 = 200ms burst gap)
if want C; then
  echo ""
  echo "======================================================================"
  echo "--- BLOCK C: Burst Traffic / Variable Rate Stress Test ---"
  echo "======================================================================"

  cleanup_netem
  # Apply steady netem baseline delay 10ms
  sudo tc qdisc add dev lo root netem delay 10ms

  for rate in 50000 200000; do # 50ms and 200ms burst interval delays
    for lib in std survey; do
      for r in 1 2 3; do
        tag="burst-r${rate}-${lib}-r$r"
        cnt=1000
        dp=4096 # 4KB payload for burst test
        rm -f data/s*.json
        echo "### Running $tag (lib=$lib cnt=$cnt rate=$rate dp=$dp)"

        ./bml-pub-sub-$lib nng --sub --sub_ids "s1" --count "$cnt" \
          --endpoint "tcp://127.0.0.1:$PORT" > "$OUTDIR/$tag-s1.log" 2>&1 &
        sub_pid=$!

        sleep 0.5
        [ "$lib" = survey ] && export NNG_SURVEY_QUORUM=1

        timeout "$PUB_TIMEOUT" ./bml-pub-sub-$lib nng --pub --count "$cnt" --rate "$rate" \
          --dp-len "$dp" --delay 1000 \
          --endpoint "tcp://:$PORT" > "$OUTDIR/$tag-pub.log" 2>&1

        echo "pub exit=$?"
        unset NNG_SURVEY_QUORUM
        wait $sub_pid 2>/dev/null

        [ -f "data/s1.json" ] && cp "data/s1.json" "$OUTDIR/$tag-s1.json"
      done
    done
  done
  cleanup_netem
fi

echo ""
echo "=== ALL NEW VARIATIONS COMPLETED -> Results saved in $OUTDIR ==="
