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
Depth 1: 36 nodes in 0ms (36.00 MNPS)
Depth 2: 1260 nodes in 0ms (272.43 MNPS)
Depth 3: 132720 nodes in 0ms (879.18 MNPS)
Depth 4: 13586048 nodes in 17ms (794.13 MNPS)
Depth 5: 1253506520 nodes in 2083ms (601.50 MNPS)

Total nodes: 1267226584
Total time: 2101ms
Average speed: 603.08 MNPS
\==============================


[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]
Depth 1: 140 nodes in 0ms (56.00 MNPS)
Depth 2: 21402 nodes in 0ms (236.92 MNPS)
Depth 3: 2774593 nodes in 11ms (237.90 MNPS)
Depth 4: 395359484 nodes in 1528ms (258.71 MNPS)
Depth 5: 49338466729 nodes in 214808ms (229.69 MNPS)

Total nodes: 49736622348
Total time: 216348ms
Average speed: 229.89 MNPS
\==============================


[TPS 2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,x5 1 3]
Depth 1: 18 nodes in 0ms (11.37 MNPS)
Depth 2: 317 nodes in 0ms (58.53 MNPS)
Depth 3: 4243 nodes in 0ms (52.27 MNPS)
Depth 4: 64855 nodes in 1ms (51.97 MNPS)
Depth 5: 754479 nodes in 19ms (39.09 MNPS)

Total nodes: 823912
Total time: 20ms
Average speed: 39.89 MNPS
\==============================


[TPS x4,2,1/x3,1,2,x/x3,1,2,x/x,1,1,1,1,2/x2,2,x,1C,x/2,x3,2112,x 2 11]
Depth 1: 102 nodes in 0ms (58.29 MNPS)
Depth 2: 7159 nodes in 0ms (186.76 MNPS)
Depth 3: 670819 nodes in 2ms (293.04 MNPS)
Depth 4: 48336683 nodes in 212ms (227.30 MNPS)
Depth 5: 4271397891 nodes in 15718ms (271.74 MNPS)

Total nodes: 4320412654
Total time: 15933ms
Average speed: 271.15 MNPS
\==============================



