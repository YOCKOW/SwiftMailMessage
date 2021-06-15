/* *************************************************************************************************
 StringProtocol.swift
   © 2021 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */

import Foundation
import NetworkGear
import yExtensions

private extension Unicode.Scalar {
  enum _Kind: Equatable {
    case canBeLinearWhiteSpace
    case visibleASCII
    case other
  }

  var _kind: _Kind {
    switch self {
    case "\u{0009}", "\u{0020}": // HTAB, SPACE
      return .canBeLinearWhiteSpace
    case "\u{0021}"..."\u{007E}":
      return .visibleASCII
    default:
      return .other
    }
  }
}

private extension RangeReplaceableCollection where Self: BidirectionalCollection {
  mutating func _replaceLastElement(with element: Element) {
    replaceSubrange(index(before: endIndex)..<endIndex, with: [element])
  }
}

private extension RangeReplaceableCollection {
  mutating func _replaceFirstElement(with element: Element) {
    replaceSubrange(startIndex..<index(after: startIndex), with: [element])
  }

  func _appending(_ element: Element) -> Self {
    var result = self
    result.append(element)
    return result
  }

  func _appending<S>(contentsOf elements: S) -> Self where S: Sequence, S.Element == Element {
    var result = self
    result.append(contentsOf: elements)
    return result
  }
}

private extension Sequence where Element == Unicode.Scalar {
  var _ascii: MIMESafeData {
    return MIMESafeData(_mimeSafeBytes: Data(self.flatMap({ $0.utf8 })))
  }
}

private extension RandomAccessCollection {
  func _split(at index: Index) -> (Self.SubSequence, Self.SubSequence) {
    return (self[startIndex..<index], self[index..<endIndex])
  }
}

private extension String {
  init<S>(_ scalars: S) where S: Sequence, S.Element == Unicode.Scalar {
    self.init(UnicodeScalarView(scalars))
  }
}

// testable
internal final class _Parser {
  enum Token: Equatable {
    case raw([Unicode.Scalar])
    case mustBeEncoded([Unicode.Scalar])
  }

  init() {}

