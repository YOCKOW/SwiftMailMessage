/* *************************************************************************************************
 MIMESafeData.swift
   © 2021 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */

import Foundation

public struct UInt7: Equatable,
                     Comparable,
                     Hashable,
                     AdditiveArithmetic,
                     Numeric,
                     ExpressibleByIntegerLiteral,
                     Strideable {
  public typealias Magnitude = UInt8
  public typealias IntegerLiteralType = UInt8
  public typealias Stride = UInt8.Stride

  fileprivate let _representation: UInt8

  public var magnitude: UInt8 {
    return _representation
  }

  public func distance(to other: UInt7) -> Stride {
    return self._representation.distance(to: other._representation)
  }

  public func advanced(by n: Stride) -> UInt7 {
    return UInt7(_uint7: self._representation.advanced(by: n))
  }

  fileprivate init(_validated uint7: UInt8) {
    _representation = uint7
  }

  private init(_uint7 uint7: UInt8) {
    precondition(uint7 < 0x80, "UInt7 Overflow")
    _representation = uint7
  }

  public init(_ uint8: UInt8) {
    _representation = 0x7F & uint8
  }

  public init?<T>(exactly source: T) where T: BinaryInteger {
    guard let rep = UInt8(exactly: source), rep < 0x80 else { return nil }
    _representation = rep
  }

  public init(integerLiteral value: UInt8) {
    self.init(value)
  }

  public init<T>(clamping soruce: T) where T: BinaryInteger {
    let uint8 = UInt8(clamping: soruce)
    self.init(_uint7: uint8 > 0x7F ? 0x7F : uint8)
  }

  public static let zero: UInt7 = UInt7(_uint7: 0)

  internal static let LF: UInt7 = UInt7(_uint7: 0x0A)
  internal static let CR: UInt7 = UInt7(_uint7: 0x0D)
  internal static let SP: UInt7 = UInt7(_uint7: 0x20)
  internal static let EQ: UInt7 = UInt7(_uint7: 0x3D)

  public static func +(lhs: UInt7, rhs: UInt7) -> UInt7 {
    return UInt7(_uint7: lhs._representation + rhs._representation)
  }

  public static func -(lhs: UInt7, rhs: UInt7) -> UInt7 {
    return UInt7(_uint7: lhs._representation + rhs._representation)
  }

  public static func *(lhs: UInt7, rhs: UInt7) -> UInt7 {
    return UInt7(_uint7: lhs._representation * rhs._representation)
  }

  public static func *=(lhs: inout UInt7, rhs: UInt7) {
    lhs = lhs * rhs
  }
}

