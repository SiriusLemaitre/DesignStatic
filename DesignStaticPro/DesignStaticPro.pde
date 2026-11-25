import java.io.File;
import java.awt.AlphaComposite;
import java.awt.Composite;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.Shape;
import java.awt.image.BufferedImage;
import processing.awt.PGraphicsJava2D;
import java.awt.Color;
import java.awt.Dimension;
import java.awt.EventQueue;
import java.awt.Frame;
import java.awt.Insets;
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.concurrent.ConcurrentLinkedQueue;
import javax.swing.JOptionPane;
import processing.awt.PSurfaceAWT;

// =========================================================
// GLOBAL CONSTANTS & ENUMS
// =========================================================
final int UI_HEIGHT = 50;
final int TOOL_BAR_HEIGHT = 32;
final int ANIMATION_TOP = UI_HEIGHT + TOOL_BAR_HEIGHT;
final int PRO_BAR_HEIGHT = TOOL_BAR_HEIGHT + 64;
final int EXPANDED_CANVAS_TOP = UI_HEIGHT + PRO_BAR_HEIGHT;
final int START_WIDTH = 600;
final int START_CANVAS_HEIGHT = 600;
final int MIN_CANVAS_HEIGHT = 174;

enum ToolType { PEN, FILL, DESIGN, RECT, CHEMISTRY, ERASER, IMAGE_PEN }

// =========================================================
// MAIN SKETCH
// =========================================================

// Systems
AppState state;
UIManager ui;
AnimationBar animationBar;
ToolControls toolControls;
ProjectFiles projectFiles;
ToolManager tools;
FileManager fileManager;
Artwork artwork;
ColorPicker picker;
Frame appFrame;
boolean sectionsVisible = true;
boolean strokeActive;
boolean controlTap;
final int SHIFT_COLOR_INTERVAL_MS = 150;
boolean cyclingPenColor;
int nextShiftColorAt;
final ConcurrentLinkedQueue<Runnable> sketchActions = new ConcurrentLinkedQueue<Runnable>();

// Images
PImage backgroundImage;
PImage penImage;

// Helper variables for mouse movement calculations
int mouseDirY = 0;
int mouseDirX = 0;
color currentPixelColor, prevPixelColor;

void settings() {
  size(START_WIDTH, START_CANVAS_HEIGHT + EXPANDED_CANVAS_TOP);
  // Keep drawing, colour picking and export crops in the same pixel space,
  // including when the standalone app runs on a high-DPI display.
  pixelDensity(1);
  noSmooth(); // Preserve the pixelated look.
}

void setup() {
  surface.setTitle("Design Static Pro");
  surface.setResizable(true);
  appFrame = ((PSurfaceAWT.SmoothCanvas)surface.getNative()).getFrame();
  EventQueue.invokeLater(() -> updateWindowMinimum(EXPANDED_CANVAS_TOP));
  frameRate(120);
  rectMode(CORNER);

  // Initialize Systems
  state = new AppState();
  ui = new UIManager();
  tools = new ToolManager();
  fileManager = new FileManager();
  picker = new ColorPicker();

  artwork = new Artwork();
  animationBar = new AnimationBar();
  toolControls = new ToolControls();
  projectFiles = new ProjectFiles();
}

int canvasTop() {
  return sectionsVisible ? EXPANDED_CANVAS_TOP : UI_HEIGHT;
}

void updateWindowMinimum(int top) {
  Insets border = appFrame.getInsets();
  appFrame.setMinimumSize(new Dimension(START_WIDTH + border.left + border.right,
    MIN_CANVAS_HEIGHT + top + border.top + border.bottom));
}

void resizeForCanvas(int canvasWidth, int canvasHeight) {
  surface.setSize(max(START_WIDTH, canvasWidth), max(MIN_CANVAS_HEIGHT, canvasHeight) + canvasTop());
}

void toggleSections() {
  finishStroke();
  toolControls.stopDrag();
  state.isWritingHex = false;
  int canvasHeight = artwork.visibleHeight();
  sectionsVisible = !sectionsVisible;
  if (!sectionsVisible) updateWindowMinimum(canvasTop());
  resizeForCanvas(width, canvasHeight);
  if (sectionsVisible) updateWindowMinimum(canvasTop());
}

