DesignStatic is a handcrafted drawing software made for extremly fast sprite making workflow

## Design Static Pro

Open `DesignStaticPro/DesignStaticPro.pde` in Processing 4 and click **Run**.

- **Frames.** Click a number to edit that frame. **Add** inserts a blank frame with the same layer names. **Copy** duplicates the artwork and layers. **Play** loops the sequence at the selected FPS. **Onion skin** shows the previous frame behind the current one while editing.
- **Layers.** Use the arrows to select a layer and click its name to rename it. **Raise** and **Lower** change the stacking order. The eraser clears pixels on the active layer, revealing layers underneath.
- **Projects.** **Save project** and **Open project** store and restore editable `.dspro` files. The shortcuts are Ctrl+S and Ctrl+O.
- **PNG export.** Use **BG** or B for transparent export to the sketch's `data/Sprites` folder. A single frame exports as `name.png`. Animation exports create `name/name_1.png`, `name/name_2.png`, and so on. The PNGs share a crop to keep their positions aligned. **S** or N selects an export folder.
