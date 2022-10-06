/* *************************************************************************************************
 MailAddress.swift
   © 2022 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */

import BonaFideCharacterSet
import NetworkGear
import Predicate
import Ranges
import yExtensions

// MARK: - Local-part Validation

private func _removeComment<S>(_ string: S) -> Substring? where S: StringProtocol, S.SubSequence == Substring {
  if let open = string.firstIndex(of: "("), let close = string.lastIndex(of: ")") {
    switch (open, close) {
    case (string.startIndex, _):
      return string[string.index(after: close)...]
    case (_, string.index(before: string.endIndex)):
      return string[..<open]
    default:
      return nil
    }
  }
  return string[...]
}

private let _usableAnywhere: UnicodeScalarSet = UnicodeScalarSet(unicodeScalarsIn: "0"..."9")
  .union(.init(unicodeScalarsIn: "A"..."Z"))
  .union(.init(unicodeScalarsIn: "a"..."z"))
  .union(.init(unicodeScalarsIn: "!#$%&'*+-/=?^_`{|}~"))
private let _usableSymbolsInQuotes = UnicodeScalarSet(unicodeScalarsIn: " (),:;<>@[]")
private let _usableSymbolsFollowingBackslashInQuotes = UnicodeScalarSet(unicodeScalarsIn: "\"\\\u{20}\u{09}")
private let _VCHAR = UnicodeScalarSet(unicodeScalarsIn: "\u{21}"..<"\u{7F}")

/// Validate local-part.
///
/// Thanks to `@yoshitake_1201`'s article:
/// https://qiita.com/yoshitake_1201/items/40268332cd23f67c504c (Japanese).
private func _validateLocalPart(_ scalars: Substring.UnicodeScalarView) -> Bool {
  enum __Mode {
    case quoted
    case unquoted
  }

  func __validate(_ scalars: Substring.UnicodeScalarView, mode: __Mode) -> Bool {
    if scalars.isEmpty {
      return false
    }
    if mode == .unquoted && (scalars.first == "." || scalars.last == ".") {
      return false
    }

    var index = scalars.startIndex
    var escaping = false
    var ii = 0
    while index < scalars.endIndex {
      defer { index = scalars.index(after: index); ii += 1 }

      let scalar = scalars[index]

      if scalar == "\\" {
        guard mode == .quoted else { return false }
        escaping.toggle()
        continue
      }
      if escaping {
        assert(mode == .quoted)
        guard _usableSymbolsFollowingBackslashInQuotes.contains(scalar) || _VCHAR.contains(scalar) else {
          return false
        }
        escaping = false
        continue
      }

      if _usableAnywhere.contains(scalar) {
        continue
      }

      if scalar == "." {
        if mode == .quoted {
          continue
        }
        assert(index > scalars.startIndex)
        if scalars[scalars.index(before: index)] == "." {
          // Dot does not appear consecutively
          return false
        }
        continue
      }

      guard mode == .quoted else { return false }
      if _usableSymbolsInQuotes.contains(scalar) {
        continue
      }
      return false
    }
    return true
  }

  guard scalars.compareCount(with: 65) == .orderedAscending else {
    return false
  }

  if scalars.first == "\"" && scalars.last == "\"" {
    return __validate(
      scalars[scalars.index(after: scalars.startIndex)..<scalars.index(before: scalars.endIndex)],
      mode: .quoted
    )
  }
  return __validate(scalars, mode: .unquoted)
}

// MARK: - Main Part

/// Represents a mail address based on [RFC 7504](https://www.rfc-editor.org/info/rfc7504) and
/// [RFC6854](https://www.rfc-editor.org/info/rfc6854).
public struct MailAddress: Equatable, Hashable, LosslessStringConvertible {
  public enum DomainPart: Equatable, Hashable, LosslessStringConvertible {
    case domain(Domain)
    case ipAddress(IPAddress)

    public init?(_ description: String) {
      if description.hasPrefix("[") && description.hasSuffix("]") {
        if let ipAddress = IPAddress(string: String(description.dropFirst().dropLast())) {
          self = .ipAddress(ipAddress)
          return
        }
        guard description.hasPrefix("[IPv6:"),
              let ipAddress = IPAddress(string: String(description.dropFirst(6).dropLast())),
              case .v6 = ipAddress else {
          return nil
        }
        self = .ipAddress(ipAddress)
        return
      }

      guard let domain = Domain(description) else {
        return nil
      }
      self = .domain(domain)
    }

    public var description: String {
      switch self {
      case .domain(let domain):
        return domain.description
      case .ipAddress(let ipAddress):
        switch ipAddress {
        case .v4:
          return "[\(ipAddress.description)]"
        case .v6:
          return "[IPv6:\(ipAddress.description)]"
        }
      }
    }
  }

  public let localPart: String
  public let domain: DomainPart

  public var description: String {
    return "\(localPart)@\(domain.description)"
  }

  /// Initializes with the given string removing comments in `local-part`.
  /// Returns `nil` if it is invalid for a mail address.
  public init?(_ string: String) {
    guard string.compareCount(with: 255) == .orderedAscending else {
      return nil
    }
    guard let lastAtMark = string.lastIndex(of: "@") else {
      return nil
    }
    guard let domain = DomainPart(String(string[string.index(after: lastAtMark)...])) else {
      return nil
    }

    var localPartDesc = string[..<lastAtMark]
    if let commentRemoved = _removeComment(string[..<lastAtMark]) {
      localPartDesc = commentRemoved
    }
    guard _validateLocalPart(localPartDesc.unicodeScalars) else {
      return nil
    }

    self.domain = domain
    self.localPart = String(localPartDesc)
  }
}
