namespace MD3View;

public class MainForm : Form
{
    private SplitContainer _splitContainer = null!;
    private ListBox _modelList = null!;
    private ModelGLControl _glControl = null!;
    private Panel _controlsPanel = null!;

    // Skin selection
    private ComboBox _skinCombo = null!;

    // Animation controls
    private ComboBox _torsoCombo = null!;
    private ComboBox _legsCombo = null!;
    private Button _playPauseButton = null!;
    private TrackBar _torsoSlider = null!;
    private TrackBar _legsSlider = null!;
    private Label _torsoFrameLabel = null!;
    private Label _legsFrameLabel = null!;
    private Button _stepBackButton = null!;
    private Button _stepForwardButton = null!;
    private TrackBar _gammaSlider = null!;
    private Label _gammaLabel = null!;

    private System.Windows.Forms.Timer _refreshTimer = null!;
    private System.Windows.Forms.Timer _uiTimer = null!;

    private PK3Archive? _archive;
    private List<string> _playerModels = new();
    private MD3PlayerModel? _currentModel;

    public MainForm()
    {
        Text = "MD3View";
        Size = new Size(1024, 768);
        MinimumSize = new Size(640, 480);
        KeyPreview = true;

        CreateMenu();
        CreateLayout();
        SetupTimers();
        PopulateAnimPopups();
    }

    private void CreateMenu()
    {
        var menuStrip = new MenuStrip();

        var fileMenu = new ToolStripMenuItem("&File");
        fileMenu.DropDownItems.Add("Open PK3...", null, OnOpenPK3);
        ((ToolStripMenuItem)fileMenu.DropDownItems[0]).ShortcutKeys = Keys.Control | Keys.O;
        fileMenu.DropDownItems.Add("Save Screenshot...", null, OnSaveScreenshot);
        ((ToolStripMenuItem)fileMenu.DropDownItems[1]).ShortcutKeys = Keys.Control | Keys.S;
        fileMenu.DropDownItems.Add("Save Render...", null, OnSaveRender);
        ((ToolStripMenuItem)fileMenu.DropDownItems[2]).ShortcutKeys = Keys.Control | Keys.Shift | Keys.S;

        menuStrip.Items.Add(fileMenu);
        MainMenuStrip = menuStrip;
        Controls.Add(menuStrip);
    }

    private void CreateLayout()
    {
        _splitContainer = new SplitContainer
        {
            Dock = DockStyle.Fill,
            Orientation = Orientation.Vertical,
            SplitterDistance = 200,
            FixedPanel = FixedPanel.Panel1
        };

        // Left panel: model list
        _modelList = new ListBox
        {
            Dock = DockStyle.Fill,
            IntegralHeight = false,
        };
        _modelList.SelectedIndexChanged += OnModelSelected;
        _splitContainer.Panel1.Controls.Add(_modelList);

        // Right panel: GL view + controls
        var rightPanel = new Panel { Dock = DockStyle.Fill };

        // Controls panel (bottom)
        _controlsPanel = new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 150,
        };
        SetupControlsPanel();
        rightPanel.Controls.Add(_controlsPanel);

        // GL view (fills remaining space)
        _glControl = new ModelGLControl
        {
            Dock = DockStyle.Fill,
        };
        rightPanel.Controls.Add(_glControl);

