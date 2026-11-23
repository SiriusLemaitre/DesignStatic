import java.io.File;
import java.awt.Color;
import java.awt.Dimension;
import java.awt.EventQueue;
import java.awt.Frame;
import java.awt.Insets;
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.concurrent.ConcurrentLinkedQueue;
import javax.swing.JOptionPane;
import processing.awt.PSurfaceAWT;

// =========================================================
// GLOBAL CONSTANTS & ENUMS
// =========================================================
final int UI_HEIGHT = 50;
final int START_WIDTH = 600;
final int START_HEIGHT = 650;
final int MIN_HEIGHT = 320;

enum ToolType { PEN, FILL, DESIGN, RECT, CHEMISTRY, ERASER, IMAGE_PEN }

// =========================================================
// MAIN SKETCH
// =========================================================

// Systems
AppState state;
UIManager ui;
ToolManager tools;
FileManager fileManager;
Artwork artwork;
ColorPicker picker;
boolean strokeActive;
boolean controlTap;
boolean shiftTap;
final ConcurrentLinkedQueue<Runnable> sketchActions = new ConcurrentLinkedQueue<Runnable>();

// Images
PImage backgroundImage;
PImage penImage;

// Helper variables for mouse movement calculations
int mouseDirY = 0;
int mouseDirX = 0;
color currentPixelColor, prevPixelColor;

void settings() {
  size(600, 650);
  // Keep drawing, colour picking and export crops in the same pixel space,
  // including when the standalone app runs on a high-DPI display.
  pixelDensity(1);
  noSmooth(); // Preserve the pixelated look.
}

void setup() {
  surface.setResizable(true);
  Frame frame = ((PSurfaceAWT.SmoothCanvas)surface.getNative()).getFrame();
  EventQueue.invokeLater(() -> {
    Insets border = frame.getInsets();
    frame.setMinimumSize(new Dimension(START_WIDTH + border.left + border.right,
                                      MIN_HEIGHT + border.top + border.bottom));
  });
  frameRate(120);
  rectMode(CORNER);

  // Initialize Systems
  state = new AppState();
  ui = new UIManager();
  tools = new ToolManager();
  fileManager = new FileManager();
  picker = new ColorPicker();
  
  // Random start background
  state.randomizeBgColor();
  artwork = new Artwork();
  artwork.ensureSize();
}

void draw() {
  artwork.ensureSize();
  Runnable action;
  while ((action = sketchActions.poll()) != null) action.run();

  blendMode(BLEND);
  background(state.bgColor);
  noTint();
  image(artwork.layer, 0, UI_HEIGHT);
  ui.drawUI();
  if (picker.open) picker.display();
  updateCursor();
  ui.updateTimers();
}

// =========================================================
// INPUT HANDLING
// =========================================================

void mousePressed() {
  controlTap = false;
  shiftTap = false;
  if (picker.open) {
    if (mouseButton == LEFT) picker.press();
    return;
  }

  if (mouseY < UI_HEIGHT) {
    ui.handleMousePress();
    return;
  }

  artwork.ensureSize();
  if (mouseButton == RIGHT) {
    state.setPenColor(artwork.sample(mouseX, mouseY));
    return;
  }

  if (mouseButton == LEFT) {
    artwork.beginEdit();
    strokeActive = true;
    state.penStart.set(mouseX, mouseY);
    sampleBrushPixels();
    artwork.beginStroke();
    tools.handlePress();
    artwork.endStroke();
  }
}

void mouseDragged() {
  if (picker.open) {
    picker.drag();
    return;
  }
  if (!strokeActive) return;

  // Update oil thickness logic from original code
  state.oilThickness -= 0.05;
  if (state.oilThickness < 0.1) state.oilThickness = 0.0;

  // Pen pixel skipping logic
  state.penPixelCounter -= 1;
  if (state.penPixelCounter < 0) {
    state.penPixelCounter = 15;
    state.penStart.set(mouseX, mouseY);
  }

  artwork.ensureSize();
  sampleBrushPixels();
  artwork.beginStroke();
  tools.handleDrag();
  artwork.endStroke();
}

void mouseReleased() {
  picker.stopDrag();
  if (mouseButton == LEFT) finishStroke();
}

void finishStroke() {
  if (!strokeActive) return;
  strokeActive = false;
  state.oilThickness = 4;
  artwork.commitEdit();
}

void focusLost() {
  sketchActions.add(() -> {
    controlTap = false;
    shiftTap = false;
    picker.stopDrag();
    finishStroke();
  });
}

void mouseMoved() {
  state.penStart.set(mouseX, mouseY);
}

void mouseWheel(MouseEvent event) {
  if (picker.open) return;
  float e = event.getCount();
  state.isWritingHex = false; // Cancel writing if wheeling
  state.adjustPenColor(e * -2); // Inverted direction to match original
}

