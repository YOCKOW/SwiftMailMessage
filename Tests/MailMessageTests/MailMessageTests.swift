/* *************************************************************************************************
 MailMessageTests.swift
   © 2021,2024 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */

import Foundation
import NetworkGear
import XHTML
@testable import MailMessage

private let CRLF: String = "\u{0D}\u{0A}"
private let resourcesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources", isDirectory: true)

private extension MIMESafeInputStream {
  mutating func _availableData() throws -> MIMESafeData {
    var result = MIMESafeData()
    while let next = try nextFragment() {
      result.append(contentsOf: next)
    }
    return result
  }
}

#if swift(>=6) && canImport(Testing)
import Testing

@Suite final class MailMessageTests {
  @Test func test_mailAddressLexer() {
    func __assert(
      _ string: String,
      _ expected: [(MailAddressToken) -> Bool],
      expectedError: MailAddressParserError? = nil,
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      do {
        let tokens = try MailAddressToken.tokenize(string)
        guard tokens.count == expected.count else {
          Issue.record("Unexpected number of tokens.", sourceLocation: sourceLocation)
          return
        }
        for ii in 0..<tokens.count {
          let token = tokens[ii]
          #expect(expected[ii](token),  "Unexpected token at #\(ii): \(token)", sourceLocation: sourceLocation)
        }
      } catch let error {
        guard case let parserError as MailAddressParserError = error,
              let expectedError,
              parserError == expectedError else {
          Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
          return
        }
      }
    }

    func __isPlainText(_ token: MailAddressToken, _ expectedText: String) -> Bool {
      guard case let plainTextToken as MailAddressToken.PlainText = token else {
        return false
      }
      return plainTextToken.text == expectedText
    }

    func __isQuotedText(_ token: MailAddressToken, _ expectedText: String) -> Bool {
      guard case let quotedTextToken as MailAddressToken.QuotedText = token else {
        return false
      }
      return quotedTextToken.content == expectedText
    }

    func __isIPAddress(_ token: MailAddressToken, _ expectedIPAddress: IPAddress) -> Bool {
      guard case let ipAddressToken as MailAddressToken.IPAddress = token else {
        return false
      }
      return ipAddressToken.ipAddress == expectedIPAddress
    }

    __assert("(comment)", [
      { $0 is MailAddressToken.OpenComment },
      { __isPlainText($0, "comment") },
      { $0 is MailAddressToken.CloseComment },
    ])

    __assert("(comment ( nested comment @ here ))", [
      { $0 is MailAddressToken.OpenComment },
      { __isPlainText($0, "comment ") },
      { $0 is MailAddressToken.OpenComment },
      { __isPlainText($0, " nested comment ") },
      { $0 is MailAddressToken.AtSign },
      { __isPlainText($0, " here ") },
      { $0 is MailAddressToken.CloseComment },
      { $0 is MailAddressToken.CloseComment },
    ])

    __assert("[127.0.0.1]", [
      { __isIPAddress($0, .v4(127, 0, 0, 1)) },
    ])

    __assert("YOCKOW@(domain-side comment)[IPv6:2001:db8::1]", [
      {  __isPlainText($0, "YOCKOW")},
      { $0 is MailAddressToken.AtSign },
      { $0 is MailAddressToken.OpenComment },
      {  __isPlainText($0, "domain-side comment")},
      { $0 is MailAddressToken.CloseComment },
      { __isIPAddress($0, .v6(0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)) },
    ])

    __assert(#""..QUOTED.."."MORE"."ESCAPE\"\\""#, [
      { __isQuotedText($0, "..QUOTED..") },
      { $0 is MailAddressToken.Dot },
      { __isQuotedText($0, "MORE") },
      { $0 is MailAddressToken.Dot },
      { __isQuotedText($0, "ESCAPE\"\\") },
    ])

