import os
import torch
from torch.utils.data import DataLoader

from tak_net import TakNet
from dataset import TakBinDataset, policy_loss, value_loss

def train(
    data_path: str,
    out_dir: str,
    channels_in: int,
    steps: int = 50_000,
    batch_size: int = 256,
    lr: float = 1e-3,
    weight_decay: float = 1e-4,
    num_workers: int = 0,
):
    os.makedirs(out_dir, exist_ok=True)

    ds = TakBinDataset(data_path)
    dl = DataLoader(ds, batch_size=batch_size, num_workers=num_workers)

    model = TakNet(channels_in=channels_in, trunk_channels=64, blocks=8)
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=weight_decay)

    model.train()
    step = 0

    for batch in dl:
        (x, t_pp, t_pt, t_sf, t_sd, t_sp, t_sl, z) = batch

        (p_pp, p_pt, p_sf, p_sd, p_sp, p_sl, v) = model(x)

        loss = (
            policy_loss(t_pp, p_pp)
            + policy_loss(t_pt, p_pt)
            + policy_loss(t_sf, p_sf)
            + policy_loss(t_sd, p_sd)
            + policy_loss(t_sp, p_sp)
            + policy_loss(t_sl, p_sl)
            + value_loss(z, v)
        )

        opt.zero_grad(set_to_none=True)
        loss.backward()
        opt.step()

        if step % 100 == 0:
            print(f"step {step} loss {loss.item():.4f}")

        if step % 2000 == 0 and step > 0:
            ckpt_path = os.path.join(out_dir, f"ckpt_{step}.pt")
            torch.save(
                {"step": step, "model": model.state_dict(), "opt": opt.state_dict()},
                ckpt_path,
            )

        if step >= steps:
            break

        step += 1

    model.eval()
    dummy = torch.randn(1, channels_in, 6, 6)
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
        dynamic_axes={"board": {0: "batch"}},
        opset_version=17,
    )
    print("Wrote", onnx_path)


if __name__ == "__main__":
    train(
        data_path="selfplay.takbin",
        out_dir="runs/run1",
        channels_in=26,
        steps=50_000,
        batch_size=256,
    )