        _splitContainer.Panel2.Controls.Add(rightPanel);
        Controls.Add(_splitContainer);
    }

    private void SetupControlsPanel()
    {
        int y = 10;
        int leftMargin = 10;

        // Row 0: Skin selection
        var skinLabel = new Label { Text = "Skin:", Location = new Point(leftMargin, y + 3), AutoSize = true };
        _controlsPanel.Controls.Add(skinLabel);

        _skinCombo = new ComboBox
        {
            Location = new Point(leftMargin + 50, y),
            Width = 180,
            DropDownStyle = ComboBoxStyle.DropDownList
        };
        _skinCombo.SelectedIndexChanged += OnSkinChanged;
        _controlsPanel.Controls.Add(_skinCombo);

        y += 30;

        // Row 1: Torso animation popup + frame info
        var torsoLabel = new Label { Text = "Torso:", Location = new Point(leftMargin, y + 3), AutoSize = true };
        _controlsPanel.Controls.Add(torsoLabel);

        _torsoCombo = new ComboBox
        {
            Location = new Point(leftMargin + 50, y),
            Width = 180,
            DropDownStyle = ComboBoxStyle.DropDownList
        };
        _torsoCombo.SelectedIndexChanged += OnTorsoAnimChanged;
        _controlsPanel.Controls.Add(_torsoCombo);

        _torsoSlider = new TrackBar
        {
            Location = new Point(leftMargin + 240, y),
            Width = 200,
            Minimum = 0,
            Maximum = 1,
            TickStyle = TickStyle.None,
            Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right,
        };
        _torsoSlider.Scroll += OnTorsoSliderChanged;
        _controlsPanel.Controls.Add(_torsoSlider);

        _torsoFrameLabel = new Label
        {
            Text = "Frame 0 / 0",
            Location = new Point(leftMargin + 450, y + 3),
            AutoSize = true,
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
        };
        _controlsPanel.Controls.Add(_torsoFrameLabel);

        y += 35;

        // Row 2: Legs animation popup + frame info
        var legsLabel = new Label { Text = "Legs:", Location = new Point(leftMargin, y + 3), AutoSize = true };
        _controlsPanel.Controls.Add(legsLabel);

        _legsCombo = new ComboBox
        {
            Location = new Point(leftMargin + 50, y),
            Width = 180,
            DropDownStyle = ComboBoxStyle.DropDownList
        };
        _legsCombo.SelectedIndexChanged += OnLegsAnimChanged;
        _controlsPanel.Controls.Add(_legsCombo);

        _legsSlider = new TrackBar
        {
            Location = new Point(leftMargin + 240, y),
            Width = 200,
            Minimum = 0,
            Maximum = 1,
            TickStyle = TickStyle.None,
            Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right,
        };
        _legsSlider.Scroll += OnLegsSliderChanged;
        _controlsPanel.Controls.Add(_legsSlider);

        _legsFrameLabel = new Label
        {
            Text = "Frame 0 / 0",
            Location = new Point(leftMargin + 450, y + 3),
            AutoSize = true,
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
        };
        _controlsPanel.Controls.Add(_legsFrameLabel);

        y += 35;

        // Row 3: Play/Pause + Step buttons + Gamma
        _playPauseButton = new Button
        {
            Text = "Pause",
            Location = new Point(leftMargin, y),
            Width = 80,
        };
        _playPauseButton.Click += OnTogglePlayPause;
        _controlsPanel.Controls.Add(_playPauseButton);

        _stepBackButton = new Button
        {
            Text = "<",
            Location = new Point(leftMargin + 90, y),
            Width = 40,
        };
        _stepBackButton.Click += OnStepBack;
        _controlsPanel.Controls.Add(_stepBackButton);

        _stepForwardButton = new Button
        {
            Text = ">",
            Location = new Point(leftMargin + 135, y),
            Width = 40,
        };
        _stepForwardButton.Click += OnStepForward;
        _controlsPanel.Controls.Add(_stepForwardButton);

        // Gamma slider
        var gammaTitle = new Label { Text = "Gamma:", Location = new Point(leftMargin + 200, y + 3), AutoSize = true };
        _controlsPanel.Controls.Add(gammaTitle);

        _gammaSlider = new TrackBar
        {
            Location = new Point(leftMargin + 255, y),
            Width = 140,
            Minimum = 30,  // 0.30
            Maximum = 300, // 3.00
            Value = 100,   // 1.00
            TickStyle = TickStyle.None,
            Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right,
        };
        _gammaSlider.Scroll += OnGammaChanged;
        _controlsPanel.Controls.Add(_gammaSlider);

        _gammaLabel = new Label
        {
            Text = "1.00",
            Location = new Point(leftMargin + 400, y + 3),
            AutoSize = true,
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
        };
        _controlsPanel.Controls.Add(_gammaLabel);
    }

    private void PopulateAnimPopups()
    {
        _torsoCombo.Items.Clear();
        _legsCombo.Items.Clear();

        foreach (var name in AnimationNames.Names)
        {
            _torsoCombo.Items.Add(name);
            _legsCombo.Items.Add(name);
        }

        _torsoCombo.SelectedIndex = (int)AnimNumber.TORSO_STAND;
        _legsCombo.SelectedIndex = (int)AnimNumber.LEGS_IDLE;
    }

    private void SetupTimers()
    {
        // Refresh timer (~60fps)
        _refreshTimer = new System.Windows.Forms.Timer { Interval = 16 };
        _refreshTimer.Tick += (s, e) => _glControl.Invalidate();
        _refreshTimer.Start();

        // UI timer (30fps) for updating frame labels + slider positions
        _uiTimer = new System.Windows.Forms.Timer { Interval = 33 };
        _uiTimer.Tick += (s, e) => UpdateUIControls();
        _uiTimer.Start();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        _glControl.HandleKeyDown(e.KeyCode);
    }

    // ============================================================
    // Animation control actions
    // ============================================================

    private void OnSkinChanged(object? sender, EventArgs e)
    {
        if (_currentModel == null || _skinCombo.SelectedItem == null) return;
        var skinName = _skinCombo.SelectedItem.ToString()!;
        _currentModel.SelectSkin(skinName);
        // Flush texture cache so new skin textures load
        _glControl.MakeCurrent();
        _glControl.TextureCache?.Flush();
        _glControl.Invalidate();
    }

    private void OnGammaChanged(object? sender, EventArgs e)
    {
        float gamma = _gammaSlider.Value / 100.0f;
        _glControl.Gamma = gamma;
        _gammaLabel.Text = gamma.ToString("F2");
        _glControl.Invalidate();
    }

    private void OnTorsoAnimChanged(object? sender, EventArgs e)
    {
        if (_currentModel == null || _torsoCombo.SelectedIndex < 0) return;
        var anim = (AnimNumber)_torsoCombo.SelectedIndex;
        _currentModel.SetTorsoAnimation(anim);
        int numFrames = _currentModel.TorsoNumFrames;
        _torsoSlider.Maximum = numFrames > 0 ? numFrames - 1 : 0;
        _torsoSlider.Value = 0;
    }

    private void OnLegsAnimChanged(object? sender, EventArgs e)
    {
        if (_currentModel == null || _legsCombo.SelectedIndex < 0) return;
        var anim = (AnimNumber)_legsCombo.SelectedIndex;
        _currentModel.SetLegsAnimation(anim);
        int numFrames = _currentModel.LegsNumFrames;
        _legsSlider.Maximum = numFrames > 0 ? numFrames - 1 : 0;
        _legsSlider.Value = 0;
    }

    private void OnTogglePlayPause(object? sender, EventArgs e)
    {
        if (_currentModel == null) return;
        _currentModel.Playing = !_currentModel.Playing;
        _playPauseButton.Text = _currentModel.Playing ? "Pause" : "Play";
    }

    private void OnStepBack(object? sender, EventArgs e)
    {
        if (_currentModel == null || _currentModel.Playing) return;
        _currentModel.StepFrame(-1);
        _glControl.Invalidate();
    }

    private void OnStepForward(object? sender, EventArgs e)
    {
        if (_currentModel == null || _currentModel.Playing) return;
        _currentModel.StepFrame(1);
        _glControl.Invalidate();
    }

    private void OnTorsoSliderChanged(object? sender, EventArgs e)
    {
        if (_currentModel == null || _currentModel.Playing) return;
        _currentModel.ScrubTorsoToFrame(_torsoSlider.Value);
        _glControl.Invalidate();
    }

    private void OnLegsSliderChanged(object? sender, EventArgs e)
    {
        if (_currentModel == null || _currentModel.Playing) return;
        _currentModel.ScrubLegsToFrame(_legsSlider.Value);
        _glControl.Invalidate();
    }

    private void UpdateUIControls()
    {
        if (_currentModel == null) return;
        int torsoFrame = _currentModel.TorsoCurrentFrame;
        int torsoTotal = _currentModel.TorsoNumFrames;
        int legsFrame = _currentModel.LegsCurrentFrame;
        int legsTotal = _currentModel.LegsNumFrames;

        _torsoFrameLabel.Text = $"Frame {torsoFrame} / {torsoTotal}";
        _legsFrameLabel.Text = $"Frame {legsFrame} / {legsTotal}";

        if (_currentModel.Playing)
        {
            if (torsoTotal > 0)
            {
                _torsoSlider.Maximum = torsoTotal - 1;
                _torsoSlider.Value = Math.Min(torsoFrame, _torsoSlider.Maximum);
            }
            if (legsTotal > 0)
            {
                _legsSlider.Maximum = legsTotal - 1;
                _legsSlider.Value = Math.Min(legsFrame, _legsSlider.Maximum);
            }
        }
    }

    // ============================================================
    // Model list
    // ============================================================

    private void OnModelSelected(object? sender, EventArgs e)
    {
        int idx = _modelList.SelectedIndex;
        if (idx < 0 || idx >= _playerModels.Count) return;
        LoadPlayerModel(_playerModels[idx]);
    }

    // ============================================================
    // File actions
    // ============================================================

    private void OnOpenPK3(object? sender, EventArgs e)
    {
        using var dialog = new OpenFileDialog
        {
            Filter = "PK3 Files (*.pk3)|*.pk3|All Files (*.*)|*.*",
            Title = "Open PK3 File"
        };

        if (dialog.ShowDialog() != DialogResult.OK) return;
        LoadArchive(dialog.FileName);
    }

    private void LoadArchive(string path)
    {
        try
        {
            _archive?.Dispose();
            _archive = new PK3Archive(path);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to open PK3 file: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        _playerModels = _archive.PlayerModelPaths();
        _modelList.Items.Clear();
        foreach (var model in _playerModels)
            _modelList.Items.Add(Path.GetFileName(model));

        Text = $"MD3View - {Path.GetFileName(path)}";

        // Auto-select first model if available
        if (_playerModels.Count > 0)
            _modelList.SelectedIndex = 0;
    }

    private void LoadPlayerModel(string modelPath)
    {
        if (_archive == null) return;

        _glControl.MakeCurrent();

        // Flush old textures
        _glControl.TextureCache?.Flush();

        var texCache = new TextureCache(_archive);
        _glControl.TextureCache = texCache;

        MD3PlayerModel model;
        try
        {
            model = new MD3PlayerModel(_archive, modelPath);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Failed to load player model: {ex.Message}");
            return;
        }

        _currentModel = model;
        _glControl.PlayerModel = model;

        // Update skin combo
        _skinCombo.Items.Clear();
        foreach (var skin in model.AvailableSkins)
            _skinCombo.Items.Add(skin);
        if (model.CurrentSkin != null && _skinCombo.Items.Contains(model.CurrentSkin))
            _skinCombo.SelectedItem = model.CurrentSkin;

        // Update animation controls
        _torsoCombo.SelectedIndex = (int)AnimNumber.TORSO_STAND;
        _legsCombo.SelectedIndex = (int)AnimNumber.LEGS_IDLE;
        _playPauseButton.Text = "Pause";

        int torsoFrames = _currentModel.TorsoNumFrames;
        int legsFrames = _currentModel.LegsNumFrames;
        _torsoSlider.Maximum = torsoFrames > 0 ? torsoFrames - 1 : 0;
        _legsSlider.Maximum = legsFrames > 0 ? legsFrames - 1 : 0;

        _glControl.Invalidate();
    }

    private void OnSaveScreenshot(object? sender, EventArgs e)
    {
        if (_currentModel == null) return;

        using var dialog = new SaveFileDialog
        {
            Filter = "PNG Image (*.png)|*.png",
            FileName = "screenshot.png"
        };

        if (dialog.ShowDialog() != DialogResult.OK) return;

        var bitmap = _glControl.CaptureScreenshot(2);
        bitmap?.Save(dialog.FileName, System.Drawing.Imaging.ImageFormat.Png);
        bitmap?.Dispose();
    }

    private void OnSaveRender(object? sender, EventArgs e)
    {
        if (_currentModel == null) return;

        // Resolution picker dialog
        using var renderDialog = new Form
        {
            Text = "Save Render",
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = false,
            StartPosition = FormStartPosition.CenterParent,
            Size = new Size(340, 220),
        };

        var presetCombo = new ComboBox
        {
            Location = new Point(10, 15),
            Width = 300,
            DropDownStyle = ComboBoxStyle.DropDownList,
        };
        presetCombo.Items.AddRange(new object[]
        {
            "1080p (1920x1080)",
            "1440p (2560x1440)",
            "4K (3840x2160)",
            "4K Portrait (2160x3840)",
            "Square 2K (2048x2048)",
            "Square 4K (4096x4096)",
            "Custom"
        });
        presetCombo.SelectedIndex = 2; // Default to 4K
        renderDialog.Controls.Add(presetCombo);

        int[] presetWidths =  { 1920, 2560, 3840, 2160, 2048, 4096 };
        int[] presetHeights = { 1080, 1440, 2160, 3840, 2048, 4096 };

        var wLabel = new Label { Text = "Width:", Location = new Point(10, 53), AutoSize = true };
        renderDialog.Controls.Add(wLabel);
        var wField = new NumericUpDown
        {
            Location = new Point(60, 50),
            Width = 80,
            Minimum = 64,
            Maximum = 8192,
            Value = 3840,
        };
        renderDialog.Controls.Add(wField);

        var hLabel = new Label { Text = "Height:", Location = new Point(160, 53), AutoSize = true };
        renderDialog.Controls.Add(hLabel);
        var hField = new NumericUpDown
        {
            Location = new Point(215, 50),
            Width = 80,
            Minimum = 64,
            Maximum = 8192,
            Value = 2160,
        };
        renderDialog.Controls.Add(hField);

        presetCombo.SelectedIndexChanged += (s, args) =>
        {
            int idx = presetCombo.SelectedIndex;
            if (idx >= 0 && idx < 6)
            {
                wField.Value = presetWidths[idx];
                hField.Value = presetHeights[idx];
            }
        };

        var noteLabel = new Label
        {
            Text = "Model will be auto-framed to fill the output.",
            Location = new Point(10, 85),
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
            Font = new Font(Font.FontFamily, 8.5f),
        };
        renderDialog.Controls.Add(noteLabel);

        var renderButton = new Button
        {
            Text = "Render",
            Location = new Point(135, 120),
            Width = 80,
            DialogResult = DialogResult.OK,
        };
        renderDialog.Controls.Add(renderButton);
        renderDialog.AcceptButton = renderButton;

        var cancelButton = new Button
        {
            Text = "Cancel",
            Location = new Point(225, 120),
            Width = 80,
            DialogResult = DialogResult.Cancel,
        };
        renderDialog.Controls.Add(cancelButton);
        renderDialog.CancelButton = cancelButton;

        if (renderDialog.ShowDialog(this) != DialogResult.OK) return;

        int renderW = (int)wField.Value;
        int renderH = (int)hField.Value;

        // Clamp
        renderW = Math.Clamp(renderW, 64, 8192);
        renderH = Math.Clamp(renderH, 64, 8192);

        // Ask where to save
        using var saveDialog = new SaveFileDialog
        {
            Filter = "PNG Image (*.png)|*.png",
            FileName = $"render_{renderW}x{renderH}.png"
        };

        if (saveDialog.ShowDialog() != DialogResult.OK) return;

        var bitmap = _glControl.CaptureRender(renderW, renderH);
        bitmap?.Save(saveDialog.FileName, System.Drawing.Imaging.ImageFormat.Png);
        bitmap?.Dispose();
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _refreshTimer?.Stop();
        _uiTimer?.Stop();
        _glControl.MakeCurrent();
        _glControl.Renderer?.Cleanup();
        _glControl.TextureCache?.Flush();
        _archive?.Dispose();
        base.OnFormClosed(e);
    }
}
