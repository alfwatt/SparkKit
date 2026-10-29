/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
import Foundation
import KitBridge
import SparkKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private let speed = 0.1

/// shows each of the spark views with sine waves for data
@objc(SparkyController)
class SparkyController: ILViewController, ILSparkMeterDataSource, ILSparkStackDataSource, ILSparkLineDataSource {
    private var gridData = ILGridData.floatGrid(withRows: 0, columns: 100)
    private let bucketData = ILBucketData()
    private var dataTimer: Timer?
    private var dataDates: [Date] = []
    private var sparkViewsAdopted = false
    #if os(macOS)
    private var frameObserver: NSObjectProtocol?
    #endif

    /// the seconds the spark line shows at any width
    private let secondsShown: CGFloat = 300

    /// the grid keeps this many rows, newest at the bottom
    private let gridRows = 100

    // MARK: - IBOutlets

    @IBOutlet var sparkBars: ILSparkBars!
    @IBOutlet var sparkLine: ILSparkLine!
    @IBOutlet var sparkGrid: ILSparkGrid!

    // MARK: - Meters

    @IBOutlet var sparkText: ILSparkMeter!
    @IBOutlet var sparkVert: ILSparkMeter!
    @IBOutlet var sparkHorz: ILSparkMeter!
    @IBOutlet var sparkSquare: ILSparkMeter!
    @IBOutlet var sparkCircle: ILSparkMeter!
    @IBOutlet var sparkRing: ILSparkMeter!
    @IBOutlet var sparkPie: ILSparkMeter!
    @IBOutlet var sparkDial: ILSparkMeter!

    // MARK: - Stacks

    @IBOutlet var stackText: ILSparkStack!
    @IBOutlet var stackVert: ILSparkStack!
    @IBOutlet var stackHorz: ILSparkStack!
    @IBOutlet var stackSquare: ILSparkStack!
    @IBOutlet var stackCircle: ILSparkStack!
    @IBOutlet var stackRing: ILSparkStack!
    @IBOutlet var stackPie: ILSparkStack!
    @IBOutlet var stackDial: ILSparkStack!

    private var meters: [ILSparkMeter] { [sparkText, sparkVert, sparkHorz, sparkSquare, sparkCircle, sparkRing, sparkPie, sparkDial] }
    private var stacks: [ILSparkStack] { [stackText, stackVert, stackHorz, stackSquare, stackCircle, stackRing, stackPie, stackDial] }

    // MARK: -

