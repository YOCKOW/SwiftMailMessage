/* *************************************************************************************************
 File.swift
   © 2021 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */

import Foundation
import NetworkGear
import yExtensions

/// Represents "Content-ID" described in
/// [RFC 2045 §7](https://tools.ietf.org/html/rfc2045#section-7).
/// It consists of the same characters with "Message-ID" defined in
/// [RFC 5322 §3.6.4](https://tools.ietf.org/html/rfc5322#section-3.6.4).
public struct ContentID: RawRepresentable, Sendable {
  public typealias RawValue = String

  /// `dot-atom-text`
  private struct _DotAtomText {
    let rawValue: String

    init?<S>(rawValue: S) where S: StringProtocol {
      let scalars = rawValue.unicodeScalars
      var index = scalars.startIndex
      let lastIndex = scalars.index(before: scalars.endIndex)
      while true {
        if index >= scalars.endIndex {
          break
        }

        let scalar = scalars[index]
        let nextIndex = scalars.index(after: index)

        switch scalar {
        case ".":
          if index == scalars.startIndex || index == lastIndex || scalars[nextIndex] == "." {
            return nil
          }
        case "0"..."9", "A"..."Z", "a"..."z",
             "!", "#", "$", "%" , "&", "'", "*", "+", "-", "/",
             "=", "?", "^", "_", "`", "{", "|", "}", "~":
          break
        default:
          return nil
        }
        index = nextIndex
      }
      self.rawValue = String(rawValue)
    }
  }

  /// `no-fold-literal`
  private struct _NoFoldLiteral {
    let rawValue: String

    init?<S>(rawValue: S) where S: StringProtocol {
      let scalars = rawValue.unicodeScalars
      guard let first = scalars.first, first == "[", let last = scalars.last, last == "]" else {
        return nil
      }
      for scalar in scalars.dropFirst().dropLast() {
        switch scalar {
        case "!"..."Z", "^"..."~":
          break
        default:
          return nil
        }
      }
      self.rawValue = String(rawValue)
    }
  }

  private struct _LeftPart {
    private let _text: _DotAtomText

    var rawValue: String {
      return _text.rawValue
    }

    init?<S>(rawValue: S) where S: StringProtocol {
      guard let id = _DotAtomText(rawValue: rawValue) else { return nil }
      _text = id
    }
  }

  private struct _RightPart {
    private enum _Guts {
      case dotAtomText(_DotAtomText)
      case noFoldLiteral(_NoFoldLiteral)
    }

    private let _guts: _Guts

    var rawValue: String {
      switch _guts {
      case .dotAtomText(let text):
        return text.rawValue
      case .noFoldLiteral(let literal):
        return literal.rawValue
      }
    }

    init?<S>(rawValue: S) where S: StringProtocol {
      if let text = _DotAtomText(rawValue: rawValue) {
        self._guts = .dotAtomText(text)
      } else if let literal = _NoFoldLiteral(rawValue: rawValue) {
        self._guts = .noFoldLiteral(literal)
      } else {
        return nil
      }
    }
  }

  /// `left-id`
  private var _leftPart: _LeftPart

  /// `right-id`
  private var _rightPart: _RightPart

  public var rawValue: String {
    return "<" + _leftPart.rawValue + "@" + _rightPart.rawValue + ">"
  }

  private init(left: _LeftPart, right: _RightPart) {
    _leftPart = left
    _rightPart = right
  }

  /// Instantiates an instance of the content ID.
  ///
  /// Note:
  ///   This method doesn't support [CFWS](https://tools.ietf.org/html/rfc5322#section-3.2.2).
  public init?(rawValue: String) {
    guard rawValue.hasPrefix("<"),
          rawValue.hasSuffix(">"),
          case let (leftSideString, rightSideString?) =
            rawValue.dropFirst().dropLast().splitOnce(separator: "@"),
          let leftPart = _LeftPart(rawValue: leftSideString),
          let rightPart = _RightPart(rawValue: rightSideString) else {
      return nil
    }
    self.init(left: leftPart, right: rightPart)
  }

  public static func random() -> ContentID {
    return ContentID(
      left: _LeftPart(rawValue: UUID().base32EncodedString())!,
      right: _RightPart(rawValue: "git.io/JOYPU")!
    )
  }
}

/// Represents a file (stream).
/// This is usually used for an attachment in mail message.
public struct File {
  public var filename: String

  public var contentType: MIMEType

  /// The world-unique identifier for this file.
  public var contentID: ContentID

  public var content: InputStream

  public init(
    filename: String,
    contentType: MIMEType = MIMEType(type: .application, subtype: "octet-stream")!,
    contentID: ContentID = .random(),
    content: InputStream
  ) {
    self.filename = filename
    self.contentType = contentType
    self.contentID = contentID
    self.content = content
  }

  internal var _stream: Result<MIMESafeInputStream, Error> {
    return Result<MIMESafeInputStream, Error> {
      let contentDispotision = ContentDisposition(
        value: .attachment,
        parameters: [
          .filename: filename,
        ]
      )

      return MIMESafeInputSequenceStream([
        MIMESafeDataStream(
          try _mimeEncodedContentDispositionHeaderField(contentDispotision, encoding: .utf8)
        ),
        MIMESafeDataStream(try _mimeEncodedContentTypeHeaderField(contentType, encoding: .utf8)),
        MIMESafeDataStream(
          try _mimeEncodedHeaderField(
            name: .contentID,
            value: contentID.rawValue,
            encoding: .utf8
          )
        ),
        MIMESafeDataStream(
          try _mimeEncodedHeaderField(
            name: .contentTransferEncoding,
            value: ContentTransferEncoding.base64.rawValue,
            encoding: .utf8
          )
        ),
        MIMESafeDataStream(.CRLF),
        try ContentTransferEncodingStream(content, encoding: .base64),
      ] as [MIMESafeInputStream])
    }
  }
}
