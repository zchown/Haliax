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
Depth 1: 36 nodes in 0ms (27.86 MNPS)
Depth 2: 1260 nodes in 0ms (540.08 MNPS)
Depth 3: 132720 nodes in 0ms (684.71 MNPS)
Depth 4: 13586048 nodes in 21ms (646.67 MNPS)
Depth 5: 1253506520 nodes in 2272ms (551.70 MNPS)
Depth 6: 112449385016 nodes in 215556ms (521.67 MNPS)

Total nodes: 113716611600
Total time: 217850ms
Average speed: 521.99 MNPS


[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]
Depth 1: 140 nodes in 0ms (43.64 MNPS)
Depth 2: 21402 nodes in 0ms (210.17 MNPS)
Depth 3: 2774593 nodes in 13ms (208.97 MNPS)
Depth 4: 395359484 nodes in 1734ms (227.91 MNPS)
Depth 5: 48986506534 nodes in 250409ms (195.63 MNPS)

Total nodes: 49384662153
Total time: 252158ms
Average speed: 195.85 MNPS


[TPS 2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,x5 1 3]
Depth 1: 18 nodes in 0ms (28.80 MNPS)
Depth 2: 317 nodes in 0ms (43.98 MNPS)
Depth 3: 4243 nodes in 0ms (39.12 MNPS)
Depth 4: 64855 nodes in 1ms (39.14 MNPS)
Depth 5: 754479 nodes in 24ms (30.48 MNPS)
Depth 6: 11320295 nodes in 306ms (36.99 MNPS)
Depth 7: 130812445 nodes in 4601ms (28.43 MNPS)
Depth 8: 2042784845 nodes in 86939ms (23.50 MNPS)
Depth 9: 24765415103 nodes in 684709ms (36.17 MNPS)

Total nodes: 26951156600
Total time: 776584ms
Average speed: 34.70 MNPS


Allowing counting instead of full move generation for perft allows for better performance:

Depth 1: 36 nodes in 0ms (34.55 MNPS)
Depth 2: 1260 nodes in 0ms (795.96 MNPS)
Depth 3: 132720 nodes in 0ms (817.79 MNPS)
Depth 4: 13586048 nodes in 16ms (835.27 MNPS)
Depth 5: 1253506520 nodes in 1769ms (708.39 MNPS)
Depth 6: 112449385016 nodes in 74325ms (1512.94 MNPS)

Total nodes: 113716611600
Total time: 74941ms
Average speed: 1517.41 MNPS


[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]
Depth 1: 140 nodes in 0ms (197.74 MNPS)
Depth 2: 21402 nodes in 0ms (318.05 MNPS)
Depth 3: 2774593 nodes in 8ms (340.07 MNPS)
Depth 4: 395359484 nodes in 1054ms (375.07 MNPS)
Depth 5: 48986506534 nodes in 151332ms (323.70 MNPS)

Total nodes: 49384662153
Total time: 152395ms
Average speed: 324.06 MNPS


[TPS 2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,x5 1 3]
Depth 1: 18 nodes in 0ms (39.22 MNPS)
Depth 2: 317 nodes in 0ms (66.17 MNPS)
Depth 3: 4243 nodes in 0ms (65.44 MNPS)
Depth 4: 64855 nodes in 0ms (68.98 MNPS)
Depth 5: 754479 nodes in 16ms (46.57 MNPS)
Depth 6: 11320295 nodes in 192ms (58.81 MNPS)
Depth 7: 130812445 nodes in 3098ms (42.22 MNPS)
Depth 8: 2042784845 nodes in 36013ms (56.72 MNPS)
Depth 9: 24765415103 nodes in 629055ms (39.37 MNPS)

Total nodes: 26951156600
Total time: 668378ms
Average speed: 40.32 MNPS
