import java.io.BufferedInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Random;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.locks.LockSupport;
import javax.sound.sampled.AudioFormat;
import javax.sound.sampled.AudioInputStream;
import javax.sound.sampled.AudioSystem;
import javax.sound.sampled.LineUnavailableException;
import javax.sound.sampled.SourceDataLine;
import javax.sound.sampled.UnsupportedAudioFileException;

enum SoundCue { CLICK, CONFIRM, ADJUST }

class SoundEffects {
  final int SAMPLE_RATE = 44100;
  final int BLOCK_FRAMES = 256;
  final long ADJUST_INTERVAL = 48000000L;
  final ScratchGesture gesture = new ScratchGesture();
  final ArrayBlockingQueue<SoundCue> pending = new ArrayBlockingQueue<SoundCue>(4);
  volatile boolean enabled;
  volatile boolean available = true;
  volatile ScratchMotion motion;
  boolean trackingPointer;
  int previousX, previousY;
  long lastAdjustment;
  Thread player;

  void start() {
    player = new Thread(this::playQueuedSounds, "Design Static audio");
    player.setDaemon(true);
    player.start();
  }

  void toggle() {
    if (!available) return;
    enabled = !enabled;
    pending.clear();
    endStroke();
    if (enabled) {
      if (player == null) start();
      play(SoundCue.CLICK);
    } else {
      LockSupport.unpark(player);
    }
  }

  void play(SoundCue cue) {
    if (enabled && available && pending.offer(cue)) LockSupport.unpark(player);
  }

  void adjustment() {
    long now = System.nanoTime();
    if (now - lastAdjustment >= ADJUST_INTERVAL || lastAdjustment == 0) {
      lastAdjustment = now;
      play(SoundCue.ADJUST);
    }
  }

  void beginStroke(int x, int y, long eventMillis) {
    motion = null;
    gesture.reset(eventMillis);
    trackingPointer = true;
    previousX = x;
    previousY = y;
  }

  void stroke(int x, int y, long eventMillis, boolean erasing) {
    if (!trackingPointer) {
      beginStroke(x, y, eventMillis);
      return;
    }
    int dx = x - previousX;
    int dy = y - previousY;
    previousX = x;
    previousY = y;
    if (!enabled || !available || (dx == 0 && dy == 0)) return;
    motion = gesture.move(dx, dy, eventMillis, System.nanoTime(), erasing);
    LockSupport.unpark(player);
  }

  void endStroke() {
    motion = null;
    gesture.reset(0);
    trackingPointer = false;
  }

  void playQueuedSounds() {
    AudioFormat format = new AudioFormat(SAMPLE_RATE, 16, 1, true, false);
    try (SourceDataLine line = AudioSystem.getSourceDataLine(format)) {
      line.open(format, BLOCK_FRAMES * 2 * 3);
      short[][] clips = new short[SoundCue.values().length][];
      clips[SoundCue.CLICK.ordinal()] = makeClip(0.019, 730, 0.084, 0.025, 1800, 1);
      clips[SoundCue.CONFIRM.ordinal()] = makeClip(0.052, 920, 0.058, 0.012, 1300, 2);
      clips[SoundCue.ADJUST.ordinal()] = makeClip(0.013, 1070, 0.033, 0.018, 2100, 3);
      ScratchVoice scratch = new ScratchVoice(readScratchRecording(), SAMPLE_RATE, new Random());
      byte[] block = new byte[BLOCK_FRAMES * 2];
      short[] uiClip = null;
      int uiIndex = 0;
      boolean flushed = false;
      line.start();

      while (!Thread.currentThread().isInterrupted()) {
        if (!enabled) {
          if (!flushed) {
            line.flush();
            scratch.reset();
            uiClip = null;
            flushed = true;
          }
          LockSupport.park();
          continue;
        }
        flushed = false;
        if (uiClip == null) {
          SoundCue cue = pending.poll();
          if (cue != null) {
            uiClip = clips[cue.ordinal()];
            uiIndex = 0;
          }
        }

        ScratchMotion current = motion;
        scratch.update(current, System.nanoTime());
        if (uiClip == null && !scratch.audible()) {
          LockSupport.park();
          continue;
        }

        for (int i = 0; i < BLOCK_FRAMES; i++) {
          double sample = scratch.nextSample();
          if (uiClip != null) {
            sample += uiClip[uiIndex++] / 32768.0;
            if (uiIndex == uiClip.length) uiClip = null;
          }
          int value = (int)Math.round(32767 * Math.max(-1, Math.min(1, sample)));
          block[i * 2] = (byte)value;
          block[i * 2 + 1] = (byte)(value >> 8);
        }
        line.write(block, 0, block.length);
      }
    } catch (LineUnavailableException | RuntimeException unavailable) {
      // The editor remains usable on systems without an audio output.
      available = false;
      pending.clear();
    }
  }

