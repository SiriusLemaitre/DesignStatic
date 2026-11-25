import java.awt.image.DataBufferInt;

final int PAPER_PENCIL_MODE = 5;

void drawPaperPencil(int startX, int startY, int endX, int endY, PGraphics layer) {
  float radius = max(0.75f, state.penSize / 2);
  int left = max(0, floor(min(startX, endX) - radius));
  int canvasY = canvasTop();
  int top = max(canvasY, floor(min(startY, endY) - radius));
  int right = min(width, ceil(max(startX, endX) + radius + 1));
  int bottom = min(height, ceil(max(startY, endY) + radius + 1));
  if (left >= right || top >= bottom) return;

  BufferedImage mark = new BufferedImage(right - left, bottom - top, BufferedImage.TYPE_INT_ARGB);
  int[] ink = ((DataBufferInt)mark.getRaster().getDataBuffer()).getData();
  float dx = endX - startX, dy = endY - startY;
  float lengthSquared = dx * dx + dy * dy;
  int rgb = state.penColor & 0xffffff;
  for (int y = top; y < bottom; y++) {
    for (int x = left; x < right; x++) {
      float offsetX = x - startX, offsetY = y - startY;
      float along = lengthSquared == 0 ? 0 : constrain((offsetX * dx + offsetY * dy) / lengthSquared, 0, 1);
      float distance = mag(offsetX - dx * along, offsetY - dy * along);
      if (distance >= radius + 0.25f) continue;

      // Anchor the paper grain to the artwork so it stays still beneath the pencil.
      int grain = x * 374761393 + (y - canvasY) * 668265263;
      grain = (grain ^ (grain >>> 13)) * 1274126177;
      float tooth = ((grain ^ (grain >>> 16)) & 255) / 255.0f;
      if (tooth < 0.17f && distance > 0.5f) continue;
      float edge = constrain((radius + 0.25f - distance) / max(0.75f, radius * 0.5f), 0, 1);
      int alpha = round(state.penOpacity * edge * (0.20f + tooth * 0.63f));
      if (alpha > 0) ink[(y - top) * mark.getWidth() + x - left] = (alpha << 24) | rgb;
    }
  }

  Graphics2D renderer = ((PGraphicsJava2D)layer).g2;
  Composite previous = renderer.getComposite();
  if (BRUSH_BLEND_MODES[state.blendModeIndex] == REPLACE) {
    renderer.setComposite((source, destination, hints) ->
      new BrushBlendContext(source, destination, REPLACE, state.bgColor));
  }
  renderer.drawImage(mark, left, top, null);
  renderer.setComposite(previous);
}
