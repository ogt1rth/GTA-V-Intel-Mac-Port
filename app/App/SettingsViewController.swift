import UIKit

/// Shared appearance and keyboard navigation for settings lists, including mod editors.
class SettingsTableViewController: UITableViewController {
    var keyboardActive = false
    var keyboardCursor: IndexPath?
    var optionDescriptionChanged: ((String?) -> Void)?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.separatorColor = UIColor(white: 1, alpha: 0.1)
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let focused = keyboardActive && keyboardCursor == indexPath
        cell.backgroundColor = focused ? SettingsHomeViewController.cursorFill : Theme.rowBackground
        if var content = cell.contentConfiguration as? UIListContentConfiguration {
            content.textProperties.font = Theme.body(20)
            content.textProperties.color = focused ? .black : Theme.text
            content.secondaryTextProperties.font = Theme.body(16)
            content.secondaryTextProperties.color = focused ? .darkGray : Theme.secondaryText
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
            cell.accessibilityHint = content.secondaryText
            cell.contentConfiguration = content
        }
        if let button = cell.accessoryView as? UIButton {
            Theme.styleSettingsButton(button)
        }
        let selected = UIView()
        selected.backgroundColor = SettingsHomeViewController.cursorFill
        cell.selectedBackgroundView = selected
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.font = Theme.body(18, .semibold)
        header.textLabel?.textColor = Theme.text
    }

    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        guard let footer = view as? UITableViewHeaderFooterView else { return }
        footer.textLabel?.font = Theme.body(16)
        footer.textLabel?.textColor = Theme.secondaryText
    }
}

/// Graphics and control options. Before launch every change applies on Play;
/// during play only resolution and controls apply live, the rest on restart.
final class SettingsViewController: SettingsTableViewController {
    private let embedded: Bool
    private let settings = GameSettings.shared
    private let savePickerDelegate = SavePickerDelegate()
    private let engineRunning: Bool
    private let bootPreset: GraphicsPreset
    /// The mode the running engine started in (nil before Play).
    private let runningMode: GameMode?
    var resolutionChanged: (() -> Void)?
    var controlsChanged: (() -> Void)?
    var editLayout: (() -> Void)?
    var targetingChanged: (() -> Void)?
    var gameModeChanged: (() -> Void)?
    var cheatSelected: ((StoryCheat) -> Void)?
    /// Cheats › Set money: the amount the player typed.
    var moneyEntered: ((Int32) -> Void)?
    /// Cheats › Spawn vehicle: the vehicle picked, and whether to get in.
    var vehicleSelected: ((SpawnVehicle, Bool) -> Void)?
    /// Cheats › an action row (repair, time, weather...): run once Settings closes.
    var nativeCheatSelected: ((NativeCheatAction) -> Void)?

    /// Cheats rows: Spawn vehicle, Set money, the NativeCheatGroup rows, then the controller story cheats.
    private var storyCheatStart: Int { 2 + NativeCheatGroup.all.count }
    var modMenuCategory: NativeCheatGroup.Category?
    private var cheatRows: [Int] {
        guard let category = modMenuCategory else { return Array(0..<(storyCheatStart + StoryCheats.all.count)) }
        if category == .story { return Array(storyCheatStart..<(storyCheatStart + StoryCheats.all.count)) }
        let actions = NativeCheatGroup.all.enumerated().compactMap { $0.element.category == category ? $0.offset + 2 : nil }
        return (category == .vehicles ? [0] : category == .player ? [1] : []) + actions
    }
    private func actionIndexPath(_ visible: IndexPath) -> IndexPath {
        guard sectionKind(visible.section) == .cheats else { return visible }
        return IndexPath(row: cheatRows[visible.row], section: visible.section)
    }


    enum Section: Int, CaseIterable { case language, mode, graphics, controls, cheats, files, device }
    /// The sections this page shows (SettingsHomeViewController opens one page per category).
    private let sections: Set<Section>
    private enum ControlsRow { case keyboardMouse, targeting, hudLayout, minimap, helpText, inputState }
    private var controlsRows: [ControlsRow] { [.keyboardMouse, .targeting, .hudLayout, .minimap, .helpText, .inputState] }

    private let preloader = AssetPreloader.shared
    /// Rows shown in the Game files section, rebuilt from the preloader's phase.
    private enum FileRow { case status, start, pause, resume, cancel, remove }
    private var fileRows: [FileRow] = []
    private var fileStateKey = ""
    private var fileMessage: String?

