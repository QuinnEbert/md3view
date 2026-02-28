"""GTK4 GLArea-based 3D viewport for MD3 player models."""

import math
import sys

import numpy as np

import gi
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, Gdk

from OpenGL.GL import *
from PIL import Image

from model_renderer import ModelRenderer


def _build_perspective(fov_y, aspect, near_z, far_z):
    """Build a column-major 4x4 perspective matrix."""
    m = np.zeros(16, dtype=np.float32)
    f = 1.0 / math.tan(fov_y * 0.5 * math.pi / 180.0)
    m[0] = f / aspect
    m[5] = f
    m[10] = (far_z + near_z) / (near_z - far_z)
    m[11] = -1.0
    m[14] = (2.0 * far_z * near_z) / (near_z - far_z)
    return m


def _build_look_at(eye_x, eye_y, eye_z, cx, cy, cz, up_x, up_y, up_z):
    """Build a column-major 4x4 lookAt matrix."""
    fx = cx - eye_x; fy = cy - eye_y; fz = cz - eye_z
    flen = math.sqrt(fx*fx + fy*fy + fz*fz)
    fx /= flen; fy /= flen; fz /= flen

    sx = fy*up_z - fz*up_y; sy = fz*up_x - fx*up_z; sz = fx*up_y - fy*up_x
    slen = math.sqrt(sx*sx + sy*sy + sz*sz)
    sx /= slen; sy /= slen; sz /= slen

    ux = sy*fz - sz*fy; uy = sz*fx - sx*fz; uz = sx*fy - sy*fx

    m = np.zeros(16, dtype=np.float32)
    m[0] = sx;  m[4] = sy;  m[8]  = sz;  m[12] = -(sx*eye_x + sy*eye_y + sz*eye_z)
    m[1] = ux;  m[5] = uy;  m[9]  = uz;  m[13] = -(ux*eye_x + uy*eye_y + uz*eye_z)
    m[2] = -fx; m[6] = -fy; m[10] = -fz; m[14] =  (fx*eye_x + fy*eye_y + fz*eye_z)
    m[3] = 0;   m[7] = 0;   m[11] = 0;   m[15] = 1
    return m


