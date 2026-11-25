final int BAR_BUTTON_HEIGHT = 22;

boolean barButton(boolean clicking, int x, int y, int w, String label, boolean enabled, boolean selected) {
  boolean hovered = !picker.open && mouseX >= x && mouseX < x + w &&
    mouseY >= y && mouseY < y + BAR_BUTTON_HEIGHT;
  if (clicking) {
    boolean pressed = enabled && hovered;
    if (pressed) sounds.play(SoundCue.CLICK);
    return pressed;
  }

  stroke(0);
  fill(!enabled ? 185 : selected ? 100 : hovered ? 145 : 0);
  rect(x, y, w, BAR_BUTTON_HEIGHT);
  fill(!enabled ? 55 : 255);
  textAlign(CENTER, CENTER);
  textSize(10);
  if (textWidth(label) > w - 6) {
    int length = label.length();
    while (length > 0 && textWidth(label.substring(0, length) + "…") > w - 6) length--;
    label = label.substring(0, length) + "…";
  }
  text(label, x + w / 2.0f, y + BAR_BUTTON_HEIGHT / 2);
  return false;
}

enum ToolSlider { NONE, SIZE, OPACITY }

class ToolControls {
  final int Y = UI_HEIGHT + 5;
  final int SIZE_X = 277, OPACITY_X = 367, SLIDER_WIDTH = 85;
  final String[] toolNames = {"Pen", "Fill", "Design", "Rect", "Chemistry", "Eraser", "Image pen"};
  final String[][] modeNames = {
    {"Smooth", "Line", "Sketchy", "Dot", "Paper pencil"},
    {"Fan", "Scatter", "Fine", "Splash"},
    {"Cross", "Diagonal", "Sewing"},
    {"Outline", "Corner", "Top/left", "Sides"},
    {"Streak", "Scratch", "Bezier", "Gradient"},
    {},
    {}
  };
  final String[] blendNames = {"Normal", "Add", "Subtract", "Darkest", "Lightest",
    "Difference", "Exclusion", "Multiply", "Screen", "Replace"};
  ToolSlider activeSlider = ToolSlider.NONE;

  void display() {
    pushStyle();
    fill(246);
    stroke(0);
    strokeWeight(1);
    rect(0, UI_HEIGHT, width, TOOL_BAR_HEIGHT - 1);
    label(toolNames[state.currentTool.ordinal()], 8, LEFT);
    controls(false);
    popStyle();
  }

  void press() {
    finishStroke();
    state.isWritingHex = false;
    if (overSlider(SIZE_X) && maximumSize() > 0) {
      activeSlider = ToolSlider.SIZE;
    } else if (overSlider(OPACITY_X) && state.currentTool != ToolType.ERASER) {
      activeSlider = ToolSlider.OPACITY;
    }
    if (activeSlider == ToolSlider.NONE) {
      controls(true);
    } else {
      sounds.play(SoundCue.CLICK);
      dragSlider(false);
    }
  }

  boolean overSlider(int x) {
    return mouseX >= x && mouseX < x + SLIDER_WIDTH && mouseY >= Y && mouseY < Y + BAR_BUTTON_HEIGHT;
  }

  boolean drag() {
    if (activeSlider == ToolSlider.NONE) return false;
    dragSlider(true);
    return true;
  }

  void dragSlider(boolean feedback) {
    float previous = activeSlider == ToolSlider.SIZE ? brushSize() : state.penOpacity;
    if (activeSlider == ToolSlider.SIZE) {
      setBrushSize(round(lerp(1, maximumSize(), sliderFraction(SIZE_X))));
    } else {
      int opacity = round(255 * sliderFraction(OPACITY_X));
      if (opacity != state.penOpacity) {
        state.penOpacity = opacity;
        artwork.dirty = true;
      }
    }
    float current = activeSlider == ToolSlider.SIZE ? brushSize() : state.penOpacity;
    if (feedback && current != previous) sounds.adjustment();
  }

  float sliderFraction(int x) {
    return constrain((mouseX - x - 1) / (SLIDER_WIDTH - 3.0f), 0, 1);
  }

