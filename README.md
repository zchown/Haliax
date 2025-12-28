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
Depth 1: 36 nodes in 0ms (41.14 MNPS)
Depth 2: 1260 nodes in 0ms (737.27 MNPS)
Depth 3: 132720 nodes in 0ms (886.28 MNPS)
Depth 4: 13586048 nodes in 15ms (868.37 MNPS)
Depth 5: 1253506520 nodes in 1708ms (733.86 MNPS)

Total nodes: 1267226584
Total time: 1723ms
Average speed: 735.10 MNPS
\==============================



[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]
Depth 1: 140 nodes in 0ms (56.00 MNPS)
Depth 2: 21402 nodes in 0ms (277.05 MNPS)
Depth 3: 2774593 nodes in 9ms (287.41 MNPS)
Depth 4: 395359484 nodes in 1220ms (324.01 MNPS)
Depth 5: 49338466729 nodes in 181676ms (271.57 MNPS)

Total nodes: 49736622348
Total time: 182906ms
Average speed: 271.92 MNPS
\==============================



[TPS 2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,x5 1 3]
Depth 1: 18 nodes in 0ms (13.09 MNPS)
Depth 2: 317 nodes in 0ms (72.46 MNPS)
Depth 3: 4243 nodes in 0ms (61.83 MNPS)
Depth 4: 64855 nodes in 1ms (61.11 MNPS)
Depth 5: 754479 nodes in 16ms (46.31 MNPS)

Total nodes: 823912
Total time: 17ms
Average speed: 47.23 MNPS
\==============================


Allowing counting instead of full move generation for perft allows for better performance:

[TPS x6/x6/x6/x6/x6/x6 1 1]
Depth 1: 36 nodes in 0ms (857.14 MNPS)
Depth 2: 1260 nodes in 0ms (703.13 MNPS)
Depth 3: 132720 nodes in 0ms (3504.16 MNPS)
Depth 4: 13586048 nodes in 4ms (3368.27 MNPS)
Depth 5: 1253506520 nodes in 541ms (2315.18 MNPS)

Total nodes: 1267226584
Total time: 545ms
Average speed: 2322.90 MNPS
\==============================

[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]
Depth 1: 140 nodes in 0ms (335.73 MNPS)
Depth 2: 23194 nodes in 0ms (452.94 MNPS)
Depth 3: 2804034 nodes in 6ms (454.91 MNPS)
Depth 4: 419297076 nodes in 810ms (517.16 MNPS)
Depth 5: 50330081908 nodes in 113174ms (444.71 MNPS)

Total nodes: 50752206352
Total time: 113991ms
Average speed: 445.23 MNPS
\==============================


[TPS 2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,x5 1 3]
Depth 1: 18 nodes in 0ms (39.22 MNPS)
Depth 2: 317 nodes in 0ms (69.81 MNPS)
Depth 3: 4243 nodes in 0ms (73.74 MNPS)
Depth 4: 64855 nodes in 0ms (82.64 MNPS)
Depth 5: 754479 nodes in 12ms (61.43 MNPS)

Total nodes: 823912
Total time: 13ms
Average speed: 62.69 MNPS
\==============================