  func parse<S>(_ string: S) -> [Token] where S: StringProtocol {
    let scalars = string.unicodeScalars
    guard let first = scalars.first else {
      return []
    }

    var tokens: [Token] = []
    switch first._kind {
    case .canBeLinearWhiteSpace, .visibleASCII:
      tokens.append(.raw([first]))
    case .other:
      tokens.append(.mustBeEncoded([first]))
    }

    var index = scalars.index(after: scalars.startIndex)
    while index < scalars.endIndex {
      defer { scalars.formIndex(after: &index) }

      let scalar = scalars[index]
      switch (scalar._kind, tokens.last!) {
      case (.canBeLinearWhiteSpace, .raw(let rawables)):
        tokens._replaceLastElement(with: .raw(rawables._appending(scalar)))
      case (.canBeLinearWhiteSpace, _):
        tokens.append(.raw([scalar]))
      case (.visibleASCII, .raw(let rawables)):
          tokens._replaceLastElement(with: .raw(rawables._appending(scalar)))
      case (.visibleASCII, .mustBeEncoded(let encodees)):
        tokens._replaceLastElement(with: .mustBeEncoded(encodees._appending(scalar)))
      case (.other, .raw(let rawables)):
        if tokens.count == 1,
           let spFirstIndex = rawables.firstIndex(where: { $0._kind == .canBeLinearWhiteSpace }),
           spFirstIndex != rawables.startIndex
        {
          // Workaround for https://github.com/YOCKOW/SwiftMailMessage/issues/2
          let spLastIndex = rawables.lastIndex(where: { $0._kind == .canBeLinearWhiteSpace })!
          tokens = [
            .raw(Array<Unicode.Scalar>(rawables[...spLastIndex])),
            .mustBeEncoded(Array<Unicode.Scalar>(rawables[rawables.index(after: spLastIndex)...])),
            .mustBeEncoded([scalar]),
          ]
        } else if rawables.allSatisfy({ $0._kind == .canBeLinearWhiteSpace }) {
          let beforeLast: Token? = ({ () -> Token? in
            guard tokens.count >= 2 else {
              return nil
            }
            return tokens.dropLast().last!
          })()
          if case .mustBeEncoded(let encodees) = beforeLast {
            // Encode also spaces!
            tokens = tokens.dropLast()
            tokens._replaceLastElement(
              with: .mustBeEncoded(encodees._appending(contentsOf: rawables)._appending(scalar))
            )
          } else {
            tokens.append(.mustBeEncoded([scalar]))
          }
        } else if case .canBeLinearWhiteSpace = rawables.last?._kind {
          tokens.append(.mustBeEncoded([scalar]))
        } else {
          tokens._replaceLastElement(with: .mustBeEncoded(rawables._appending(scalar)))
        }
      case (.other, .mustBeEncoded(let encodees)):
        tokens._replaceLastElement(with: .mustBeEncoded(encodees._appending(scalar)))
      }
    }

    var finalizedTokens: [Token] = []
    for (offset, token) in tokens.enumerated() {
      if offset == 0 {
        finalizedTokens.append(token)
        continue
      }

      switch token {
      case .raw(let rawables) where offset == tokens.count - 1 && rawables.allSatisfy({ $0._kind == .canBeLinearWhiteSpace }):
        if case .mustBeEncoded(let encodees) = finalizedTokens.last {
          finalizedTokens._replaceLastElement(with: .mustBeEncoded(encodees._appending(contentsOf: rawables)))
        } else {
          finalizedTokens.append(.mustBeEncoded(rawables))
        }
      case .raw(let rawables):
        if case .raw(let lastRawables) = finalizedTokens.last {
          finalizedTokens._replaceLastElement(with: .raw(lastRawables._appending(contentsOf: rawables)))
        } else {
          finalizedTokens.append(token)
        }
      case .mustBeEncoded(let encodees):
        if case .mustBeEncoded(let lastEncodees) = finalizedTokens.last {
          finalizedTokens._replaceLastElement(with: .mustBeEncoded(lastEncodees._appending(contentsOf: encodees)))
        } else {
          finalizedTokens.append(token)
        }
      }
    }
    return finalizedTokens
  }
}

enum MIMEEncodingError: Error {
  case noCharacterSetName
  case dataConversionFailure
  case percentEncodingFailure
}


private extension String.Encoding {
  var _dataSizeIsIncrementable: Bool {
    switch self {
    // TODO: Add more encodings
    case .utf8, .utf16, .utf32:
      return true
    default:
      return false
    }
  }
}

private extension RandomAccessCollection where Element == Unicode.Scalar, Index == Int {
  /// Returns the end index to satisfy that
  /// `countWhenEncoded(self[startIndex..<resultOfThisMethod]) <= maxByteCount`
  func _endIndex(
    withinMaxByteCount maxByteCount: Int,
    incrementable: Bool,
    countWhenEncoded: (Self.SubSequence) throws -> Int
  ) rethrows -> Index {
    assert(!self.isEmpty)

    var byteCounts: Dictionary<Index, Int> = [:]
    func __byteCount(_ index: Index) throws -> Int {
      guard let byteCount = byteCounts[index] else {
        let result: Int = try ({
          if incrementable {
            return try (index == startIndex ? 0 : __byteCount(index - 1)) + countWhenEncoded(self[index...index])
          } else {
            return try countWhenEncoded(self[startIndex...index])
          }
        })()
        byteCounts[index] = result
        return result
      }
      return byteCount
    }

    func __binarySearch(_ range: Range<Index>) throws -> Index {
      let middleIndex = range.lowerBound + ((range.upperBound - range.lowerBound) / 2)
      let byteCount = try __byteCount(middleIndex)

      if byteCount == maxByteCount {
        return middleIndex + 1
      }

      if byteCount < maxByteCount {
        if middleIndex >= range.upperBound - 1 {
          return range.upperBound
        }
        let nextIndex = middleIndex + 1
        return try __binarySearch(nextIndex..<range.upperBound)
      }

      assert(byteCount > maxByteCount)
      if middleIndex <= range.lowerBound {
        return range.lowerBound
      }
      let prevIndex = middleIndex - 1
      return try __binarySearch(range.lowerBound..<prevIndex)
    }

    return try __binarySearch(startIndex..<endIndex)
  }