    init(engineRunning: Bool, runningMode: GameMode? = nil, title pageTitle: String? = nil, sections: Set<Section> = Set(Section.allCases), embedded: Bool = false) {
        self.embedded = embedded
        self.sections = sections
        self.engineRunning = engineRunning
        self.runningMode = engineRunning ? runningMode : nil
        self.bootPreset = GameSettings.shared.graphicsPreset
        super.init(style: embedded ? .plain : .insetGrouped)
        title = pageTitle ?? AppLanguage.choose("Settings")
        modalPresentationStyle = .formSheet
        overrideUserInterfaceStyle = .dark
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Automation: --settings-scroll-bottom shows the end of the page (screenshots of the last rows).
        if ProcessInfo.processInfo.arguments.contains("--settings-scroll-bottom"), tableView.numberOfSections > 0 {
            let section = tableView.numberOfSections - 1, rows = tableView.numberOfRows(inSection: section)
            if rows > 0 { tableView.scrollToRow(at: IndexPath(row: rows - 1, section: section), at: .bottom, animated: false) }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: AppLanguage.choose("Done"), primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem?.tintColor = Theme.accent
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        Theme.styleSettingsTable(tableView)
        if embedded {
            tableView.backgroundView = nil
            tableView.backgroundColor = .clear
        }
        fileRows = makeFileRows()
        NotificationCenter.default.addObserver(self, selector: #selector(preloadChanged), name: .assetPreloadChanged, object: nil)
        preloader.refresh()
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "--settings-section"), i + 1 < arguments.count,
           let section = ["files": Section.files, "graphics": Section.graphics, "resolution": Section.graphics, "device": Section.device][arguments[i + 1]], sections.contains(section) {
            let row = arguments[i + 1] == "resolution" ? (engineRunning ? 0 : settings.tier.allowed.count) : arguments[i + 1] == "device" ? 0 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.tableView.scrollToRow(at: IndexPath(row: row, section: self.indexOf(section)), at: .middle, animated: false)
            }
        }
        // Automation: --settings-section spawn goes on to Cheats › Spawn vehicle.
        if let i = arguments.firstIndex(of: "--settings-section"), i + 1 < arguments.count, arguments[i + 1] == "spawn",
           engineRunning, sections.contains(.cheats) {
            DispatchQueue.main.async { self.tableView(self.tableView, didSelectRowAt: IndexPath(row: 0, section: self.indexOf(.cheats))) }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { shown.count }
    /// Only this page's sections are in the table; these translate between table positions and sections.
    private lazy var shown: [Section] = Section.allCases.filter { sections.contains($0) }
    private func sectionKind(_ index: Int) -> Section { shown[index] }
    private func indexOf(_ section: Section) -> Int { shown.firstIndex(of: section) ?? 0 }
    /// Settings › HUD layout (GTA-197), with a piece chosen (the minimap's and help messages' Custom).
    private func editHUD(_ piece: HUDPiece? = nil) {
        let editor = HUDLayoutEditorController(select: piece)
        editor.onDone = { [weak self] in self?.reload(.controls); self?.controlsChanged?() }
        present(editor, animated: true)
    }
    private func reload(_ section: Section) {
        if let index = shown.firstIndex(of: section) { tableView.reloadSections([index], with: .none) }
    }

    // The app's look: rows as glass on the darkened art, headers in the display font.
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let focused = keyboardActive && keyboardCursor == indexPath
        cell.backgroundColor = focused ? SettingsHomeViewController.cursorFill : Theme.rowBackground
        if embedded, var content = cell.contentConfiguration as? UIListContentConfiguration {
            content.textProperties.color = focused ? .black : Theme.text
            content.secondaryTextProperties.color = focused ? .darkGray : Theme.secondaryText
            cell.contentConfiguration = content
        }
        let selected = UIView()
        selected.backgroundColor = Theme.rowSelected
        cell.selectedBackgroundView = selected
    }
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        var content = header.defaultContentConfiguration()
        content.text = self.tableView(tableView, titleForHeaderInSection: section)
        content.textProperties.font = embedded ? Theme.body(18, .semibold) : Theme.display(15, .bold)
        content.textProperties.color = Theme.text
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        content.textProperties.transform = .uppercase
        header.contentConfiguration = content
    }
    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.tertiaryText
        if embedded { (view as? UITableViewHeaderFooterView)?.textLabel?.font = Theme.body(16, .regular) }
    }

    /// Game mode: Story, Sandbox, the Sandbox map (Sandbox only), then Import a Story save.
    private var importSaveRow: Int { GameMode.allCases.count + (settings.gameModeChoice == .sandbox ? 1 : 0) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sectionKind(section) {
        // While the game runs, settings that only take effect at the next start are hidden.
        case .mode: return engineRunning ? 0 : importSaveRow + 1
        case .graphics: return engineRunning ? Self.liveGraphicsRows.count : settings.tier.allowed.count + 7 + GraphicsDetail.all.count
        case .controls: return controlsRows.count
        case .cheats: return engineRunning ? cheatRows.count : 0
        case .files: return engineRunning ? 0 : fileRows.count
        case .device: return 5
        case .language: return 1
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if sectionKind(section) == .cheats, !engineRunning { return nil }
        if engineRunning, [.mode, .files].contains(sectionKind(section)) { return nil }
        return [AppLanguage.choose("Language"), AppLanguage.choose("Game mode"), AppLanguage.choose("Graphics"), AppLanguage.choose("Keyboard, mouse and controller"), AppLanguage.choose("Cheats"), AppLanguage.choose("Game files"), AppLanguage.choose("This device")][sectionKind(section).rawValue]
    }

    /// Graphics rows that act during play: resolution, fill the screen, FPS counter, steady when hot,
    /// sharper upscaling (row numbers after the presets). Presets and the frame rate apply at the next start.
    private static let liveGraphicsRows = [0, 1, 3, 4, 6]

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if engineRunning, [.mode, .files].contains(sectionKind(section)) { return nil }
        switch sectionKind(section) {
        case .mode:
            var text = AppLanguage.choose("Story mode saves stay on this phone between launches. Sandbox keeps its own separate files.")
            if let runningMode {
                text = AppLanguage.choose("Changes apply the next time you start the game. ") + text
                if settings.gameMode != runningMode { text += AppLanguage.interpolate(AppLanguage.choose(" Close and reopen the app to play {arg0}."), [String(describing: settings.gameMode.title)]) }
            }
            return text
        case .graphics:
            var text: String
            if engineRunning && !Self.liveResolution { text = AppLanguage.choose("Changes apply the next time you start the game. ") }
            else {
                text = AppLanguage.choose("Resolution changes apply right away. ")
                text += engineRunning ? AppLanguage.choose("Preset and frame rate changes apply the next time you start the game.") : AppLanguage.choose("Presets apply when you press Play.")
            }
            if settings.graphicsPreset != bootPreset && engineRunning { text += AppLanguage.interpolate(AppLanguage.choose(" Restart needed for {arg0}."), [String(describing: settings.graphicsPreset.title)]) }
            if settings.tier.risky(settings.graphicsPreset) { text += AppLanguage.choose(" Higher presets use more memory and GPU power. If a launch fails, the game falls back automatically.") }
            return text
        case .controls:
            return AppLanguage.choose("Use WASD and the mouse, or connect a controller. Configure key bindings and mouse sensitivity in the game’s own settings.")
        case .cheats:
            return engineRunning
                ? AppLanguage.choose("Switches and actions take effect when you're back in the game. Turn God mode and Never wanted off for missions that need damage or a police chase. The game's own cheats close this screen and press the buttons for you, which takes a few seconds. Works in Story mode and Sandbox.")
                : nil
        case .files: return filesFooter()
        case .device: return AppLanguage.choose("GTA-V") + " \(Theme.appVersion). " + AppLanguage.choose("Quote this version when you report a problem.")
        case .language:
            return AppLanguage.choose("Menus change right away. The game itself switches language the next time it starts.")
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let indexPath = actionIndexPath(indexPath)
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .default
        var content = cell.defaultContentConfiguration()
        content.secondaryTextProperties.color = .secondaryLabel
        let presets = settings.tier.allowed
        switch sectionKind(indexPath.section) {
        case .mode where indexPath.row == importSaveRow:
            content.text = AppLanguage.choose("Import a Story save…")
            content.secondaryText = AppLanguage.choose("A save file from a PC or a friend (named like SGTA50000). It goes into a free save slot; load it in the game: Pause › Game › Load Game.")
            content.image = UIImage(systemName: "square.and.arrow.down")
            content.textProperties.color = view.tintColor ?? .systemBlue
        case .mode where indexPath.row == GameMode.allCases.count:
            // Sandbox only: which map.
            content.text = AppLanguage.choose("Sandbox map")
            content.secondaryText = settings.sandboxMap == 1 ? AppLanguage.choose("The test level that comes with the game files") : AppLanguage.choose("The full GTA V map")
            let button = UIButton(configuration: .gray())
            button.configuration?.title = GameSettings.sandboxMapTitles[settings.sandboxMap]
            button.menu = UIMenu(children: GameSettings.sandboxMapTitles.enumerated().map { index, title in
                UIAction(title: title, attributes: index == 1 && !(GameFolder.isChosen && GameFolder.testMapAvailable) ? .disabled : [],
                         state: index == settings.sandboxMap ? .on : .off) { [weak self] _ in
                    self?.settings.sandboxMap = index
                    self?.gameModeChanged?()
                    UIView.performWithoutAnimation { self?.reload(.mode) }
                }
            })
            button.showsMenuAsPrimaryAction = true
            button.sizeToFit()
            cell.accessoryView = button
            cell.selectionStyle = .none
        case .mode:
            let mode = GameMode.allCases[indexPath.row]
            content.text = mode.title + (mode == runningMode ? AppLanguage.choose(" (playing now)") : "")
            content.secondaryText = mode.detail
            cell.accessoryType = settings.gameModeChoice == mode ? .checkmark : .none
        case .graphics:
            let graphicsRow = engineRunning ? presets.count + Self.liveGraphicsRows[indexPath.row] : indexPath.row
            if graphicsRow < presets.count {
                let preset = presets[graphicsRow]
                content.text = preset.title + (preset == settings.tier.recommended ? AppLanguage.choose(" (recommended)") : "")
                content.secondaryText = AppLanguage.interpolate(AppLanguage.choose("Detail level, default {arg0}p · "), [String(describing: preset.height)]) + preset.detail + (settings.tier.risky(preset) ? AppLanguage.choose("\n⚠︎ Above this Mac's recommended preset; uses more memory and GPU power.") : "")
                if settings.tier.risky(preset) { content.secondaryTextProperties.color = .systemOrange }
                cell.accessoryType = preset == settings.graphicsPreset ? .checkmark : .none
            } else {
                let row = graphicsRow - presets.count
                cell.selectionStyle = .none
                if row == 0 {
                    content.text = AppLanguage.choose("Resolution")
                    content.secondaryText = currentSizeText() + (engineRunning && !Self.liveResolution ? "" : AppLanguage.choose(" · changes right away"))
                    let button = UIButton(type: .system)
                    button.setTitle(resolutionTitle(settings.renderHeight) + " ▾", for: .normal)
                    button.showsMenuAsPrimaryAction = true
                    button.accessibilityLabel = AppLanguage.choose("Resolution")
                    let choices = [0] + GraphicsConfiguration.resolutionChoices
                    button.menu = UIMenu(children: choices.map { height in
                        UIAction(title: resolutionTitle(height), state: height == settings.renderHeight ? .on : .off) { [weak self] _ in
                            guard let self else { return }
                            self.settings.renderHeight = height
                            self.resolutionChanged?()
                            self.reloadFooters()
                        }
                    })
                    button.sizeToFit()
                    cell.accessoryView = button
                } else if row == 1 {
                    content.text = AppLanguage.choose("Fill the screen")
                    content.secondaryText = AppLanguage.choose("Render at the screen's shape instead of stretching 16:9")
                    cell.accessoryView = toggle(settings.matchScreenShape, label: AppLanguage.choose("Fill the screen")) { [weak self] in
                        self?.settings.matchScreenShape = $0; self?.resolutionChanged?(); self?.tableView.reloadData()
                    }
                } else if row >= 7, row - 7 < GraphicsDetail.all.count {
                    // The player's own details over the preset (GTA-84): kept when the preset changes.
                    let detail = GraphicsDetail.all[row - 7]
                    let presetValue = detail.presetValue(settings.graphicsPreset)
                    let own = settings.graphicsOverrides[detail.option]
                    content.text = detail.title
                    content.secondaryText = own == nil ? AppLanguage.choose("As the preset · applies when you press Play") : AppLanguage.choose("Your own setting · applies when you press Play")
                    let button = UIButton(type: .system)
                    button.setTitle((own.map(detail.name(of:)) ?? AppLanguage.interpolate(AppLanguage.choose("Preset ({arg0})"), [detail.name(of: presetValue)])) + " ▾", for: .normal)
                    button.showsMenuAsPrimaryAction = true
                    button.accessibilityLabel = detail.title
                    let presetChoice = UIAction(title: AppLanguage.interpolate(AppLanguage.choose("Preset ({arg0})"), [detail.name(of: presetValue)]), state: own == nil ? .on : .off) { [weak self] _ in
                        self?.settings.graphicsOverrides[detail.option] = nil; self?.tableView.reloadData()
                    }
                    button.menu = UIMenu(children: [presetChoice] + zip(detail.values, detail.names).map { value, name in
                        UIAction(title: name, state: own == value ? .on : .off) { [weak self] _ in
                            self?.settings.graphicsOverrides[detail.option] = value; self?.tableView.reloadData()
                        }
                    })
                    button.sizeToFit()
                    cell.accessoryView = button
                } else if row == 6 {
                    content.text = AppLanguage.choose("Sharper upscaling")
                    content.secondaryText = AppLanguage.choose("MetalFX brings the picture to the screen's resolution with sharpening instead of stretching it. Uses a little more battery.")
                    cell.accessoryView = toggle(settings.sharperUpscaling, label: AppLanguage.choose("Sharper upscaling")) { [weak self] in
                        self?.settings.sharperUpscaling = $0
                    }
                } else if row == 3 {
                    // Off, the frame rate, or the frame rate with CPU power, busy cores and the heat state (GTA-216).
                    content.text = AppLanguage.choose("Show FPS counter")
                    let choices = [(AppLanguage.choose("Off"), false, false), (AppLanguage.choose("FPS"), true, false), (AppLanguage.choose("FPS and heat"), true, true)]
                    let current = choices.firstIndex { $0.1 == settings.showFPS && (!$0.1 || $0.2 == settings.showPower) } ?? 1
                    if settings.showFPS && settings.showPower { content.secondaryText = AppLanguage.choose("Watts: the CPU's power. Cores: how many CPU cores the game keeps busy. Then the iPhone's heat state.") }
                    let button = UIButton(type: .system)
                    button.setTitle(choices[current].0 + " ▾", for: .normal)
                    button.showsMenuAsPrimaryAction = true
                    button.accessibilityLabel = AppLanguage.choose("Show FPS counter")
                    button.menu = UIMenu(children: choices.enumerated().map { index, choice in
                        UIAction(title: choice.0, state: index == current ? .on : .off) { [weak self] _ in
                            self?.settings.showFPS = choice.1; self?.settings.showPower = choice.2; self?.tableView.reloadData()
                        }
                    })
                    button.sizeToFit()
                    cell.accessoryView = button
                } else if row == 5 {
                    content.text = AppLanguage.choose("Memory cap")
                    content.secondaryText = AppLanguage.choose("The most memory the game may use. Lower it if the game closes on its own. Applies when you press Play.")
                    let title: (Int) -> String = { $0 == 0 ? AppLanguage.choose("Automatic") : AppLanguage.interpolate(AppLanguage.choose("{arg0} GB"), [String(format: "%g", Double($0) / 1024)]) }
                    let limit = settings.tier.memoryLimitMB
                    let choices = [0] + [2560, 3072, 3584, 4096, 5120, 6144, 7168].filter { $0 < limit }
                    let button = UIButton(type: .system)
                    button.setTitle(title(settings.memoryCapMB) + " ▾", for: .normal)
                    button.showsMenuAsPrimaryAction = true
                    button.accessibilityLabel = AppLanguage.choose("Memory cap")
                    button.menu = UIMenu(children: choices.map { mb in
                        UIAction(title: title(mb), state: mb == settings.memoryCapMB ? .on : .off) { [weak self] _ in
                            self?.settings.memoryCapMB = mb; self?.tableView.reloadData()
                        }
                    })
                    button.sizeToFit()
                    cell.accessoryView = button
                } else if row == 4 {
                    content.text = AppLanguage.choose("Steady frame rate when hot")
                    content.secondaryText = AppLanguage.choose("Fewer stutters and steadier play: lowers the frame rate while the iPhone is hot, and raises it again once it cools down")
                    cell.accessoryView = toggle(settings.steadyWhenHot, label: AppLanguage.choose("Steady frame rate when hot")) { [weak self] in
                        self?.settings.steadyWhenHot = $0
                        NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
                    }
                } else {
                    content.text = AppLanguage.choose("Frame rate")
                    content.secondaryText = GameSettings.supports40
                        ? AppLanguage.choose("Higher uses more power and heat; 30 FPS is steadiest. 40 FPS is smoother than Unlocked when the game runs between 40 and 60. Unlocked goes up to 120.")
                        : AppLanguage.choose("Higher uses more power and heat; 30 FPS is steadiest. Unlocked goes up to 120 on ProMotion iPhones.")
                    let button = UIButton(type: .system)
                    button.setTitle(GameSettings.frameRateTitle(settings.frameRateCap) + " ▾", for: .normal)
                    button.showsMenuAsPrimaryAction = true
                    button.accessibilityLabel = AppLanguage.choose("Frame rate")
                    button.menu = UIMenu(children: GameSettings.frameRateChoices.map { cap in
                        UIAction(title: GameSettings.frameRateTitle(cap), state: cap == settings.frameRateCap ? .on : .off) { [weak self] _ in
                            self?.settings.frameRateCap = cap; self?.reloadFooters(); self?.tableView.reloadData()
                            // Applied in play too: the frame limit follows the setting (see thermalChanged).
                            NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
                        }
                    })
                    button.sizeToFit()
                    cell.accessoryView = button
                }
            }
        case .controls:
            cell.selectionStyle = .none
            switch controlsRows[indexPath.row] {
            case .targeting:
                content.text = AppLanguage.choose("Targeting")
                let button = UIButton(configuration: .gray())
                button.configuration?.title = GameSettings.targetingTitles[settings.targetingMode]
                button.menu = UIMenu(children: GameSettings.targetingTitles.enumerated().map { index, title in
                    UIAction(title: title, state: index == settings.targetingMode ? .on : .off) { [weak self] _ in
                        self?.settings.targetingMode = index
                        self?.targetingChanged?()
                        UIView.performWithoutAnimation { self?.reload(.controls) }
                    }
                })
                button.showsMenuAsPrimaryAction = true
                button.sizeToFit()
                cell.accessoryView = button
            case .minimap:
                // Where the game's minimap sits (GTA-131): the game reads it when it starts.
                content.text = AppLanguage.choose("Minimap")
                content.secondaryText = AppLanguage.choose("Where the map sits. Changes apply the next time the game starts.")
                let button = UIButton(type: .system)
                button.setTitle(settings.minimapPlace.title + " ▾", for: .normal)
                button.accessibilityLabel = AppLanguage.choose("Minimap")
                button.showsMenuAsPrimaryAction = true
                button.menu = UIMenu(children: GameSettings.MinimapPlace.allCases.map { place in
                    UIAction(title: place.title, state: place == settings.minimapPlace ? .on : .off) { [weak self] _ in
                        guard let self else { return }
                        if place == .custom { self.editHUD(.minimap) } else { self.settings.minimapPlace = place; self.reload(.controls) }
                    }
                })
                button.sizeToFit()
                cell.accessoryView = button
                cell.selectionStyle = .none
            case .helpText:
                // Where the game's help messages show: the game reads it when it starts.
                content.text = AppLanguage.choose("Help messages")
                content.secondaryText = AppLanguage.choose("Where the game's \"Press … to …\" box shows. Changes apply the next time the game starts.")
                let button = UIButton(type: .system)
                button.setTitle(settings.helpTextPlace.title + " ▾", for: .normal)
                button.accessibilityLabel = AppLanguage.choose("Help messages")
                button.showsMenuAsPrimaryAction = true
                button.menu = UIMenu(children: GameSettings.HelpTextPlace.allCases.map { place in
                    UIAction(title: place.title, state: place == settings.helpTextPlace ? .on : .off) { [weak self] _ in
                        guard let self else { return }
                        if place == .custom { self.editHUD(.helpText) } else { self.settings.helpTextPlace = place; self.reload(.controls) }
                    }
                })
                button.sizeToFit()
                cell.accessoryView = button
                cell.selectionStyle = .none
            case .hudLayout:
                content.text = AppLanguage.choose("HUD layout")
                content.secondaryText = settings.hudLayoutCustomized ? AppLanguage.choose("Customized")
                    : AppLanguage.choose("Move the character wheel, FPS counter, map and other HUD pieces")
                content.textProperties.color = .systemBlue
                cell.selectionStyle = .default
            case .keyboardMouse:
                content.text = AppLanguage.choose("Keyboard and mouse")
                content.secondaryText = AppLanguage.choose("Play with WASD, mouse look, mouse buttons and the scroll wheel.")
                cell.accessoryView = toggle(settings.keyboardMouse, label: AppLanguage.choose("Keyboard and mouse")) { [weak self] in
                    self?.settings.keyboardMouse = $0
                    if !$0 { KeyboardMouse.shared.releaseAll() }
                }
            case .inputState:
                content.text = AppLanguage.choose("Input device (live test)")
                let device = PGLastInputDevice()
                let kind = device == -4 ? AppLanguage.choose("Mouse/keyboard") : (0...3).contains(device) ? AppLanguage.choose("Controller") : AppLanguage.choose("Unknown")
                content.secondaryText = AppLanguage.interpolate(AppLanguage.choose("{arg0} [{arg1}] · Aim mode: {arg2}"), [kind, String(device), String(PGTargetingMode())])
            }
        case .cheats where indexPath.row == 0:
            content.text = AppLanguage.choose("Spawn vehicle")
            content.secondaryText = AppLanguage.choose("Search all vehicles available in this game")
            cell.accessoryType = .disclosureIndicator
        case .cheats where indexPath.row == 1:
            content.text = AppLanguage.choose("Set money")
            content.secondaryText = AppLanguage.choose("Type an amount for the character you're playing. Handy if the old $0 bug took yours.")
        case .cheats where indexPath.row < storyCheatStart:
            let group = NativeCheatGroup.all[indexPath.row - 2]
            content.text = AppLanguage.choose(group.title)
            content.secondaryText = AppLanguage.choose(group.detail)
            if let cheat = group.toggle {
                cell.selectionStyle = .none
                cell.accessoryView = toggle(PGCheatEnabled(cheat), label: AppLanguage.choose(group.title)) {
                    _ = PGSetPersistentCheatEnabled(cheat, $0)
                }
            } else if group.actions.count > 1 { cell.accessoryType = .disclosureIndicator }
        case .cheats:
            let cheat = StoryCheats.all[indexPath.row - storyCheatStart]
            content.text = AppLanguage.choose(cheat.title)
            content.secondaryText = AppLanguage.choose(cheat.detail)
        case .files:
            configureFileCell(cell, &content, fileRows[indexPath.row])
        case .language:
            cell.selectionStyle = .none
            content.text = AppLanguage.choose("App language")
            content.secondaryText = AppLanguage.choose("Language for menus and settings")
            let button = UIButton(type: .system)
            button.setTitle(AppLanguage.current.name + " ▾", for: .normal)
            button.accessibilityLabel = AppLanguage.choose("App language")
            button.showsMenuAsPrimaryAction = true
            button.menu = UIMenu(children: AppLanguage.allCases.map { language in
                UIAction(title: language.name, state: language == AppLanguage.current ? .on : .off) { [weak self] _ in
                    AppLanguage.select(language)
                    self?.title = AppLanguage.choose("Settings")
                    self?.navigationItem.rightBarButtonItem?.title = AppLanguage.choose("Done")
                    self?.tableView.reloadData()
                    (self?.parent as? SettingsHomeViewController)?.refreshLanguageIfNeeded()
                }
            })
            button.sizeToFit()
            cell.accessoryView = button
        case .device:
            if indexPath.row == 0 {
                content.text = settings.tier.displaySummary
                content.secondaryText = settings.tier.increasedMemoryStatus
                #if targetEnvironment(macCatalyst)
                content.secondaryTextProperties.color = .secondaryLabel
                #else
                content.secondaryTextProperties.color = DeviceTier.increasedMemoryGranted == false ? .systemOrange : .secondaryLabel
                #endif
                content.textProperties.font = .preferredFont(forTextStyle: .footnote)
                content.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
            } else {
                // Experimental (v1.4.3, BC3 v1.4.4): on by default; turning one off applies the next time the app starts.
                let rows: [(String, String, ReferenceWritableKeyPath<GameSettings, Bool>)] = [
                    (AppLanguage.choose("Smarter texture loading"), AppLanguage.choose("Keeps streaming memory available for the ground and roads."), \.smarterTextureLoading),
                    (AppLanguage.choose("Faster engine threads"), AppLanguage.choose("Runs engine work at a higher scheduling priority."), \.fastEngineThreads),
                    (AppLanguage.choose("Lighter 3D models in memory"), AppLanguage.choose("Releases the CPU copy of meshes after uploading them to the GPU."), \.meshMemoryRelease),
                    (AppLanguage.choose("More engine memory"), AppLanguage.choose("Gives the engine additional address space for streaming."), \.smallerEngineHeaps),
                ]
                let (title, detail, key) = rows[indexPath.row - 1]
                content.text = title
                content.secondaryText = detail + " " + AppLanguage.choose("Applies the next time the app starts.")
                cell.accessoryView = toggle(settings[keyPath: key], label: title) { [weak self] in self?.settings[keyPath: key] = $0 }
                cell.selectionStyle = .none
            }
        }
        if embedded {
            // Keep the desktop menu dense; the full explanation remains available to VoiceOver.
            if let button = cell.accessoryView as? UIButton {
                Theme.styleSettingsButton(button)
            }
            cell.accessibilityHint = content.secondaryText
            if sectionKind(indexPath.section) != .device { content.secondaryText = nil }
            content.textProperties.font = Theme.body(20, .regular)
            content.secondaryTextProperties.font = Theme.body(16, .regular)
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        }
        cell.contentConfiguration = content
        return cell
    }

    /// An action row: one action runs right away (Settings closes first); several open a list to pick from.
    private func selectNativeCheat(_ group: NativeCheatGroup, at indexPath: IndexPath) {
        guard group.toggle == nil else { return }
        let run: (NativeCheatAction) -> Void = { [weak self] action in
            guard let self else { return }
            let selected = self.nativeCheatSelected
            self.navigationController?.dismiss(animated: true) { selected?(action) }
        }
        if group.actions.count == 1 { run(group.actions[0]); return }
        let sheet = UIAlertController(title: AppLanguage.choose(group.title), message: AppLanguage.choose(group.detail), preferredStyle: .actionSheet)
        for action in group.actions {
            sheet.addAction(UIAlertAction(title: AppLanguage.choose(action.title), style: .default) { _ in run(action) })
        }
        sheet.addAction(UIAlertAction(title: AppLanguage.choose("Cancel"), style: .cancel))
        guard let anchor: UIView = tableView.cellForRow(at: indexPath) ?? tableView else { return }
        sheet.popoverPresentationController?.sourceView = anchor
        sheet.popoverPresentationController?.sourceRect = anchor.bounds
        present(sheet, animated: true)
    }

    /// Set money: a number field; the money changes once Settings closes and the game runs a frame.
    private func askForMoney() {
        let alert = UIAlertController(title: AppLanguage.choose("Set money"),
                                      message: AppLanguage.choose("The money of the character you're playing (Michael, Franklin or Trevor) becomes this amount. Save the game to keep it."),
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "1000000"
        }
        alert.addAction(UIAlertAction(title: AppLanguage.choose("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: AppLanguage.choose("Set"), style: .default) { [weak self, weak alert] _ in
            let digits = (alert?.textFields?.first?.text ?? "").filter(\.isNumber)
            guard let self, let value = Int64(digits.prefix(10)) else { return }
            let amount = Int32(min(value, Int64(Int32.max)))
            self.dismiss(animated: true) { self.moneyEntered?(amount) }
        })
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let visibleIndexPath = indexPath
        let indexPath = actionIndexPath(indexPath)
        if sectionKind(indexPath.section) == .controls,
           controlsRows[indexPath.row] == .hudLayout { editHUD(); return }
        if sectionKind(indexPath.section) == .cheats, indexPath.row == 0 {
            let page = VehicleSpawnViewController()
            page.vehicleSelected = vehicleSelected
            navigationController?.pushViewController(page, animated: true)
            return
        }
        if sectionKind(indexPath.section) == .cheats, indexPath.row == 1 { askForMoney(); return }
        if sectionKind(indexPath.section) == .cheats, indexPath.row < storyCheatStart {
            selectNativeCheat(NativeCheatGroup.all[indexPath.row - 2], at: visibleIndexPath)
            return
        }
        if sectionKind(indexPath.section) == .cheats {
            let cheat = StoryCheats.all[indexPath.row - storyCheatStart]
            dismiss(animated: true) { self.cheatSelected?(cheat) }
            return
        }
        if sectionKind(indexPath.section) == .mode, indexPath.row == importSaveRow {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .data], asCopy: true)
            picker.delegate = savePickerDelegate
            savePickerDelegate.done = { [weak self] outcome in self?.showSaveImport(outcome) }
            present(picker, animated: true)
            return
        }
        if sectionKind(indexPath.section) == .mode {
            guard indexPath.row < GameMode.allCases.count else { return }
            settings.gameMode = GameMode.allCases[indexPath.row]
            gameModeChanged?()
            UIView.performWithoutAnimation { reload(.mode) }
            return
        }
        if sectionKind(indexPath.section) == .files { selectFileRow(fileRows[indexPath.row]); return }
        let presets = settings.tier.allowed
        guard sectionKind(indexPath.section) == .graphics, !engineRunning, indexPath.row < presets.count else { return }
        settings.graphicsPreset = presets[indexPath.row]
        resolutionChanged?()
        UIView.performWithoutAnimation { reload(.graphics) }
    }

    // MARK: Game files

    private func makeFileRows() -> [FileRow] {
        let phase = preloader.phase
        let hasFiles = preloader.cachedBytes > 0
        switch phase {
        case .unavailable: return [.status]
        case .idle: return hasFiles ? [.start, .remove] : [.start]
        case .downloading: return [.status, .pause, .cancel]
        case .paused: return [.status, .resume, .cancel] + (hasFiles ? [.remove] : [])
        case .complete: return [.status, .remove]
        }
    }

    @objc private func preloadChanged() {
        let rows = makeFileRows()
        guard shown.contains(.files) else { fileRows = rows; return }
        let section = indexOf(.files)
        // Footer text depends on these; a footer only resizes on a reload.
        let key = "\(rows)|\(preloader.phase)|\(preloader.removing)|\(preloader.lastError ?? "")|\(fileMessage ?? "")|\(preloader.measured)|\(preloader.cachedBytes > 0)"
        if rows != fileRows || key != fileStateKey {
            fileRows = rows
            fileStateKey = key
            UIView.performWithoutAnimation { tableView.reloadSections([section], with: .none) }
            return
        }
        // Same rows: refresh the visible text in place (no flicker).
        for (row, kind) in rows.enumerated() {
            guard let cell = tableView.cellForRow(at: IndexPath(row: row, section: section)) else { continue }
            var content = cell.defaultContentConfiguration()
            content.secondaryTextProperties.color = .secondaryLabel
            configureFileCell(cell, &content, kind)
            cell.contentConfiguration = content
        }
    }

    private func progressText() -> String {
        let percent = Int((preloader.fraction * 100).rounded(.down))
        var text = AppLanguage.interpolate(AppLanguage.choose("{arg0}% · {arg1} of {arg2}"), [String(describing: percent), String(describing: AssetPreloader.format(preloader.cachedBytes)), String(describing: AssetPreloader.format(preloader.totalBytes))])
        if preloader.phase == .downloading {
            if let rate = preloader.bytesPerSecond { text += " · \(AssetPreloader.format(UInt64(rate)))/s" }
            if let seconds = preloader.secondsRemaining { text += " · " + AssetPreloader.formatDuration(seconds) }
        }
        return text
    }

    private func configureFileCell(_ cell: UITableViewCell, _ content: inout UIListContentConfiguration, _ row: FileRow) {
        let total = preloader.measured ? AssetPreloader.format(preloader.totalBytes) : AppLanguage.choose("Checking size")
        switch row {
        case .status:
            cell.selectionStyle = .none
            switch preloader.phase {
            case .unavailable(let reason):
                content.text = AppLanguage.choose("Download all game files")
                content.secondaryText = reason
                content.textProperties.color = .secondaryLabel
            case .complete:
                content.text = AppLanguage.choose("All files on device")
                content.secondaryText = AppLanguage.interpolate(AppLanguage.choose("{arg0} · plays without streaming"), [String(describing: total)])
                content.image = UIImage(systemName: "checkmark.circle.fill")
                content.imageProperties.tintColor = Theme.ok
            case .downloading:
                content.text = AppLanguage.choose("Downloading game files")
                content.secondaryText = progressText()
                cell.accessoryView = progressView()
            default:
                content.text = preloader.lastError == nil ? AppLanguage.choose("Download paused") : AppLanguage.choose("Download stopped")
                content.secondaryText = progressText()
                cell.accessoryView = progressView()
            }
        case .start:
            content.text = AppLanguage.choose("Download all game files")
            content.textProperties.color = .tintColor
            if preloader.cachedBytes > 0 && preloader.measured {
                content.secondaryText = AppLanguage.interpolate(AppLanguage.choose("{arg0} · {arg1} already on this iPhone"), [String(describing: total), String(describing: AssetPreloader.format(preloader.cachedBytes))])
            } else {
                content.secondaryText = total
            }
            content.image = UIImage(systemName: "arrow.down.circle")
        case .pause:
            content.text = AppLanguage.choose("Pause")
            content.textProperties.color = .tintColor
            content.image = UIImage(systemName: "pause.circle")
        case .resume:
            content.text = AppLanguage.choose("Resume download")
            content.textProperties.color = .tintColor
            content.image = UIImage(systemName: "arrow.down.circle")
        case .cancel:
            content.text = AppLanguage.choose("Cancel download")
            content.secondaryText = AppLanguage.choose("Keeps what is already downloaded")
            content.textProperties.color = .systemRed
            content.image = UIImage(systemName: "xmark.circle")
            content.imageProperties.tintColor = .systemRed
        case .remove:
            content.text = preloader.removing ? AppLanguage.choose("Removing files…") : AppLanguage.choose("Remove downloaded files")
            content.secondaryText = engineRunning ? AppLanguage.choose("Available after restarting the app") : AppLanguage.interpolate(AppLanguage.choose("Frees {arg0}"), [String(describing: AssetPreloader.format(preloader.cachedBytes))])
            content.textProperties.color = engineRunning ? .secondaryLabel : .systemRed
            content.image = UIImage(systemName: "trash")
            content.imageProperties.tintColor = engineRunning ? .secondaryLabel : .systemRed
            cell.selectionStyle = engineRunning ? .none : .default
        }
    }

    private func progressView() -> UIProgressView {
        let bar = UIProgressView(progressViewStyle: .default)
        bar.frame.size.width = 110
        bar.progress = Float(preloader.fraction)
        bar.accessibilityLabel = AppLanguage.choose("Download progress")
        return bar
    }

    private func filesFooter() -> String {
        var text = ""
        if let message = fileMessage ?? preloader.lastError { text = message + "\n\n" }
        switch preloader.phase {
        case .unavailable: return text
        case .complete:
            text += AppLanguage.choose("The game reads everything from this iPhone. Removing the files frees the space; the game then streams again.")
        default:
            let size = preloader.measured ? AssetPreloader.format(preloader.totalBytes) : AppLanguage.choose("about 21 GB")
            text += AppLanguage.interpolate(AppLanguage.choose("Saves the whole game on this iPhone ({arg0}) so it no longer streams from the server. Tailscale must be connected while it downloads. Keep the app open: in the background the download pauses after a short while and continues when you come back. You can play while it downloads."), [size])
            if preloader.cachedBytes > 0 && preloader.phase != .downloading {
                text += AppLanguage.choose(" Removing files also clears the startup set; the next Play prepares it again.")
            }
        }
        return text
    }

    private func selectFileRow(_ row: FileRow) {
        fileMessage = nil
        switch row {
        case .status: return
        case .start, .resume:
            let start = { [weak self] in
                guard let self else { return }
                if let message = self.preloader.start() { self.showAlert(AppLanguage.choose("Can't download"), message) }
            }
            if row == .start {
                let alert = UIAlertController(title: AppLanguage.choose("Download all game files?"),
                    message: AppLanguage.interpolate(AppLanguage.choose("This saves {arg0} more on this iPhone ({arg1} free). Wi-Fi and Tailscale recommended."), [String(describing: AssetPreloader.format(preloader.missingBytes)), String(describing: AssetPreloader.format(preloader.availableBytes()))]),
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: AppLanguage.choose("Cancel"), style: .cancel))
                alert.addAction(UIAlertAction(title: AppLanguage.choose("Download"), style: .default) { _ in start() })
                present(alert, animated: true)
            } else { start() }
        case .pause: preloader.pause()
        case .cancel: preloader.cancel()
        case .remove:
            guard !engineRunning else { return }
            let alert = UIAlertController(title: AppLanguage.choose("Remove downloaded files?"),
                message: AppLanguage.interpolate(AppLanguage.choose("Frees {arg0}. The game will stream from the server again."), [String(describing: AssetPreloader.format(preloader.cachedBytes))]),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: AppLanguage.choose("Cancel"), style: .cancel))
            alert.addAction(UIAlertAction(title: AppLanguage.choose("Remove"), style: .destructive) { [weak self] _ in
                guard let self else { return }
                self.preloader.removeDownloads { message in
                    if let message { self.showAlert(AppLanguage.choose("Can't remove files"), message) }
                }
            })
            present(alert, animated: true)
        }
        preloadChanged()
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: AppLanguage.choose("OK"), style: .default))
        present(alert, animated: true)
    }

    /// Resolution changes during play: live on the Mac (window resizes need it); on iPhone and iPad they wait for the
    /// next start, because a third of the live resizes in player logs ended the run soon after (GTA-89: the game frees
    /// textures still in use while it rebuilds its render targets).
    static var liveResolution: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }
    private func currentSizeText() -> String {
        let screen = view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        let (w, h) = GraphicsConfiguration.size(for: engineRunning ? bootPreset : settings.graphicsPreset, renderHeight: settings.renderHeight,
                                                screen: screen, matchScreenShape: settings.matchScreenShape)
        return AppLanguage.interpolate(AppLanguage.choose("Renders at {arg0}×{arg1}"), [String(describing: w), String(describing: h)])
    }
    private func resolutionTitle(_ height: Int) -> String {
        if height == 0 {
            let screen = view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
            let (_, h) = GraphicsConfiguration.size(for: engineRunning ? bootPreset : settings.graphicsPreset, renderHeight: 0, screen: screen, matchScreenShape: settings.matchScreenShape)
            return AppLanguage.interpolate(AppLanguage.choose("Auto ({arg0}p)"), [String(describing: h)])
        }
        return height == GraphicsConfiguration.nativeHeight ? AppLanguage.interpolate(AppLanguage.choose("Native ({arg0}p)"), [String(describing: height)]) : "\(height)p"
    }
    private func reloadFooters() {
        UIView.performWithoutAnimation { reload(.graphics) }
    }
    /// Compact slider plus a live numeric readout; unlike a secondaryText
    /// snapshot the displayed value follows the finger without reloading rows.
    private func sensitivitySlider(_ value: Double, low: Double, high: Double,
                                   label: String, changed: @escaping (Double) -> Void) -> UIView {
        let view = UIStackView()
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 7
        view.frame.size = CGSize(width: 175, height: 32)
        let slider = UISlider()
        slider.minimumValue = Float(low)
        slider.maximumValue = Float(high)
        slider.value = Float(value)
        slider.accessibilityLabel = label
        let number = UILabel()
        number.text = String(format: "%.1f×", value)
        number.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        number.textColor = .secondaryLabel
        number.textAlignment = .right
        number.widthAnchor.constraint(equalToConstant: 43).isActive = true
        slider.addAction(UIAction { [weak slider, weak number] _ in
            guard let slider else { return }
            let rounded = (Double(slider.value) * 10).rounded() / 10
            number?.text = String(format: "%.1f×", rounded)
            changed(rounded)
        }, for: .valueChanged)
        view.addArrangedSubview(slider)
        view.addArrangedSubview(number)
        return view
    }
    private func slider(_ value: Double, _ low: Float, _ high: Float, label: String, changed: @escaping (Double) -> Void) -> UISlider {
        let control = UISlider()
        control.minimumValue = low; control.maximumValue = high
        control.value = Float(value)
        control.frame.size.width = 160
        control.accessibilityLabel = label
        control.addAction(UIAction { [weak control] _ in changed(Double(control?.value ?? 0)) }, for: .valueChanged)
        return control
    }
    private func toggle(_ on: Bool, label: String, changed: @escaping (Bool) -> Void) -> UISwitch {
        let control = UISwitch()
        control.isOn = on
        control.accessibilityLabel = label
        control.addAction(UIAction { [weak control] _ in changed(control?.isOn ?? false) }, for: .valueChanged)
        return control
    }
}

