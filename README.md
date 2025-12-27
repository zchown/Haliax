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

[TPS x6/x6/x6/x6/x6/x6 1 1]
Depth 1: 36 nodes in 0ms (61.75 MNPS)
Depth 2: 1260 nodes in 0ms (549.74 MNPS)
Depth 3: 132720 nodes in 0ms (1004.50 MNPS)
Depth 4: 13586048 nodes in 14ms (960.14 MNPS)
Depth 5: 1253506520 nodes in 1646ms (761.44 MNPS)
Depth 6: 112449385016 nodes in 159885ms (703.31 MNPS)

Total nodes: 113716611600
Total time: 161546ms
Average speed: 703.93 MNPS
\==============================



[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]
Depth 1: 140 nodes in 0ms (65.88 MNPS)
Depth 2: 21402 nodes in 0ms (281.61 MNPS)
Depth 3: 2774593 nodes in 9ms (288.63 MNPS)
Depth 4: 395359484 nodes in 1224ms (322.76 MNPS)
Depth 5: 49338466729 nodes in 177283ms (278.30 MNPS)

Total nodes: 49736622348
Total time: 178517ms
Average speed: 278.61 MNPS
\==============================



[TPS 2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,x5 1 3]
Depth 1: 18 nodes in 0ms (61.64 MNPS)
Depth 2: 317 nodes in 0ms (73.86 MNPS)
Depth 3: 4243 nodes in 0ms (64.33 MNPS)
Depth 4: 64855 nodes in 1ms (64.70 MNPS)
Depth 5: 754479 nodes in 16ms (47.10 MNPS)
Depth 6: 11320295 nodes in 198ms (57.14 MNPS)
Depth 7: 130812445 nodes in 3012ms (43.42 MNPS)

Total nodes: 142956652
Total time: 3227ms
Average speed: 44.29 MNPS
==============================



[TPS x4,2,1/x3,1,2,x/x3,1,2,x/x,1,1,1,1,2/x2,2,x,1C,x/2,x3,2112,x 2 11]
Depth 1: 102 nodes in 0ms (74.18 MNPS)
Depth 2: 7159 nodes in 0ms (226.37 MNPS)
Depth 3: 670819 nodes in 1ms (357.87 MNPS)
Depth 4: 48336683 nodes in 177ms (272.83 MNPS)
Depth 5: 4271397891 nodes in 13013ms (328.22 MNPS)

Total nodes: 4320412654
Total time: 13192ms
Average speed: 327.48 MNPS
\==============================



[TPS 2S,221,1,1,1,x/x,1S,2,x,1,x/x2,2,111112C,1,2/2,2,2,1,112S,1/1,2221C,221,2,2221S,2/2,2,1,x,2S,1 1 39]
Depth 1: 111 nodes in 0ms (64.99 MNPS)
Depth 2: 20969 nodes in 0ms (327.64 MNPS)
Depth 3: 2559626 nodes in 10ms (254.75 MNPS)
Depth 4: 318067684 nodes in 1130ms (281.33 MNPS)
Depth 5: 41330513334 nodes in 150181ms (275.20 MNPS)

Total nodes: 41651161724
Total time: 151321ms
Average speed: 275.25 MNPS
\==============================



