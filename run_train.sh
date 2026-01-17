python training_loop.py \
  --selfplay-bin ./zig-out/bin/selfplay \
  --train-py ./Engine/NeuralNetwork/train.py \
  --concat-py concat_takbin.py \
  --iters 1 \
  --workers 6 \
  --games 1000 \
  --train-steps 8000 \
  --batch-size 256 \
  --channels-in 26

