# What is `SwiftMailMessage`?

It will provide a representation of mail message.
It does *not* provide functions like a mailer.

# Requirements

- Swift >=6.2
- macOS(>=13.0) or Linux

## Dependencies

<!-- SWIFT PACKAGE DEPENDENCIES MERMAID START -->
```mermaid
---
title: MailMessage Dependencies
---
flowchart TD
  swiftbootstring(["Bootstring<br>@1.2.0"])
  swiftmailmessage["MailMessage"]
  swiftnetworkgear(["NetworkGear<br>@0.21.1"])
  swiftpublicsuffix(["PublicSuffix<br>@2.4.29"])
  swiftranges(["Ranges<br>@4.0.2"])
  swiftstringcomposition(["StringComposition<br>@3.0.0"])
  swifttemporaryfile(["TemporaryFile<br>@5.0.0"])
  swiftunicodesupplement(["UnicodeSupplement<br>@2.0.1"])
  swiftxhtml(["XHTML<br>@3.0.0"])
  yswiftextensions(["yExtensions<br>@2.2.1"])

  click swiftbootstring href "https://github.com/YOCKOW/SwiftBootstring.git"
  click swiftnetworkgear href "https://github.com/YOCKOW/SwiftNetworkGear.git"
  click swiftpublicsuffix href "https://github.com/YOCKOW/SwiftPublicSuffix.git"
  click swiftranges href "https://github.com/YOCKOW/SwiftRanges.git"
  click swiftstringcomposition href "https://github.com/YOCKOW/SwiftStringComposition.git"
  click swifttemporaryfile href "https://github.com/YOCKOW/SwiftTemporaryFile.git"
  click swiftunicodesupplement href "https://github.com/YOCKOW/SwiftUnicodeSupplement.git"
  click swiftxhtml href "https://github.com/YOCKOW/SwiftXHTML.git"
  click yswiftextensions href "https://github.com/YOCKOW/ySwiftExtensions.git"

  swiftmailmessage --> swiftnetworkgear
  swiftmailmessage ----> swiftranges
  swiftmailmessage --> swiftunicodesupplement
  swiftmailmessage --> swiftxhtml
  swiftmailmessage --> yswiftextensions
  swiftnetworkgear ----> swiftbootstring
  swiftnetworkgear ----> swiftpublicsuffix
  swiftnetworkgear ----> swiftranges
  swiftnetworkgear --> swifttemporaryfile
  swiftnetworkgear --> swiftunicodesupplement
  swiftnetworkgear --> yswiftextensions
  swiftstringcomposition --> yswiftextensions
  swifttemporaryfile ----> swiftranges
  swifttemporaryfile --> yswiftextensions
  swiftunicodesupplement ----> swiftranges
  swiftxhtml --> swiftnetworkgear
  swiftxhtml ----> swiftranges
  swiftxhtml --> swiftstringcomposition
  swiftxhtml --> swiftunicodesupplement
  swiftxhtml --> yswiftextensions
  yswiftextensions ----> swiftranges
  yswiftextensions --> swiftunicodesupplement


```
<!-- SWIFT PACKAGE DEPENDENCIES MERMAID END -->


# Usage

You can get a text or data representation for a mail message like below.
- The output can be used for `sendmail -i -t`'s standard input.
- You can also use [Gmail API's Message](https://developers.google.com/gmail/api/reference/rest/v1/users.messages#Message) after the output is encoded with Base64.

## Plain Text Message

```Swift
import MailMessage

let body = PlainText(
  text: """
    Hello, World!
    こんにちは、世界！
    """,
  stringEncoding: .iso2022JP,
  contentTransferEncoding: ._7bit
)
let message = MailMessage(
  author: Person(displayName: "Author", mailAddress: "author@example.com"),
  recipients: Group([Person(displayName: "Recipient", mailAddress: "recipient@example.com")]),
  subject: "My First Mail Message. - 私の初めてのメールメッセージ -",
  body: body
)

print(try message.deliverableDescription(using: .iso2022JP))
/*
== OUTPUT ==
From: Author <author@example.com>
To: Recipient <recipient@example.com>
Subject: My First Mail Message. - =?iso-2022-jp?B?GyRCO2QkTj1pJGEbKEI=?=
 =?iso-2022-jp?B?GyRCJEYkTiVhITwlayVhJUMlOyE8JTgbKEI=?= -
Content-Transfer-Encoding: 7bit
Content-Type: text/plain; charset=iso-2022-jp

Hello, World!
$B$3$s$K$A$O!"@$3&!*(B

*/

```


## Rich Text Message (XHTML)

```Swift
import MailMessage
import XHTML

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
let richText = RichText(plainText: plainText, htmlContent: htmlContent)

let message = MailMessage(
  recipients: Group([Person(mailAddress: "recipient@example.com")]),
  subject: "Rich Text Mail",
  body: richText
)

print(try message.deliverableDescription())

/*
== OUTPUT ==
To: recipient@example.com
Subject: Rich Text Mail
Content-Type: multipart/alternative;
 boundary="6v1YAWqdQCUybGGiWXME4RXQ--git.io/JOYPU"
Content-Transfer-Encoding: quoted-printable

--6v1YAWqdQCUybGGiWXME4RXQ--git.io/JOYPU
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: quoted-printable

Hello, HTML!
--6v1YAWqdQCUybGGiWXME4RXQ--git.io/JOYPU
Content-Type: text/html; charset=utf-8
Content-Transfer-Encoding: quoted-printable

<?xml version=3D"1.0" encoding=3D"utf-8"?>
<!DOCTYPE html>
<html xmlns=3D"http://www.w3.org/1999/xhtml"><head><title>XHTML Title</titl=
e></head><body><div>XHTML</div></body></html>
--6v1YAWqdQCUybGGiWXME4RXQ--git.io/JOYPU--
*/

```


## Attach Files

```Swift
import MailMessage
import XHTML

let plainText = PlainText(
  text: "Hello, many resources!",
  stringEncoding: .ascii,
  contentTransferEncoding: .quotedPrintable
)
let pngFile = File(
  filename: "samll.png",
  contentType: MIMEType(pathExtension: .png)!,
  contentID: ContentID(rawValue: "<some-content-id@swift.mail.message>")!,
  content: InputStream(url: pngFileURL)!
)
let xhtml = XHTMLDocument.template(
  title: "title",
  contents: [
    .text("Hello, image!"),
    .image(attributes: ["src": "cid:some-content-id@swift.mail.message"]),
  ]
)
let htmlContent = RichText.HTMLContent(xhtml: xhtml, resources: [pngFile])
let richText = RichText(plainText: plainText, htmlContent: htmlContent)
let body = FileAttachedBody(mainBody: richText, files: [shortTextFile])
let message = MailMessage(
  recipients: Group([Person(mailAddress: "recipient@example.com")]),
  subject: "Full Message",
  body: body
)

print(try message.deliverableDescription())

// OUTPUT omitted

```


# License

MIT License.  
See "LICENSE.txt" for more information.
