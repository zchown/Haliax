import torch
import torch.nn as nn
import torch.nn.functional as F
import os

class ResidualBlock(nn.Module):
    def __init__(self, c: int):
        super().__init__()
        self.conv1 = nn.Conv2d(c, c, 3, padding=1, bias=False)
        self.bn1 = nn.BatchNorm2d(c)
        self.conv2 = nn.Conv2d(c, c, 3, padding=1, bias=False)
        self.bn2 = nn.BatchNorm2d(c)

    def forward(self, x):
        skip = x
        x = F.relu(self.bn1(self.conv1(x)))
        x = self.bn2(self.conv2(x))
        x = F.relu(x + skip)
        return x

class TakNet(nn.Module):
    def __init__(self, channels_in: int, trunk_channels: int = 64, blocks: int = 8):
        super().__init__()
        self.stem = nn.Sequential(
            nn.Conv2d(channels_in, trunk_channels, 3, padding=1, bias=False),
            nn.BatchNorm2d(trunk_channels),
            nn.ReLU(inplace=True),
        )
        self.blocks = nn.Sequential(*[ResidualBlock(trunk_channels) for _ in range(blocks)])
        self.fc = nn.Sequential(
            nn.Flatten(),
            nn.Linear(trunk_channels * 6 * 6, 256),
            nn.ReLU(inplace=True),
        )

        self.place_pos     = nn.Linear(256, 36)
        self.place_type    = nn.Linear(256, 3)
        self.slide_from    = nn.Linear(256, 36)
        self.slide_dir     = nn.Linear(256, 4)
        self.slide_pickup  = nn.Linear(256, 6)
        self.slide_len     = nn.Linear(256, 6)
        self.value         = nn.Linear(256, 1)

    def forward(self, x):
        # x: NCHW
        x = self.stem(x)
        x = self.blocks(x)
        x = self.fc(x)
        return (
            self.place_pos(x),
            self.place_type(x),
            self.slide_from(x),
            self.slide_dir(x),
            self.slide_pickup(x),
            self.slide_len(x),
            torch.tanh(self.value(x)),
        )

def policy_loss(target_pi, logits):
    logp = F.log_softmax(logits, dim=-1)
    return -(target_pi * logp).sum(dim=-1).mean()

def value_loss(z, v):
    return F.mse_loss(v.squeeze(-1), z)

if __name__ == "__main__":
    # Simple test
    model = TakNet(channels_in=26)
    dummy = torch.randn(1, 26, 6, 6)
    onnx_path = os.path.join("models", "tak_net.onnx")
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
        opset_version=18,
        dynamo=False,
        dynamic_axes={"board": {0: "batch"}},
    )
    print("Wrote", onnx_path)

