/* *************************************************************************************************
 Body.swift
   © 2021,2024 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */

import Foundation
import NetworkGear
import XHTML

/// A type that can be a body of mail message.
public protocol Body {
  /// "Content-Type" of the body.
  var contentType: MIMEType { get }

  /// "Content-Transfer-Encoding" that is used when encode the body content.
  var contentTransferEncoding: ContentTransferEncoding { get }

  /// The content representation.
  var content: Result<MIMESafeInputStream, Error> { get }
}

/// A type that can be a main part of mail message's body.
/// Conforming types are expected to be `PlainText` and `RichText`.
public protocol MainBody: Body {
  var stringEncoding: String.Encoding { get }
}

/// Represents plain text.
public struct PlainText: MainBody, Sendable {
  /// The mail message.
  public let text: String

  public let stringEncoding: String.Encoding

  public var contentType: MIMEType {
    guard let charset = stringEncoding.ianaCharacterSetName else {
      fatalError("Cannot recognize the string encoding.")
    }
    return MIMEType(
      type: .text,
      tree: nil,
      subtype: "plain",
      suffix: nil,
      parameters: [
        "charset": charset
      ]
    )!
  }

  public let contentTransferEncoding: ContentTransferEncoding

  public var content: Result<MIMESafeInputStream, Error> {
    return Result<MIMESafeInputStream, Error> {
      return MIMESafeDataStream(
        try text.mimeSafeData(using: contentTransferEncoding, stringEncoding: stringEncoding)
      )
    }
  }

  public init(
    text: String,
    stringEncoding: String.Encoding = .utf8,
    contentTransferEncoding: ContentTransferEncoding = .base64
  ) {
    self.text = text
    self.stringEncoding = stringEncoding
    self.contentTransferEncoding = contentTransferEncoding
  }
}

private extension PlainText {
  func _stream() throws -> MIMESafeInputStream {
    return MIMESafeInputSequenceStream([
      MIMESafeDataStream(
        try _mimeEncodedContentTypeHeaderField(contentType, encoding: stringEncoding)
      ),
      MIMESafeDataStream(
        try _mimeEncodedHeaderField(
          name: .contentTransferEncoding,
          value: contentTransferEncoding.rawValue,
          encoding: stringEncoding
        )
      ),
      MIMESafeDataStream(.CRLF),
      LazyMIMESafeInputStream { try content.get() },
    ] as [MIMESafeInputStream])
  }
}

/// Represents plain text.
public struct RichText: MainBody {
  public var plainText: PlainText

  public struct HTMLContent {
    public var htmlString: String

    public var resources: [File]

    public var stringEncoding: String.Encoding

    public var contentTransferEncoding: ContentTransferEncoding

    public internal(set) var boundary: String

    public var contentType: MIMEType {
      guard let charset = stringEncoding.ianaCharacterSetName else {
        fatalError("Cannot recognize the string encoding.")
      }
      // I don't know why
      // `application/xhtml+xml` cannot be used even if `htmlString` is marked up with XHTML.
      return MIMEType(
        type: .text,
        subtype: "html",
        parameters: [
          "charset": charset
        ]
      )!
    }

    public init(
      htmlString: String,
      resources: [File] = [],
      stringEncoding: String.Encoding = .utf8,
      contentTransferEncoding: ContentTransferEncoding = .quotedPrintable
    ) {
      self.htmlString = htmlString
      self.resources = resources
      self.stringEncoding = stringEncoding
      self.contentTransferEncoding = contentTransferEncoding
      self.boundary = _randomBoundary()
    }

    public init(
      xhtml: XHTMLDocument,
      resources: [File] = [],
      contentTransferEncoding: ContentTransferEncoding = .quotedPrintable
    ) {
      self.init(
        htmlString: xhtml.xhtmlString,
        resources: resources,
        stringEncoding: xhtml.prolog.stringEncoding,
        contentTransferEncoding: contentTransferEncoding
      )
    }

