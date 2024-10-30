/* *************************************************************************************************
 MailAddress.swift
   © 2022-2024 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */

import NetworkGear
import Predicate
import Ranges
import yExtensions

// MARK: - Mail Address Parser

private extension Set where Element == Unicode.Scalar {
  init(_ closedRanges: ClosedRange<Unicode.Scalar>...) {
    self.init()
    for closedRange in closedRanges {
      for ii in closedRange.lowerBound.value...closedRange.upperBound.value {
        guard let scalar = Unicode.Scalar(ii) else { fatalError("Unexpected scalar value.") }
        self.insert(scalar)
      }
    }
  }
}

private extension Unicode.Scalar {
  var _isAvailableAnywhere: Bool {
    enum __Available {
      static let scalars = Set<Unicode.Scalar>("0"..."9", "A"..."Z", "a"..."z").union("!#$%&'*+-/=?^_`{|}~".unicodeScalars)
    }
    return __Available.scalars.contains(self)
  }

  var _isAvailableSymbolInQuote: Bool {
    enum __Available { static let scalars = Set<Unicode.Scalar>(". (),:;<>@[]".unicodeScalars) }
    return __Available.scalars.contains(self)
  }

  var _isAvailableSymbolFollowingBackslashInQuote: Bool {
    enum __Available { static let scalars = Set<Unicode.Scalar>("\"\\\u{20}\u{09}".unicodeScalars) }
    return __Available.scalars.contains(self)
  }

  var _isVisible: Bool {
    return ("\u{21}"..<"\u{7F}").contains(self)
  }

  var _isAvailableInIPAddressLiteral: Bool {
    enum __Available {
      static let scalars = Set<Unicode.Scalar>("0"..."9", "A"..."F", "a"..."f").union(".:IPv6".unicodeScalars)
    }
    return __Available.scalars.contains(self)
  }
}

public enum MailAddressParserError: Error, Equatable, Sendable {
  // MARK: - Lexer Errors

  case unterminatedQuotedString

  case invalidScalarInQuotedString

  case unterminatedIPAddressLiteral

  case invalidScalarInIPAddressLiteral

  case invalidIPAddressLiteral


  // MARK: - Preparser Errors

  case unbalancedParenthesis

  // MARK: - Parser Errors

  case tooLong

  case duplicateAtSigns

  case missingAtSign

  case missingLocalPart

  case missingDomain

  case invalidCommentPosition

  case invalidDomain

  case consecutiveDots

  case invalidDotPosition

  case invalidScalarInLocalPart

  case invalidQuotedStringPosition

  case tooLongLocalPart
}

private extension IPAddress {
  var _descriptionForMailAddress: String {
    switch self {
    case .v4:
      return "[\(self.description)]"
    case .v6:
      return "[IPv6:\(self.description)]"
    }
  }
}

private func _quotedStringDescription(_ content: String) -> String {
  var scalars = String.UnicodeScalarView()
  scalars.append("\"")
  for scalar in content.unicodeScalars {
    switch scalar {
    case "\\", "\"":
      scalars.append("\\")
      scalars.append(scalar)
    default:
      scalars.append(scalar)
    }
  }
  scalars.append("\"")
  return String(scalars)
}

internal class MailAddressToken {
  class OpenComment: MailAddressToken {}

  class CloseComment: MailAddressToken {}

  class Dot: MailAddressToken {}

  class AtSign: MailAddressToken {}

  class IPAddress: MailAddressToken {
    let ipAddress: NetworkGear.IPAddress

    var description: String {
      return ipAddress._descriptionForMailAddress
    }

    init(_ ipAddress: NetworkGear.IPAddress) {
      self.ipAddress = ipAddress
    }
  }

  class PlainText: MailAddressToken {
    fileprivate(set) var scalars: String.UnicodeScalarView

    var text: String {
      return String(scalars)
    }

    fileprivate init(_ scalar: Unicode.Scalar) {
      self.scalars = .init([scalar])
    }

    internal init(_ scalars: String.UnicodeScalarView) {
      self.scalars = scalars
    }
  }

  class QuotedText: MailAddressToken {
    let content: String

    var description: String {
      return _quotedStringDescription(content)
    }
    
    internal init(_ content: String) {
      self.content = content
    }
  }
}

