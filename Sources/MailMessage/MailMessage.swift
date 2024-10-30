/* *************************************************************************************************
 MailMessage.swift
   © 2021 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */

import Foundation
import NetworkGear

/// Represents entire mail message
@dynamicMemberLookup
public struct MailMessage {
  public struct Header: Sequence, Sendable {
    // At first, I was considering using `HTTPHeader` in `NetworkGear` module.
    // It validates, however, strictly its value.
    // I gave up and implement original `Header` for that reason.

    public struct Name: Equatable,
                        Comparable,
                        Hashable,
                        ExpressibleByStringLiteral,
                        CustomStringConvertible,
                        Sendable {
      /// "From"
      public static let from: Name = "From"

      /// "Sender"
      public static let sender: Name = "Sender"

      /// "Reply-To"
      public static let replyTo: Name = "Reply-To"

      /// "To"
      public static let to: Name = "To"

      /// "Cc"
      public static let cc: Name = "Cc"

      /// "Bcc"
      public static let bcc: Name = "Bcc"

      /// "Subject"
      public static let subject: Name = "Subject"

      /// "Content-Disposition"
      public static let contentDisposition: Name = "Content-Disposition"

      /// "Content-ID"
      public static let contentID: Name = "Content-ID"

      /// "Content-Type"
      public static let contentType: Name = "Content-Type"

      /// "Content-Transfer-Encoding"
      public static let contentTransferEncoding: Name = "Content-Transfer-Encoding"

      /// "MIME-Version"
      public static let mimeVersion: Name = "MIME-Version"

      /// "X-Mailer"
      public static let mailer: Name = "X-Mailer"

      /// "In-Reply-To"
      public static let inReplyTo: Name = "In-Reply-To"

      /// Original description.
      private let _originalString: String

      /// Description in lower case.
      private let _lowercased: String

      public var description: String {
        return _originalString
      }

      public static func ==(lhs: Name, rhs: Name) -> Bool {
        return lhs._lowercased == rhs._lowercased
      }

      public static func <(lhs: Name, rhs: Name) -> Bool {
        return lhs._lowercased < rhs._lowercased
      }

      public func hash(into hasher: inout Hasher) {
        hasher.combine(_lowercased)
      }

      public init(_ string: String) {
        _originalString = string
        _lowercased = string.lowercased()
      }

      public init(stringLiteral: String) {
        self.init(stringLiteral)
      }
    }

    fileprivate var _fields: [Name: String]

    public typealias Iterator = Dictionary<Name, String>.Iterator

    public func makeIterator() -> Dictionary<Name, String>.Iterator {
      return _fields.makeIterator()
    }

    public fileprivate(set) subscript(_ name: Name) -> String? {
      get {
        return _fields[name]
      }
      set {
        _fields[name] = newValue
      }
    }

    public init() {
      _fields = [:]
    }

    private func _get<T>(_ type: T.Type, forName name: Name) -> T? where T: LosslessStringConvertible {
      guard let value = self[name].flatMap(T.init) else {
        return nil
      }
      return value
    }

    private func _get<T>(_ type: T.Type, forName name: Name) -> T? where T: _LosslessStringConvertible {
      guard let value = self[name].flatMap(T.init) else {
        return nil
      }
      return value
    }

    private func _get<T>(_ type: T.Type, forName name: Name) -> T? where T: RawRepresentable, T.RawValue: LosslessStringConvertible {
      guard let value = self[name].flatMap(T.RawValue.init).flatMap(T.init) else {
        return nil
      }
      return value
    }

    private mutating func _set<T>(_ value: T?, forName name: Name) where T: CustomStringConvertible {
      self[name] = value?.description
    }

    private mutating func _set<T>(_ value: T?, forName name: Name) where T: RawRepresentable, T.RawValue: LosslessStringConvertible {
      self[name] = value?.rawValue.description
    }

    /// The value of "MIME-Version" header field.
    /// Only "1.0" is valid.
    public var mimeVersion: String? {
      get {
        _get(String.self, forName: .mimeVersion)
      }
      set {
        _set(newValue != nil ? "1.0" : nil, forName: .mimeVersion)
      }
    }

    /// The value of "From" header field.
    public var author: Person? {
      get {
        _get(Person.self, forName: .from)
      }
      set {
        _set(newValue, forName: .from)
      }
    }

    /// The value of "Sender" header field.
    public var sender: Person? {
      get {
        _get(Person.self, forName: .sender)
      }
      set {
        _set(newValue, forName: .sender)
      }
    }

    /// The value of "Reply-To" header field.
    public var returnAddress: Person? {
      get {
        _get(Person.self, forName: .replyTo)
      }
      set {
        _set(newValue, forName: .replyTo)
      }
    }

    /// The value of "To" header field.
    public var recipients: Group? {
      get {
        _get(Group.self, forName: .to)
      }
      set {
        _set(newValue, forName: .to)
      }
    }

    /// The value of "Cc" header field.
    public var carbonCopyRecipients: Group? {
      get {
        _get(Group.self, forName: .cc)
      }
      set {
        _set(newValue, forName: .cc)
      }
    }

    /// The value of "Bcc" header field.
    public var blindCarbonCopyRecipients: Group? {
      get {
        _get(Group.self, forName: .bcc)
      }
      set {
        _set(newValue, forName: .bcc)
      }
    }

    /// The value of "Subject" header field.
    public var subject: String? {
      get {
        _get(String.self, forName: .subject)
      }
      set {
        _set(newValue, forName: .subject)
      }
    }

