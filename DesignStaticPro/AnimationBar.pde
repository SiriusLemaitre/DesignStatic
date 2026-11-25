class AnimationBar {
  final int FRAME_Y = ANIMATION_TOP + 5;
  final int LAYER_Y = ANIMATION_TOP + 37;
  final int FRAME_SLOTS = 5;

  void display() {
    pushStyle();
    fill(246);
    stroke(0);
    strokeWeight(1);
    rect(0, ANIMATION_TOP, width, EXPANDED_CANVAS_TOP - ANIMATION_TOP - 1);
    line(0, ANIMATION_TOP + 31, width, ANIMATION_TOP + 31);
    fill(0);
    textAlign(LEFT, CENTER);
    textSize(11);
    text("Frames", 8, FRAME_Y + BAR_BUTTON_HEIGHT / 2);
    text("Layers", 8, LAYER_Y + BAR_BUTTON_HEIGHT / 2);
    controls(false);
    popStyle();
  }

  void press() {
    state.isWritingHex = false;
    controls(true);
  }

  void controls(boolean clicking) {
    int shownFrame = artwork.displayedFrameIndex();
    int frameCount = artwork.frames.size();
    boolean editing = !artwork.playing;
    int firstSlot = (shownFrame / FRAME_SLOTS) * FRAME_SLOTS;
    if (barButton(clicking, 59, FRAME_Y, 18, "<", shownFrame > 0, false)) {
      artwork.selectFrame(shownFrame - 1);
      return;
    }
    for (int slot = 0; slot < FRAME_SLOTS; slot++) {
      int index = firstSlot + slot;
      if (index >= frameCount) break;
      if (barButton(clicking, 81 + slot * 32, FRAME_Y, 29, str(index + 1), true, index == shownFrame)) {
        artwork.selectFrame(index);
        return;
      }
    }
    if (barButton(clicking, 242, FRAME_Y, 18, ">", shownFrame + 1 < frameCount, false)) {
      artwork.selectFrame(shownFrame + 1);
      return;
    }
    if (barButton(clicking, 268, FRAME_Y, 33, "Add", editing, false)) artwork.addFrame(false);
    if (barButton(clicking, 305, FRAME_Y, 33, "Copy", editing, false)) artwork.addFrame(true);
    if (barButton(clicking, 342, FRAME_Y, 42, "Delete", editing && frameCount > 1, false)) artwork.deleteFrame();
    if (barButton(clicking, 393, FRAME_Y, 39, artwork.playing ? "Stop" : "Play", frameCount > 1, artwork.playing)) {
      artwork.togglePlayback();
    }
    if (barButton(clicking, 440, FRAME_Y, 16, "-", artwork.fps > 1, false)) artwork.changeFps(-1);
    if (!clicking) {
      fill(0);
      textSize(10);
      textAlign(CENTER, CENTER);
      text(artwork.fps + " fps", 479, FRAME_Y + BAR_BUTTON_HEIGHT / 2);
    }
    if (barButton(clicking, 501, FRAME_Y, 16, "+", artwork.fps < 60, false)) artwork.changeFps(1);
    if (barButton(clicking, 525, FRAME_Y, 66, "Onion skin", true, artwork.onionSkin)) {
      artwork.onionSkin = !artwork.onionSkin;
      artwork.changed();
    }

    AnimationFrame frame = artwork.frames.get(artwork.displayedFrameIndex());
    int index = frame.selectedLayer;
    int layerCount = frame.layers.size();
    DrawingLayer layer = frame.layers.get(index);
    if (barButton(clicking, 59, LAYER_Y, 18, "<", editing && index > 0, false)) artwork.selectLayer(index - 1);
    if (barButton(clicking, 81, LAYER_Y, 139, (index + 1) + "/" + layerCount + "  " + layer.name, editing, true)) {
      artwork.renameLayer();
    }
    if (barButton(clicking, 224, LAYER_Y, 18, ">", editing && index + 1 < layerCount, false)) artwork.selectLayer(index + 1);
    if (barButton(clicking, 250, LAYER_Y, 33, "Add", editing, false)) artwork.addLayer();
    if (barButton(clicking, 287, LAYER_Y, 37, layer.visible ? "Hide" : "Show", editing, !layer.visible)) artwork.toggleLayerVisibility();
    if (barButton(clicking, 328, LAYER_Y, 40, "Raise", editing && index + 1 < layerCount, false)) artwork.moveLayer(1);
    if (barButton(clicking, 372, LAYER_Y, 42, "Lower", editing && index > 0, false)) artwork.moveLayer(-1);
    if (barButton(clicking, 418, LAYER_Y, 42, "Delete", editing && layerCount > 1, false)) artwork.deleteLayer();
    if (barButton(clicking, 468, LAYER_Y, 60, "Save project", true, false)) projectFiles.selectSave();
    if (barButton(clicking, 532, LAYER_Y, 65, "Open project", true, false)) projectFiles.selectLoad();
  }
}
