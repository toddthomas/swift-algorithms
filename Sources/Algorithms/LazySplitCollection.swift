//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Algorithms open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// A collection that lazily splits a base collection into subsequences
/// separated by elements that satisfy the given `whereSeparator` predicate.
///
/// - Note: This type is the result of
///
///     x.split(maxSplits:omittingEmptySubsequences:whereSeparator)
///     x.split(separator:maxSplits:omittingEmptySubsequences)
///
///   where `x` conforms to `LazyCollectionProtocol`.
public struct LazySplitCollection<Base: Collection> {
  internal let base: Base
  internal let isSeparator: (Base.Element) -> Bool
  internal let maxSplits: Int
  internal let omittingEmptySubsequences: Bool
  internal var _startIndex: Index
  internal let _endIndex: Index

  internal init(
    base: Base,
    isSeparator: @escaping (Base.Element) -> Bool,
    maxSplits: Int,
    omittingEmptySubsequences: Bool
  ) {
    self.base = base
    self.isSeparator = isSeparator
    self.maxSplits = maxSplits
    self.omittingEmptySubsequences = omittingEmptySubsequences
    self._endIndex = Index.end

    /// We precalculate `startIndex`. There are three possibilities:
    /// 1. `base` is empty and we're _not_ omitting empty subsequences, in which
    /// case the following index describes the sole element of this collection;
    self._startIndex = Index(
      baseRange: base.startIndex..<base.startIndex,
      sequenceLength: 1,
      splitCount: 0
    )
    if base.isEmpty {
      if omittingEmptySubsequences {
        /// 2. `base` is empty and we _are_ omitting empty subsequences, so this
        /// collection has no elements;
        _startIndex = _endIndex
      }
    } else {
      /// 3. `base` isn't empty, so we must iterate it to determine the start index.
      _startIndex = indexForSubsequence(
        atOrAfter: base.startIndex,
        sequenceLength: 0,
        splitCount: 0
      )
    }
  }
}

extension LazySplitCollection: LazyCollectionProtocol {
  /// Position of a subsequence in a split collection.
  public struct Index: Comparable {
    internal enum Representation: Equatable {
      /// A subsequence in the collection.
      case element(
            /// The range corresponding to the subsequence at this position.
            baseRange: Range<Base.Index>,
            /// The number of subsequences up to and including this position in the
            /// collection.
            sequenceLength: Int,
            /// The number of splits performed up to and including this
            /// position in the collection.
            splitCount: Int
           )
      /// The end of the collection.
      case end
    }

    internal let representation: Representation

    /// Initialize an `Index` with an `element` representation.
    internal init(
      baseRange: Range<Base.Index>,
      sequenceLength: Int,
      splitCount: Int
    ) {
      self.representation = Representation.element(
        baseRange: baseRange,
        sequenceLength: sequenceLength,
        splitCount: splitCount
      )
    }

    /// Initialize an `Index` with an `end` representation.
    internal init() {
      self.representation = Representation.end
    }

    internal static var end: Index {
      Index()
    }

    public static func < (lhs: Index, rhs: Index) -> Bool {
      switch (lhs.representation, rhs.representation) {
      case let (.element(leftRange, _, _), .element(rightRange, _, _)):
        return leftRange.lowerBound < rightRange.lowerBound
      case (.element, .end):
        return true
      case (.end, .element):
        return false
      case (.end, .end):
        return false
      }
    }
  }

  /// Returns the index of the subsequence starting at or after the given base collection index.
  internal func indexForSubsequence(
    atOrAfter lowerBound: Base.Index,
    sequenceLength: Int,
    splitCount: Int
  ) -> Index {
    var newSplitCount = splitCount
    var start = lowerBound
    // If we don't have any more splits to do (which we'll determine shortly),
    // the end of the next subsequence will be the end of the base collection.
    var end = base.endIndex

    // The number of separators encountered thus far is identical to the number
    // of splits performed thus far.
    if newSplitCount < maxSplits {
      // The non-inclusive end of the next subsequence is marked by the next
      // separator, or the end of the base collection.
      end =
        base[start...].firstIndex(where: isSeparator)
        ?? base.endIndex

      if base[start..<end].isEmpty {
        if omittingEmptySubsequences {
          // Find the next subsequence of non-separators.
          start =
            base[end...].firstIndex(where: { !isSeparator($0) })
            ?? base.endIndex
          if start == base.endIndex {
            // No non-separators left in the base collection. We're done.
            return endIndex
          }
          end = base[start...].firstIndex(where: isSeparator) ?? base.endIndex
        }
      }
    }

    if end < base.endIndex {
      newSplitCount += 1
    }

    return Index(
      baseRange: start..<end,
      sequenceLength: sequenceLength + 1,
      splitCount: newSplitCount
    )
  }