void draw() {
  Runnable action;
  while ((action = sketchActions.poll()) != null) action.run();
  updateShiftColor();

  blendMode(BLEND);
  background(state.bgColor);
  artwork.drawCanvas();
  drawInterfaceBars();
  if (picker.open) picker.display();
  updateCursor();
  ui.updateTimers();
}

void drawInterfaceBars() {
  Graphics2D renderer = ((PGraphicsJava2D)g).g2;
  RenderingHints previousHints = renderer.getRenderingHints();
  Shape previousClip = renderer.getClip();
  renderer.clipRect(0, 0, width, canvasTop());
  renderer.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
  renderer.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
  try {
    ui.drawUI();
    if (sectionsVisible) {
      toolControls.display();
      animationBar.display();
    }
  } finally {
    renderer.setRenderingHints(previousHints);
    renderer.setClip(previousClip);
  }
}

// =========================================================
// INPUT HANDLING
// =========================================================

void mousePressed() {
  controlTap = false;
  if (picker.open) {
    if (mouseButton == LEFT) picker.press();
    return;
  }

  if (mouseY < UI_HEIGHT) {
    ui.handleMousePress();
    return;
  }

  if (mouseY < canvasTop()) {
    if (mouseButton == LEFT) {
      if (mouseY < ANIMATION_TOP) toolControls.press();
      else animationBar.press();
    }
    return;
  }

  if (artwork.playing) return;
  if (mouseButton == RIGHT) {
    state.setPenColor(artwork.sample(mouseX, mouseY));
    return;
  }

  if (mouseButton == LEFT && artwork.canEdit()) {
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
  if (toolControls.drag()) return;
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

  sampleBrushPixels();
  artwork.beginStroke();
  tools.handleDrag();
  artwork.endStroke();
}

void mouseReleased() {
  picker.stopDrag();
  toolControls.stopDrag();
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
    cyclingPenColor = false;
    picker.stopDrag();
    toolControls.stopDrag();
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
  if (event.isControlDown() || event.isMetaDown() || event.isAltDown()) cyclingPenColor = false;
  if (picker.open) {
    picker.pressKey(event);
    return;
  }

  if (keyCode == CONTROL) {
    if (!event.isAutoRepeat()) controlTap = !event.isShiftDown() && !event.isAltDown();
    return;
  }
  if (keyCode == SHIFT) {
    if (!event.isAutoRepeat() && !cyclingPenColor && !state.isWritingHex &&
        !event.isControlDown() && !event.isMetaDown() && !event.isAltDown()) {
      cyclingPenColor = true;
      changeShiftColor(millis());
    }
    return;
  }
  if (event.isControlDown() || event.isMetaDown()) {
    if (keyCode == java.awt.event.KeyEvent.VK_S) projectFiles.selectSave();
    if (keyCode == java.awt.event.KeyEvent.VK_O) projectFiles.selectLoad();
    if (keyCode == java.awt.event.KeyEvent.VK_Z || keyCode == java.awt.event.KeyEvent.VK_Y) {
      finishStroke();
      artwork.stopPlayback();
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
      artwork.stopPlayback();
      if (!artwork.canEdit()) return;
      artwork.beginEdit();
      state.randomizeBgColor();
      artwork.clear(false);
      artwork.commitEdit();
    }
  }

  // Tool Selection Hotkeys
  if (key == 'q') state.selectTool(ToolType.PEN);
  if (key == 'w') state.selectTool(ToolType.FILL);
  if (key == 'e') state.selectTool(ToolType.DESIGN);
  if (key == 'r') state.selectTool(ToolType.RECT);
  if (key == 't') state.selectTool(ToolType.CHEMISTRY);
  if (key == 'd') state.selectTool(ToolType.ERASER);
  if (key == 'f') state.selectTool(ToolType.IMAGE_PEN);

  // Sub-tool shortcuts
  if (key >= '1' && key <= '4') state.subToolMode = key - '0';
  if (key == '5' && state.currentTool == ToolType.PEN) state.subToolMode = PAPER_PENCIL_MODE;

  // Parameter Adjustments (+, -, s, a, c, x)
  handleParameterAdjustments();

  // File & Misc Commands
  if (key == 'v') fileManager.selectImageForLoad(false);
  if (key == 'm') fileManager.selectImageForLoad(true); // BG Image
  if (key == 'j' && state.isBgImageActive) {
    state.isBgImageActive = false;
    artwork.dirty = true;
  }
  if (key == 'k') state.isLocked = true;
  if (key == 'l') state.isLocked = false;
  if (key == 'g') fileManager.selectImageForPen();
  if (key == 'n') fileManager.saveCustomLocation();
  if (key == 'b') fileManager.saveTransparent();
  if (key == 'o') state.setPenColor(color(255)); // White
  if (key == 'p') state.setPenColor(color(0));   // Black

  // Blend Modes
  if (key == 'y') {
    state.cycleBlend(1);
  }

  if (key == TAB) state.cycleChemistryVariant();
}

void keyReleased(KeyEvent event) {
  if (keyCode == CONTROL && controlTap) {
    controlTap = false;
    if (!picker.open && !state.isWritingHex) fileManager.quickSave();
  }
  if (keyCode == SHIFT) cyclingPenColor = false;
}

void updateShiftColor() {
  if (!cyclingPenColor) return;
  if (picker.open || state.isWritingHex) {
    cyclingPenColor = false;
    return;
  }
  int now = millis();
  if (now - nextShiftColorAt >= 0) changeShiftColor(now);
}

void changeShiftColor(int now) {
  state.randomizePenColor();
  artwork.dirty = true;
  nextShiftColorAt = now + SHIFT_COLOR_INTERVAL_MS;
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
  if (!picker.open && mouseX >= 0 && mouseX < width && mouseY >= canvasTop() && mouseY < height && !artwork.playing && artwork.canEdit()) {
    cursor(CROSS);
  } else {
    cursor(ARROW);
  }
}

void handleReset() {
  finishStroke();
  artwork.stopPlayback();
  if (!artwork.canEdit()) return;
  artwork.beginEdit();
  boolean useBackgroundImage = state.isBgImageActive && backgroundImage != null;
  artwork.clear(useBackgroundImage);
  artwork.commitEdit();
  if (!useBackgroundImage && !state.isLocked) {
    resizeForCanvas(START_WIDTH, START_CANVAS_HEIGHT);
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
  if (state.currentTool == ToolType.PEN || state.currentTool == ToolType.FILL) {
    if (up) toolControls.adjustSize(2);
    if (down) toolControls.adjustSize(-2);
  }
  if (state.currentTool == ToolType.ERASER) {
    if (up && state.eraserSize <= 98) state.eraserSize += 2;
    if (down && state.eraserSize >= 4) state.eraserSize -= 2;
  }
  if (state.currentTool == ToolType.FILL) {
    if (key == 'c' && state.splashConcentration <= 100) state.splashConcentration += 2;
    if (key == 'x' && state.splashConcentration >= 2) state.splashConcentration -= 2;
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
  color bgColor = #D28E8E;
  color penColor = #FFFFFF;
  int penOpacity = 255;

  // Tools
  ToolType currentTool = ToolType.PEN;
  int subToolMode = 1;

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

  void selectTool(ToolType tool) {
    currentTool = tool;
    if (tool != ToolType.PEN && subToolMode == PAPER_PENCIL_MODE) subToolMode = 1;
  }

  void cycleBlend(int direction) {
    blendModeIndex = Math.floorMod(blendModeIndex + direction, BRUSH_BLEND_MODES.length);
    artwork.dirty = true;
  }

  void cycleChemistryVariant() {
    if (currentTool != ToolType.CHEMISTRY) return;
    if (subToolMode == 1) {
      chemistrySwitchR = chemistrySwitchR % 4 + 1;
      artwork.dirty = true;
    } else if (subToolMode == 4) {
      switchS = !switchS;
      artwork.dirty = true;
    }
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

// =========================================================
// CLASS: UI MANAGER
// =========================================================
class UIManager {
  float saveMsgTimer = 0;
  String fileMessage = "";

  void showFileMessage(String message) {
    fileMessage = message;
    saveMsgTimer = 300;
  }

  final int ERASER_X = 487;
  final int FILE_X = 531, FILE_Y = 5, FILE_BUTTON_SIZE = 16, FILE_BUTTON_STEP = 19;
  final int SECTIONS_ARROW_WIDTH = 14, SECTIONS_ARROW_HEIGHT = 19;
  final int SECTIONS_ARROW_Y = FILE_Y + FILE_BUTTON_STEP + FILE_BUTTON_SIZE - SECTIONS_ARROW_HEIGHT;
  final String[] fileLabels = {"L", "S", "qS", "BG"};
  final String[] fileTooltips = {"Load image", "Save custom", "Quick Save", "Transparent BG"};

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
    if (saveMsgTimer > 0) { textSize(12); fill(0); text(fileMessage, 136, 42); }

    drawFileButtons();
    drawToolIcons();
    drawSectionsArrow();
  }

  void updateTimers() {
    if (saveMsgTimer > 0) saveMsgTimer--;

    // Sewing tool countdown
    if (mousePressed) {
      state.sewingCountdown--;
      if (state.sewingCountdown < 0) state.sewingCountdown = 5;
    }
  }

  boolean overButton(int x, int y, int w, int h) {
    return mouseX >= x && mouseX < x + w && mouseY >= y && mouseY < y + h;
  }

  int fileButtonX(int index) {
    return FILE_X + index % 2 * FILE_BUTTON_STEP;
  }

  int fileButtonY(int index) {
    return FILE_Y + index / 2 * FILE_BUTTON_STEP;
  }

  int hoveredFileButton() {
    for (int index = 0; index < fileLabels.length; index++) {
      if (overButton(fileButtonX(index), fileButtonY(index), FILE_BUTTON_SIZE, FILE_BUTTON_SIZE)) return index;
    }
    return -1;
  }

  void drawFileButtons() {
    int hovered = hoveredFileButton();
    for (int index = 0; index < fileLabels.length; index++) {
      int x = fileButtonX(index);
      int y = fileButtonY(index);
      fill(index == hovered ? 100 : 0);
      rect(x, y, FILE_BUTTON_SIZE, FILE_BUTTON_SIZE);
      fill(255);
      textSize(index < 2 ? 11 : 10);
      String label = fileLabels[index];
      text(label, x + (FILE_BUTTON_SIZE - textWidth(label)) / 2, y + 12);
    }
    if (hovered >= 0) {
      textSize(8);
      fill(0);
      text(fileTooltips[hovered], FILE_X + FILE_BUTTON_STEP + FILE_BUTTON_SIZE - textWidth(fileTooltips[hovered]), 47);
    }
  }

  int sectionsArrowX() {
    return width - SECTIONS_ARROW_WIDTH - 4;
  }

  boolean overSectionsArrow() {
    return overButton(sectionsArrowX(), SECTIONS_ARROW_Y, SECTIONS_ARROW_WIDTH, SECTIONS_ARROW_HEIGHT);
  }

  void drawSectionsArrow() {
    boolean hovered = overSectionsArrow();
    int x = sectionsArrowX();
    int centerX = x + SECTIONS_ARROW_WIDTH / 2;
    int centerY = SECTIONS_ARROW_Y + SECTIONS_ARROW_HEIGHT / 2;
    int direction = sectionsVisible ? -1 : 1;
    pushStyle();
    stroke(0);
    fill(hovered ? 100 : 0);
    rect(x, SECTIONS_ARROW_Y, SECTIONS_ARROW_WIDTH, SECTIONS_ARROW_HEIGHT, 2);
    stroke(255);
    strokeWeight(1.5f);
    line(centerX - 3, centerY - direction * 2, centerX, centerY + direction);
    line(centerX, centerY + direction, centerX + 3, centerY - direction * 2);
    if (hovered) {
      String label = sectionsVisible ? "Hide panels" : "Show panels";
      textSize(8);
      fill(0);
      text(label, width - 5 - textWidth(label), 47);
    }
    popStyle();
  }

  boolean overEraser() {
    return overButton(ERASER_X, 3, 32, 36);
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
      if (overEraser()) hl[5] = 150;
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
    fill(255); arc(ERASER_X + 16, 20, 31, 32, PI, TWO_PI); fill(hl[5]); rect(ERASER_X, 15, 32, 23); fill(255); textSize(10); text("eraser", ERASER_X + 2, 33);
  }

  void handleMousePress() {
    if (mouseButton != LEFT) return;
    if (overSectionsArrow()) {
      toggleSections();
      return;
    }
    if (dist(mouseX, mouseY, 124, 23) <= 15) {
      state.isWritingHex = false;
      picker.show();
      return;
    }
    if (mouseX > 2 && mouseX < 60 && mouseY < 48) {
      state.isWritingHex = true;
      state.hexInput = "";
    }

    switch (hoveredFileButton()) {
      case 0: fileManager.selectImageForLoad(false); return;
      case 1: fileManager.saveCustomLocation(); return;
      case 2: fileManager.quickSave(); return;
      case 3: fileManager.saveTransparent(); return;
    }

    // Tool Selection by Mouse
    if (mouseY < 46) {
      if (mouseX > 215 && mouseX < 245) state.selectTool(ToolType.PEN);
      if (mouseX > 255 && mouseX < 290) state.selectTool(ToolType.FILL);
      if (mouseX > 300 && mouseX < 355) state.selectTool(ToolType.DESIGN);
      if (mouseX > 365 && mouseX < 415) state.selectTool(ToolType.RECT);
      if (mouseX > 425 && mouseX < 475) state.selectTool(ToolType.CHEMISTRY);
      if (overEraser()) state.selectTool(ToolType.ERASER);
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
    layer = artwork.activeLayer().pixels;
    // Initial dots or setup for tools
    if (state.currentTool == ToolType.PEN && state.subToolMode == PAPER_PENCIL_MODE) {
      drawPaperPencil(mouseX, mouseY, mouseX, mouseY, layer);
    } else if (state.currentTool == ToolType.PEN) {
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
     layer = artwork.activeLayer().pixels;
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
    if (state.subToolMode == PAPER_PENCIL_MODE) {
      drawPaperPencil(pmouseX, pmouseY, mouseX, mouseY, layer);
      return;
    }
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
       layer.strokeWeight(state.penSize / 30.0f);
       if (mouseX > 360) layer.line(state.shapeStart.x+random(0, mouseX-state.shapeStart.x), state.shapeStart.y+random(0, 32), mouseX+random(-16, 16), mouseY+random(-16, 16));
       else {
         // This brush mixes X with the original window-relative Y.
         float originalStartY = state.shapeStart.y - (canvasTop() - UI_HEIGHT);
         layer.line(state.shapeStart.x + random(mouseX - originalStartY, 0), state.shapeStart.y + random(0, 32),
           mouseX + random(-16, 16), mouseY + random(-16, 16));
       }
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
    Graphics2D renderer = ((PGraphicsJava2D)layer).g2;
    Composite previous = renderer.getComposite();
    renderer.setComposite(AlphaComposite.Clear);
    layer.noStroke();
    layer.fill(255);
    layer.circle(mouseX, mouseY, state.eraserSize);
    layer.stroke(255);
    layer.strokeWeight(state.eraserSize);
    layer.strokeCap(ROUND);
    layer.line(state.eraserStart.x, state.eraserStart.y, mouseX, mouseY);
    renderer.setComposite(previous);
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
      int offset = canvasTop() - UI_HEIGHT;
      float endY = (pmouseY - offset) / 1.5 + offset;
      layer.bezier(mouseX, mouseY, pmouseX, pmouseY, mouseX, mouseY, pmouseX / 1.5, endY);
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
