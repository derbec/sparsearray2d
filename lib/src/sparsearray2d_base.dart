// Copyright (c) 2022, Derek Becker
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//  * Neither the name of  nor the names of its contributors may be used to
//    endorse or promote products derived from this software without specific
//    prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

import 'dart:collection';
import 'package:collection/collection.dart';

/// (2^53)-1 because javascript
const int _maxSafeInteger = 9007199254740991;

/// null safe cast
T? _castNullSafe<T>(final x) => x is T ? x : null;

/// An index along an axis in dense format
typedef DenseIndex = int;

/// Zero based index along row axis in dense format
typedef DenseRowIndex = int;

/// Zero based index along column axis in dense format
typedef DenseColumnIndex = int;

/// Base for all nodes in graph
abstract class _Node<E> {
  _Node(this._owner, this.rowIndex, this.columnIndex, this._nodeN, this._nodeE,
      this._nodeS, this._nodeW);

  /// An index for when no index is wanted.
  static const DenseRowIndex noIndex = -1;

  /// The row portion of this objects location in the [SparseArray2D]
  final DenseRowIndex rowIndex;

  /// The column portion of this objects location in the [SparseArray2D]
  final DenseColumnIndex columnIndex;

  _Node<E>? _nodeN, _nodeE, _nodeS, _nodeW;

  /// If this value is null then node does not belong to a graph and is invalid.
  SparseArray2D<E>? _owner;

  /// [SparseArray2D] this node belongs to.
  ///
  /// Throws [StateError] if node has no owner.
  SparseArray2D<E> get owner {
    final owner = _owner;
    if (identical(owner, null)) {
      throw StateError('Node has no owner');
    }
    return owner;
  }

  /// Return true if this belongs to a [SparseArray2D].
  ///
  /// If false then this has no siblings or child elements.
  ///
  /// Note: If false and this is an [Iterable] then attempting to iterate will
  /// throw [StateError].
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// final element = sparse.elementAt(0, 1);
  /// final row = sparse.rowAt(2);
  /// final column = sparse.columnAt(2);
  ///
  /// print(element!.isValid);
  /// print(row!.isValid);
  /// print(column!.isValid);
  ///
  /// print('--------');
  ///
  /// sparse.remove(element.rowIndex, element.columnIndex);
  /// sparse.removeRow(row.index);
  /// sparse.removeColumn(row.index);
  ///
  /// print(element.isValid);
  /// print(row.isValid);
  /// print(column.isValid);
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// true
  /// true
  /// true
  /// --------
  /// false
  /// false
  /// false
  /// ```
  bool get isValid => !identical(_owner, null);

  /// Disconnect from graph
  void _invalidate() {
    _owner = null;
    _nodeE = null;
    _nodeW = null;
    _nodeS = null;
    _nodeN = null;
  }
}

/// An object that ensures owner has not changed version.
abstract class _OwnerVersionedObject<E> {
  _OwnerVersionedObject(this.owner) : _validVersion = owner._version;
  final SparseArray2D<E> owner;
  final int _validVersion;

  /// Ensure owner has not changed since this object was created.
  void _checkVersion() {
    if (owner._version != _validVersion) {
      throw ConcurrentModificationError();
    }
  }
}

/// Iterate sequence of [Element].
abstract class _ElementIterator<E> extends _OwnerVersionedObject<E>
    implements Iterator<Element<E>> {
  _ElementIterator._(super.owner);

  Element<E>? _current;

  @override
  Element<E> get current => _current!;
}

/// An iterable sequence of [Element] representing sparse values.
///
/// Use [dense] to access values in dense format.
///
/// Maintains links to siblings via [this.previous] and [this.next].
///
/// Throws [ConcurrentModificationError] if [this] changes during iteration.
///
/// Throws [StateError] during iteration if [this.isValid] is false.
abstract class ElementIterable<E> extends _Node<E>
    with IterableMixin<Element<E>> {
  ElementIterable._(
      final SparseArray2D<E> owner,
      final DenseRowIndex row,
      final DenseColumnIndex column,
      final _Node<E>? previousRow,
      final _Node<E>? previousCol,
      final _Node<E>? nextRow,
      final _Node<E>? nextColumn,
      this.index)
      : super(
            owner, row, column, previousRow, nextColumn, nextRow, previousCol);

  /// Index of this [ElementIterable] within the [SparseArray2D].
  ///
  /// If this represents a row then [index] is a rowIndex, otherwise is a
  /// columnIndex.
  final DenseIndex index;

  // Reference to first element
  // This element always points back to this element iterable.
  Element<E>? _head;
  // Reference to last element allows discovery of max row/column index.
  // This element always points back to this ElementIterable.
  Element<E>? _tail;

  int _length = 0;

  /// Return number of elements to be iterated.
  ///
  /// Note: This simply returns a precalculated value and is thus efficient.
  @override
  int get length => _length;

  /// Return element from this [ElementIterable] at position [index] assuming dense
  /// representation.
  ///
  /// Equivilent to [elementAt] if missing elements were included.
  ///
  /// Return null if no element present at [index].
  ///
  /// Note: Because the [SparseArray2D] is theoretically infinite there
  /// is no upper bounds check on [index];
  ///
  /// See [DenseValueIterable] for explanation of dense format.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// final sparse = SparseArray2D<String>();
  ///
  /// sparse.put(2, 0, 'a');
  /// sparse.put(2, 1, 'b');
  /// sparse.put(2, 5, 'c');
  /// sparse.put(2, 8, 'd');
  /// sparse.put(0, 5, 'e');
  ///
  /// final row = sparse.rowAt(2);
  /// final col = sparse.columnAt(5);
  ///
  /// print(row); // Sparse row
  /// print(col); // Sparse column
  ///
  /// print('--------');
  ///
  /// print(row!.dense); // Dense row
  /// print(col!.dense); // Dense column
  ///
  /// print('--------');
  /// print(row.elementAt(1)); // Sparse element addressing
  /// print(col.elementAt(1)); // Sparse element addressing
  ///
  /// print('--------');
  /// print(row.elementAtDense(1)); // Dense element addressing
  /// print(col.elementAtDense(1)); // Dense element addressing
  /// print(col.elementAtDense(2)); // Dense element addressing
  /// print(col.elementAtDense(9999999999)); // No upper bounds check
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (2)[(2, 0)[a],(2, 1)[b],(2, 5)[c],(2, 8)[d]]
  /// (5)[(0, 5)[e],(2, 5)[c]]
  /// --------
  /// (a, b, null, null, null, c, null, null, d)
  /// (e, null, c)
  /// --------
  /// (2, 1)[b]
  /// (2, 5)[c]
  /// --------
  /// (2, 1)[b]
  /// null
  /// (2, 5)[c]
  /// null
  /// ```
  Element<E>? elementAtDense(final DenseIndex index);

  /// Returns the first element.
  ///
  /// Returns precalculated value so is efficient with no iteration involved.
  ///
  /// Throws a [StateError] if [this] is empty.
  @override
  Element<E> get first {
    final head = _head;
    if (identical(head, null)) {
      throw StateError("No elements");
    }
    return head;
  }

  /// Returns the last element.
  ///
  /// Returns precalculated value so is efficient with no iteration involved.
  ///
  /// Throws a [StateError] if [this] is empty.
  @override
  Element<E> get last {
    final tail = _tail;
    if (identical(tail, null)) {
      throw StateError("No elements");
    }
    return tail;
  }

  /// Return dense representation.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// final sparse = SparseArray2D<String>();
  ///
  /// sparse.put(2, 0, 'a');
  /// sparse.put(2, 1, 'b');
  /// sparse.put(2, 5, 'c');
  /// sparse.put(2, 8, 'd');
  /// sparse.put(0, 5, 'e');
  ///
  /// final row = sparse.rowAt(2);
  /// final col = sparse.columnAt(5);
  ///
  /// print(row); // Sparse row
  /// print(col); // Sparse column
  ///
  /// print('--------');
  ///
  /// print(row!.dense); // Dense row
  /// print(col!.dense); // Dense column
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (2)[(2, 0)[a],(2, 1)[b],(2, 5)[c],(2, 8)[d]]
  /// (5)[(0, 5)[e],(2, 5)[c]]
  /// --------
  /// (a, b, null, null, null, c, null, null, d)
  /// (e, null, c)
  /// ```
  DenseValueIterable<E> get dense;

  /// Returns the next [ElementIterable] in order.
  ///
  /// See [Row.next], [Column.next].
  ElementIterable<E>? get next;

  /// Returns the next [ElementIterable] in order.
  ///
  /// See [Row.previous], [Column.previous].
  ElementIterable<E>? get previous;

  @override
  String toString() => '($rowIndex)[${join(',')}]';

  /// Disconnect all elements within this iterable
  @override
  void _invalidate() {
    for (final element in this) {
      element._invalidate();
    }
    super._invalidate();
  }
}