  public var startIndex: Index {
    _startIndex
  }

  public var endIndex: Index {
    _endIndex
  }

  public func index(after i: Index) -> Index {
    precondition(i != endIndex, "Can't advance past endIndex")

    switch i.representation {
    case let .element(baseRange, sequenceLength, splitCount):
      var subsequenceStart = baseRange.upperBound
      if subsequenceStart < base.endIndex {
        // If we're not already at the end of the base collection, the previous
        // susequence ended with a separator. Start searching for the next
        // subsequence at the following element.
        subsequenceStart = base.index(after: baseRange.upperBound)
      }

      guard subsequenceStart != base.endIndex else {
        if !omittingEmptySubsequences
          && sequenceLength < splitCount + 1
        {
          // The base collection ended with a separator, so we need to emit one
          // more empty subsequence positioned just after the last element of
          // the base collection.
          return Index(
            baseRange: base.endIndex..<base.endIndex,
            sequenceLength: sequenceLength + 1,
            splitCount: splitCount
          )
        } else {
          return endIndex
        }
      }

      return indexForSubsequence(
        atOrAfter: subsequenceStart,
        sequenceLength: sequenceLength,
        splitCount: splitCount
      )
    case .end:
      assert(false, "Can't advance past endIndex")
    }
  }

  public subscript(position: Index) -> Base.SubSequence {
    precondition(position != endIndex, "Can't subscript using endIndex")
    switch position.representation {
    case let .element(range, _, _):
      return base[range]
    case .end:
      assert(false, "Can't subscript using endIndex")
    }
  }
}

//extension LazySplitCollection.Index: Hashable where Base.Index: Hashable {}

extension LazyCollectionProtocol {
  /// Lazily returns the longest possible subsequences of the collection, in order,
  /// that don't contain elements satisfying the given predicate.
  ///
  /// The resulting lazy collection consists of at most `maxSplits + 1` subsequences.
  /// Elements that are used to split the collection are not returned as part of any
  /// subsequence (except possibly the last one, in the case where `maxSplits` is
  /// less than the number of separators in the collection).
  ///
  /// The following examples show the effects of the `maxSplits` and
  /// `omittingEmptySubsequences` parameters when lazily splitting a string using a
  /// closure that matches spaces. The first use of `split` returns each word
  /// that was originally separated by one or more spaces.
  ///
  ///     let line = "BLANCHE:   I don't want realism. I want magic!"
  ///     for spaceless in line.lazy.split(whereSeparator: { $0 == " " }) {
  ///       print(spaceless)
  ///     }
  ///     // Prints
  ///     // BLANCHE:
  ///     // I
  ///     // don't
  ///     // want
  ///     // realism.
  ///     // I
  ///     // want
  ///     // magic!
  ///
  /// The second example passes `1` for the `maxSplits` parameter, so the
  /// original string is split just once, into two new strings.
  ///
  ///     for spaceless in line.lazy.split(
  ///       maxSplits: 1,
  ///       whereSeparator: { $0 == " " }
  ///     ) {
  ///       print(spaceless)
  ///     }
  ///     // Prints
  ///     // BLANCHE:
  ///     // I don't want realism. I want magic!
  ///
  /// The final example passes `false` for the `omittingEmptySubsequences`
  /// parameter, so the returned array contains empty strings where spaces
  /// were repeated.
  ///
  ///     for spaceless in line.lazy.split(
  ///       omittingEmptySubsequences: false,
  ///       whereSeparator: { $0 == " " }
  ///     ) {
  ///       print(spaceless)
  ///     }
  ///     // Prints
  ///     // BLANCHE:
  ///     //
  ///     //
  ///     // I
  ///     // don't
  ///     // want
  ///     // realism.
  ///     // I
  ///     // want
  ///     // magic!
  ///
  /// - Parameters:
  ///   - maxSplits: The maximum number of times to split the collection, or
  ///     one less than the number of subsequences to return. If
  ///     `maxSplits + 1` subsequences are returned, the last one is a suffix
  ///     of the original collection containing the remaining elements.
  ///     `maxSplits` must be greater than or equal to zero. The default value
  ///     is `Int.max`.
  ///   - omittingEmptySubsequences: If `false`, an empty subsequence is
  ///     returned in the result for each pair of consecutive elements
  ///     satisfying the `isSeparator` predicate and for each element at the
  ///     start or end of the collection satisfying the `isSeparator`
  ///     predicate. The default value is `true`.
  ///   - whereSeparator: A closure that takes an element as an argument and
  ///     returns a Boolean value indicating whether the collection should be
  ///     split at that element.
  /// - Returns: A lazy collection of subsequences, split from this collection's
  ///   elements.
  ///
  /// - Complexity: O(*n*), where *n* is the length of the collection.
  public func split(
    maxSplits: Int = Int.max,
    omittingEmptySubsequences: Bool = true,
    whereSeparator isSeparator: @escaping (Element) -> Bool
  ) -> LazySplitCollection<Elements> {
    precondition(maxSplits >= 0, "Must take zero or more splits")

    return LazySplitCollection(
      base: elements,
      isSeparator: isSeparator,
      maxSplits: maxSplits,
      omittingEmptySubsequences: omittingEmptySubsequences
    )
  }
}