// MARK: Import a Story save

final class SavePickerDelegate: NSObject, UIDocumentPickerDelegate {
    var done: ((SaveImport.Outcome) -> Void)?
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let outcome = SaveImport.importSave(from: url)
        DispatchQueue.main.async { self.done?(outcome) }
    }
}



extension SettingsViewController {
    fileprivate func showSaveImport(_ outcome: SaveImport.Outcome) {
        let alert: UIAlertController
        switch outcome {
        case let .imported(title, slot):
            alert = UIAlertController(title: AppLanguage.choose("Save imported"),
                                      message: AppLanguage.interpolate(AppLanguage.choose("\"{arg0}\" is in save slot {arg1}. Start Story mode, then load it: Pause › Game › Load Game."), [title, String(slot)]),
                                      preferredStyle: .alert)
        case let .failed(message):
            alert = UIAlertController(title: AppLanguage.choose("Couldn't import the save"), message: message, preferredStyle: .alert)
        }
        alert.addAction(UIAlertAction(title: AppLanguage.choose("OK"), style: .cancel))
        present(alert, animated: true)
    }
}

/// What the Settings home screen needs from a page to drive it with the keyboard.
protocol SettingsKeyboardNavigable: AnyObject {
    /// Shows or hides the highlighted row. Turning it on starts at the first row you can use.
    func setKeyboardFocus(_ on: Bool)
    func moveCursor(_ delta: Int)
    /// Left / Right on the highlighted row. Returns false when the row has nothing to change.
    func adjustCursor(_ delta: Int) -> Bool
    /// Enter / Space: flips a switch, steps a drop-down, or presses a button row.
    func activateCursor()
}

