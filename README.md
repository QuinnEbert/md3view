# MD3View

A cross-platform Quake 3 player model viewer with native implementations for macOS, Linux, and Windows.

Loads `.pk3` archives and renders animated three-part player models (lower/upper/head) with proper tag stitching, skin selection, and frame-interpolated animation.

## Platforms

### macOS (`mac/`)

Objective-C, Cocoa, OpenGL 3.2 Core.

**Requirements:** Xcode command line tools, macOS 10.15+

```sh
cd mac
make
open MD3View.app
```

### Linux (`lin/`)

Python 3, GTK4, PyOpenGL.

**Requirements:** Python 3.10+, GTK4 libraries, OpenGL drivers

```sh
cd lin
pip install -r requirements.txt
python main.py
```

### Windows (`win/`)

C#, WinForms, OpenTK, .NET 8.

**Requirements:** .NET 8 SDK

```sh
cd win
dotnet run --project MD3View
```

## Usage

1. **File > Open PK3** (Ctrl+O) — open a Quake 3 `.pk3` file containing player models
2. Select a model from the sidebar list
3. Choose a skin from the **Skin** dropdown
4. Pick torso/legs animations from the dropdowns
5. **Pause** to stop playback, then use **<** / **>** or arrow keys to step frames
6. Drag the sliders to scrub to a specific frame
7. Drag the mouse to orbit, scroll to zoom
8. Adjust **Gamma** to taste

### Screenshots and Renders

- **File > Save Screenshot** (Ctrl+S) — captures the current viewport at 2x resolution
- **File > Save Render** (Ctrl+Shift+S) — renders at a chosen resolution (up to 8192x8192) with automatic model framing

## Architecture

All three implementations share the same design:

| Module | Responsibility |
|---|---|
| **PK3Archive** | ZIP reading with case-insensitive file lookup |
| **MD3Model** | Binary `.md3` parser — decompresses int16 vertices and packed lat/lng normals |
| **SkinParser** | Parses `.skin` files mapping surface names to texture paths |
| **AnimationConfig** | Parses `animation.cfg` with leg frame offset calculation |
| **TextureCache** | Loads TGA/JPEG/PNG textures from the archive with GL caching |
| **ModelRenderer** | GLSL 150 shaders — vertex lerping, diffuse lighting, gamma correction |
| **MD3PlayerModel** | Three-part assembly with tag stitching, animation state machine |
| **ModelView** | GL viewport with orbit camera, FBO screenshot/render capture |

### Key technical details

- **Winding order:** `glFrontFace(GL_CW)` — Quake 3 uses clockwise winding
- **Coordinate system:** Z-up
- **Normal decompression:** lat/lng packed in an int16, converted via spherical coordinates
- **Tag stitching:** child.origin = parent.origin + tag.origin * parent.axis; child.axis = tag.axis * parent.axis
- **Leg frame offset:** `skip = LEGS_WALKCR.firstFrame - TORSO_GESTURE.firstFrame`, subtracted from all leg animation first frames

## Vendored Dependencies

The macOS build vendors two libraries in `mac/`:

- **minizip** (Gilles Vollant) — zlib-licensed ZIP reader
- **stb_image.h** v2.30 (Sean Barrett) — public domain image loader

## License

See individual vendored library headers for their respective licenses.