    @available(*, unavailable, message: "Content-Transfer-Encoding can't be specified here. Use `Body`'s property instead.")
    public var contentTransferEncoding: ContentTransferEncoding? {
      get {
        fatalError()
      }
      set {
        fatalError()
      }
    }

    @available(*, unavailable, message: "Content-Type can't be specified here. Use `Body`'s property instead.")
    public var contentType: MIMEType? {
      get {
        fatalError()
      }
      set {
        fatalError()
      }
    }

    /// The value of "In-Reply-To" header field.
    public var referenceMessageID: String? {
      get {
        _get(String.self, forName: .inReplyTo)
      }
      set {
        _set(newValue, forName: .inReplyTo)
      }
    }

    /// The value of "X-Mailer" header field.
    public var mailer: String? {
      get {
        _get(String.self, forName: .mailer)
      }
      set {
        _set(newValue, forName: .mailer)
      }
    }

    /// Returns the Boolean value that indicates whether or not the header has recipients:
    /// "To", "Cc", or "Bcc".
    public var hasRecipients: Bool {
      return recipients != nil || carbonCopyRecipients != nil || blindCarbonCopyRecipients != nil
    }
  }

  public var header: Header

  /// The message body
  public var body: Body

  public subscript<T>(dynamicMember key: KeyPath<Header, T>) -> T {
    return header[keyPath: key]
  }

  public subscript<T>(dynamicMember key: WritableKeyPath<Header, T>) -> T {
    get {
      return header[keyPath: key]
    }
    set {
      header[keyPath: key] = newValue
    }
  }

  public init(
    author: Person? = nil,
    sender: Person? = nil,
    returnAddress: Person? = nil,
    recipients: Group?,
    carbonCopyRecipients: Group? = nil,
    blindCarbonCopyRecipients: Group? = nil,
    subject: String?,
    body: Body
  ) {
    self.header = .init()
    self.header.author = author
    self.header.sender = sender
    self.header.returnAddress = returnAddress
    self.header.recipients = recipients
    self.header.carbonCopyRecipients = carbonCopyRecipients
    self.header.blindCarbonCopyRecipients = blindCarbonCopyRecipients
    self.header.subject = subject

    self.body = body
  }
}

extension MailMessage {
  public enum Error: Swift.Error {
    case dataConversionFailure
    case invalidContentTransferEncoding
    case noCharacterSetName
    case noDataWrittenToStream
    case noRecipients
  }

  /// Write the `MIMESafeData` that can be deliverable with a mailer.
  /// - parameter output: A steam that the data will be written to.
  /// - parameter encoding: String encoding that is used to encode the message header fields in "MIME Encode".
  ///
  /// Note: Once this method is called, some streams may come to have no available bytes.
  ///
  /// You can pass it to `sendmail` with a pipe.
  /// You can also use it with [Gmail API Message](https://developers.google.com/gmail/api/reference/rest/v1/users.messages#Message)
  /// after the output is Base64 encoded.
  public func writeDeliverableData(to output: OutputStream, using encoding: String.Encoding = .utf8) throws {
    guard self.hasRecipients else {
      throw Error.noRecipients
    }

    // "common" HEADER Fields
    do {
      func __sorter(
        pair1: (key: Header.Name, value: String),
        pair2: (key: Header.Name, value: String)
      ) -> Bool {
        // Make the tests simple
        let precedence: [Header.Name: Int] = [
          .from: 0,
          .to: 1,
          .cc: 2,
          .bcc: 3,
          .subject: 4,
          .mimeVersion: 5,
          .mailer: 6,
        ]
        switch (precedence[pair1.key], precedence[pair2.key]) {
        case (nil, nil):
          return pair1.key < pair2.key
        case (nil, _):
          return false
        case (_, nil):
          return true
        case (let prec1?, let prec2?):
          return prec1 < prec2
        }
      }
      for (name, value) in header._fields.sorted(by: __sorter) {
        try output.write(_mimeEncodedHeaderField(name: name, value: value, encoding: encoding))
      }
    }

    // Header fields related to the content
    do {
      try output.write(_mimeEncodedContentTypeHeaderField(body.contentType, encoding: encoding))
      try output.write(
        _mimeEncodedHeaderField(
          name: .contentTransferEncoding,
          value: body.contentTransferEncoding.rawValue,
          encoding: encoding
        )
      )
    }

    try output.write(.CRLF) // End of Header

    var contentStream = try body.content.get()
    while let bytes = try contentStream.nextFragment() {
      try output.write(bytes)
    }
  }

  /// Returns the data that some deliverable data written to.
  /// See the explanation of `writeDeliverableData(to:using:)`.
  public func deliverableData(using encoding: String.Encoding = .utf8) throws -> MIMESafeData {
    let memory = OutputStream.toMemory()
    memory.open()
    defer { memory.close() }
    try writeDeliverableData(to: memory, using: encoding)

    guard case let data as Data = memory.property(forKey: .dataWrittenToMemoryStreamKey),
          let safeData = MIMESafeData(data: data) else {
      throw Error.noDataWrittenToStream
    }
    return safeData
  }

  /// Shortcut for `String(data: try deliverableData(using: encoding))`.
  /// See the explanation of `deliverableData(using:)`.
  public func deliverableDescription(using encoding: String.Encoding = .utf8) throws -> String {
    return String(data: try deliverableData(using: encoding))
  }
}


// MARK: - Helpers

private protocol _LosslessStringConvertible {
  init?<S>(_ string: S) where S: StringProtocol
  var description: String { get }
}

extension MIMEType: _LosslessStringConvertible {}