extension SettingsTableViewController: SettingsKeyboardNavigable {
    func setKeyboardFocus(_ on: Bool) {
        let old = keyboardCursor
        keyboardActive = on
        keyboardCursor = on ? navigablePaths().first : nil
        if let path = keyboardCursor { optionDescriptionChanged?(cell(at: path)?.accessibilityHint) }
        reloadRows([old, keyboardCursor])
    }

    func moveCursor(_ delta: Int) {
        let paths = navigablePaths()
        guard !paths.isEmpty else { return }
        let old = keyboardCursor
        let index = old.flatMap { paths.firstIndex(of: $0) } ?? (delta > 0 ? -1 : paths.count)
        let next = min(max(index + delta, 0), paths.count - 1)
        keyboardCursor = paths[next]
        if let path = keyboardCursor { optionDescriptionChanged?(cell(at: path)?.accessibilityHint) }
        reloadRows([old, keyboardCursor])
        tableView.scrollToRow(at: paths[next], at: .none, animated: false)
    }

    func adjustCursor(_ delta: Int) -> Bool {
        guard let path = keyboardCursor, isValid(path), let cell = cell(at: path), let control = control(in: cell) else { return false }
        switch control {
        case .toggle(let toggle):
            let target = delta > 0
            if toggle.isOn != target {
                toggle.setOn(target, animated: false)
                toggle.sendActions(for: .valueChanged)
            }
        case .slider(let slider):
            let step = (slider.maximumValue - slider.minimumValue) / 20
            slider.value = min(max(slider.value + Float(delta) * step, slider.minimumValue), slider.maximumValue)
            slider.sendActions(for: .valueChanged)
        case .segments(let tabs):
            let next = min(max(tabs.selectedSegmentIndex + delta, 0), tabs.numberOfSegments - 1)
            if next != tabs.selectedSegmentIndex {
                tabs.selectedSegmentIndex = next
                tabs.sendActions(for: .valueChanged)
            }
        case .menu(let button):
            cycle(button, delta)
        }
        reloadRows([keyboardCursor])
        return true
    }

