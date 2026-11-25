import java.awt.CompositeContext;
import java.awt.image.ColorModel;
import java.awt.image.Raster;
import java.awt.image.WritableRaster;

final int[] BRUSH_BLEND_MODES = { BLEND, ADD, SUBTRACT, DARKEST, LIGHTEST, DIFFERENCE,
  EXCLUSION, MULTIPLY, SCREEN, REPLACE };

void applyBrushBlend(PGraphicsJava2D pixels) {
  int mode = BRUSH_BLEND_MODES[state.blendModeIndex];
  pixels.blendMode(BLEND);
  if (mode == REPLACE) {
    pixels.g2.setComposite(AlphaComposite.Src);
  } else if (mode != BLEND) {
    int backdrop = state.bgColor;
    pixels.g2.setComposite((source, destination, hints) ->
      new BrushBlendContext(source, destination, mode, backdrop));
  }
}

class BrushBlendContext implements CompositeContext {
  final ColorModel sourceModel, destinationModel;
  final int mode, backdrop;

  BrushBlendContext(ColorModel sourceModel, ColorModel destinationModel, int mode, int backdrop) {
    this.sourceModel = sourceModel;
    this.destinationModel = destinationModel;
    this.mode = mode;
    this.backdrop = backdrop;
  }

  public void compose(Raster source, Raster destination, WritableRaster output) {
    Object sourcePixel = null, destinationPixel = null, outputPixel = null;
    for (int y = 0; y < output.getHeight(); y++) {
      for (int x = 0; x < output.getWidth(); x++) {
        sourcePixel = source.getDataElements(source.getMinX() + x, source.getMinY() + y, sourcePixel);
        destinationPixel = destination.getDataElements(destination.getMinX() + x, destination.getMinY() + y, destinationPixel);
        int ink = sourceModel.getRGB(sourcePixel);
        int existing = destinationModel.getRGB(destinationPixel);
        int result = blendInk(existing, ink);
        outputPixel = destinationModel.getDataElements(result, outputPixel);
        output.setDataElements(output.getMinX() + x, output.getMinY() + y, outputPixel);
      }
    }
  }

  int blendInk(int existing, int ink) {
    int inkAlpha = ink >>> 24;
    if (inkAlpha == 0) return existing;
    int existingAlpha = existing >>> 24;
    if (existingAlpha == 255) return PImage.blendColor(existing, ink, mode);

    // Next blended against its opaque canvas. Use that color as the blend
    // reference under clear pixels while keeping the new ink on this layer.
    int reference = mixRgb(backdrop, existing, existingAlpha, 255);
    int blendedInk = PImage.blendColor(reference, ink | 0xff000000, mode);
    int alphaTimes255 = inkAlpha * 255 + existingAlpha * (255 - inkAlpha);
    int rgb = mixRgb(existing, blendedInk, inkAlpha * 255, alphaTimes255);
    return (((alphaTimes255 + 127) / 255) << 24) | (rgb & 0xffffff);
  }

  int mixRgb(int from, int to, int weight, int total) {
    int result = 0xff000000;
    for (int shift = 0; shift < 24; shift += 8) {
      int low = (from >>> shift) & 255;
      int high = (to >>> shift) & 255;
      int channel = (low * (total - weight) + high * weight + total / 2) / total;
      result |= channel << shift;
    }
    return result;
  }

  public void dispose() {}
}
