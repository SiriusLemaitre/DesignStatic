DesignStatic is a handcrafted drawing software made for extremly fast sprite making workflow

## Design Static Pro

Open `DesignStaticPro/DesignStaticPro.pde` in Processing 4 and click **Run**.

- **Toolbar.** Click the arrow at the far right to hide or show the tool controls, frames, and layers. The window resizes around the canvas.
- **Sound.** Audio starts muted. The speaker next to the arrow toggles audio. Pencil volume follows mouse speed, sharp turns briefly bring out the rasp, and the sound fades when you pause or lift. Pencil audio is adapted from [Pencil stroke slow soft by Trtle.T](https://freesound.org/people/Trtle.T/sounds/809937/) (CC0).
- **Colors.** The pen starts white on a `#D28E8E` canvas. Click the pen swatch to edit pen and background colors side by side.
- **Tool controls.** Use the row under the toolbar to choose the active tool's mode and blend, and drag the size and opacity sliders. For Fill, A and S decrease and increase size. Press Shift to randomize the pen color. Hold it for one second to start cycling. Select **Pen** and click **5** or press 5 for the textured **Paper pencil** mode.
- **Frames.** Click a number to edit that frame. **Add** inserts a blank frame with the same layer names. **Copy** duplicates the artwork and layers. **Play** loops the sequence at the selected FPS. **Onion skin** shows the previous frame behind the current one while editing.
- **Layers.** Use the arrows to select a layer and click its name to rename it. **Raise** and **Lower** change the stacking order. The eraser clears pixels on the active layer, revealing layers underneath.
- **Projects.** **Save project** and **Open project** store and restore editable `.dspro` files. The shortcuts are Ctrl+S and Ctrl+O.
- **PNG export.** Use **BG** or B for transparent export to the sketch's `data/Sprites` folder. A single frame exports as `name.png`. Animation exports create `name/name_1.png`, `name/name_2.png`, and so on. The PNGs share a crop to keep their positions aligned. **S** or N selects an export folder.