  float[] readScratchRecording() {
    try (InputStream source = createInput("sounds/pencil-scratch.wav")) {
      if (source == null) return null;
      try (AudioInputStream recording = AudioSystem.getAudioInputStream(new BufferedInputStream(source))) {
        AudioFormat format = recording.getFormat();
        if (!AudioFormat.Encoding.PCM_SIGNED.equals(format.getEncoding()) ||
            format.getSampleRate() != SAMPLE_RATE || format.getFrameSize() != 2 ||
            format.getSampleSizeInBits() != 16 || format.getChannels() != 1) return null;
        byte[] pcm = recording.readAllBytes();
        if (pcm.length < SAMPLE_RATE || pcm.length % 2 != 0) return null;
        ByteBuffer bytes = ByteBuffer.wrap(pcm).order(format.isBigEndian() ? ByteOrder.BIG_ENDIAN : ByteOrder.LITTLE_ENDIAN);
        float[] samples = new float[pcm.length / 2];
        for (int i = 0; i < samples.length; i++) samples[i] = bytes.getShort() / 32768.0f;
        return samples;
      }
    } catch (IOException | UnsupportedAudioFileException error) {
      return null;
    }
  }

  short[] makeClip(double duration, double toneHz, double toneLevel, double textureLevel,
                   double textureCutoff, int seed) {
    int length = (int)(SAMPLE_RATE * duration);
    short[] clip = new short[length];
    Random grains = new Random(seed);
    double lowPass = 1 - Math.exp(-2 * Math.PI * textureCutoff / SAMPLE_RATE);
    double smoothNoise = 0;
    for (int i = 0; i < length; i++) {
      double time = (double)i / SAMPLE_RATE;
      double phase = (double)i / (length - 1);
      double envelope = Math.min(1, time / 0.0025) * Math.pow(1 - phase, 1.8);
      double tone = Math.sin(2 * Math.PI * toneHz * time) +
        0.13 * Math.sin(2 * Math.PI * toneHz * 2.1 * time);
      smoothNoise += lowPass * (grains.nextDouble() * 2 - 1 - smoothNoise);
      clip[i] = (short)Math.round(32767 * envelope * (tone * toneLevel + smoothNoise * textureLevel));
    }
    return clip;
  }

  void stop() {
    if (player != null) player.interrupt();
  }
}

class ScratchMotion {
  final long time, sharpTurnAt;
  final double speed, turn, sharpness;
  final boolean erasing;

  ScratchMotion(long time, double speed, double turn, long sharpTurnAt, double sharpness, boolean erasing) {
    this.time = time;
    this.speed = speed;
    this.turn = turn;
    this.sharpTurnAt = sharpTurnAt;
    this.sharpness = sharpness;
    this.erasing = erasing;
  }
}

class ScratchGesture {
  static final double TURN_RECOVERY_SECONDS = 0.085;
  long lastMove, sharpTurnAt;
  double distance, seconds;
  double headingX, headingY, pendingX, pendingY, turn, sharpness;

  void reset(long time) {
    lastMove = time;
    sharpTurnAt = 0;
    distance = seconds = 0;
    headingX = headingY = pendingX = pendingY = turn = sharpness = 0;
  }

  ScratchMotion move(int dx, int dy, long eventMillis, long now, boolean erasing) {
    double elapsed = lastMove == 0 ? 0.016 : (eventMillis - lastMove) / 1000.0;
    if (elapsed < 0 || elapsed > 0.105) {
      reset(eventMillis);
      elapsed = 0.016;
    }
    lastMove = eventMillis;
    double dt = Math.max(seconds == 0 ? 0.006 : 0, Math.min(0.055, elapsed));
    double carry = Math.exp(-dt / 0.031);
    distance = distance * carry + Math.hypot(dx, dy);
    seconds = seconds * carry + dt;
    turn *= Math.exp(-dt / TURN_RECOVERY_SECONDS);

    // Measure heading across a few pixels so a stair-stepped diagonal doesn't register as a turn.
    pendingX += dx;
    pendingY += dy;
    double travel = Math.hypot(pendingX, pendingY);
    if (travel >= 3) {
      double x = pendingX / travel;
      double y = pendingY / travel;
      double alignment = headingX * x + headingY * y;
      if ((headingX != 0 || headingY != 0) && alignment < 0.74) {
        turn = Math.max(turn, Math.sqrt((0.74 - alignment) / 1.74));
        if (alignment < -0.62) {
          sharpTurnAt = now;
          sharpness = Math.min(1, (-alignment - 0.62) / 0.38);
        }
      } else {
        x += 1.4 * headingX;
        y += 1.4 * headingY;
      }
      double length = Math.hypot(x, y);
      headingX = x / length;
      headingY = y / length;
      pendingX = pendingY = 0;
    }

    return new ScratchMotion(now, distance / Math.max(0.006, seconds), turn, sharpTurnAt, sharpness, erasing);
  }
}

