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

Depth 1: 36 nodes in 0ms (857.14 MNPS)

Depth 2: 1260 nodes in 0ms (657.62 MNPS)

Depth 3: 132720 nodes in 0ms (2683.77 MNPS)

Depth 4: 13586048 nodes in 4ms (2947.78 MNPS)

Depth 5: 1253506520 nodes in 609ms (2056.09 MNPS)

Depth 6: 112449385016 nodes in 61890ms (1816.90 MNPS)

Total nodes: 113716611600
Total time: 62505ms
Average speed: 1819.32 MNPS


[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]

Depth 1: 140 nodes in 0ms (239.73 MNPS)

Depth 2: 21402 nodes in 0ms (411.24 MNPS)

Depth 3: 2774593 nodes in 6ms (435.87 MNPS)

Depth 4: 395359484 nodes in 824ms (479.70 MNPS)

Depth 5: 48986506534 nodes in 118471ms (413.49 MNPS)

Total nodes: 4938462153
Total time: 119302ms
Average speed: 413.94 MNPS

[TPS 2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,x5 1 3]

Depth 1: 18 nodes in 0ms (30.87 MNPS)

Depth 2: 317 nodes in 0ms (83.60 MNPS)

Depth 3: 4243 nodes in 0ms (73.26 MNPS)

Depth 4: 64855 nodes in 0ms (86.03 MNPS)

Depth 5: 754479 nodes in 12ms (59.26 MNPS)

Depth 6: 11320295 nodes in 150ms (75.40 MNPS)

Depth 7: 130812445 nodes in 2417ms (54.11 MNPS)

Depth 8: 2042784845 nodes in 27906ms (73.20 MNPS)

Depth 9: 24765415103 nodes in 461284ms (53.69 MNPS)

Total nodes: 26951156600
Total time: 491772ms
Average speed: 54.80 MNPS

