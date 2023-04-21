/* *************************************************************************************************
 Person.swift
   © 2021,2023 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */

import UnicodeSupplement
import yExtensions

/// Represents `mailbox` defined in [RFC 5322](https://tools.ietf.org/html/rfc5322).
///
/// Note: Each properties will not be validated as of now.
public struct Person: LosslessStringConvertible, Equatable, Hashable {
  /// The person's name
  public var displayName: String?

  /// The person's mail address
  public var mailAddress: MailAddress

  public init(displayName: String? = nil, mailAddress: MailAddress) {
    self.displayName = displayName
    self.mailAddress = mailAddress
  }

  public init?(displayName: String? = nil, mailAddress: String) {
    guard let mailAddress = MailAddress(mailAddress) else {
      return nil
    }
    self.init(displayName: displayName, mailAddress: mailAddress)
  }

  public var description: String {
    guard let displayName = self.displayName else {
      return mailAddress.description
    }
    return "\(displayName) <\(mailAddress.description)>"
  }

  /// Instantiates an instance of the conforming type from a string representation.
  ///
  /// Validation is poor as of now.
  public init?(_ description: String) {
    let valueDescription = description.trimmingUnicodeScalars(where: \.latestProperties.isWhitespace || \.latestProperties.isNewline)
    if valueDescription.hasSuffix(">") {
      guard let ltIndex = valueDescription.lastIndex(of: "<") else {
        return nil
      }
      let mailAddressStartIndex = valueDescription.index(after: ltIndex)
      let mailAddressEndIndex = valueDescription.index(before: valueDescription.endIndex)
      guard let mailAddress = MailAddress(String(valueDescription[mailAddressStartIndex..<mailAddressEndIndex])) else {
        return nil
      }
      let displayName = valueDescription[..<ltIndex].trimmingUnicodeScalars(where: \.latestProperties.isWhitespace || \.latestProperties.isNewline)
      if displayName.isEmpty {
        self.init(displayName: nil, mailAddress: mailAddress)
      } else {
        self.init(displayName: displayName, mailAddress: mailAddress)
      }
    } else {
      guard let mailAddress = MailAddress(valueDescription) else {
        return nil
      }
      self.init(mailAddress: mailAddress)
    }
  }
}

/// Represents `"group"`defined in [RFC 5322](https://tools.ietf.org/html/rfc5322).
@dynamicMemberLookup
public struct Group: LosslessStringConvertible, BidirectionalCollection, RangeReplaceableCollection, Equatable, Hashable {
  public var persons: [Person]

  public typealias Iterator =  Array<Person>.Iterator
  public typealias Index = Array<Person>.Index

  public func makeIterator() -> Array<Person>.Iterator {
    return persons.makeIterator()
  }

  public var startIndex: Array<Person>.Index {
    return persons.startIndex
  }

  public var endIndex: Array<Person>.Index {
    return persons.endIndex
  }

  public func index(after i: Array<Person>.Index) -> Array<Person>.Index {
    return persons.index(after: i)
  }

  public func index(before i: Array<Person>.Index) -> Array<Person>.Index {
    return persons.index(before: i)
  }

  public subscript(position: Array<Person>.Index) -> Person {
    get {
      return persons[position]
    }
    set {
      persons[position] = newValue
    }
  }

  public init() {
    persons = []
  }

  public init<S>(_ persons: S) where S: Sequence, S.Element == Person {
    self.persons = Array(persons)
  }

  public mutating func append(_ person: Person) {
    persons.append(person)
  }

  public mutating func append<S>(contentsOf persons: S) where S: Sequence, S.Element == Person {
    self.persons.append(contentsOf: persons)
  }

  public mutating func replaceSubrange<C>(
    _ subrange: Range<Array<Person>.Index>,
    with newElements: C
  ) where C: Collection, Person == C.Element {
    self.persons.replaceSubrange(subrange, with: newElements)
  }

  public subscript<T>(dynamicMember key: KeyPath<Array<Person>, T>) -> T {
    return persons[keyPath: key]
  }

  public subscript<T>(dynamicMember key: WritableKeyPath<Array<Person>, T>) -> T {
    get {
      return persons[keyPath: key]
    }
    set {
      persons[keyPath: key] = newValue
    }
  }

  public var description: String {
    return persons.map({ $0.description }).joined(separator: ",")
  }

  public init?(_ description: String) {
    let valueDescription = description.trimmingUnicodeScalars(where: \.latestProperties.isWhitespace || \.latestProperties.isNewline)
    var persons: [Person] = []
    for personDescription in valueDescription.split(separator: ",") {
      guard let person = Person(String(personDescription)) else { return nil }
      persons.append(person)
    }
    self.init(persons)
  }
}
