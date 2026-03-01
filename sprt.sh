#!/usr/bin/env bash
set -euo pipefail

ENGINE_NEW="./zig-out/bin/Haliax"
ENGINE_BASE="./engines/Haliax_AB_0.20"
# ENGINE_BASE="./engines/HaliaxFlatDiff"
# ENGINE_BASE="./engines/HaliaxRandom"
# ENGINE_BASE="./../syntaks/target/x86_64-apple-darwin/release/syntaks"

RACETRACK="racetrack"

BOARD_SIZE=6          # Board size (5 or 6)
KOMI=2.0              # Komi value
TC="2+0.1"             # Time control: seconds+increment
GAMES=10000           # Max games (SPRT will stop early)
CONCURRENCY=10        # Parallel games

BOOK="./sprt_balanced.book"
BOOK_FORMAT="tps"     # tps or ptn

ELO0=0
ELO1=10
ALPHA=0.05
BETA=0.05

OUTDIR="matches/$(date +%Y%m%d_%H%M%S)"
LOG="$OUTDIR/racetrack.log"

mkdir -p "$OUTDIR"

echo "Starting racetrack SPRT match"
echo "  New:    $ENGINE_NEW"
echo "  Base:   $ENGINE_BASE"
echo "  Size:   ${BOARD_SIZE}x${BOARD_SIZE}  Komi: $KOMI"
echo "  TC:     $TC"
echo "  Games:  $GAMES (SPRT will stop early)"
echo "  SPRT:   elo0=$ELO0 elo1=$ELO1 alpha=$ALPHA beta=$BETA"
echo "  Output: $OUTDIR"
echo

$RACETRACK \
  -s $BOARD_SIZE \
  -c $CONCURRENCY \
  --komi $KOMI \
  -g $GAMES \
  -b "$BOOK" \
  --book-format $BOOK_FORMAT \
  --shuffle-book \
  -e path="$ENGINE_BASE" \
  -e path="$ENGINE_NEW" \
  --all-engines tc=$TC \
  --format sprt \
  --log $LOG \
  | tee "$LOG"

# --sprt elo0=$ELO0 elo1=$ELO1 alpha=$ALPHA beta=$BETA \
echo
echo "SPRT test finished"
echo "Log: $LOG"
