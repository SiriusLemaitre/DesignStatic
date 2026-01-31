import java.io.File;

// =========================================================
// GLOBAL CONSTANTS & ENUMS
// =========================================================
final int UI_HEIGHT = 50;
final int CANVAS_WIDTH = 600;
final int CANVAS_HEIGHT = 650;

enum ToolType { PEN, FILL, DESIGN, RECT, CHEMISTRY, ERASER, IMAGE_PEN }

// =========================================================
// MAIN SKETCH
// =========================================================

// Systems
AppState state;
UIManager ui;
ToolManager tools;
FileManager fileManager;

// Images
PImage loadedImage;
PImage backgroundImage;
PImage penImage;

// Helper variables for mouse movement calculations
int mouseDirY = 0;
int mouseDirX = 0;
color currentPixelColor, prevPixelColor;

void setup() {
  size(600, 650);
  surface.setResizable(true);
  frameRate(120);
  rectMode(CORNER);
  noSmooth(); // Preserving the pixelated look from original code

  // Initialize Systems
  state = new AppState();
  ui = new UIManager();
  tools = new ToolManager();
  fileManager = new FileManager();
  
  // Random start background
  state.randomizeBgColor();
  background(state.bgColor);
}

void draw() {
  // 1. Blend Mode Handling
  if (state.blendModeIndex == 0) blendMode(BLEND);
  else setBlendMode(state.blendModeIndex);

  // 2. Track Colors & Mouse Direction for specific brushes
  currentPixelColor = get(mouseX, mouseY);
  prevPixelColor = get(pmouseX, pmouseY);
  updateMouseDirection();

  // 3. Draw UI (Always draws on top)
  ui.drawUI();
  
  // 4. Handle loaded images
  if (state.shouldLoadImage && loadedImage != null) {
    image(loadedImage, width/2 - loadedImage.width/2, height/2 - loadedImage.height/2);
    state.shouldLoadImage = false;
  }
  
  // 5. Decrement Timers
  ui.updateTimers();
}

// =========================================================
// INPUT HANDLING
// =========================================================

void mousePressed() {
  // Check if clicking UI
  if (mouseY < UI_HEIGHT) {
    ui.handleMousePress();
    return;
  }

  // Right Click: Color Picker
  if (mouseButton == RIGHT) {
    color c = get(mouseX, mouseY);
    state.setPenColor(c);
    return;
  }

  // Left Click: Drawing Tools
  if (mouseButton == LEFT) {
    tools.handlePress();
  }
}

void mouseDragged() {
  // Update oil thickness logic from original code
  state.oilThickness -= 0.05;
  if (state.oilThickness < 0.1) state.oilThickness = 0.0;

  // Pen pixel skipping logic
  state.penPixelCounter -= 1;
  if (state.penPixelCounter < 0) {
    state.penPixelCounter = 15;
    state.penStart.set(mouseX, mouseY);
  }

  if (mouseButton == LEFT && mouseY > UI_HEIGHT) {
    tools.handleDrag();
  }
}

void mouseReleased() {
  state.oilThickness = 4; // Reset oil
  tools.handleRelease();
}

void mouseMoved() {
  state.penStart.set(mouseX, mouseY);
}

void mouseWheel(MouseEvent event) {
  float e = event.getCount();
  state.isWritingHex = false; // Cancel writing if wheeling
  state.adjustPenColor(e * -2); // Inverted direction to match original
}

void mouseClicked() {
  // Trigger Hex writing mode
  if (mouseButton == LEFT && mouseX < 60 && mouseX > 2 && mouseY < 48) {
    state.isWritingHex = true;
    state.hexInput = "";
  }
}