  void stopDrag() {
    activeSlider = ToolSlider.NONE;
  }

  void controls(boolean clicking) {
    String[] modes = modeNames[state.currentTool.ordinal()];
    int currentMode = state.subToolMode;
    for (int slot = 0; slot < modes.length; slot++) {
      int mode = slot + 1;
      if (barButton(clicking, 65 + slot * 24, Y, 21, str(mode), true, mode == currentMode)) {
        if (state.subToolMode != mode) artwork.dirty = true;
        state.subToolMode = mode;
        return;
      }
    }
    boolean chemistryVariant = state.currentTool == ToolType.CHEMISTRY && (currentMode == 1 || currentMode == 4);
    if (chemistryVariant) {
      String variant = currentMode == 1 ? "Streak " + state.chemistrySwitchR : state.switchS ? "Gradient V" : "Gradient H";
      if (barButton(clicking, 190, Y, 82, variant, true, false)) state.cycleChemistryVariant();
    } else if (!clicking && currentMode <= modes.length) {
      label(modes[currentMode - 1], 190, LEFT);
    }

    if (!clicking && maximumSize() > 0) {
      float size = brushSize();
      drawSlider(SIZE_X, "Size " + round(size), norm(size, 1, maximumSize()));
    }
    if (!clicking && state.currentTool != ToolType.ERASER) {
      float opacity = state.penOpacity / 255.0f;
      drawSlider(OPACITY_X, "Opacity " + round(opacity * 100) + "%", opacity);
    }
    if (state.currentTool == ToolType.ERASER) return;
    if (barButton(clicking, 467, Y, 16, "<", true, false)) state.cycleBlend(-1);
    if (!clicking) label("Blend " + blendNames[state.blendModeIndex], 531, CENTER);
    if (barButton(clicking, 579, Y, 16, ">", true, false)) state.cycleBlend(1);
  }

  void label(String title, int x, int alignment) {
    fill(0);
    textSize(10);
    textAlign(alignment, CENTER);
    text(title, x, Y + BAR_BUTTON_HEIGHT / 2);
  }

  void drawSlider(int x, String title, float fraction) {
    stroke(0);
    fill(255);
    rect(x, Y, SLIDER_WIDTH, BAR_BUTTON_HEIGHT);
    noStroke();
    fill(210);
    rect(x + 1, Y + 1, (SLIDER_WIDTH - 1) * constrain(fraction, 0, 1), BAR_BUTTON_HEIGHT - 1);
    label(title, x + SLIDER_WIDTH / 2, CENTER);
  }

  float brushSize() {
    switch (state.currentTool) {
      case PEN: return state.penSize;
      case ERASER: return state.eraserSize;
      case RECT: return state.rectSize;
      case FILL:
        if (state.subToolMode == 4) return state.splashWidth;
        return state.penSize;
      case CHEMISTRY: return state.subToolMode == 3 ? state.bezierWeight : 0;
      default: return 0;
    }
  }

  int maximumSize() {
    switch (state.currentTool) {
      case ERASER: return 100;
      case RECT: return 104;
      case CHEMISTRY: return state.subToolMode == 3 ? 27 : 0;
      case FILL: return state.subToolMode == 4 ? 102 : 32;
      case PEN: return 32;
      default: return 0;
    }
  }

  void adjustSize(int delta) {
    float previous = brushSize();
    setBrushSize(previous + delta);
    if (brushSize() != previous) sounds.adjustment();
  }

  void setBrushSize(float requestedSize) {
    int maximum = maximumSize();
    if (maximum == 0) return;
    float size = constrain(requestedSize, 1, maximum);
    if (size == brushSize()) return;
    artwork.dirty = true;
    switch (state.currentTool) {
      case PEN: state.penSize = size; break;
      case ERASER: state.eraserSize = size; break;
      case RECT: state.rectSize = size; break;
      case CHEMISTRY: state.bezierWeight = size; break;
      case FILL:
        if (state.subToolMode == 4) state.splashWidth = size;
        else state.penSize = size;
        break;
    }
  }
}