/// Manages a sequence of [Element] representing a column.
///
/// Maintains links to siblings via [this.previous] and [this.next].
///
/// Throws [ConcurrentModificationError] if [this] changes during iteration.
///
/// Throws [StateError] during iteration if [this.isValid] is false.
///
/// ```
///    3
/// ┌────┐
/// └─┼──┘
///   │
/// ┌─▼──┐
/// │23,3│
/// │    │
/// └┬─┬─┘
///  │ │
/// ┌┴─┴─┐
/// │24,3│
/// │    │
/// └┬─┬─┘
///  │ │
/// ┌┴─┴─┐
/// │76,3│
/// │    │
/// └────┘
/// ```
///
class Column<E> extends ElementIterable<E> {
  Column._(final SparseArray2D<E> owner, final DenseColumnIndex colIdx,
      final Column<E>? previous, final Column<E>? next)
      : super._(
            owner, _Node.noIndex, colIdx, null, previous, null, next, colIdx);

  /// Insert [value] to column at position [rowIdx].
  Element<E> _insertElement(
      final DenseRowIndex rowIdx, final Element<E> element) {
    final head = _head;

    // Simple case, first element of column
    if (identical(head, null)) {
      _length = 1;
      return _tail = _head = element;
    }

    final tail = _tail!;
    // Can we just add directly to tail
    if (rowIdx > tail.rowIndex) {
      _length++;
      return _tail = tail._nodeS = element.._nodeN = _tail;
    }

    // Find or create element node for col
    final targetNode = _getOrCreateNodeRow(head, rowIdx,
        ((final _Node<E>? previous, final _Node<E>? next) {
      _length++;
      element._nodeN = previous;
      element._nodeS = next;
      return element;
    })) as Element<E>;

    if (targetNode.rowIndex < head.rowIndex) {
      _head = targetNode;
    }

    assert(targetNode.rowIndex == rowIdx);
    assert(_assertIntegrity());
    return targetNode;
  }

  /// Remove [element] from this [Column]
  /// Assumes that element belongs to this [Column].
  void _removeElement(final Element<E> element) {
    if (identical(element, _head)) {
      // First element of column, update head
      _head = _castNullSafe<Element<E>>(element._nodeS);
    } else {
      element._nodeN!._nodeS = element._nodeS;
    }

    if (identical(element, _tail)) {
      // Last element of column, update tail
      _tail = _castNullSafe<Element<E>>(element._nodeN);
    } else {
      element._nodeS!._nodeN = element._nodeN;
    }
    _length--;

    assert(identical(element, _head) ? identical(_head, element._nodeS) : true);
    assert(identical(element, _tail) ? identical(_tail, element._nodeN) : true);
    assert(identical(element._nodeS, null)
        ? true
        : identical(element._nodeS!._nodeN, element._nodeN));
    assert(identical(element._nodeN, null)
        ? true
        : identical(element._nodeN!._nodeS, element._nodeS));
    assert(_assertIntegrity());
  }

  @override
  Element<E>? elementAtDense(final DenseIndex index) {
    _Node<E>? elementNode = _head;
    while (!identical(elementNode, null) && elementNode.rowIndex < index) {
      elementNode = elementNode._nodeS;
    }

    return (identical(elementNode, null) || elementNode.rowIndex != index)
        ? null
        : elementNode as Element<E>;
  }

  @override
  DenseValueIterable<E> get dense => _ElementColIterableDense<E>(this);

  @override
  Iterator<Element<E>> get iterator => _ColumnElementIterator(this);

  /// Return the next [Column] in iteration order.
  ///
  /// Return null if no next [Column] available.
  ///
  /// ```
  ///  This ►►►► Next
  ///    0         ?
  /// ┌────┐    ┌────┐
  /// └─┼──┘    └──┼─┘
  ///   │          │
  /// ┌─▼──┐    ┌──▼─┐
  /// │23,0│    │?,? ├
  /// │    │    │    ├
  /// └┬─┬─┘    └┬─┬─┘
  ///  │ │       │ │
  /// ┌┴─┴─┐    ┌┴─┴─┐
  /// │24,0│    │?,? ├
  /// │    │    │    ├
  /// └┬─┬─┘    └┬─┬─┘
  ///  │ │       │ │
  /// ┌┴─┴─┐    ┌┴─┴─┐
  /// │76,0│    │?,? ├
  /// │    │    │    ├
  /// └────┘    └────┘
  /// ```
  @override
  Column<E>? get next => _castNullSafe<Column<E>>(_nodeE);

  /// Return the previous [Column] in iteration order.
  ///
  /// Return null if no previous [Column] available.
  ///
  /// ```
  /// Previous ◄◄ This
  ///    ?         3
  /// ┌────┐    ┌────┐
  /// └─┼──┘    └──┼─┘
  ///   │          │
  /// ┌─▼──┐    ┌──▼─┐
  /// │?,? │    │23,3├
  /// │    │    │    ├
  /// └┬─┬─┘    └┬─┬─┘
  ///  │ │       │ │
  /// ┌┴─┴─┐    ┌┴─┴─┐
  /// │?,? │    │24,3├
  /// │    │    │    ├
  /// └┬─┬─┘    └┬─┬─┘
  ///  │ │       │ │
  /// ┌┴─┴─┐    ┌┴─┴─┐
  /// │?,? │    │76,3├
  /// │    │    │    ├
  /// └────┘    └────┘
  /// ```
  @override
  Column<E>? get previous => _castNullSafe<Column<E>>(_nodeW);

  @override
  String toString() => '($columnIndex)[${join(',')}]';

  bool _assertIntegrity() {
    assert(_length == 0 ? identical(_head, null) : !identical(_head, null));
    assert(identical(_head, null) ? _length == 0 : _length > 0);
    assert(_length == 0 ? identical(_tail, null) : !identical(_tail, null));
    assert(identical(_tail, null) ? _length == 0 : _length > 0);
    assert(identical(_head, null)
        ? identical(_tail, null)
        : !identical(_tail, null));
    assert(identical(_tail, null)
        ? identical(_head, null)
        : !identical(_head, null));
    assert(identical(previous, null) ? true : previous!.index < index);
    assert(identical(next, null) ? true : next!.index > index);

    return true;
  }
}

/// An [ElementIterable] representing a Row.
///
/// Maintains links to siblings via [this.previous] and [this.next].
///
/// Throws [ConcurrentModificationError] if [SparseArray2D] changes during iteration.
///
/// Throws [StateError] during iteration if [this.isValid] is false.
///
/// ```
///   ┌─┐  ┌────┐    ┌────┐    ┌────┐    ┌────┐
/// 23│ │  │23,0├────┤23,3├────┤23,9├────┤23, │
///   │ ├──►    ├────┤    ├────┤    ├────┤318 │
///   └─┘  └┬─┬─┘    └┬─┬─┘    └┬─┬─┘    └─┬─┬┘
/// ```
class Row<E> extends ElementIterable<E> {
  Row._(final SparseArray2D<E> owner, final DenseRowIndex rowIdx,
      final Row<E>? previous, final Row<E>? next)
      : super._(
            owner, rowIdx, _Node.noIndex, previous, null, next, null, rowIdx);