extension MailAddressToken {
  /// Split the given `string` into tokens as a mail address.
  ///
  /// Some characters may be omitted when they are not necessary for the address.
  static func tokenize(_ string: String) throws -> [MailAddressToken] {
    let scalars = string.unicodeScalars
    var index = scalars.startIndex
    var result: [MailAddressToken] = []

    func __next() { index = scalars.index(after: index) }

    scan_scalars: while index < scalars.endIndex {
      let scalar = scalars[index]

      // Quoted
      if scalar == "\"" {
        var content = String.UnicodeScalarView()
        var escaping = false

        consume_quoted: while index < scalars.endIndex {
          __next()
          guard index < scalars.endIndex else {
            throw MailAddressParserError.unterminatedQuotedString
          }
          let quotedScalar = scalars[index]
          if quotedScalar == "\\" {
            if !escaping {
              escaping = true
              continue consume_quoted
            }
          }
          if !escaping && quotedScalar == "\"" {
            result.append(MailAddressToken.QuotedText(String(content)))
            __next()
            continue scan_scalars
          }
          guard (
            quotedScalar._isAvailableAnywhere ||
            quotedScalar._isAvailableSymbolInQuote ||
            (escaping && quotedScalar._isAvailableSymbolFollowingBackslashInQuote) ||
            (escaping && quotedScalar._isVisible)
          ) else {
            throw MailAddressParserError.invalidScalarInQuotedString
          }
          content.append(quotedScalar)
          escaping = false
        }
      }

      // IP Address
      if scalar == "[" {
        var maybeIPAddress = String.UnicodeScalarView()
        consume_ip: while index < scalars.endIndex {
          __next()
          guard index < scalars.endIndex else {
            throw MailAddressParserError.unterminatedIPAddressLiteral
          }

          let scalarInIPAddressLiteral = scalars[index]
          if scalarInIPAddressLiteral == "]" {
            var v6 = false
            var maybeIPAddressDesc = String(maybeIPAddress)
            if maybeIPAddressDesc.hasPrefix("IPv6:") {
              maybeIPAddressDesc = String(maybeIPAddressDesc.dropFirst(5))
              v6 = true
            }
            guard let ipAddress = NetworkGear.IPAddress(string: maybeIPAddressDesc) else {
              throw MailAddressParserError.invalidIPAddressLiteral
            }
            if v6 {
              guard case .v6 = ipAddress else {
                throw MailAddressParserError.invalidIPAddressLiteral
              }
            }
            result.append(MailAddressToken.IPAddress(ipAddress))
            __next()
            continue scan_scalars
          }

          guard scalarInIPAddressLiteral._isAvailableInIPAddressLiteral else {
            throw MailAddressParserError.invalidScalarInIPAddressLiteral
          }
          maybeIPAddress.append(scalarInIPAddressLiteral)
        }
      }

      if scalar == "(" {
        result.append(MailAddressToken.OpenComment())
        __next()
        continue
      }

      if scalar == ")" {
        result.append(MailAddressToken.CloseComment())
        __next()
        continue
      }

      if scalar == "." {
        result.append(MailAddressToken.Dot())
        __next()
        continue
      }

      if scalar == "@" {
        result.append(MailAddressToken.AtSign())
        __next()
        continue
      }

      if let last = result.last, case let plainText as MailAddressToken.PlainText = last {
        plainText.scalars.append(scalar)
      } else {
        result.append(MailAddressToken.PlainText(scalar))
      }
      __next()
    }

    return result
  }
}

/// Abstract node for mail address.
///
/// This class exists for the purpose of debug.
internal class MailAddressSyntaxNode {
  class Comment: MailAddressSyntaxNode {
    private(set) var children: [MailAddressSyntaxNode]

    fileprivate override init() {
      self.children = []
    }

    fileprivate func append(_ text: String) {
      if let last = children.last, case let textToken as PlainText = last {
        textToken.text += text
      } else {
        children.append(PlainText(text))
      }
    }

    fileprivate func append(_ comment: Comment) {
      children.append(comment)
    }
  }

  class Dot: MailAddressSyntaxNode {}

  class AtSign: MailAddressSyntaxNode {}

  class IPAddress: MailAddressSyntaxNode {
    let ipAddress: NetworkGear.IPAddress

    var description: String {
      return ipAddress._descriptionForMailAddress
    }

    fileprivate init(_ ipAddress: NetworkGear.IPAddress) {
      self.ipAddress = ipAddress
    }
  }

  class PlainText: MailAddressSyntaxNode {
    fileprivate(set) var text: String

    fileprivate init(_ text: String) {
      self.text = text
    }
  }

  class QuotedText: MailAddressSyntaxNode {
    let content: String

    fileprivate init(_ content: String) {
      self.content = content
    }
  }
}

