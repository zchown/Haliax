import argparse
import os
from typing import Optional

import torch
from torch.utils.data import DataLoader, IterableDataset

from tak_net import TakNet
from dataset import TakBinDataset, policy_loss, value_loss


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Train TakNet from takbin selfplay data. Supports resuming from .pt checkpoints."
    )
    p.add_argument("--data", required=True, help="Path to .takbin dataset (e.g. selfplay.takbin)")
    p.add_argument("--out-dir", required=True, help="Output directory for checkpoints and ONNX export")
    p.add_argument("--channels-in", type=int, required=True, help="Input channels (e.g. 27)")

    p.add_argument(
        "--steps",
        type=int,
        default=50_000,
        help="Number of optimizer steps to run (additional steps if --resume is provided)",
    )
    p.add_argument("--batch-size", type=int, default=256, help="Batch size")
    p.add_argument("--lr", type=float, default=1e-3, help="Learning rate")
    p.add_argument("--weight-decay", type=float, default=1e-4, help="Weight decay")
    p.add_argument("--num-workers", type=int, default=0, help="DataLoader workers")
    p.add_argument("--seed", type=int, default=0, help="Random seed")

    p.add_argument(
        "--device",
        default=None,
        help='Device string (e.g. "cuda", "cuda:0", "cpu"). Default: auto',
    )

    # Checkpointing / resume
    p.add_argument(
        "--resume",
        default=None,
        help="Path to .pt checkpoint to resume from (loads model + optimizer + step)",
    )
    p.add_argument(
        "--save-every",
        type=int,
        default=2000,
        help="Save a .pt checkpoint every N steps (0 disables periodic saves)",
    )
    p.add_argument(
        "--print-every",
        type=int,
        default=100,
        help="Print loss every N steps (0 disables)",
    )

    # Optional ONNX export at end (for your Zig engine)
    p.add_argument(
        "--export-onnx",
        action="store_true",
        help="Export ONNX at the end to <out-dir>/tak_net.onnx",
    )
    p.add_argument(
        "--onnx-opset",
        type=int,
        default=18,
        help="ONNX opset version (default 18)",
    )

    # Only valid for map-style datasets; ignored for IterableDataset
    p.add_argument(
        "--shuffle",
        action="store_true",
        help="Shuffle dataset each epoch (ignored for IterableDataset)",
    )

    return p.parse_args()


def set_seed(seed: int) -> None:
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def save_ckpt(out_dir: str, step: int, model: torch.nn.Module, opt: torch.optim.Optimizer) -> str:
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"ckpt_{step}.pt")
    payload = {"step": step, "model": model.state_dict(), "opt": opt.state_dict()}
    torch.save(payload, path)

    # Also write/update a stable "latest.pt" pointer for easy resume
    latest_path = os.path.join(out_dir, "latest.pt")
    torch.save(payload, latest_path)

    return path


def load_ckpt(
    ckpt_path: str,
    model: torch.nn.Module,
    opt: Optional[torch.optim.Optimizer],
    device: str,
) -> int:
    ckpt = torch.load(ckpt_path, map_location=device)
    model.load_state_dict(ckpt["model"], strict=True)
    if opt is not None and "opt" in ckpt:
        opt.load_state_dict(ckpt["opt"])
    return int(ckpt.get("step", 0))


def export_onnx(model: torch.nn.Module, out_dir: str, channels_in: int, device: str, opset: int) -> str:
    model.eval()
    dummy = torch.randn(1, channels_in, 6, 6, device=device)
    onnx_path = os.path.join(out_dir, "tak_net.onnx")
    torch.onnx.export(
        model,
        dummy,
        onnx_path,
        input_names=["board"],
        output_names=[
            "place_pos",
            "place_type",
            "slide_from",
            "slide_dir",
            "slide_pickup",
            "slide_len",
            "value",
        ],
        opset_version=opset,
        dynamo=False,
    )
    return onnx_path


def train_cli(args: argparse.Namespace) -> None:
    os.makedirs(args.out_dir, exist_ok=True)

    device = args.device or ("cuda" if torch.cuda.is_available() else "cpu")
    set_seed(args.seed)

    ds = TakBinDataset(args.data)

    is_iterable = isinstance(ds, IterableDataset)
    if is_iterable and args.shuffle:
        print("Note: --shuffle ignored for IterableDataset (TakBinDataset)")

    dl = DataLoader(
        ds,
        batch_size=args.batch_size,
        num_workers=args.num_workers,
        shuffle=(args.shuffle if not is_iterable else False),
        drop_last=True,
    )

    model = TakNet(channels_in=args.channels_in, trunk_channels=128, blocks=12).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)

    # Resume (model + opt + step)
    start_step = 0
    if args.resume:
        start_step = load_ckpt(args.resume, model, opt, device)
        print(f"Resumed from {args.resume} at step {start_step}")

    # IMPORTANT: steps means "additional steps" when resuming
    target_step = start_step + int(args.steps)
    step = start_step

    model.train()

    dl_iter = iter(dl)

    while step < target_step:
        try:
            batch = next(dl_iter)
        except StopIteration:
            dl_iter = iter(dl)
            batch = next(dl_iter)

        (x, t_pp, t_pt, t_sf, t_sd, t_sp, t_sl, z) = batch

        x = x.to(device)
        t_pp = t_pp.to(device)
        t_pt = t_pt.to(device)
        t_sf = t_sf.to(device)
        t_sd = t_sd.to(device)
        t_sp = t_sp.to(device)
        t_sl = t_sl.to(device)
        z = z.to(device)

        (p_pp, p_pt, p_sf, p_sd, p_sp, p_sl, v) = model(x)

        loss = (
            ((policy_loss(t_pp, p_pp)
            + policy_loss(t_pt, p_pt)
            + policy_loss(t_sf, p_sf)
            + policy_loss(t_sd, p_sd)
            + policy_loss(t_sp, p_sp)
            + policy_loss(t_sl, p_sl)) / 6.0)
            + value_loss(z, v)
        )

        opt.zero_grad(set_to_none=True)
        loss.backward()
        opt.step()

        if args.print_every and (step % args.print_every == 0):
            print(f"step {step} loss {loss.item():.4f}")
            print(f"  value loss {value_loss(z, v).item():.4f}")

        # Save every N *global* steps
        if args.save_every and (step % args.save_every == 0) and step > start_step:
            ckpt_path = save_ckpt(args.out_dir, step, model, opt)
            print(f"Saved {ckpt_path}")

        step += 1

    # Always save a final checkpoint at the end
    final_path = save_ckpt(args.out_dir, step, model, opt)
    print(f"Saved final {final_path} (also wrote {os.path.join(args.out_dir, 'latest.pt')})")

    if args.export_onnx:
        onnx_path = export_onnx(model, args.out_dir, args.channels_in, device, args.onnx_opset)
        print(f"Wrote {onnx_path}")


def main() -> None:
    args = parse_args()
    train_cli(args)


if __name__ == "__main__":
    main()

