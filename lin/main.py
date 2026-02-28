#!/usr/bin/env python3
"""MD3View — Quake 3 player model viewer (GTK4 + OpenGL)."""

import os
import sys

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Gio, GLib, Gdk

from pk3_archive import PK3Archive
from md3_player_model import MD3PlayerModel
from model_view import ModelView
from texture_cache import TextureCache
from md3_types import AnimNumber, AnimState, ANIMATION_NAMES, MAX_QPATH


class MD3ViewApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='com.md3view.app',
                         flags=Gio.ApplicationFlags.FLAGS_NONE)
        self._archive = None
        self._player_models = []
        self._current_model = None

        # Widgets
        self._window = None
        self._model_list = None
        self._model_view = None
        self._skin_dropdown = None
        self._torso_dropdown = None
        self._legs_dropdown = None
        self._play_pause_button = None
        self._torso_slider = None
        self._legs_slider = None
        self._torso_frame_label = None
        self._legs_frame_label = None
        self._gamma_slider = None
        self._gamma_label = None
        self._ui_timer_id = None

        # String lists for dropdowns
        self._skin_model = None
        self._torso_model = None
        self._legs_model = None

    def do_activate(self):
        self._create_actions()
        self._create_window()

    def _create_actions(self):
        open_action = Gio.SimpleAction.new('open', None)
        open_action.connect('activate', self._on_open)
        self.add_action(open_action)
        self.set_accels_for_action('app.open', ['<Control>o'])

        save_screenshot = Gio.SimpleAction.new('save-screenshot', None)
        save_screenshot.connect('activate', self._on_save_screenshot)
        self.add_action(save_screenshot)
        self.set_accels_for_action('app.save-screenshot', ['<Control>s'])

        save_render = Gio.SimpleAction.new('save-render', None)
        save_render.connect('activate', self._on_save_render)
        self.add_action(save_render)
        self.set_accels_for_action('app.save-render', ['<Control><Shift>s'])

    def _create_window(self):
        self._window = Gtk.ApplicationWindow(application=self, title='MD3View')
        self._window.set_default_size(1024, 768)

        # Header bar with menu
        header = Gtk.HeaderBar()
        self._window.set_titlebar(header)

        menu_model = Gio.Menu()
        menu_model.append('Open PK3...', 'app.open')
        menu_model.append('Save Screenshot...', 'app.save-screenshot')
        menu_model.append('Save Render...', 'app.save-render')

        menu_button = Gtk.MenuButton()
        menu_button.set_icon_name('open-menu-symbolic')
        menu_button.set_menu_model(menu_model)
        header.pack_end(menu_button)

        # Main layout: Paned (sidebar | right panel)
        paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        paned.set_position(200)
        self._window.set_child(paned)

        # Sidebar: scrolled list of model names
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_size_request(150, -1)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        self._model_list = Gtk.ListBox()
        self._model_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._model_list.connect('row-selected', self._on_model_selected)
        scrolled.set_child(self._model_list)
        paned.set_start_child(scrolled)
        paned.set_shrink_start_child(False)

        # Right panel: GL view + controls
        right_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        paned.set_end_child(right_box)
        paned.set_shrink_end_child(False)

        # GL view
        self._model_view = ModelView()
        right_box.append(self._model_view)

        # Controls panel
        controls = self._create_controls()
        right_box.append(controls)

        # Keyboard controller for frame stepping
        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect('key-pressed', self._on_key_pressed)
        self._window.add_controller(key_ctrl)

        # UI update timer (30fps)
        self._ui_timer_id = GLib.timeout_add(33, self._update_ui_controls)

        self._window.present()

    def _create_controls(self):
        grid = Gtk.Grid()
        grid.set_row_spacing(6)
        grid.set_column_spacing(8)
        grid.set_margin_start(10)
        grid.set_margin_end(10)
        grid.set_margin_top(8)
        grid.set_margin_bottom(8)

        # Row 0: Skin
        grid.attach(Gtk.Label(label='Skin:'), 0, 0, 1, 1)
        self._skin_model = Gtk.StringList()
        self._skin_dropdown = Gtk.DropDown(model=self._skin_model)
        self._skin_dropdown.set_hexpand(False)
        self._skin_dropdown.set_size_request(180, -1)
        self._skin_dropdown.connect('notify::selected', self._on_skin_changed)
        grid.attach(self._skin_dropdown, 1, 0, 2, 1)

        # Row 1: Torso
        grid.attach(Gtk.Label(label='Torso:'), 0, 1, 1, 1)
        self._torso_model = Gtk.StringList()
        for name in ANIMATION_NAMES:
            self._torso_model.append(name)
        self._torso_dropdown = Gtk.DropDown(model=self._torso_model)
        self._torso_dropdown.set_selected(AnimNumber.TORSO_STAND)
        self._torso_dropdown.set_size_request(180, -1)
        self._torso_dropdown.connect('notify::selected', self._on_torso_anim_changed)
        grid.attach(self._torso_dropdown, 1, 1, 1, 1)

        self._torso_slider = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL)
        self._torso_slider.set_range(0, 1)
        self._torso_slider.set_digits(0)
        self._torso_slider.set_hexpand(True)
        self._torso_slider.connect('value-changed', self._on_torso_slider_changed)
        grid.attach(self._torso_slider, 2, 1, 1, 1)

        self._torso_frame_label = Gtk.Label(label='Frame 0 / 0')
        self._torso_frame_label.set_width_chars(14)
        grid.attach(self._torso_frame_label, 3, 1, 1, 1)

        # Row 2: Legs
        grid.attach(Gtk.Label(label='Legs:'), 0, 2, 1, 1)
        self._legs_model = Gtk.StringList()
        for name in ANIMATION_NAMES:
            self._legs_model.append(name)
        self._legs_dropdown = Gtk.DropDown(model=self._legs_model)
        self._legs_dropdown.set_selected(AnimNumber.LEGS_IDLE)
        self._legs_dropdown.set_size_request(180, -1)
        self._legs_dropdown.connect('notify::selected', self._on_legs_anim_changed)
        grid.attach(self._legs_dropdown, 1, 2, 1, 1)

        self._legs_slider = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL)
        self._legs_slider.set_range(0, 1)
        self._legs_slider.set_digits(0)
        self._legs_slider.set_hexpand(True)
        self._legs_slider.connect('value-changed', self._on_legs_slider_changed)
        grid.attach(self._legs_slider, 2, 2, 1, 1)

        self._legs_frame_label = Gtk.Label(label='Frame 0 / 0')
        self._legs_frame_label.set_width_chars(14)
        grid.attach(self._legs_frame_label, 3, 2, 1, 1)

        # Row 3: Play/Pause, Step, Gamma
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)

        self._play_pause_button = Gtk.Button(label='Pause')
        self._play_pause_button.connect('clicked', self._on_toggle_play_pause)
        button_box.append(self._play_pause_button)

        step_back = Gtk.Button(label='<')
        step_back.connect('clicked', self._on_step_back)
        button_box.append(step_back)

        step_fwd = Gtk.Button(label='>')
        step_fwd.connect('clicked', self._on_step_forward)
        button_box.append(step_fwd)

        grid.attach(button_box, 0, 3, 2, 1)

        gamma_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        gamma_box.set_hexpand(True)
        gamma_box.append(Gtk.Label(label='Gamma:'))

        self._gamma_slider = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL)
        self._gamma_slider.set_range(0.3, 3.0)
        self._gamma_slider.set_value(1.0)
        self._gamma_slider.set_hexpand(True)
        self._gamma_slider.connect('value-changed', self._on_gamma_changed)
        gamma_box.append(self._gamma_slider)

        self._gamma_label = Gtk.Label(label='1.00')
        self._gamma_label.set_width_chars(5)
        gamma_box.append(self._gamma_label)

        grid.attach(gamma_box, 2, 3, 2, 1)

        return grid

    # ---- Actions ----

    def _on_open(self, action, param):
        dialog = Gtk.FileDialog()
        dialog.set_title('Open PK3 File')
        pk3_filter = Gtk.FileFilter()
        pk3_filter.set_name('PK3 Files')
        pk3_filter.add_pattern('*.pk3')
        filter_model = Gio.ListStore.new(Gtk.FileFilter)
        filter_model.append(pk3_filter)
        dialog.set_filters(filter_model)
        dialog.open(self._window, None, self._on_open_response)

    def _on_open_response(self, dialog, result):
        try:
            gfile = dialog.open_finish(result)
        except GLib.Error:
            return
        if gfile:
            self._load_archive(gfile.get_path())

    def _on_save_screenshot(self, action, param):
        if not self._current_model:
            return
        dialog = Gtk.FileDialog()
        dialog.set_title('Save Screenshot')
        dialog.set_initial_name('screenshot.png')
        dialog.save(self._window, None, self._on_save_screenshot_response)

    def _on_save_screenshot_response(self, dialog, result):
        try:
            gfile = dialog.save_finish(result)
        except GLib.Error:
            return
        if gfile:
            img = self._model_view.capture_screenshot(scale=2)
            if img:
                img.save(gfile.get_path(), 'PNG')

    def _on_save_render(self, action, param):
        if not self._current_model:
            return
        self._show_render_dialog()

    def _show_render_dialog(self):
        dialog = Gtk.Window(title='Save Render', transient_for=self._window, modal=True)
        dialog.set_default_size(350, 200)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        vbox.set_margin_start(15)
        vbox.set_margin_end(15)
        vbox.set_margin_top(15)
        vbox.set_margin_bottom(15)
        dialog.set_child(vbox)

        # Preset dropdown
        presets = [
            ('1080p (1920x1080)', 1920, 1080),
            ('1440p (2560x1440)', 2560, 1440),
            ('4K (3840x2160)', 3840, 2160),
            ('4K Portrait (2160x3840)', 2160, 3840),
            ('Square 2K (2048x2048)', 2048, 2048),
            ('Square 4K (4096x4096)', 4096, 4096),
            ('Custom', 0, 0),
        ]
        preset_model = Gtk.StringList()
        for name, _, _ in presets:
            preset_model.append(name)
        preset_dropdown = Gtk.DropDown(model=preset_model)
        preset_dropdown.set_selected(2)  # Default to 4K
        vbox.append(preset_dropdown)

        # Width/Height fields
        dim_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        dim_box.append(Gtk.Label(label='Width:'))
        w_entry = Gtk.Entry()
        w_entry.set_text('3840')
        w_entry.set_width_chars(6)
        dim_box.append(w_entry)
        dim_box.append(Gtk.Label(label='Height:'))
        h_entry = Gtk.Entry()
        h_entry.set_text('2160')
        h_entry.set_width_chars(6)
        dim_box.append(h_entry)
        vbox.append(dim_box)

        # Update fields when preset changes
        def on_preset_changed(dropdown, param):
            idx = dropdown.get_selected()
            if idx < len(presets) - 1:
                _, pw, ph = presets[idx]
                w_entry.set_text(str(pw))
                h_entry.set_text(str(ph))
        preset_dropdown.connect('notify::selected', on_preset_changed)

        note = Gtk.Label(label='Model will be auto-framed to fill the output.')
        note.add_css_class('dim-label')
        vbox.append(note)

        # Buttons
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_box.set_halign(Gtk.Align.END)

        cancel_btn = Gtk.Button(label='Cancel')
        cancel_btn.connect('clicked', lambda b: dialog.close())
        btn_box.append(cancel_btn)

        render_btn = Gtk.Button(label='Render')
        render_btn.add_css_class('suggested-action')

        def on_render_clicked(button):
            try:
                render_w = max(64, min(8192, int(w_entry.get_text())))
                render_h = max(64, min(8192, int(h_entry.get_text())))
            except ValueError:
                return
            dialog.close()
            self._do_save_render(render_w, render_h)

        render_btn.connect('clicked', on_render_clicked)
        btn_box.append(render_btn)
        vbox.append(btn_box)

        dialog.present()

    def _do_save_render(self, render_w, render_h):
        dialog = Gtk.FileDialog()
        dialog.set_title('Save Render')
        dialog.set_initial_name(f'render_{render_w}x{render_h}.png')

        def on_response(dlg, result):
            try:
                gfile = dlg.save_finish(result)
            except GLib.Error:
                return
            if gfile:
                img = self._model_view.capture_render(render_w, render_h)
                if img:
                    img.save(gfile.get_path(), 'PNG')

        dialog.save(self._window, None, on_response)

    # ---- Model loading ----

    def _load_archive(self, path):
        try:
            self._archive = PK3Archive(path)
        except Exception as e:
            print(f"Failed to open PK3: {e}", file=sys.stderr)
            return

        self._player_models = self._archive.player_model_paths()

        # Clear and repopulate model list
        while True:
            row = self._model_list.get_row_at_index(0)
            if row is None:
                break
            self._model_list.remove(row)

        for model_path in self._player_models:
            name = model_path.rsplit('/', 1)[-1] if '/' in model_path else model_path
            label = Gtk.Label(label=name, xalign=0.0)
            label.set_margin_start(6)
            label.set_margin_end(6)
            label.set_margin_top(4)
            label.set_margin_bottom(4)
            self._model_list.append(label)

        self._window.set_title(f'MD3View - {os.path.basename(path)}')

        # Auto-select first model
        if self._player_models:
            first_row = self._model_list.get_row_at_index(0)
            if first_row:
                self._model_list.select_row(first_row)

    def _on_model_selected(self, listbox, row):
        if row is None:
            return
        idx = row.get_index()
        if idx < 0 or idx >= len(self._player_models):
            return
        self._load_player_model(self._player_models[idx])

    def _load_player_model(self, model_path):
        self._model_view.make_current()

        # Flush old textures
        if self._model_view.texture_cache:
            self._model_view.texture_cache.flush()

        tex_cache = TextureCache(self._archive)
        self._model_view.texture_cache = tex_cache

        try:
            model = MD3PlayerModel(self._archive, model_path)
        except Exception as e:
            print(f"Failed to load player model {model_path}: {e}", file=sys.stderr)
            return

        self._current_model = model
        self._model_view.player_model = model

        # Update skin dropdown
        self._skin_model.splice(0, self._skin_model.get_n_items(), [])
        for skin in model.available_skins:
            self._skin_model.append(skin)
        if model.current_skin and model.current_skin in model.available_skins:
            self._skin_dropdown.set_selected(model.available_skins.index(model.current_skin))

        # Reset animation controls
        self._torso_dropdown.set_selected(AnimNumber.TORSO_STAND)
        self._legs_dropdown.set_selected(AnimNumber.LEGS_IDLE)
        self._play_pause_button.set_label('Pause')

        torso_frames = self._current_model.torso_num_frames()
        legs_frames = self._current_model.legs_num_frames()
        self._torso_slider.set_range(0, max(torso_frames - 1, 0))
        self._legs_slider.set_range(0, max(legs_frames - 1, 0))

        self._model_view.queue_render()

    # ---- Control callbacks ----

    def _on_skin_changed(self, dropdown, param):
        if not self._current_model:
            return
        idx = dropdown.get_selected()
        if idx == Gtk.INVALID_LIST_POSITION:
            return
        skins = self._current_model.available_skins
        if idx < len(skins):
            self._current_model.select_skin(skins[idx])
            self._model_view.make_current()
            self._model_view.texture_cache.flush()
            self._model_view.queue_render()

    def _on_torso_anim_changed(self, dropdown, param):
        if not self._current_model:
            return
        idx = dropdown.get_selected()
        if idx == Gtk.INVALID_LIST_POSITION:
            return
        self._current_model.set_torso_animation(idx)
        num_frames = self._current_model.torso_num_frames()
        self._torso_slider.set_range(0, max(num_frames - 1, 0))
        self._torso_slider.set_value(0)

    def _on_legs_anim_changed(self, dropdown, param):
        if not self._current_model:
            return
        idx = dropdown.get_selected()
        if idx == Gtk.INVALID_LIST_POSITION:
            return
        self._current_model.set_legs_animation(idx)
        num_frames = self._current_model.legs_num_frames()
        self._legs_slider.set_range(0, max(num_frames - 1, 0))
        self._legs_slider.set_value(0)

    def _on_toggle_play_pause(self, button):
        if not self._current_model:
            return
        self._current_model.playing = not self._current_model.playing
        button.set_label('Pause' if self._current_model.playing else 'Play')

    def _on_step_back(self, button):
        if not self._current_model or self._current_model.playing:
            return
        self._current_model.step_frame(-1)
        self._model_view.queue_render()

    def _on_step_forward(self, button):
        if not self._current_model or self._current_model.playing:
            return
        self._current_model.step_frame(1)
        self._model_view.queue_render()

    def _on_torso_slider_changed(self, slider):
        if not self._current_model or self._current_model.playing:
            return
        self._current_model.scrub_torso_to_frame(int(slider.get_value()))
        self._model_view.queue_render()

    def _on_legs_slider_changed(self, slider):
        if not self._current_model or self._current_model.playing:
            return
        self._current_model.scrub_legs_to_frame(int(slider.get_value()))
        self._model_view.queue_render()

    def _on_gamma_changed(self, slider):
        gamma = slider.get_value()
        self._model_view.gamma = gamma
        self._gamma_label.set_label(f'{gamma:.2f}')
        self._model_view.queue_render()

    def _on_key_pressed(self, controller, keyval, keycode, state):
        if keyval == Gdk.KEY_Left:
            if self._current_model and not self._current_model.playing:
                self._current_model.step_frame(-1)
                self._model_view.queue_render()
            return True
        elif keyval == Gdk.KEY_Right:
            if self._current_model and not self._current_model.playing:
                self._current_model.step_frame(1)
                self._model_view.queue_render()
            return True
        return False

    def _update_ui_controls(self):
        if not self._current_model:
            return True

        torso_frame = self._current_model.torso_current_frame()
        torso_total = self._current_model.torso_num_frames()
        legs_frame = self._current_model.legs_current_frame()
        legs_total = self._current_model.legs_num_frames()

        self._torso_frame_label.set_label(f'Frame {torso_frame} / {torso_total}')
        self._legs_frame_label.set_label(f'Frame {legs_frame} / {legs_total}')

        if self._current_model.playing:
            if torso_total > 0:
                self._torso_slider.set_range(0, torso_total - 1)
            self._torso_slider.set_value(torso_frame)
            if legs_total > 0:
                self._legs_slider.set_range(0, legs_total - 1)
            self._legs_slider.set_value(legs_frame)

        return True  # keep timer running


def main():
    app = MD3ViewApp()
    app.run(sys.argv)


if __name__ == '__main__':
    main()
