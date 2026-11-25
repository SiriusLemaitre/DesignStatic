import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.InputStream;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.StandardCopyOption;
import java.util.Locale;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

class ProjectFiles {
  final String EXTENSION = ".dspro";
  final String MANIFEST = "project.dat";
  final int MAGIC = 0x44535052; // DSPR
  final int VERSION = 1;
  File currentFile;

  void selectSave() {
    File suggested = currentFile == null ? new File(sketchPath("Untitled" + EXTENSION)) : currentFile;
    selectOutput("Save Design Static Pro project", "projectSaveChosen", suggested);
  }

  void selectLoad() {
    selectInput("Open Design Static Pro project", "projectOpenChosen", currentFile);
  }

  void save(File selection) {
    finishStroke();
    if (!selection.getName().toLowerCase(Locale.ROOT).endsWith(EXTENSION)) {
      selection = new File(selection.getParentFile(), selection.getName() + EXTENSION);
      if (selection.exists() && JOptionPane.showConfirmDialog(null,
          "Replace “" + selection.getName() + "”?", "Save Project",
          JOptionPane.OK_CANCEL_OPTION, JOptionPane.WARNING_MESSAGE) != JOptionPane.OK_OPTION) return;
    }
    try {
      writeProject(selection.toPath().toAbsolutePath());
      currentFile = selection;
      artwork.dirty = false;
      ui.showFileMessage("Project saved");
    } catch (IOException | RuntimeException error) {
      fileManager.showError("Could not save the project.\n" + error.getMessage());
    }
  }