/// A byte buffer in memory that each bytes contained in is 7 bit.
public struct MIMESafeData: Equatable,
                            Hashable,
                            Sequence,
                            Collection,
                            BidirectionalCollection,
                            RangeReplaceableCollection,
                            RandomAccessCollection,
                            MutableCollection {
  public typealias Element = UInt7
  public typealias Index = Data.Index
  public typealias SubSequence = MIMESafeData

  public private(set) var bytes: Data

  @usableFromInline
  internal init(_mimeSafeBytes bytes: Data) {
    assert(bytes.allSatisfy({ UInt7(exactly: $0) != nil }))
    self.bytes = bytes
  }

  public init() {
    self.init(_mimeSafeBytes: Data())
  }

  /// Instantiates an instance with `data` if `data` consists of 7 bit bytes.
  public init?<D>(data: D) where D: DataProtocol {
    guard data.allSatisfy({ UInt7(exactly: $0) != nil }) else {
      return nil
    }
    self.init(_mimeSafeBytes: Data(data))
  }

  /// Instantiates an instance of the conforming type from a data representation.
  public init<T>(contentsOf data: T) where T: Sequence, T.Element == UInt7 {
    if case let data as MIMESafeData = data {
      self = data
    } else {
      self.init(_mimeSafeBytes: Data(contentsOf: data.map(\._representation)))
    }
  }

  internal static let CRLF: MIMESafeData = .init(contentsOf: [.CR, .LF])

  internal static let CRLFSP: MIMESafeData = .init(contentsOf: [.CR, .LF, .SP])

  @inlinable
  public static func ==(lhs: MIMESafeData, rhs: MIMESafeData) -> Bool {
    return lhs.bytes == rhs.bytes
  }

  @inlinable
  public static func +(lhs: MIMESafeData, rhs: MIMESafeData) -> MIMESafeData {
    return MIMESafeData(_mimeSafeBytes: lhs.bytes + rhs.bytes)
  }

  public static func +<Other>(
    lhs: MIMESafeData,
    rhs: Other
  ) -> MIMESafeData where Other: Sequence, Other.Element == UInt7  {
    if case let rhs as MIMESafeData = rhs {
      return lhs + rhs
    } else {
      return MIMESafeData(_mimeSafeBytes: lhs.bytes + rhs.map(\._representation ))
    }
  }

  public static func +<Other>(
    lhs: Other,
    rhs: MIMESafeData
  ) -> MIMESafeData where Other: Sequence, Other.Element == UInt7  {
    if case let lhs as MIMESafeData = lhs {
      return rhs + lhs
    } else {
      return MIMESafeData(_mimeSafeBytes: lhs.map(\._representation) + rhs.bytes)
    }
  }

  /// Appends the bytes of `rhs` to `lhs`.
  public static func +=(lhs: inout MIMESafeData, rhs: MIMESafeData) {
    lhs.bytes += rhs.bytes
  }

  public static func +=<Other>(
    lhs: inout MIMESafeData,
    rhs: Other
  ) where Other: Sequence, Other.Element == UInt7  {
    if case let rhs as MIMESafeData = rhs {
      lhs += rhs
    } else {
      lhs.bytes += rhs.map({ $0._representation })
    }
  }

  public struct Iterator: IteratorProtocol {
    public typealias Element = UInt7

    private var _iterator: Data.Iterator

    fileprivate init(_ data: Data) {
      _iterator = data.makeIterator()
    }

    public mutating func next() -> UInt7? {
      guard let byte = _iterator.next() else { return nil }
      return UInt7(_validated: byte)
    }
  }

  public func makeIterator() -> Iterator {
    return Iterator(bytes)
  }

  @inlinable
  public var count: Int {
    return bytes.count
  }

  @inlinable
  public var startIndex: Index {
    return bytes.startIndex
  }

  @inlinable
  public var endIndex: Index {
    return bytes.endIndex
  }

  public subscript(position: Index) -> UInt7 {
    get {
      return UInt7(_validated: bytes[position])
    }
    set {
      bytes[position] = newValue._representation
    }
  }

  public subscript(bounds: Range<Index>) -> SubSequence {
    get {
      return MIMESafeData(_mimeSafeBytes: bytes[bounds])
    }
    set {
      bytes[bounds] = newValue.bytes
    }
  }

  public func index(_ i: Index, offsetBy distance: Int) -> Index {
    return bytes.index(i, offsetBy: distance)
  }

  public func index(after i: Index) -> Index {
    return bytes.index(after: i)
  }

  public func formIndex(after i: inout Index) {
    bytes.formIndex(after: &i)
  }

  public func index(before i: Index) -> Index {
    return bytes.index(before: i)
  }

  public mutating func append(_ newElement: UInt7) {
    bytes.append(newElement._representation)
  }

  /// Adds the bytes of `data` to the end of this collection.
  public mutating func append(contentsOf data: MIMESafeData) {
    bytes.append(data.bytes)
  }

  public mutating func append<S>(contentsOf newElements: S) where S: Sequence, Self.Element == S.Element {
    if case let safeData as MIMESafeData = newElements {
      append(contentsOf: safeData)
    } else {
      bytes.append(contentsOf: newElements.map(\._representation))
    }
  }

  /// `mimeSafeBytes` must consist of 7-bit bytes.
  /// Do NOT make this func `public`,
  internal mutating func append<D>(contentsOf mimeSafeBytes: D) where D: DataProtocol {
    assert(mimeSafeBytes.allSatisfy({ UInt7(exactly: $0) != nil }))
    bytes.append(contentsOf: mimeSafeBytes)
  }

  public mutating func insert(contentsOf newElements: MIMESafeData, at i: Index) {
    bytes.insert(contentsOf: newElements.bytes, at: i)
  }

  public mutating func insert<S>(contentsOf newElements: S, at i: Index) where S: Collection, Self.Element == S.Element {
    if case let safe as MIMESafeData = newElements {
      insert(contentsOf: safe, at: i)
    } else {
      bytes.insert(contentsOf: newElements.map(\._representation), at: i)
    }
  }

  public mutating func replaceSubrange<C>(
    _ subrange: Range<Data.Index>,
    with newElements: C
  ) where C: Collection, UInt7 == C.Element {
    bytes.replaceSubrange(subrange, with: newElements.map(\._representation))
  }

  @inlinable
  public func withUnsafeBytes<ResultType>(
    body : (UnsafeRawBufferPointer) throws -> ResultType
  ) rethrows -> ResultType {
    return try bytes.withUnsafeBytes(body)
  }
}

extension String {
  @inlinable
  public init(data: MIMESafeData) {
    self.init(data: data.bytes, encoding: .utf8)!
  }
}

extension OutputStream {
  public enum MIMESafeDataWritingError: Error {
    case hasReachedCapacity
    case unexpectedError
  }

  @inlinable
  public func write(_ data: MIMESafeData) throws {
    let count = data.count
    guard count > 0 else { return }

    try data.withUnsafeBytes {
      assert($0.count == count)
      let numberOfBytesWritten = write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: count)
      switch numberOfBytesWritten {
      case count:
        // Successful
        break
      case 1..<count:
        try write(data.dropFirst(numberOfBytesWritten))
      case 0:
        throw MIMESafeDataWritingError.hasReachedCapacity
      default:
        throw streamError ?? MIMESafeDataWritingError.unexpectedError
      }
    }
  }
}
