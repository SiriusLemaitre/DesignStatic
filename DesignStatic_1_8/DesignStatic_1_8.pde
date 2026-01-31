import java.io.File;
import javax.swing.JOptionPane;

// =========================================================
// GLOBAL CONSTANTS & ENUMS
// =========================================================
final int UI_HEIGHT = 60; // Increased slightly for better spacing
final int CANVAS_WIDTH = 600;
final int CANVAS_HEIGHT = 650;

enum ToolType { PEN, FILL, DESIGN, RECT, CHEMISTRY, ERASER, IMAGE_PEN }

// =========================================================
// MAIN SKETCH
// =========================================================

AppState state;
UIManager ui;
ToolManager tools;
FileManager fileManager;

PImage loadedImage;
PImage backgroundImage;
PImage penImage;

int mouseDirY = 0;
int mouseDirX = 0;
color currentPixelColor, prevPixelColor;

void setup() {
  size(600, 650);
  surface.setResizable(true);
  frameRate(120);
  rectMode(CORNER);
  noSmooth(); 

  // Initialize Systems
  state = new AppState();
  ui = new UIManager();
  tools = new ToolManager();
  fileManager = new FileManager();
  
  state.randomizeBgColor();
  background(state.bgColor);
}

void draw() {
  // Blend Mode
  if (state.blendModeIndex == 0) blendMode(BLEND);
  else setBlendMode(state.blendModeIndex);

  // Updates
  currentPixelColor = get(mouseX, mouseY);
  prevPixelColor = get(pmouseX, pmouseY);
  updateMouseDirection();

  // Draw UI (Always on top, no blend mode)
  blendMode(BLEND);
  ui.drawUI();
  
  // Handle Images
  if (state.shouldLoadImage && loadedImage != null) {
    image(loadedImage, width/2 - loadedImage.width/2, height/2 - loadedImage.height/2);
    state.shouldLoadImage = false;
  }
  
  ui.updateTimers();
}

// =========================================================
// INPUT HANDLING
// =========================================================

void mousePressed() {
  if (mouseY < UI_HEIGHT) {
    ui.handleMousePress();
    return;
  }
  if (mouseButton == RIGHT) {
    color c = get(mouseX, mouseY);
    state.setPenColor(c);
    return;
  }
  if (mouseButton == LEFT) {
    tools.handlePress();
  }
}

void mouseDragged() {
  state.oilThickness -= 0.05;
  if (state.oilThickness < 0.1) state.oilThickness = 0.0;

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
  state.oilThickness = 4;
  tools.handleRelease();
}

void mouseMoved() {
  state.penStart.set(mouseX, mouseY);
}

void mouseWheel(MouseEvent event) {
  float e = event.getCount();
  state.isWritingHex = false;
  state.adjustPenColor(e * -2);
}

void mouseClicked() {
  // Trigger Hex writing mode if clicked on the hex box
  if (mouseButton == LEFT && mouseX > 60 && mouseX < 130 && mouseY > 35 && mouseY < 55) {
    state.isWritingHex = true;
    state.hexInput = "";
  }
}