    __assert(#""NEVER ENDING STORY"#, [], expectedError: .unterminatedQuotedString)
    __assert(#""日本語""#, [], expectedError: .invalidScalarInQuotedString)
    __assert("foo@[IPv6:2001:db8::1", [], expectedError: .unterminatedIPAddressLiteral)
    __assert("foo@[127.0.0.X]", [], expectedError: .invalidScalarInIPAddressLiteral)
    __assert("foo@[999.0.0.0]", [], expectedError: .invalidIPAddressLiteral)
  }

  @Test func test_mailAddressPreparser() throws {
    func __parse(_ string: String) throws -> [MailAddressSyntaxNode] {
      return try MailAddressSyntaxNode.parse(MailAddressToken.tokenize(string))
    }

    nested_comment: do {
      let nodes = try __parse("(comment (nested@1) (nested@2))")
      guard nodes.count == 1 else {
        Issue.record("Unexpected number of nodes.")
        break nested_comment
      }
      guard case let commentNode as MailAddressSyntaxNode.Comment = nodes.first else {
        Issue.record("Unexpected node.")
        break nested_comment
      }
      guard commentNode.children.count == 4 else {
        Issue.record("Unexpected number of children.")
        break nested_comment
      }
      #expect(commentNode.children[0] is MailAddressSyntaxNode.PlainText)
      #expect(commentNode.children[1] is MailAddressSyntaxNode.Comment)
      #expect(commentNode.children[2] is MailAddressSyntaxNode.PlainText)
      #expect(commentNode.children[3] is MailAddressSyntaxNode.Comment)
      #expect(
        ((commentNode.children[3] as? MailAddressSyntaxNode.Comment)?.children.first as? MailAddressSyntaxNode.PlainText)?.text ==
        "nested@2"
      )
    }

    simple_address: do {
      let nodes = try __parse(#"YOCKOW@example.com"#)
      guard nodes.count == 5 else {
        Issue.record("Unexpected number of nodes.")
        break simple_address
      }
      #expect((nodes[0] as? MailAddressSyntaxNode.PlainText)?.text == "YOCKOW")
      #expect(nodes[1] is MailAddressSyntaxNode.AtSign)
      #expect((nodes[2] as? MailAddressSyntaxNode.PlainText)?.text == "example")
      #expect(nodes[3] is MailAddressSyntaxNode.Dot)
      #expect((nodes[4] as? MailAddressSyntaxNode.PlainText)?.text == "com")
    }

    #expect(throws: MailAddressParserError.unbalancedParenthesis) { try __parse("(foo (bar)") }
  }

  @Test func test_mailAddressParserError() {
    func __assert(
      _ string: String, expectedError: MailAddressParserError,
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      #expect(throws: expectedError, sourceLocation: sourceLocation) {
        try MailAddress.parse(string)
      }
    }

    __assert("a@" + String(repeating: "foo.", count: 70) + "com", expectedError: .tooLong)
    __assert("foo@bar@example.com", expectedError: .duplicateAtSigns)
    __assert("foo.bar.baz", expectedError: .missingAtSign)
    __assert("(comment)@example.com", expectedError: .missingLocalPart)
    __assert("foo@(comment)", expectedError: .missingDomain)
    __assert("foo(comment)bar@example.com", expectedError: .invalidCommentPosition)
    __assert("foo.bar@example.(comment)com", expectedError: .invalidCommentPosition)
    __assert("foo@----.com", expectedError: .invalidDomain)
    __assert("foo@example..com", expectedError: .consecutiveDots)
    __assert("foo..bar@example.com", expectedError: .consecutiveDots)
    __assert(".foo@example.com", expectedError: .invalidDotPosition)
    __assert("foo.@example.com", expectedError: .invalidDotPosition)
    __assert("foo,bar@example.com", expectedError: .invalidScalarInLocalPart)
    __assert(#""foo""bar"@example.com"#, expectedError: .invalidQuotedStringPosition)
    __assert(String(repeating: "foo", count: 30) + "@example.com", expectedError: .tooLongLocalPart)
  }

  @Test func test_mailAddress() {
    func __test_wholeAddress(
      _ string: String, isValid: Bool, sourceLocation: SourceLocation = #_sourceLocation
    ) {
      let maybeAddress = MailAddress(string)
      if isValid {
        #expect(maybeAddress != nil, "\(string) is expected to be valid.", sourceLocation: sourceLocation)
      } else {
        #expect(maybeAddress == nil, "\(string) is expected to be invalid.", sourceLocation: sourceLocation)
      }
    }

    func __test_localPart(
      _ localPart: String, isValid: Bool, sourceLocation: SourceLocation = #_sourceLocation
    ) {
      __test_wholeAddress("\(localPart)@example.com", isValid: isValid, sourceLocation: sourceLocation)
    }

    do { // https://qiita.com/yoshitake_1201/items/40268332cd23f67c504c
      __test_localPart("abcdefghijklmnopqrstuvwxyz", isValid: true)
      __test_localPart("ABCDEFGHIJKLMNOPQRSTUVWXYZ", isValid: true)
      __test_localPart("0123456789", isValid: true)
      __test_localPart("!#$%&'*+-/=?^_{|}~`", isValid: true)
      __test_localPart("a.b", isValid: true)
      __test_localPart("\"abcdefghijklmnopqrstuvwxyz\"", isValid: true)
      __test_localPart("\"ABCDEFGHIJKLMNOPQRSTUVWXYZ\"", isValid: true)
      __test_localPart("\"0123456789\"", isValid: true)
      __test_localPart("\"!#$%&'*+-/=?^_{|}~`\"", isValid: true)
      __test_localPart("\".\"", isValid: true)
      __test_localPart("\"..\"", isValid: true)
      __test_localPart("\" ()*,:;<>@[]\"", isValid: true)
      __test_localPart("\"\\a\\A\\0\\!\\.\"", isValid: true)
      __test_localPart("0123456789012345678901234567890123456789012345678901234567890123", isValid: true) // 64 scalars

      __test_localPart(".aaa", isValid: false)
      __test_localPart("aaa.", isValid: false)
      __test_localPart("a..a", isValid: false)
      __test_localPart("()", isValid: false)
      __test_localPart("\"aaa\"a", isValid: false)
      __test_localPart("", isValid: false)
      __test_localPart("01234567890123456789012345678901234567890123456789012345678901234", isValid: false) // 65 scalars
    }

    do { // https://en.wikipedia.org/wiki/Email_address
      __test_wholeAddress("simple@example.com", isValid: true)
      __test_wholeAddress("very.common@example.com", isValid: true)
      __test_wholeAddress("disposable.style.email.with+symbol@example.com", isValid: true)
      __test_wholeAddress("other.email-with-hyphen@example.com", isValid: true)
      __test_wholeAddress("fully-qualified-domain@example.com", isValid: true)
      __test_wholeAddress("user.name+tag+sorting@example.com", isValid: true)
      __test_wholeAddress("x@example.com", isValid: true)
      __test_wholeAddress("example-indeed@strange-example.com", isValid: true)
      __test_wholeAddress("test/test@test.com", isValid: true)
      __test_wholeAddress("admin@mailserver1", isValid: true)
      __test_wholeAddress("example@s.example", isValid: true)
      __test_wholeAddress(#"" "@example.org"#, isValid: true)
      __test_wholeAddress(#""john..doe"@example.org"#, isValid: true)
      __test_wholeAddress("mailhost!username@example.org", isValid: true)
      __test_wholeAddress(#""very.(),:;<>[]\".VERY.\"very@\\ \"very\".unusual"@strange.example.com"#, isValid: true)
      __test_wholeAddress("user%example.com@example.org", isValid: true)
      __test_wholeAddress("user-@example.org", isValid: true)
      __test_wholeAddress("postmaster@[123.123.123.123]", isValid: true)
      __test_wholeAddress("postmaster@[IPv6:2001:0db8:85a3:0000:0000:8a2e:0370:7334]", isValid: true)

      __test_wholeAddress("Abc.example.com", isValid: false)
      __test_wholeAddress("A@b@c@example.com", isValid: false)
      __test_wholeAddress(#"a"b(c)d,e:f;g<h>i[j\k]l@example.com"#, isValid: false)
      __test_wholeAddress(#"just"not"right@example.com"#, isValid: false)
      __test_wholeAddress(#"this is"not\allowed@example.com"#, isValid: false)
      __test_wholeAddress(#"this\ still\"not\\allowed@example.com"#, isValid: false)
      __test_wholeAddress("1234567890123456789012345678901234567890123456789012345678901234+x@example.com", isValid: false)
    }
  }

  @Test func test_parser() {
    let parser = _Parser()
    func __assert(_ string: String, expectedTokens: [_Parser.Token],
                  sourceLocation: SourceLocation = #_sourceLocation) {
      #expect(parser.parse(string) == expectedTokens, sourceLocation: sourceLocation)
    }

    func __scalars(_ string: String) -> [Unicode.Scalar] {
      return Array<Unicode.Scalar>(string.unicodeScalars)
    }

    __assert(
      "Only ASCII.",
      expectedTokens: [
        .raw(__scalars("Only ASCII."))
      ]
    )
    __assert(
      "ひらがな ASCII 漢字",
      expectedTokens: [
        .mustBeEncoded(__scalars("ひらがな")),
        .raw(__scalars(" ASCII ")),
        .mustBeEncoded(__scalars("漢字")),
      ]
    )
    // Example from http://www.din.or.jp/~ohzaki/perl.htm#JP_Base64
    __assert(
      "Subject: ASCII 日本語 ASCIIと日本語 ASCII ASCII",
      expectedTokens: [
        .raw(__scalars("Subject: ASCII ")),
        .mustBeEncoded(__scalars("日本語 ASCIIと日本語")),
        .raw(__scalars(" ASCII ASCII"))
      ]
    )

    // Confirm that [Issue#2](https://github.com/YOCKOW/SwiftMailMessage/issues/2) is fixed.
    __assert(
      "Subject: AlphabetsWithNoWhitespacesからの日本語",
      expectedTokens: [
        .raw(__scalars("Subject: ")),
        .mustBeEncoded(__scalars("AlphabetsWithNoWhitespacesからの日本語")),
      ]
    )
  }

  @Test func test_mimeEncode() throws {
    #expect(try "Only ASCII".mimeEncodedString(using: .utf8) == "Only ASCII")
    #expect(
      try "ひらがな ASCII 漢字".mimeEncodedString(using: .utf8) ==
      "=?utf-8?B?44Gy44KJ44GM44Gq?= ASCII =?utf-8?B?5ryi5a2X?="
    )
    // Example from http://www.din.or.jp/~ohzaki/perl.htm#JP_Base64
    #expect(
      try "Subject: ASCII 日本語 ASCIIと日本語 ASCII ASCII".mimeEncodedString(using: .iso2022JP) ==
      [
        "Subject: ASCII =?iso-2022-jp?B?GyRCRnxLXDhsGyhCIEFTQ0lJGyRCJEhGfEtcGyhC?=",
        "=?iso-2022-jp?B?GyRCOGwbKEI=?= ASCII ASCII",
      ].joined(separator: "\u{0D}\u{0A}\u{20}")
    )
  }

  @Test func test_mimeEncode_parameter() throws {
    #expect(
      String(data: try _mimeEncodedParameter(
        name: "filename",
        value: "とてもとても長い長い日本語の名前のファイル.txt",
        encoding: .iso2022JP,
        locale: Locale(identifier: "ja_JP")
      )) ==
      """
       filename*0*=iso-2022-jp'ja'%1B$B$H$F$b$H$F$bD9$$D9$$F%7CK%5C8l$N%1B%28B;\(CRLF)\
       filename*1*=%1B$BL%3EA0$N%25U%25%21%25$%25k%1B%28B.txt
      """
    )
  }

  @Test func test_mimeEncode_contentType() throws {
    let contentType = try #require(MIMEType(
      type: .application,
      subtype: "xhtml+xml",
      parameters: ["charset": "utf-8"]
    ))
    #expect(
      String(data: try _mimeEncodedContentTypeHeaderField(contentType, encoding: .utf8)) ==
      "Content-Type: application/xhtml+xml; charset=utf-8\(CRLF)"
    )
  }

  @Test func test_headerValues() throws {
    let author = try #require(Person(displayName: "John Doe", mailAddress: "john.doe@example.com"))
    let recipients = Group([
      try #require(Person(displayName: "Jane Doe", mailAddress: "jane.doe@example.com")),
      try #require(Person(mailAddress: "taro@example.com")),
    ])
    var header = MailMessage.Header()
    header.author = author
    header.recipients = recipients

    #expect(header["From"] == "John Doe <john.doe@example.com>")
    #expect(header["To"] == "Jane Doe <jane.doe@example.com>,taro@example.com")
  }

  @Test func test_plainText() throws {
    let body = PlainText(
      text: """
        Hello, World!
        こんにちは、世界！
        """,
      stringEncoding: .iso2022JP,
      contentTransferEncoding: ._7bit
    )
    let message = MailMessage(
      author: try #require(Person(displayName: "Author", mailAddress: "author@example.com")),
      recipients: Group([
        try #require(Person(displayName: "Recipient", mailAddress: "recipient@example.com")),
      ]),
      subject: "My First Mail Message. - 私の初めてのメールメッセージ -",
      body: body
    )

    #expect(
      try message.deliverableDescription(using: .iso2022JP) ==
      """
      From: Author <author@example.com>\(CRLF)\
      To: Recipient <recipient@example.com>\(CRLF)\
      Subject: My First Mail Message. - =?iso-2022-jp?B?GyRCO2QkTj1pJGEbKEI=?=\(CRLF)\
       =?iso-2022-jp?B?GyRCJEYkTiVhITwlayVhJUMlOyE8JTgbKEI=?= -\(CRLF)\
      Content-Type: text/plain; charset=iso-2022-jp\(CRLF)\
      Content-Transfer-Encoding: 7bit\(CRLF)\
      \(CRLF)\
      Hello, World!
      \u{1B}$B$3$s$K$A$O!\"@$3&!*\u{1B}(B
      """
    )
  }

  @Test func test_contentTransferEncoding() throws {
    let string = """
    0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
    !あいうえおかきくけこさしすせそたちつてとなにぬね
    """
    let data = Data(string.utf8)

    #expect(
      try #require(String(data: data.mimeSafeData(using: .base64).bytes, encoding: .utf8)) ==
      """
      MDEyMzQ1Njc4OUFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaYWJjZGVmZ2hpamtsbW5vcHFyc3R1\(CRLF)\
      dnd4eXoKIeOBguOBhOOBhuOBiOOBiuOBi+OBjeOBj+OBkeOBk+OBleOBl+OBmeOBm+OBneOBn+OB\(CRLF)\
      oeOBpOOBpuOBqOOBquOBq+OBrOOBrQ==
      """
    )

    #expect(
      try String(data: string.mimeSafeData(using: .quotedPrintable, stringEncoding: .utf8).bytes, encoding: .utf8) ==
      """
      0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz\(CRLF)\
      !=E3=81=82=E3=81=84=E3=81=86=E3=81=88=E3=81=8A=E3=81=8B=E3=81=8D=E3=81=8F=\(CRLF)\
      =E3=81=91=E3=81=93=E3=81=95=E3=81=97=E3=81=99=E3=81=9B=E3=81=9D=E3=81=9F=E3=\(CRLF)\
      =81=A1=E3=81=A4=E3=81=A6=E3=81=A8=E3=81=AA=E3=81=AB=E3=81=AC=E3=81=AD
      """
    )
  }

  let shortText: String = "TEXT"

  var shortTextFile: File {
    return File(
      filename: "short.txt",
      contentType: MIMEType(pathExtension: .txt)!,
      contentID: ContentID(rawValue: "<test-shortTextFile@swift.mail.message>")!,
      content: InputStream(data: Data(shortText.utf8))
    )
  }

  let shortTextFileBase64: String = "VEVYVA=="

  let pngFileURL: URL = resourcesDirectory.appendingPathComponent("stripe.png")

  var pngFile: File {
    return File(
      filename: "繰り返しを適用することで横縞模様に使うことができる小さな画像.png",
      contentType: MIMEType(pathExtension: .png)!,
      contentID: ContentID(rawValue: "<test-pngFile@swift.mail.message>")!,
      content: InputStream(url: pngFileURL)!
    )
  }

  let pngFileBase64: String = """
    iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAABGdBTUEAALGPC/xhBQAABA5pQ0NQ\(CRLF)\
    a0NHQ29sb3JTcGFjZUdlbmVyaWNSR0IAADiNjVVdaBxVFD6bubMrJM6D1Kamkg7+NZS0bFLRhNro\(CRLF)\
    /mWzbdwsk2y0QZDJ7N2daSYz4/ykaSk+FEEQwajgk+D/W8EnIWqr7YstorRQogSDKPjQ+keh0hcJ\(CRLF)\
    67kzs7uTuGu9y9z55pzvfufec+7eC5C4LFuW3iUCLBquLeXT4rPH5sTEOnTBfdANfdAtK46VKpUm\(CRLF)\
    ARvjwr/a7e8gxt7X9rf3/2frrlBHAYjdhdisOMoi4mUA/hXFsl2ABEH7yAnXYvgJxDtsnCDiEsO1\(CRLF)\
    AFcYng/wss+ZkTKIX0UsKKqM/sTbiAfnI/ZaBAdz8NuOPDWorSkiy0XJNquaTiPTvYP7f7ZF3WvE\(CRLF)\
    24NPj7MwfRTfA7j2lypyluGHEJ9V5Nx0iK8uabPFEP9luWkJ8SMAXbu8hXIK8T7EY1V7vBzodKmq\(CRLF)\
    N9HAK6fUmWcQ34N4dcE8ysbuRPy1MV+cCnV+UpwM5g8eAODiKi2wevcjHrBNaSqIy41XaDbH8oj4\(CRLF)\
    uOYWZgJ97i1naTrX0DmlZopBLO6L4/IRVqc+xFepnpdC/V8ttxTGJT2GXpwMdMgwdfz1+nZXnZkI\(CRLF)\
    4pI5FwsajCUvVrXxQsh/V7UnpBBftnR/j+LcyE3bk8oBn7+fGuVQkx+T7Vw+xBWYjclAwYR57BUw\(CRLF)\
    YBNEkCAPaXxbYKOnChroaKHopWih+NXg7N/CKfn+ALdUav7I6+jRMEKm/yPw0KrC72hVI7wMfnlo\(CRLF)\
    q3XQCWZwI9QxSS9JkoP4HCKT5DAZIaMgkifJU2SMZNE6Sg41x5Yic2TzudHUeQEjUp83i7yL6HdB\(CRLF)\
    xv5nZJjgtM/FSp83ENjP2M9rypXXbl46fW5Xi7tGVp+71nPpdCRnGmotdMja1J1yz//CX+fXsF/n\(CRLF)\
    N1oM/gd+A3/r21a3Nes0zFYKfbpvW8RH8z1OZD6lLVVsYbOjolk1VvoCH8sAfbl4uwhnBlv85PfJ\(CRLF)\
    P5JryfeSHyZ/497kPuHOc59yn3HfgMhd4C5yX3JfcR9zn0dq1HnvNGvur6OxCuZpl1Hcn0Ja2C08\(CRLF)\
    KGSFPcLDwmRLT+gVhoQJYS96djerE40XXbsGx7BvZKt9rIAXqXPsbqyz1uE/VEaWBid8puPvMwNO\(CRLF)\
    buOEI0k/GSKFbbt6hO31pnZ+Sz3ar4HGc/FsPAVifF98ND4UP8Jwgxnfi75R7PHUcumyyw7ijGmd\(CRLF)\
    tLWa6orDyeTjYgqvMioWDOXAoCjruui7HNGmDrWXaOUAsHsyOMJvSf79F9t5pWVznwY4/Cc791q2\(CRLF)\
    OQ/grAPQ+2jLNoBn473vAKw+pnj2UngnxGLfAjjVg8PBV08az6sf6/VbeG4l3gDYfL1e//v9en3z\(CRLF)\
    A9TfALig/wP/JXgLxWPWywAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3Cc\(CRLF)\
    ulE8AAAAXGVYSWZNTQAqAAAACAAEAQYAAwAAAAEAAQAAARIAAwAAAAEAAQAAASgAAwAAAAEAAgAA\(CRLF)\
    h2kABAAAAAEAAAA+AAAAAAACoAIABAAAAAEAAAACoAMABAAAAAEAAAACAAAAAPxT8VAAAAKyaVRY\(CRLF)\
    dFhNTDpjb20uYWRvYmUueG1wAAAAAAA8eDp4bXBtZXRhIHhtbG5zOng9ImFkb2JlOm5zOm1ldGEv\(CRLF)\
    IiB4OnhtcHRrPSJYTVAgQ29yZSA2LjAuMCI+CiAgIDxyZGY6UkRGIHhtbG5zOnJkZj0iaHR0cDov\(CRLF)\
    L3d3dy53My5vcmcvMTk5OS8wMi8yMi1yZGYtc3ludGF4LW5zIyI+CiAgICAgIDxyZGY6RGVzY3Jp\(CRLF)\
    cHRpb24gcmRmOmFib3V0PSIiCiAgICAgICAgICAgIHhtbG5zOnRpZmY9Imh0dHA6Ly9ucy5hZG9i\(CRLF)\
    ZS5jb20vdGlmZi8xLjAvIgogICAgICAgICAgICB4bWxuczpleGlmPSJodHRwOi8vbnMuYWRvYmUu\(CRLF)\
    Y29tL2V4aWYvMS4wLyI+CiAgICAgICAgIDx0aWZmOkNvbXByZXNzaW9uPjE8L3RpZmY6Q29tcHJl\(CRLF)\
    c3Npb24+CiAgICAgICAgIDx0aWZmOlJlc29sdXRpb25Vbml0PjI8L3RpZmY6UmVzb2x1dGlvblVu\(CRLF)\
    aXQ+CiAgICAgICAgIDx0aWZmOlBob3RvbWV0cmljSW50ZXJwcmV0YXRpb24+MTwvdGlmZjpQaG90\(CRLF)\
    b21ldHJpY0ludGVycHJldGF0aW9uPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZm\(CRLF)\
    Ok9yaWVudGF0aW9uPgogICAgICAgICA8ZXhpZjpQaXhlbFhEaW1lbnNpb24+MjwvZXhpZjpQaXhl\(CRLF)\
    bFhEaW1lbnNpb24+CiAgICAgICAgIDxleGlmOlBpeGVsWURpbWVuc2lvbj4yPC9leGlmOlBpeGVs\(CRLF)\
    WURpbWVuc2lvbj4KICAgICAgPC9yZGY6RGVzY3JpcHRpb24+CiAgIDwvcmRmOlJERj4KPC94Onht\(CRLF)\
    cG1ldGE+Cr3yEU0AAAAVSURBVAgdY2RgYPgPxAws//+DaQYAIyUEAhbdyZAAAAAASUVORK5CYII=
    """

  @Test func test_contentTransferEncodingStream() throws {
    var textStream = try ContentTransferEncodingStream(
      InputStream(data: Data(shortText.utf8)),
      encoding: .base64
    )
    #expect(String(data: try textStream._availableData()) == shortTextFileBase64 + CRLF)

    var pngStream = try ContentTransferEncodingStream(
      try #require(InputStream(url: pngFileURL)),
      encoding: .base64
    )
    #expect(String(data: try pngStream._availableData()) == pngFileBase64 + CRLF)
  }

  @Test func test_file() throws {
    var shortTextFileStream = try shortTextFile._stream.get()
    #expect(
      String(data: try shortTextFileStream._availableData()) ==
      """
      Content-Disposition: attachment; filename=short.txt\(CRLF)\
      Content-Type: text/plain\(CRLF)\
      Content-ID: <test-shortTextFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(shortTextFileBase64)\(CRLF)
      """
    )

    var pngFileStream = try pngFile._stream.get()
    #expect(
      String(data: try pngFileStream._availableData()) ==
      """
      Content-Disposition: attachment;\(CRLF)\
       filename*0*=utf-8''%E7%B9%B0%E3%82%8A%E8%BF%94%E3%81%97%E3%82%92%E9%81%A9;\(CRLF)\
       filename*1*=%E7%94%A8%E3%81%99%E3%82%8B%E3%81%93%E3%81%A8%E3%81%A7;\(CRLF)\
       filename*2*=%E6%A8%AA%E7%B8%9E%E6%A8%A1%E6%A7%98%E3%81%AB%E4%BD%BF;\(CRLF)\
       filename*3*=%E3%81%86%E3%81%93%E3%81%A8%E3%81%8C%E3%81%A7%E3%81%8D;\(CRLF)\
       filename*4*=%E3%82%8B%E5%B0%8F%E3%81%95%E3%81%AA%E7%94%BB%E5%83%8F.png\(CRLF)\
      Content-Type: image/png\(CRLF)\
      Content-ID: <test-pngFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(pngFileBase64)\(CRLF)
      """
    )
  }

  @Test func test_richText() throws {
    let plainText = PlainText(
      text: "Hello, HTML!",
      contentTransferEncoding: .quotedPrintable
    )
    let xhtml = XHTMLDocument.template(
      title: "XHTML Title",
      contents: [
        .div(children: [.text("XHTML")])
      ]
    )
    let htmlContent = RichText.HTMLContent(xhtml: xhtml)
    var richText = RichText(plainText: plainText, htmlContent: htmlContent)
    richText.boundary = "test-boundary"

    let message = MailMessage(
      recipients: Group([
        try #require(Person(mailAddress: "recipient@example.com")),
      ]),
      subject: "Rich Text Mail",
      body: richText
    )
    #expect(
      try message.deliverableDescription() ==
      """
      To: recipient@example.com\(CRLF)\
      Subject: Rich Text Mail\(CRLF)\
      Content-Type: multipart/alternative; boundary=test-boundary\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      --test-boundary\(CRLF)\
      Content-Type: text/plain; charset=utf-8\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      Hello, HTML!\(CRLF)\
      --test-boundary\(CRLF)\
      Content-Type: text/html; charset=utf-8\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      <?xml version=3D"1.0" encoding=3D"utf-8"?>\(CRLF)\
      <!DOCTYPE html>\(CRLF)\
      <html xmlns=3D"http://www.w3.org/1999/xhtml"><head><title>XHTML Title</titl=\(CRLF)\
      e></head><body><div>XHTML</div></body></html>\(CRLF)\
      --test-boundary--\(CRLF)
      """
    )
  }

  @Test func test_fileAttached() throws {
    let textBody = PlainText(text: "Hello, files!", contentTransferEncoding: .quotedPrintable)
    var mailBody = FileAttachedBody(mainBody: textBody, files: [shortTextFile, pngFile])
    mailBody.boundary = "test-boundary"

    let message = MailMessage(
      recipients: Group([
        try #require(Person(mailAddress: "recipient@example.com"))
      ]),
      subject: "Mail with attachments!",
      body: mailBody
    )

    #expect(
      try message.deliverableDescription() ==
      """
      To: recipient@example.com\(CRLF)\
      Subject: Mail with attachments!\(CRLF)\
      Content-Type: multipart/mixed; boundary=test-boundary\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      This is a multi-part message in MIME format.\(CRLF)\
      \(CRLF)\
      --test-boundary\(CRLF)\
      Content-Type: text/plain; charset=utf-8\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      Hello, files!\(CRLF)\
      --test-boundary\(CRLF)\
      Content-Disposition: attachment; filename=short.txt\(CRLF)\
      Content-Type: text/plain\(CRLF)\
      Content-ID: <test-shortTextFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(shortTextFileBase64)\(CRLF)\
      --test-boundary\(CRLF)\
      Content-Disposition: attachment;\(CRLF)\
       filename*0*=utf-8''%E7%B9%B0%E3%82%8A%E8%BF%94%E3%81%97%E3%82%92%E9%81%A9;\(CRLF)\
       filename*1*=%E7%94%A8%E3%81%99%E3%82%8B%E3%81%93%E3%81%A8%E3%81%A7;\(CRLF)\
       filename*2*=%E6%A8%AA%E7%B8%9E%E6%A8%A1%E6%A7%98%E3%81%AB%E4%BD%BF;\(CRLF)\
       filename*3*=%E3%81%86%E3%81%93%E3%81%A8%E3%81%8C%E3%81%A7%E3%81%8D;\(CRLF)\
       filename*4*=%E3%82%8B%E5%B0%8F%E3%81%95%E3%81%AA%E7%94%BB%E5%83%8F.png\(CRLF)\
      Content-Type: image/png\(CRLF)\
      Content-ID: <test-pngFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(pngFileBase64)\(CRLF)\
      --test-boundary--\(CRLF)
      """
    )
  }

  @Test func test_fullMessage() throws {
    let plainText = PlainText(
      text: "Hello, many resources!",
      stringEncoding: .ascii,
      contentTransferEncoding: .quotedPrintable
    )
    let xhtml = XHTMLDocument.template(
      title: "title",
      contents: [
        .text("Hello, image!"),
        .image(attributes: ["src": "cid:test-pngFile@swift.mail.message"]),
      ]
    )
    var htmlContent = RichText.HTMLContent(xhtml: xhtml, resources: [pngFile])
    htmlContent.boundary = "test-html-boundary"
    var richText = RichText(plainText: plainText, htmlContent: htmlContent)
    richText.boundary = "test-rich-text-boundary"
    var body = FileAttachedBody(mainBody: richText, files: [shortTextFile])
    body.boundary = "test-file-boundary"
    let message = MailMessage(
      recipients: Group([
        try #require(Person(mailAddress: "recipient@example.com"))
      ]),
      subject: "Full Message",
      body: body
    )

    #expect(
      try message.deliverableDescription(using: .utf8) ==
      """
      To: recipient@example.com\(CRLF)\
      Subject: Full Message\(CRLF)\
      Content-Type: multipart/mixed; boundary=test-file-boundary\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      This is a multi-part message in MIME format.\(CRLF)\
      \(CRLF)\
      --test-file-boundary\(CRLF)\
      Content-Type: multipart/alternative; boundary=test-rich-text-boundary\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      --test-rich-text-boundary\(CRLF)\
      Content-Type: text/plain; charset=us-ascii\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      Hello, many resources!\(CRLF)\
      --test-rich-text-boundary\(CRLF)\
      Content-Type: multipart/related; boundary=test-html-boundary;\(CRLF)\
       type="text/html"\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      --test-html-boundary\(CRLF)\
      Content-Type: text/html; charset=utf-8\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      <?xml version=3D"1.0" encoding=3D"utf-8"?>\(CRLF)\
      <!DOCTYPE html>\(CRLF)\
      <html xmlns=3D"http://www.w3.org/1999/xhtml"><head><title>title</title></he=\(CRLF)\
      ad><body>Hello, image!<img src=3D"cid:test-pngFile@swift.mail.message" /></=\(CRLF)\
      body></html>\(CRLF)\
      --test-html-boundary\(CRLF)\
      Content-Disposition: attachment;\(CRLF)\
       filename*0*=utf-8''%E7%B9%B0%E3%82%8A%E8%BF%94%E3%81%97%E3%82%92%E9%81%A9;\(CRLF)\
       filename*1*=%E7%94%A8%E3%81%99%E3%82%8B%E3%81%93%E3%81%A8%E3%81%A7;\(CRLF)\
       filename*2*=%E6%A8%AA%E7%B8%9E%E6%A8%A1%E6%A7%98%E3%81%AB%E4%BD%BF;\(CRLF)\
       filename*3*=%E3%81%86%E3%81%93%E3%81%A8%E3%81%8C%E3%81%A7%E3%81%8D;\(CRLF)\
       filename*4*=%E3%82%8B%E5%B0%8F%E3%81%95%E3%81%AA%E7%94%BB%E5%83%8F.png\(CRLF)\
      Content-Type: image/png\(CRLF)\
      Content-ID: <test-pngFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(pngFileBase64)\(CRLF)\
      --test-html-boundary--\(CRLF)\
      \(CRLF)\
      --test-rich-text-boundary--\(CRLF)\
      \(CRLF)\
      --test-file-boundary\(CRLF)\
      Content-Disposition: attachment; filename=short.txt\(CRLF)\
      Content-Type: text/plain\(CRLF)\
      Content-ID: <test-shortTextFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(shortTextFileBase64)\(CRLF)\
      --test-file-boundary--\(CRLF)
      """
    )
  }
}
#else
import XCTest