void keyPressed(KeyEvent event) {
  if (keyCode != CONTROL) controlTap = false;
  if (keyCode != SHIFT) shiftTap = false;
  if (picker.open) {
    picker.pressKey(event);
    return;
  }

  if (keyCode == CONTROL) {
    if (!event.isAutoRepeat()) controlTap = !event.isShiftDown() && !event.isAltDown();
    return;
  }
  if (keyCode == SHIFT) {
    if (!event.isAutoRepeat()) shiftTap = !event.isControlDown() && !event.isMetaDown() && !event.isAltDown();
    return;
  }
  if (event.isControlDown() || event.isMetaDown()) {
    if (keyCode == java.awt.event.KeyEvent.VK_Z || keyCode == java.awt.event.KeyEvent.VK_Y) {
      finishStroke();
      artwork.stepHistory(keyCode == java.awt.event.KeyEvent.VK_Y || event.isShiftDown());
    }
    return;
  }
  if (state.isWritingHex) {
    if (key == ESC) {
      key = 0;
      state.isWritingHex = false;
    } else if (key == BACKSPACE && !state.hexInput.isEmpty()) {
      state.hexInput = state.hexInput.substring(0, state.hexInput.length() - 1);
    }
    return;
  }

  // Global Key Commands
  if (key == ' ') handleReset();
  if (key == CODED) {
    if (keyCode == UP || keyCode == DOWN || keyCode == LEFT || keyCode == RIGHT) {
      finishStroke();
      artwork.beginEdit();
      state.randomizeBgColor();
      artwork.clear(false);
      artwork.commitEdit();
    }
  }

  // Tool Selection Hotkeys
  if (key == 'q') state.currentTool = ToolType.PEN;
  if (key == 'w') state.currentTool = ToolType.FILL;
  if (key == 'e') state.currentTool = ToolType.DESIGN;
  if (key == 'r') state.currentTool = ToolType.RECT;
  if (key == 't') state.currentTool = ToolType.CHEMISTRY;
  if (key == 'd') state.currentTool = ToolType.ERASER;
  if (key == 'f') state.currentTool = ToolType.IMAGE_PEN;

  // Sub-Tool Switching (1, 2, 3, 4)
  if (key >= '1' && key <= '4') {
    state.subToolMode = int(String.valueOf(key));
  }
  
  // Parameter Adjustments (+, -, s, a, c, x)
  handleParameterAdjustments();

  // File & Misc Commands
  if (key == 'v') fileManager.selectImageForLoad(false);
  if (key == 'm') fileManager.selectImageForLoad(true); // BG Image
  if (key == 'j') state.isBgImageActive = false;
  if (key == 'k') state.isLocked = true;
  if (key == 'l') state.isLocked = false;
  if (key == 'g') fileManager.selectImageForPen();
  if (key == 'n') fileManager.saveCustomLocation();
  if (key == 'b') fileManager.saveTransparent();
  if (key == 'o') state.setPenColor(color(255)); // White
  if (key == 'p') state.setPenColor(color(0));   // Black
  
  // Blend Modes
  if (key == 'y') {
    state.blendModeIndex++;
    if (state.blendModeIndex > 9) state.blendModeIndex = 0;
  }
  
  // Specific toggles
  if (key == TAB) {
    if (state.currentTool == ToolType.CHEMISTRY) {
      if (state.subToolMode == 1) state.chemistrySwitchR++;
      if (state.chemistrySwitchR > 4) state.chemistrySwitchR = 1;
      
      if (state.subToolMode == 4) state.switchS = !state.switchS;
    }
  }
}

void keyReleased(KeyEvent event) {
  if (keyCode == CONTROL && controlTap) {
    controlTap = false;
    if (!picker.open && !state.isWritingHex) fileManager.quickSave();
  }
  if (keyCode == SHIFT && shiftTap) {
    shiftTap = false;
    if (!picker.open && !state.isWritingHex) state.randomizePenColor();
  }
}

void keyTyped() {
  if (picker.open) {
    picker.typeKey(key);
  } else if (state.isWritingHex && isHexDigit(key)) {
    state.hexInput += key;
    if (state.hexInput.length() == 6) {
      state.setPenColor(0xff000000 | unhex(state.hexInput));
      state.isWritingHex = false;
    }
  }
}

boolean isHexDigit(char value) {
  return (value >= '0' && value <= '9') ||
         (value >= 'a' && value <= 'f') ||
         (value >= 'A' && value <= 'F');
}

// =========================================================
// HELPER METHODS
// =========================================================

void updateMouseDirection() {
  if (mouseY - pmouseY > 0) mouseDirY = 1;
  else if (mouseY - pmouseY < 0) mouseDirY = -1;
  else mouseDirY = 0;

  if (mouseX - pmouseX != 0) {
    mouseDirX = (mouseX - pmouseX > 0) ? 1 : -1;
  } else mouseDirX = 0;
}

void sampleBrushPixels() {
  if (state.currentTool == ToolType.CHEMISTRY && state.subToolMode == 4) {
    currentPixelColor = artwork.sample(mouseX, mouseY);
    prevPixelColor = artwork.sample(pmouseX, pmouseY);
    updateMouseDirection();
  }
}

void updateCursor() {
  if (!picker.open && mouseX >= 0 && mouseX < width && mouseY >= UI_HEIGHT && mouseY < height) {
    cursor(CROSS);
  } else {
    cursor(ARROW);
  }
}

void handleReset() {
  finishStroke();
  artwork.beginEdit();
  boolean useBackgroundImage = state.isBgImageActive && backgroundImage != null;
  artwork.clear(useBackgroundImage);
  artwork.commitEdit();
  if (!useBackgroundImage && !state.isLocked) {
    surface.setSize(START_WIDTH, START_HEIGHT);
  }
  // Reset Params
  state.rectSize = 33.0;
  state.chemistryAlpha = 60.0;
  state.bezierWeight = 6;
}

void handleParameterAdjustments() {
  boolean up = (key == '+' || key == 's');
  boolean down = (key == '-' || key == 'a');
  
  if (state.currentTool == ToolType.RECT) {
    if (up && state.rectSize <= 103) state.rectSize++;
    if (down && state.rectSize >= 33) state.rectSize--;
  }
  if (state.currentTool == ToolType.CHEMISTRY) {
    if (up && state.chemistryAlpha <= 200) state.chemistryAlpha += 3;
    if (down && state.chemistryAlpha >= 4) state.chemistryAlpha -= 3;
    
    if (state.subToolMode == 3) { // Bezier weight
      if (key == 'c' && state.bezierWeight <= 26) state.bezierWeight++;
      if (key == 'x' && state.bezierWeight >= 1) state.bezierWeight--;
    }
  }
  if (state.currentTool == ToolType.PEN) {
    if (up && state.penSize <= 30) state.penSize += 2;
    if (down && state.penSize >= 2) state.penSize -= 2;
  }
  if (state.currentTool == ToolType.ERASER) {
    if (up && state.eraserSize <= 98) state.eraserSize += 2;
    if (down && state.eraserSize >= 4) state.eraserSize -= 2;
  }
  if (state.currentTool == ToolType.FILL) {
    if (up && state.splashWidth <= 100) state.splashWidth += 2;
    if (down && state.splashWidth >= 2) state.splashWidth--;
    if (key == 'c' && state.splashConcentration <= 100) state.splashConcentration += 2;
    if (key == 'x' && state.splashConcentration >= 2) state.splashConcentration -= 2;
  }
}

void setBlendMode(PGraphics layer, int mode) {
   switch(mode) {
     case 1: layer.blendMode(ADD); break;
     case 2: layer.blendMode(SUBTRACT); break;
     case 3: layer.blendMode(DARKEST); break;
     case 4: layer.blendMode(LIGHTEST); break;
     case 5: layer.blendMode(DIFFERENCE); break;
     case 6: layer.blendMode(EXCLUSION); break;
     case 7: layer.blendMode(MULTIPLY); break;
     case 8: layer.blendMode(SCREEN); break;
     case 9: layer.blendMode(REPLACE); break;
     default: layer.blendMode(BLEND); break;
   }
}

