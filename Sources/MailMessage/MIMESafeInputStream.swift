/* *************************************************************************************************
 MIMESafeInputStream.swift
   © 2021 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */
 
public protocol MIMESafeInputStream {
  mutating func nextFragment() throws -> MIMESafeData?
}

open class MIMESafeDataStream: MIMESafeInputStream {
  public let data: MIMESafeData

  public private(set) var hasBytesAvailable: Bool = true

  public init(_ data: MIMESafeData) {
    self.data = data
  }

  open func nextFragment() throws -> MIMESafeData? {
    if self.hasBytesAvailable {
      defer { self.hasBytesAvailable = false }
      return data
    }
    return nil
  }
}

open class LazyMIMESafeInputStream: MIMESafeInputStream {
  private let _generator: () throws -> MIMESafeInputStream

  private var _stream: MIMESafeInputStream? = nil

  public init(_ streamGenerator: @escaping () throws -> MIMESafeInputStream) {
    _generator = streamGenerator
  }

  open func nextFragment() throws -> MIMESafeData? {
    if _stream == nil {
      _stream = try _generator()
    }
    return try _stream!.nextFragment()
  }
}

open class MIMESafeInputSequenceStream: MIMESafeInputStream {
  public typealias ArrayLiteralElement = MIMESafeInputStream

  private var _iterator: AnyIterator<MIMESafeInputStream>

  private var _currentStream: MIMESafeInputStream? = nil

  public init<S>(_ streams: S) where S: Sequence, S.Element == MIMESafeInputStream {
    _iterator = AnyIterator(streams.makeIterator())
  }

  open func nextFragment() throws -> MIMESafeData? {
    if let fragment = try _currentStream?.nextFragment() {
      return fragment
    }
    guard let nextStream = _iterator.next() else {
      return nil
    }
    _currentStream = nextStream
    return try nextFragment()
  }
}
