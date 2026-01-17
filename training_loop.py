import argparse
import subprocess
from pathlib import Path

def run(cmd, **kw):
    print(" ".join(cmd))
    subprocess.check_call(cmd, **kw)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iters", type=int, default=50)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--games", type=int, default=1000)
    ap.add_argument("--max-plies", type=int, default=256)

    ap.add_argument("--selfplay-bin", required=True, help="Path to selfplay executable")
    ap.add_argument("--train-py", default="train.py", help="Path to train.py")
    ap.add_argument("--concat-py", default="concat_takbin.py", help="Path to concat_takbin.py")

    ap.add_argument("--runs-dir", default="runs", help="Base runs directory")
    ap.add_argument("--channels-in", type=int, default=26)

    ap.add_argument("--train-steps", type=int, default=8000)
    ap.add_argument("--batch-size", type=int, default=256)
    ap.add_argument("--device", default=None)

    args = ap.parse_args()

    # ---- resolve everything up front ----
    selfplay_bin = Path(args.selfplay_bin).resolve()
    train_py = Path(args.train_py).resolve()
    concat_py = Path(args.concat_py).resolve()
    runs_dir = Path(args.runs_dir).resolve()

    runs_dir.mkdir(parents=True, exist_ok=True)

    best_dir = (runs_dir / "best")
    best_dir.mkdir(parents=True, exist_ok=True)
    best_onnx = (best_dir / "tak_net.onnx").resolve()

    tmp_dir = Path("tmp_selfplay").resolve()
    tmp_dir.mkdir(exist_ok=True)

    if not best_onnx.exists():
        print(
            f"WARNING: {best_onnx} does not exist yet. "
            "Selfplay must handle no-model or you must create an initial model."
        )

    resume_ckpt = None

    for it in range(args.iters):
        print(f"\n=== ITER {it} ===")

        per = args.games // args.workers
        rem = args.games % args.workers

        procs = []
        chunk_paths = []

        for w in range(args.workers):
            g = per + (1 if w < rem else 0)
            out = (tmp_dir / f"self_{it}_{w}.takbin").resolve()
            chunk_paths.append(str(out))

            cmd = [
                str(selfplay_bin),
                str(best_onnx),
                str(out),
                str(g),
                str(args.max_plies),
            ]
            procs.append(subprocess.Popen(cmd))

        for p in procs:
            if p.wait() != 0:
                raise SystemExit("Selfplay worker failed")

        # ---- concat into one dataset ----
        dataset_path = (runs_dir / f"selfplay_iter{it}.takbin").resolve()
        run(
            ["python", str(concat_py), "--out", str(dataset_path)] + chunk_paths
        )

        out_dir = (runs_dir / f"iter{it}").resolve()
        out_dir.mkdir(parents=True, exist_ok=True)

        train_cmd = [
            "python",
            str(train_py),
            "--data", str(dataset_path),
            "--out-dir", str(out_dir),
            "--channels-in", str(args.channels_in),
            "--steps", str(args.train_steps),
            "--batch-size", str(args.batch_size),
            "--export-onnx",
        ]
        if resume_ckpt:
            train_cmd += ["--resume", resume_ckpt]
        if args.device:
            train_cmd += ["--device", args.device]

        run(train_cmd)

        resume_ckpt = str((out_dir / f"ckpt_{args.train_steps}.pt").resolve())

        new_onnx = (out_dir / "tak_net.onnx").resolve()
        if new_onnx.exists():
            best_onnx.write_bytes(new_onnx.read_bytes())
            print("Promoted", new_onnx, "->", best_onnx)

if __name__ == "__main__":
    main()