void keyPressed() {
  if (state.isWritingHex) return; 

  if (key == ' ') handleReset();
  if (key == CODED) {
    if (keyCode == CONTROL) fileManager.quickSave();
    if (keyCode == UP || keyCode == DOWN || keyCode == LEFT || keyCode == RIGHT) {
      state.randomizeBgColor();
      background(state.bgColor);
    }
    if (keyCode == SHIFT) state.randomizePenColor();
  }

  if (key == 'q') state.currentTool = ToolType.PEN;
  if (key == 'w') state.currentTool = ToolType.FILL;
  if (key == 'e') state.currentTool = ToolType.DESIGN;
  if (key == 'r') state.currentTool = ToolType.RECT;
  if (key == 't') state.currentTool = ToolType.CHEMISTRY;
  if (key == 'd') state.currentTool = ToolType.ERASER;
  if (key == 'f') state.currentTool = ToolType.IMAGE_PEN;

  if (key >= '1' && key <= '4') {
    state.subToolMode = int(String.valueOf(key));
  }
  
  handleParameterAdjustments();

  if (key == 'v') fileManager.selectImageForLoad(false);
  if (key == 'm') fileManager.selectImageForLoad(true); 
  if (key == 'j') state.isBgImageActive = false;
  if (key == 'k') state.isLocked = true;
  if (key == 'l') state.isLocked = false;
  if (key == 'g') fileManager.selectImageForPen();
  if (key == 'n') fileManager.saveCustomLocation();
  if (key == 'b') fileManager.saveTransparent();
  if (key == 'o') state.setPenColor(color(255)); 
  if (key == 'p') state.setPenColor(color(0));   
  
  if (key == 'y') {
    state.blendModeIndex++;
    if (state.blendModeIndex > 9) state.blendModeIndex = 0;
  }
  
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
    if (state.subToolMode == 3) { 
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
  color bgColor;
  color penColor;
  
  ToolType currentTool = ToolType.PEN;
  int subToolMode = 1; 
  
  float penSize = 6;
  float rectSize = 33.0;
  float rectStroke = 1.0;
  float chemistryAlpha = 60.0;
  float bezierWeight = 6;
  float oilThickness = 4;
  float splashWidth = 30;
  float splashConcentration = 8;
  
  PVector penStart = new PVector(0,0);
  PVector shapeStart = new PVector(300, 300);
  PVector eraserStart = new PVector(300, 300);
  float penPixelCounter = 0;
  float sewingCountdown = 0;
  int chemistrySwitchR = 1;
  boolean switchS = false;
  
  int[] verticesX = new int[50];
  int[] verticesY = new int[50];
  int vertIndex = 0;
  
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
// CLASS: UI MANAGER & VISUALS
// =========================================================
class UIManager {
  float saveMsgTimer = 0;
  float loadMsgTimer = 0;
  
  // Theme Colors
  color colBg = color(40, 40, 40);
  color colPanel = color(60, 60, 60);
  color colActive = color(59, 149, 214); // Blue accent
  color colText = color(220);
  color colHover = color(80, 80, 80);
  
  ArrayList<UIButton> buttons;

  UIManager() {
    buttons = new ArrayList<UIButton>();
    // Tools
    buttons.add(new UIButton(ToolType.PEN, 200, 10));
    buttons.add(new UIButton(ToolType.FILL, 250, 10));
    buttons.add(new UIButton(ToolType.DESIGN, 300, 10));
    buttons.add(new UIButton(ToolType.RECT, 350, 10));
    buttons.add(new UIButton(ToolType.CHEMISTRY, 400, 10));
    buttons.add(new UIButton(ToolType.ERASER, 450, 10));
    
    // File Actions (Using pseudo-tooltypes for detection, handled manually)
    // We will just draw these manually or add specific buttons if we wanted full OOP
  }
  
  void drawUI() {
    // Background Bar
    noStroke();
    fill(colBg);
    rect(0, 0, width, UI_HEIGHT);
    
    // Color Section
    drawColorSection();
    
    // Separators
    stroke(80);
    line(180, 10, 180, 50);
    line(490, 10, 490, 50);

    // Tools
    for (UIButton b : buttons) {
      b.update();
      b.display();
    }
    
    // File Buttons
    drawFileButtons();
    
    // Messages
    fill(colText);
    textSize(10);
    textAlign(RIGHT);
    if (saveMsgTimer > 0) text("Saved.", width - 10, 50);
    else if (loadMsgTimer > 0) text("Loaded.", width - 10, 50);
    textAlign(LEFT);
  }
  
  void drawColorSection() {
    // Color Preview
    fill(colPanel);
    rect(10, 10, 40, 40, 5);
    
    fill(state.penColor);
    noStroke();
    circle(30, 30, 24);
    
    // Hex Input
    fill(state.isWritingHex ? colActive : colPanel);
    rect(60, 18, 70, 24, 4);
    
    fill(colText);
    textSize(12);
    textAlign(LEFT, CENTER);
    String label = state.isWritingHex ? "#" + state.hexInput.toUpperCase() : "#" + hex(state.penColor, 6);
    if(state.isWritingHex && frameCount % 60 < 30) label += "|"; // Cursor
    text(label, 65, 29);
    
    // Helper Text
    fill(120);
    textSize(9);
    text("R-Click: Pick", 60, 50);
    
    // Update Hex Logic
    if (state.isWritingHex && state.hexInput.length() == 6) {
        int hi = unhex(state.hexInput.toUpperCase());
        state.penColor = color(red(hi), green(hi), blue(hi));
        state.isWritingHex = false;
    }
  }
  
  void drawFileButtons() {
    drawMiniButton("LOAD", 500, 10, 40, 18, "L");
    drawMiniButton("SAVE", 545, 10, 40, 18, "S");
    drawMiniButton("QUICK", 500, 32, 40, 18, "Q");
    drawMiniButton("PNG", 545, 32, 40, 18, "T");
  }
  
  void drawMiniButton(String label, int x, int y, int w, int h, String shortKey) {
    boolean hover = mouseX > x && mouseX < x+w && mouseY > y && mouseY < y+h;
    
    fill(hover ? colHover : colPanel);
    stroke(0);
    rect(x, y, w, h, 3);
    
    fill(colText);
    textSize(9);
    textAlign(CENTER, CENTER);
    text(label, x + w/2, y + h/2);
    textAlign(LEFT); // Reset
  }
  
  void updateTimers() {
    if (saveMsgTimer > 0) saveMsgTimer--;
    if (loadMsgTimer > 0) loadMsgTimer--;
    if (mousePressed) {
      state.sewingCountdown--;
      if (state.sewingCountdown < 0) state.sewingCountdown = 5;
    }
  }
  
  void handleMousePress() {
    // Color click
    if (mouseX > 10 && mouseX < 50) state.randomizePenColor();
    
    // Tools
    for (UIButton b : buttons) {
      if (b.isHovered()) {
        state.currentTool = b.type;
        return; 
      }
    }
    
    // File Actions (Hardcoded coords for simplicity)
    if (mouseY > 10 && mouseY < 28) {
      if (mouseX > 500 && mouseX < 540) fileManager.selectImageForLoad(false); // Load
      if (mouseX > 545 && mouseX < 585) fileManager.saveCustomLocation(); // Save
    }
    if (mouseY > 32 && mouseY < 50) {
      if (mouseX > 500 && mouseX < 540) fileManager.quickSave(); // Quick
      if (mouseX > 545 && mouseX < 585) fileManager.saveTransparent(); // PNG
    }
  }
  
  // --- BUTTON INNER CLASS ---
  class UIButton {
    ToolType type;
    int x, y, w, h;
    
    UIButton(ToolType t, int _x, int _y) {
      type = t;
      x = _x; y = _y;
      w = 40; h = 40;
    }
    
    boolean isHovered() {
      return mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
    }
    
    void update() {}
    
    void display() {
      boolean active = state.currentTool == type;
      boolean hover = isHovered();
      
      // Base
      noStroke();
      if (active) fill(colPanel);
      else if (hover) fill(colHover);
      else fill(colBg);
      
      // Active Indicator (Border or background)
      if (active) {
        stroke(colActive);
        strokeWeight(2);
        rect(x, y, w, h, 5);
        noStroke();
      } else {
        // Just rounded bg
        if (hover) rect(x, y, w, h, 5);
      }
      
      // Icon
      stroke(active ? colActive : colText);
      strokeWeight(1.5);
      noFill();
      drawIcon(type, x + w/2, y + h/2);
      
      // Sub-tool Dots
      if (active) {
        noStroke();
        fill(colActive);
        int dots = state.subToolMode;
        float startX = x + w/2 - ((dots-1)*4)/2.0;
        for(int i=0; i<dots; i++) {
          circle(startX + i*4, y + h - 5, 2);
        }
      }
    }
  }
  
  void drawIcon(ToolType t, float cx, float cy) {
    switch(t) {
      case PEN:
        line(cx-5, cy+5, cx+5, cy-5);
        line(cx-5, cy+5, cx-7, cy+7); // Tip
        break;
      case FILL:
        beginShape();
        vertex(cx-6, cy-4); vertex(cx+6, cy-4);
        vertex(cx+4, cy+6); vertex(cx-4, cy+6);
        endShape(CLOSE);
        line(cx, cy-4, cx, cy-8); // Handle
        break;
      case DESIGN:
        circle(cx, cy, 10);
        line(cx-6, cy, cx+6, cy);
        line(cx, cy-6, cx, cy+6);
        break;
      case RECT:
        rect(cx-6, cy-4, 12, 8);
        break;
      case CHEMISTRY:
        beginShape();
        vertex(cx-3, cy-6); vertex(cx+3, cy-6);
        vertex(cx+5, cy+6); vertex(cx-5, cy+6);
        endShape(CLOSE);
        break;
      case ERASER:
        rectMode(CENTER);
        pushMatrix();
        translate(cx, cy);
        rotate(PI/4);
        rect(0, 0, 12, 6);
        popMatrix();
        rectMode(CORNER);
        break;
      case IMAGE_PEN:
        rect(cx-5, cy-5, 10, 10);
        point(cx, cy);
        break;
    }
  }
}

// =========================================================
// CLASS: TOOL MANAGER
// =========================================================
class ToolManager {
  
  void handlePress() {
    if (mouseY > UI_HEIGHT + 10) {
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
  }
  
  void handleRelease() {
    if (state.currentTool == ToolType.FILL) {
      beginShape(POINTS);
      tint(state.penColor);
      for (int k = 0; k < state.vertIndex; k++) {} // Placeholder logic
      endShape(CLOSE);
    }
  }

  void drawPenDrag() {
    stroke(state.penColor);
    if (state.subToolMode == 2) { 
      strokeWeight(state.penSize);
      line(state.penStart.x, state.penStart.y, mouseX, mouseY);
    } else if (state.subToolMode == 1) {
      strokeWeight(state.penSize);
      line(mouseX, mouseY, pmouseX, pmouseY);
    } else if (state.subToolMode == 3) {
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
      drawScratchLines(); 
    } else if (state.subToolMode == 3) {
      strokeWeight(state.bezierWeight);
      bezier(mouseX, mouseY, pmouseX, pmouseY, mouseX, mouseY, pmouseX/1.5, pmouseY/1.5);
    } else if (state.subToolMode == 4) {
      int X_AXIS = 2;
      if (!state.switchS) setGradient(mouseX-25, int(pmouseY-mouseDirY*5), 50, mouseDirY*10, currentPixelColor, prevPixelColor, X_AXIS);
      else setGradient(mouseX-mouseDirX*5, pmouseY-25, mouseDirX*10, 50, currentPixelColor, prevPixelColor, X_AXIS);
    }
  }
  
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
    
    ui.saveMsgTimer = 300;
    
    // Capture canvas excluding UI
    PImage temp = get(0, UI_HEIGHT, 600, 600);
    
    // Save to data folder
    temp.save(dataPath(filename + ".png"));
    println("Saved as: " + filename + ".png");
  }
  
  void saveTransparent() {
    String filename = promptForFilename();
    if (filename == null) return; // User pressed Cancel
    
    ui.saveMsgTimer = 300;
    
    PImage canvas = get(0, UI_HEIGHT, width, height-UI_HEIGHT);
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
    String path = "Sprites/" + filename + ".png";
    
    if (maxX >= minX && maxY >= minY) {
      PImage cropped = canvas.get(minX, minY, maxX - minX + 1, maxY - minY + 1);
      cropped.save(dataPath(path));
    } else {
      canvas.save(dataPath(path));
    }
    println("Saved transparent as: " + filename + ".png");
  }

  String generateRandomFilename() {
    String res = "";
    for (int y = 0; y < 6; y++) res += char(int(random(65, 89)));
    return res;
  }
}

// =========================================================
// FILE CALLBACKS
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
  PImage temp = get(0, UI_HEIGHT, width, height-UI_HEIGHT);
  temp.save(selection.getPath() + File.separator + filename + ".png");
  ui.saveMsgTimer = 300;
}