  func _endIndex(withinMaxByteCount maxByteCount: Int, using encoding: String.Encoding) throws -> Index {
    return try _endIndex(withinMaxByteCount: maxByteCount, incrementable: encoding._dataSizeIsIncrementable) {
      guard let data = String($0).data(using: encoding) else {
        throw MIMEEncodingError.dataConversionFailure
      }
      return data.count
    }
  }
}

extension StringProtocol {
  /// Returns the encoded data with the method
  /// defined in [RFC2047](https://www.ietf.org/rfc/rfc2047.txt).
  ///
  /// This method is intended to be used in mail headers.
  internal func mimeEncodedData(using encoding: String.Encoding) throws -> MIMESafeData {
    if self.isEmpty {
      return MIMESafeData()
    }

    guard let encodingName = encoding.ianaCharacterSetName else {
      throw MIMEEncodingError.noCharacterSetName
    }
    let startEncodedText = MIMESafeData(_mimeSafeBytes: Data("=?\(encodingName)?B?".utf8))
    let endEncodedText = MIMESafeData(_mimeSafeBytes: Data("?=".utf8))

    // reference: http://www.din.or.jp/~ohzaki/perl.htm#JP_Base64 (Japanese)

    var restOfTokens: ArraySlice<_Parser.Token> = _Parser().parse(self)[...]
    let nPerLine = 75 // ≦75 bytes per line
    var lines: [MIMESafeData] = [MIMESafeData()]
    func __newLine() { lines.append(MIMESafeData()) }

    while let token = restOfTokens.first, let lastLine = lines.last {
      defer {
        if lines.last!.count >= nPerLine {
          __newLine()
        }
      }

      let remainingCapacity = nPerLine - lastLine.count
      switch token {
      case .raw(let rawables):
        // ASCII: 1 byte/scalar
        if rawables.count <= remainingCapacity {
          lines._replaceLastElement(with: lastLine._appending(contentsOf: rawables._ascii))
          restOfTokens = restOfTokens.dropFirst()
        } else {
          let (thisLine, nextLine) = rawables._split(at: remainingCapacity)
          lines._replaceLastElement(with: lastLine._appending(contentsOf: thisLine._ascii))
          restOfTokens._replaceFirstElement(with: .raw(Array(nextLine)))
        }
      case .mustBeEncoded(let encodees):
        let maxEncodedByteCount = remainingCapacity - startEncodedText.count - endEncodedText.count
        // Base 64  | Original
        //  4 bytes | 1 ... 3 bytes
        //  8 bytes | 4 ... 6 bytes
        //   :      |    :
        // 4n bytes | 3(n-1)+1 ... 3n bytes
        let maxByteCount = (maxEncodedByteCount / 4) * 3
        let (scalarsToBeInThisLine, scalarsToBeNextLine) =
          encodees._split(at: try encodees._endIndex(withinMaxByteCount: maxByteCount, using: encoding))
        if scalarsToBeInThisLine.isEmpty {
          __newLine()
          continue
        }
        guard let stringData = String(scalarsToBeInThisLine).data(using: encoding) else {
          throw MIMEEncodingError.dataConversionFailure
        }
        let encoded = MIMESafeData(_mimeSafeBytes: stringData.base64EncodedData())
        assert(encoded.count <= maxEncodedByteCount)
        let newLastLine = lastLine + startEncodedText + encoded + endEncodedText
        lines._replaceLastElement(with: newLastLine)
        if scalarsToBeNextLine.isEmpty {
          restOfTokens = restOfTokens.dropFirst()
        } else {
          __newLine()
          restOfTokens._replaceFirstElement(with: .mustBeEncoded(Array(scalarsToBeNextLine)))
        }
      }
    }

    var result = MIMESafeData()
    for line in lines.dropLast() {
      result += line
      result += .CRLFSP
    }
    result += lines.last!
    return result
  }