class ModelView(Gtk.GLArea):
    def __init__(self):
        super().__init__()
        self.set_required_version(3, 2)
        self.set_has_depth_buffer(True)
        self.set_auto_render(True)
        self.set_hexpand(True)
        self.set_vexpand(True)

        self.player_model = None
        self.renderer = None
        self.texture_cache = None
        self.gamma = 1.0

        self._rotation_x = 0.0
        self._rotation_y = -90.0  # Start facing camera
        self._zoom = 100.0
        self._shaders_ready = False
        self._drag_start_x = 0.0
        self._drag_start_y = 0.0
        self._tick_callback_id = None

        self.connect('realize', self._on_realize)
        self.connect('unrealize', self._on_unrealize)
        self.connect('render', self._on_render)

        # Mouse drag for orbit
        drag = Gtk.GestureDrag()
        drag.connect('drag-begin', self._on_drag_begin)
        drag.connect('drag-update', self._on_drag_update)
        self.add_controller(drag)

        # Scroll for zoom
        scroll = Gtk.EventControllerScroll(
            flags=Gtk.EventControllerScrollFlags.VERTICAL
        )
        scroll.connect('scroll', self._on_scroll)
        self.add_controller(scroll)

    def _on_realize(self, widget):
        self.make_current()
        if self.get_error() is not None:
            print("GLArea realize error", file=sys.stderr)
            return

        glEnable(GL_DEPTH_TEST)
        glEnable(GL_CULL_FACE)
        glFrontFace(GL_CW)  # Q3 winding order
        glCullFace(GL_BACK)
        glEnable(GL_BLEND)
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        glClearColor(0.2, 0.2, 0.25, 1.0)

        if self.renderer is None:
            self.renderer = ModelRenderer()
        self._shaders_ready = self.renderer.setup_shaders()
        if not self._shaders_ready:
            print("ModelView: shader setup failed", file=sys.stderr)

        # Start tick callback for continuous rendering
        self._tick_callback_id = self.add_tick_callback(self._tick)

    def _on_unrealize(self, widget):
        self.make_current()
        if self.renderer:
            self.renderer.cleanup()
        if self._tick_callback_id is not None:
            self.remove_tick_callback(self._tick_callback_id)
            self._tick_callback_id = None

    def _tick(self, widget, frame_clock):
        self.queue_render()
        return True  # keep ticking

    def _on_render(self, area, context):
        if not self._shaders_ready:
            return True

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

        if self.player_model and self.texture_cache:
            width = self.get_width()
            height = self.get_height()
            if height == 0:
                height = 1
            # Account for scale factor
            scale = self.get_scale_factor()
            gl_w = width * scale
            gl_h = height * scale
            aspect = gl_w / gl_h

            proj_matrix = _build_perspective(45.0, aspect, 1.0, 2000.0)

            center_z = self.player_model.center_height
            rad_x = self._rotation_x * math.pi / 180.0
            rad_y = self._rotation_y * math.pi / 180.0
            cam_x = self._zoom * math.cos(rad_x) * math.cos(rad_y)
            cam_y = self._zoom * math.cos(rad_x) * math.sin(rad_y)
            cam_z = center_z + self._zoom * math.sin(rad_x)

            view_matrix = _build_look_at(cam_x, cam_y, cam_z, 0, 0, center_z, 0, 0, 1)

            self.player_model.render(self.renderer, self.texture_cache,
                                     view_matrix, proj_matrix, self.gamma)

        return True

    def _on_drag_begin(self, gesture, start_x, start_y):
        self._drag_start_x = start_x
        self._drag_start_y = start_y
        self._drag_last_x = start_x
        self._drag_last_y = start_y

    def _on_drag_update(self, gesture, offset_x, offset_y):
        cur_x = self._drag_start_x + offset_x
        cur_y = self._drag_start_y + offset_y
        dx = cur_x - self._drag_last_x
        dy = cur_y - self._drag_last_y
        self._rotation_y += dx * 0.5
        self._rotation_x -= dy * 0.5  # GTK y-axis is top-down
        if self._rotation_x > 89:
            self._rotation_x = 89
        if self._rotation_x < -89:
            self._rotation_x = -89
        self._drag_last_x = cur_x
        self._drag_last_y = cur_y
        self.queue_render()

    def _on_scroll(self, controller, dx, dy):
        self._zoom += dy * 5.0
        if self._zoom < 10:
            self._zoom = 10
        if self._zoom > 500:
            self._zoom = 500
        self.queue_render()
        return True

    def capture_screenshot(self, scale=2):
        """Capture a screenshot at given scale factor. Returns PIL Image or None."""
        self.make_current()

        width = self.get_width() * self.get_scale_factor() * scale
        height = self.get_height() * self.get_scale_factor() * scale
        w, h = int(width), int(height)

        return self._render_to_image(w, h, use_smart_framing=False)

    def capture_render(self, width, height):
        """Capture a render at specified dimensions with smart framing. Returns PIL Image or None."""
        self.make_current()
        return self._render_to_image(width, height, use_smart_framing=True)

    def _render_to_image(self, w, h, use_smart_framing=False):
        """Internal: render to FBO and return PIL Image."""
        # Create FBO
        fbo = glGenFramebuffers(1)
        glBindFramebuffer(GL_FRAMEBUFFER, fbo)

        color_tex = glGenTextures(1)
        glBindTexture(GL_TEXTURE_2D, color_tex)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, None)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, color_tex, 0)

        depth_rb = glGenRenderbuffers(1)
        glBindRenderbuffer(GL_RENDERBUFFER, depth_rb)
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, w, h)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depth_rb)

        if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
            print("FBO not complete", file=sys.stderr)
            glBindFramebuffer(GL_FRAMEBUFFER, 0)
            glDeleteFramebuffers(1, [fbo])
            glDeleteTextures(1, [color_tex])
            glDeleteRenderbuffers(1, [depth_rb])
            return None

        glViewport(0, 0, w, h)
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

        if self.player_model and self.texture_cache:
            aspect = w / h
            fov_y = 45.0
            proj_matrix = _build_perspective(fov_y, aspect, 1.0, 2000.0)

            center_z = self.player_model.center_height

            if use_smart_framing:
                # Smart framing: compute zoom distance to fit bounding sphere
                radius = self.player_model.bounding_radius
                padding = 1.4
                half_fov_rad = fov_y * 0.5 * math.pi / 180.0
                dist_v = (radius * padding) / math.sin(half_fov_rad)
                half_h_fov = math.atan(math.tan(half_fov_rad) * aspect)
                dist_h = (radius * padding) / math.sin(half_h_fov)
                zoom = max(dist_v, dist_h)
            else:
                zoom = self._zoom

            rad_x = self._rotation_x * math.pi / 180.0
            rad_y = self._rotation_y * math.pi / 180.0
            cam_x = zoom * math.cos(rad_x) * math.cos(rad_y)
            cam_y = zoom * math.cos(rad_x) * math.sin(rad_y)
            cam_z = center_z + zoom * math.sin(rad_x)

            view_matrix = _build_look_at(cam_x, cam_y, cam_z, 0, 0, center_z, 0, 0, 1)

            self.player_model.render(self.renderer, self.texture_cache,
                                     view_matrix, proj_matrix, self.gamma)

        # Read pixels
        pixels = glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE)

        # Cleanup FBO
        glBindFramebuffer(GL_FRAMEBUFFER, 0)
        glDeleteFramebuffers(1, [fbo])
        glDeleteTextures(1, [color_tex])
        glDeleteRenderbuffers(1, [depth_rb])

        # Restore viewport
        scale = self.get_scale_factor()
        glViewport(0, 0, self.get_width() * scale, self.get_height() * scale)

        # Convert to PIL Image (flip vertically, strip alpha)
        img = Image.frombytes('RGBA', (w, h), pixels)
        img = img.transpose(Image.FLIP_TOP_BOTTOM)
        img = img.convert('RGB')
        return img
