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
        defaultStyle.width = 1
        defaultStyle.addHints([ILSparkLineFalloffInterval: 30.0])

        #if os(macOS)
        let viewController = SparkyController(nibName: "Sparky", bundle: .main)
        #else
        let viewController = ILStoryboard(name: "Sparky", bundle: nil).instantiateInitialViewController() as! SparkyController
        self.window = window
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        #endif
        self.viewController = viewController
        viewController.initView()

        #if os(macOS)
        // most of the screen, it can be resized from small to full screen
        if let window = viewController.view.window, let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            window.contentMinSize = NSSize(width: 320, height: 240)
            window.setFrame(visible.insetBy(dx: (visible.width * 0.1).rounded(), dy: (visible.height * 0.1).rounded()), display: true)
            addColorWell(to: window)
        }
        #endif

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        start(in: nil)
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