  @override
  Element<E>? elementAtDense(final DenseIndex index) {
    _Node<E>? elementNode = _head;
    while (!identical(elementNode, null) && elementNode.columnIndex < index) {
      elementNode = elementNode._nodeE;
    }

    return (identical(elementNode, null) || elementNode.columnIndex != index)
        ? null
        : elementNode as Element<E>;
  }

  /// Insert [value] to row at position [col].
  Element<E> _insertElement(final DenseRowIndex col, final E value) {
    assert(!identical(_owner, null));
    final owner = _owner!;
    final head = _head;

    // Simple case, first element of row
    if (identical(head, null)) {
      _length = 1;
      return _tail = _head =
          Element<E>._(owner, rowIndex, col, null, null, null, null, value);
    }

    final tail = _tail!;
    // Can we add directly to tail
    if (col > tail.columnIndex) {
      _length++;
      return _tail = tail._nodeE =
          Element<E>._(owner, rowIndex, col, null, null, null, tail, value);
    }

    // Find or create element node for col
    final targetNode = _getOrCreateNodeCol(head, col,
        ((final _Node<E>? previous, final _Node<E>? next) {
      _length++;
      return Element<E>._(
          owner, rowIndex, col, null, next, null, previous, value);
    })) as Element<E>;

    if (targetNode.columnIndex < head.columnIndex) {
      _head = targetNode;
    }

    assert(targetNode.columnIndex == col);
    assert(_assertIntegrity());
    return targetNode;
  }

  /// Remove element from this row's element list
  /// Assumes that element belongs to this [Row].
  void _removeElement(final Element<E> element) {
    if (identical(element, _head)) {
      // First element of row, update head
      _head = _castNullSafe<Element<E>>(element._nodeE);
    } else {
      element._nodeW!._nodeE = element._nodeE;
    }

    if (identical(element, _tail)) {
      // Last element of row, update tail
      _tail = _castNullSafe<Element<E>>(element._nodeW);
    } else {
      element._nodeE!._nodeW = element._nodeW;
    }
    _length--;

    assert(identical(element._nodeW, null)
        ? identical(_head, element._nodeE)
        : true);
    assert(identical(element._nodeE, null)
        ? identical(_tail, element._nodeW)
        : true);
    assert(identical(element._nodeE, null)
        ? true
        : identical(element._nodeE!._nodeW, element._nodeW));
    assert(identical(element._nodeW, null)
        ? true
        : identical(element._nodeW!._nodeE, element._nodeE));

    assert(_assertIntegrity());
  }

  @override
  DenseValueIterable<E> get dense => _ElementRowIterableDense(this);

  @override
  Iterator<Element<E>> get iterator => _RowElementIterator<E>(this);

  /// Return next [Row] in iteration order.
  ///
  /// Return null if no next row is available.
  ///
  /// ```
  ///         ┌─┐  ┌────┐    ┌────┐    ┌────┐    ┌────┐
  /// This  23│ │  │23,0├────┤23,3├────┤23,9├────┤23, │
  ///  ▼      │ ├──►    ├────┤    ├────┤    ├────┤318 │
  ///  ▼      └─┘  └────┘    └────┘    └────┘    └────┘
  ///  ▼
  ///  ▼      ┌─┐  ┌────┐    ┌────┐    ┌────┐    ┌────┐
  /// Next  ? │ │  │?,? ├────┤?,? ├────┤?,? ├────┤?,? │
  ///         │ ├──►    ├────┤    ├────┤    ├────┤    │
  ///         └─┘  └┬─┬─┘    └┬─┬─┘    └┬─┬─┘    └─┬─┬┘
  /// ```
  @override
  Row<E>? get next => _castNullSafe<Row<E>>(_nodeS);

  /// Return previous [Row] in iteration order.
  ///
  /// Return null if no previous [Row] is available.
  ///
  /// ```
  ///             ┌─┐  ┌────┐    ┌────┐    ┌────┐    ┌────┐
  /// Previous  ? │ │  │ ?,?├────┤?,? ├────┤?,? ├────┤?,? │
  ///  ▲          │ ├──►    ├────┤    ├────┤    ├────┤    │
  ///  ▲          └─┘  └────┘    └────┘    └────┘    └────┘
  ///  ▲
  ///  ▲          ┌─┐  ┌────┐    ┌────┐    ┌────┐    ┌────┐
  /// This      24│ │  │24,0├────┤24,3├────┤24,9├────┤24, │
  ///             │ ├──►    ├────┤    ├────┤    ├────┤318 │
  ///             └─┘  └┬─┬─┘    └┬─┬─┘    └┬─┬─┘    └─┬─┬┘
  /// ```
  @override
  Row<E>? get previous => _castNullSafe<Row<E>>(_nodeN);

  bool _assertIntegrity() {
    assert(_length == 0 ? identical(_head, null) : !identical(_head, null));
    assert(identical(_head, null) ? _length == 0 : _length > 0);
    assert(_length == 0 ? identical(_tail, null) : !identical(_tail, null));
    assert(identical(_tail, null) ? _length == 0 : _length > 0);
    assert(identical(_head, null)
        ? identical(_tail, null)
        : !identical(_tail, null));
    assert(identical(_tail, null)
        ? identical(_head, null)
        : !identical(_head, null));
    assert(identical(previous, null) ? true : previous!.index < index);
    assert(identical(next, null) ? true : next!.index > index);

    return true;
  }
}

/// Represents a single sparse entry.
class Element<E> extends _Node<E> {
  Element._(super.owner, super.row, super.col, super.nodeN, super.nodeE,
      super.nodeS, super.nodeW, this.value);

  /// The value of this [Element].
  ///
  /// **Example:**
  ///
  /// ```dart
  /// final sparse = SparseArray2D<String>();
  ///
  /// final element = sparse.put(2, 0, 'a');
  ///
  /// print(sparse);
  ///
  /// element.value = 'z';
  ///
  /// print(sparse);
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (null)
  /// (null)
  /// (a)
  ///
  /// (null)
  /// (null)
  /// (z)
  /// ```
  E value;

  /// Returns nearest [Element] in East direction.
  /// If no such [Element] exists returns null.
  ///
  /// ```
  ///           ┌────┐
  ///           ┤    ├
  ///           ┤    ├
  ///           └┬─┬─┘
  ///            │ │
  /// ┌┴─┴─┐    ┌┴─┴─┐    ┌┴─┴─┐
  /// │    ├────┤this├────┤ E  ├
  /// │    ├────┤    ├────┤    ├
  /// └┬─┬─┘    └┬─┬─┘    └┬─┬─┘
  ///            │ │
  ///           ┌┴─┴─┐
  ///           ┤    ├
  ///           ┤    ├
  ///           └────┘
  /// ```
  Element<E>? get nextE => _castNullSafe<Element<E>>(_nodeE);

  /// Returns nearest [Element] in West direction.
  /// If no such [Element] exists returns null.
  ///
  /// ```
  ///           ┌────┐
  ///           ┤    ├
  ///           ┤    ├
  ///           └┬─┬─┘
  ///            │ │
  /// ┌┴─┴─┐    ┌┴─┴─┐    ┌┴─┴─┐
  /// │ W  ├────┤this├────┤    ├
  /// │    ├────┤    ├────┤    ├
  /// └┬─┬─┘    └┬─┬─┘    └┬─┬─┘
  ///            │ │
  ///           ┌┴─┴─┐
  ///           ┤    ├
  ///           ┤    ├
  ///           └────┘
  /// ```
  Element<E>? get nextW => _castNullSafe<Element<E>>(_nodeW);

  /// Returns nearest [Element] in South direction.
  /// If no such [Element] exists returns null.
  ///
  /// ```
  ///           ┌────┐
  ///           ┤    ├
  ///           ┤    ├
  ///           └┬─┬─┘
  ///            │ │
  /// ┌┴─┴─┐    ┌┴─┴─┐    ┌┴─┴─┐
  /// │    ├────┤this├────┤    ├
  /// │    ├────┤    ├────┤    ├
  /// └┬─┬─┘    └┬─┬─┘    └┬─┬─┘
  ///            │ │
  ///           ┌┴─┴─┐
  ///           ┤ S  ├
  ///           ┤    ├
  ///           └────┘
  /// ```
  Element<E>? get nextS => _castNullSafe<Element<E>>(_nodeS);

