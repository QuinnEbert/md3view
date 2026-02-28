"""GL texture loading and caching with Pillow."""

import io
import sys

from OpenGL.GL import *
from PIL import Image


class TextureCache:
    def __init__(self, archive):
        self._archive = archive
        self._cache = {}
        self._white_texture = 0

    def white_texture(self):
        if self._white_texture == 0:
            tex = glGenTextures(1)
            glBindTexture(GL_TEXTURE_2D, tex)
            white = bytes([255, 255, 255, 255])
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, white)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
            self._white_texture = tex
        return self._white_texture

    def texture_for_path(self, path):
        if not path:
            return self.white_texture()

        key = path.lower()
        cached = self._cache.get(key)
        if cached is not None:
            return cached

        # Try loading the file directly
        data = self._archive.read_file(path)

        # Try alternate extensions if not found
        if data is None:
            base = path.rsplit('.', 1)[0] if '.' in path else path
            for ext in ('tga', 'jpg', 'jpeg', 'png', 'TGA', 'JPG', 'PNG'):
                data = self._archive.read_file(base + '.' + ext)
                if data is not None:
                    break

        if data is None:
            self._cache[key] = self.white_texture()
            return self.white_texture()

        try:
            img = Image.open(io.BytesIO(data))
            img = img.convert('RGBA')
            # Do NOT flip — Pillow loads top-to-bottom, matching Q3 UV convention
            width, height = img.size
            pixels = img.tobytes()
        except Exception as e:
            print(f"TextureCache: failed to decode {path}: {e}", file=sys.stderr)
            self._cache[key] = self.white_texture()
            return self.white_texture()

        tex = glGenTextures(1)
        glBindTexture(GL_TEXTURE_2D, tex)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, pixels)
        glGenerateMipmap(GL_TEXTURE_2D)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)

        self._cache[key] = tex
        return tex

    def flush(self):
        for tex in self._cache.values():
            if tex != self._white_texture:
                glDeleteTextures(1, [tex])
        self._cache.clear()
        if self._white_texture:
            glDeleteTextures(1, [self._white_texture])
            self._white_texture = 0
