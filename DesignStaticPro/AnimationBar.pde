class AnimationBar {
  final int FRAME_Y = UI_HEIGHT + 5;
  final int LAYER_Y = UI_HEIGHT + 37;
  final int BUTTON_H = 22;
  final int FRAME_SLOTS = 5;

  void display() {
    pushStyle();
    fill(246);
    stroke(0);
    strokeWeight(1);
    rect(0, UI_HEIGHT, width, CANVAS_TOP - UI_HEIGHT - 1);
    line(0, UI_HEIGHT + 31, width, UI_HEIGHT + 31);
    fill(0);
    textAlign(LEFT, CENTER);
    textSize(11);
    text("Frames", 8, FRAME_Y + BUTTON_H / 2);
    text("Layers", 8, LAYER_Y + BUTTON_H / 2);
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
    if (button(clicking, 59, FRAME_Y, 18, "<", shownFrame > 0, false)) {
      artwork.selectFrame(shownFrame - 1);
      return;
    }
    for (int slot = 0; slot < FRAME_SLOTS; slot++) {
      int index = firstSlot + slot;
      if (index >= frameCount) break;
      if (button(clicking, 81 + slot * 32, FRAME_Y, 29, str(index + 1), true, index == shownFrame)) {
        artwork.selectFrame(index);
        return;
      }
    }
    if (button(clicking, 242, FRAME_Y, 18, ">", shownFrame + 1 < frameCount, false)) {
      artwork.selectFrame(shownFrame + 1);
      return;
    }
    if (button(clicking, 268, FRAME_Y, 33, "Add", editing, false)) artwork.addFrame(false);
    if (button(clicking, 305, FRAME_Y, 33, "Copy", editing, false)) artwork.addFrame(true);
    if (button(clicking, 342, FRAME_Y, 42, "Delete", editing && frameCount > 1, false)) artwork.deleteFrame();
    if (button(clicking, 393, FRAME_Y, 39, artwork.playing ? "Stop" : "Play", frameCount > 1, artwork.playing)) {
      artwork.togglePlayback();
    }
    if (button(clicking, 440, FRAME_Y, 16, "-", artwork.fps > 1, false)) artwork.changeFps(-1);
    if (!clicking) {
      fill(0);
      textSize(10);
      textAlign(CENTER, CENTER);
      text(artwork.fps + " fps", 479, FRAME_Y + BUTTON_H / 2);
    }
    if (button(clicking, 501, FRAME_Y, 16, "+", artwork.fps < 60, false)) artwork.changeFps(1);
    if (button(clicking, 525, FRAME_Y, 66, "Onion skin", true, artwork.onionSkin)) {
      artwork.onionSkin = !artwork.onionSkin;
      artwork.changed();
    }

    AnimationFrame frame = artwork.frames.get(artwork.displayedFrameIndex());
    int index = frame.selectedLayer;
    int layerCount = frame.layers.size();
    DrawingLayer layer = frame.layers.get(index);
    if (button(clicking, 59, LAYER_Y, 18, "<", editing && index > 0, false)) artwork.selectLayer(index - 1);
    if (button(clicking, 81, LAYER_Y, 139, (index + 1) + "/" + layerCount + "  " + layer.name, editing, true)) {
      artwork.renameLayer();
    }
    if (button(clicking, 224, LAYER_Y, 18, ">", editing && index + 1 < layerCount, false)) artwork.selectLayer(index + 1);
    if (button(clicking, 250, LAYER_Y, 33, "Add", editing, false)) artwork.addLayer();
    if (button(clicking, 287, LAYER_Y, 37, layer.visible ? "Hide" : "Show", editing, !layer.visible)) artwork.toggleLayerVisibility();
    if (button(clicking, 328, LAYER_Y, 40, "Raise", editing && index + 1 < layerCount, false)) artwork.moveLayer(1);
    if (button(clicking, 372, LAYER_Y, 42, "Lower", editing && index > 0, false)) artwork.moveLayer(-1);
    if (button(clicking, 418, LAYER_Y, 42, "Delete", editing && layerCount > 1, false)) artwork.deleteLayer();
    if (button(clicking, 468, LAYER_Y, 60, "Save project", true, false)) projectFiles.selectSave();
    if (button(clicking, 532, LAYER_Y, 65, "Open project", true, false)) projectFiles.selectLoad();
  }

  boolean button(boolean clicking, int x, int y, int w, String label, boolean enabled, boolean selected) {
    boolean hovered = !picker.open && mouseX >= x && mouseX < x + w &&
      mouseY >= y && mouseY < y + BUTTON_H;
    if (clicking) return enabled && hovered;

    stroke(0);
    fill(!enabled ? 185 : selected ? 100 : hovered ? 145 : 0);
    rect(x, y, w, BUTTON_H);
    fill(!enabled ? 55 : 255);
    textAlign(CENTER, CENTER);
    textSize(10);
    if (textWidth(label) > w - 6) {
      int length = label.length();
      while (length > 0 && textWidth(label.substring(0, length) + "…") > w - 6) length--;
      label = label.substring(0, length) + "…";
    }
    text(label, x + w / 2.0f, y + BUTTON_H / 2);
    return false;
  }
}