int sgn(float f) {
  if (f > 0) return 1;
  if (f < 0) return -1;
  return 0;
}

// =========================================================
// CLASS: APP STATE
// =========================================================
class AppState {
  // Colors
  color bgColor;
  color penColor;
  int penOpacity = 255;
  
  // Tools
  ToolType currentTool = ToolType.PEN;
  int subToolMode = 1; // 1, 2, 3, 4
  
  // Tool Settings
  float penSize = 6;
  float eraserSize = 24;
  float rectSize = 33.0;
  float rectStroke = 1.0;
  float chemistryAlpha = 60.0;
  float bezierWeight = 6;
  float oilThickness = 4;
  float splashWidth = 30;
  float splashConcentration = 8;
  
  // Geometry / Logic
  PVector penStart = new PVector(0,0);
  PVector shapeStart = new PVector(300, 300);
  PVector eraserStart = new PVector(300, 300);
  float penPixelCounter = 0;
  float sewingCountdown = 0;
  int chemistrySwitchR = 1;
  boolean switchS = false;
  
  // System Flags
  boolean isWritingHex = false;
  String hexInput = "";
  boolean isLocked = false;
  boolean isBgImageActive = false;
  int blendModeIndex = 0;
  
  AppState() {
    randomizePenColor();
  }
  
  void randomizeBgColor() {
    bgColor = color(random(255), random(255), random(255));
  }
  
  void randomizePenColor() {
    penColor = color(random(255), random(255), random(255));
  }
  
  void setPenColor(color c) {
    penColor = c | 0xff000000;
  }
  
  void adjustPenColor(float amt) {
    float r = red(penColor) + amt;
    float g = green(penColor) + amt;
    float b = blue(penColor) + amt;
    r = constrain(r, 0, 255);
    g = constrain(g, 0, 255);
    b = constrain(b, 0, 255);
    penColor = color(r, g, b);
  }
}

class Artwork {
  final int HISTORY_STEPS = 40;
  final long HISTORY_BYTES = 128L * 1024 * 1024;
  final ArrayDeque<ArtworkSnapshot> undo = new ArrayDeque<ArtworkSnapshot>();
  final ArrayDeque<ArtworkSnapshot> redo = new ArrayDeque<ArtworkSnapshot>();
  PGraphics layer;
  ArtworkSnapshot beforeEdit;
  long historyBytes;

  int visibleHeight() {
    return max(1, height - UI_HEIGHT);
  }

  void ensureSize() {
    if (layer != null && width <= layer.width && visibleHeight() <= layer.height) return;

    PImage previous = layer == null ? null : layer.get();
    int newWidth = previous == null ? width : max(previous.width, width);
    int newHeight = previous == null ? visibleHeight() : max(previous.height, visibleHeight());
    if (layer != null) layer.dispose();
    layer = createGraphics(newWidth, newHeight, JAVA2D);
    layer.noSmooth();
    paintBackground(previous, false);
  }

  void paintBackground(PImage pixels, boolean useBackgroundImage) {
    layer.beginDraw();
    layer.blendMode(BLEND);
    layer.noTint();
    layer.background(state.bgColor);
    if (pixels != null) layer.set(0, 0, pixels);
    if (useBackgroundImage) layer.image(backgroundImage, 0, 0);
    layer.endDraw();
  }

  void clear(boolean useBackgroundImage) {
    paintBackground(null, useBackgroundImage);
  }

  void beginStroke() {
    layer.beginDraw();
    layer.clip(0, 0, width, visibleHeight());
    // Keep the existing tools' window-relative geometry.
    layer.translate(0, -UI_HEIGHT);
    setBlendMode(layer, state.blendModeIndex);
  }

  void endStroke() {
    layer.noClip();
    layer.endDraw();
  }

  color sample(int x, int y) {
    if (x < 0 || x >= width || y < UI_HEIGHT || y >= height) return state.bgColor;
    return layer.get(x, y - UI_HEIGHT);
  }

  PImage visibleImage() {
    ensureSize();
    return layer.get(0, 0, width, visibleHeight());
  }

  void importImage(PImage imported) {
    finishStroke();
    beginEdit();
    layer.beginDraw();
    layer.blendMode(BLEND);
    layer.noTint();
    layer.clip(0, 0, width, visibleHeight());
    layer.image(imported, (width - imported.width) / 2, (visibleHeight() - imported.height) / 2);
    layer.noClip();
    layer.endDraw();
    commitEdit();
  }

  ArtworkSnapshot capture() {
    return new ArtworkSnapshot(layer.get(), state.bgColor);
  }

  void beginEdit() {
    ensureSize();
    beforeEdit = capture();
  }

  void commitEdit() {
    ArtworkSnapshot previous = beforeEdit;
    beforeEdit = null;
    if (!previous.differsFrom(layer, state.bgColor)) return;
    while (!redo.isEmpty()) historyBytes -= redo.removeLast().byteSize();
    remember(undo, previous);
  }

  void stepHistory(boolean forward) {
    ArrayDeque<ArtworkSnapshot> source = forward ? redo : undo;
    if (source.isEmpty()) return;
    ensureSize();
    ArtworkSnapshot target = source.removeLast();
    historyBytes -= target.byteSize();
    remember(forward ? undo : redo, capture());
    state.bgColor = target.backgroundColor;
    paintBackground(target.pixels, false);
  }

  void remember(ArrayDeque<ArtworkSnapshot> stack, ArtworkSnapshot snapshot) {
    stack.addLast(snapshot);
    historyBytes += snapshot.byteSize();
    while (undo.size() + redo.size() > HISTORY_STEPS ||
           (historyBytes > HISTORY_BYTES && undo.size() + redo.size() > 1)) {
      // Drop the farthest step while keeping the entry just recorded.
      ArrayDeque<ArtworkSnapshot> oldest = undo.size() > 1 || stack == redo && !undo.isEmpty() ? undo : redo;
      historyBytes -= oldest.removeFirst().byteSize();
    }
  }
}

class ArtworkSnapshot {
  final PImage pixels;
  final color backgroundColor;

  ArtworkSnapshot(PImage pixels, color backgroundColor) {
    this.pixels = pixels;
    this.backgroundColor = backgroundColor;
  }

  long byteSize() {
    return (long)pixels.width * pixels.height * Integer.BYTES;
  }

