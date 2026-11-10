import UIKit

/// The start screen, GTA V menu style: full art, one big dark info panel (title, mode text, game files, Play)
/// and a flat bar along the bottom with text items (left: Controls layout, Settings; right: the modes).
/// The view controller keeps the logic; this view only lays things out and reports taps.
final class HomeView: UIView {
    enum FilesState { case ready, attention, problem, busy }

    #if targetEnvironment(macCatalyst)
    /// How much the start screen is scaled up in a Mac window of this height.
    static func macScale(forHeight height: CGFloat) -> CGFloat { min(max(height / 1000, 1), 2) }
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = (window?.screen.scale ?? 2) * transform.a
        func sharpen(_ view: UIView) { if view.contentScaleFactor != scale { view.contentScaleFactor = scale }; view.subviews.forEach(sharpen) }
        sharpen(self)
    }
    #endif

    let playButton = Theme.primaryButton(AppLanguage.choose("Play"), symbol: "play.fill")
    let settingsButton = Theme.barButton(AppLanguage.choose("Settings"), symbol: "gearshape.fill")
    let layoutButton = Theme.barButton(AppLanguage.choose("Controls layout"), symbol: "hand.tap.fill")
    let preloadLabel = UILabel()
    let controllerLabel = UILabel()
    /// Taps on the game files card.
    var onFiles: (() -> Void)?
    /// A mode tab was tapped (index into GameMode.allCases).
    var onMode: ((Int) -> Void)?

    private let filesCard = UIControl()
    private let filesIcon = UIImageView()
    private let filesTitle = UILabel()
    private let filesDetail = UILabel()
    private let filesSpinner = UIActivityIndicatorView(style: .medium)
    private var modeCards: [ModeCard] = []
    private let modeDetail = UILabel()
    private let brandTitle = UILabel()
    private let brandSubtitle = UILabel()
    private let mapTitle = UILabel()
    /// Sandbox only: which map (it takes the place of the mode description).
    private let mapRow = UIStackView()
    private var mapChips: [UIButton] = []
    var onMap: ((Int) -> Void)?

    private let scroll = UIScrollView()
    private let secondary = UIStackView()

    init(modes: [(title: String, symbol: String)]) {
        super.init(frame: .zero)
        let backdrop = Theme.backdrop(image: "StartBackground")
        pin(backdrop, to: self)

        // Panel header: icon, big title, small subtitle.
        let icon = UIImageView(image: UIImage(named: "HomeIcon"))
        icon.contentMode = .scaleAspectFit
        icon.layer.cornerRadius = 10
        icon.layer.cornerCurve = .continuous
        icon.clipsToBounds = true
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let title = brandTitle
        title.text = AppLanguage.choose("GTA-V")
        title.font = Theme.display(36, .semibold)
        title.textColor = Theme.text
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.7
        let subtitle = brandSubtitle
        subtitle.text = AppLanguage.choose("Fan project · plays your own game files") + " · \(Theme.appVersion)"
        subtitle.font = Theme.body(14, .medium)
        subtitle.textColor = Theme.secondaryText
        subtitle.numberOfLines = 2
        let titles = UIStackView(arrangedSubviews: [title, subtitle])
        titles.axis = .vertical
        titles.spacing = 2
        let header = UIStackView(arrangedSubviews: [icon, titles])
        header.spacing = 14
        header.alignment = .center

        let divider = UIView()
        divider.backgroundColor = UIColor(white: 1, alpha: 0.2)
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        buildFilesCard()

        // Modes become the right side of the bottom bar.
        for (index, mode) in modes.enumerated() {
            let card = ModeCard(title: mode.title, symbol: mode.symbol)
            card.addAction(UIAction { [weak self] _ in self?.onMode?(index) }, for: .touchUpInside)
            modeCards.append(card)
        }
        let modeStack = UIStackView(arrangedSubviews: modeCards)
        modeStack.spacing = 4
        modeStack.alignment = .fill
        modeStack.translatesAutoresizingMaskIntoConstraints = false
        modeStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        // The mode description is the panel's body text.
        modeDetail.font = Theme.body(15)
        modeDetail.textColor = UIColor(white: 1, alpha: 0.85)
        modeDetail.numberOfLines = 0

        settingsButton.accessibilityLabel = AppLanguage.choose("Settings")
        layoutButton.accessibilityLabel = AppLanguage.choose("Controls layout")
        #if targetEnvironment(macCatalyst)
        secondary.addArrangedSubviews([settingsButton])   // no touch controls to lay out on a Mac
        #else
        secondary.addArrangedSubviews([layoutButton, settingsButton])
        #endif
        secondary.spacing = 2
        secondary.alignment = .fill
        secondary.translatesAutoresizingMaskIntoConstraints = false
        for label in [preloadLabel, controllerLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textColor = Theme.tertiaryText
            label.numberOfLines = 0
        }
        preloadLabel.isHidden = true

        let mapLabel = mapTitle
        mapLabel.text = AppLanguage.choose("Map")
        mapLabel.font = Theme.body(13, .semibold)
        mapLabel.textColor = Theme.secondaryText
        mapRow.addArrangedSubview(mapLabel)
        for (index, title) in GameSettings.sandboxMapTitles.enumerated() {
            var config = UIButton.Configuration.gray()
            config.title = title
            config.cornerStyle = .fixed
            config.background.cornerRadius = 2
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in var a = a; a.font = Theme.body(13, .semibold); return a }
            let chip = UIButton(configuration: config)
            chip.addAction(UIAction { [weak self] _ in self?.onMap?(index) }, for: .touchUpInside)
            mapChips.append(chip)
            mapRow.addArrangedSubview(chip)
        }
        mapRow.addArrangedSubview(UIView())
        mapRow.spacing = 8
        mapRow.alignment = .center
        mapRow.isHidden = true

        // The info panel: everything the player needs before Play.
        let column = UIStackView(arrangedSubviews: [header, divider, modeDetail, mapRow, filesCard, playButton, preloadLabel, controllerLabel])
        column.axis = .vertical
        column.spacing = 14
        column.alignment = .fill
        column.setCustomSpacing(18, after: header)
        column.setCustomSpacing(20, after: filesCard)
        column.translatesAutoresizingMaskIntoConstraints = false

        let card = UIView()
        card.backgroundColor = Theme.panelFill
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(card)

        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(wrapper)
        addSubview(scroll)


        // Bottom bar.
        let bar = UIView()
        bar.backgroundColor = Theme.night.withAlphaComponent(0.82)
        bar.translatesAutoresizingMaskIntoConstraints = false
        let hairline = UIView()
        hairline.backgroundColor = Theme.panelStroke
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        bar.addSubview(hairline)
        bar.addSubview(secondary)
        bar.addSubview(modeStack)

        let guide = safeAreaLayoutGuide
        let width = scroll.widthAnchor.constraint(equalTo: guide.widthAnchor, multiplier: 0.5)
        width.priority = .defaultHigh
        let centered = card.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        centered.priority = .defaultHigh
        NSLayoutConstraint.activate([
            // Bar
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.topAnchor.constraint(equalTo: secondary.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            hairline.topAnchor.constraint(equalTo: bar.topAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            secondary.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 14),
            secondary.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            secondary.heightAnchor.constraint(equalToConstant: 54),
            modeStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -14),
            modeStack.topAnchor.constraint(equalTo: secondary.topAnchor),
            modeStack.bottomAnchor.constraint(equalTo: secondary.bottomAnchor),
            // Long translations must not run into the mode tabs.
            secondary.trailingAnchor.constraint(lessThanOrEqualTo: modeStack.leadingAnchor, constant: -12),

            // Panel (scrolls when the screen is short, centred when there is room)
            scroll.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 28),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.topAnchor),
            width,
            scroll.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
            wrapper.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            wrapper.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            wrapper.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            wrapper.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            wrapper.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            wrapper.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
            card.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            card.topAnchor.constraint(greaterThanOrEqualTo: wrapper.topAnchor, constant: 12),
            card.bottomAnchor.constraint(lessThanOrEqualTo: wrapper.bottomAnchor, constant: -12),
            centered,
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            column.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -26),

        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Update language-specific titles in place without touching downloaded game files or layout.
    func refreshLanguage() {
        brandTitle.text = AppLanguage.choose("GTA-V")
        brandSubtitle.text = AppLanguage.choose("Fan project · plays your own game files") + " · \(Theme.appVersion)"
        mapTitle.text = AppLanguage.choose("Map")
        playButton.configuration?.title = AppLanguage.choose("Play")
        settingsButton.configuration?.title = AppLanguage.choose("Settings").uppercased()
        layoutButton.configuration?.title = AppLanguage.choose("Controls layout").uppercased()
        settingsButton.accessibilityLabel = AppLanguage.choose("Settings")
        layoutButton.accessibilityLabel = AppLanguage.choose("Controls layout")
        for (index, card) in modeCards.enumerated() {
            card.setTitle(GameMode.allCases[index].title)
        }
        for (i, chip) in mapChips.enumerated() {
            chip.configuration?.title = GameSettings.sandboxMapTitles[i]
        }
    }

    private func buildFilesCard() {
        let panel = Theme.flatPanel()
        panel.isUserInteractionEnabled = false
        pin(panel, to: filesCard)
        filesIcon.contentMode = .scaleAspectFit
        filesIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        filesIcon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        filesTitle.font = Theme.body(16, .semibold)
        filesTitle.textColor = Theme.text
        filesDetail.font = Theme.body(13)
        filesDetail.textColor = Theme.secondaryText
        filesDetail.numberOfLines = 2
        let texts = UIStackView(arrangedSubviews: [filesTitle, filesDetail])
        texts.axis = .vertical
        texts.spacing = 2
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)))
        chevron.tintColor = Theme.tertiaryText
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        filesSpinner.color = Theme.text
        let iconHolder = UIView()
        for view in [filesIcon, filesSpinner] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            iconHolder.addSubview(view)
            NSLayoutConstraint.activate([view.centerXAnchor.constraint(equalTo: iconHolder.centerXAnchor), view.centerYAnchor.constraint(equalTo: iconHolder.centerYAnchor)])
        }
        iconHolder.widthAnchor.constraint(equalToConstant: 30).isActive = true
        let row = UIStackView(arrangedSubviews: [iconHolder, texts, chevron])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        filesCard.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: filesCard.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: filesCard.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: filesCard.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: filesCard.bottomAnchor, constant: -12)
        ])
        filesCard.accessibilityTraits = .button
        filesCard.isAccessibilityElement = true
        filesCard.addAction(UIAction { [weak self] _ in self?.onFiles?() }, for: .touchUpInside)
        filesCard.addAction(UIAction { [weak self] _ in self?.filesCard.alpha = 0.7 }, for: [.touchDown, .touchDragEnter])
        filesCard.addAction(UIAction { [weak self] _ in self?.filesCard.alpha = 1 }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    /// Shows where the game files are and whether they're ready.
    func setFiles(_ state: FilesState, title: String, detail: String) {
        filesTitle.text = title
        filesDetail.text = detail
        filesDetail.isHidden = detail.isEmpty
        filesSpinner.isHidden = state != .busy
        filesIcon.isHidden = state == .busy
        if state == .busy { filesSpinner.startAnimating() } else { filesSpinner.stopAnimating() }
        let (symbol, color): (String, UIColor) = switch state {
        case .ready: ("checkmark.circle.fill", Theme.ok)
        case .attention: ("folder.badge.plus", Theme.warning)
        case .problem: ("exclamationmark.triangle.fill", Theme.problem)
        case .busy: ("", Theme.text)
        }
        filesIcon.image = symbol.isEmpty ? nil : UIImage(systemName: symbol)
        filesIcon.tintColor = color
        filesCard.accessibilityLabel = AppLanguage.interpolate(AppLanguage.choose("Game files: {arg0}. {arg1}"), [title, detail])
    }

    /// Shows the map choice (Sandbox) instead of the mode description, with `index` selected.
    func setMap(_ index: Int, visible: Bool, enabled: Bool, testMapAvailable: Bool = true) {
        mapRow.isHidden = !visible
        modeDetail.isHidden = visible
        for (i, chip) in mapChips.enumerated() {
            let selected = i == index
            // The GTA VI test map greys out when the game files don't include it.
            chip.isEnabled = enabled && (i != 1 || testMapAvailable)
            chip.configuration?.baseForegroundColor = selected ? Theme.accent : Theme.text
            chip.configuration?.background.backgroundColor = selected ? Theme.accent.withAlphaComponent(0.18) : UIColor(white: 1, alpha: 0.1)
            chip.configuration?.background.strokeColor = selected ? Theme.accent : .clear
            chip.configuration?.background.strokeWidth = selected ? 1.5 : 0
            chip.accessibilityTraits = selected ? [.button, .selected] : .button
            chip.accessibilityLabel = AppLanguage.choose("Sandbox map: ") + GameSettings.sandboxMapTitles[i]
        }
    }

    /// Marks the chosen mode (nil: none yet) and shows its description.
    func setMode(_ index: Int?, detail: String, enabled: Bool) {
        for (i, card) in modeCards.enumerated() { card.isSelected = i == index; card.isEnabled = enabled }
        modeDetail.text = detail
    }

    private func pin(_ view: UIView, to parent: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor), view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            view.topAnchor.constraint(equalTo: parent.topAnchor), view.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }
}

/// One of the Story mode / Sandbox tabs in the bottom bar: uppercase text, white and underlined when chosen.
private final class ModeCard: UIControl {
    private let icon = UIImageView()
    private let label = UILabel()
    private let underline = UIView()

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        label.text = title.uppercased()
        label.font = Theme.body(14, .semibold)
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 8
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        underline.backgroundColor = Theme.accent
        underline.isUserInteractionEnabled = false
        underline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(underline)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            underline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            underline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            underline.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            underline.heightAnchor.constraint(equalToConstant: 3)
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
        update()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setTitle(_ title: String) {
        label.text = title.uppercased()
        accessibilityLabel = title
    }

    override var isSelected: Bool { didSet { update() } }
    override var isEnabled: Bool { didSet { update() } }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.75 : 1 } }

    private func update() {
        let color = isSelected ? Theme.text : Theme.secondaryText
        icon.tintColor = color
        label.textColor = isEnabled ? color : Theme.tertiaryText
        underline.isHidden = !isSelected
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

private extension UIStackView {
    func addArrangedSubviews(_ views: [UIView]) { views.forEach(addArrangedSubview) }
}
