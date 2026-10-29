import Foundation

/// streaming data interface for ILStreamView
@objc(ILStreamData)
open class ILStreamData: NSObject {
    @objc public var buffer: Data?
    @objc public var width = 1 // of the stream, in bytes
    @objc public weak var delegate: ILStreamDataDelegate?

    /// append data to the stream, which notifies the delegate each time the buffer holds a multiple of the stream's width
    @objc public func appendData(_ data: Data) {
        if buffer == nil {
            buffer = Data()
            delegate?.streamDidOpen?(self)
        }

        buffer?.append(data)

        if let buffer, width > 0, (buffer.count % width) == 0 {
            delegate?.stream?(self, recievedData: buffer)
        }
    }

    /// send streamWillClose to the delegate and release the buffer
    @objc public func closeStream() {
        delegate?.streamWillClose?(self)
        buffer = nil
    }
}

// MARK: - ILStreamDataDelegate

/// ILStreamDataDelegate - delegate for ILStreamData
@objc public protocol ILStreamDataDelegate: NSObjectProtocol {
    @objc optional func streamDidOpen(_ stream: ILStreamData) // first write
    @objc optional func stream(_ stream: ILStreamData, recievedData data: Data) // every stream.width
    @objc optional func streamWillClose(_ stream: ILStreamData) // close
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
