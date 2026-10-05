"""Grafik artikel RTT-lite — JALANKAN DI COLAB (butuh matplotlib).

Cara pakai di Colab:
  1. Upload folder `hasil-multi/` dan `hasil-new-variations/` (atau mount Drive
     lalu sesuaikan path di bawah).
  2. Run sel ini. Output: 4 file PNG + tabel verifikasi angka untuk naskah.

Isi:
  - fig_loss_d10_perpayload.png  (pengganti fig5: loss per payload, std vs survey)
  - fig_burst_completion.png     (waktu selesai burst 50ms vs 200ms pacing)
  - fig_burst_rate.png           (laju efektif vs laju yang ditawarkan)
  - fig_wifi_hasil.png           (wifi fisik: kelengkapan + latensi md-std vs md-rtt)

Hanya butuh pustaka standar + matplotlib. Tidak ada dependensi lain.
"""

import argparse
import glob
import json
import os
import re
import statistics

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ----------------------------------------------------------------------------
# Muat data
# ----------------------------------------------------------------------------

PAT = re.compile(r"^(\d+)-(std|survey)-(.+)-r(\d+)(?:-s(\d+))?\.json$")


def parse_rest(rest):
    rest = rest.replace("-v2", "")
    m = re.match(r"^(ipc|lo|lod10|lod50l2)-?(\d+sub)$", rest)
    if m:
        return m.group(1), m.group(2)
    return rest, ""


def load(d):
    out = {}
    for f in glob.glob(os.path.join(d, "*.json")):
        m = PAT.match(os.path.basename(f))
        if not m:
            continue
        p, v, rest, r, s = m.groups()
        scen, ns = parse_rest(rest)
        out.setdefault((p, v, scen, ns), []).append(json.load(open(f)))
    return out


def load_simple(d, prefix):
    """Untuk muldev: md-{std,rtt}-{1,4,16}-r*.json (tanpa info sub)."""
    out = {}
    for f in glob.glob(os.path.join(d, prefix + "*.json")):
        m = re.match(r"^md-(std|rtt)-(\d+)-r\d+\.json$", os.path.basename(f))
        if m:
            out.setdefault((m.group(1), m.group(2)), []).append(json.load(open(f)))
    return out


def load_burst(d):
    out = {}
    for f in glob.glob(os.path.join(d, "burst-*.json")):
        m = re.match(r"^burst-r(\d+)-(std|survey)-r\d+-s\d+\.json$", os.path.basename(f))
        if m:
            out.setdefault((m.group(1), m.group(2)), []).append(json.load(open(f)))
    return out


def load_asym(d):
    """asym-{std,q1-survey,q2-survey}-rN-{s1,s2}.json (hasil rerun netns)."""
    out = {}
    for f in glob.glob(os.path.join(d, "asym-*.json")):
        m = re.match(r"^asym-(std|q1-survey|q2-survey)-r\d+-(s\d+)\.json$",
                     os.path.basename(f))
        if m:
            out.setdefault((m.group(1), m.group(2)), []).append(json.load(open(f)))
    return out


def load_transient(d):
    out = {}
    for f in glob.glob(os.path.join(d, "transient-*.json")):
        m = re.match(r"^transient-(std|survey)-r\d+-s\d+\.json$", os.path.basename(f))
        if m:
            out.setdefault(m.group(1), []).append(json.load(open(f)))
    return out


