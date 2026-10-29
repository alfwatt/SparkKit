import Foundation
import CoreGraphics

/// a stream of records, each the same number of values of one type, e.g. the samples of a spectrum analyzer, for ILSparkStream views,
/// data can arrive in any size of pieces, each complete record is kept, up to the capacity, and sent to the observers
@objc(ILStreamData)
open class ILStreamData: NSObject {
    private let lock = NSRecursiveLock()
    private var pending = Data() // the start of the next record
    private var isOpen = false
    private let observers = NSHashTable<ILStreamDataDelegate>.weakObjects()

    /// the records kept, oldest first
    @objc public let grid: ILGridData

    /// the most records kept, the oldest are dropped
    @objc public var capacity: Int

    /// the range of the values, the views show each value as a fraction of the top of the range
    @objc public var valueRange: NSRange

    @objc public var dataType: ILGridDataType { grid.dataType }

    /// the number of values in each record
    @objc public var columns: Int { grid.columns }

    /// the size of each record in bytes
    @objc public var recordSize: Int { grid.sizeOfRow }

    /// the number of records kept
    @objc public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return grid.rows
    }

    @objc public init(dataType: ILGridDataType, columns: Int, capacity: Int, valueRange: NSRange) {
        self.grid = ILGridData(dataType: dataType, rows: 0, columns: columns)
        self.capacity = capacity
        self.valueRange = valueRange
        super.init()
    }

    // MARK: - Observers

    /// the observer is told when the stream opens, gets each record and closes, on the thread that appends the data
    @objc public func addObserver(_ observer: ILStreamDataDelegate) {
        lock.lock()
        defer { lock.unlock() }
        observers.add(observer)
    }

    @objc public func removeObserver(_ observer: ILStreamDataDelegate) {
        lock.lock()
        defer { lock.unlock() }
        observers.remove(observer)
    }

    // MARK: - Records

    /// append data to the stream, each complete record is kept and sent to the observers, the rest waits for the next data
    @objc public func appendData(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        let watchers = observers.allObjects
        if !isOpen {
            isOpen = true
            watchers.forEach { $0.streamDidOpen?(self) }
        }

        pending.append(data)
        let size = recordSize
        guard size > 0 else { return }
        while pending.count >= size {
            let record = pending.prefix(size)
            pending = pending.dropFirst(size)
            let rows = grid.rows
            if rows >= max(capacity, 1) { // drop the oldest
                let dropped = rows - capacity + 1
                grid.trim(toRangeOfRows: NSRange(location: dropped, length: capacity - 1))
                recordTimes.removeFirst(min(dropped, recordTimes.count))
            }
            grid.appendData(Data(record))
            recordTimes.append(Date())
            watchers.forEach { $0.stream?(self, didAppendRecord: Data(record)) }
        }
    }

    /// when each record kept arrived, oldest first
    private var recordTimes: [Date] = []

    /// the newest records, up to the number, oldest first
    @objc(newestRecords:)
    public func newestRecords(_ number: Int) -> [Data] {
        newestTimedRecords(number).map(\.record)
    }

    /// the newest records and when they arrived, up to the number, oldest first
    public func newestTimedRecords(_ number: Int) -> [(time: Date, record: Data)] {
        lock.lock()
        defer { lock.unlock() }
        let rows = grid.rows
        return (max(rows - number, 0)..<rows).map { row in
            (time: row < recordTimes.count ? recordTimes[row] : Date(), record: grid.data(atRow: row))
        }
    }

    /// the newest record, nil if there's none yet
    @objc public var newestRecord: Data? {
        newestRecords(1).first
    }

    /// the values of the record as fractions of the top of the value range
    @objc(percentsOfRecord:)
    public func percents(of record: Data) -> [CGFloat] {
        grid.percents(ofRowData: record, in: valueRange)
    }

    /// tell the observers the stream is closing, and drop any partial record, the records are kept
    @objc public func closeStream() {
        lock.lock()
        defer { lock.unlock() }
        observers.allObjects.forEach { $0.streamWillClose?(self) }
        pending = Data()
        isOpen = false
    }
}

// MARK: - ILStreamDataDelegate

/// told about a stream's records, on the thread that appends the data
@objc public protocol ILStreamDataDelegate: NSObjectProtocol {
    @objc optional func streamDidOpen(_ stream: ILStreamData) // first data
    @objc optional func stream(_ stream: ILStreamData, didAppendRecord record: Data) // each complete record
    @objc optional func streamWillClose(_ stream: ILStreamData) // close
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