  boolean differsFrom(PGraphics layer, color currentBackground) {
    if (backgroundColor != currentBackground) return true;
    layer.loadPixels();
    if (layer.width == pixels.width && layer.height == pixels.height) {
      return !Arrays.equals(layer.pixels, pixels.pixels);
    }
    // A resize during a stroke can add rows or columns filled with the background.
    for (int y = 0; y < layer.height; y++) {
      for (int x = 0; x < layer.width; x++) {
        color previous = x < pixels.width && y < pixels.height
          ? pixels.pixels[y * pixels.width + x] : backgroundColor;
        if (layer.pixels[y * layer.width + x] != previous) return true;
      }
    }
    return false;
  }
}

class ColorPicker {
  final int X = 8, Y = 55, WIDTH = 332, HEIGHT = 261;
  final int FIELD_X = 20, FIELD_Y = 87, FIELD_WIDTH = 242, FIELD_HEIGHT = 144;
  final int HUE_X = 272, HUE_WIDTH = 20;
  final int HEX_X = 20, HEX_Y = 241, HEX_WIDTH = 83, HEX_HEIGHT = 23;
  final int ALPHA_X = 64, ALPHA_Y = 271, ALPHA_WIDTH = 226, ALPHA_HEIGHT = 12;
  final int CANCEL_X = 174, DONE_X = 253, BUTTON_Y = 288, BUTTON_WIDTH = 74, BUTTON_HEIGHT = 21;
  final int NO_DRAG = 0, FIELD_DRAG = 1, HUE_DRAG = 2, ALPHA_DRAG = 3;
  boolean open;
  boolean hexFocused;
  boolean replaceHex;
  int dragTarget;
  float hue, saturation, brightness;
  float renderedHue = -1;
  color originalColor;
  int originalOpacity;
  String hexValue;
  PImage field;
  PImage hueBar;

  void show() {
    open = true;
    hexFocused = false;
    stopDrag();
    originalColor = state.penColor;
    originalOpacity = state.penOpacity;
    setFromColor(originalColor);
    hexValue = hex(originalColor, 6);
    if (field != null) return;

    field = createImage(FIELD_WIDTH, FIELD_HEIGHT, RGB);
    hueBar = createImage(HUE_WIDTH, FIELD_HEIGHT, RGB);
    hueBar.loadPixels();
    for (int y = 0; y < FIELD_HEIGHT; y++) {
      int rgb = Color.HSBtoRGB(y / (FIELD_HEIGHT - 1.0f), 1, 1);
      Arrays.fill(hueBar.pixels, y * HUE_WIDTH, (y + 1) * HUE_WIDTH, rgb);
    }
    hueBar.updatePixels();
  }

  void setFromColor(color value) {
    float[] hsb = Color.RGBtoHSB((value >> 16) & 255, (value >> 8) & 255, value & 255, null);
    hue = hsb[0];
    saturation = hsb[1];
    brightness = hsb[2];
  }

  color selectedColor() {
    return Color.HSBtoRGB(hue, saturation, brightness);
  }

  void updateField() {
    if (hue == renderedHue) return;
    field.loadPixels();
    for (int y = 0; y < FIELD_HEIGHT; y++) {
      float value = 1 - y / (FIELD_HEIGHT - 1.0f);
      for (int x = 0; x < FIELD_WIDTH; x++) {
        field.pixels[y * FIELD_WIDTH + x] = Color.HSBtoRGB(hue, x / (FIELD_WIDTH - 1.0f), value);
      }
    }
    field.updatePixels();
    renderedHue = hue;
  }

  void display() {
    updateField();
    pushStyle();
    strokeWeight(1);
    stroke(0);
    fill(246);
    rect(X, Y, WIDTH, HEIGHT);
    fill(0);
    textSize(15);
    text("Pen Color", FIELD_X, 76);
    image(field, FIELD_X, FIELD_Y);
    image(hueBar, HUE_X, FIELD_Y);

    float pointX = FIELD_X + saturation * (FIELD_WIDTH - 1);
    float pointY = FIELD_Y + (1 - brightness) * (FIELD_HEIGHT - 1);
    noFill();
    stroke(0);
    circle(pointX, pointY, 11);
    stroke(255);
    circle(pointX, pointY, 9);
    float hueY = FIELD_Y + hue * (FIELD_HEIGHT - 1);
    stroke(0);
    rect(HUE_X - 2, hueY - 2, HUE_WIDTH + 3, 4);
    stroke(255);
    line(HUE_X, hueY, HUE_X + HUE_WIDTH - 1, hueY);

    color preview = state.penColor;
    drawSwatch(302, FIELD_Y, originalColor, originalOpacity);
    drawSwatch(302, FIELD_Y + FIELD_HEIGHT / 2, preview, state.penOpacity);

    stroke(hexFocused ? color(0) : color(150));
    fill(hexFocused && replaceHex ? color(218, 230, 243) : color(255));
    rect(HEX_X, HEX_Y, HEX_WIDTH, HEX_HEIGHT);
    fill(0);
    textSize(12);
    text("#" + hexValue.toUpperCase(), HEX_X + 6, HEX_Y + 16);
    if (hexValue.length() == 6) {
      text("RGB  " + int(red(preview)) + ", " + int(green(preview)) + ", " + int(blue(preview)), 115, HEX_Y + 16);
    } else {
      text("Enter 6 hex digits", 115, HEX_Y + 16);
    }
    drawAlphaSlider();
    drawButton(CANCEL_X, "Cancel");
    drawButton(DONE_X, "Done");
    popStyle();
  }