  /// Returns the encoded string with the method
  /// defined in [RFC2047](https://www.ietf.org/rfc/rfc2047.txt).
  ///
  /// This method is intended to be used in mail headers.
  internal func mimeEncodedString(using encoding: String.Encoding) throws -> String {
    return String(data: try mimeEncodedData(using: encoding))
  }
}

internal func _mimeEncodedHeaderField(
  name: MailMessage.Header.Name,
  value: String,
  encoding: String.Encoding
) throws -> MIMESafeData {
  return try "\(name.description): \(value)".mimeEncodedData(using: encoding) + .CRLF
}

private extension DataProtocol {
  func _addingPercentEncoding() -> Data {
    let hex: [UInt8] = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
                        0x38, 0x39, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46]
    var result = Data()
    for byte in self {
      switch byte {
      case 0x24, // $
           0x2D...0x2E, // -.
           0x30...0x39, // 0-9
           0x40, // @
           0x41...0x5A, // A-Z
           0x5F, // _
           0x61...0x7A, // a-z
           0x7E: // ~
        result.append(byte)
      default:
        result.append(0x25) // %
        result.append(hex[Int(byte >> 4)])
        result.append(hex[Int(byte & 0x0F)])
      }
    }
    return result
  }
}

private extension String {
  var _quoted: String? {
    var result = "\""
    for scalar in unicodeScalars {
      guard 0x20 <= scalar.value && scalar.value < 0x7F else {
        return nil
      }
      switch scalar {
      case "\"", "\\":
        result += "\\\(scalar)"
      default:
        result += "\(scalar)"
      }
    }
    result += "\""
    return result
  }
}

/// Returns the encoded data with the method defined in
/// [RFC2231](https://tools.ietf.org/html/rfc2231).
internal func _mimeEncodedParameter(
  name: String,
  value: String,
  encoding: String.Encoding,
  locale: Locale? = nil
) throws -> MIMESafeData {
  assert(name.allSatisfy(\.isASCII))

  let nameCount = name.count
  let nPerLine = 75

  if value.consists(of: .mimeTypeTokenAllowed) &&
      nameCount + 1 + value.count < nPerLine {
    return try " \(name)=\(value)".mimeSafeData(using: ._7bit, stringEncoding: .utf8)
  } else if let quoted = value._quoted,
            quoted.compareCount(with: nPerLine - nameCount - 1) == .orderedAscending {
    return try " \(name)=\(quoted)".mimeSafeData(using: ._7bit, stringEncoding: .utf8)
  }

  guard let charset = encoding.ianaCharacterSetName else {
    throw MIMEEncodingError.noCharacterSetName
  }
  let langTag = locale?.languageCode ?? ""

  let firstLine = MIMESafeData(
    _mimeSafeBytes: Data((encoding == .ascii ? " \(name)*0=" : " \(name)*0*=\(charset)'\(langTag)'").utf8)
  )
  var lines: [MIMESafeData] = [firstLine]
  func __newLine() {
    lines.append(
      MIMESafeData(
        _mimeSafeBytes: Data((encoding == .ascii ? " \(name)*\(lines.count)=" : " \(name)*\(lines.count)*=").utf8)
      )
    )
  }

  var restOfScalars = ArraySlice<Unicode.Scalar>(value.unicodeScalars)

  while !restOfScalars.isEmpty, let lastLine = lines.last {
    let maxByteCount = nPerLine - lastLine.count
    let (scalarsToBeInThisLine, scalarsToBeNextLine) = restOfScalars._split(
      at: try restOfScalars._endIndex(
        withinMaxByteCount: maxByteCount,
        incrementable: encoding._dataSizeIsIncrementable,
        countWhenEncoded: {
          guard let rawStringData = String(String.UnicodeScalarView($0)).data(using: encoding) else {
            throw MIMEEncodingError.dataConversionFailure
          }
          return rawStringData._addingPercentEncoding().count
        }
      )
    )
    if scalarsToBeInThisLine.isEmpty {
      __newLine()
      continue
    }

    guard let percentEncoded = String(String.UnicodeScalarView(scalarsToBeInThisLine)).data(using: encoding)?._addingPercentEncoding() else {
      throw MIMEEncodingError.percentEncodingFailure
    }
    let encodedData = MIMESafeData(_mimeSafeBytes: percentEncoded)
    lines._replaceLastElement(with: lastLine + encodedData)
    restOfScalars = scalarsToBeNextLine
  }

  var result = MIMESafeData()
  for line in lines.dropLast() {
    result += line
    result.append(0x3B) // ";"
    result += .CRLF
  }
  result += lines.last!
  return result
}