extension LazyCollectionProtocol
where Element: Equatable {
  /// Lazily returns the longest possible subsequences of the collection, in order,
  /// around elements equal to the given element.
  ///
  /// The resulting lazy collection consists of at most `maxSplits + 1` subsequences.
  /// Elements that are used to split the collection are not returned as part of any
  /// subsequence (except possibly the last one, in the case where `maxSplits` is
  /// less than the number of separators in the collection).
  ///
  /// The following examples show the effects of the `maxSplits` and
  /// `omittingEmptySubsequences` parameters when splitting a string at each
  /// space character (" "). The first use of `split` returns each word that
  /// was originally separated by one or more spaces.
  ///
  ///     let line = "BLANCHE:   I don't want realism. I want magic!"
  ///     for spaceless in line.lazy.split(separator: " ") {
  ///       print(spaceless)
  ///     }
  ///     // Prints
  ///     // BLANCHE:
  ///     // I
  ///     // don't
  ///     // want
  ///     // realism.
  ///     // I
  ///     // want
  ///     // magic!
  ///
  /// The second example passes `1` for the `maxSplits` parameter, so the
  /// original string is split just once, into two new strings.
  ///
  ///     for spaceless in line.lazy.split(separator: " ", maxSplits: 1) {
  ///       print(spaceless)
  ///     }
  ///     // Prints
  ///     // BLANCHE:
  ///     // I don't want realism. I want magic!
  ///
  /// The final example passes `false` for the `omittingEmptySubsequences`
  /// parameter, so the returned array contains empty strings where spaces
  /// were repeated.
  ///
  ///     for spaceless in line.lazy.split(
  ///       separator: " ",
  ///       omittingEmptySubsequences: false
  ///     ) {
  ///       print(spaceless)
  ///     }
  ///     // Prints
  ///     // BLANCHE:
  ///     //
  ///     //
  ///     // I
  ///     // don't
  ///     // want
  ///     // realism.
  ///     // I
  ///     // want
  ///     // magic!
  ///
  /// - Parameters:
  ///   - separator: The element that should be split upon.
  ///   - maxSplits: The maximum number of times to split the collection, or
  ///     one less than the number of subsequences to return. If
  ///     `maxSplits + 1` subsequences are returned, the last one is a suffix
  ///     of the original collection containing the remaining elements.
  ///     `maxSplits` must be greater than or equal to zero. The default value
  ///     is `Int.max`.
  ///   - omittingEmptySubsequences: If `false`, an empty subsequence is
  ///     returned in the result for each consecutive pair of `separator`
  ///     elements in the collection and for each instance of `separator` at
  ///     the start or end of the collection. If `true`, only nonempty
  ///     subsequences are returned. The default value is `true`.
  /// - Returns: A lazy collection of subsequences split from this collection's
  ///   elements.
  ///
  /// - Complexity: O(*n*), where *n* is the length of the collection.
  public func split(
    separator: Element,
    maxSplits: Int = Int.max,
    omittingEmptySubsequences: Bool = true
  ) -> LazySplitCollection<Elements> {
    precondition(maxSplits >= 0, "Must take zero or more splits")

    return LazySplitCollection(
      base: elements,
      isSeparator: { $0 == separator },
      maxSplits: maxSplits,
      omittingEmptySubsequences: omittingEmptySubsequences
    )
  }
}