class ScratchVoice {
  final float[] recording;
  final int overlap;
  final Random texture;
  final double attack, soften, release, cornerAttack;
  final double silence = 0.0002;
  int phase;
  double gain, targetGain;
  double cornerGain, targetCornerGain, cornerLow;
  double gripGain, targetGripGain, gripLow;
  boolean unloading;
  double dark, eraserMix, targetEraserMix, fallbackBody, fallbackGrain;

  ScratchVoice(float[] recording, int rate, Random texture) {
    this.recording = recording;
    this.texture = texture;
    overlap = recording == null ? 0 : Math.min(rate / 20, recording.length / 4);
    attack = smoothing(0.011, rate);
    soften = smoothing(0.021, rate);
    release = smoothing(0.055, rate);
    cornerAttack = smoothing(0.006, rate);
  }

  double smoothing(double seconds, int rate) {
    return 1 - Math.exp(-1 / (seconds * rate));
  }

  void update(ScratchMotion motion, long now) {
    targetGain = 0;
    targetCornerGain = 0;
    targetGripGain = 0;
    unloading = false;
    if (motion == null) return;

    // Brief gaps between pointer events are normal. Fade a stationary stroke.
    double age = Math.max(0, (now - motion.time) / 1e9);
    double contact = Math.max(0, 1 - Math.max(0, age - 0.048) / 0.100);
    targetEraserMix = motion.erasing ? 1 : 0;
    double movementGain = (0.035 + 0.78 * motion.speed / (motion.speed + 350)) * contact;
    if (motion.erasing) movementGain *= 0.51;
    double pivot = motion.turn * Math.exp(-age / ScratchGesture.TURN_RECOVERY_SECONDS);
    targetGain = movementGain * (1 - 0.42 * pivot);
    targetCornerGain = movementGain * pivot * (motion.erasing ? 0.64 : 2.05);
    if (!motion.erasing && motion.sharpness > 0) {
      double sharpAge = Math.max(0, (now - motion.sharpTurnAt) / 1e9);
      // A near reversal briefly unloads the tip before it grips the paper again.
      double lift = motion.sharpness * Math.exp(-sharpAge / 0.014);
      unloading = lift > 0.18;
      targetGain *= 1 - 0.76 * lift;
      targetCornerGain *= 1 - 0.92 * lift;
      double recontact = Math.max(0, sharpAge - 0.009);
      double grip = motion.sharpness * (1 - Math.exp(-recontact / 0.008)) * Math.exp(-recontact / 0.037);
      targetGripGain = movementGain * grip * 1.55;
    }
    if (targetGain > silence && gain < silence) {
      if (recording != null) phase = texture.nextInt(recording.length - overlap);
      eraserMix = targetEraserMix;
      dark = cornerLow = gripLow = 0;
    }
  }

  boolean audible() {
    return targetGain > silence || gain > silence || targetCornerGain > silence || cornerGain > silence ||
      targetGripGain > silence || gripGain > silence;
  }

  double nextSample() {
    if (!audible()) return 0;
    double response = targetGain == 0 ? release : targetGain > gain ? attack : unloading ? cornerAttack : soften;
    gain += (targetGain - gain) * response;
    cornerGain += (targetCornerGain - cornerGain) * (targetCornerGain > cornerGain || unloading ? cornerAttack : soften);
    gripGain += (targetGripGain - gripGain) * (targetGripGain > gripGain ? cornerAttack : soften);
    eraserMix += (targetEraserMix - eraserMix) * attack;
    double paper = recording == null ? fallbackSample() : nextRecordingSample();
    dark += (paper - dark) * 0.20;
    // The pencil catches briefly on a turn. Bring out the rasp already present in the recording.
    cornerLow += (paper - cornerLow) * 0.15;
    gripLow += (cornerLow - gripLow) * 0.045;
    return gain * (paper + (dark - paper) * (0.72 * eraserMix)) +
      cornerGain * (paper - cornerLow) + gripGain * (cornerLow - gripLow);
  }

  double nextRecordingSample() {
    int fadeStart = recording.length - overlap;
    double value = recording[phase];
    if (phase >= fadeStart) {
      int offset = phase - fadeStart;
      double fade = (double)offset / overlap;
      value += (recording[offset] - value) * fade;
    }
    phase++;
    if (phase >= recording.length) phase -= fadeStart;
    return value;
  }

  double fallbackSample() {
    double noise = texture.nextDouble() * 2 - 1;
    fallbackBody += (noise - fallbackBody) * 0.08;
    fallbackGrain += (noise - fallbackGrain) * 0.35;
    return 0.25 * (fallbackGrain - fallbackBody);
  }

  void reset() {
    gain = 0;
    targetGain = 0;
    cornerGain = 0;
    targetCornerGain = 0;
    gripGain = 0;
    targetGripGain = 0;
  }
}
