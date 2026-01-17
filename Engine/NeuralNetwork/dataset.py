import struct
import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import IterableDataset

MAGIC = b"TAKDATA1"
BOARD_N = 6


def idx_to_rc(idx: int) -> tuple[int, int]:
    return divmod(idx, BOARD_N)  # r, c


def rc_to_idx(r: int, c: int) -> int:
    return r * BOARD_N + c


def transform_rc(r: int, c: int, rot: int, flip: bool) -> tuple[int, int]:
    """
    Apply dihedral transform to coordinates.
    rot: 0,1,2,3 = rotate 0/90/180/270 degrees clockwise.
    flip: mirror horizontally (left-right) AFTER rotation.
    """
    # rotate clockwise
    if rot == 0:
        rr, cc = r, c
    elif rot == 1:
        rr, cc = c, BOARD_N - 1 - r
    elif rot == 2:
        rr, cc = BOARD_N - 1 - r, BOARD_N - 1 - c
    elif rot == 3:
        rr, cc = BOARD_N - 1 - c, r
    else:
        raise ValueError("rot must be 0..3")

    # horizontal flip
    if flip:
        cc = BOARD_N - 1 - cc

    return rr, cc


def transform_index(idx: int, rot: int, flip: bool) -> int:
    r, c = idx_to_rc(idx)
    rr, cc = transform_rc(r, c, rot, flip)
    return rc_to_idx(rr, cc)


def transform_board_tensor(x: torch.Tensor, rot: int, flip: bool) -> torch.Tensor:
    """
    x: (C, H, W) == (C,6,6)
    rot: 0..3; flip: bool
    """
    # rotate in HW dims
    if rot != 0:
        x = torch.rot90(x, k=rot, dims=(1, 2))  # k times 90deg counter-clockwise
        # NOTE: torch.rot90 uses CCW. Our transform_rc uses CW.
        # So invert: CW rot r == CCW (4-r).
        # Easier: convert here: use k_ccw = (4-rot)%4
    return x


def transform_board_tensor_cw(x: torch.Tensor, rot_cw: int, flip: bool) -> torch.Tensor:
    """
    Use CW rotation to match transform_rc.
    """
    k_ccw = (-rot_cw) % 4  # CW 1 == CCW 3
    if k_ccw:
        x = torch.rot90(x, k=k_ccw, dims=(1, 2))
    if flip:
        x = torch.flip(x, dims=(2,))  # flip W (left-right)
    return x


def permute_policy_pos(p: torch.Tensor, rot: int, flip: bool) -> torch.Tensor:
    """
    p: (36,) distribution over squares.
    """
    out = torch.empty_like(p)
    for i in range(BOARD_N * BOARD_N):
        j = transform_index(i, rot, flip)
        out[j] = p[i]
    return out


def remap_dirs_probs(d: torch.Tensor, rot: int, flip: bool) -> torch.Tensor:
    """
    Remap a 4-way direction distribution under the same board transform.
    Assumes dir encoding: 0=N, 1=E, 2=S, 3=W.

    We compute where each original direction ends up after (rot, flip),
    then move probability mass accordingly.
    """
    vecs = [(-1, 0), (0, 1), (1, 0), (0, -1)]

    def apply_to_vec(dr: int, dc: int) -> tuple[int, int]:
        # Apply rotation+flip to a direction vector by applying the transform
        # to two points and subtracting. Use origin at (2,2) and neighbor.
        r0, c0 = 2, 2
        r1, c1 = r0 + dr, c0 + dc
        tr0 = transform_rc(r0, c0, rot, flip)
        tr1 = transform_rc(r1, c1, rot, flip)
        ndr = tr1[0] - tr0[0]
        ndc = tr1[1] - tr0[1]
        return ndr, ndc

    # Map transformed vec back to index
    vec_to_idx = {(-1, 0): 0, (0, 1): 1, (1, 0): 2, (0, -1): 3}

    out = torch.zeros_like(d)
    for i, (dr, dc) in enumerate(vecs):
        ndr, ndc = apply_to_vec(dr, dc)
        j = vec_to_idx.get((ndr, ndc), None)
        if j is None:
            # Shouldn't happen on orthonormal dihedral transforms
            continue
        out[j] += d[i]
    return out


class TakBinDataset(IterableDataset):
    """
    Reads .takbin written by selfplay.zig (slide_len version) and optionally applies
    8-way symmetry augmentation.

    If augment=True, each record yields 8 samples (rot 0..3 × flip False/True).
    """

    def __init__(self, path: str, augment: bool = True):
        super().__init__()
        self.path = path
        self.augment = augment

    def __iter__(self):
        with open(self.path, "rb") as f:
            magic = f.read(8)
            if magic != MAGIC:
                raise ValueError(f"Bad magic: {magic!r}")

            channels_in = struct.unpack("<I", f.read(4))[0]
            _count = struct.unpack("<I", f.read(4))[0]

            feat_n = BOARD_N * BOARD_N * channels_in

            def read_arr(n: int) -> np.ndarray:
                b = f.read(4 * n)
                if len(b) != 4 * n:
                    raise EOFError("Truncated record")
                return np.frombuffer(b, dtype=np.float32)

            while True:
                buf = f.read(4 * feat_n)
                if not buf:
                    break

                x = np.frombuffer(buf, dtype=np.float32).reshape(BOARD_N, BOARD_N, channels_in)

                t_place_pos = read_arr(36)
                t_place_type = read_arr(3)
                t_slide_from = read_arr(36)
                t_slide_dir = read_arr(4)
                t_slide_pickup = read_arr(6)
                t_slide_len = read_arr(6)
                z = read_arr(1)[0]

                x = torch.from_numpy(x).permute(2, 0, 1).contiguous()  # C,H,W

                t_place_pos = torch.from_numpy(t_place_pos)
                t_place_type = torch.from_numpy(t_place_type)
                t_slide_from = torch.from_numpy(t_slide_from)
                t_slide_dir = torch.from_numpy(t_slide_dir)
                t_slide_pickup = torch.from_numpy(t_slide_pickup)
                t_slide_len = torch.from_numpy(t_slide_len)
                zt = torch.tensor(z, dtype=torch.float32)

                if not self.augment:
                    yield (x, t_place_pos, t_place_type, t_slide_from, t_slide_dir, t_slide_pickup, t_slide_len, zt)
                    continue

                # 8 symmetries
                for rot in (0, 1, 2, 3):
                    for flip in (False, True):
                        xa = transform_board_tensor_cw(x, rot, flip)
                        pp = permute_policy_pos(t_place_pos, rot, flip)
                        sf = permute_policy_pos(t_slide_from, rot, flip)
                        sd = remap_dirs_probs(t_slide_dir, rot, flip)

                        yield (xa, pp, t_place_type, sf, sd, t_slide_pickup, t_slide_len, zt)


def policy_loss(target_pi: torch.Tensor, logits: torch.Tensor) -> torch.Tensor:
    logp = F.log_softmax(logits, dim=-1)
    return -(target_pi * logp).sum(dim=-1).mean()


def value_loss(z: torch.Tensor, v: torch.Tensor) -> torch.Tensor:
    return F.mse_loss(v.squeeze(-1), z)