def mean(js, k):
    return statistics.mean(j[k] for j in js)


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--multi", default="hasil-multi")
    ap.add_argument("--new", default="hasil-new-variations")
    ap.add_argument("--out", default=".")
    a = ap.parse_args()

    M = load(a.multi)
    N = load(a.new)
    W = load_simple(os.path.join(a.multi, "muldev"), "md-")
    B = load_burst(a.new)
    A = load_asym(a.new)
    T = load_transient(a.new)

    # --- tabel verifikasi: baseline IPC 1KB ---
    print("== baseline IPC 1KB (untuk Tab. baseline) ==")
    for v in ["std", "survey"]:
        for n in ["2sub", "4sub", "8sub"]:
            js = M[("1000", v, "ipc", n)]
            print(
                f"{v} {n}: recv={mean(js, 'message_received'):.0f} "
                f"thr={mean(js, 'throughput'):.0f} "
                f"avg_us={mean(js, 'avg_latency') / 1e3:.1f} "
                f"p99_us={mean(js, 'p99_latency') / 1e3:.1f}"
            )

    # --- tabel verifikasi: d10 2sub ---
    print("== d10 2sub (untuk Tab. d10) ==")
    for p in ["1000", "4000", "16000"]:
        for v in ["std", "survey"]:
            js = M[(p, v, "lod10", "2sub")]
            print(
                f"{p} {v}: recv={mean(js, 'message_received'):.0f} "
                f"thr={mean(js, 'throughput'):.1f} "
                f"avg_ms={mean(js, 'avg_latency') / 1e6:.1f} "
                f"p99_ms={mean(js, 'p99_latency') / 1e6:.1f}"
            )

    # --- tabel verifikasi: wifi muldev ---
    print("== wifi muldev ==")
    for lib in ["std", "rtt"]:
        for p in ["1", "4", "16"]:
            js = W[(lib, p)]
            print(
                f"md-{lib}-{p}: recv={mean(js, 'message_received'):.0f} "
                f"thr={mean(js, 'throughput'):.0f} "
                f"avg_ms={mean(js, 'avg_latency') / 1e6:.1f} "
                f"p99_ms={mean(js, 'p99_latency') / 1e6:.1f}"
            )

    # --- tabel verifikasi: burst ---
    print("== burst (4 KB, d10, 1 sub) ==")
    for rate in ["50000", "200000"]:
        for v in ["std", "survey"]:
            js = B[(rate, v)]
            print(
                f"rate={rate} {v}: recv={mean(js, 'message_received'):.0f} "
                f"t={mean(js, 'time'):.1f}s thr={mean(js, 'throughput'):.1f} "
                f"avg_ms={mean(js, 'avg_latency') / 1e6:.1f}"
            )

    # --- tabel verifikasi: asym rerun (s1 cepat, s2 lambat 50ms) ---
    print("== asym rerun ==")
    for k in ["std", "q1-survey", "q2-survey"]:
        for s in ["s1", "s2"]:
            js = A[(k, s)]
            print(
                f"asym-{k} {s}: recv={mean(js, 'message_received'):.0f} "
                f"thr={mean(js, 'throughput'):.0f} "
                f"avg_ms={mean(js, 'avg_latency') / 1e6:.2f} "
                f"p99_ms={mean(js, 'p99_latency') / 1e6:.2f} "
                f"t={mean(js, 'time'):.2f}s"
            )

    # --- tabel verifikasi: transient rerun ---
    print("== transient rerun (2000 msgs, paced, inject @3-8s) ==")
    for v in ["std", "survey"]:
        js = T[v]
        print(
            f"transient-{v}: recv={mean(js, 'message_received'):.0f} "
            f"thr={mean(js, 'throughput'):.1f} "
            f"avg_ms={mean(js, 'avg_latency') / 1e6:.2f} "
            f"p99_ms={mean(js, 'p99_latency') / 1e6:.2f}"
        )

    # --- G1: loss d10 per payload, kedua lib (pengganti fig5) ---
    # Count mengikuti run-multi-test.sh: COUNT_D10=1000,
    # COUNT_D10_BIG=500 untuk dp>=16000. Jangan hardcode 1000.
    fig, ax = plt.subplots()
    pays = ["1000", "4000", "16000"]
    counts = {"1000": 1000, "4000": 1000, "16000": 500}
    xs = ["1 KB", "4 KB", "16 KB"]
    w = 0.35
    for i, v in enumerate(["std", "survey"]):
        loss = [
            (counts[p] - mean(M[(p, v, "lod10", "2sub")], "message_received"))
            / counts[p] * 100
            for p in pays
        ]
        ax.bar([x + i * w for x in range(3)], loss, width=w, label=v)
    ax.set_xticks([x + w / 2 for x in range(3)], xs)
    ax.set_ylabel("Message Loss (%)")
    ax.set_xlabel("Payload (delay 10 ms, 2 subscribers)")
    ax.set_title("Message Loss Rate per Payload (delay 10 ms)")
    ax.legend(title="lib")
    fig.tight_layout()
    fig.savefig(os.path.join(a.out, "fig_loss_d10_perpayload.png"), dpi=150)

    # --- G2: waktu selesai burst ---
    fig, ax = plt.subplots()
    labels, std_t, sur_t = [], [], []
    for rate in ["50000", "200000"]:
        labels.append("50 ms" if rate == "50000" else "200 ms")
        std_t.append(mean(B[(rate, "std")], "time"))
        sur_t.append(mean(B[(rate, "survey")], "time"))
    x = range(len(labels))
    ax.bar([i - 0.2 for i in x], std_t, width=0.4, label="std")
    ax.bar([i + 0.2 for i in x], sur_t, width=0.4, label="survey")
    ax.set_xticks(list(x), ["pacing " + lb for lb in labels])
    ax.set_ylabel("Completion Time (s, 1000 msgs)")
    ax.set_xlabel("Send Interval (4 KB, delay 10 ms, 1 subscriber)")
    ax.set_title("Burst Completion Time: steady pacing favors no-handshake")
    ax.legend(title="lib")
    for i in x:
        ax.text(i - 0.2, std_t[i] + 2, f"{std_t[i]:.0f}s", ha="center", fontsize=8)
        ax.text(i + 0.2, sur_t[i] + 2, f"{sur_t[i]:.0f}s", ha="center", fontsize=8)
    fig.tight_layout()
    fig.savefig(os.path.join(a.out, "fig_burst_completion.png"), dpi=150)

    # --- G3: laju efektif vs laju yang ditawarkan ---
    fig, ax = plt.subplots()
    offered = [20.0, 5.0]
    eff_std = [mean(B[("50000", "std")], "throughput"),
               mean(B[("200000", "std")], "throughput")]
    eff_sur = [mean(B[("50000", "survey")], "throughput"),
               mean(B[("200000", "survey")], "throughput")]
    x = range(2)
    ax.bar([i - 0.25 for i in x], offered, width=0.25, label="offered")
    ax.bar([i for i in x], eff_std, width=0.25, label="std effective")
    ax.bar([i + 0.25 for i in x], eff_sur, width=0.25, label="survey effective")
    ax.set_xticks(list(x), ["50 ms pacing", "200 ms pacing"])
    ax.set_ylabel("Throughput (msg/s)")
    ax.set_title("Survey handshake tax: ~21 ms/msg under 10 ms delay")
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(a.out, "fig_burst_rate.png"), dpi=150)

    # --- G4: wifi fisik md-std vs md-rtt ---
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 4))
    xs = ["1 KB", "4 KB", "16 KB"]
    recv_std = [mean(W[("std", p)], "message_received") for p in ["1", "4", "16"]]
    recv_rtt = [mean(W[("rtt", p)], "message_received") for p in ["1", "4", "16"]]
    avg_std = [mean(W[("std", p)], "avg_latency") / 1e6 for p in ["1", "4", "16"]]
    avg_rtt = [mean(W[("rtt", p)], "avg_latency") / 1e6 for p in ["1", "4", "16"]]
    x = range(3)
    ax1.bar([i - 0.2 for i in x], recv_std, width=0.4, label="std")
    ax1.bar([i + 0.2 for i in x], recv_rtt, width=0.4, label="rtt-lite")
    ax1.set_xticks(list(x), xs)
    ax1.set_ylabel("Messages Received (of 5000)")
    ax1.set_xlabel("Payload (physical Wi-Fi)")
    ax1.set_title("Completeness over Real Wi-Fi")
    ax1.legend()
    ax2.bar([i - 0.2 for i in x], avg_std, width=0.4, label="std")
    ax2.bar([i + 0.2 for i in x], avg_rtt, width=0.4, label="rtt-lite")
    ax2.set_xticks(list(x), xs)
    ax2.set_ylabel("Average Latency (ms)")
    ax2.set_xlabel("Payload (physical Wi-Fi)")
    ax2.set_title("Average Latency over Real Wi-Fi")
    ax2.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(a.out, "fig_wifi_hasil.png"), dpi=150)

    # --- G5: isolasi slow-peer (rerun netns) ---
    # q1/q2 memakai env yang diabaikan SACK dan hasilnya identik,
    # jadi di-pool menjadi satu bar "survey" (6 file per sub).
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 4))
    order = ["std", "survey"]
    labels = ["std", "survey"]
    s1thr = [mean(A[("std", "s1")], "throughput"),
             mean(A[("q1-survey", "s1")] + A[("q2-survey", "s1")], "throughput")]
    s2recv = [mean(A[("std", "s2")], "message_received"),
              mean(A[("q1-survey", "s2")] + A[("q2-survey", "s2")], "message_received")]
    x = range(2)
    ax1.bar(list(x), s1thr)
    ax1.set_yscale("log")
    ax1.set_xticks(list(x), labels)
    ax1.set_ylabel("Throughput s1, msg/s (log)")
    ax1.set_xlabel("Varian (s1 cepat, s2 lambat 50 ms)")
    ax1.set_title("Fast Peer Throughput (Shared Window)")
    for i in x:
        ax1.text(i, s1thr[i] * 1.2, f"{s1thr[i]:.0f}", ha="center", fontsize=8)
    ax2.bar(list(x), s2recv)
    ax2.set_xticks(list(x), labels)
    ax2.set_ylabel("Messages Received s2 (of 1000)")
    ax2.set_xlabel("Varian (s1 cepat, s2 lambat 50 ms)")
    ax2.set_title("Slow Peer Completeness")
    fig.tight_layout()
    fig.savefig(os.path.join(a.out, "fig_asym_isolation.png"), dpi=150)

    # --- G6: latensi injeksi transien ---
    fig, ax = plt.subplots()
    avg = [mean(T["std"], "avg_latency") / 1e6, mean(T["survey"], "avg_latency") / 1e6]
    p99 = [mean(T["std"], "p99_latency") / 1e6, mean(T["survey"], "p99_latency") / 1e6]
    x = range(2)
    ax.bar([i - 0.2 for i in x], avg, width=0.4, label="avg")
    ax.bar([i + 0.2 for i in x], p99, width=0.4, label="P99")
    ax.set_xticks(list(x), ["std", "survey"])
    ax.set_ylabel("Latency (ms)")
    ax.set_xlabel("Transient 50 ms + loss 1% @3-8s (2000 msgs, paced)")
    ax.set_title("No Queue Amplification Under Survey (P99 pinned at floor)")
    ax.legend()
    for i in x:
        ax.text(i - 0.2, avg[i] + 5, f"{avg[i]:.1f}", ha="center", fontsize=8)
        ax.text(i + 0.2, p99[i] + 5, f"{p99[i]:.0f}", ha="center", fontsize=8)
    fig.tight_layout()
    fig.savefig(os.path.join(a.out, "fig_transient_latency.png"), dpi=150)

    print("saved: fig_loss_d10_perpayload.png fig_burst_completion.png "
          "fig_burst_rate.png fig_wifi_hasil.png "
          "fig_asym_isolation.png fig_transient_latency.png")
    print("survey per-msg tax: "
          f"{(sur_t[0] - std_t[0]):.1f}s/1000 @50ms-pacing, "
          f"{(sur_t[1] - std_t[1]):.1f}s/1000 @200ms-pacing")


if __name__ == "__main__":
    main()
