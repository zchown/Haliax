import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

def residual_block(x, channels):
    skip = x
    x = layers.Conv2D(channels, 3, padding="same", use_bias=False)(x)
    x = layers.BatchNormalization()(x)
    x = layers.ReLU()(x)
    x = layers.Conv2D(channels, 3, padding="same", use_bias=False)(x)
    x = layers.BatchNormalization()(x)
    x = layers.Add()([x, skip])
    x = layers.ReLU()(x)
    return x

def build_tak_net(channels_in: int, trunk_channels=64, blocks=8):
    inp = keras.Input(shape=(6, 6, channels_in), name="board")  # NHWC
    x = layers.Conv2D(trunk_channels, 3, padding="same", use_bias=False)(inp)
    x = layers.BatchNormalization()(x)
    x = layers.ReLU()(x)

    for _ in range(blocks):
        x = residual_block(x, trunk_channels)

    flat = layers.Flatten()(x)
    flat = layers.Dense(256, activation="relu")(flat)

    place_pos     = layers.Dense(36, name="place_pos")(flat)
    place_type    = layers.Dense(3,  name="place_type")(flat)
    slide_from    = layers.Dense(36, name="slide_from")(flat)
    slide_dir     = layers.Dense(4,  name="slide_dir")(flat)
    slide_pickup  = layers.Dense(6,  name="slide_pickup")(flat)
    slide_pattern = layers.Dense(32, name="slide_pattern")(flat)

    value = layers.Dense(1, activation="tanh", name="value")(flat)

    return keras.Model(
        inputs=inp,
        outputs=[place_pos, place_type, slide_from, slide_dir, slide_pickup, slide_pattern, value],
        name="tak_net",
    )

def policy_loss(target_pi, logits):
    # target_pi: [B,A] probabilities from visit counts
    # logits: [B,A]
    logp = tf.nn.log_softmax(logits, axis=-1)
    return -tf.reduce_mean(tf.reduce_sum(target_pi * logp, axis=-1))

def value_loss(z, v):
    return tf.reduce_mean(tf.square(z - v))

@tf.function
def train_step(model, opt, batch):
    x, t_place_pos, t_place_type, t_slide_from, t_slide_dir, t_slide_pickup, t_slide_pattern, z = batch

    with tf.GradientTape() as tape:
        (p_place_pos, p_place_type,
         p_slide_from, p_slide_dir,
         p_slide_pickup, p_slide_pattern,
         v) = model(x, training=True)

        loss = (
            policy_loss(t_place_pos,     p_place_pos) +
            policy_loss(t_place_type,    p_place_type) +
            policy_loss(t_slide_from,    p_slide_from) +
            policy_loss(t_slide_dir,     p_slide_dir) +
            policy_loss(t_slide_pickup,  p_slide_pickup) +
            policy_loss(t_slide_pattern, p_slide_pattern) +
            value_loss(z, v)
        )

        l2 = tf.add_n([tf.nn.l2_loss(w) for w in model.trainable_weights])
        loss = loss + 1e-4 * l2

    grads = tape.gradient(loss, model.trainable_weights)
    opt.apply_gradients(zip(grads, model.trainable_weights))
    return loss