void keyPressed() {
  // 1. Text Input for Colors
  if (state.isWritingHex) return; // Logic handled in keyTyped

  // 2. Global Key Commands
  if (key == ' ') handleReset();
  if (key == CODED) {
    if (keyCode == CONTROL) fileManager.quickSave();
    if (keyCode == UP || keyCode == DOWN || keyCode == LEFT || keyCode == RIGHT) {
      state.randomizeBgColor();
      background(state.bgColor);
    }
  }

  // 3. Tool Selection Hotkeys
  if (key == 'q') state.currentTool = ToolType.PEN;
  if (key == 'w') state.currentTool = ToolType.FILL;
  if (key == 'e') state.currentTool = ToolType.DESIGN;
  if (key == 'r') state.currentTool = ToolType.RECT;
  if (key == 't') state.currentTool = ToolType.CHEMISTRY;
  if (key == 'd') state.currentTool = ToolType.ERASER;
  if (key == 'f') state.currentTool = ToolType.IMAGE_PEN;

  // 4. Sub-Tool Switching (1, 2, 3, 4)
  if (key >= '1' && key <= '4') {
    state.subToolMode = int(String.valueOf(key));
  }
  
  // 5. Parameter Adjustments (+, -, s, a, c, x)
  handleParameterAdjustments();

  // 6. File & Misc Commands
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
  
  // 7. Blend Modes
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

void keyTyped() {
  if (state.isWritingHex) {
    if ((key >= 'A' && key <= 'f') || (key >= '0' && key <= '9') || (key >= 'A' && key <= 'F')) {
      state.hexInput += key;
    }
  }
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

void handleReset() {
  if (state.isBgImageActive && backgroundImage != null) {
    background(state.bgColor);
    image(backgroundImage, 0, UI_HEIGHT);
  } else if (state.isLocked) {
    background(state.bgColor);
  } else {
    surface.setSize(600, 650);
    background(state.bgColor);
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
  if (state.currentTool == ToolType.FILL) {
    if (up && state.splashWidth <= 100) state.splashWidth += 2;
    if (down && state.splashWidth >= 2) state.splashWidth--;
    if (key == 'c' && state.splashConcentration <= 100) state.splashConcentration += 2;
    if (key == 'x' && state.splashConcentration >= 2) state.splashConcentration -= 2;
  }
}

void setBlendMode(int mode) {
   switch(mode) {
     case 1: blendMode(ADD); break;
     case 2: blendMode(SUBTRACT); break;
     case 3: blendMode(DARKEST); break;
     case 4: blendMode(LIGHTEST); break;
     case 5: blendMode(DIFFERENCE); break;
     case 6: blendMode(EXCLUSION); break;
     case 7: blendMode(MULTIPLY); break;
     case 8: blendMode(SCREEN); break;
     case 9: blendMode(REPLACE); break;
     default: blendMode(BLEND); break;
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
  
  // Tools
  ToolType currentTool = ToolType.PEN;
  int subToolMode = 1; // 1, 2, 3, 4
  
  // Tool Settings
  float penSize = 6;
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
  
  // Arrays for Fill Tool (Polygon)
  int[] verticesX = new int[50];
  int[] verticesY = new int[50];
  int vertIndex = 0;
  
  // System Flags
  boolean isWritingHex = false;
  String hexInput = "";
  boolean isLocked = false;
  boolean shouldLoadImage = false;
  boolean isBgImageActive = false;
  boolean isPenImageSet = false;
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
    penColor = c;
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
      
      // Check if done typing
      if (state.hexInput.length() == 6) {
        int hi = unhex(state.hexInput.toUpperCase());
        state.penColor = color(red(hi), green(hi), blue(hi));
        state.isWritingHex = false;
      }
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
    if (mouseX > 105 && mouseX < 139 && mouseY > 9 && mouseY < 36) state.randomizePenColor();
    
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
  
  void handlePress() {
    // Initial dots or setup for tools
    if (mouseY > 60) {
      if (state.currentTool == ToolType.PEN) {
         stroke(state.penColor); strokeWeight(state.penSize); point(mouseX, mouseY);
      }
      
      if (state.currentTool == ToolType.DESIGN) {
        stroke(state.penColor); strokeWeight(1);
        if (state.subToolMode == 1) {
           line(mouseX-66, mouseY, mouseX+66, mouseY);
           line(mouseX, mouseY-66, mouseX, mouseY+66);
        } else if (state.subToolMode == 2) {
           line(mouseX-66, mouseY+66, mouseX+66, mouseY-66);
           line(mouseX-66, mouseY-66, mouseX+66, mouseY+66);
        }
      }
      
      if (state.currentTool == ToolType.RECT) drawRectLogic();
      if (state.currentTool == ToolType.ERASER) drawEraserLogic();
      if (state.currentTool == ToolType.CHEMISTRY) drawChemistryLogic();
      
      if (state.currentTool == ToolType.IMAGE_PEN && penImage != null) {
        image(penImage, mouseX - penImage.width/2, mouseY - penImage.height/2);
      }
    }
    
    // Set start points
    state.shapeStart.set(mouseX, mouseY);
    state.eraserStart.set(mouseX, mouseY);
  }
  
  void handleDrag() {
     switch(state.currentTool) {
       case PEN: drawPenDrag(); break;
       case FILL: drawFillDrag(); break;
       case DESIGN: drawDesignDrag(); break;
       case RECT: drawRectLogic(); break;
       case CHEMISTRY: drawChemistryLogic(); break;
       case ERASER: drawEraserLogic(); break;
       case IMAGE_PEN: 
         if (penImage != null) image(penImage, mouseX - penImage.width/2, mouseY - penImage.height/2);
         break;
     }
     
     // Update start points continuously
     state.shapeStart.set(mouseX, mouseY);
     state.eraserStart.set(mouseX, mouseY);
  }
  
  void handleRelease() {
    if (state.currentTool == ToolType.FILL) {
      beginShape(POINTS);
      tint(state.penColor);
      for (int k = 0; k < state.vertIndex; k++) {
        // Note: The original logic for vertex index (i, j) was slightly buggy/unused
        // in the drag handler, but we keep the structure here.
        // Since we aren't accumulating vertices in drag anymore (original was commented out),
        // this is mostly a placeholder unless logic is restored.
      }
      endShape(CLOSE);
    }
  }

  // --- Drawing Logic Implementations ---
  
  void drawPenDrag() {
    stroke(state.penColor);
    if (state.subToolMode == 2) { // Standard Line
      strokeWeight(state.penSize);
      line(state.penStart.x, state.penStart.y, mouseX, mouseY);
    } else if (state.subToolMode == 1) { // Smooth
      strokeWeight(state.penSize);
      line(mouseX, mouseY, pmouseX, pmouseY);
    } else if (state.subToolMode == 3) { // Sketchy
      strokeWeight(state.penSize/2);
      for(int k=0; k<4; k++) {
        float r = random(4,8);
        line(mouseX + random(-r,r), mouseY + random(-r,r), pmouseX + random(-r,r), pmouseY + random(-r,r));
      }
    }
  }
  
  void drawFillDrag() {
    stroke(state.penColor);
    if (state.subToolMode == 1) {
      strokeWeight(state.penSize * 2);
      line(state.shapeStart.x, state.shapeStart.y, mouseX, mouseY);
    } else if (state.subToolMode == 2) {
      strokeWeight(state.penSize);
      line(state.shapeStart.x+random(-16,16), state.shapeStart.y+random(-16,16), mouseX+random(-16,16), mouseY+random(-16,16));
      line(state.shapeStart.x+random(-16,16), state.shapeStart.y+random(-16,16), mouseX+random(-16,16), mouseY+random(-16,16));
    } else if (state.subToolMode == 3) {
       strokeWeight(0.2);
       if (mouseX > 360) line(state.shapeStart.x+random(0, mouseX-state.shapeStart.x), state.shapeStart.y+random(0, 32), mouseX+random(-16, 16), mouseY+random(-16, 16));
       else line(state.shapeStart.x+random(mouseX-state.shapeStart.y, 0), state.shapeStart.y+random(0, 32), mouseX+random(-16, 16), mouseY+random(-16, 16));
    } else if (state.subToolMode == 4) {
      strokeWeight(1);
      for (int y = 0; y < state.splashConcentration; y++) {
         point(mouseX+random(-state.splashWidth, state.splashWidth), mouseY+random(-state.splashWidth, state.splashWidth));
      }
    }
  }
  
  void drawDesignDrag() {
    stroke(state.penColor); strokeWeight(1);
    if (state.subToolMode == 1) {
       line(mouseX-66, mouseY, mouseX+66, mouseY);
       line(mouseX, mouseY-66, mouseX, mouseY+66);
    } else if (state.subToolMode == 2) {
       line(mouseX-66, mouseY+66, mouseX+66, mouseY-66);
       line(mouseX-66, mouseY-66, mouseX+66, mouseY+66);
    } else if (state.subToolMode == 3 && state.sewingCountdown < 1) {
       line(mouseX-66, mouseY+50, mouseX+66, mouseY+50);
       line(mouseX-66, mouseY-50, mouseX+66, mouseY-50);
       line(mouseX-50, mouseY-66, mouseX-50, mouseY+66);
       line(mouseX+50, mouseY-66, mouseX+50, mouseY+66);
    }
  }
  
  void drawRectLogic() {
    stroke(state.penColor); strokeWeight(state.rectStroke);
    float s = state.rectSize;
    if (state.subToolMode == 1) {
      line(mouseX-s, mouseY-s, mouseX+s, mouseY-s);
      line(mouseX-s, mouseY+s, mouseX+s, mouseY+s);
      line(mouseX-s, mouseY-s, mouseX-s, mouseY+s);
      line(mouseX+s, mouseY-s, mouseX+s, mouseY+s);
    } else if (state.subToolMode == 2) {
      line(mouseX-s, mouseY-s, mouseX+s, mouseY-s);
      line(mouseX+s, mouseY-s, mouseX+s, mouseY+s);
    } else if (state.subToolMode == 3) {
      line(mouseX-s, mouseY-s, mouseX+s, mouseY-s);
      line(mouseX-s, mouseY-s, mouseX-s, mouseY+s);
    } else if (state.subToolMode == 4) {
      line(mouseX-s, mouseY-s, mouseX-s, mouseY+s);
      line(mouseX+s, mouseY-s, mouseX+s, mouseY+s);
    }
  }
  
  void drawEraserLogic() {
    if (state.subToolMode == 3) {
      noStroke(); fill(state.bgColor);
      rect(mouseX-20, mouseY-20, 40, 40);
    } else if (state.subToolMode == 2) {
      strokeWeight(6); stroke(state.bgColor, 30);
      drawScratchLines();
    } else if (state.subToolMode == 1) {
      stroke(state.bgColor); strokeWeight(state.penSize * 2);
      line(state.eraserStart.x, state.eraserStart.y, mouseX, mouseY);
    }
  }
  
  void drawChemistryLogic() {
    stroke(state.penColor, state.chemistryAlpha);
    
    if (state.subToolMode == 1) {
      strokeWeight(6);
      if (state.chemistrySwitchR == 1) line(mouseX+22, mouseY+22, pmouseX-22, pmouseY-22);
      if (state.chemistrySwitchR == 2) line(mouseX-22, mouseY+22, pmouseX+22, pmouseY-22);
      if (state.chemistrySwitchR == 3) line(mouseX, mouseY+31, pmouseX, pmouseY-31);
      if (state.chemistrySwitchR == 4) line(mouseX+31, mouseY, pmouseX-31, pmouseY);
    } else if (state.subToolMode == 2) {
      strokeWeight(6);
      drawScratchLines(); // Reusing the scratch line logic from Eraser
    } else if (state.subToolMode == 3) {
      strokeWeight(state.bezierWeight);
      bezier(mouseX, mouseY, pmouseX, pmouseY, mouseX, mouseY, pmouseX/1.5, pmouseY/1.5);
    } else if (state.subToolMode == 4) {
      int X_AXIS = 2;
      if (!state.switchS) setGradient(mouseX-25, int(pmouseY-mouseDirY*5), 50, mouseDirY*10, currentPixelColor, prevPixelColor, X_AXIS);
      else setGradient(mouseX-mouseDirX*5, pmouseY-25, mouseDirX*10, 50, currentPixelColor, prevPixelColor, X_AXIS);
    }
  }
  
  // Helper for duplicate scratch line logic
  void drawScratchLines() {
      line(mouseX, mouseY, pmouseX, pmouseY);
      line(mouseX+2, mouseY+5, pmouseX+2, pmouseY-5);
      line(mouseX-2, mouseY+5, pmouseX-2, pmouseY-5);
      line(mouseX+4, mouseY+5, pmouseX+4, pmouseY-5);
      line(mouseX-4, mouseY+5, pmouseX-4, pmouseY-5);
      line(mouseX+6, mouseY+5, pmouseX+6, pmouseY-5);
      line(mouseX-6, mouseY+5, pmouseX-6, pmouseY-5);
      line(mouseX+8, mouseY+5, pmouseX+8, pmouseY-5);
      line(mouseX-8, mouseY+5, pmouseX-8, pmouseY-5);
  }
  
  void setGradient(int x, int y, float w, float h, color c1, color c2, int axis) {
    int X_AXIS = 2;
    noFill();
    if (axis == X_AXIS) {
      for (int i = x; i <= x+w; i++) {
        float inter = map(i, x, x+w, 0, 1);
        color c = lerpColor(c1, c2, inter);
        stroke(c, state.chemistryAlpha);
        line(i, y, i, y+h);
      }
    }
  }
}

// =========================================================
// CLASS: FILE MANAGER
// =========================================================
class FileManager {
  
  void selectImageForLoad(boolean isBg) {
    state.isBgImageActive = isBg;
    state.isPenImageSet = false;
    selectInput("Select an image", "imageChosen");
  }
  
  void selectImageForPen() {
    state.isPenImageSet = true;
    selectInput("Select an image", "imageChosen");
  }
  
  void saveCustomLocation() {
    selectFolder("Select a folder to process:", "folderSelected");
  }
  
  void quickSave() {
    String filename = generateRandomFilename();
    ui.saveMsgTimer = 300;
    PImage temp = get(0, 50, 600, 600);
    // Original path: dataPath
    temp.save(dataPath(filename + ".png"));
  }
  
  void saveTransparent() {
    String filename = generateRandomFilename();
    ui.saveMsgTimer = 300;
    
    PImage canvas = get(0, 50, width, height-50);
    canvas.format = ARGB;
    canvas.loadPixels();
    color bg = state.bgColor;
    color transparent = color(0,0,0,0);
    
    // Mask pixels
    for(int i=0; i < canvas.pixels.length; i++) {
       if (canvas.pixels[i] == bg) canvas.pixels[i] = transparent;
    }
    canvas.updatePixels();
    
    // Crop calculation
    int minX = canvas.width, maxX = -1;
    int minY = canvas.height, maxY = -1;
    for (int y = 0; y < canvas.height; y++) {
      for (int x = 0; x < canvas.width; x++) {
        int i = y * canvas.width + x;
        if ((canvas.pixels[i] & 0xFF000000) != 0) { // Check alpha
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    
    if (maxX >= minX && maxY >= minY) {
      PImage cropped = canvas.get(minX, minY, maxX - minX + 1, maxY - minY + 1);
      cropped.save(dataPath("Sprites/" + filename + ".png"));
    } else {
      canvas.save(dataPath("Sprites/" + filename + ".png"));
    }
  }

  String generateRandomFilename() {
    String res = "";
    for (int y = 0; y < 6; y++) res += char(int(random(65, 89)));
    return res;
  }
}

// =========================================================
// FILE CALLBACKS (Must be global)
// =========================================================

void imageChosen(File f) {
  if (f == null || !f.exists()) return;
  
  PImage img = loadImage(f.getAbsolutePath());
  
  if (state.isPenImageSet) {
    penImage = img;
    state.isPenImageSet = false;
  } else {
    if (state.isBgImageActive) {
      backgroundImage = img;
    } else {
      loadedImage = img;
      state.shouldLoadImage = true;
      ui.loadMsgTimer = 300;
    }
  }
}

void folderSelected(File selection) {
  if (selection == null) return;
  
  String filename = fileManager.generateRandomFilename();
  PImage temp = get(0, 50, width, height-50);
  temp.save(selection.getPath() + File.separator + filename + ".png");
  ui.saveMsgTimer = 300;
}
