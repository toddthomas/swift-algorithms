//
//  File.swift
//  
//
//  Created by Todd Thomas on 2/28/21.
//

@testable import Algorithms
import XCTest

final class LazySplitCollectionIndexTests: XCTestCase {
  var parts: LazySplitCollection<[Int]> {
    [42, 1, 42, 2, 42].lazy.split(separator: 42)
  }

  func testOperatorEqualTo() {
    let start = parts.startIndex
    let end = parts.endIndex
    XCTAssertFalse(start == end)
    XCTAssertTrue(start == parts.startIndex)
    XCTAssertTrue(end == parts.endIndex)
  }
  func testOperatorLessThan() {
    let start = parts.startIndex
    let end = parts.endIndex
    XCTAssertTrue(start < end)
    XCTAssertTrue(end > start)
    XCTAssertFalse(end < start)
    XCTAssertFalse(end < end)
    XCTAssertFalse(end > end)
  }
}
