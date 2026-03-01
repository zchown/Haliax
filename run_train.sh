python training_loop.py \
  --selfplay-bin ./zig-out/bin/selfplay \
  --train-py ./Engine/NeuralNetwork/train.py \
  --concat-py concat_takbin.py \
  --iters 100 \
  --workers 8 \
  --games 64 \
  --train-steps 1200  \
  --batch-size 128 \
  --channels-in 27