  /// Returns nearest [Element] in North direction.
  /// If no such [Element] exists returns null.
  ///
  /// ```
  ///           ┌────┐
  ///           ┤ N  ├
  ///           ┤    ├
  ///           └┬─┬─┘
  ///            │ │
  /// ┌┴─┴─┐    ┌┴─┴─┐    ┌┴─┴─┐
  /// │    ├────┤this├────┤    ├
  /// │    ├────┤    ├────┤    ├
  /// └┬─┬─┘    └┬─┬─┘    └┬─┬─┘
  ///            │ │
  ///           ┌┴─┴─┐
  ///           ┤    ├
  ///           ┤    ├
  ///           └────┘
  /// ```
  Element<E>? get nextN => _castNullSafe<Element<E>>(_nodeN);

  @override
  String toString() => '($rowIndex, $columnIndex)[$value]';
}

class _RowElementIterator<E> extends _ElementIterator<E> {
  _RowElementIterator(
    this._row,
  ) : super._(_row.owner);

  final Row<E> _row;

  @override
  bool moveNext() {
    _checkVersion();

    if (identical(_current, null)) {
      _current = _row._head;
      return !identical(_current, null);
    }

    final result = _current!._nodeE;
    if (identical(result, null)) {
      return false;
    }

    _current = result as Element<E>;
    return true;
  }
}

class _ColumnElementIterator<E> extends _ElementIterator<E> {
  _ColumnElementIterator(
    this._column,
  ) : super._(_column.owner);

  final Column<E> _column;

  @override
  bool moveNext() {
    _checkVersion();

    if (identical(_current, null)) {
      _current = _column._head;
      return !identical(_current, null);
    }

    final result = _current!._nodeS;
    if (identical(result, null)) {
      return false;
    }

    _current = result as Element<E>;
    return true;
  }
}

/// A dense representation of [ElementIterable] values.
///
/// 'Gaps' between sparse entries are padded with null.
///
/// **Example:**
///
/// ```dart
/// final sparse = SparseArray2D<String>();
///
/// sparse.put(2, 0, 'a');
/// sparse.put(2, 1, 'b');
/// sparse.put(2, 5, 'c');
/// sparse.put(2, 8, 'd');
///
/// final row = sparse.rowAt(2);
///
/// print(row); // Sparse row
///
/// print('--------');
///
/// print(row!.dense); // Dense row
///
/// print('--------');
///
/// sparse.put(4, 6, 'e');
///
/// print(sparse.rows.join('\n')); // Sparse 2D
///
/// print('--------');
///
/// print(sparse.denseRows.join('\n')); // Dense 2D
/// ```
///
/// **Output:**
///
/// ```
/// (2)[(2, 0)[a],(2, 1)[b],(2, 5)[c],(2, 8)[d]]
/// --------
/// (a, b, null, null, null, c, null, null, d)
/// --------
/// (2)[(2, 0)[a],(2, 1)[b],(2, 5)[c],(2, 8)[d]]
/// (4)[(4, 6)[e]]
/// --------
/// (null, null, null, null, null, null, null, null, null)
/// (null, null, null, null, null, null, null, null, null)
/// (a, b, null, null, null, c, null, null, d)
/// (null, null, null, null, null, null, null, null, null)
/// (null, null, null, null, null, null, e, null, null)
/// ```
abstract class DenseValueIterable<E> implements IterableBase<E?> {
  /// Return version of this such that null values are replaced with [value].
  ///
  /// **Example:**
  ///
  /// ```dart
  /// final sparse = SparseArray2D<String>();
  ///
  /// sparse.put(2, 0, 'a');
  /// sparse.put(2, 1, 'b');
  /// sparse.put(2, 5, 'c');
  /// sparse.put(2, 8, 'd');
  ///
  /// final row = sparse.rowAt(2);
  ///
  /// print(row);
  ///
  /// print(row!.dense);
  ///
  /// print(row.dense.withDefault('-'));
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (2)[(2, 0)[a],(2, 1)[b],(2, 5)[c],(2, 8)[d]]
  ///
  /// (a, b, null, null, null, c, null, null, d)
  ///
  /// (a, b, -, -, -, c, -, -, d)
  /// ```
  Iterable<E> withDefault(final E value);
}

class _EmptyDenseValueIterable<E> extends IterableBase<E?>
    implements DenseValueIterable<E> {
  final _iterable = Iterable<E>.empty();
  @override
  Iterator<E?> get iterator => _iterable.iterator;

  @override
  Iterable<E> withDefault(final E value) => _iterable;
}

class _NullDenseValueIterable<E> extends IterableBase<E?>
    implements DenseValueIterable<E> {
  _NullDenseValueIterable(final int length)
      : _iterable = Iterable<E?>.generate(length, ((final index) => null));
  final Iterable<E?> _iterable;
  @override
  Iterator<E?> get iterator => _iterable.iterator;

  @override
  Iterable<E> withDefault(final E value) =>
      Iterable<E>.generate(_iterable.length, ((final index) => value));
}

class _ElementColIterableDense<E> extends IterableBase<E?>
    implements DenseValueIterable<E> {
  _ElementColIterableDense(this._column);
  final Column<E> _column;

  @override
  Iterator<E?> get iterator => _ElementColIteratorDense(_column);

  @override
  Iterable<E> withDefault(final E value) {
    return map((final e) => e ?? value);
  }
}

class _ElementColIteratorDense<E> implements Iterator<E?> {
  _ElementColIteratorDense(
    final Column<E> column,
  )   : _numRows = column.owner.numDenseRows,
        _itr = column.iterator {
    _itrValid = _itr.moveNext();
  }

  final int _numRows;
  final Iterator<Element<E>> _itr;
  int _index = 0;
  bool _itrValid = false;

  E? _current;

  @override
  E? get current => _current;

  @override
  bool moveNext() {
    if (_index >= _numRows) {
      return false;
    }

    if (_itrValid) {
      if (_index < _itr.current.rowIndex) {
        _current = null;
      } else if (_index == _itr.current.rowIndex) {
        _current = _itr.current.value;
        _itrValid = _itr.moveNext();
      }
    } else {
      _current = null;
    }

    _index++;
    return true;
  }
}

class _ElementRowIterableDense<E> extends IterableBase<E?>
    implements DenseValueIterable<E> {
  _ElementRowIterableDense(this._row);
  final Row<E> _row;

  @override
  Iterator<E?> get iterator => _ElementRowIteratorDense(_row);

  @override
  Iterable<E> withDefault(final E value) => map((final e) => e ?? value);
}

class _ElementRowIteratorDense<E> implements Iterator<E?> {
  _ElementRowIteratorDense(
    final Row<E> row,
  )   : _numCols = row.owner.numDenseColumns,
        _itr = row.iterator {
    _itrValid = _itr.moveNext();
  }

  final int _numCols;
  final Iterator<Element<E>> _itr;
  int _index = 0;
  bool _itrValid = false;
  E? _current;

  @override
  E? get current => _current;

  @override
  bool moveNext() {
    if (_index >= _numCols) {
      return false;
    }

    if (_itrValid) {
      if (_index < _itr.current.columnIndex) {
        _current = null;
      } else if (_index == _itr.current.columnIndex) {
        _current = _itr.current.value;
        _itrValid = _itr.moveNext();
      }
    } else {
      _current = null;
    }

    _index++;
    return true;
  }
}

/// Iterable of sparse rows.
///
/// Has efficient length.
///
/// Throws [ConcurrentModificationError] if [SparseArray2D] changes during iteration.
class _RowIterable<E> extends IterableBase<Row<E>> {
  _RowIterable(this._owner);

  final SparseArray2D<E> _owner;

  @override
  Iterator<Row<E>> get iterator => _RowIterator(_owner);

  @override
  int get length => _owner.numSparseRows;
}