    /// load the view, style each meter and stack in the order of the meter styles and start the data
    func initView() {
        _ = view

        #if os(tvOS)
        let defaultStyle = ILSparkStyle.defaultStyle
        defaultStyle.width = 0
        defaultStyle.font = ILFont(name: "Helvetica", size: 48)
        defaultStyle.background = .lightGray
        defaultStyle.border = .clear
        defaultStyle.stroke = .clear
        #endif

        let meterStyles: [ILSparkMeterStyle] = [.textStyle, .verticalStyle, .horizontalStyle, .squareStyle, .circleStyle, .ringStyle, .pieStyle, .dialStyle]
        let stackColors: [ILColor] = [.black, .darkGray, .gray, .lightGray]
        for (meter, meterStyle) in zip(meters, meterStyles) {
            meter.style = ILSparkStyle.defaultStyle.copy(withHints: [ILSparkMeterStyleHint: meterStyle.rawValue])
            meter.dataSource = self
        }
        for (stack, meterStyle) in zip(stacks, meterStyles) {
            stack.style = ILSparkStyle.defaultStyle.copy(withHints: [ILSparkMeterStyleHint: meterStyle.rawValue, ILSparkStackColorsHint: stackColors])
            stack.stackDataSource = self
        }

        sparkLine.dataSource = self

        sparkGrid.grid = gridData
        sparkGrid.xAxisLabels = ["1", "2", "3", "4", "5"]
        sparkGrid.yAxisLabels = ["y"]

        sparkBars.dataSource = bucketData

        adoptSparkViews()

        dataTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.appendData()
        }
        dataTimer?.fire()
    }

    func updateView() {
        sparkLine.updateView()
        sparkBars.updateView()
        meters.forEach { $0.updateView() }
        stacks.forEach { $0.updateView() }
    }

    // MARK: - Layout

    /// take the spark views out of the nib's containers and constraints, they're laid out in code to fill the view at any size
    private func adoptSparkViews() {
        let sparkViews: [ILSparkView] = meters + stacks + [sparkLine, sparkBars, sparkGrid]
        sparkViews.forEach { $0.removeFromSuperview() }
        view.subviews.forEach { $0.removeFromSuperview() } // the containers, with their constraints
        for sparkView in sparkViews {
            sparkView.removeConstraints(sparkView.constraints) // their fixed sizes
            sparkView.translatesAutoresizingMaskIntoConstraints = true
            view.addSubview(sparkView)
        }
        sparkViewsAdopted = true
        #if os(macOS)
        view.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
            self?.layoutSparkViews()
        }
        #endif
        layoutSparkViews()
    }

    /// a row of meters and a row of stacks in square cells, then the line and bars side by side over the grid,
    /// with margins, fonts and ring widths in proportion to the cells, so every size shows the same picture
    private func layoutSparkViews() {
        guard sparkViewsAdopted else { return }
        #if os(macOS)
        let area = view.bounds
        #else
        let area = view.bounds.inset(by: view.safeAreaInsets)
        #endif
        guard area.width > 0, area.height > 0 else { return }

        let margin = max(4, (min(area.width, area.height) * 0.02).rounded())
        let cellWidth = (area.width - (margin * 9)) / 8
        let cell = max(1, min(cellWidth, (area.height - (margin * 5)) * 0.2).rounded(.down))
        let rest = max(2, area.height - (margin * 5) - (cell * 2))
        let halfWidth = (area.width - (margin * 3)) / 2

        /// place the view in the area, y from the top
        func place(_ sparkView: ILSparkView, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
            #if os(macOS)
            let originY = view.isFlipped ? area.minY + y : area.maxY - y - height
            #else
            let originY = area.minY + y
            #endif
            sparkView.frame = CGRect(x: area.minX + x, y: originY, width: width, height: height).integral
        }

        // the text and widths in proportion to a 70 point cell, the size the defaults suit
        let scale = cell / 70
        let font = ILFont(name: "Helvetica", size: max(6, (12 * scale).rounded()))
        ILSparkStyle.defaultStyle.font = font
        for (index, (meter, stack)) in zip(meters, stacks).enumerated() {
            for sparkView in [meter, stack] as [ILSparkView] {
                sparkView.style.font = font
                sparkView.style.addHints([ILSparkMeterRingWidthHint: 8 * scale, ILSparkMeterDialWidthHint: 4 * scale])
            }
            let x = margin + (CGFloat(index) * (cellWidth + margin)) + ((cellWidth - cell) / 2)
            place(meter, x: x, y: margin, width: cell, height: cell)
            place(stack, x: x, y: (margin * 2) + cell, width: cell, height: cell)
        }

        let chartsTop = (margin * 3) + (cell * 2)
        let chartsHeight = (rest / 2).rounded(.down)
        sparkLine.style = ILSparkStyle.defaultStyle.copy(withHints: [ILSparkLineScaleFactor: secondsShown / max(halfWidth, 1)])
        place(sparkLine, x: margin, y: chartsTop, width: halfWidth, height: chartsHeight)
        place(sparkBars, x: (margin * 2) + halfWidth, y: chartsTop, width: halfWidth, height: chartsHeight)
        place(sparkGrid, x: margin, y: chartsTop + chartsHeight + margin, width: area.width - (margin * 2), height: rest - chartsHeight)

        updateView()
        sparkGrid.updateView()
    }

    #if !os(macOS)
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutSparkViews()
    }
    #endif

    #if os(macOS)
    // MARK: - Color

    /// restyle every view from the palette of the color
    func apply(_ color: NSColor) {
        let palette = SparkyPalette(color)
        for style in [ILSparkStyle.defaultStyle] + meters.map(\.style) + stacks.map(\.style) {
            palette.apply(to: style)
        }
        let gridStyle = ILSparkStyle.defaultStyle.copy() as! ILSparkStyle
        gridStyle.background = .clear // each row's background covers the fill the values shade
        sparkGrid.style = gridStyle
        layoutSparkViews() // copies the default style to the line and redraws everything
    }
    #endif

    // MARK: - Data

    /// a row of sine waves for the grid and bars, each column faster than the last
    private func appendData() {
        dataDates.append(Date())

        let interval = Date.timeIntervalSinceReferenceDate
        let columns = gridData.columns
        let row = (0..<columns).map { index in
            CGFloat(abs(sin(interval * Double(index + 1) / Double(columns))))
        }
        bucketData.buckets = row.map { NSNumber(value: Double($0)) }
        if gridData.rows >= gridRows { // drop the oldest row
            gridData.trim(toRangeOfRows: NSRange(location: 1, length: gridData.rows - 1))
        }
        gridData.appendData(row.withUnsafeBytes { Data($0) })
        sparkGrid.updateView()
    }

    // MARK: - ILSparkMeterDataSource

    var datum: CGFloat {
        CGFloat(abs(sin(Date.timeIntervalSinceReferenceDate * speed)))
    }

    // MARK: - ILSparkStackDataSource

    var data: [NSNumber] {
        let fraction = (Date.timeIntervalSinceReferenceDate * speed).truncatingRemainder(dividingBy: 1)
        return [fraction, abs(sin(fraction)), abs(cos(fraction)), abs(tan(fraction))].map { NSNumber(value: $0) }
    }

    // MARK: - ILSparkLineDataSource

    var sampleDates: [Date] {
        dataDates
    }

    func sampleValue(at index: Int) -> CGFloat {
        CGFloat(abs(sin(dataDates[index].timeIntervalSinceReferenceDate * speed)))
    }
}