private func _mimeEncodedHeaderField(
  name: MailMessage.Header.Name,
  coreValue: String,
  parameters: [String: String]?,
  encoding: String.Encoding
) throws -> MIMESafeData {
  guard let parameters = parameters else {
    return try _mimeEncodedHeaderField(name: name, value: coreValue, encoding: encoding)
  }

  var result = try "\(name.description): \(coreValue)".mimeSafeData(using: ._7bit, stringEncoding: .utf8)

  let parameterPairs = parameters.sorted(by: { $0.key < $1.key })
  var ii = 0
  while ii < parameterPairs.count {
    let (name, value) = parameterPairs[ii]
    assert(name.consists(of: .mimeTypeTokenAllowed))
    let nameCount = name.count
    if value.consists(of: .mimeTypeTokenAllowed) &&
        result.count + 2 + nameCount + 1 + value.count < 76 {
      result += try "; \(name)=\(value)".mimeSafeData(using: ._7bit, stringEncoding: .utf8)
    } else if let quoted = value._quoted,
              quoted.compareCount(with: 76 - result.count - 2 - nameCount - 1) == .orderedAscending {
      result += try "; \(name)=\(quoted)".mimeSafeData(using: ._7bit, stringEncoding: .utf8)
    } else {
      break
    }
    ii += 1
  }

  for jj in ii..<parameterPairs.count {
    let (name, value) = parameterPairs[jj]
    result.append(0x3B) // ";"
    result += .CRLF
    result += try _mimeEncodedParameter(name: name, value: value, encoding: encoding)
  }
  result += .CRLF

  return result
}

internal func _mimeEncodedContentTypeHeaderField(
  _ contentType: MIMEType,
  encoding: String.Encoding
) throws -> MIMESafeData {
  let coreType = MIMEType(
    type: contentType.type,
    tree: contentType.tree,
    subtype: contentType.subtype,
    suffix: contentType.suffix,
    parameters: nil
  )!
  return try _mimeEncodedHeaderField(
    name: .contentType,
    coreValue: coreType.description,
    parameters: contentType.parameters,
    encoding: encoding
  )
}

internal func _mimeEncodedContentDispositionHeaderField(
  _ disposition: ContentDisposition,
  encoding: String.Encoding
) throws -> MIMESafeData {
  return try _mimeEncodedHeaderField(
    name: .contentDisposition,
    coreValue: disposition.value.rawValue,
    parameters: disposition.parameters?.reduce(into: [:], { $0[$1.key.rawValue] = $1.value }),
    encoding: encoding
  )
}
