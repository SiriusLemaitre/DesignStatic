class DrawingLayer {
  String name;
  boolean visible = true;
  PGraphics pixels;

  DrawingLayer(String name) {
    this.name = name;
  }

  void dispose() {
    if (pixels != null) pixels.dispose();
    pixels = null;
  }
}

class AnimationFrame {
  final ArrayList<DrawingLayer> layers = new ArrayList<DrawingLayer>();
  int selectedLayer;

  void dispose() {
    for (DrawingLayer layer : layers) layer.dispose();
  }
}

class Artwork {
  final int HISTORY_STEPS = 40;
  final long HISTORY_BYTES = 128L * 1024 * 1024;
  final ArrayDeque<ArtworkSnapshot> undo = new ArrayDeque<ArtworkSnapshot>();
  final ArrayDeque<ArtworkSnapshot> redo = new ArrayDeque<ArtworkSnapshot>();
  final ArrayList<AnimationFrame> frames = new ArrayList<AnimationFrame>();
  ArtworkSnapshot beforeEdit;
  long historyBytes;
  int selectedFrame;
  int fps = 8;
  boolean onionSkin;
  boolean playing;
  boolean dirty;
  long playbackStart;
  int playbackOrigin;
  AnimationFrame onionFrame;
  BufferedImage onionImage;
  final BufferedImage samplePixel = new BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB);

  Artwork() {
    AnimationFrame first = new AnimationFrame();
    first.layers.add(new DrawingLayer("Layer 1"));
    frames.add(first);
  }

  AnimationFrame currentFrame() {
    return frames.get(selectedFrame);
  }

  DrawingLayer activeLayer() {
    AnimationFrame frame = currentFrame();
    return frame.layers.get(frame.selectedLayer);
  }

  boolean canEdit() {
    return activeLayer().visible;
  }

  int visibleHeight() {
    return max(1, height - canvasTop());
  }

  void drawCanvas() {
    Graphics2D renderer = ((PGraphicsJava2D)g).g2;
    Graphics2D canvas = (Graphics2D) renderer.create(0, canvasTop(), width, visibleHeight());
    int frameIndex = displayedFrameIndex();
    if (onionSkin && !playing && frameIndex > 0) {
      AnimationFrame previous = frames.get(frameIndex - 1);
      if (onionFrame != previous || onionImage.getWidth() != width ||
          onionImage.getHeight() != visibleHeight()) {
        onionImage = composite(previous, false, width, visibleHeight());
        onionFrame = previous;
      }
      canvas.setComposite(AlphaComposite.SrcOver.derive(0.28f));
      canvas.drawImage(onionImage, 0, 0, null);
      canvas.setComposite(AlphaComposite.SrcOver);
    }
    drawLayers(canvas, frames.get(frameIndex), 0, 0);
    canvas.dispose();
  }

  void drawLayers(Graphics2D target, AnimationFrame frame, int x, int y) {
    for (DrawingLayer layer : frame.layers) {
      if (layer.visible && layer.pixels != null) {
        target.drawImage(layer.pixels.image, x, y, null);
      }
    }
  }

  BufferedImage composite(AnimationFrame frame, boolean opaque, int imageWidth, int imageHeight) {
    BufferedImage result = new BufferedImage(imageWidth, imageHeight, BufferedImage.TYPE_INT_ARGB);
    Graphics2D renderer = result.createGraphics();
    if (opaque) {
      renderer.setColor(new Color(state.bgColor));
      renderer.fillRect(0, 0, imageWidth, imageHeight);
    }
    drawLayers(renderer, frame, 0, 0);
    renderer.dispose();
    return result;
  }

  color sample(int x, int y) {
    if (x < 0 || x >= width || y < canvasTop() || y >= height) return state.bgColor;
    samplePixel.setRGB(0, 0, state.bgColor);
    Graphics2D renderer = samplePixel.createGraphics();
    drawLayers(renderer, currentFrame(), -x, canvasTop() - y);
    renderer.dispose();
    return samplePixel.getRGB(0, 0);
  }

  int displayedFrameIndex() {
    if (!playing) return selectedFrame;
    long elapsedFrames = (long)((System.nanoTime() - playbackStart) * (fps / 1000000000.0));
    return (int)((playbackOrigin + elapsedFrames) % frames.size());
  }

  void togglePlayback() {
    if (playing) {
      selectedFrame = displayedFrameIndex();
      stopPlayback();
    } else if (frames.size() > 1) {
      finishStroke();
      playbackOrigin = selectedFrame;
      playbackStart = System.nanoTime();
      playing = true;
    }
  }

  void stopPlayback() {
    playing = false;
  }

  void changeFps(int delta) {
    int nextFps = constrain(fps + delta, 1, 60);
    if (nextFps == fps) return;
    if (playing) {
      playbackOrigin = displayedFrameIndex();
      playbackStart = System.nanoTime();
    }
    fps = nextFps;
    dirty = true;
  }

  void selectFrame(int index) {
    if (index < 0 || index >= frames.size()) return;
    finishStroke();
    stopPlayback();
    selectedFrame = index;
  }

  void addFrame(boolean duplicate) {
    finishStroke();
    stopPlayback();
    AnimationFrame source = currentFrame();
    AnimationFrame added = new AnimationFrame();
    for (DrawingLayer original : source.layers) {
      DrawingLayer copy = new DrawingLayer(original.name);
      copy.visible = original.visible;
      if (duplicate && original.pixels != null) {
        copy.pixels = newLayerPixels(original.pixels.width, original.pixels.height, original.pixels.image);
      }
      added.layers.add(copy);
    }
    added.selectedLayer = source.selectedLayer;
    if (!duplicate) added.layers.get(added.selectedLayer).visible = true;
    frames.add(++selectedFrame, added);
    changed();
  }

  void deleteFrame() {
    if (frames.size() <= 1) return;
    finishStroke();
    stopPlayback();
    if (!confirmDelete("Delete frame " + (selectedFrame + 1) + "?")) return;
    AnimationFrame removed = frames.remove(selectedFrame);
    for (DrawingLayer layer : removed.layers) discardHistory(layer);
    removed.dispose();
    selectedFrame = min(selectedFrame, frames.size() - 1);
    changed();
  }

  void selectLayer(int index) {
    AnimationFrame frame = currentFrame();
    if (index < 0 || index >= frame.layers.size()) return;
    finishStroke();
    stopPlayback();
    frame.selectedLayer = index;
  }

  void addLayer() {
    finishStroke();
    stopPlayback();
    AnimationFrame frame = currentFrame();
    HashSet<String> names = new HashSet<String>();
    for (DrawingLayer layer : frame.layers) names.add(layer.name);
    int number = 1;
    while (names.contains("Layer " + number)) number++;
    frame.layers.add(++frame.selectedLayer, new DrawingLayer("Layer " + number));
    changed();
  }

  void renameLayer() {
    finishStroke();
    stopPlayback();
    DrawingLayer layer = activeLayer();
    String name = JOptionPane.showInputDialog(null, "Layer name", layer.name);
    if (name == null || name.trim().isEmpty()) return;
    name = name.trim();
    if (name.length() > 120) name = name.substring(0, 120);
    if (layer.name.equals(name)) return;
    layer.name = name;
    dirty = true;
  }

  void moveLayer(int direction) {
    AnimationFrame frame = currentFrame();
    int destination = frame.selectedLayer + direction;
    if (destination < 0 || destination >= frame.layers.size()) return;
    finishStroke();
    stopPlayback();
    Collections.swap(frame.layers, frame.selectedLayer, destination);
    frame.selectedLayer = destination;
    changed();
  }

  void toggleLayerVisibility() {
    finishStroke();
    stopPlayback();
    DrawingLayer layer = activeLayer();
    layer.visible = !layer.visible;
    changed();
  }

  void deleteLayer() {
    AnimationFrame frame = currentFrame();
    if (frame.layers.size() <= 1) return;
    finishStroke();
    stopPlayback();
    if (!confirmDelete("Delete layer “" + activeLayer().name + "”?")) return;
    DrawingLayer removed = frame.layers.remove(frame.selectedLayer);
    discardHistory(removed);
    removed.dispose();
    frame.selectedLayer = min(frame.selectedLayer, frame.layers.size() - 1);
    changed();
  }

  boolean confirmDelete(String message) {
    return JOptionPane.showConfirmDialog(null, message, "Design Static Pro",
      JOptionPane.OK_CANCEL_OPTION, JOptionPane.WARNING_MESSAGE) == JOptionPane.OK_OPTION;
  }

  void changed() {
    dirty = true;
    onionFrame = null;
    onionImage = null;
  }

  PGraphics newLayerPixels(int w, int h, java.awt.Image content) {
    PGraphics pixels = createGraphics(w, h, JAVA2D);
    pixels.noSmooth();
    pixels.beginDraw();
    pixels.clear();
    if (content != null) {
      Graphics2D renderer = ((PGraphicsJava2D)pixels).g2;
      renderer.setComposite(AlphaComposite.Src);
      renderer.drawImage(content, 0, 0, null);
    }
    pixels.endDraw();
    return pixels;
  }

  PGraphics ensureSize(DrawingLayer layer) {
    PGraphics previous = layer.pixels;
    if (previous != null && previous.width >= width && previous.height >= visibleHeight()) return previous;
    int w = previous == null ? width : max(previous.width, width);
    int h = previous == null ? visibleHeight() : max(previous.height, visibleHeight());
    layer.pixels = newLayerPixels(w, h, previous == null ? null : previous.image);
    if (previous != null) previous.dispose();
    return layer.pixels;
  }

  void beginStroke() {
    PGraphics pixels = ensureSize(activeLayer());
    pixels.beginDraw();
    pixels.clip(0, 0, width, visibleHeight());
    pixels.translate(0, -canvasTop());
    applyBrushBlend((PGraphicsJava2D)pixels);
  }

  void endStroke() {
    PGraphics pixels = activeLayer().pixels;
    pixels.noClip();
    pixels.endDraw();
  }

  void clear(boolean useBackgroundImage) {
    if (activeLayer().pixels == null && !useBackgroundImage) return;
    PGraphics pixels = ensureSize(activeLayer());
    pixels.beginDraw();
    pixels.clear();
    if (useBackgroundImage) {
      pixels.blendMode(BLEND);
      pixels.noTint();
      pixels.image(backgroundImage, 0, 0);
    }
    pixels.endDraw();
  }

  void importImage(PImage imported) {
    finishStroke();
    stopPlayback();
    if (!canEdit()) {
      JOptionPane.showMessageDialog(null, "Show the active layer before importing an image.");
      return;
    }
    beginEdit();
    PGraphics pixels = ensureSize(activeLayer());
    pixels.beginDraw();
    pixels.blendMode(BLEND);
    pixels.noTint();
    pixels.clip(0, 0, width, visibleHeight());
    pixels.image(imported, (width - imported.width) / 2, (visibleHeight() - imported.height) / 2);
    pixels.noClip();
    pixels.endDraw();
    state.isBgImageActive = false;
    commitEdit();
    dirty = true;
    ui.showFileMessage("Image loaded");
  }

  void beginEdit() {
    beforeEdit = new ArtworkSnapshot(currentFrame(), activeLayer());
  }

  void commitEdit() {
    ArtworkSnapshot previous = beforeEdit;
    beforeEdit = null;
    if (previous == null) return;
    previous.restoreBackground = previous.backgroundColor != state.bgColor;
    if (!previous.restoreBackground && !previous.differsFromLayer()) return;
    while (!redo.isEmpty()) historyBytes -= redo.removeLast().byteSize();
    remember(undo, previous);
    changed();
  }

  void stepHistory(boolean forward) {
    ArrayDeque<ArtworkSnapshot> source = forward ? redo : undo;
    if (source.isEmpty()) return;
    ArtworkSnapshot target = source.removeLast();
    historyBytes -= target.byteSize();
    ArtworkSnapshot inverse = new ArtworkSnapshot(target.frame, target.layer);
    inverse.restoreBackground = target.restoreBackground;
    remember(forward ? undo : redo, inverse);
    selectedFrame = frames.indexOf(target.frame);
    target.frame.selectedLayer = target.frame.layers.indexOf(target.layer);
    if (target.restoreBackground) state.bgColor = target.backgroundColor;
    target.restorePixels();
    changed();
    sounds.play(SoundCue.CLICK);
  }

  void remember(ArrayDeque<ArtworkSnapshot> stack, ArtworkSnapshot snapshot) {
    stack.addLast(snapshot);
    historyBytes += snapshot.byteSize();
    while (undo.size() + redo.size() > HISTORY_STEPS ||
           (historyBytes > HISTORY_BYTES && undo.size() + redo.size() > 1)) {
      ArrayDeque<ArtworkSnapshot> oldest = undo.size() > 1 || stack == redo && !undo.isEmpty() ? undo : redo;
      historyBytes -= oldest.removeFirst().byteSize();
    }
  }

  void discardHistory(DrawingLayer layer) {
    undo.removeIf(snapshot -> discardSnapshot(snapshot, layer));
    redo.removeIf(snapshot -> discardSnapshot(snapshot, layer));
  }

  boolean discardSnapshot(ArtworkSnapshot snapshot, DrawingLayer layer) {
    if (snapshot.layer != layer) return false;
    historyBytes -= snapshot.byteSize();
    return true;
  }
}

