/* *************************************************************************************************
 ContentTransferEncoding.swift
   © 2021 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */

import Foundation
import NetworkGear

public enum ContentTransferEncodingError: Error {
  case cannotEncode
  case non7bitRepresentation
  case unexpectedError
}

extension DataProtocol {
  public func mimeSafeData(using encoding: ContentTransferEncoding) throws -> MIMESafeData {
    switch encoding {
    case ._7bit:
      guard let safeData = MIMESafeData(data: self) else {
        throw ContentTransferEncodingError.cannotEncode
      }
      return safeData
    case .base64:
      return MIMESafeData(_mimeSafeBytes: Data(self).base64EncodedData(options: .lineLength76Characters))
    case .quotedPrintable:
      return MIMESafeData(_mimeSafeBytes: Data(self).quotedPrintableEncodedData(options: .regardAsBinary))
    default:
      throw ContentTransferEncodingError.non7bitRepresentation
    }
  }
}

extension StringProtocol {
  internal func mimeSafeData(
    using transferEncoding: ContentTransferEncoding,
    stringEncoding: String.Encoding
  ) throws -> MIMESafeData {
    guard let data = self.data(using: stringEncoding) else {
      throw MailMessage.Error.dataConversionFailure
    }
    switch transferEncoding {
    case .quotedPrintable:
      return MIMESafeData(_mimeSafeBytes: data.quotedPrintableEncodedData(options: .default))
    default:
      return try data.mimeSafeData(using: transferEncoding)
    }
  }
}

private extension InputStream {
  func _getBytes(_ buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) throws -> Data? {
    let count = read(buffer, maxLength: maxLength)
    switch count {
    case ..<0:
      throw streamError ?? ContentTransferEncodingError.unexpectedError
    case 0:
      return nil
    default:
      return Data(bytes: UnsafeRawPointer(buffer), count: count)
    }
  }
}

public final class ContentTransferEncodingStream: MIMESafeInputStream {
  /// The source.
  public let input: InputStream

  /// The encoding that is used to encode bytes from stream
  public let encoding: ContentTransferEncoding

  private var _bufferSize = 4096

  private var __buffer: UnsafeMutablePointer<UInt8>? = nil
  private var _buffer:UnsafeMutablePointer<UInt8> {
    guard let buffer = __buffer else {
      let newBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: _bufferSize)
      __buffer = newBuffer
      return newBuffer
    }
    return buffer
  }

  deinit {
    if let buffer = __buffer {
      buffer.deallocate()
    }
  }

  private static let _encoders: [ContentTransferEncoding: (ContentTransferEncodingStream) throws -> MIMESafeData?] = [
    ._7bit: {
      guard let data = try $0.input._getBytes($0._buffer, maxLength: $0._bufferSize),
            !data.isEmpty else {
        return nil
      }
      guard let result = MIMESafeData(data: data) else {
        throw ContentTransferEncodingError.cannotEncode
      }
      return result
    },
    .base64: {
      let numberOfBytesOfSourcePerLine = 76 / 4 * 3
      let sizePerRead =
        ($0._bufferSize / numberOfBytesOfSourcePerLine) * numberOfBytesOfSourcePerLine
      guard let data = try $0.input._getBytes($0._buffer, maxLength: sizePerRead),
            !data.isEmpty else {
        return nil
      }
      assert(data.count <= sizePerRead)

      var result = MIMESafeData()
      result.append(contentsOf: data.base64EncodedData(options: .lineLength76Characters))

      // Workaround for https://bugs.swift.org/browse/SR-14496
      #if canImport(Darwin) || swift(>=5.6)
      result.append(contentsOf: .CRLF)
      #else
      if (1..<55).contains(data.count % numberOfBytesOfSourcePerLine) {
        result.append(contentsOf: .CRLF)
      }
      #endif

      return result
    },
    .quotedPrintable: {
      guard let data = try $0.input._getBytes($0._buffer, maxLength: $0._bufferSize),
            !data.isEmpty else {
        return nil
      }

      let softLineBreak = MIMESafeData([.EQ, .CR, .LF])
      var result = MIMESafeData()
      result.append(contentsOf: data.quotedPrintableEncodedData(options: .regardAsBinary))
      // To be safe, append "soft line break".
      let countOfLastLine = result.endIndex - (result.lastIndex(of: .LF) ?? -1) - 1
      switch countOfLastLine {
      case 0:
        // do nothing
        break
      case ..<76:
        result.append(contentsOf: softLineBreak)
      case 76:
        if result[result.endIndex - 3] == .EQ {
          // For example:
          // .............=C3[End of Data]
          result.insert(contentsOf: softLineBreak, at: result.endIndex - 3)
        } else {
          result.insert(contentsOf: softLineBreak, at: result.endIndex - 1)
        }
      default:
        throw ContentTransferEncodingError.unexpectedError
      }
      return result
    }
  ]

  private let _encoder: (ContentTransferEncodingStream) throws -> MIMESafeData?

  public init(_ input: InputStream, encoding: ContentTransferEncoding) throws {
    guard let encoder = Self._encoders[encoding] else {
      throw ContentTransferEncodingError.non7bitRepresentation
    }
    self.input = input
    self.encoding = encoding
    self._encoder = encoder

    self.input.open()
  }

  /// Returns some encoded bytes, or `nil` if stream put no bytes out.
  public func nextFragment() throws -> MIMESafeData? {
    return try _encoder(self)
  }
}
