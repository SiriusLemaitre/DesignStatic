class ColorPicker {
  final int X = 8, Y = 55, WIDTH = 584, HEIGHT = 261;
  final int PANEL_WIDTH = WIDTH / 2;
  final int FIELD_X = 12, FIELD_Y = Y + 32, FIELD_WIDTH = 216, FIELD_HEIGHT = 144;
  final int HUE_X = 238, HUE_WIDTH = 17;
  final int HEX_Y = Y + 186, HEX_WIDTH = 83, HEX_HEIGHT = 23;
  final int ALPHA_X = X + 55, ALPHA_Y = Y + 216, ALPHA_WIDTH = 200, ALPHA_HEIGHT = 12;
  final int CANCEL_X = X + 421, DONE_X = X + 500;
  final int BUTTON_Y = Y + 233, BUTTON_WIDTH = 74, BUTTON_HEIGHT = 21;
  final int NO_DRAG = 0, FIELD_DRAG = 1, HUE_DRAG = 2, ALPHA_DRAG = 3;
  final ColorEditor pen = new ColorEditor(X, "Pen color", false);
  final ColorEditor backdrop = new ColorEditor(X + PANEL_WIDTH, "Background color", true);
  boolean open;
  boolean replaceHex;
  int originalOpacity;
  int dragTarget;
  ColorEditor dragging;
  ColorEditor hexFocus;
  PImage hueBar;

  void show() {
    sounds.play(SoundCue.CLICK);
    finishStroke();
    artwork.beginEdit();
    open = true;
    hexFocus = null;
    stopDrag();
    originalOpacity = state.penOpacity;
    pen.reset();
    backdrop.reset();
    if (hueBar != null) return;

    hueBar = createImage(HUE_WIDTH, FIELD_HEIGHT, RGB);
    hueBar.loadPixels();
    for (int y = 0; y < FIELD_HEIGHT; y++) {
      int rgb = Color.HSBtoRGB(y / (FIELD_HEIGHT - 1.0f), 1, 1);
      Arrays.fill(hueBar.pixels, y * HUE_WIDTH, (y + 1) * HUE_WIDTH, rgb);
    }
    hueBar.updatePixels();
  }

  void display() {
    pushMatrix();
    translate(X, Y);
    scale(pickerScale());
    translate(-X, -Y);
    pushStyle();
    strokeWeight(1);
    stroke(0);
    fill(246);
    rect(X, Y, WIDTH, HEIGHT);
    line(X + PANEL_WIDTH, Y, X + PANEL_WIDTH, BUTTON_Y - 5);
    pen.display();
    backdrop.display();
    drawAlphaSlider();
    drawButton(CANCEL_X, "Cancel");
    drawButton(DONE_X, "Done");
    popStyle();
    popMatrix();
  }

  void drawAlphaSlider() {
    drawCheckerboard(ALPHA_X, ALPHA_Y, ALPHA_WIDTH, ALPHA_HEIGHT);
    for (int x = 0; x < ALPHA_WIDTH; x++) {
      stroke(state.penColor, x * 255.0f / (ALPHA_WIDTH - 1));
      line(ALPHA_X + x, ALPHA_Y, ALPHA_X + x, ALPHA_Y + ALPHA_HEIGHT - 1);
    }
    noFill();
    stroke(0);
    rect(ALPHA_X - 1, ALPHA_Y - 1, ALPHA_WIDTH + 1, ALPHA_HEIGHT + 1);
    float markerX = ALPHA_X + state.penOpacity * (ALPHA_WIDTH - 1) / 255.0f;
    rect(markerX - 2, ALPHA_Y - 2, 4, ALPHA_HEIGHT + 3);
    stroke(255);
    line(markerX, ALPHA_Y - 1, markerX, ALPHA_Y + ALPHA_HEIGHT);
    fill(0);
    textSize(12);
    text("Alpha", X + FIELD_X, ALPHA_Y + 10);
    text(str(state.penOpacity), ALPHA_X + ALPHA_WIDTH + 7, ALPHA_Y + 10);
  }

  void drawCheckerboard(int x, int y, int w, int h) {
    int tile = 6;
    noStroke();
    for (int row = 0; row < h; row += tile) {
      for (int col = 0; col < w; col += tile) {
        fill((row / tile + col / tile) % 2 == 0 ? 255 : 190);
        rect(x + col, y + row, min(tile, w - col), min(tile, h - row));
      }
    }
  }

  void drawButton(int x, String title) {
    fill(over(x, BUTTON_Y, BUTTON_WIDTH, BUTTON_HEIGHT) ? 220 : 255);
    stroke(0);
    rect(x, BUTTON_Y, BUTTON_WIDTH, BUTTON_HEIGHT);
    fill(0);
    textAlign(CENTER);
    text(title, x + BUTTON_WIDTH / 2, BUTTON_Y + 15);
    textAlign(LEFT);
  }

  float pickerScale() {
    return min(1.0f, (height - Y - 4.0f) / HEIGHT);
  }

  float pickerMouseX() {
    return X + (mouseX - X) / pickerScale();
  }

  float pickerMouseY() {
    return Y + (mouseY - Y) / pickerScale();
  }

  boolean over(int x, int y, int w, int h) {
    float cursorX = pickerMouseX();
    float cursorY = pickerMouseY();
    return cursorX >= x && cursorX < x + w && cursorY >= y && cursorY < y + h;
  }

  void press() {
    if (!over(X, Y, WIDTH, HEIGHT) || over(DONE_X, BUTTON_Y, BUTTON_WIDTH, BUTTON_HEIGHT)) {
      close(false);
    } else if (over(CANCEL_X, BUTTON_Y, BUTTON_WIDTH, BUTTON_HEIGHT)) {
      close(true);
    } else if (over(ALPHA_X - 2, ALPHA_Y - 2, ALPHA_WIDTH + 4, ALPHA_HEIGHT + 4)) {
      sounds.play(SoundCue.CLICK);
      dragTarget = ALPHA_DRAG;
      updateDrag(false);
    } else {
      ColorEditor panel = pickerMouseX() < backdrop.x ? pen : backdrop;
      if (over(panel.x + FIELD_X, HEX_Y, HEX_WIDTH, HEX_HEIGHT)) {
        sounds.play(SoundCue.CLICK);
        hexFocus = panel;
        replaceHex = true;
      } else if (over(panel.x + FIELD_X, FIELD_Y, FIELD_WIDTH, FIELD_HEIGHT)) {
        sounds.play(SoundCue.CLICK);
        dragging = panel;
        dragTarget = FIELD_DRAG;
        updateDrag(false);
      } else if (over(panel.x + HUE_X, FIELD_Y, HUE_WIDTH, FIELD_HEIGHT)) {
        sounds.play(SoundCue.CLICK);
        dragging = panel;
        dragTarget = HUE_DRAG;
        updateDrag(false);
      }
    }
  }

  void drag() {
    updateDrag(true);
  }

  void updateDrag(boolean feedback) {
    if (dragTarget == NO_DRAG) return;
    if (dragTarget == ALPHA_DRAG) {
      int previous = state.penOpacity;
      state.penOpacity = constrain(round((pickerMouseX() - ALPHA_X) * 255.0f / (ALPHA_WIDTH - 1)), 0, 255);
      if (feedback && state.penOpacity != previous) sounds.adjustment();
    } else {
      color previous = dragging.currentColor();
      float vertical = constrain((pickerMouseY() - FIELD_Y) / (FIELD_HEIGHT - 1.0f), 0, 1);
      if (dragTarget == FIELD_DRAG) {
        dragging.saturation = constrain((pickerMouseX() - dragging.x - FIELD_X) / (FIELD_WIDTH - 1.0f), 0, 1);
        dragging.brightness = 1 - vertical;
      } else {
        dragging.hue = vertical;
      }
      dragging.setColor(Color.HSBtoRGB(dragging.hue, dragging.saturation, dragging.brightness));
      dragging.hexValue = hex(dragging.currentColor(), 6);
      if (feedback && dragging.currentColor() != previous) sounds.adjustment();
    }
    hexFocus = null;
  }

  void stopDrag() {
    dragTarget = NO_DRAG;
    dragging = null;
  }

  void pressKey(KeyEvent event) {
    if (key == ESC) {
      key = 0;
      close(true);
    } else if (key == ENTER || key == RETURN) {
      close(false);
    } else if (hexFocus != null && (event.isControlDown() || event.isMetaDown()) &&
               keyCode == java.awt.event.KeyEvent.VK_A) {
      replaceHex = true;
    } else if (hexFocus != null && (key == BACKSPACE || key == DELETE)) {
      String value = hexFocus.hexValue;
      hexFocus.hexValue = replaceHex || value.isEmpty() ? "" : value.substring(0, value.length() - 1);
      replaceHex = false;
    }
  }

  void typeKey(char typed) {
    if (hexFocus == null || !isHexDigit(typed)) return;
    if (replaceHex) {
      hexFocus.hexValue = "";
      replaceHex = false;
    }
    if (hexFocus.hexValue.length() < 6) hexFocus.hexValue += typed;
    if (hexFocus.hexValue.length() == 6) {
      hexFocus.setColor(unhex(hexFocus.hexValue));
      hexFocus.setFromColor(hexFocus.currentColor());
    }
  }

  void close(boolean cancel) {
    sounds.play(SoundCue.CLICK);
    if (cancel) {
      pen.setColor(pen.originalColor);
      backdrop.setColor(backdrop.originalColor);
      state.penOpacity = originalOpacity;
    }
    if (state.penColor != pen.originalColor || state.penOpacity != originalOpacity) artwork.dirty = true;
    artwork.commitEdit();
    stopDrag();
    open = false;
  }

  class ColorEditor {
    final int x;
    final String title;
    final boolean background;
    float hue, saturation, brightness;
    float renderedHue = -1;
    color originalColor;
    String hexValue;
    PImage field;

    ColorEditor(int x, String title, boolean background) {
      this.x = x;
      this.title = title;
      this.background = background;
    }

    color currentColor() {
      return background ? state.bgColor : state.penColor;
    }

    void setColor(color value) {
      if (background) state.bgColor = value | 0xff000000;
      else state.setPenColor(value);
    }

    void reset() {
      originalColor = currentColor();
      hexValue = hex(originalColor, 6);
      setFromColor(originalColor);
      if (field == null) field = createImage(FIELD_WIDTH, FIELD_HEIGHT, RGB);
    }

    void setFromColor(color value) {
      float[] hsb = Color.RGBtoHSB((value >> 16) & 255, (value >> 8) & 255, value & 255, null);
      hue = hsb[0];
      saturation = hsb[1];
      brightness = hsb[2];
    }

    void updateField() {
      if (hue == renderedHue) return;
      field.loadPixels();
      for (int row = 0; row < FIELD_HEIGHT; row++) {
        float value = 1 - row / (FIELD_HEIGHT - 1.0f);
        for (int col = 0; col < FIELD_WIDTH; col++) {
          field.pixels[row * FIELD_WIDTH + col] = Color.HSBtoRGB(hue, col / (FIELD_WIDTH - 1.0f), value);
        }
      }
      field.updatePixels();
      renderedHue = hue;
    }

    void display() {
      updateField();
      int fieldX = x + FIELD_X;
      int hueX = x + HUE_X;
      fill(0);
      textSize(15);
      text(title, fieldX, Y + 21);
      image(field, fieldX, FIELD_Y);
      image(hueBar, hueX, FIELD_Y);

      float pointX = fieldX + saturation * (FIELD_WIDTH - 1);
      float pointY = FIELD_Y + (1 - brightness) * (FIELD_HEIGHT - 1);
      noFill();
      stroke(0);
      circle(pointX, pointY, 11);
      stroke(255);
      circle(pointX, pointY, 9);
      float hueY = FIELD_Y + hue * (FIELD_HEIGHT - 1);
      stroke(0);
      rect(hueX - 2, hueY - 2, HUE_WIDTH + 3, 4);
      stroke(255);
      line(hueX, hueY, hueX + HUE_WIDTH - 1, hueY);

      int swatchX = x + 264;
      color preview = currentColor();
      drawSwatch(swatchX, FIELD_Y, originalColor, background ? 255 : originalOpacity);
      drawSwatch(swatchX, FIELD_Y + FIELD_HEIGHT / 2, preview, background ? 255 : state.penOpacity);

      stroke(hexFocus == this ? color(0) : color(150));
      fill(hexFocus == this && replaceHex ? color(218, 230, 243) : color(255));
      rect(fieldX, HEX_Y, HEX_WIDTH, HEX_HEIGHT);
      fill(0);
      textSize(12);
      text("#" + hexValue.toUpperCase(), fieldX + 6, HEX_Y + 16);
      String rgb = "RGB  " + int(red(preview)) + ", " + int(green(preview)) + ", " + int(blue(preview));
      text(hexValue.length() == 6 ? rgb : "Enter 6 hex digits", x + 107, HEX_Y + 16);
    }

    void drawSwatch(int x, int y, color value, int opacity) {
      int swatchWidth = 17, swatchHeight = FIELD_HEIGHT / 2;
      drawCheckerboard(x, y, swatchWidth, swatchHeight);
      fill(value, opacity);
      rect(x, y, swatchWidth, swatchHeight);
      noFill();
      stroke(0);
      rect(x, y, swatchWidth, swatchHeight);
    }
  }
}