final class MailMessageTests: XCTestCase {
  func test_mailAddressLexer() {
    func __assert(
      _ string: String,
      _ expected: [(MailAddressToken) -> Bool],
      expectedError: MailAddressParserError? = nil,
      file: StaticString = #filePath,
      line: UInt = #line
    ) {
      do {
        let tokens = try MailAddressToken.tokenize(string)
        guard tokens.count == expected.count else {
          XCTFail("Unexpected number of tokens.", file: file, line: line)
          return
        }
        for ii in 0..<tokens.count {
          let token = tokens[ii]
          XCTAssertTrue(expected[ii](token), "Unexpected token at #\(ii): \(token)", file: file, line: line)
        }
      } catch let error {
        guard case let parserError as MailAddressParserError = error,
              let expectedError,
              parserError == expectedError else {
          XCTFail("Unexpected error: \(error)", file: file, line: line)
          return
        }
      }
    }

    func __isPlainText(_ token: MailAddressToken, _ expectedText: String) -> Bool {
      guard case let plainTextToken as MailAddressToken.PlainText = token else {
        return false
      }
      return plainTextToken.text == expectedText
    }

    func __isQuotedText(_ token: MailAddressToken, _ expectedText: String) -> Bool {
      guard case let quotedTextToken as MailAddressToken.QuotedText = token else {
        return false
      }
      return quotedTextToken.content == expectedText
    }

    func __isIPAddress(_ token: MailAddressToken, _ expectedIPAddress: IPAddress) -> Bool {
      guard case let ipAddressToken as MailAddressToken.IPAddress = token else {
        return false
      }
      return ipAddressToken.ipAddress == expectedIPAddress
    }

    __assert("(comment)", [
      { $0 is MailAddressToken.OpenComment },
      { __isPlainText($0, "comment") },
      { $0 is MailAddressToken.CloseComment },
    ])

    __assert("(comment ( nested comment @ here ))", [
      { $0 is MailAddressToken.OpenComment },
      { __isPlainText($0, "comment ") },
      { $0 is MailAddressToken.OpenComment },
      { __isPlainText($0, " nested comment ") },
      { $0 is MailAddressToken.AtSign },
      { __isPlainText($0, " here ") },
      { $0 is MailAddressToken.CloseComment },
      { $0 is MailAddressToken.CloseComment },
    ])

    __assert("[127.0.0.1]", [
      { __isIPAddress($0, .v4(127, 0, 0, 1)) },
    ])

    __assert("YOCKOW@(domain-side comment)[IPv6:2001:db8::1]", [
      {  __isPlainText($0, "YOCKOW")},
      { $0 is MailAddressToken.AtSign },
      { $0 is MailAddressToken.OpenComment },
      {  __isPlainText($0, "domain-side comment")},
      { $0 is MailAddressToken.CloseComment },
      { __isIPAddress($0, .v6(0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)) },
    ])

    __assert(#""..QUOTED.."."MORE"."ESCAPE\"\\""#, [
      { __isQuotedText($0, "..QUOTED..") },
      { $0 is MailAddressToken.Dot },
      { __isQuotedText($0, "MORE") },
      { $0 is MailAddressToken.Dot },
      { __isQuotedText($0, "ESCAPE\"\\") },
    ])