class _RowIterator<E> extends _OwnerVersionedObject<E>
    implements Iterator<Row<E>> {
  _RowIterator(final SparseArray2D<E> owner) : super(owner);

  @override
  bool moveNext() {
    _checkVersion();

    if (identical(_current, null)) {
      _current = owner._rowHead;
      return !identical(_current, null);
    }

    final result = _current!.next;
    if (identical(result, null)) {
      return false;
    }

    _current = result;
    return true;
  }

  Row<E>? _current;

  @override
  Row<E> get current => _current!;
}

/// Iterable of dense columns.
///
/// Has efficient length.
///
/// Throws [ConcurrentModificationError] if [SparseArray2D] changes during iteration.
class _ColIterableDense<E> extends IterableBase<DenseValueIterable<E?>> {
  _ColIterableDense(this._owner);

  final SparseArray2D<E> _owner;

  @override
  Iterator<DenseValueIterable<E?>> get iterator => _ColIteratorDense(_owner);

  @override
  int get length => _owner.numDenseColumns;
}

class _ColIteratorDense<E> implements Iterator<DenseValueIterable<E?>> {
  _ColIteratorDense(final SparseArray2D<E> owner)
      : _numRows = owner.numDenseRows,
        _numCols = owner.numDenseColumns,
        _itr = owner.columns.iterator {
    _itrValid = _itr.moveNext();
  }

  final int _numRows, _numCols;
  final Iterator<Column<E>> _itr;
  int _index = 0;
  bool _itrValid = false;
  DenseValueIterable<E> _current = _EmptyDenseValueIterable<E>();

  @override
  bool moveNext() {
    if (_index >= _numCols) {
      return false;
    }

    if (_itrValid) {
      if (_index < _itr.current.index) {
        _current = _NullDenseValueIterable(_numRows);
      } else if (_index == _itr.current.index) {
        _current = _itr.current.dense;
        _itrValid = _itr.moveNext();
      }
    } else {
      _current = _NullDenseValueIterable(_numRows);
    }

    _index++;
    return true;
  }

  @override
  DenseValueIterable<E?> get current => _current;
}

/// Iterable of dense rows.
///
/// Has efficient length.
///
/// Throws [ConcurrentModificationError] if [SparseArray2D] changes during iteration.
class _RowIterableDense<E> extends IterableBase<DenseValueIterable<E?>> {
  _RowIterableDense(this._owner);

  final SparseArray2D<E> _owner;

  @override
  int get length => _owner.numDenseRows;

  @override
  Iterator<DenseValueIterable<E?>> get iterator => _RowIteratorDense(_owner);
}

class _RowIteratorDense<E> implements Iterator<DenseValueIterable<E?>> {
  _RowIteratorDense(final SparseArray2D<E> owner)
      : _numRows = owner.numDenseRows,
        _numCols = owner.numDenseColumns,
        _itr = owner.rows.iterator {
    _itrValid = _itr.moveNext();
  }

  final int _numRows, _numCols;
  final Iterator<ElementIterable<E>> _itr;
  int _index = 0;
  bool _itrValid = false;
  DenseValueIterable<E> _current = _EmptyDenseValueIterable<E>();

  @override
  bool moveNext() {
    if (_index >= _numRows) {
      return false;
    }

    if (_itrValid) {
      if (_index < _itr.current.index) {
        _current = _NullDenseValueIterable(_numCols);
      } else if (_index == _itr.current.index) {
        _current = _itr.current.dense;
        _itrValid = _itr.moveNext();
      }
    } else {
      _current = _NullDenseValueIterable(_numCols);
    }

    _index++;
    return true;
  }

  @override
  DenseValueIterable<E?> get current => _current;
}

/// Iterable of sparse columns.
///
/// Has efficient length.
///
/// Throws [ConcurrentModificationError] if [SparseArray2D] changes during iteration.
class _ColIterable<E> extends IterableBase<Column<E>> {
  _ColIterable(this._owner);

  final SparseArray2D<E> _owner;

  @override
  Iterator<Column<E>> get iterator => _ColIterator(_owner);

  @override
  int get length => _owner.numSparseColumns;
}

class _ColIterator<E> extends _OwnerVersionedObject<E>
    implements Iterator<Column<E>> {
  _ColIterator(super.owner);

  @override
  bool moveNext() {
    _checkVersion();

    if (identical(_current, null)) {
      _current = owner._colHead;
      return !identical(_current, null);
    }

    final result = _current!.next;
    if (identical(result, null)) {
      return false;
    }

    _current = result;
    return true;
  }

  Column<E>? _current;

  @override
  Column<E> get current => _current!;
}

/// A doublely linked graph of [Element]s representing a sparse 2D array.
///
/// Direct mapping of [Row] and [Column] iterables for acceleration.
///
/// Methods addressing [Element] and [ElementIterable] objects assume
/// dense representation.
///
/// See: [DenseValueIterable] for explanation of dense format.
///
/// ```
///          0         3         9         318
///        ┌────┐    ┌────┐    ┌────┐    ┌────┐
///        └─┼──┘    └──┼─┘    └──┼─┘    └─┼──┘
///          │          │         │        │
///   ┌─┐  ┌─▼──┐    ┌──▼─┐    ┌──▼─┐    ┌─▼──┐
/// 23│ │  │23,0├────┤23,3├────┤23,9├────┤23, │
///   │ ├──►    ├────┤    ├────┤    ├────┤318 │
///   └─┘  └┬─┬─┘    └┬─┬─┘    └┬─┬─┘    └─┬─┬┘
///         │ │       │ │       │ │        │ │
///   ┌─┐  ┌┴─┴─┐    ┌┴─┴─┐    ┌┴─┴─┐    ┌─┴─┴┐
/// 24│ │  │24,0├────┤24,3├────┤24,9├────┤24, │
///   │ ├──►    ├────┤    ├────┤    ├────┤318 │
///   └─┘  └┬─┬─┘    └┬─┬─┘    └┬─┬─┘    └─┬─┬┘
///         │ │       │ │       │ │        │ │
///   ┌─┐  ┌┴─┴─┐    ┌┴─┴─┐    ┌┴─┴─┐    ┌─┴─┴┐
/// 76│ │  │76,0├────┤76,3├────┤76,9├────┤76, │
///   │ ├──►    ├────┤    ├────┤    ├────┤318 │
///   └─┘  └────┘    └────┘    └────┘    └────┘
/// ```
class SparseArray2D<E> {
  /// Construct an empty [SparseArray2D] for elements of specified type.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// final sparse = SparseArray2D<int>();
  /// print(sparse.isEmpty);
  /// print(sparse.numDenseRows);
  /// print(sparse.numDenseColumns);
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// true
  /// 0
  /// 0
  /// ```
  SparseArray2D();

  /// Construct a new [SparseArray2D] from [other].
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  /// final copy = SparseArray2D<String>.from(sparse);
  ///
  /// print(sparse.rows.join('\n'));
  ///
  /// print('--------');
  ///
  /// print(copy.rows.join('\n'));
  ///
  /// print('--------');
  ///
  /// print(SparseArray2DEquality<String>().equals(copy, sparse));  ///
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (0)[(0, 0)[a],(0, 1)[b],(0, 2)[c]]
  /// (1)[(1, 2)[a]]
  /// (2)[(2, 0)[d],(2, 2)[c]]
  /// (5)[(5, 0)[e]]
  /// --------
  /// (0)[(0, 0)[a],(0, 1)[b],(0, 2)[c]]
  /// (1)[(1, 2)[a]]
  /// (2)[(2, 0)[d],(2, 2)[c]]
  /// (5)[(5, 0)[e]]
  /// --------
  /// true
  /// ```
  SparseArray2D.from(final SparseArray2D<E> other) {
    for (final element in other.elements) {
      put(element.rowIndex, element.columnIndex, element.value);
    }
  }