#if os(macOS)
// MARK: -

/// a style's colors from one color: its shades for the stroke, border and text, a pale tint for the background,
/// and its complement and neighbors on the color wheel for the stacks and the gradient
struct SparkyPalette {
    let fill: NSColor
    let stroke: NSColor
    let border: NSColor
    let background: NSColor
    let fontColor: NSColor
    let stackColors: [NSColor]
    let gradient: NSGradient?

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? NSColor.gray
        let hue = rgb.hueComponent, saturation = rgb.saturationComponent, brightness = rgb.brightnessComponent

        /// the color turned around the wheel by the fraction of a turn, with its saturation and brightness scaled
        func variant(turn: CGFloat = 0, saturation scaleSaturation: CGFloat = 1, brightness scaleBrightness: CGFloat = 1) -> NSColor {
            let turned = (hue + turn).truncatingRemainder(dividingBy: 1)
            return NSColor(hue: turned < 0 ? turned + 1 : turned, saturation: min(saturation * scaleSaturation, 1),
                           brightness: min(max(brightness * scaleBrightness, 0), 1), alpha: 1)
        }

        let complement = variant(turn: 0.5)
        fill = variant()
        stroke = variant(brightness: 0.6)
        border = variant(saturation: 0.5, brightness: 1.2)
        background = NSColor(hue: hue, saturation: saturation * 0.12, brightness: 0.98, alpha: 1)
        fontColor = NSColor(hue: hue, saturation: min(saturation, 0.6), brightness: 0.25, alpha: 1)
        stackColors = [fill, complement, variant(turn: 1.0 / 12, saturation: 0.7, brightness: 1.2), variant(turn: 0.5 - (1.0 / 12), brightness: 0.6)]
        gradient = NSGradient(starting: fill, ending: complement)
    }

    func apply(to style: ILSparkStyle) {
        style.fill = fill
        style.stroke = stroke
        style.border = border
        style.background = background
        style.fontColor = fontColor
        style.gradient = gradient
        style.addHints([ILSparkStackColorsHint: stackColors])
    }
}
#endif
