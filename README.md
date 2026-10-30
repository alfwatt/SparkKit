
# SparkKit

Small, Simple and Fast; Line, Pie, Dial, Bar, Ring, Stack, Grid and Stream Views for macOS, iOS and tvOS

## Support SparkKit!

Are you using SparkKit in your apps? Would you like to help support the project and get a sponsor credit?

Visit our [Patreon Page](https://www.patreon.com/istumblerlabs) and patronize us in exchange for great rewards!

## Dependencies

### KitBridge

<a href="https://github.com/alfwatt/KitBridge">KitBridge</a> provides bridging for UIKit and AppKit.

## Using SparkKit

SparkKit is written in Swift and builds as a framework from `SparkKit.xcodeproj` or as a Swift package:

    .package(url: "https://github.com/alfwatt/SparkKit.git", branch: "main")

Then `import SparkKit` in Swift or `@import SparkKit;` in Objective-C.
The classes keep their `IL` names in the Objective-C runtime, so nibs and storyboards can use them as custom classes.

## Styles and Hints

An `ILSparkStyle` holds a view's colors, font, line width, and whether it's filled and bordered. Its `hints` dictionary tunes each
kind of view, the keys are Swift constants:

    let style = ILSparkStyle.defaultStyle.copy(withHints: [ILSparkMeterStyleHint: ILSparkMeterStyle.ringStyle.rawValue])
    meter.style = style

| Hint | Value | Views |
|---|---|---|
| `ILSparkFillDirectionHint` | an `ILSparkFillDirection`, see below | all |
| `ILSparkLogScaleHint` | the strength `k` of a log curve, each value `v` is shown as `log(1 + k·v) / log(1 + k)`, e.g. 10 is gentle and 100 strong | grids, bars, stream lines |
| `ILSparkMeterStyleHint` | an `ILSparkMeterStyle`: text, vertical, horizontal, square, circle, ring, pie or dial | meters, stacks |
| `ILSparkMeterRingWidthHint` | the ring's width in points, 8 by default | meters, stacks |
| `ILSparkMeterDialWidthHint` | the dial's width in points, 4 by default | meters, stacks |
| `ILSparkStackColorsHint` | an array of `ILColor`s, one for each value | stacks |
| `ILSparkLineScaleFactor` | the seconds for each point | lines |
| `ILSparkLineFalloffInterval` | the seconds between samples which leave a dashed gap | lines |
| `ILSparkGridRowSizeHint` | each row's size in points, 0 stretches the rows to fill the view, square cells by default | grids |
| `ILSparkGridEmptyColorHint` | an `ILColor` for the grid where there's no data, a neutral gray by default | grids |
| `ILSparkGridScrollSpeedHint` | points a second, the rows sit where their records arrived and the grid moves smoothly, gaps show as empty grid | stream grids |
| `ILSparkStreamStyleHint` | an `ILSparkStreamStyle`: grid, bars or line | streams |

`ILSparkFillDirectionHint` sets the direction a view fills in: `.fromTop`, `.fromBottom`, `.fromLeft` or `.fromRight`, and for the square
and circle meters and stacks `.inward` from the edges or `.outward` from the center. Meters and stacks fill from that edge, bars grow from it,
and the newest sample of a line or row of a grid is at it. Without the hint each view keeps its own default: meters, stacks and bars from the bottom,
or the left for the horizontal styles, square and circle meters outward and stacks inward, lines from the right and grids from the top.

The outline of a bordered view is drawn over its content, and its background behind it.

## Classes

### ILSparkStyle

Style definitions which can be re-used across multiple views. Provides a default style.

### ILSparkView

Base class which manages borders and style information, the axis labels, and `spans`: titles across the top, each centered over a range
of columns with a rule under it, e.g. the bands of a run of channels. Bars, grids and streams draw them when their columns run across the
view, and the pulsar plot over its segments.

### ILSparkLine

Time-sequence line graph

### ILSparkMeter

Multiple style gauge indicators: text, vertical, horizontal, square, circle, ring, pie and dial

### ILSparkStack

A meter with a stack of values, in the same styles as ILSparkMeter

### ILSparkBars &amp; ILBucketData

Bar chart of bucketed values, e.g. a histogram

### ILSparkGrid &amp; ILGridData

High performance grid data view and source. Each cell blends from the style's background to its fill by its value in the grid's
`valueRange`. The cells are square unless `ILSparkGridRowSizeHint` sizes the rows, the newest row enters from the top or the edge
`ILSparkFillDirectionHint` names, and `ILSparkGridEmptyColorHint` colors the grid where there's no data.

### ILSparkStream &amp; ILStreamData

A stream of records, each the same number of values of one type, e.g. the samples of a spectrum analyzer, and a view of it.

`ILStreamData` takes data in any size of pieces with `appendData(_:)`, keeps each complete record with when it arrived, up to its
`capacity`, and tells its observers about each one. Its `valueRange` sets the values shown as 0 and 1, the start of the range is the floor.

    let stream = ILStreamData(dataType: .byte, columns: 256, capacity: 4096, valueRange: NSMakeRange(0, 255))
    waterfall.style = style.copy(withHints: [ILSparkStreamStyleHint: ILSparkStreamStyle.gridStyle.rawValue, ILSparkGridScrollSpeedHint: 20])
    waterfall.stream = stream
    bars.style = style.copy(withHints: [ILSparkStreamStyleHint: ILSparkStreamStyle.barsStyle.rawValue])
    bars.stream = stream
    stream.appendData(sample) // from any thread

`ILSparkStream` draws the stream as `ILSparkStreamStyleHint` says:

- grid: the records as rows, newest at the fill direction's edge, the top by default, with `ILSparkGridScrollSpeedHint` the rows are placed
  by when they arrived and the grid moves smoothly, so gaps in the stream show and grids with the same speed match in time
- bars: the newest record as bars, growing from the bottom by default
- line: the newest record as a line, rising from the bottom by default, filled if the style is

Records that arrive together are drawn once, and any number of views can show one stream.

### ILSparkPulsar &amp; ILSparkCurve

A pulsar plot, spectra drawn as smooth curves stacked up the view, the newest at the bottom, each hiding the ones behind it, like the
cover of Unknown Pleasures. The values of each spectrum can be split into `segments`, drawn with gaps between them, with `spans` titled
across the top and `marks` along the bottom. `ILSparkCurve` smooths the values with an FFT, `pointsPerValue` points for each value.

    pulsar.maximumValue = 128
    pulsar.segments = [0..<14, 14..<40] // e.g. two bands
    pulsar.spans = [ILSparkSpan(title: "2.4 GHz", values: 0...13), ILSparkSpan(title: "5 GHz", values: 14...39)]
    pulsar.append(spectrum) // or
    pulsar.stream = stream // each record is a spectrum, scaled from the stream's value range to the maximum value

The style's background is the plot, the older curves are in its stroke color and the newest in its fill, starting from
`ILSparkPulsar.defaultPulsarStyle`, white on black with the newest in orange. The background should be opaque, it hides the curves behind
each one. Older curves are kept in a bitmap which moves up a row for each new curve, so each redraw draws only the newest, and redraws are
limited to `redrawInterval`.

### ILBucketData, ILGridData and ILStreamData

The data sources tell their views when they change, from any thread, and the views redraw on the main queue.

## Examples

See the included Sparky app, for macOS, iOS and tvOS, which shows the meters, stacks, line, bars and grid, scaled to fill its window,
and on the Mac styles them from a color well in the title bar.

## Releases

- 0.1-beta      2018ish?
- 0.2-beta      2024ish? (TODO)

## License

    The MIT License (MIT)

    Copyright © 2016-2026 Alf Watt

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