  void drawSwatch(int x, int y, color value, int opacity) {
    int swatchWidth = 25;
    int swatchHeight = FIELD_HEIGHT / 2;
    drawCheckerboard(x, y, swatchWidth, swatchHeight);
    fill(value, opacity);
    rect(x, y, swatchWidth, swatchHeight);
    noFill();
    stroke(0);
    rect(x, y, swatchWidth, swatchHeight);
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
    text("Alpha", FIELD_X, ALPHA_Y + 10);
    text(str(state.penOpacity), 301, ALPHA_Y + 10);
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

  boolean over(int x, int y, int w, int h) {
    return mouseX >= x && mouseX < x + w && mouseY >= y && mouseY < y + h;
  }

  void press() {
    if (!over(X, Y, WIDTH, HEIGHT) || over(DONE_X, BUTTON_Y, BUTTON_WIDTH, BUTTON_HEIGHT)) {
      open = false;
    } else if (over(CANCEL_X, BUTTON_Y, BUTTON_WIDTH, BUTTON_HEIGHT)) {
      cancel();
    } else if (over(HEX_X, HEX_Y, HEX_WIDTH, HEX_HEIGHT)) {
      hexFocused = true;
      replaceHex = true;
    } else if (over(FIELD_X, FIELD_Y, FIELD_WIDTH, FIELD_HEIGHT)) {
      dragTarget = FIELD_DRAG;
      drag();
    } else if (over(HUE_X, FIELD_Y, HUE_WIDTH, FIELD_HEIGHT)) {
      dragTarget = HUE_DRAG;
      drag();
    } else if (over(ALPHA_X - 2, ALPHA_Y - 2, ALPHA_WIDTH + 4, ALPHA_HEIGHT + 4)) {
      dragTarget = ALPHA_DRAG;
      drag();
    }
  }

  void drag() {
    if (dragTarget == NO_DRAG) return;
    if (dragTarget == ALPHA_DRAG) {
      state.penOpacity = constrain(round((mouseX - ALPHA_X) * 255.0f / (ALPHA_WIDTH - 1)), 0, 255);
    } else {
      float vertical = constrain((mouseY - FIELD_Y) / (FIELD_HEIGHT - 1.0f), 0, 1);
      if (dragTarget == FIELD_DRAG) {
        saturation = constrain((mouseX - FIELD_X) / (FIELD_WIDTH - 1.0f), 0, 1);
        brightness = 1 - vertical;
      } else {
        hue = vertical;
      }
      state.setPenColor(selectedColor());
    }
    hexFocused = false;
    hexValue = hex(state.penColor, 6);
  }

  void stopDrag() {
    dragTarget = NO_DRAG;
  }

  void pressKey(KeyEvent event) {
    if (key == ESC) {
      key = 0;
      cancel();
    } else if (key == ENTER || key == RETURN) {
      open = false;
    } else if (hexFocused && (event.isControlDown() || event.isMetaDown()) &&
               keyCode == java.awt.event.KeyEvent.VK_A) {
      replaceHex = true;
    } else if (hexFocused && (key == BACKSPACE || key == DELETE)) {
      hexValue = replaceHex || hexValue.isEmpty() ? "" : hexValue.substring(0, hexValue.length() - 1);
      replaceHex = false;
    }
  }

  void typeKey(char typed) {
    if (!hexFocused || !isHexDigit(typed)) return;
    if (replaceHex) {
      hexValue = "";
      replaceHex = false;
    }
    if (hexValue.length() < 6) hexValue += typed;
    if (hexValue.length() == 6) {
      state.setPenColor(unhex(hexValue));
      setFromColor(state.penColor);
    }
  }

  void cancel() {
    state.setPenColor(originalColor);
    state.penOpacity = originalOpacity;
    open = false;
  }
}

// =========================================================
// CLASS: UI MANAGER
// =========================================================
class UIManager {
  float saveMsgTimer = 0;
  float loadMsgTimer = 0;
  
  // Highlight colors for buttons
  color cLoad, cSave, cQuick, cTrans;
  
  void drawUI() {
    blendMode(BLEND);
    strokeWeight(1);
    stroke(0);
    
    // Background bar
    fill(state.penColor); // Using pen color for UI bg (from original code logic pc1,pc2,pc3)
    rect(0, 0, width, 49);
    
    // Color Preview Circle
    stroke(0);
    fill(state.penColor);
    circle(124, 23, 30);
    
    // Text Labels
    fill(0);
    textSize(21);
    text("Pen Color : ", 8, 30);
    text("Tools : ", 148, 30);
    
    // Hex Input Box
    textSize(12);
    if (state.isWritingHex) {
      fill(0);
      rect(7, 32, 50, 12);
      fill(255);
      text("#", 10, 42);
      text(state.hexInput.toUpperCase(), 15, 42);
      
    } else {
       text("#" + hex(state.penColor, 6), 10, 42);
    }
    
    // Save/Load Feedback messages
    if (saveMsgTimer > 0) { textSize(12); fill(0); text("Design saved", 136, 40); }
    if (loadMsgTimer > 0) { textSize(12); fill(0); text("Image loaded", 136, 40); }
    
    drawFileButtons();
    drawToolIcons();
  }
  
  void updateTimers() {
    if (saveMsgTimer > 0) saveMsgTimer--;
    if (loadMsgTimer > 0) loadMsgTimer--;
    
    // Sewing tool countdown
    if (mousePressed) {
      state.sewingCountdown--;
      if (state.sewingCountdown < 0) state.sewingCountdown = 5;
    }
  }
  
  void drawFileButtons() {
    // Hover detection logic
    boolean overLoad = mouseX > 498 && mouseX < 514 && mouseY > 5 && mouseY < 22;
    boolean overSave = mouseX > 517 && mouseX < 533 && mouseY > 5 && mouseY < 22;
    boolean overQuick = mouseX > 498 && mouseX < 514 && mouseY > 24 && mouseY < 40;
    boolean overTrans = mouseX > 517 && mouseX < 533 && mouseY > 24 && mouseY < 40;
    
    cLoad = overLoad ? color(100) : color(0);
    cSave = overSave ? color(100) : color(0);
    cQuick = overQuick ? color(100) : color(0);
    cTrans = overTrans ? color(100) : color(0);
    
    // Tooltip logic
    textSize(8); fill(0);
    if (overLoad) text("Load image", 491, 47);
    if (overSave) text("Save custom", 491, 47);
    if (overQuick) text("Quick Save", 491, 47);
    if (overTrans) text("Transparent BG", 491, 47);
    
    // Draw Icons
    fill(cLoad); rect(498, 5, 16, 16); fill(255); textSize(11); text("L", 504, 16);
    fill(cSave); rect(517, 5, 16, 16); fill(255); textSize(11); text("S", 522, 16);
    fill(cQuick); rect(498, 24, 16, 16); fill(255); textSize(10); text("qS", 501, 36);
    fill(cTrans); rect(517, 24, 16, 16); fill(255); textSize(10); text("BG", 519, 36);
  }
  