  /// Construct a [SparseArray2D] from dense array of objects of specified type,
  /// inserting only non null elements.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.rows.join('\n'));
  ///
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (0)[(0, 0)[a],(0, 1)[b],(0, 2)[c]]
  /// (1)[(1, 2)[a]]
  /// (2)[(2, 0)[d],(2, 2)[c]]
  /// (5)[(5, 0)[e]]
  /// ```
  SparseArray2D.fromDense(final Iterable<Iterable<E?>> denseRows) {
    int rowIdx = 0;
    for (final row in denseRows) {
      int colIdx = 0;
      for (final element in row) {
        if (!identical(element, null)) {
          put(rowIdx, colIdx, element);
        }
        colIdx++;
      }

      rowIdx++;
    }
  }

  /// References to first and last [Column]
  Column<E>? _colHead, _colTail;

  /// References to first and last [Row]
  Row<E>? _rowHead, _rowTail;

  /// Allow fast access to [Row] and [Column] by index
  final _rows = <DenseRowIndex, Row<E>>{};
  final _columns = <DenseColumnIndex, Column<E>>{};

  // Keep track of changes to detect changes during iteration
  int _version = 0;

  /// Insert [value] at position ([rowIdx], [columnIdx]).
  ///
  /// Return reference to [Element] containing [value].
  ///
  /// **Example:**
  ///
  /// ```dart
  /// final sparse = SparseArray2D<String>();
  ///
  /// sparse.put(0, 1, 'a');
  /// sparse.put(1, 0, 'b');
  /// final c = sparse.put(1, 4, 'c');
  /// sparse.put(3, 1, 'd');
  ///
  /// print(sparse.rows.join('\n'));
  ///
  /// print('Element = $c');
  ///
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (0)[(0, 1)[a]]
  /// (1)[(1, 0)[b],(1, 4)[c]]
  /// (3)[(3, 1)[d]]
  /// Element = (1, 4)[c]
  /// ```
  Element<E> put(final DenseRowIndex rowIdx, final DenseColumnIndex columnIdx,
      final E value) {
    if (rowIdx < 0) {
      throw RangeError('rowIdx:$rowIdx');
    }
    if (columnIdx < 0) {
      throw RangeError('columnIdx:$columnIdx');
    }

    final rowHead = _rowHead;
    // Get row and column entry points
    // Update row and column header roots of needed
    Column<E> colEntry;
    Row<E> rowEntry;
    if (identical(rowHead, null)) {
      // SparseArray is empty

      _rows[rowIdx] =
          rowEntry = _rowTail = _rowHead = Row<E>._(this, rowIdx, null, null);
      _columns[columnIdx] = colEntry =
          _colTail = _colHead = Column<E>._(this, columnIdx, null, null);
    } else {
      // Try to add directly to tail first
      final rowTail = _rowTail!;
      if (rowIdx > rowTail.rowIndex) {
        _rows[rowIdx] = _rowTail =
            rowEntry = rowTail._nodeS = Row<E>._(this, rowIdx, rowTail, null);
      } else {
        // Try to retrieve from map, otherwise walk the graph
        final mappedRow = _rows[rowIdx];

        if (identical(mappedRow, null)) {
          rowEntry = _getOrCreateNodeRow<E>(rowHead, rowIdx,
              ((final previous, final next) {
            return Row<E>._(this, rowIdx, _castNullSafe<Row<E>>(previous),
                _castNullSafe<Row<E>>(next));
          })) as Row<E>;
          _rows[rowIdx] = rowEntry;
        } else {
          rowEntry = mappedRow;
        }

        if (rowEntry.rowIndex < rowHead.rowIndex) {
          _rowHead = rowEntry;
        }
      }

      final colTail = _colTail!;

      // Try to add directly to tail first
      if (columnIdx > colTail.columnIndex) {
        _columns[columnIdx] = _colTail = colEntry =
            colTail._nodeE = Column<E>._(this, columnIdx, colTail, null);
      } else {
        final mappedColumn = _columns[columnIdx];
        final colHead = _colHead!;
        // Try to retrieve from map, otherwise walk the graph
        if (identical(mappedColumn, null)) {
          colEntry = _getOrCreateNodeCol<E>(colHead, columnIdx,
              ((final previous, final next) {
            return Column<E>._(
                this,
                columnIdx,
                _castNullSafe<Column<E>>(previous),
                _castNullSafe<Column<E>>(next));
          })) as Column<E>;
          _columns[columnIdx] = colEntry;
        } else {
          colEntry = mappedColumn;
        }

        if (colEntry.columnIndex < colHead.columnIndex) {
          _colHead = colEntry;
        }
      }
    }

    // Insert element to row and column entry points
    final rowElement = rowEntry._insertElement(columnIdx, value);
    final colElement = colEntry._insertElement(rowIdx, rowElement);

    assert(identical(rowElement, colElement));

    rowElement.value = value;

    assert(_assertIntegrity());

    _incVersion();

    return rowElement;
  }

  /// Equivilent to calling [put] ([row], [indices], [values]) for each
  /// ([indices], [values]) pair.
  ///
  /// Throws error if [indices] and [values] are of different lengths.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// final sparse = SparseArray2D<String>();
  ///
  /// sparse.putAllRow(2, [1, 3, 7, 2], ['a', 'c', 'g', 'b']);
  ///
  /// print(sparse.rows);
  ///
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (2)[(2, 1)[a],(2, 2)[b],(2, 3)[c],(2, 7)[g]]
  /// ```
  ///
  /// Note: Currently naive implementation.
  void putAllRow(final DenseRowIndex row,
      final Iterable<DenseColumnIndex> indices, final Iterable<E> values) {
    final indicesItr = indices.iterator;
    final valuesItr = values.iterator;

    while (indicesItr.moveNext() && valuesItr.moveNext()) {
      put(row, indicesItr.current, valuesItr.current);
    }

    // Both iterators should be exhausted at this point
    if (indicesItr.moveNext() || valuesItr.moveNext()) {
      throw ArgumentError('indices and values are of different length');
    }
  }

  /// Equivilent to calling [put] ([indices], [columnIdx], [values]) for each
  /// ([indices], [values]) pair.
  ///
  /// Throws error if [indices] and [values] are of different lengths.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// final sparse = SparseArray2D<String>();
  ///
  /// sparse.putAllColumn(2, [1, 3, 7, 2], ['a', 'c', 'g', 'b']);
  ///
  /// print(sparse.rows.join('\n'));
  ///
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (1)[(1, 2)[a]]
  /// (2)[(2, 2)[b]]
  /// (3)[(3, 2)[c]]
  /// (7)[(7, 2)[g]]
  /// ```
  ///
  /// Note: Currently naive implementation.
  void putAllColumn(final DenseColumnIndex columnIdx,
      final Iterable<DenseRowIndex> indices, final Iterable<E> values) {
    final indicesItr = indices.iterator;
    final valuesItr = values.iterator;

    while (indicesItr.moveNext() && valuesItr.moveNext()) {
      put(indicesItr.current, columnIdx, valuesItr.current);
    }

    // Both iterators should be exhausted at this point
    if (indicesItr.moveNext() || valuesItr.moveNext()) {
      throw ArgumentError('indices and values are of different length');
    }
  }

  /// Remove [Element] at ([rowIdx], [columnIdx]) if exists.
  ///
  /// Return removed value if exists, null otherwise.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.rows.join('\n'));
  ///
  /// sparse.remove(2, 2);
  /// sparse.remove(5, 0);
  ///
  /// print('--------');
  ///
  /// print(sparse.rows.join('\n'));
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (0)[(0, 0)[a],(0, 1)[b],(0, 2)[c]]
  /// (1)[(1, 2)[a]]
  /// (2)[(2, 0)[d],(2, 2)[c]]
  /// (5)[(5, 0)[e]]
  /// --------
  /// (0)[(0, 0)[a],(0, 1)[b],(0, 2)[c]]
  /// (1)[(1, 2)[a]]
  /// (2)[(2, 0)[d]]
  /// ```
  E? remove(final DenseRowIndex rowIdx, final DenseColumnIndex columnIdx) {
    if (rowIdx < 0) {
      throw RangeError('row:$rowIdx');
    }
    if (columnIdx < 0) {
      throw RangeError('column:$columnIdx');
    }

    final targetRow = _castNullSafe<Row<E>>(rowAt(rowIdx));

    if (identical(targetRow, null)) {
      return null;
    }

    final targetCol = _castNullSafe<Column<E>>(columnAt(columnIdx));

    if (identical(targetCol, null)) {
      return null;
    }

    final targetElement = targetRow.elementAtDense(columnIdx);

    if (identical(targetElement, null)) {
      return null;
    }

    // Remove element from both row and column
    targetRow._removeElement(targetElement);
    targetCol._removeElement(targetElement);

    // Update rows and columns
    if (identical(targetRow._head, null)) {
      // Row is empty so remove
      _disconnectRow(targetRow);
    }

    if (identical(targetCol._head, null)) {
      // Column is empty so remove
      _disconnectColumn(targetCol);
    }

    targetElement._invalidate();

    assert(_assertIntegrity());

    return targetElement.value;
  }

