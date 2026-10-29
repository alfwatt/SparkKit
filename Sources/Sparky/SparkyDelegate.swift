/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
import Foundation
import KitBridge
import SparkKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// sets the default style, shows the spark views and updates them ten times a second
@main
@objc(SparkyDelegate)
class SparkyDelegate: ILResponder, ILApplicationDelegate {
    var window: ILWindow?
    private var viewController: SparkyController?
    private var updateTimer: Timer?

    /// set the default style, show the spark views, in the scene's window on iOS and tvOS, and update them
    func start(in window: ILWindow?) {
        let defaultStyle = ILSparkStyle.defaultStyle
        defaultStyle.bordered = true
        defaultStyle.filled = true
        defaultStyle.width = 2
        defaultStyle.addHints([ILSparkLineFalloffInterval: 30.0])

        let viewController = SparkyController()
        #if os(macOS)
        // most of the screen, it can be resized from small to full screen
        let window = NSWindow(contentViewController: viewController)
        window.title = "Sparky"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 320, height: 240)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrame(visible.insetBy(dx: (visible.width * 0.1).rounded(), dy: (visible.height * 0.1).rounded()), display: false)
        }
        addColorWell(to: window)
        window.makeKeyAndOrderFront(nil)
        #else
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        #endif
        self.window = window
        self.viewController = viewController
        viewController.initView()

        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.viewController?.updateView()
        }
        updateTimer?.fire()
    }

    #if os(macOS)
    /// a color well in the title bar, picking a color restyles the views from it
    private func addColorWell(to window: NSWindow) {
        let colorWell = NSColorWell(frame: NSRect(x: 8, y: 3, width: 44, height: 22))
        if #available(macOS 13, *) {
            colorWell.colorWellStyle = .minimal
        }
        colorWell.color = ILSparkStyle.defaultStyle.fill ?? .gray
        colorWell.toolTip = "Style the views from a color"
        colorWell.target = self
        colorWell.action = #selector(pickColor(_:))
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 60, height: 28))
        accessory.view.addSubview(colorWell)
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)
    }

    @objc private func pickColor(_ sender: NSColorWell) {
        viewController?.apply(sender.color)
    }

    /// the app and window menus
    private static func mainMenu() -> NSMenu {
        let appName = ProcessInfo.processInfo.processName
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let mainMenu = NSMenu()
        for menu in [appMenu, windowMenu] {
            mainMenu.addItem(withTitle: menu.title, action: nil, keyEquivalent: "").submenu = menu
        }
        NSApplication.shared.windowsMenu = windowMenu
        return mainMenu
    }

    /// there's no main nib, the app gets its delegate and menus here
    static func main() {
        let application = NSApplication.shared
        let delegate = SparkyDelegate()
        application.delegate = delegate
        application.mainMenu = mainMenu()
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        start(in: nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
    #else
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true // the scene delegate starts when it has a window
    }
    #endif
}

#if !os(macOS)
/// makes the window for the scene and has the app delegate show the spark views in it, iOS requires the scene lifecycle
@objc(SparkySceneDelegate)
class SparkySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        (UIApplication.shared.delegate as? SparkyDelegate)?.start(in: window)
    }
}
#endif
