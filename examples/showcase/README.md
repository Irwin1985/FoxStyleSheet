# Showcase: FoxStyleSheet + VFPStretch

A complete Visual FoxPro 9 application with one screen, a customer record, that takes its
look from [FoxStyleSheet](https://github.com/Irwin1985/FoxStyleSheet) and stretches with its
window thanks to [VFPStretch](https://github.com/Irwin1985/VFPStretch). The form itself has
no colours: change the theme and the same screen looks different.

- It opens with the theme Windows uses (light or dark), or with the one the user chose last.
- The sun and moon button switches between `light` and `dark`; the combo offers every
  built-in theme.
- On Windows 10 and 11 the title bar follows the theme.
- Drag the border, or maximize: every control, font, grid and list follows.

## Run it

The two libraries come with FoxPack, into `lib\`:

```
foxpack add foxstylesheet
foxpack add vfpstretch
```

Then, from this folder:

```foxpro
DO main.prg
```

or build `showcase.pjx` as an EXE and run `showcase.exe`.

## Where to look

| File | What it shows |
|---|---|
| `main.prg` | Loads the two libraries and creates `_Screen.oVfpStretch`, once for the whole application |
| `frmcustomers.prg` | The screen. `Init` links the theme first and then calls VFPStretch; `ApplyTheme()` and `OnThemeChanged()` switch it and save the choice in `%APPDATA%\FoxShowcase\theme.txt` |
| `config.fpw` | `SCREEN=OFF`: as an EXE the form is the whole application |
