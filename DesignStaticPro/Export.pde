import java.awt.Rectangle;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import javax.imageio.ImageIO;

class FileManager {
  void selectImageForLoad(boolean isBg) {
    selectInput("Select an image", isBg ? "backgroundChosen" : "imageChosen");
  }

  void selectImageForPen() {
    selectInput("Select an image", "penImageChosen");
  }

  void saveCustomLocation() {
    selectFolder("Select an export folder", "folderSelected");
  }

  String promptForFilename() {
    String name = JOptionPane.showInputDialog(null, "Enter sprite name", "Save Image", JOptionPane.PLAIN_MESSAGE);
    if (name == null) return null;
    name = name.trim();
    if (name.isEmpty()) return generateRandomFilename();
    if (name.equals(".") || name.endsWith(".") || name.matches(".*[<>:\"/\\\\|?*\\p{Cntrl}].*")) {
      showError("Choose a name without invalid filename characters.");
      return null;
    }
    return name;
  }

  void quickSave() {
    String name = promptForFilename();
    if (name != null) export(new File(dataPath("")).toPath(), name, false);
  }

  void saveTransparent() {
    String name = promptForFilename();
    if (name != null) export(new File(dataPath("Sprites")).toPath(), name, true);
  }

  void saveInFolder(File selection) {
    if (artwork.frames.size() > 1) {
      String name = promptForFilename();
      if (name != null) export(selection.toPath(), name, true);
      return;
    }
    String name;
    do {
      name = generateRandomFilename();
    } while (new File(selection, name + ".png").exists());
    export(selection.toPath(), name, false);
  }

  void export(Path parent, String name, boolean transparent) {
    finishStroke();
    int frameCount = artwork.frames.size();
    Path output = parent.resolve(frameCount > 1 ? name : name + ".png");
    try {
      Files.createDirectories(parent);
      if (Files.exists(output)) {
        showError("“" + output.getFileName() + "” already exists. Choose another name.");
        return;
      }
      if (frameCount > 1) {
        exportAnimation(parent, output, name);
      } else {
        AnimationFrame frame = artwork.currentFrame();
        if (transparent) {
          Rectangle crop = exportBounds(artwork.frames);
          writeSinglePng(parent, output, renderSprite(frame, crop));
        } else {
          writeSinglePng(parent, output, artwork.composite(frame, true, width, artwork.visibleHeight()));
        }
      }
      ui.showFileMessage("Design saved");
      println("Saved to " + output);
    } catch (IOException | RuntimeException error) {
      showError("Could not export the sprite.\n" + error.getMessage());
    }
  }

  void exportAnimation(Path parent, Path output, String name) throws IOException {
    Rectangle crop = exportBounds(artwork.frames);
    Path staging = Files.createTempDirectory(parent, ".sprite-");
    ArrayList<Path> files = new ArrayList<Path>();
    try {
      for (int i = 0; i < artwork.frames.size(); i++) {
        Path file = staging.resolve(name + "_" + (i + 1) + ".png");
        files.add(file);
        writePng(file, renderSprite(artwork.frames.get(i), crop));
      }
      Files.move(staging, output);
    } finally {
      for (Path file : files) Files.deleteIfExists(file);
      Files.deleteIfExists(staging);
    }
  }

  void writeSinglePng(Path parent, Path output, BufferedImage image) throws IOException {
    Path staging = Files.createTempFile(parent, ".sprite-", ".png");
    try {
      writePng(staging, image);
      Files.move(staging, output);
    } finally {
      Files.deleteIfExists(staging);
    }
  }

  void writePng(Path file, BufferedImage image) throws IOException {
    if (!ImageIO.write(image, "PNG", file.toFile())) throw new IOException("PNG writer unavailable.");
  }

  Rectangle exportBounds(ArrayList<AnimationFrame> frames) {
    int left = width, top = artwork.visibleHeight(), right = -1, bottom = -1;
    for (AnimationFrame frame : frames) {
      for (DrawingLayer layer : frame.layers) {
        if (!layer.visible || layer.pixels == null) continue;
        PGraphics pixels = layer.pixels;
        int columns = min(width, pixels.width);
        int rows = min(artwork.visibleHeight(), pixels.height);
        for (int y = 0; y < rows; y++) {
          for (int x = 0; x < columns; x++) {
            if ((pixels.pixels[y * pixels.width + x] >>> 24) == 0) continue;
            left = min(left, x);
            top = min(top, y);
            right = max(right, x);
            bottom = max(bottom, y);
          }
        }
      }
    }
    if (right < left) return new Rectangle(0, 0, width, artwork.visibleHeight());
    return new Rectangle(left, top, right - left + 1, bottom - top + 1);
  }

  BufferedImage renderSprite(AnimationFrame frame, Rectangle crop) {
    BufferedImage result = new BufferedImage(crop.width, crop.height, BufferedImage.TYPE_INT_ARGB);
    Graphics2D renderer = result.createGraphics();
    artwork.drawLayers(renderer, frame, -crop.x, -crop.y);
    renderer.dispose();
    return result;
  }

  String generateRandomFilename() {
    String name = "";
    for (int i = 0; i < 6; i++) name += char(int(random(65, 89)));
    return name;
  }

  void showError(String message) {
    JOptionPane.showMessageDialog(null, message, "Design Static Pro", JOptionPane.ERROR_MESSAGE);
  }
}

void imageChosen(File selection) {
  if (selection == null) return;
  sketchActions.add(() -> {
    PImage imported = loadSelectedImage(selection);
    if (imported != null) artwork.importImage(imported);
  });
}

void backgroundChosen(File selection) {
  if (selection == null) return;
  sketchActions.add(() -> {
    PImage imported = loadSelectedImage(selection);
    if (imported == null) return;
    backgroundImage = imported;
    state.isBgImageActive = true;
    artwork.dirty = true;
  });
}

void penImageChosen(File selection) {
  if (selection == null) return;
  sketchActions.add(() -> {
    PImage imported = loadSelectedImage(selection);
    if (imported == null) return;
    penImage = imported;
    artwork.dirty = true;
  });
}

PImage loadSelectedImage(File file) {
  PImage imported = loadImage(file.getAbsolutePath());
  if (imported != null && imported.width > 0 && imported.height > 0) return imported;
  fileManager.showError("Could not open “" + file.getName() + "” as an image.");
  return null;
}

void folderSelected(File selection) {
  if (selection != null) sketchActions.add(() -> fileManager.saveInFolder(selection));
}