    func activateCursor() {
        guard let path = keyboardCursor, isValid(path), let cell = cell(at: path) else { return }
        if let control = control(in: cell) {
            switch control {
            case .toggle(let toggle):
                toggle.setOn(!toggle.isOn, animated: false)
                toggle.sendActions(for: .valueChanged)
            case .menu(let button):
                cycle(button, 1)
            case .slider, .segments:
                return // Left and Right change these.
            }
            reloadRows([keyboardCursor])
            return
        }
        guard cell.selectionStyle != .none else { return }
        self.tableView(self.tableView, didSelectRowAt: path)
    }

    override func tableView(_ tableView: UITableView, didHighlightRowAt indexPath: IndexPath) {
        optionDescriptionChanged?(cell(at: indexPath)?.accessibilityHint)
    }

    // MARK: Helpers

    private enum Control {
        case toggle(UISwitch), slider(UISlider), menu(UIButton), segments(UISegmentedControl)
    }

    private func control(in cell: UITableViewCell) -> Control? {
        if let tabs = cell.contentView.subviews.compactMap({ $0 as? UISegmentedControl }).first { return .segments(tabs) }
        switch cell.accessoryView {
        case let toggle as UISwitch: return .toggle(toggle)
        case let slider as UISlider: return .slider(slider)
        case let button as UIButton where button.menu != nil: return .menu(button)
        case let view?: return findSlider(in: view).map { .slider($0) }
        default: return nil
        }
    }

