import UIKit

/// Settings in the style of GTA V's own settings menu: a white SETTINGS bar, the categories in a column on the
/// left, the highlighted category's options on the right.
///
/// Keyboard:
///   Up / Down      move through categories, or through the options once you are inside
///   Right / Enter  go into the options (or open Mods / Self Radio)
///   Left / Right   change the highlighted option (slider, switch, drop-down)
///   Enter / Space  press the highlighted row
///   Esc            close Settings and return to the previous screen
///   Delete         back to the categories, then close Settings
final class SettingsHomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var openModMenuOnAppear = false
    private let engineRunning: Bool
    private let runningMode: GameMode?
    var resolutionChanged: (() -> Void)?
    var controlsChanged: (() -> Void)?
    var editLayout: (() -> Void)?
    var targetingChanged: (() -> Void)?
    var gameModeChanged: (() -> Void)?
    var cheatSelected: ((StoryCheat) -> Void)?
    var moneyEntered: ((Int32) -> Void)?
    var vehicleSelected: ((SpawnVehicle, Bool) -> Void)?
    var nativeCheatSelected: ((NativeCheatAction) -> Void)?

    /// Name of an image in the asset catalog drawn behind the menu. A dark colour is used when it is missing.
    private static let backgroundImageName = "SettingsBackground"
    static let cursorFill = UIColor(white: 0.94, alpha: 1)
    static let rowFill = UIColor(white: 0, alpha: 0.62)

    private struct Category {
        let icon: String
        let title: String
        let summary: () -> String
        let sections: Set<SettingsViewController.Section>
        var page: (() -> UIViewController)? = nil
        var modCategory: NativeCheatGroup.Category? = nil
    }
    private func makeCategories() -> [Category] {
        let settings = GameSettings.shared, running = engineRunning
        if openModMenuOnAppear && engineRunning {
            return NativeCheatGroup.Category.allCases.map { category in
                let text: (String, String)
                switch category {
                case .vehicles: text = ("Vehicles", "Spawn, repair and clean vehicles")
                case .player: text = ("Player", "Money, God mode and wanted level")
                case .world: text = ("World", "Weather and time of day")
                case .story: text = ("Story cheats", "The game's original cheat sequences")
                }
                return Category(icon: "wand.and.stars", title: AppLanguage.choose(text.0),
                                summary: { AppLanguage.choose(text.1) }, sections: [.cheats], modCategory: category)
            }
        }

        var list = [
            Category(icon: "display", title: AppLanguage.choose("Graphics"), summary: {
                AppLanguage.interpolate(AppLanguage.choose("{arg0}, resolution, frame rate, memory"), [settings.graphicsPreset.title])
            }, sections: [.graphics]),
            Category(icon: "gamecontroller", title: AppLanguage.choose("Controls"), summary: {
                AppLanguage.choose("Keyboard, mouse, controller and HUD layout")
            }, sections: [.controls]),
        ]
        if engineRunning {
            list.append(Category(icon: "wand.and.stars", title: AppLanguage.choose("Mod menu"), summary: {
                AppLanguage.choose("Vehicles, repairs, weather, time, money and more")
            }, sections: [.cheats]))
        }
        list.append(Category(icon: "globe", title: engineRunning ? AppLanguage.choose("Language") : AppLanguage.choose("Game mode and language"), summary: {
            running ? AppLanguage.current.name : "\(settings.gameMode.title) · \(AppLanguage.current.name)"
        }, sections: [.language, .mode]))
        if !engineRunning {
            list.append(Category(icon: "folder", title: AppLanguage.choose("Game files"), summary: {
                AppLanguage.choose("Where the game is, checking and downloading its files")
            }, sections: [.files]))
        }
        list.append(Category(icon: "shippingbox", title: AppLanguage.choose("Mods"), summary: {
            let count = ModInstaller.installed().filter(\.enabled).count
            return count == 0 ? AppLanguage.choose("Install car, skin and script mods") : AppLanguage.interpolate(AppLanguage.choose("{arg0} mods on"), [String(count)])
        }, sections: [], page: { ModsViewController() }))
        list.append(Category(icon: "radio", title: AppLanguage.choose("Self Radio"), summary: {
            let count = SelfRadio.files().count
            return count == 0 ? AppLanguage.choose("Your own music as a radio station") : AppLanguage.interpolate(AppLanguage.choose("{arg0} songs"), [String(count)])
        }, sections: [], page: { SelfRadioViewController() }))
        list.append(Category(icon: "desktopcomputer", title: AppLanguage.choose("This Mac"), summary: {
            AppLanguage.choose("Memory and device options")
        }, sections: [.device]))
        return list
    }

    private enum Focus { case categories, options }
    private var focus: Focus = .categories { didSet { updateFocusUI() } }
    private lazy var list: [Category] = makeCategories()
    private var selectedIndex = 0
    private var pages: [Int: UIViewController] = [:]
    private var pagesLanguage = AppLanguage.current
    private var current: UIViewController?
    private var navigable: SettingsKeyboardNavigable? { current as? SettingsKeyboardNavigable }

    private let done = UIButton(type: .system)
    private let headerBar = UIView()
    private let headerTitle = UILabel()
    private let categoriesTable = UITableView(frame: .zero, style: .plain)
    private let versionLabel = UILabel()
    private let panel = UIView()
    private let optionHelp = SettingsInsetLabel()
    private var menuTop: NSLayoutConstraint!
    private var menuHeight: NSLayoutConstraint!
    private var panelHeight: NSLayoutConstraint!
    private var categoryHeight: NSLayoutConstraint!
    private var contentObservation: NSKeyValueObservation?
    private var categoryObservation: NSKeyValueObservation?

    init(engineRunning: Bool, runningMode: GameMode?) {
        self.engineRunning = engineRunning
        self.runningMode = runningMode
        super.init(nibName: nil, bundle: nil)
        title = AppLanguage.choose("Settings")
        modalPresentationStyle = .fullScreen
        overrideUserInterfaceStyle = .dark
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Layout

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.05, alpha: 1)
        if let art = UIImage(named: Self.backgroundImageName) {
            let picture = UIImageView(image: art)
            picture.contentMode = .scaleAspectFill
            picture.clipsToBounds = true
            picture.frame = view.bounds
            picture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(picture)
            let dim = UIView(frame: view.bounds)
            dim.backgroundColor = UIColor(white: 0, alpha: 0.18)
            dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(dim)
        }

        // White title bar, like GTA V's.
        headerBar.backgroundColor = Self.cursorFill
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        updateHeaderTitle()
        done.setTitle(AppLanguage.choose("Done"), for: .normal)
        done.setTitleColor(.black, for: .normal)
        done.titleLabel?.font = Theme.body(18, .semibold)
        done.translatesAutoresizingMaskIntoConstraints = false
        done.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        headerBar.addSubview(headerTitle)
        headerBar.addSubview(done)

        categoriesTable.translatesAutoresizingMaskIntoConstraints = false
        categoriesTable.dataSource = self
        categoriesTable.delegate = self
        categoriesTable.backgroundColor = .clear
        categoriesTable.separatorColor = UIColor(white: 1, alpha: 0.08)
        categoriesTable.rowHeight = UITableView.automaticDimension
        categoriesTable.estimatedRowHeight = 30
        categoriesTable.contentInsetAdjustmentBehavior = .never
        categoriesTable.alwaysBounceVertical = false
        categoryObservation = categoriesTable.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            self?.view.setNeedsLayout()
        }

        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.font = Theme.body(14, .regular)
        versionLabel.textColor = Theme.tertiaryText
        versionLabel.numberOfLines = 0
        versionLabel.text = AppLanguage.choose("GTA-V") + " \(Theme.appVersion)"

        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = UIColor(white: 0, alpha: 0.35)
        panel.clipsToBounds = true

        optionHelp.translatesAutoresizingMaskIntoConstraints = false
        optionHelp.font = Theme.body(16, .regular)
        optionHelp.textColor = .white
        optionHelp.numberOfLines = 3
        optionHelp.backgroundColor = UIColor(white: 0, alpha: 0.62)
        [headerBar, categoriesTable, versionLabel, panel, optionHelp].forEach(view.addSubview)
        let safe = view.safeAreaLayoutGuide
        let menu = UILayoutGuide()
        view.addLayoutGuide(menu)
        let menuWidth = menu.widthAnchor.constraint(equalTo: safe.widthAnchor, multiplier: 0.74)
        menuWidth.priority = .defaultHigh
        menuTop = menu.topAnchor.constraint(equalTo: safe.topAnchor)
        menuHeight = menu.heightAnchor.constraint(equalToConstant: 500)
        panelHeight = panel.heightAnchor.constraint(equalToConstant: 400)
        categoryHeight = categoriesTable.heightAnchor.constraint(equalToConstant: 350)
        NSLayoutConstraint.activate([
            menuTop, menuHeight, panelHeight, categoryHeight,
            menu.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            menuWidth,
            menu.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, constant: -32),
            menu.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            headerBar.topAnchor.constraint(equalTo: menu.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: menu.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: menu.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 38),
            headerTitle.centerXAnchor.constraint(equalTo: headerBar.centerXAnchor),
            headerTitle.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -10),
            done.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            categoriesTable.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 12),
            categoriesTable.leadingAnchor.constraint(equalTo: menu.leadingAnchor),
            categoriesTable.widthAnchor.constraint(equalTo: menu.widthAnchor, multiplier: 0.333),
            categoriesTable.bottomAnchor.constraint(lessThanOrEqualTo: menu.bottomAnchor),
            versionLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            versionLabel.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -20),
            versionLabel.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -16),
            panel.topAnchor.constraint(equalTo: categoriesTable.topAnchor),
            panel.leadingAnchor.constraint(equalTo: categoriesTable.trailingAnchor, constant: 2),
            panel.trailingAnchor.constraint(equalTo: menu.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: optionHelp.topAnchor, constant: -2),
            optionHelp.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            optionHelp.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            optionHelp.bottomAnchor.constraint(lessThanOrEqualTo: menu.bottomAnchor),
            optionHelp.heightAnchor.constraint(equalToConstant: 88),
        ])
        let accentLine = UIView()
        accentLine.backgroundColor = UIColor(red: 0.35, green: 0.72, blue: 0.80, alpha: 1)
        accentLine.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(accentLine)
        NSLayoutConstraint.activate([
            accentLine.topAnchor.constraint(equalTo: headerBar.topAnchor),
            accentLine.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            accentLine.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            accentLine.heightAnchor.constraint(equalToConstant: 3),
        ])

        select(0)

        // Automation: open the mod menu, or --settings-section <name> opens that category.
        if openModMenuOnAppear, let index = list.firstIndex(where: { $0.sections.contains(.cheats) }) {
            select(index)
            focus = .options
            return
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "--settings-section"), i + 1 < arguments.count {
            if arguments[i + 1] == "selfradio" {
                if let index = list.firstIndex(where: { $0.icon == "radio" }) {
                    select(index)
                    DispatchQueue.main.async { self.open(self.list[index]) }
                }
            } else {
                let wanted: SettingsViewController.Section? = ["files": .files, "graphics": .graphics, "resolution": .graphics, "device": .device, "controls": .controls, "cheats": .cheats, "spawn": .cheats][arguments[i + 1]]
                if let wanted, let index = list.firstIndex(where: { $0.sections.contains(wanted) }) { select(index) }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard menuHeight != nil, panelHeight != nil else { return }
        menuTop.constant = view.safeAreaLayoutGuide.layoutFrame.height * 0.11
        let available = max(120, view.safeAreaLayoutGuide.layoutFrame.height * 0.78)
        let chrome: CGFloat = 38 + 12 + 90
        let table = (current as? UITableViewController)?.tableView
        let content = table?.contentSize.height ?? 160
        let right = min(max(44, ceil(content)), max(44, available - chrome))
        if abs(panelHeight.constant - right) > 1 { panelHeight.constant = right }
        // Measure from the category model: an initially empty table must not collapse its own viewport.
        let textWidth = max(100, categoriesTable.bounds.width - 32)
        let categoryContent = list.reduce(CGFloat.zero) { height, category in
            let bounds = (category.title as NSString).boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: Theme.body(20)], context: nil)
            return height + max(52, ceil(bounds.height) + 24)
        }
        let categories = min(categoryContent, max(44, available - 50))
        if abs(categoryHeight.constant - categories) > 1 { categoryHeight.constant = categories }
        let left = categories + 50
        let total = min(available, max(left, right + chrome))
        if abs(menuHeight.constant - total) > 1 { menuHeight.constant = total }
        table?.isScrollEnabled = content > right + 1
    }

    private func updateHeaderTitle() {
        headerTitle.attributedText = NSAttributedString(string: AppLanguage.choose(openModMenuOnAppear ? "Mod menu" : "Settings").uppercased(), attributes: [
            .font: Theme.body(18, .regular), .foregroundColor: UIColor.black, .kern: 0.3,
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        refreshLanguageIfNeeded()
        categoriesTable.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Pushed pages (Mods, Self Radio, Spawn vehicle) bring their own back button.
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: Pages

    func refreshLanguageIfNeeded() {
        guard AppLanguage.current != pagesLanguage else { return }
        pagesLanguage = AppLanguage.current
        pages = pages.filter { $0.value === current }
        list = makeCategories()
        title = AppLanguage.choose("Settings")
        updateHeaderTitle()
        done.setTitle(AppLanguage.choose("Done"), for: .normal)
        versionLabel.text = AppLanguage.choose("GTA-V") + " \(Theme.appVersion)"
        categoriesTable.reloadData()
    }

    private func select(_ index: Int) {
        refreshLanguageIfNeeded()
        guard list.indices.contains(index) else { return }
        optionHelp.text = list[index].summary()
        selectedIndex = index
        let page = pages[index] ?? makePage(for: index)
        pages[index] = page
        show(page)
        navigable?.setKeyboardFocus(focus == .options)
        categoriesTable.reloadData()
        categoriesTable.scrollToRow(at: IndexPath(row: index, section: 0), at: .none, animated: false)
    }

    private func makePage(for index: Int) -> UIViewController {
        let category = list[index]
        if let factory = category.page {
            let page = factory()
            (page as? SettingsTableViewController)?.optionDescriptionChanged = { [weak self] in self?.optionHelp.text = $0 }
            return page
        }
        let page = SettingsViewController(engineRunning: engineRunning, runningMode: runningMode, title: category.title,
                                          sections: category.sections, embedded: true)
        page.modMenuCategory = category.modCategory
        // Forwarded late so callbacks set after presenting still work.
        page.optionDescriptionChanged = { [weak self] in self?.optionHelp.text = $0 }
        page.resolutionChanged = { [weak self] in self?.resolutionChanged?() }
        page.controlsChanged = { [weak self] in self?.controlsChanged?() }
        page.editLayout = { [weak self] in self?.editLayout?() }
        page.targetingChanged = { [weak self] in self?.targetingChanged?() }
        page.gameModeChanged = { [weak self] in self?.gameModeChanged?() }
        page.cheatSelected = { [weak self] in self?.cheatSelected?($0) }
        page.moneyEntered = { [weak self] in self?.moneyEntered?($0) }
        page.nativeCheatSelected = { [weak self] in self?.nativeCheatSelected?($0) }
        page.vehicleSelected = { [weak self] in self?.vehicleSelected?($0, $1) }
        return page
    }

    private func show(_ page: UIViewController) {
        guard page !== current else { return }
        if let old = current {
            (old as? SettingsKeyboardNavigable)?.setKeyboardFocus(false)
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        addChild(page)
        page.view.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(page.view)
        NSLayoutConstraint.activate([
            page.view.topAnchor.constraint(equalTo: panel.topAnchor),
            page.view.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            page.view.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            page.view.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
        ])
        page.didMove(toParent: self)
        current = page
        contentObservation = nil
        if let table = (page as? UITableViewController)?.tableView {
            contentObservation = table.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                self?.view.setNeedsLayout()
            }
        }
        view.setNeedsLayout()
    }

    private func open(_ category: Category) {
        guard let page = category.page else { return }
        navigationController?.pushViewController(page(), animated: true)
    }

    private func updateFocusUI() {
        refreshLanguageIfNeeded()
        navigable?.setKeyboardFocus(focus == .options)
        categoriesTable.reloadData()
    }

    // MARK: Categories column

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { list.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let isSelected = indexPath.row == selectedIndex
        let active = isSelected && focus == .categories
        let dimmed = isSelected && focus == .options
        cell.selectionStyle = .none
        cell.backgroundColor = active ? Self.cursorFill : dimmed ? UIColor(white: 0.38, alpha: 0.9) : Self.rowFill
        var content = cell.defaultContentConfiguration()
        content.text = list[indexPath.row].title
        content.textProperties.numberOfLines = 0
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        content.textProperties.font = Theme.body(20, .regular)
        content.textProperties.color = active ? .black : .white
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        select(indexPath.row)
        focus = .categories
    }

    // MARK: Keyboard

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        func key(_ input: String, _ action: Selector) -> UIKeyCommand {
            let command = UIKeyCommand(input: input, modifierFlags: [], action: action)
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
        return [
            key(UIKeyCommand.inputUpArrow, #selector(keyUp)),
            key(UIKeyCommand.inputDownArrow, #selector(keyDown)),
            key(UIKeyCommand.inputLeftArrow, #selector(keyLeft)),
            key(UIKeyCommand.inputRightArrow, #selector(keyRight)),
            key("\r", #selector(keyEnter)),
            key(" ", #selector(keyEnter)),
            key(UIKeyCommand.inputEscape, #selector(closeSettings)),
            key("\u{8}", #selector(keyBack)),
        ]
    }

    @objc private func keyUp() { move(-1) }
    @objc private func keyDown() { move(1) }

    private func move(_ delta: Int) {
        switch focus {
        case .categories: select((selectedIndex + delta + list.count) % list.count)
        case .options: navigable?.moveCursor(delta)
        }
    }

    @objc private func keyRight() {
        switch focus {
        case .categories: enterOptions()
        case .options: _ = navigable?.adjustCursor(1)
        }
    }

    @objc private func keyLeft() {
        guard focus == .options else { return }
        // A row with nothing to change: Left steps back out to the categories.
        if navigable?.adjustCursor(-1) != true { focus = .categories }
    }

    @objc private func keyEnter() {
        switch focus {
        case .categories: enterOptions()
        case .options: navigable?.activateCursor()
        }
    }

    @objc private func closeSettings() { dismiss(animated: true) }

    @objc private func keyBack() {
        if focus == .options { focus = .categories } else { dismiss(animated: true) }
    }

    private func enterOptions() {
        guard navigable != nil else { return }
        focus = .options
    }
}

/// Keeps Escape available on pushed settings pages, too.
final class SettingsNavigationController: UINavigationController {
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        if viewController is SettingsHomeViewController || viewController is SettingsDetailViewController {
            super.pushViewController(viewController, animated: animated)
        } else {
            super.pushViewController(SettingsDetailViewController(content: viewController), animated: animated)
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closeSettings))
        escape.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [escape]
    }

    @objc private func closeSettings() { dismiss(animated: true) }
}

/// The same artwork, title strip and content-sized panel for deeper settings pages.
private final class SettingsDetailViewController: UIViewController {
    private let content: UIViewController
    private let menu = UIView()
    private let bar = UINavigationBar()
    private let panel = UIView()
    private var top: NSLayoutConstraint!
    private var height: NSLayoutConstraint!
    private var observation: NSKeyValueObservation?
    private var searchHeight: CGFloat = 0

    init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let art = Theme.backdrop(image: "SettingsBackground", darken: 0.18)
        art.frame = view.bounds
        art.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(art)
        menu.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(menu)
        addChild(content)
        content.loadViewIfNeeded()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = SettingsHomeViewController.cursorFill
        appearance.titleTextAttributes = [.font: Theme.body(18), .foregroundColor: UIColor.black]
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.tintColor = .black
        let item = UINavigationItem(title: (content.title ?? AppLanguage.choose("Settings")).uppercased())
        item.leftBarButtonItem = UIBarButtonItem(title: AppLanguage.choose("Back"), primaryAction: UIAction { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        item.rightBarButtonItems = content.navigationItem.rightBarButtonItems
        bar.setItems([item], animated: false)
        bar.translatesAutoresizingMaskIntoConstraints = false
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = UIColor(white: 0, alpha: 0.62)
        panel.clipsToBounds = true
        menu.addSubview(bar)
        menu.addSubview(panel)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(content.view)
        var contentTop = panel.topAnchor
        if let search = content.navigationItem.searchController {
            let searchBar = search.searchBar
            searchBar.translatesAutoresizingMaskIntoConstraints = false
            searchBar.searchBarStyle = .minimal
            searchBar.tintColor = Theme.text
            panel.addSubview(searchBar)
            NSLayoutConstraint.activate([
                searchBar.topAnchor.constraint(equalTo: panel.topAnchor),
                searchBar.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
                searchBar.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
                searchBar.heightAnchor.constraint(equalToConstant: 56),
            ])
            searchHeight = 56
            contentTop = searchBar.bottomAnchor
        }
        height = menu.heightAnchor.constraint(equalToConstant: 400)
        let safe = view.safeAreaLayoutGuide
        top = menu.topAnchor.constraint(equalTo: safe.topAnchor)
        NSLayoutConstraint.activate([
            top,
            menu.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            menu.widthAnchor.constraint(equalTo: safe.widthAnchor, multiplier: 0.74),
            height,
            bar.topAnchor.constraint(equalTo: menu.topAnchor),
            bar.leadingAnchor.constraint(equalTo: menu.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: menu.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 44),
            panel.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 12),
            panel.leadingAnchor.constraint(equalTo: menu.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: menu.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: menu.bottomAnchor),
            content.view.topAnchor.constraint(equalTo: contentTop),
            content.view.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            content.view.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])
        let version = UILabel()
        version.text = AppLanguage.choose("GTA-V") + " \(Theme.appVersion)"
        version.font = Theme.body(14)
        version.textColor = Theme.tertiaryText
        version.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(version)
        NSLayoutConstraint.activate([
            version.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            version.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -16),
        ])
        content.didMove(toParent: self)
        if let table = content as? UITableViewController {
            observation = table.tableView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in self?.view.setNeedsLayout() }
        } else if let collection = content as? UICollectionViewController {
            collection.collectionView.backgroundColor = .clear
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        top.constant = view.safeAreaLayoutGuide.layoutFrame.height * 0.11
        let maximum = max(100, view.safeAreaLayoutGuide.layoutFrame.height * 0.78)
        let table = (content as? UITableViewController)?.tableView
        let wanted = (table?.contentSize.height ?? maximum) + 56 + searchHeight
        let fitted = min(maximum, max(100, ceil(wanted)))
        if abs(height.constant - fitted) > 1 { height.constant = fitted }
        table?.isScrollEnabled = wanted > maximum + 1
    }
    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(up)),
         UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(down)),
         UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(left)),
         UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(right)),
         UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(activate)),
         UIKeyCommand(input: "\u{8}", modifierFlags: [], action: #selector(back))]
    }
    private var keyboardPage: SettingsKeyboardNavigable? { content as? SettingsKeyboardNavigable }
    private var hasCursor = false
    private func focusPage() {
        if !hasCursor { keyboardPage?.setKeyboardFocus(true); hasCursor = true }
    }
    @objc private func up() { focusPage(); keyboardPage?.moveCursor(-1) }
    @objc private func down() { focusPage(); keyboardPage?.moveCursor(1) }
    @objc private func left() { focusPage(); _ = keyboardPage?.adjustCursor(-1) }
    @objc private func right() { focusPage(); _ = keyboardPage?.adjustCursor(1) }
    @objc private func activate() { focusPage(); keyboardPage?.activateCursor() }
    @objc private func back() { navigationController?.popViewController(animated: true) }
}

/// Readable padding around the contextual help below every settings list.
private final class SettingsInsetLabel: UILabel {
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)))
    }
}