    fileprivate func _stream() throws -> MIMESafeInputStream {
      var streams: [MIMESafeInputStream] = []

      if !resources.isEmpty {
        let contentType = MIMEType(
          type: .multipart,
          subtype: "related",
          parameters: [
            "boundary": boundary,
            "type": "text/html",
          ]
        )!
        streams.append(
          MIMESafeDataStream(
            try _mimeEncodedContentTypeHeaderField(contentType, encoding: stringEncoding)
          )
        )
        streams.append(
          MIMESafeDataStream(
            try _mimeEncodedHeaderField(
              name: .contentTransferEncoding,
              value: contentTransferEncoding.rawValue,
              encoding: stringEncoding
            ) + .CRLF
          )
        )
        streams.append(
          MIMESafeDataStream(
            try "--\(boundary)".mimeSafeData(using: contentTransferEncoding, stringEncoding: stringEncoding) + .CRLF
          )
        )
      } // end of `!resources.isEmpty`

      streams.append(
        MIMESafeDataStream(
          try _mimeEncodedContentTypeHeaderField(contentType, encoding: stringEncoding)
        )
      )
      streams.append(
        MIMESafeDataStream(
          try _mimeEncodedHeaderField(
            name: .contentTransferEncoding,
            value: contentTransferEncoding.rawValue,
            encoding: stringEncoding
          )
        )
      )
      streams.append(MIMESafeDataStream(.CRLF))
      streams.append(LazyMIMESafeInputStream {
        MIMESafeDataStream(try htmlString.mimeSafeData(using: contentTransferEncoding, stringEncoding: stringEncoding))
      })

      if !resources.isEmpty {
        streams.append(MIMESafeDataStream(.CRLF))
        for resource in resources {
          streams.append(
            MIMESafeDataStream(
              try "--\(boundary)".mimeSafeData(using: contentTransferEncoding, stringEncoding: stringEncoding) + .CRLF
            )
          )
          streams.append(LazyMIMESafeInputStream { try resource._stream.get() })
        }
        streams.append(
          MIMESafeDataStream(
            try "--\(boundary)--".mimeSafeData(using: contentTransferEncoding, stringEncoding: stringEncoding) + .CRLF
          )
        )
      }

      return MIMESafeInputSequenceStream(streams)
    }
  }

  public var htmlContent: HTMLContent

  /// The boundary between each contents.
  /// See [RFC 2046 §5.1.1](https://tools.ietf.org/html/rfc2046#section-5.1.1).
  public internal(set) var boundary: String

  public var contentType: MIMEType {
    return MIMEType(
      type: .multipart,
      subtype: "alternative",
      parameters: [
        "boundary": boundary,
      ]
    )!
  }

  public var contentTransferEncoding: ContentTransferEncoding {
    return plainText.contentTransferEncoding
  }

  public var stringEncoding: String.Encoding {
    return plainText.stringEncoding
  }

  public init(
    plainText: PlainText,
    htmlContent: HTMLContent
  ) {
    self.plainText = plainText
    self.htmlContent = htmlContent
    self.boundary = _randomBoundary()
  }

  public var content: Result<MIMESafeInputStream, Error> {
    return Result<MIMESafeInputStream, Error> {
      var streams: [MIMESafeInputStream] = []

      streams.append(
        MIMESafeDataStream(try "--\(boundary)".mimeSafeData(using: ._7bit, stringEncoding: .utf8) + .CRLF)
      )
      streams.append(LazyMIMESafeInputStream { try plainText._stream() })
      streams.append(MIMESafeDataStream(.CRLF))
      streams.append(
        MIMESafeDataStream(try "--\(boundary)".mimeSafeData(using: ._7bit, stringEncoding: .utf8) + .CRLF)
      )
      streams.append(LazyMIMESafeInputStream { try htmlContent._stream() })
      streams.append(MIMESafeDataStream(.CRLF))
      streams.append(
        MIMESafeDataStream(try "--\(boundary)--".mimeSafeData(using: ._7bit, stringEncoding: .utf8) + .CRLF)
      )

      return MIMESafeInputSequenceStream(streams)
    }
  }
}

