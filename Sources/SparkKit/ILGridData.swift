/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
#endif

@objc public enum ILGridDataType: Int {
    case byte
    case integer
    case float
    case unichar

    /// the size of each value in bytes
    public var size: Int {
        switch self {
        case .byte: MemoryLayout<UInt8>.size
        case .integer: MemoryLayout<Int>.size
        case .float: MemoryLayout<CGFloat>.size
        case .unichar: MemoryLayout<UniChar>.size
        }
    }
}

// MARK: -

/// ILGridData wraps Data with a 2d array of values of one type, the rows are computed from the length of the data
@objc(ILGridData)
open class ILGridData: NSObject {
    private let lock = NSRecursiveLock()

    @objc public var data: Data
    @objc public var dataType: ILGridDataType
    @objc public var columns: Int
    @objc public weak var delegate: ILGridDataDelegate?

    /// the size of each value in bytes, which depends on the type
    @objc public var valueSize: Int { dataType.size }

    /// the number of rows, computed from the length of the data
    @objc public var rows: Int { columns > 0 ? (data.count / sizeOfRow) : 0 }

    /// the size of each row in bytes
    @objc public var sizeOfRow: Int { valueSize * columns }

    // MARK: - Factory

    @objc(gridWithDataType:rows:columns:)
    public class func grid(with dataType: ILGridDataType, rows: Int, columns: Int) -> ILGridData {
        ILGridData(dataType: dataType, rows: rows, columns: columns)
    }

    @objc public class func byteGrid(withRows rows: Int, columns: Int) -> ILGridData {
        ILGridData(dataType: .byte, rows: rows, columns: columns)
    }

    @objc public class func integerGrid(withRows rows: Int, columns: Int) -> ILGridData {
        ILGridData(dataType: .integer, rows: rows, columns: columns)
    }

    @objc public class func floatGrid(withRows rows: Int, columns: Int) -> ILGridData {
        ILGridData(dataType: .float, rows: rows, columns: columns)
    }

    @objc public class func uniCharGrid(withRows rows: Int, columns: Int) -> ILGridData {
        let grid = ILGridData(dataType: .unichar, rows: rows, columns: columns)
        grid.fillUniCharValue(UniChar(UInt8(ascii: " ")))
        return grid
    }

    // MARK: -

    /// a grid of zeros
    @objc(initGridWithDataType:rows:columns:)
    public init(dataType: ILGridDataType, rows: Int, columns: Int) {
        self.data = Data(count: rows * columns * dataType.size)
        self.dataType = dataType
        self.columns = columns
        super.init()
    }

    // MARK: - Values

    private func raiseRange(_ reason: String) -> Never {
        NSException(name: .rangeException, reason: reason, userInfo: nil).raise()
        fatalError(reason) // raise doesn't return
    }

    /// the offset in bytes of the value
    private func offset(ofRow row: Int, column: Int) -> Int {
        guard row >= 0, row < rows, column >= 0, column < columns else {
            raiseRange("row: \(row) or column: \(column) out of range: \(rows) x \(columns)")
        }
        return (row * sizeOfRow) + (column * valueSize)
    }

    private func value<T>(_ type: ILGridDataType, atRow row: Int, column: Int, as: T.Type) -> T {
        guard dataType == type else {
            raiseRange("\(self) has \(dataType) values, not \(type)")
        }
        let offset = offset(ofRow: row, column: column)
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }

    private func setValue<T>(_ value: T, _ type: ILGridDataType, atRow row: Int, column: Int) {
        guard dataType == type else {
            raiseRange("\(self) has \(dataType) values, not \(type)")
        }
        let offset = offset(ofRow: row, column: column)
        data.withUnsafeMutableBytes { $0.storeBytes(of: value, toByteOffset: offset, as: T.self) }
    }

    @objc public func byte(atRow row: Int, column: Int) -> UInt8 {
        value(.byte, atRow: row, column: column, as: UInt8.self)
    }

    @objc public func integer(atRow row: Int, column: Int) -> Int {
        value(.integer, atRow: row, column: column, as: Int.self)
    }

    @objc public func float(atRow row: Int, column: Int) -> CGFloat {
        value(.float, atRow: row, column: column, as: CGFloat.self)
    }

    @objc public func uniChar(atRow row: Int, column: Int) -> UniChar {
        value(.unichar, atRow: row, column: column, as: UniChar.self)
    }

    /// the value as a fraction of the top of the range, the magnitude of negative values, a float grid without a range has fractions
    @objc(percentOfValueAtRow:column:inRange:)
    public func percentOfValue(atRow row: Int, column: Int, in range: NSRange) -> CGFloat { // TODO negative and floating point ranges
        let maxValue = CGFloat(range.location + range.length)
        switch dataType {
        case .byte:
            return maxValue > 0 ? CGFloat(byte(atRow: row, column: column)) / maxValue : 0
        case .integer:
            return maxValue > 0 ? CGFloat(abs(integer(atRow: row, column: column))) / maxValue : 0
        case .float:
            let value = abs(float(atRow: row, column: column))
            return maxValue > 0 ? value / maxValue : value
        case .unichar:
            return 0
        }
    }