    __assert(#""NEVER ENDING STORY"#, [], expectedError: .unterminatedQuotedString)
    __assert(#""日本語""#, [], expectedError: .invalidScalarInQuotedString)
    __assert("foo@[IPv6:2001:db8::1", [], expectedError: .unterminatedIPAddressLiteral)
    __assert("foo@[127.0.0.X]", [], expectedError: .invalidScalarInIPAddressLiteral)
    __assert("foo@[999.0.0.0]", [], expectedError: .invalidIPAddressLiteral)
  }

  func test_mailAddressPreparser() throws {
    func __parse(_ string: String) throws -> [MailAddressSyntaxNode] {
      return try MailAddressSyntaxNode.parse(MailAddressToken.tokenize(string))
    }

    nested_comment: do {
      let nodes = try __parse("(comment (nested@1) (nested@2))")
      guard nodes.count == 1 else {
        XCTFail("Unexpected number of nodes.")
        break nested_comment
      }
      guard case let commentNode as MailAddressSyntaxNode.Comment = nodes.first else {
        XCTFail("Unexpected node.")
        break nested_comment
      }
      guard commentNode.children.count == 4 else {
        XCTFail("Unexpected number of children.")
        break nested_comment
      }
      XCTAssertTrue(commentNode.children[0] is MailAddressSyntaxNode.PlainText)
      XCTAssertTrue(commentNode.children[1] is MailAddressSyntaxNode.Comment)
      XCTAssertTrue(commentNode.children[2] is MailAddressSyntaxNode.PlainText)
      XCTAssertTrue(commentNode.children[3] is MailAddressSyntaxNode.Comment)
      XCTAssertEqual(
        ((commentNode.children[3] as? MailAddressSyntaxNode.Comment)?.children.first as? MailAddressSyntaxNode.PlainText)?.text,
        "nested@2"
      )
    }

    simple_address: do {
      let nodes = try __parse(#"YOCKOW@example.com"#)
      guard nodes.count == 5 else {
        XCTFail("Unexpected number of nodes.")
        break simple_address
      }
      XCTAssertEqual((nodes[0] as? MailAddressSyntaxNode.PlainText)?.text, "YOCKOW")
      XCTAssertTrue(nodes[1] is MailAddressSyntaxNode.AtSign)
      XCTAssertEqual((nodes[2] as? MailAddressSyntaxNode.PlainText)?.text, "example")
      XCTAssertTrue(nodes[3] is MailAddressSyntaxNode.Dot)
      XCTAssertEqual((nodes[4] as? MailAddressSyntaxNode.PlainText)?.text, "com")
    }

    XCTAssertThrowsError(try __parse("(foo (bar)")) {
      XCTAssertEqual($0 as? MailAddressParserError, .unbalancedParenthesis)
    }
  }

  func test_mailAddressParserError() {
    func __assert(
      _ string: String, expectedError: MailAddressParserError,
      file: StaticString = #filePath, line: UInt = #line
    ) {
      do {
        let address = try MailAddress.parse(string)
        XCTFail("Unexpected success: localPart=\(address.localPart); domain=\(address.domain.description)", file: file, line: line)
      } catch let error {
        guard case let parseError as MailAddressParserError = error else {
          XCTFail("Unexpected error: \(error)", file: file, line: line)
          return
        }
        XCTAssertEqual(parseError, expectedError, file: file, line: line)
      }
    }

    __assert("a@" + String(repeating: "foo.", count: 70) + "com", expectedError: .tooLong)
    __assert("foo@bar@example.com", expectedError: .duplicateAtSigns)
    __assert("foo.bar.baz", expectedError: .missingAtSign)
    __assert("(comment)@example.com", expectedError: .missingLocalPart)
    __assert("foo@(comment)", expectedError: .missingDomain)
    __assert("foo(comment)bar@example.com", expectedError: .invalidCommentPosition)
    __assert("foo.bar@example.(comment)com", expectedError: .invalidCommentPosition)
    __assert("foo@----.com", expectedError: .invalidDomain)
    __assert("foo@example..com", expectedError: .consecutiveDots)
    __assert("foo..bar@example.com", expectedError: .consecutiveDots)
    __assert(".foo@example.com", expectedError: .invalidDotPosition)
    __assert("foo.@example.com", expectedError: .invalidDotPosition)
    __assert("foo,bar@example.com", expectedError: .invalidScalarInLocalPart)
    __assert(#""foo""bar"@example.com"#, expectedError: .invalidQuotedStringPosition)
    __assert(String(repeating: "foo", count: 30) + "@example.com", expectedError: .tooLongLocalPart)
  }

  func test_mailAddress() {
    func __test_wholeAddress(
      _ string: String, isValid: Bool, file: StaticString = #filePath, line: UInt = #line
    ) {
      let maybeAddress = MailAddress(string)
      if isValid {
        XCTAssertNotNil(maybeAddress, "\(string) is expected to be valid.", file: file, line: line)
      } else {
        XCTAssertNil(maybeAddress, "\(string) is expected to be invalid.", file: file, line: line)
      }
    }

    func __test_localPart(
      _ localPart: String, isValid: Bool, file: StaticString = #filePath, line: UInt = #line
    ) {
      __test_wholeAddress("\(localPart)@example.com", isValid: isValid, file: file, line: line)
    }

    do { // https://qiita.com/yoshitake_1201/items/40268332cd23f67c504c
      __test_localPart("abcdefghijklmnopqrstuvwxyz", isValid: true)
      __test_localPart("ABCDEFGHIJKLMNOPQRSTUVWXYZ", isValid: true)
      __test_localPart("0123456789", isValid: true)
      __test_localPart("!#$%&'*+-/=?^_{|}~`", isValid: true)
      __test_localPart("a.b", isValid: true)
      __test_localPart("\"abcdefghijklmnopqrstuvwxyz\"", isValid: true)
      __test_localPart("\"ABCDEFGHIJKLMNOPQRSTUVWXYZ\"", isValid: true)
      __test_localPart("\"0123456789\"", isValid: true)
      __test_localPart("\"!#$%&'*+-/=?^_{|}~`\"", isValid: true)
      __test_localPart("\".\"", isValid: true)
      __test_localPart("\"..\"", isValid: true)
      __test_localPart("\" ()*,:;<>@[]\"", isValid: true)
      __test_localPart("\"\\a\\A\\0\\!\\.\"", isValid: true)
      __test_localPart("0123456789012345678901234567890123456789012345678901234567890123", isValid: true) // 64 scalars

      __test_localPart(".aaa", isValid: false)
      __test_localPart("aaa.", isValid: false)
      __test_localPart("a..a", isValid: false)
      __test_localPart("()", isValid: false)
      __test_localPart("\"aaa\"a", isValid: false)
      __test_localPart("", isValid: false)
      __test_localPart("01234567890123456789012345678901234567890123456789012345678901234", isValid: false) // 65 scalars
    }

    do { // https://en.wikipedia.org/wiki/Email_address
      __test_wholeAddress("simple@example.com", isValid: true)
      __test_wholeAddress("very.common@example.com", isValid: true)
      __test_wholeAddress("disposable.style.email.with+symbol@example.com", isValid: true)
      __test_wholeAddress("other.email-with-hyphen@example.com", isValid: true)
      __test_wholeAddress("fully-qualified-domain@example.com", isValid: true)
      __test_wholeAddress("user.name+tag+sorting@example.com", isValid: true)
      __test_wholeAddress("x@example.com", isValid: true)
      __test_wholeAddress("example-indeed@strange-example.com", isValid: true)
      __test_wholeAddress("test/test@test.com", isValid: true)
      __test_wholeAddress("admin@mailserver1", isValid: true)
      __test_wholeAddress("example@s.example", isValid: true)
      __test_wholeAddress(#"" "@example.org"#, isValid: true)
      __test_wholeAddress(#""john..doe"@example.org"#, isValid: true)
      __test_wholeAddress("mailhost!username@example.org", isValid: true)
      __test_wholeAddress(#""very.(),:;<>[]\".VERY.\"very@\\ \"very\".unusual"@strange.example.com"#, isValid: true)
      __test_wholeAddress("user%example.com@example.org", isValid: true)
      __test_wholeAddress("user-@example.org", isValid: true)
      __test_wholeAddress("postmaster@[123.123.123.123]", isValid: true)
      __test_wholeAddress("postmaster@[IPv6:2001:0db8:85a3:0000:0000:8a2e:0370:7334]", isValid: true)

      __test_wholeAddress("Abc.example.com", isValid: false)
      __test_wholeAddress("A@b@c@example.com", isValid: false)
      __test_wholeAddress(#"a"b(c)d,e:f;g<h>i[j\k]l@example.com"#, isValid: false)
      __test_wholeAddress(#"just"not"right@example.com"#, isValid: false)
      __test_wholeAddress(#"this is"not\allowed@example.com"#, isValid: false)
      __test_wholeAddress(#"this\ still\"not\\allowed@example.com"#, isValid: false)
      __test_wholeAddress("1234567890123456789012345678901234567890123456789012345678901234+x@example.com", isValid: false)
    }
  }

  func test_parser() {
    let parser = _Parser()
    func __assert(_ string: String, expectedTokens: [_Parser.Token],
                  file: StaticString = #filePath, line: UInt = #line) {
      XCTAssertEqual(parser.parse(string), expectedTokens, file: file, line: line)
    }

    func __scalars(_ string: String) -> [Unicode.Scalar] {
      return Array<Unicode.Scalar>(string.unicodeScalars)
    }

    __assert(
      "Only ASCII.",
      expectedTokens: [
        .raw(__scalars("Only ASCII."))
      ]
    )
    __assert(
      "ひらがな ASCII 漢字",
      expectedTokens: [
        .mustBeEncoded(__scalars("ひらがな")),
        .raw(__scalars(" ASCII ")),
        .mustBeEncoded(__scalars("漢字")),
      ]
    )
    // Example from http://www.din.or.jp/~ohzaki/perl.htm#JP_Base64
    __assert(
      "Subject: ASCII 日本語 ASCIIと日本語 ASCII ASCII",
      expectedTokens: [
        .raw(__scalars("Subject: ASCII ")),
        .mustBeEncoded(__scalars("日本語 ASCIIと日本語")),
        .raw(__scalars(" ASCII ASCII"))
      ]
    )

    // Confirm that [Issue#2](https://github.com/YOCKOW/SwiftMailMessage/issues/2) is fixed.
    __assert(
      "Subject: AlphabetsWithNoWhitespacesからの日本語",
      expectedTokens: [
        .raw(__scalars("Subject: ")),
        .mustBeEncoded(__scalars("AlphabetsWithNoWhitespacesからの日本語")),
      ]
    )
  }

  func test_mimeEncode() throws {
    XCTAssertEqual(
      try "Only ASCII".mimeEncodedString(using: .utf8),
      "Only ASCII"
    )
    XCTAssertEqual(
      try "ひらがな ASCII 漢字".mimeEncodedString(using: .utf8),
      "=?utf-8?B?44Gy44KJ44GM44Gq?= ASCII =?utf-8?B?5ryi5a2X?="
    )
    // Example from http://www.din.or.jp/~ohzaki/perl.htm#JP_Base64
    XCTAssertEqual(
      try "Subject: ASCII 日本語 ASCIIと日本語 ASCII ASCII".mimeEncodedString(using: .iso2022JP),
      [
        "Subject: ASCII =?iso-2022-jp?B?GyRCRnxLXDhsGyhCIEFTQ0lJGyRCJEhGfEtcGyhC?=",
        "=?iso-2022-jp?B?GyRCOGwbKEI=?= ASCII ASCII",
      ].joined(separator: "\u{0D}\u{0A}\u{20}")
    )
  }

  func test_mimeEncode_parameter() throws {
    XCTAssertEqual(
      String(data: try _mimeEncodedParameter(
        name: "filename",
        value: "とてもとても長い長い日本語の名前のファイル.txt",
        encoding: .iso2022JP,
        locale: Locale(identifier: "ja_JP")
      )),
      """
       filename*0*=iso-2022-jp'ja'%1B$B$H$F$b$H$F$bD9$$D9$$F%7CK%5C8l$N%1B%28B;\(CRLF)\
       filename*1*=%1B$BL%3EA0$N%25U%25%21%25$%25k%1B%28B.txt
      """
    )
  }

  func test_mimeEncode_contentType() throws {
    let contentType = try XCTUnwrap(MIMEType(
      type: .application,
      subtype: "xhtml+xml",
      parameters: ["charset": "utf-8"]
    ))
    XCTAssertEqual(
      String(data: try _mimeEncodedContentTypeHeaderField(contentType, encoding: .utf8)),
      "Content-Type: application/xhtml+xml; charset=utf-8\(CRLF)"
    )
  }

  func test_headerValues() throws {
    let author = try XCTUnwrap(Person(displayName: "John Doe", mailAddress: "john.doe@example.com"))
    let recipients = Group([
      try XCTUnwrap(Person(displayName: "Jane Doe", mailAddress: "jane.doe@example.com")),
      try XCTUnwrap(Person(mailAddress: "taro@example.com")),
    ])
    var header = MailMessage.Header()
    header.author = author
    header.recipients = recipients

    XCTAssertEqual(header["From"], "John Doe <john.doe@example.com>")
    XCTAssertEqual(header["To"], "Jane Doe <jane.doe@example.com>,taro@example.com")
  }

  func test_plainText() throws {
    let body = PlainText(
      text: """
        Hello, World!
        こんにちは、世界！
        """,
      stringEncoding: .iso2022JP,
      contentTransferEncoding: ._7bit
    )
    let message = MailMessage(
      author: try XCTUnwrap(Person(displayName: "Author", mailAddress: "author@example.com")),
      recipients: Group([
        try XCTUnwrap(Person(displayName: "Recipient", mailAddress: "recipient@example.com")),
      ]),
      subject: "My First Mail Message. - 私の初めてのメールメッセージ -",
      body: body
    )

    XCTAssertEqual(
      try message.deliverableDescription(using: .iso2022JP),
      """
      From: Author <author@example.com>\(CRLF)\
      To: Recipient <recipient@example.com>\(CRLF)\
      Subject: My First Mail Message. - =?iso-2022-jp?B?GyRCO2QkTj1pJGEbKEI=?=\(CRLF)\
       =?iso-2022-jp?B?GyRCJEYkTiVhITwlayVhJUMlOyE8JTgbKEI=?= -\(CRLF)\
      Content-Type: text/plain; charset=iso-2022-jp\(CRLF)\
      Content-Transfer-Encoding: 7bit\(CRLF)\
      \(CRLF)\
      Hello, World!
      \u{1B}$B$3$s$K$A$O!\"@$3&!*\u{1B}(B
      """
    )
  }

  func test_contentTransferEncoding() throws {
    let string = """
    0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
    !あいうえおかきくけこさしすせそたちつてとなにぬね
    """
    let data = Data(string.utf8)

    XCTAssertEqual(
      try XCTUnwrap(String(data: data.mimeSafeData(using: .base64).bytes, encoding: .utf8)),
      """
      MDEyMzQ1Njc4OUFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaYWJjZGVmZ2hpamtsbW5vcHFyc3R1\(CRLF)\
      dnd4eXoKIeOBguOBhOOBhuOBiOOBiuOBi+OBjeOBj+OBkeOBk+OBleOBl+OBmeOBm+OBneOBn+OB\(CRLF)\
      oeOBpOOBpuOBqOOBquOBq+OBrOOBrQ==
      """
    )

    XCTAssertEqual(
      try String(data: string.mimeSafeData(using: .quotedPrintable, stringEncoding: .utf8).bytes, encoding: .utf8),
      """
      0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz\(CRLF)\
      !=E3=81=82=E3=81=84=E3=81=86=E3=81=88=E3=81=8A=E3=81=8B=E3=81=8D=E3=81=8F=\(CRLF)\
      =E3=81=91=E3=81=93=E3=81=95=E3=81=97=E3=81=99=E3=81=9B=E3=81=9D=E3=81=9F=E3=\(CRLF)\
      =81=A1=E3=81=A4=E3=81=A6=E3=81=A8=E3=81=AA=E3=81=AB=E3=81=AC=E3=81=AD
      """
    )
  }

  let shortText: String = "TEXT"

  var shortTextFile: File {
    return File(
      filename: "short.txt",
      contentType: MIMEType(pathExtension: .txt)!,
      contentID: ContentID(rawValue: "<test-shortTextFile@swift.mail.message>")!,
      content: InputStream(data: Data(shortText.utf8))
    )
  }

  let shortTextFileBase64: String = "VEVYVA=="

  let pngFileURL: URL = resourcesDirectory.appendingPathComponent("stripe.png")

  var pngFile: File {
    return File(
      filename: "繰り返しを適用することで横縞模様に使うことができる小さな画像.png",
      contentType: MIMEType(pathExtension: .png)!,
      contentID: ContentID(rawValue: "<test-pngFile@swift.mail.message>")!,
      content: InputStream(url: pngFileURL)!
    )
  }

  let pngFileBase64: String = """
    iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAABGdBTUEAALGPC/xhBQAABA5pQ0NQ\(CRLF)\
    a0NHQ29sb3JTcGFjZUdlbmVyaWNSR0IAADiNjVVdaBxVFD6bubMrJM6D1Kamkg7+NZS0bFLRhNro\(CRLF)\
    /mWzbdwsk2y0QZDJ7N2daSYz4/ykaSk+FEEQwajgk+D/W8EnIWqr7YstorRQogSDKPjQ+keh0hcJ\(CRLF)\
    67kzs7uTuGu9y9z55pzvfufec+7eC5C4LFuW3iUCLBquLeXT4rPH5sTEOnTBfdANfdAtK46VKpUm\(CRLF)\
    ARvjwr/a7e8gxt7X9rf3/2frrlBHAYjdhdisOMoi4mUA/hXFsl2ABEH7yAnXYvgJxDtsnCDiEsO1\(CRLF)\
    AFcYng/wss+ZkTKIX0UsKKqM/sTbiAfnI/ZaBAdz8NuOPDWorSkiy0XJNquaTiPTvYP7f7ZF3WvE\(CRLF)\
    24NPj7MwfRTfA7j2lypyluGHEJ9V5Nx0iK8uabPFEP9luWkJ8SMAXbu8hXIK8T7EY1V7vBzodKmq\(CRLF)\
    N9HAK6fUmWcQ34N4dcE8ysbuRPy1MV+cCnV+UpwM5g8eAODiKi2wevcjHrBNaSqIy41XaDbH8oj4\(CRLF)\
    uOYWZgJ97i1naTrX0DmlZopBLO6L4/IRVqc+xFepnpdC/V8ttxTGJT2GXpwMdMgwdfz1+nZXnZkI\(CRLF)\
    4pI5FwsajCUvVrXxQsh/V7UnpBBftnR/j+LcyE3bk8oBn7+fGuVQkx+T7Vw+xBWYjclAwYR57BUw\(CRLF)\
    YBNEkCAPaXxbYKOnChroaKHopWih+NXg7N/CKfn+ALdUav7I6+jRMEKm/yPw0KrC72hVI7wMfnlo\(CRLF)\
    q3XQCWZwI9QxSS9JkoP4HCKT5DAZIaMgkifJU2SMZNE6Sg41x5Yic2TzudHUeQEjUp83i7yL6HdB\(CRLF)\
    xv5nZJjgtM/FSp83ENjP2M9rypXXbl46fW5Xi7tGVp+71nPpdCRnGmotdMja1J1yz//CX+fXsF/n\(CRLF)\
    N1oM/gd+A3/r21a3Nes0zFYKfbpvW8RH8z1OZD6lLVVsYbOjolk1VvoCH8sAfbl4uwhnBlv85PfJ\(CRLF)\
    P5JryfeSHyZ/497kPuHOc59yn3HfgMhd4C5yX3JfcR9zn0dq1HnvNGvur6OxCuZpl1Hcn0Ja2C08\(CRLF)\
    KGSFPcLDwmRLT+gVhoQJYS96djerE40XXbsGx7BvZKt9rIAXqXPsbqyz1uE/VEaWBid8puPvMwNO\(CRLF)\
    buOEI0k/GSKFbbt6hO31pnZ+Sz3ar4HGc/FsPAVifF98ND4UP8Jwgxnfi75R7PHUcumyyw7ijGmd\(CRLF)\
    tLWa6orDyeTjYgqvMioWDOXAoCjruui7HNGmDrWXaOUAsHsyOMJvSf79F9t5pWVznwY4/Cc791q2\(CRLF)\
    OQ/grAPQ+2jLNoBn473vAKw+pnj2UngnxGLfAjjVg8PBV08az6sf6/VbeG4l3gDYfL1e//v9en3z\(CRLF)\
    A9TfALig/wP/JXgLxWPWywAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3Cc\(CRLF)\
    ulE8AAAAXGVYSWZNTQAqAAAACAAEAQYAAwAAAAEAAQAAARIAAwAAAAEAAQAAASgAAwAAAAEAAgAA\(CRLF)\
    h2kABAAAAAEAAAA+AAAAAAACoAIABAAAAAEAAAACoAMABAAAAAEAAAACAAAAAPxT8VAAAAKyaVRY\(CRLF)\
    dFhNTDpjb20uYWRvYmUueG1wAAAAAAA8eDp4bXBtZXRhIHhtbG5zOng9ImFkb2JlOm5zOm1ldGEv\(CRLF)\
    IiB4OnhtcHRrPSJYTVAgQ29yZSA2LjAuMCI+CiAgIDxyZGY6UkRGIHhtbG5zOnJkZj0iaHR0cDov\(CRLF)\
    L3d3dy53My5vcmcvMTk5OS8wMi8yMi1yZGYtc3ludGF4LW5zIyI+CiAgICAgIDxyZGY6RGVzY3Jp\(CRLF)\
    cHRpb24gcmRmOmFib3V0PSIiCiAgICAgICAgICAgIHhtbG5zOnRpZmY9Imh0dHA6Ly9ucy5hZG9i\(CRLF)\
    ZS5jb20vdGlmZi8xLjAvIgogICAgICAgICAgICB4bWxuczpleGlmPSJodHRwOi8vbnMuYWRvYmUu\(CRLF)\
    Y29tL2V4aWYvMS4wLyI+CiAgICAgICAgIDx0aWZmOkNvbXByZXNzaW9uPjE8L3RpZmY6Q29tcHJl\(CRLF)\
    c3Npb24+CiAgICAgICAgIDx0aWZmOlJlc29sdXRpb25Vbml0PjI8L3RpZmY6UmVzb2x1dGlvblVu\(CRLF)\
    aXQ+CiAgICAgICAgIDx0aWZmOlBob3RvbWV0cmljSW50ZXJwcmV0YXRpb24+MTwvdGlmZjpQaG90\(CRLF)\
    b21ldHJpY0ludGVycHJldGF0aW9uPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZm\(CRLF)\
    Ok9yaWVudGF0aW9uPgogICAgICAgICA8ZXhpZjpQaXhlbFhEaW1lbnNpb24+MjwvZXhpZjpQaXhl\(CRLF)\
    bFhEaW1lbnNpb24+CiAgICAgICAgIDxleGlmOlBpeGVsWURpbWVuc2lvbj4yPC9leGlmOlBpeGVs\(CRLF)\
    WURpbWVuc2lvbj4KICAgICAgPC9yZGY6RGVzY3JpcHRpb24+CiAgIDwvcmRmOlJERj4KPC94Onht\(CRLF)\
    cG1ldGE+Cr3yEU0AAAAVSURBVAgdY2RgYPgPxAws//+DaQYAIyUEAhbdyZAAAAAASUVORK5CYII=
    """

  func test_contentTransferEncodingStream() throws {
    var textStream = try ContentTransferEncodingStream(
      InputStream(data: Data(shortText.utf8)),
      encoding: .base64
    )
    XCTAssertEqual(String(data: try textStream._availableData()), shortTextFileBase64 + CRLF)

    var pngStream = try ContentTransferEncodingStream(
      try XCTUnwrap(InputStream(url: pngFileURL)),
      encoding: .base64
    )
    XCTAssertEqual(String(data: try pngStream._availableData()), pngFileBase64 + CRLF)
  }

  func test_file() throws {
    var shortTextFileStream = try shortTextFile._stream.get()
    XCTAssertEqual(
      String(data: try shortTextFileStream._availableData()),
      """
      Content-Disposition: attachment; filename=short.txt\(CRLF)\
      Content-Type: text/plain\(CRLF)\
      Content-ID: <test-shortTextFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(shortTextFileBase64)\(CRLF)
      """
    )

    var pngFileStream = try pngFile._stream.get()
    XCTAssertEqual(
      String(data: try pngFileStream._availableData()),
      """
      Content-Disposition: attachment;\(CRLF)\
       filename*0*=utf-8''%E7%B9%B0%E3%82%8A%E8%BF%94%E3%81%97%E3%82%92%E9%81%A9;\(CRLF)\
       filename*1*=%E7%94%A8%E3%81%99%E3%82%8B%E3%81%93%E3%81%A8%E3%81%A7;\(CRLF)\
       filename*2*=%E6%A8%AA%E7%B8%9E%E6%A8%A1%E6%A7%98%E3%81%AB%E4%BD%BF;\(CRLF)\
       filename*3*=%E3%81%86%E3%81%93%E3%81%A8%E3%81%8C%E3%81%A7%E3%81%8D;\(CRLF)\
       filename*4*=%E3%82%8B%E5%B0%8F%E3%81%95%E3%81%AA%E7%94%BB%E5%83%8F.png\(CRLF)\
      Content-Type: image/png\(CRLF)\
      Content-ID: <test-pngFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(pngFileBase64)\(CRLF)
      """
    )
  }

  func test_richText() throws {
    let plainText = PlainText(
      text: "Hello, HTML!",
      contentTransferEncoding: .quotedPrintable
    )
    let xhtml = XHTMLDocument.template(
      title: "XHTML Title",
      contents: [
        .div(children: [.text("XHTML")])
      ]
    )
    let htmlContent = RichText.HTMLContent(xhtml: xhtml)
    var richText = RichText(plainText: plainText, htmlContent: htmlContent)
    richText.boundary = "test-boundary"

    let message = MailMessage(
      recipients: Group([
        try XCTUnwrap(Person(mailAddress: "recipient@example.com")),
      ]),
      subject: "Rich Text Mail",
      body: richText
    )
    XCTAssertEqual(
      try message.deliverableDescription(),
      """
      To: recipient@example.com\(CRLF)\
      Subject: Rich Text Mail\(CRLF)\
      Content-Type: multipart/alternative; boundary=test-boundary\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      --test-boundary\(CRLF)\
      Content-Type: text/plain; charset=utf-8\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      Hello, HTML!\(CRLF)\
      --test-boundary\(CRLF)\
      Content-Type: text/html; charset=utf-8\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      <?xml version=3D"1.0" encoding=3D"utf-8"?>\(CRLF)\
      <!DOCTYPE html>\(CRLF)\
      <html xmlns=3D"http://www.w3.org/1999/xhtml"><head><title>XHTML Title</titl=\(CRLF)\
      e></head><body><div>XHTML</div></body></html>\(CRLF)\
      --test-boundary--\(CRLF)
      """
    )
  }

  func test_fileAttached() throws {
    let textBody = PlainText(text: "Hello, files!", contentTransferEncoding: .quotedPrintable)
    var mailBody = FileAttachedBody(mainBody: textBody, files: [shortTextFile, pngFile])
    mailBody.boundary = "test-boundary"

    let message = MailMessage(
      recipients: Group([
        try XCTUnwrap(Person(mailAddress: "recipient@example.com"))
      ]),
      subject: "Mail with attachments!",
      body: mailBody
    )

    XCTAssertEqual(
      try message.deliverableDescription(),
      """
      To: recipient@example.com\(CRLF)\
      Subject: Mail with attachments!\(CRLF)\
      Content-Type: multipart/mixed; boundary=test-boundary\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      This is a multi-part message in MIME format.\(CRLF)\
      \(CRLF)\
      --test-boundary\(CRLF)\
      Content-Type: text/plain; charset=utf-8\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      Hello, files!\(CRLF)\
      --test-boundary\(CRLF)\
      Content-Disposition: attachment; filename=short.txt\(CRLF)\
      Content-Type: text/plain\(CRLF)\
      Content-ID: <test-shortTextFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(shortTextFileBase64)\(CRLF)\
      --test-boundary\(CRLF)\
      Content-Disposition: attachment;\(CRLF)\
       filename*0*=utf-8''%E7%B9%B0%E3%82%8A%E8%BF%94%E3%81%97%E3%82%92%E9%81%A9;\(CRLF)\
       filename*1*=%E7%94%A8%E3%81%99%E3%82%8B%E3%81%93%E3%81%A8%E3%81%A7;\(CRLF)\
       filename*2*=%E6%A8%AA%E7%B8%9E%E6%A8%A1%E6%A7%98%E3%81%AB%E4%BD%BF;\(CRLF)\
       filename*3*=%E3%81%86%E3%81%93%E3%81%A8%E3%81%8C%E3%81%A7%E3%81%8D;\(CRLF)\
       filename*4*=%E3%82%8B%E5%B0%8F%E3%81%95%E3%81%AA%E7%94%BB%E5%83%8F.png\(CRLF)\
      Content-Type: image/png\(CRLF)\
      Content-ID: <test-pngFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(pngFileBase64)\(CRLF)\
      --test-boundary--\(CRLF)
      """
    )
  }

  func test_fullMessage() throws {
    let plainText = PlainText(
      text: "Hello, many resources!",
      stringEncoding: .ascii,
      contentTransferEncoding: .quotedPrintable
    )
    let xhtml = XHTMLDocument.template(
      title: "title",
      contents: [
        .text("Hello, image!"),
        .image(attributes: ["src": "cid:test-pngFile@swift.mail.message"]),
      ]
    )
    var htmlContent = RichText.HTMLContent(xhtml: xhtml, resources: [pngFile])
    htmlContent.boundary = "test-html-boundary"
    var richText = RichText(plainText: plainText, htmlContent: htmlContent)
    richText.boundary = "test-rich-text-boundary"
    var body = FileAttachedBody(mainBody: richText, files: [shortTextFile])
    body.boundary = "test-file-boundary"
    let message = MailMessage(
      recipients: Group([
        try XCTUnwrap(Person(mailAddress: "recipient@example.com"))
      ]),
      subject: "Full Message",
      body: body
    )

    XCTAssertEqual(
      try message.deliverableDescription(using: .utf8),
      """
      To: recipient@example.com\(CRLF)\
      Subject: Full Message\(CRLF)\
      Content-Type: multipart/mixed; boundary=test-file-boundary\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      This is a multi-part message in MIME format.\(CRLF)\
      \(CRLF)\
      --test-file-boundary\(CRLF)\
      Content-Type: multipart/alternative; boundary=test-rich-text-boundary\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      --test-rich-text-boundary\(CRLF)\
      Content-Type: text/plain; charset=us-ascii\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      Hello, many resources!\(CRLF)\
      --test-rich-text-boundary\(CRLF)\
      Content-Type: multipart/related; boundary=test-html-boundary;\(CRLF)\
       type="text/html"\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      --test-html-boundary\(CRLF)\
      Content-Type: text/html; charset=utf-8\(CRLF)\
      Content-Transfer-Encoding: quoted-printable\(CRLF)\
      \(CRLF)\
      <?xml version=3D"1.0" encoding=3D"utf-8"?>\(CRLF)\
      <!DOCTYPE html>\(CRLF)\
      <html xmlns=3D"http://www.w3.org/1999/xhtml"><head><title>title</title></he=\(CRLF)\
      ad><body>Hello, image!<img src=3D"cid:test-pngFile@swift.mail.message" /></=\(CRLF)\
      body></html>\(CRLF)\
      --test-html-boundary\(CRLF)\
      Content-Disposition: attachment;\(CRLF)\
       filename*0*=utf-8''%E7%B9%B0%E3%82%8A%E8%BF%94%E3%81%97%E3%82%92%E9%81%A9;\(CRLF)\
       filename*1*=%E7%94%A8%E3%81%99%E3%82%8B%E3%81%93%E3%81%A8%E3%81%A7;\(CRLF)\
       filename*2*=%E6%A8%AA%E7%B8%9E%E6%A8%A1%E6%A7%98%E3%81%AB%E4%BD%BF;\(CRLF)\
       filename*3*=%E3%81%86%E3%81%93%E3%81%A8%E3%81%8C%E3%81%A7%E3%81%8D;\(CRLF)\
       filename*4*=%E3%82%8B%E5%B0%8F%E3%81%95%E3%81%AA%E7%94%BB%E5%83%8F.png\(CRLF)\
      Content-Type: image/png\(CRLF)\
      Content-ID: <test-pngFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(pngFileBase64)\(CRLF)\
      --test-html-boundary--\(CRLF)\
      \(CRLF)\
      --test-rich-text-boundary--\(CRLF)\
      \(CRLF)\
      --test-file-boundary\(CRLF)\
      Content-Disposition: attachment; filename=short.txt\(CRLF)\
      Content-Type: text/plain\(CRLF)\
      Content-ID: <test-shortTextFile@swift.mail.message>\(CRLF)\
      Content-Transfer-Encoding: base64\(CRLF)\
      \(CRLF)\
      \(shortTextFileBase64)\(CRLF)\
      --test-file-boundary--\(CRLF)
      """
    )
  }
}
#endif