  void writeProject(Path destination) throws IOException {
    Path staging = Files.createTempFile(destination.getParent(), ".design-static-", EXTENSION);
    try {
      try (ZipOutputStream zip = new ZipOutputStream(Files.newOutputStream(staging))) {
        zip.putNextEntry(new ZipEntry(MANIFEST));
        DataOutputStream data = new DataOutputStream(zip);
        data.writeInt(MAGIC);
        data.writeInt(VERSION);
        data.writeInt(width);
        data.writeInt(artwork.visibleHeight());
        data.writeInt(artwork.fps);
        data.writeBoolean(artwork.onionSkin);
        data.writeInt(artwork.selectedFrame);
        writeSettings(data);
        data.writeBoolean(backgroundImage != null);
        data.writeBoolean(penImage != null);
        data.writeInt(artwork.frames.size());
        for (AnimationFrame frame : artwork.frames) {
          data.writeInt(frame.selectedLayer);
          data.writeInt(frame.layers.size());
          for (DrawingLayer layer : frame.layers) {
            data.writeUTF(layer.name);
            data.writeBoolean(layer.visible);
            data.writeBoolean(layer.pixels != null);
          }
        }
        data.flush();
        zip.closeEntry();

        if (backgroundImage != null) writeImage(zip, "background.png", (BufferedImage)backgroundImage.getImage());
        if (penImage != null) writeImage(zip, "brush.png", (BufferedImage)penImage.getImage());
        for (int f = 0; f < artwork.frames.size(); f++) {
          AnimationFrame frame = artwork.frames.get(f);
          for (int l = 0; l < frame.layers.size(); l++) {
            PGraphics pixels = frame.layers.get(l).pixels;
            if (pixels != null) writeImage(zip, layerPath(f, l), (BufferedImage)pixels.image);
          }
        }
      }
      try {
        Files.move(staging, destination, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
      } catch (AtomicMoveNotSupportedException error) {
        Files.move(staging, destination, StandardCopyOption.REPLACE_EXISTING);
      }
    } finally {
      Files.deleteIfExists(staging);
    }
  }

  void open(File selection) {
    finishStroke();
    if (artwork.dirty && JOptionPane.showConfirmDialog(null,
        "Open another project and discard unsaved changes?", "Open Project",
        JOptionPane.OK_CANCEL_OPTION, JOptionPane.WARNING_MESSAGE) != JOptionPane.OK_OPTION) return;

    try {
      LoadedProject loaded = readProject(selection);
      for (AnimationFrame frame : artwork.frames) frame.dispose();
      artwork = loaded.artwork;
      state = loaded.state;
      backgroundImage = loaded.background;
      penImage = loaded.brush;
      currentFile = selection;
      surface.setSize(max(START_WIDTH, loaded.canvasWidth), max(MIN_HEIGHT, loaded.canvasHeight + CANVAS_TOP));
      ui.showFileMessage("Project opened");
    } catch (IOException | RuntimeException error) {
      fileManager.showError("Could not open the project.\n" + error.getMessage());
    }
  }

  LoadedProject readProject(File source) throws IOException {
    LoadedProject loaded = new LoadedProject();
    try (ZipFile zip = new ZipFile(source);
         DataInputStream data = new DataInputStream(openEntry(zip, MANIFEST))) {
      if (data.readInt() != MAGIC || data.readInt() != VERSION) {
        throw new IOException("Unsupported Design Static Pro project format.");
      }
      loaded.canvasWidth = readRange(data, 1, 32768);
      loaded.canvasHeight = readRange(data, 1, 32768);
      loaded.artwork.fps = readRange(data, 1, 60);
      loaded.artwork.onionSkin = data.readBoolean();
      int selectedFrame = data.readInt();
      loaded.state = readSettings(data);
      if (data.readBoolean()) loaded.background = toPImage(readImage(zip, "background.png"));
      if (data.readBoolean()) loaded.brush = toPImage(readImage(zip, "brush.png"));
      loaded.state.isBgImageActive &= loaded.background != null;
      int frameCount = readRange(data, 1, Integer.MAX_VALUE);
      if (selectedFrame < 0 || selectedFrame >= frameCount) throw new IOException("Invalid selected frame.");
      loaded.artwork.selectedFrame = selectedFrame;
      loaded.artwork.frames.clear();
      for (int f = 0; f < frameCount; f++) {
        AnimationFrame frame = new AnimationFrame();
        loaded.artwork.frames.add(frame);
        frame.selectedLayer = data.readInt();
        int layerCount = readRange(data, 1, Integer.MAX_VALUE);
        if (frame.selectedLayer < 0 || frame.selectedLayer >= layerCount) {
          throw new IOException("Invalid selected layer.");
        }
        for (int l = 0; l < layerCount; l++) {
          DrawingLayer layer = new DrawingLayer(data.readUTF());
          frame.layers.add(layer);
          layer.visible = data.readBoolean();
          if (data.readBoolean()) {
            BufferedImage image = readImage(zip, layerPath(f, l));
            layer.pixels = loaded.artwork.newLayerPixels(image.getWidth(), image.getHeight(), image);
          }
        }
      }
      if (data.read() != -1) throw new IOException("Unexpected project metadata.");
    } catch (IOException | RuntimeException error) {
      for (AnimationFrame frame : loaded.artwork.frames) frame.dispose();
      throw error;
    }
    return loaded;
  }

  void writeSettings(DataOutputStream data) throws IOException {
    data.writeInt(state.bgColor);
    data.writeInt(state.penColor);
    data.writeInt(state.penOpacity);
    data.writeUTF(state.currentTool.name());
    data.writeInt(state.subToolMode);
    data.writeInt(state.blendModeIndex);
    data.writeInt(state.chemistrySwitchR);
    data.writeBoolean(state.switchS);
    data.writeBoolean(state.isLocked);
    data.writeBoolean(state.isBgImageActive);
    data.writeFloat(state.penSize);
    data.writeFloat(state.eraserSize);
    data.writeFloat(state.rectSize);
    data.writeFloat(state.rectStroke);
    data.writeFloat(state.chemistryAlpha);
    data.writeFloat(state.bezierWeight);
    data.writeFloat(state.splashWidth);
    data.writeFloat(state.splashConcentration);
  }

  AppState readSettings(DataInputStream data) throws IOException {
    AppState restored = new AppState();
    restored.bgColor = data.readInt() | 0xff000000;
    restored.setPenColor(data.readInt());
    restored.penOpacity = readRange(data, 0, 255);
    restored.currentTool = ToolType.valueOf(data.readUTF());
    restored.subToolMode = readRange(data, 1, 4);
    restored.blendModeIndex = readRange(data, 0, 9);
    restored.chemistrySwitchR = readRange(data, 1, 4);
    restored.switchS = data.readBoolean();
    restored.isLocked = data.readBoolean();
    restored.isBgImageActive = data.readBoolean();
    restored.penSize = readSetting(data);
    restored.eraserSize = readSetting(data);
    restored.rectSize = readSetting(data);
    restored.rectStroke = readSetting(data);
    restored.chemistryAlpha = readSetting(data);
    restored.bezierWeight = readSetting(data);
    restored.splashWidth = readSetting(data);
    restored.splashConcentration = readSetting(data);
    return restored;
  }

  int readRange(DataInputStream data, int lower, int upper) throws IOException {
    int value = data.readInt();
    if (value < lower || value > upper) throw new IOException("Invalid project metadata.");
    return value;
  }

  float readSetting(DataInputStream data) throws IOException {
    float value = data.readFloat();
    if (!Float.isFinite(value) || value < 0 || value > 255) throw new IOException("Invalid tool setting.");
    return value;
  }

  String layerPath(int frame, int layer) {
    return "frames/" + frame + "/" + layer + ".png";
  }

  void writeImage(ZipOutputStream zip, String name, BufferedImage image) throws IOException {
    zip.putNextEntry(new ZipEntry(name));
    if (!ImageIO.write(image, "PNG", zip)) throw new IOException("PNG writer unavailable.");
    zip.closeEntry();
  }

  InputStream openEntry(ZipFile zip, String name) throws IOException {
    ZipEntry entry = zip.getEntry(name);
    if (entry == null || entry.isDirectory()) throw new IOException("Missing project entry " + name);
    return zip.getInputStream(entry);
  }

  BufferedImage readImage(ZipFile zip, String name) throws IOException {
    try (InputStream input = openEntry(zip, name)) {
      BufferedImage image = ImageIO.read(input);
      if (image == null) throw new IOException("Invalid project image " + name);
      return image;
    }
  }

  PImage toPImage(BufferedImage image) {
    PImage converted = createImage(image.getWidth(), image.getHeight(), ARGB);
    converted.pixels = image.getRGB(0, 0, image.getWidth(), image.getHeight(), null, 0, image.getWidth());
    converted.updatePixels();
    return converted;
  }
}

class LoadedProject {
  final Artwork artwork = new Artwork();
  AppState state;
  PImage background;
  PImage brush;
  int canvasWidth, canvasHeight;
}

void projectSaveChosen(File selection) {
  if (selection != null) sketchActions.add(() -> projectFiles.save(selection));
}

void projectOpenChosen(File selection) {
  if (selection != null) sketchActions.add(() -> projectFiles.open(selection));
}