  void drawToolIcons() {
    // Determine Highlight Levels
    float[] hl = new float[6]; // Pen, Fill, Design, Rect, Chem, Eraser
    ToolType[] types = {ToolType.PEN, ToolType.FILL, ToolType.DESIGN, ToolType.RECT, ToolType.CHEMISTRY, ToolType.ERASER};
    
    for(int i=0; i<6; i++) {
      if (state.currentTool == types[i]) {
        if (state.subToolMode == 1) hl[i] = 100;
        else if (state.subToolMode == 2) hl[i] = 150;
        else if (state.subToolMode == 3) hl[i] = 200;
        else if (state.subToolMode == 4) hl[i] = 220;
        else hl[i] = 150;
      } else {
        hl[i] = 0; 
      }
    }
    
    // Mouse Over Highlights (Visual Only)
    if (mouseY < 50) {
      if (mouseX > 215 && mouseX < 245) hl[0] = 150;
      if (mouseX > 255 && mouseX < 290) hl[1] = 150;
      if (mouseX > 300 && mouseX < 355) hl[2] = 150;
      if (mouseX > 365 && mouseX < 415) hl[3] = 150;
      if (mouseX > 425 && mouseX < 475) hl[4] = 150;
      if (mouseX > 563 && mouseX < 588) hl[5] = 150;
    }

    strokeWeight(1); stroke(0);
    
    // Pen
    fill(hl[0]); rect(215, 10, 30, 30); fill(255); textSize(11); text("pen", 220, 30);
    // Fill
    fill(hl[1]); circle(275, 25, 35); fill(255); textSize(12); text("FILL", 264, 30);
    // Design
    fill(hl[2]); arc(325, 40, 50, 60, PI, TWO_PI); fill(255); textSize(11); text("design", 306, 33);
    // Rect
    fill(hl[3]); rect(365, 5, 50, 35); fill(255); textSize(12); text("RECT", 374, 30);
    // Chemistry
    fill(hl[4]); rect(443, 5, 15, 25, 18); rect(425, 20, 50, 20, 28); fill(255); textSize(10); text("chemistry", 427, 33);
    // Eraser
    fill(255); arc(577, 20, 31, 32, PI, TWO_PI); fill(hl[5]); rect(561, 15, 32, 23); fill(255); textSize(10); text("eraser", 563, 33);
  }
  
  void handleMousePress() {
    if (mouseButton != LEFT) return;
    if (dist(mouseX, mouseY, 124, 23) <= 15) {
      state.isWritingHex = false;
      picker.show();
      return;
    }
    if (mouseX > 2 && mouseX < 60 && mouseY < 48) {
      state.isWritingHex = true;
      state.hexInput = "";
    }
    
    if (mouseX > 498 && mouseX < 514 && mouseY > 5 && mouseY < 22) fileManager.selectImageForLoad(false);
    if (mouseX > 517 && mouseX < 533 && mouseY > 5 && mouseY < 22) fileManager.saveCustomLocation();
    if (mouseX > 498 && mouseX < 514 && mouseY > 24 && mouseY < 40) fileManager.quickSave();
    if (mouseX > 517 && mouseX < 533 && mouseY > 24 && mouseY < 40) fileManager.saveTransparent();
    
    // Tool Selection by Mouse
    if (mouseY < 46) {
      if (mouseX > 215 && mouseX < 245) state.currentTool = ToolType.PEN;
      if (mouseX > 255 && mouseX < 290) state.currentTool = ToolType.FILL;
      if (mouseX > 300 && mouseX < 355) state.currentTool = ToolType.DESIGN;
      if (mouseX > 365 && mouseX < 415) state.currentTool = ToolType.RECT;
      if (mouseX > 425 && mouseX < 475) state.currentTool = ToolType.CHEMISTRY;
      if (mouseX > 563 && mouseX < 588) state.currentTool = ToolType.ERASER;
    }
  }
}

// =========================================================
// CLASS: TOOL MANAGER
// =========================================================
class ToolManager {
  PGraphics layer;
  
  void handlePress() {
    if (state.penOpacity == 0 && state.currentTool != ToolType.ERASER) return;
    layer = artwork.layer;
    // Initial dots or setup for tools
    if (state.currentTool == ToolType.PEN) {
      layer.stroke(state.penColor, state.penOpacity);
      layer.strokeWeight(state.penSize);
      layer.point(mouseX, mouseY);
    }

    if (state.currentTool == ToolType.DESIGN) {
      layer.stroke(state.penColor, state.penOpacity);
      layer.strokeWeight(1);
      if (state.subToolMode == 1) {
        layer.line(mouseX-66, mouseY, mouseX+66, mouseY);
        layer.line(mouseX, mouseY-66, mouseX, mouseY+66);
      } else if (state.subToolMode == 2) {
        layer.line(mouseX-66, mouseY+66, mouseX+66, mouseY-66);
        layer.line(mouseX-66, mouseY-66, mouseX+66, mouseY+66);
      }
    }

    if (state.currentTool == ToolType.RECT) drawRectLogic();
    if (state.currentTool == ToolType.ERASER) {
      state.eraserStart.set(mouseX, mouseY);
      drawEraserLogic();
    }
    if (state.currentTool == ToolType.CHEMISTRY) drawChemistryLogic();

    if (state.currentTool == ToolType.IMAGE_PEN) drawImagePen();

    // Set start points
    state.shapeStart.set(mouseX, mouseY);
    state.eraserStart.set(mouseX, mouseY);
  }
  
  void handleDrag() {
     if (state.penOpacity == 0 && state.currentTool != ToolType.ERASER) return;
     layer = artwork.layer;
     switch(state.currentTool) {
       case PEN: drawPenDrag(); break;
       case FILL: drawFillDrag(); break;
       case DESIGN: drawDesignDrag(); break;
       case RECT: drawRectLogic(); break;
       case CHEMISTRY: drawChemistryLogic(); break;
       case ERASER: drawEraserLogic(); break;
       case IMAGE_PEN: drawImagePen(); break;
     }
     
  }
  
  // --- Drawing Logic Implementations ---

  void drawImagePen() {
    if (penImage == null) return;
    if (state.penOpacity < 255) layer.tint(255, state.penOpacity);
    layer.image(penImage, mouseX - penImage.width/2, mouseY - penImage.height/2);
    layer.noTint();
  }
  
  void drawPenDrag() {
    layer.stroke(state.penColor, state.penOpacity);
    if (state.subToolMode == 2) { // Standard Line
      layer.strokeWeight(state.penSize);
      layer.line(state.penStart.x, state.penStart.y, mouseX, mouseY);
    } else if (state.subToolMode == 1) { // Smooth
      layer.strokeWeight(state.penSize);
      layer.line(mouseX, mouseY, pmouseX, pmouseY);
    } else if (state.subToolMode == 3) { // Sketchy
      layer.strokeWeight(state.penSize/2);
      for(int k=0; k<4; k++) {
        float r = random(4,8);
        layer.line(mouseX + random(-r,r), mouseY + random(-r,r), pmouseX + random(-r,r), pmouseY + random(-r,r));
      }
    }
  }
  