class ArtworkSnapshot {
  final AnimationFrame frame;
  final DrawingLayer layer;
  final PImage pixels;
  final color backgroundColor;
  boolean restoreBackground;

  ArtworkSnapshot(AnimationFrame frame, DrawingLayer layer) {
    this.frame = frame;
    this.layer = layer;
    pixels = layer.pixels == null ? null : layer.pixels.get();
    backgroundColor = state.bgColor;
  }

  long byteSize() {
    return pixels == null ? 0 : (long)pixels.width * pixels.height * Integer.BYTES;
  }

  boolean differsFromLayer() {
    PGraphics current = layer.pixels;
    if (current == null) return pixels != null;
    if (pixels != null && current.width == pixels.width && current.height == pixels.height) {
      return !Arrays.equals(current.pixels, pixels.pixels);
    }
    for (int y = 0; y < current.height; y++) {
      for (int x = 0; x < current.width; x++) {
        color previous = pixels != null && x < pixels.width && y < pixels.height
          ? pixels.pixels[y * pixels.width + x] : 0;
        if (current.pixels[y * current.width + x] != previous) return true;
      }
    }
    return false;
  }

  void restorePixels() {
    layer.dispose();
    if (pixels != null) {
      layer.pixels = artwork.newLayerPixels(pixels.width, pixels.height, null);
      layer.pixels.beginDraw();
      layer.pixels.set(0, 0, pixels);
      layer.pixels.endDraw();
    }
  }
}