  /// Remove all [Element] in row [rowIdx].
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.rows.join('\n'));
  ///
  /// sparse.removeRow(5);
  /// sparse.removeRow(1);
  /// sparse.removeRow(3);
  ///
  /// print('--------');
  ///
  /// print(sparse.rows.join('\n'));
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (0)[(0, 0)[a],(0, 1)[b],(0, 2)[c]]
  /// (1)[(1, 2)[a]]
  /// (2)[(2, 0)[d],(2, 2)[c]]
  /// (5)[(5, 0)[e]]
  /// --------
  /// (0)[(0, 0)[a],(0, 1)[b],(0, 2)[c]]
  /// (2)[(2, 0)[d],(2, 2)[c]]
  /// ```
  void removeRow(final DenseRowIndex rowIdx) {
    final targetRow = rowAt(rowIdx);

    if (identical(targetRow, null)) {
      return;
    }

    // Remove all elements of column and associated rows
    var current = targetRow._head;

    while (!identical(current, null)) {
      // Delete element from its row
      assert(_columns.containsKey(current.columnIndex));
      final currentColumn = _columns[current.columnIndex]!;

      currentColumn._removeElement(current);

      // if this has emptied the row then remove row
      if (identical(currentColumn._head, null)) {
        // Row is empty so remove
        _disconnectColumn(currentColumn);
      }

      final next = current.nextE;

      current._invalidate();

      current = next;
    }

    _disconnectRow(targetRow);
    assert(_assertIntegrity());
  }

  /// Remove all [Element] in column [columnIdx].
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.columns.join('\n'));
  ///
  /// sparse.removeColumn(2);
  ///
  /// print('--------');
  ///
  /// print(sparse.columns.join('\n'));
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (0)[(0, 0)[a],(2, 0)[d],(5, 0)[e]]
  /// (1)[(0, 1)[b]]
  /// (2)[(0, 2)[c],(1, 2)[a],(2, 2)[c]]
  /// --------
  /// (0)[(0, 0)[a],(2, 0)[d],(5, 0)[e]]
  /// (1)[(0, 1)[b]]
  /// ```
  void removeColumn(final DenseColumnIndex columnIdx) {
    final targetColumn = columnAt(columnIdx);

    if (identical(targetColumn, null)) {
      return;
    }

    // Remove all elements of column and associated rows
    var current = targetColumn._head;

    while (!identical(current, null)) {
      // Delete element from its row
      assert(_rows.containsKey(current.rowIndex));
      final currentRow = _rows[current.rowIndex]!;

      currentRow._removeElement(current);

      // if this has emptied the row then remove row
      if (identical(currentRow._head, null)) {
        // Row is empty so remove
        _disconnectRow(currentRow);
      }

      final next = current.nextS;

      current._invalidate();

      current = next;
    }

    _disconnectColumn(targetColumn);
    assert(_assertIntegrity());
  }

  /// Return [Element] located at ([rowIdx], [columnIdx]).
  ///
  /// Return null if no element exists at these coordinates.
  ///
  /// Note: Because the SparseArray2D is theoretically infinite there
  /// is no upper bounds check on ([rowIdx], [columnIdx]);
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.elementAt(2, 2));
  /// print(sparse.elementAt(90, 32)); // No upper bounds check
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (2, 2)[c]
  /// null
  /// ```
  Element<E>? elementAt(
      final DenseRowIndex rowIdx, final DenseColumnIndex columnIdx) {
    if (rowIdx < 0) {
      throw RangeError('rowIdx:$rowIdx');
    }
    if (columnIdx < 0) {
      throw RangeError('columnIdx:$columnIdx');
    }

    // To maximise benefit of ElementIterable mappings use the one
    // that avoids most linked list traversal on average.
    return (_rows.length > _columns.length)
        ? _rows[rowIdx]?.elementAtDense(columnIdx)
        : _columns[columnIdx]?.elementAtDense(rowIdx);
  }

  /// Return [Row] representing row located at [rowIdx].
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.rowAt(2));
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (2)[(2, 0)[d],(2, 2)[c]]
  /// ```
  Row<E>? rowAt(final DenseRowIndex rowIdx) => _rows[rowIdx];

  /// Return [Column] representing column located at [columnIdx].
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.columnAt(2));
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (2)[(0, 2)[c],(1, 2)[a],(2, 2)[c]]
  /// ```
  Column<E>? columnAt(final DenseColumnIndex columnIdx) => _columns[columnIdx];

  /// Number of columns in dense representation.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.numDenseColumns);
  /// print(sparse.denseColumns.length);
  ///
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// 3
  /// 3
  /// ```
  int get numDenseColumns => (_colTail?.columnIndex ?? -1) + 1;

  /// Number of rows in dense representation.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.numDenseRows);
  /// print(sparse.denseRows.length);
  ///
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// 6
  /// 6
  /// ```
  int get numDenseRows => (_rowTail?.rowIndex ?? -1) + 1;

  /// Number of columns in sparse representation.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.numSparseColumns);
  /// print(sparse.columns.length);
  ///
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// 3
  /// 3
  /// ```
  int get numSparseColumns => _columns.length;

  /// Number of rows in sparse representation.
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.numSparseRows);
  /// print(sparse.rows.length);
  ///
  /// ```
  ///
  /// ```
  /// 4
  /// 4
  /// ```
  int get numSparseRows => _rows.length;

  /// An [Iterable] of [Row] representing rows in order.
  ///
  /// Ordering is equivilent to repeated calls to [Row.next].
  ///
  /// Returned [Iterable] has efficient length.
  ///
  /// Throws [ConcurrentModificationError] if [SparseArray2D] changes during iteration.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.rows.join('\n'));
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (0)[(0, 0)[a],(0, 1)[b],(0, 2)[c]]
  /// (1)[(1, 2)[a]]
  /// (2)[(2, 0)[d],(2, 2)[c]]
  /// (5)[(5, 0)[e]]
  /// ```
  Iterable<Row<E>> get rows => _RowIterable(this);

  /// An [Iterable] of [DenseValueIterable] representing [rows] in dense
  /// format.
  ///
  /// See [DenseValueIterable].
  ///
  /// Returned [Iterable] has efficient length.
  ///
  /// Throws [ConcurrentModificationError] if [SparseArray2D] changes during iteration.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.denseRows.join('\n'));
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (a, b, c)
  /// (null, null, a)
  /// (d, null, c)
  /// (null, null, null)
  /// (null, null, null)
  /// (e, null, null)
  /// ```
  Iterable<DenseValueIterable<E?>> get denseRows => _RowIterableDense<E>(this);

  /// An [Iterable] of [DenseValueIterable] representing [columns] in dense
  /// format.
  ///
  /// See [DenseValueIterable].
  ///
  /// Returned [Iterable] has efficient length.
  ///
  /// Throws [ConcurrentModificationError] if [SparseArray2D] changes during iteration.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.denseColumns.join('\n'));
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (a, null, d, null, null, e)
  /// (b, null, null, null, null, null)
  /// (c, a, c, null, null, null)
  /// ```
  Iterable<DenseValueIterable<E?>> get denseColumns =>
      _ColIterableDense<E>(this);

  /// An [Iterable] of [Column] representing columns in order.
  ///
  /// Ordering is equivilent to repeated calls to [Column.next].
  ///
  /// Returned [Iterable] has efficient length.
  ///
  /// Throws [ConcurrentModificationError] if [SparseArray2D] changes during iteration.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.columns.join('\n'));
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// (0)[(0, 0)[a],(2, 0)[d],(5, 0)[e]]
  /// (1)[(0, 1)[b]]
  /// (2)[(0, 2)[c],(1, 2)[a],(2, 2)[c]]
  /// ```
  Iterable<Column<E>> get columns => _ColIterable(this);

  /// Return true if this collection has no elements, false otherwise.
  ///
  /// **Example:**
  ///
  /// ```dart
  /// final sparse = SparseArray2D<String>();
  /// print(sparse.isEmpty);
  /// sparse.put(25, 2, 'g');
  /// print(sparse.isEmpty);
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// true
  /// false
  /// ```
  bool get isEmpty => identical(_colHead, null);

  /// Disconnect [targetRow] from graph
  void _disconnectRow(final Row<E> targetRow) {
    if (identical(targetRow._nodeN, null)) {
      // Is first row
      if (identical(targetRow._nodeS, null)) {
        _rowHead = _rowTail = null;
      } else {
        _rowHead = targetRow._nodeS as Row<E>;
        _rowHead!._nodeN = null;
      }
    } else if (identical(targetRow._nodeS, null)) {
      // Is last row
      if (identical(targetRow._nodeN, null)) {
        _rowHead = _rowTail = null;
      } else {
        _rowTail = targetRow._nodeN as Row<E>;
        _rowTail!._nodeS = null;
      }
    } else {
      // Is between first and last row
      targetRow._nodeN!._nodeS = targetRow._nodeS;
      targetRow._nodeS!._nodeN = targetRow._nodeN;
    }

    targetRow._invalidate();
    _rows.remove(targetRow.index);
  }

  /// Disconnect [targetCol] from graph
  void _disconnectColumn(final Column<E> targetCol) {
    if (identical(targetCol._nodeW, null)) {
      // Is first Col
      if (identical(targetCol._nodeE, null)) {
        _colHead = _colTail = null;
      } else {
        _colHead = targetCol._nodeE as Column<E>;
        _colHead!._nodeW = null;
      }
    } else if (identical(targetCol._nodeE, null)) {
      // Is last Col
      if (identical(targetCol._nodeW, null)) {
        _colHead = _colTail = null;
      } else {
        _colTail = targetCol._nodeW as Column<E>;
        _colTail!._nodeE = null;
      }
    } else {
      // Is between first and last Col
      targetCol._nodeW!._nodeE = targetCol._nodeE;
      targetCol._nodeE!._nodeW = targetCol._nodeW;
    }

    targetCol._invalidate();
    _columns.remove(targetCol.index);
  }

  void _incVersion() =>
      _version = _version < _maxSafeInteger ? _version + 1 : 1;

  @override
  String toString() {
    final buff = StringBuffer();
    for (final row in denseRows) {
      buff.writeln(row);
    }

    return buff.toString();
  }

  /// All sparse elements
  ///
  /// **Example:**
  ///
  /// ```dart
  /// const dense = [
  ///   ['a', 'b', 'c'],
  ///   [null, null, 'a'],
  ///   ['d', null, 'c'],
  ///   [null, null, null],
  ///   [null, null, null],
  ///   ['e', null, null]
  /// ];
  ///
  /// final sparse = SparseArray2D<String>.fromDense(dense);
  ///
  /// print(sparse.elements);
  /// ```
  ///
  /// **Output:**
  ///
  /// ```
  /// ((0, 0)[a], (0, 1)[b], (0, 2)[c], (1, 2)[a], (2, 0)[d], (2, 2)[c], (5, 0)[e])
  /// ```
  Iterable<Element<E>> get elements => rows.expand((final row) => row);

  /// Various integrity checks
  bool _assertIntegrity() {
    assert(identical(_rowHead, null)
        ? identical(_colHead, null)
        : !identical(_colHead, null));

    assert(identical(_colHead, null)
        ? identical(_rowHead, null)
        : !identical(_rowHead, null));

    assert(identical(_rowHead, null)
        ? identical(_rowTail, null)
        : !identical(_rowTail, null));

    assert(identical(_colHead, null)
        ? identical(_colTail, null)
        : !identical(_colTail, null));

    assert(identical(_rowHead, null) ? true : _rowHead!.isNotEmpty);
    assert(identical(_colHead, null) ? true : _colHead!.isNotEmpty);
    assert(identical(_rowTail, null) ? true : _rowTail!.isNotEmpty);
    assert(identical(_colTail, null) ? true : _colTail!.isNotEmpty);

    for (final row in rows) {
      assert(row.isNotEmpty);
    }

    for (final col in columns) {
      assert(col.isNotEmpty);
    }

    return true;
  }
}