  void drawFillDrag() {
    layer.stroke(state.penColor, state.penOpacity);
    if (state.subToolMode == 1) {
      layer.strokeWeight(state.penSize * 2);
      layer.line(state.shapeStart.x, state.shapeStart.y, mouseX, mouseY);
    } else if (state.subToolMode == 2) {
      layer.strokeWeight(state.penSize);
      layer.line(state.shapeStart.x+random(-16,16), state.shapeStart.y+random(-16,16), mouseX+random(-16,16), mouseY+random(-16,16));
      layer.line(state.shapeStart.x+random(-16,16), state.shapeStart.y+random(-16,16), mouseX+random(-16,16), mouseY+random(-16,16));
    } else if (state.subToolMode == 3) {
       layer.strokeWeight(0.2);
       if (mouseX > 360) layer.line(state.shapeStart.x+random(0, mouseX-state.shapeStart.x), state.shapeStart.y+random(0, 32), mouseX+random(-16, 16), mouseY+random(-16, 16));
       else layer.line(state.shapeStart.x+random(mouseX-state.shapeStart.y, 0), state.shapeStart.y+random(0, 32), mouseX+random(-16, 16), mouseY+random(-16, 16));
    } else if (state.subToolMode == 4) {
      layer.strokeWeight(1);
      for (int y = 0; y < state.splashConcentration; y++) {
         layer.point(mouseX+random(-state.splashWidth, state.splashWidth), mouseY+random(-state.splashWidth, state.splashWidth));
      }
    }
  }
  
  void drawDesignDrag() {
    layer.stroke(state.penColor, state.penOpacity); layer.strokeWeight(1);
    if (state.subToolMode == 1) {
       layer.line(mouseX-66, mouseY, mouseX+66, mouseY);
       layer.line(mouseX, mouseY-66, mouseX, mouseY+66);
    } else if (state.subToolMode == 2) {
       layer.line(mouseX-66, mouseY+66, mouseX+66, mouseY-66);
       layer.line(mouseX-66, mouseY-66, mouseX+66, mouseY+66);
    } else if (state.subToolMode == 3 && state.sewingCountdown < 1) {
       layer.line(mouseX-66, mouseY+50, mouseX+66, mouseY+50);
       layer.line(mouseX-66, mouseY-50, mouseX+66, mouseY-50);
       layer.line(mouseX-50, mouseY-66, mouseX-50, mouseY+66);
       layer.line(mouseX+50, mouseY-66, mouseX+50, mouseY+66);
    }
  }
  
  void drawRectLogic() {
    layer.stroke(state.penColor, state.penOpacity); layer.strokeWeight(state.rectStroke);
    float s = state.rectSize;
    if (state.subToolMode == 1) {
      layer.line(mouseX-s, mouseY-s, mouseX+s, mouseY-s);
      layer.line(mouseX-s, mouseY+s, mouseX+s, mouseY+s);
      layer.line(mouseX-s, mouseY-s, mouseX-s, mouseY+s);
      layer.line(mouseX+s, mouseY-s, mouseX+s, mouseY+s);
    } else if (state.subToolMode == 2) {
      layer.line(mouseX-s, mouseY-s, mouseX+s, mouseY-s);
      layer.line(mouseX+s, mouseY-s, mouseX+s, mouseY+s);
    } else if (state.subToolMode == 3) {
      layer.line(mouseX-s, mouseY-s, mouseX+s, mouseY-s);
      layer.line(mouseX-s, mouseY-s, mouseX-s, mouseY+s);
    } else if (state.subToolMode == 4) {
      layer.line(mouseX-s, mouseY-s, mouseX-s, mouseY+s);
      layer.line(mouseX+s, mouseY-s, mouseX+s, mouseY+s);
    }
  }
  
  void drawEraserLogic() {
    // Stamp a circle for clicks and connect them with a rounded stroke for
    // a continuous circular eraser while dragging.
    layer.pushStyle();
    layer.blendMode(BLEND);
    layer.noStroke();
    layer.fill(state.bgColor);
    layer.circle(mouseX, mouseY, state.eraserSize);
    layer.stroke(state.bgColor);
    layer.strokeWeight(state.eraserSize);
    layer.strokeCap(ROUND);
    layer.line(state.eraserStart.x, state.eraserStart.y, mouseX, mouseY);
    layer.popStyle();
  }
  
  void drawChemistryLogic() {
    layer.stroke(state.penColor, chemistryOpacity());
    
    if (state.subToolMode == 1) {
      layer.strokeWeight(6);
      if (state.chemistrySwitchR == 1) layer.line(mouseX+22, mouseY+22, pmouseX-22, pmouseY-22);
      if (state.chemistrySwitchR == 2) layer.line(mouseX-22, mouseY+22, pmouseX+22, pmouseY-22);
      if (state.chemistrySwitchR == 3) layer.line(mouseX, mouseY+31, pmouseX, pmouseY-31);
      if (state.chemistrySwitchR == 4) layer.line(mouseX+31, mouseY, pmouseX-31, pmouseY);
    } else if (state.subToolMode == 2) {
      layer.strokeWeight(6);
      drawScratchLines(); // Reusing the scratch line logic from Eraser
    } else if (state.subToolMode == 3) {
      layer.strokeWeight(state.bezierWeight);
      layer.bezier(mouseX, mouseY, pmouseX, pmouseY, mouseX, mouseY, pmouseX/1.5, pmouseY/1.5);
    } else if (state.subToolMode == 4) {
      int X_AXIS = 2;
      if (!state.switchS) setGradient(mouseX-25, int(pmouseY-mouseDirY*5), 50, mouseDirY*10, currentPixelColor, prevPixelColor, X_AXIS);
      else setGradient(mouseX-mouseDirX*5, pmouseY-25, mouseDirX*10, 50, currentPixelColor, prevPixelColor, X_AXIS);
    }
  }

  float chemistryOpacity() {
    return state.chemistryAlpha * state.penOpacity / 255.0f;
  }
  
