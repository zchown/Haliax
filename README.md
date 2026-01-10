# Haliax

# Overview
Haliax is an implementation of the game Tak. More information can be found here [ustak.org](https://ustak.org/). Haliax is written in Zig and is designed to generate moves as fast as possible but without doing anything that would negatively impact writing an AI on top of it. Things like Zobrist hashing and other nice features for an AI are included.

# Optimizations
Haliax uses a number of optimizations to achieve fast move generation:
- **Bitboards**: The board state is represented using bitboards, allowing for efficient manipulation and querying of the game state.
- **Move Representation**: Moves are represented in a u16, allowing for quick encoding and decoding of moves. They use a pattern system where a 0 represents a drop and a 1 represents a move and drop. This is much more efficient than my previous implementation.
- **Precomputed Move Tables**: All slide move patterns are precomputed and stored in tables, allowing for quick lookup of valid moves. This is for normal slide moves and crush moves. Zig allows this to be done at compile time, so there is no runtime cost.
- **Magic Bitboards**: Magic bitboards are used to quickly generate slide moves. This technique is borrowed from chess engines and allows for fast move generation by using bitwise operations and precomputed tables. This is a time save when compared to doing a raycast for each slide move. Bitboards generated ahead of time but not using Zigs comptime features as sometimes you might want to try to get better results which can take to long for comptime.
- **Road detection**: Road detection is optimized using bitwise operations to quickly filter out impossible road patterns before checking for valid roads. Checking for valid roads is done with a bitboard flood fill algorithm. Also included is a union find structure to help with road detection. The union find structure suffers on performance in a raw perft test but would help an AI to evaluate positions faster.

# Project Structure
- `Tak/main.zig`: Main entry point for the Haliax library that runs perft tests.
- `Tak/perft.zig`: Contains the perft testing functions to validate move generation.
- `Tak/src/board.zig`: Contains the board representation and related functions.
- `Tak/src/move.zig`: Contains make move, undo move, and move generation functions.
- `Tak/src/zobrist.zig`: Contains Zobrist hashing functions for board state hashing.
- `Tak/src/magic.zig`: Contains magic bitboard generation and lookup functions.
- `Tak/src/magic_bitboards.zig`: Contains precomputed magic bitboards for move generation.
- `Tak/src/sympathy.zig`: Contains precomputed slide move patterns.
- `Tak/src/road.zig`: Contains union find structure and road detection functions.
- `Tak/src/ptn.zig`: Contains PTN parsing and generation functions.
- `Tak/src/tps.zig`: Contains TPS parsing and generation functions.
- `Tak/tests/`: Contains test cases for validating the functionality of the Haliax library.
- `Tak/tools/gen_magic.zig`: Tool to generate magic bitboards.
- `Tracy/tracy.zig`: Tracy profiler integration for performance analysis.

# Performance
Haliax was optimized using the tracy profiler to identify bottlenecks in the move generation process.

Running bulk perft a macbook air m4 on a variety of board positions yields the following results:

---

### TPS: `x6/x6/x6/x6/x6/x6` (6×6 Empty Board)

| Depth |           Nodes | Time (ms) | Speed (MNPS) |
| ----: | --------------: | --------: | -----------: |
|     1 |              36 |         0 |       428.57 |
|     2 |           1,260 |         0 |       756.30 |
|     3 |         132,720 |         0 |     3,059.83 |
|     4 |      13,586,048 |         4 |     3,389.56 |
|     5 |   1,253,506,520 |       528 |     2,370.06 |
|     6 | 112,449,385,016 |   466,454 |     2,410.71 |

**Summary**

* **Total nodes:** 113,716,611,600
* **Total time:** 471,760 ms
* **Average speed:** **2,410.34 MNPS**

---

### TPS:

`2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1`

| Depth |          Nodes | Time (ms) | Speed (MNPS) |
| ----: | -------------: | --------: | -----------: |
|     1 |            140 |         0 |       240.14 |
|     2 |         21,402 |         0 |       632.58 |
|     3 |      2,774,593 |         3 |       829.80 |
|     4 |    395,359,484 |       396 |       997.74 |
|     5 | 48,986,506,534 |    60,492 |       809.79 |

**Summary**

* **Total nodes:** 4,938,462,153
* **Total time:** 60892ms
* **Average speed:** **811.02 MNPS**

---

### TPS:

`2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,x5`

| Depth |          Nodes | Time (ms) | Speed (MNPS) |
| ----: | -------------: | --------: | -----------: |
|     1 |             18 |         0 |        48.00 |
|     2 |            317 |         0 |        90.57 |
|     3 |          4,243 |         0 |       120.66 |
|     4 |         64,855 |         0 |       120.73 |
|     5 |        754,479 |         7 |        98.72 |
|     6 |     11,320,295 |        99 |       114.24 |
|     7 |    130,812,445 |     1,423 |        91.92 |
|     8 |  2,042,784,845 |    17,805 |       114.73 |
|     9 | 24,765,415,103 |   282,887 |        87.55 |

**Summary**

* **Total nodes:** 26,951,156,600
* **Total time:** 302,223 ms
* **Average speed:** **89.18 MNPS**

---

### TPS: `2,2,21S,12122,221,x/x,12C,2,x/x,12,x3,1,1/x,2,x3,1/x,12C,2,x2,1/x,12S,1,1,1/x,2`

| Depth |          Nodes | Time (ms) | Speed (MNPS) |
| ----: | -------------: | --------: | -----------: |
|     1 |             85 |         0 |       170.00 |
|     2 |         12,914 |         0 |       655.27 |
|     3 |      1,347,284 |         2 |       626.04 |
|     4 |    170,199,602 |       185 |       918.75 |
|     5 | 19,062,244,190 |    24,139 |       789.68 |

**Summary**

* **Total nodes:** 19,233,804,075
* **Total time:** 24,326 ms
* **Average speed:** **790.64 MNPS**
