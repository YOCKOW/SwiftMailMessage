/* *************************************************************************************************
 MIMESafeData.swift
   © 2021,2024,2026 YOCKOW.
     Licensed under MIT License.
     See "LICENSE.txt" for more information.
 ************************************************************************************************ */

// TODO: Integrate with NetworkGear

import NetworkGear

public typealias UInt7 = NetworkGear.UInt7

public typealias MIMESafeData = NetworkGear.MIMESafeData

internal extension MIMESafeData {
  static let CRLF: MIMESafeData = MIMESafeData([0x0D, 0x0A])
}