    // MARK: - Setters

    @objc public func setByte(_ byteValue: UInt8, atRow row: Int, column: Int) {
        setValue(byteValue, .byte, atRow: row, column: column)
    }

    @objc public func setInteger(_ integerValue: Int, atRow row: Int, column: Int) {
        setValue(integerValue, .integer, atRow: row, column: column)
    }

    @objc public func setFloat(_ floatValue: CGFloat, atRow row: Int, column: Int) {
        setValue(floatValue, .float, atRow: row, column: column)
    }

    @objc public func setUniChar(_ charValue: UniChar, atRow row: Int, column: Int) {
        setValue(charValue, .unichar, atRow: row, column: column)
    }

    // MARK: - Fill Grid with a Value

    private func fill(_ set: (Int, Int) -> Void) {
        for row in 0..<rows {
            for column in 0..<columns {
                set(row, column)
            }
        }
    }

    @objc public func fillByteValue(_ byteValue: UInt8) {
        fill { setByte(byteValue, atRow: $0, column: $1) }
    }

    @objc public func fillIntegerValue(_ integerValue: Int) {
        fill { setInteger(integerValue, atRow: $0, column: $1) }
    }

    @objc public func fillUniCharValue(_ unicharValue: UniChar) {
        fill { setUniChar(unicharValue, atRow: $0, column: $1) }
    }

    @objc public func fillFloatValue(_ floatValue: CGFloat) {
        fill { setFloat(floatValue, atRow: $0, column: $1) }
    }

    // MARK: - String Representations

    /// the rows separated by commas and newlines, each value formatted as a column
    private func representation(rowStart: String, rowEnd: String, separator: String, start: String, end: String,
                                _ format: (Int, Int) -> String) -> String {
        let rowStrings = (0..<rows).map { row in
            rowStart + (0..<columns).map { format(row, $0) }.joined(separator: separator) + rowEnd
        }
        return start + rowStrings.joined(separator: ",\n") + end
    }

    @objc public func integerGridRepresentation() -> String {
        representation(rowStart: "", rowEnd: "", separator: " ", start: "", end: "") {
            String(format: "% 5li", integer(atRow: $0, column: $1))
        }
    }

    /// arrays of arrays of numbers
    @objc public func jsonIntegerRepresentation() -> String {
        representation(rowStart: "[", rowEnd: "]", separator: ",", start: "[", end: "]") {
            String(format: "%li", integer(atRow: $0, column: $1))
        }
    }

    /// arrays of arrays of numbers
    @objc public func jsonFloatRepresentation() -> String {
        representation(rowStart: "[", rowEnd: "]", separator: ",", start: "[", end: "]") {
            String(format: "'%lf'", float(atRow: $0, column: $1))
        }
    }

    /// arrays of unichar strings
    @objc public func jsonUniCharRepresentation() -> String {
        representation(rowStart: "[", rowEnd: "]", separator: ",", start: "[", end: "]") {
            String(format: "'%C'", uniChar(atRow: $0, column: $1))
        }
    }

    // MARK: - Image Representations