    private func findSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider { return slider }
        for subview in view.subviews { if let slider = findSlider(in: subview) { return slider } }
        return nil
    }

    /// Steps a drop-down to the next or previous choice by running that choice's action (iOS 16 and later).
    private func cycle(_ button: UIButton, _ delta: Int) {
        guard let menu = button.menu else { return }
        let actions = menuActions(menu).filter { !$0.attributes.contains(.disabled) }
        guard !actions.isEmpty else { return }
        let current = actions.firstIndex { $0.state == .on } ?? (delta > 0 ? -1 : 0)
        let next = (current + delta + actions.count) % actions.count
        if #available(iOS 16.0, *) { actions[next].performWithSender(nil, target: nil) }
    }

    private func menuActions(_ menu: UIMenu) -> [UIAction] {
        menu.children.flatMap { child -> [UIAction] in
            if let action = child as? UIAction { return [action] }
            if let submenu = child as? UIMenu { return menuActions(submenu) }
            return []
        }
    }

    /// Rows the cursor can stop on: anything with a control or that reacts to a tap. Plain info rows are skipped.
    private func navigablePaths() -> [IndexPath] {
        var result: [IndexPath] = []
        for section in 0..<tableView.numberOfSections {
            for row in 0..<tableView.numberOfRows(inSection: section) {
                let path = IndexPath(row: row, section: section)
                guard let cell = tableView.dataSource?.tableView(tableView, cellForRowAt: path) else { continue }
                if cell.selectionStyle != .none || control(in: cell) != nil { result.append(path) }
            }
        }
        return result
    }

    private func cell(at path: IndexPath) -> UITableViewCell? {
        tableView.cellForRow(at: path) ?? tableView.dataSource?.tableView(tableView, cellForRowAt: path)
    }

    private func isValid(_ path: IndexPath) -> Bool {
        path.section < tableView.numberOfSections && path.row < tableView.numberOfRows(inSection: path.section)
    }

    private func reloadRows(_ paths: [IndexPath?]) {
        let valid = Array(Set(paths.compactMap { $0 }.filter(isValid)))
        if !valid.isEmpty { tableView.reloadRows(at: valid, with: .none) }
    }
}