  // Helper for duplicate scratch line logic
  void drawScratchLines() {
      layer.line(mouseX, mouseY, pmouseX, pmouseY);
      layer.line(mouseX+2, mouseY+5, pmouseX+2, pmouseY-5);
      layer.line(mouseX-2, mouseY+5, pmouseX-2, pmouseY-5);
      layer.line(mouseX+4, mouseY+5, pmouseX+4, pmouseY-5);
      layer.line(mouseX-4, mouseY+5, pmouseX-4, pmouseY-5);
      layer.line(mouseX+6, mouseY+5, pmouseX+6, pmouseY-5);
      layer.line(mouseX-6, mouseY+5, pmouseX-6, pmouseY-5);
      layer.line(mouseX+8, mouseY+5, pmouseX+8, pmouseY-5);
      layer.line(mouseX-8, mouseY+5, pmouseX-8, pmouseY-5);
  }
  
  void setGradient(int x, int y, float w, float h, color c1, color c2, int axis) {
    int X_AXIS = 2;
    layer.noFill();
    if (axis == X_AXIS) {
      float opacity = chemistryOpacity();
      for (int i = x; i <= x+w; i++) {
        float inter = map(i, x, x+w, 0, 1);
        color c = lerpColor(c1, c2, inter);
        layer.stroke(c, opacity);
        layer.line(i, y, i, y+h);
      }
    }
  }
}

// =========================================================
// CLASS: FILE MANAGER
// =========================================================
class FileManager {
  
  void selectImageForLoad(boolean isBg) {
    selectInput("Select an image", isBg ? "backgroundChosen" : "imageChosen");
  }
  
  void selectImageForPen() {
    selectInput("Select an image", "penImageChosen");
  }
  
  void saveCustomLocation() {
    selectFolder("Select a folder to process:", "folderSelected");
  }
  
  // New helper to get name from user
  String promptForFilename() {
    // This opens the small window
    String name = JOptionPane.showInputDialog(null, "Enter file name:", "Save Image", JOptionPane.PLAIN_MESSAGE);
    
    // If user clicks "Cancel", name is null. We return null to signal abort.
    if (name == null) return null;
    
    // If user clicks "OK" but typed nothing, generate a random name
    if (name.trim().isEmpty()) return generateRandomFilename();
    
    return name;
  }
  
  void quickSave() {
    String filename = promptForFilename();
    if (filename == null) return; // User pressed Cancel
    String outputPath = dataPath(filename + ".png");
    if (!isOutputPathAvailable(outputPath)) return;
    
    ui.saveMsgTimer = 300;
    
    PImage temp = artwork.visibleImage();
    
    // Save to data folder
    temp.save(outputPath);
    println("Saved as: " + filename + ".png");
  }
  
  void saveTransparent() {
    String filename = promptForFilename();
    if (filename == null) return; // User pressed Cancel

    // Transparent exports live in data/Sprites. Create it on first use so the
    // B shortcut works in a freshly copied sketch as well.
    File spritesFolder = new File(dataPath("Sprites"));
    if (!spritesFolder.exists() && !spritesFolder.mkdirs()) {
      JOptionPane.showMessageDialog(null, "Could not create the Sprites folder.");
      return;
    }

    String outputPath = new File(spritesFolder, filename + ".png").getPath();
    if (!isOutputPathAvailable(outputPath)) return;
    
    ui.saveMsgTimer = 300;
    
    PImage canvas = artwork.visibleImage();
    canvas.format = ARGB;
    canvas.loadPixels();
    color bg = state.bgColor;
    color transparent = color(0,0,0,0);
    
    // Mask pixels to remove background color
    for(int i=0; i < canvas.pixels.length; i++) {
       if (canvas.pixels[i] == bg) canvas.pixels[i] = transparent;
    }
    canvas.updatePixels();
    
    // Calculate crop bounds
    int minX = canvas.width, maxX = -1;
    int minY = canvas.height, maxY = -1;
    for (int y = 0; y < canvas.height; y++) {
      for (int x = 0; x < canvas.width; x++) {
        int i = y * canvas.width + x;
        if ((canvas.pixels[i] & 0xFF000000) != 0) { 
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    
    // Ensure "Sprites" folder exists or save to root
    if (maxX >= minX && maxY >= minY) {
      PImage cropped = canvas.get(minX, minY, maxX - minX + 1, maxY - minY + 1);
      cropped.save(outputPath);
    } else {
      canvas.save(outputPath);
    }
    println("Saved transparent as: " + filename + ".png");
  }

  String generateRandomFilename() {
    String res = "";
    for (int y = 0; y < 6; y++) res += char(int(random(65, 89)));
    return res;
  }

  boolean isOutputPathAvailable(String outputPath) {
    File outputFile = new File(outputPath);
    if (!outputFile.exists()) return true;

    JOptionPane.showMessageDialog(
      null,
      "A file named '" + outputFile.getName() + "' already exists. Choose another name.",
      "File already exists",
      JOptionPane.WARNING_MESSAGE
    );
    return false;
  }
}

// =========================================================
// FILE CALLBACKS
// =========================================================

void imageChosen(File f) {
  PImage imported = loadSelectedImage(f);
  if (imported == null) return;
  sketchActions.add(() -> {
    state.isBgImageActive = false;
    artwork.importImage(imported);
    ui.loadMsgTimer = 300;
  });
}

void backgroundChosen(File f) {
  PImage imported = loadSelectedImage(f);
  if (imported == null) return;
  sketchActions.add(() -> {
    backgroundImage = imported;
    state.isBgImageActive = true;
  });
}

void penImageChosen(File f) {
  PImage imported = loadSelectedImage(f);
  if (imported != null) sketchActions.add(() -> penImage = imported);
}

PImage loadSelectedImage(File f) {
  if (f == null || !f.exists()) return null;
  PImage imported = loadImage(f.getAbsolutePath());
  return imported != null && imported.width > 0 && imported.height > 0 ? imported : null;
}

void folderSelected(File selection) {
  if (selection == null) return;
  sketchActions.add(() -> saveInFolder(selection));
}

void saveInFolder(File selection) {
  String filename = fileManager.generateRandomFilename();
  File outputFile = new File(selection, filename + ".png");
  int attempts = 0;
  while (outputFile.exists() && attempts < 100) {
    filename = fileManager.generateRandomFilename();
    outputFile = new File(selection, filename + ".png");
    attempts++;
  }
  if (outputFile.exists()) {
    JOptionPane.showMessageDialog(null, "Could not find an unused filename in the selected folder.");
    return;
  }
  PImage temp = artwork.visibleImage();
  temp.save(outputFile.getPath());
  ui.saveMsgTimer = 300;
}