/// Represents a mail message with some attached files.
public struct FileAttachedBody: Body {
  public let mainBody: MainBody

  public let files: [File]

  /// The boundary between each contents.
  /// See [RFC 2046 §5.1.1](https://tools.ietf.org/html/rfc2046#section-5.1.1).
  public internal(set) var boundary: String

  public var contentType: MIMEType {
    return MIMEType(
      type: .multipart,
      subtype: "mixed",
      parameters: [
        "boundary": boundary,
      ]
    )!
  }

  public var contentTransferEncoding: ContentTransferEncoding {
    return mainBody.contentTransferEncoding
  }

  public var content: Result<MIMESafeInputStream, Error> {
    return Result<MIMESafeInputStream, Error> {
      let mainBodyStream = MIMESafeInputSequenceStream([
        MIMESafeDataStream(
          try _mimeEncodedContentTypeHeaderField(
            mainBody.contentType,
            encoding: mainBody.stringEncoding
          )
        ) as MIMESafeInputStream,
        MIMESafeDataStream(
          try _mimeEncodedHeaderField(
            name: .contentTransferEncoding,
            value: mainBody.contentTransferEncoding.rawValue,
            encoding: mainBody.stringEncoding
          )
        ),
        MIMESafeDataStream(.CRLF),
        LazyMIMESafeInputStream { try mainBody.content.get() }
      ])

      let attachmentsStream = MIMESafeInputSequenceStream(try files.map({ (file) throws-> MIMESafeInputStream  in
        return MIMESafeInputSequenceStream([
          MIMESafeDataStream(try "--\(boundary)".mimeSafeData(using: ._7bit, stringEncoding: .utf8) + .CRLF) as MIMESafeInputStream,
          LazyMIMESafeInputStream { try file._stream.get() },
        ])
      }))

      return MIMESafeInputSequenceStream([
        MIMESafeDataStream(try "This is a multi-part message in MIME format.".mimeEncodedData(using: .utf8) + .CRLF + .CRLF),
        MIMESafeDataStream(try "--\(boundary)".mimeSafeData(using: ._7bit, stringEncoding: .utf8) + .CRLF),
        mainBodyStream,
        MIMESafeDataStream(.CRLF),
        attachmentsStream,
        MIMESafeDataStream(try "--\(boundary)--".mimeSafeData(using: ._7bit, stringEncoding: .utf8) + .CRLF),
      ] as [MIMESafeInputStream])
    }
  }

  private init<Files>(
    _mainBody mainBody: MainBody,
    files: Files
  ) where Files: Sequence, Files.Element == File {
    self.mainBody = mainBody
    self.files = Array(files)
    self.boundary = _randomBoundary()
  }

  public init<Files>(mainBody: PlainText, files: Files) where Files: Sequence, Files.Element == File {
    self.init(_mainBody: mainBody, files: files)
  }

  public init<Files>(mainBody: RichText, files: Files) where Files: Sequence, Files.Element == File {
    self.init(_mainBody: mainBody, files: files)
  }
}

internal func _randomString(count: Int = 24) -> String {
  let bytes = [
    Array<UInt8>(0x30...0x39), // Numbers
    Array<UInt8>(0x41...0x5A), // Capital Letters
    Array<UInt8>(0x61...0x7A), // Small Letters
  ].flatMap({ $0 })
  return String(data: Data((0..<count).map({ _ in bytes.randomElement()! })), encoding: .utf8)!
}

internal func _randomBoundary(suffix: String = "--git.io/JOYPU", count: Int? = nil) -> String {
  return _randomString(count: (count ?? suffix.count + 24) - suffix.count) + suffix
}