extension MailAddressSyntaxNode {
  internal static func parse(_ tokens: [MailAddressToken]) throws -> [MailAddressSyntaxNode] {
    var result: [MailAddressSyntaxNode] = []

    var index = 0
    scan_tokens: while index < tokens.count {
      func __parseComment() throws -> Comment {
        guard index < tokens.count else {
          throw MailAddressParserError.unbalancedParenthesis
        }

        let token = tokens[index]
        assert(token is MailAddressToken.OpenComment)

        let comment = Comment()
        consume_comment: while index < tokens.count {
          index += 1
          guard index < tokens.count else {
            throw MailAddressParserError.unbalancedParenthesis
          }

          let token = tokens[index]
          switch token {
          case is MailAddressToken.CloseComment:
            break consume_comment
          case is MailAddressToken.OpenComment:
            comment.append(try __parseComment())
            continue consume_comment
          case is MailAddressToken.Dot:
            comment.append(".")
            continue consume_comment
          case is MailAddressToken.AtSign:
            comment.append("@")
            continue consume_comment
          case let ipAddressToken as MailAddressToken.IPAddress:
            comment.append(ipAddressToken.description)
            continue consume_comment
          case let plainTextToken as MailAddressToken.PlainText:
            comment.append(plainTextToken.text)
            continue consume_comment
          case let quotedTextToken as MailAddressToken.QuotedText:
            comment.append(quotedTextToken.description)
            continue consume_comment
          default:
            fatalError("Unimplemented Token.")
          }
        }
        return comment
      }

      let token = tokens[index]
      switch token {
      case is MailAddressToken.OpenComment:
        result.append(try __parseComment())
      case is MailAddressToken.CloseComment:
        throw MailAddressParserError.unbalancedParenthesis
      case is MailAddressToken.Dot:
        result.append(Dot())
      case is MailAddressToken.AtSign:
        result.append(AtSign())
      case let ipAddressToken as MailAddressToken.IPAddress:
        result.append(IPAddress(ipAddressToken.ipAddress))
      case let plainTextToken as MailAddressToken.PlainText:
        if let last = result.last, case let lastText as MailAddressSyntaxNode.PlainText = last {
          lastText.text += plainTextToken.text
        } else {
          result.append(PlainText(plainTextToken.text))
        }
      case let quotedTextToken as MailAddressToken.QuotedText:
        result.append(QuotedText(quotedTextToken.content))
      default:
        fatalError("Unimplemented Token.")
      }
      index += 1
    }

    return result
  }
}

// MARK: - Main Part

/// Represents a mail address based on [RFC 7504](https://www.rfc-editor.org/info/rfc7504) and
/// [RFC6854](https://www.rfc-editor.org/info/rfc6854).
public struct MailAddress: Equatable, Hashable, LosslessStringConvertible, Sendable {
  public enum DomainPart: Equatable, Hashable, LosslessStringConvertible, Sendable {
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

  private init(_validatedLocalPart: String, domain: DomainPart) {
    self.localPart = _validatedLocalPart
    self.domain = domain
  }