class SparseArray2DEquality<E> implements Equality<SparseArray2D<E>> {
  @override
  bool equals(final SparseArray2D<E> e1, final SparseArray2D<E> e2) {
    if (e1.numDenseRows != e2.numDenseRows) {
      return false;
    }
    if (e1.numDenseColumns != e2.numDenseColumns) {
      return false;
    }

    final e1RowItr = e1.rows.iterator;
    final e2RowItr = e1.rows.iterator;

    while (e1RowItr.moveNext() && e2RowItr.moveNext()) {
      // First check row length
      if (e1RowItr.current.length != e2RowItr.current.length) {
        return false;
      }
      final e1ElementItr = e1RowItr.current.iterator;
      final e2ElementItr = e2RowItr.current.iterator;

      while (e1ElementItr.moveNext() && e2ElementItr.moveNext()) {
        final e1Current = e1ElementItr.current;
        final e2Current = e2ElementItr.current;

        if (e1Current.rowIndex != e2Current.rowIndex) {
          return false;
        }

        if (e1Current.columnIndex != e2Current.columnIndex) {
          return false;
        }

        if (e1Current.value != e2Current.value) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  int hash(final SparseArray2D<E> sparseArray2D) => Object.hashAll(sparseArray2D
      .rows
      .expand((final elementIterable) => elementIterable)
      .map((final element) =>
          Object.hash(element.rowIndex, element.columnIndex, element.value)));

  @override
  bool isValidKey(final Object? o) => o is SparseArray2D<E>;
}

/// Insert [_head] at [index] and return new or existing [_Node]
/// Row direction
_Node<E> _getOrCreateNodeRow<E>(final _Node<E> root, final DenseRowIndex row,
    final _Node<E> Function(_Node<E>? previous, _Node<E>? next) createNodeRow) {
  _Node<E> currentNode = root;
  _Node<E>? lastNode;
  while (row != currentNode.rowIndex) {
    if (row < currentNode.rowIndex) {
      if (identical(lastNode, null)) {
        return currentNode._nodeN = createNodeRow(null, currentNode);
      } else {
        return currentNode._nodeN =
            lastNode._nodeS = createNodeRow(lastNode, currentNode);
      }
    }

    _Node<E>? nextNode = currentNode._nodeS;

    if (identical(nextNode, null)) {
      return currentNode._nodeS = createNodeRow(currentNode, null);
    }
    lastNode = currentNode;
    currentNode = nextNode;
  }
  return currentNode;
}

/// Insert [_head] at [index] and return new or existing [_Node]
/// Column direction
_Node<E> _getOrCreateNodeCol<E>(final _Node<E> root, final DenseColumnIndex col,
    final _Node<E> Function(_Node<E>? previous, _Node<E>? next) createNodeCol) {
  _Node<E> currentNode = root;
  _Node<E>? lastNode;
  while (col != currentNode.columnIndex) {
    if (col < currentNode.columnIndex) {
      if (identical(lastNode, null)) {
        return currentNode._nodeW = createNodeCol(null, currentNode);
      } else {
        return currentNode._nodeW =
            lastNode._nodeE = createNodeCol(lastNode, currentNode);
      }
    }

    _Node<E>? nextNode = currentNode._nodeE;

    if (identical(nextNode, null)) {
      return currentNode._nodeE = createNodeCol(currentNode, null);
    }
    lastNode = currentNode;
    currentNode = nextNode;
  }
  return currentNode;
}