    /// a gray bitmap of the rows, from the values as a fraction of the range, darker for larger values in grayscale bitmaps
    private func bitmap(rows rowRange: Range<Int>, range: NSRange, alpha: Bool) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        let grayscale = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = alpha ? CGImageAlphaInfo.alphaOnly : CGImageAlphaInfo.none
        guard columns > 0, !rowRange.isEmpty,
              let context = CGContext(data: nil, width: columns, height: rowRange.count, bitsPerComponent: 8,
                                      bytesPerRow: columns * grayscale.numberOfComponents, space: grayscale,
                                      bitmapInfo: bitmapInfo.rawValue) else { return nil }
        context.setFillColorSpace(grayscale)
        for (y, row) in rowRange.enumerated() {
            for column in 0..<columns {
                let percentValue = percentOfValue(atRow: row, column: column, in: range)
                if alpha {
                    context.setFillColor([percentValue, 1.0])
                    context.setAlpha(percentValue)
                }
                else {
                    context.setFillColor([1.0 - percentValue, 1.0])
                }
                context.fill(CGRect(x: column, y: y, width: 1, height: 1)) // single pixel
            }
        }
        return context.makeImage()
    }

    @objc(grayscaleBitmapOfRow:withRange:)
    public func grayscaleBitmap(ofRow row: Int, with range: NSRange) -> CGImage? {
        bitmap(rows: row..<(row + 1), range: range, alpha: false)
    }

    @objc(grayscaleBitmapWithRange:)
    public func grayscaleBitmap(with range: NSRange) -> CGImage? {
        bitmap(rows: 0..<rows, range: range, alpha: false)
    }

    @objc(alphaBitmapOfRow:withRange:)
    public func alphaBitmap(ofRow row: Int, with range: NSRange) -> CGImage? {
        bitmap(rows: row..<(row + 1), range: range, alpha: true)
    }

    @objc(alphaBitmapWithRange:)
    public func alphaBitmap(with range: NSRange) -> CGImage? {
        bitmap(rows: 0..<rows, range: range, alpha: true)
    }

    // MARK: - Slices

    @objc public func data(atRow row: Int) -> Data {
        lock.lock()
        defer { lock.unlock() }
        let start = offset(ofRow: row, column: 0)
        return data.subdata(in: start..<(start + sizeOfRow))
    }

    @objc public func setData(_ slice: Data, atRow row: Int) {
        lock.lock()
        defer { lock.unlock() }
        let index = row * sizeOfRow
        guard row >= 0, slice.count == sizeOfRow, (index + sizeOfRow) <= data.count else {
            raiseRange("\(self) setData:atRow: slice lands outside of data range: \(slice) row \(row)")
        }
        data.replaceSubrange(index..<(index + sizeOfRow), with: slice)
        delegate?.grid?(self, didSetData: slice, atRow: row)
    }

    /// append zero or more rows
    @objc public func appendData(_ slice: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard columns > 0, valueSize > 0 else {
            NSLog("EXCEPTION appending data: %@ to a grid with 0 columns or no value size: %@", slice as NSData, self)
            return
        }
        guard (slice.count % sizeOfRow) == 0 else {
            NSLog("EXCEPTION appending data: %@, wrong sized slice: %lu bytes for grid: %@", slice as NSData, slice.count, self)
            return
        }
        data.append(slice)
        delegate?.grid?(self, didAppendedData: slice, asRow: rows - 1)
    }

    @objc(trimToRangeOfRows:)
    public func trim(toRangeOfRows rowRange: NSRange) {
        lock.lock()
        defer { lock.unlock() }
        guard (rowRange.location + rowRange.length) <= rows else {
            NSLog("EXCEPTION trimmed range (%lu,%lu) exceeds grid size: %lu", rowRange.location, rowRange.length, rows)
            return
        }
        delegate?.grid?(self, willTrimToRangeOfRows: rowRange)
        let start = rowRange.location * sizeOfRow
        data = data.subdata(in: start..<(start + (rowRange.length * sizeOfRow)))
    }

    /// add rows of zeros until there are at least the number of rows
    @objc(extendToRow:)
    public func extend(toRow rows: Int) {
        lock.lock()
        defer { lock.unlock() }
        while self.rows < rows {
            appendData(Data(count: sizeOfRow))
        }
    }

    // MARK: - Buckets

    @objc(bucketsAtRow:withRange:)
    public func buckets(atRow row: Int, with valueRange: NSRange) -> [NSNumber] {
        lock.lock()
        defer { lock.unlock() }
        return (0..<columns).map { NSNumber(value: Double(percentOfValue(atRow: row, column: $0, in: valueRange))) }
    }
}

// MARK: - ILGridDataDelegate

@objc public protocol ILGridDataDelegate: NSObjectProtocol {

    // MARK: - Slice Operations

    @objc(grid:didSetData:atRow:)
    optional func grid(_ grid: ILGridData, didSetData data: Data, atRow row: Int)

    @objc(grid:didAppendedData:asRow:)
    optional func grid(_ grid: ILGridData, didAppendedData data: Data, asRow row: Int)

    @objc(grid:willTrimToRangeOfRows:)
    optional func grid(_ grid: ILGridData, willTrimToRangeOfRows rows: NSRange)
}

#if os(macOS)
// MARK: - Table Data Source Adapter

/// shows a grid in a table, the labels in the first column then a column for each column of the grid
@objc(ILGridTableDataSource)
open class ILGridTableDataSource: NSObject, NSTableViewDataSource {
    @objc public var grid: ILGridData?
    @objc public var labels: [Any]?
    @objc public var range = NSRange(location: 0, length: 0)

    // MARK: - NSTableViewDataSource

    public func numberOfRows(in tableView: NSTableView) -> Int {
        grid?.rows ?? 0
    }

    public func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let tableColumn, let columnIndex = tableView.tableColumns.firstIndex(of: tableColumn) else { return nil }
        if columnIndex == 0 {
            return labels.flatMap { row < $0.count ? $0[row] : nil }
        }
        guard let grid else { return nil }
        switch grid.dataType {
        case .integer: return NSNumber(value: Double(grid.percentOfValue(atRow: row, column: columnIndex - 1, in: range)))
        case .byte: return NSNumber(value: grid.byte(atRow: row, column: columnIndex - 1))
        case .float: return NSNumber(value: Double(grid.float(atRow: row, column: columnIndex - 1)))
        case .unichar: return String(format: "%C", grid.uniChar(atRow: row, column: columnIndex - 1))
        }
    }
}
#endif