  /// Parse the given `string` as a mail address. Comments will be removed.
  /// An instance of `MailAddressParserError` may be thrown
  /// if there is an error to parse the string.
  public static func parse(_ string: String) throws -> MailAddress {
    guard string.unicodeScalars.compareCount(with: 255) == .orderedAscending else {
      throw MailAddressParserError.tooLong
    }

    let nodes = try MailAddressSyntaxNode.parse(MailAddressToken.tokenize(string))

    // First, search the position to split the address into local-part and domain.
    var indexOfAtSign: Int? = nil
    for ii in 0..<nodes.count {
      if nodes[ii] is MailAddressSyntaxNode.AtSign {
        guard indexOfAtSign == nil else {
          throw MailAddressParserError.duplicateAtSigns
        }
        indexOfAtSign = ii
      }
    }
    guard let indexOfAtSign else {
      throw MailAddressParserError.missingAtSign
    }
    guard indexOfAtSign > 0 else {
      throw MailAddressParserError.missingLocalPart
    }
    guard indexOfAtSign < nodes.count - 1 else {
      throw MailAddressParserError.missingDomain
    }

    var localPartNodes: ArraySlice<MailAddressSyntaxNode> = nodes[..<indexOfAtSign]
    var domainPartNodes: ArraySlice<MailAddressSyntaxNode> = nodes[(indexOfAtSign + 1)...]

    func __trimComments(_ nodes: inout ArraySlice<MailAddressSyntaxNode>) {
      if nodes.first is MailAddressSyntaxNode.Comment {
        nodes = nodes.dropFirst()
      }
      if nodes.last is MailAddressSyntaxNode.Comment {
        nodes = nodes.dropLast()
      }
    }

    __trimComments(&localPartNodes)
    if localPartNodes.isEmpty {
      throw MailAddressParserError.missingLocalPart
    }

    __trimComments(&domainPartNodes)
    if domainPartNodes.isEmpty {
      throw MailAddressParserError.missingDomain
    }

    if localPartNodes.contains(where: { $0 is MailAddressSyntaxNode.Comment }) ||
       domainPartNodes.contains(where: { $0 is MailAddressSyntaxNode.Comment }) {
      throw MailAddressParserError.invalidCommentPosition
    }

    // Validate DOMAIN PART

    let domainPart: DomainPart = try ({
      if domainPartNodes.count == 1 {
        if case let ipAddressNode as MailAddressSyntaxNode.IPAddress = domainPartNodes.first {
          return .ipAddress(ipAddressNode.ipAddress)
        }
        if case let plainTextNode as MailAddressSyntaxNode.PlainText = domainPartNodes.first {
          guard let domain = Domain(plainTextNode.text) else {
            throw MailAddressParserError.invalidDomain
          }
          return .domain(domain)
        }
        throw MailAddressParserError.invalidDomain
      }

      var domainDesc = ""
      for node in domainPartNodes {
        if node is MailAddressSyntaxNode.Dot {
          if domainDesc.isEmpty {
            throw MailAddressParserError.invalidDomain
          }
          if domainDesc.hasSuffix(".") {
            throw MailAddressParserError.consecutiveDots
          }
          domainDesc += "."
        } else if case let plainTextNode as MailAddressSyntaxNode.PlainText = node {
          domainDesc += plainTextNode.text
        } else {
          throw MailAddressParserError.invalidDomain
        }
      }
      guard let domain = Domain(domainDesc) else {
        throw MailAddressParserError.invalidDomain
      }
      return .domain(domain)
    })()


    // Validate LOCAL PART

    let localPart: String = try ({
      if localPartNodes.first is MailAddressSyntaxNode.Dot ||
         localPartNodes.last is MailAddressSyntaxNode.Dot  {
        throw MailAddressParserError.invalidDotPosition
      }

      var localPart = ""

      for ii in localPartNodes.startIndex..<localPartNodes.endIndex {
        let node = localPartNodes[ii]

        func __prevNode() -> MailAddressSyntaxNode? {
          guard ii > localPartNodes.startIndex else {
            return nil
          }
          return localPartNodes[localPartNodes.index(before: ii)]
        }

        func __nextNode() -> MailAddressSyntaxNode? {
          let nextIndex = localPartNodes.index(after: ii)
          guard nextIndex < localPartNodes.endIndex else {
            return nil
          }
          return localPartNodes[nextIndex]
        }

        switch node {
        case is MailAddressSyntaxNode.Dot:
          if __nextNode() is MailAddressSyntaxNode.Dot {
            throw MailAddressParserError.consecutiveDots
          }
          localPart += "."
        case is MailAddressSyntaxNode.IPAddress:
          throw MailAddressParserError.invalidScalarInLocalPart
        case let plainTextNode as MailAddressSyntaxNode.PlainText:
          let text = plainTextNode.text
          guard text.unicodeScalars.allSatisfy(\._isAvailableAnywhere) else {
            throw MailAddressParserError.invalidScalarInLocalPart
          }
          localPart += text
        case let quotedTextNode as MailAddressSyntaxNode.QuotedText:
          let prevNode = __prevNode()
          guard prevNode == nil || prevNode is MailAddressSyntaxNode.Dot else {
            throw MailAddressParserError.invalidQuotedStringPosition
          }
          let nextNode = __nextNode()
          guard nextNode == nil || nextNode is MailAddressSyntaxNode.Dot else {
            throw MailAddressParserError.invalidQuotedStringPosition
          }

          let text = quotedTextNode.content
          if text.unicodeScalars.allSatisfy(\._isAvailableAnywhere) {
            localPart += text
          } else {
            localPart += _quotedStringDescription(text)
          }
        default:
          fatalError("Unexpected node.")
        }
      }

      guard localPart.unicodeScalars.compareCount(with: 65) == .orderedAscending else {
        throw MailAddressParserError.tooLongLocalPart
      }

      return localPart
    })()

    return .init(_validatedLocalPart: localPart, domain: domainPart)
  }

  /// Initializes with the given string removing comments.
  /// Returns `nil` if it is invalid for a mail address.
  ///
  /// Use `MailAddress.parse` if you want to know _why_ the address is invalid.
  public init?(_ string: String) {
    guard let instance = try? MailAddress.parse(string) else {
      return nil
    }
    self = instance
  }
}
