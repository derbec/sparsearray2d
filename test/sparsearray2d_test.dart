import 'package:sparsearray2d/sparsearray2d.dart';
import 'package:test/test.dart';

/// Do not change these dense arrays!

const dense1 = [
  ['a', 'b', 'c'],
  [null, null, 'a'],
  ['d', null, 'c'],
  [null, null, null],
  [null, null, null],
  ['e', null, null]
];

/// Final row of all null must be kept
const dense2 = [
  [null, null, null],
  [1, 2, 1],
  [null, null, 1],
  [null, null, null],
  [4, null, 3],
  [null, null, null],
];

/// No null elements
const denseNonNull = [
  [0, 1, 3, 4],
  [5, 6, 7, 8],
  [9, 10, 11, 12],
  [13, 14, 15, 16],
  [17, 18, 19, 20],
  [21, 22, 23, 24],
];

/// Transpose dense matrix, assume consistent size rows
List<List<E?>> transpose<E>(final List<List<E?>> table) {
  List<List<E?>> ret = <List<E?>>[];
  final int N = table[0].length;
  for (int i = 0; i < N; i++) {
    List<E?> col = <E?>[];
    for (final row in table) {
      col.add(row[i]);
    }
    ret.add(col);
  }
  return ret;
}

/// Construct from dense by inserting elements in random order.
/// Assumes dense rows are all same length
SparseArray2D<E> denseToSparseRandom<E>(final List<List<E?>> dense) {
  final sparse = SparseArray2D<E>();
  final rowIndices =
      List<int>.generate(dense.length, (final int index) => index);
  rowIndices.shuffle();
  for (final rowIdx in rowIndices) {
    final denseRow = dense[rowIdx];
    final colIndices =
        List<int>.generate(denseRow.length, (final int index) => index);
    colIndices.shuffle();
    for (final colIdx in colIndices) {
      final denseVal = denseRow[colIdx];
      if (!identical(denseVal, null)) {
        sparse.put(rowIdx, colIdx, denseVal);
      }
    }
  }
  return sparse;
}

void main() {
  group('SparseArray2D', () {
    setUp(() {
      // Additional setup goes here.
    });

    test('Construct from dense', () {
      expect(SparseArray2D<String>.fromDense(dense1).denseRows, equals(dense1));
      // Dense2 has last row of null
      expect(SparseArray2D<int>.fromDense(dense2).denseRows,
          equals(dense2.sublist(0, dense2.length - 1)));
      expect(SparseArray2D<int>.fromDense(denseNonNull).denseRows,
          equals(denseNonNull));
    });

    test('Num rows + cols', () {
      final arr1 = denseToSparseRandom(dense1);
      expect(arr1.numDenseColumns, equals(3));
      expect(arr1.numDenseRows, equals(6));

      final arr2 = denseToSparseRandom(dense2);

      // Final row of all null is ignored
      expect(arr2.numDenseColumns, equals(3));
      expect(arr2.numDenseRows, equals(5));
    });

    test('Sparse length', () {
      final arr1 = denseToSparseRandom(dense1);
      expect(arr1.rows.map((final Row<String> e) => e.length),
          equals([3, 1, 2, 1]));
      expect(arr1.columns.map((final Column<String> e) => e.length),
          equals([3, 1, 3]));
      final arr2 = denseToSparseRandom(dense2);
      expect(arr2.rows.map((final Row<int> e) => e.length), equals([3, 1, 2]));
      expect(arr2.columns.map((final Column<int> e) => e.length),
          equals([2, 1, 3]));
    });

    test('ElementAt', () {
      void process(final List<List<dynamic>> dense) {
        final sparse = denseToSparseRandom(dense);
        int rowIdx = 0;
        for (final row in dense) {
          int colIdx = 0;
          for (final dynamic element in row) {
            final spElement = sparse.elementAt(rowIdx, colIdx);
            if (identical(element, null)) {
              expect(spElement, equals(null));
            } else {
              expect(spElement!.rowIndex, equals(rowIdx));
              expect(spElement.columnIndex, equals(colIdx));
              expect(spElement.value, equals(element));
            }

            colIdx++;
          }

          rowIdx++;
        }
      }

      process(dense1);
      process(dense2);
      process(denseNonNull);
    });

    test('Negative indices', () {
      final sparse = denseToSparseRandom(dense1);

      expect(() {
        sparse.elementAt(-1, 0);
      }, throwsA(isA<RangeError>()));

      expect(() {
        sparse.elementAt(0, -1);
      }, throwsA(isA<RangeError>()));

      expect(() {
        sparse.put(-1, 0, 'd');
      }, throwsA(isA<RangeError>()));

      expect(() {
        sparse.put(0, -1, '7');
      }, throwsA(isA<RangeError>()));
    });

    test('Large indices', () {
      final sparse = denseToSparseRandom(dense1);

      expect(sparse.elementAt(6000, 45), equals(null));
      expect(sparse.elementAt(1, 4500), equals(null));
      expect(sparse.elementAt(4500, 1), equals(null));
    });

    test('Iterators', () {
      /*
const dense1 = [
  [1, 2, 3],
  [null, null, 1],
  [4, null, 3],
  [null, null, null],
  [null, null, null],
  [9, null, null]
];
*/

      final sparse1 = denseToSparseRandom(dense1);
      expect(
          sparse1.rows
              .map((final e) => e.map((final element) => element.value)),
          equals([
            ['a', 'b', 'c'],
            ['a'],
            ['d', 'c'],
            ['e']
          ]));

      expect(
          sparse1.columns
              .map((final e) => e.map((final element) => element.value)),
          equals([
            ['a', 'd', 'e'],
            ['b'],
            ['c', 'a', 'c']
          ]));

      expect(
          sparse1.columns.map((final e) => e.dense),
          equals([
            ['a', null, 'd', null, null, 'e'],
            ['b', null, null, null, null, null],
            ['c', 'a', 'c', null, null, null]
          ]));

      expect(() {
        // ignore: unused_local_variable
        for (final row in sparse1.rows) {
          sparse1.put(0, 1, 'c');
        }
      }, throwsA(isA<ConcurrentModificationError>()));

      expect(() {
        // ignore: unused_local_variable
        for (final column in sparse1.columns) {
          sparse1.put(0, 1, 'c');
        }
      }, throwsA(isA<ConcurrentModificationError>()));
    });

    test('Remove', () {
      final sparse1 = denseToSparseRandom(dense1);

      sparse1.remove(0, 1);
      sparse1.remove(0, 0);
      sparse1.remove(5, 0);
      sparse1.remove(2, 0);
      sparse1.remove(2, 2);
      sparse1.remove(0, 2);
      sparse1.remove(1, 2);

      expect(sparse1.isEmpty, equals(true));
    });

    test('rows', () {
      final sparse1 = denseToSparseRandom(dense1);

      expect(sparse1.denseRows, equals(dense1));
    });

    test('cols', () {
      final sparse1 = denseToSparseRandom(dense1);

      expect(sparse1.denseColumns, equals(transpose<String>(dense1)));
    });

    test('rowAt', () {
      final sparse1 = denseToSparseRandom(dense1);

      expect(sparse1.rowAt(1)!.dense, equals(dense1[1]));
    });

    test('columnAt', () {
      final sparse1 = denseToSparseRandom(dense1);

      expect(sparse1.columnAt(1)!.dense, equals(transpose<String>(dense1)[1]));
    });
  });

  group('SparseArray2DEquality', () {
    test('Equality', () {
      final sparse1 = denseToSparseRandom(dense1);
      final sparse1a = denseToSparseRandom(dense1);

      final sparse2 = denseToSparseRandom(dense2);

      expect(SparseArray2DEquality().equals(sparse1, sparse2), equals(false));
      expect(
          SparseArray2DEquality().hash(sparse1) ==
              SparseArray2DEquality().hash(sparse1a),
          equals(true));

      final hash1 = SparseArray2DEquality().hash(sparse1);
      sparse1.put(200, 3000, '6');
      expect(SparseArray2DEquality().hash(sparse1) == hash1, equals(false));
    });
  });
  group('Element', () {
    test('Readme ', () {});

    test('Adjacency ', () {
      void checkNextElement(final SparseArray2D<int> sparse,
          final List<List<int>> dense, final int rowIdx, final int colIdx) {
        final indiciesN = [rowIdx - 1, colIdx];
        final indiciesE = [rowIdx, colIdx + 1];
        final indiciesW = [rowIdx, colIdx - 1];
        final indiciesS = [rowIdx + 1, colIdx];

        final sparseElement = sparse.elementAt(rowIdx, colIdx)!;

        // North
        try {
          final denseN = dense[indiciesN[0]][indiciesN[1]];
          expect(sparseElement.nextN!.value, equals(denseN));
        } catch (e) {
          expect(sparseElement.nextN, equals(null));
        }

        // South
        try {
          final denseS = dense[indiciesS[0]][indiciesS[1]];
          expect(sparseElement.nextS!.value, equals(denseS));
        } catch (e) {
          expect(sparseElement.nextS, equals(null));
        }

        // East
        try {
          final denseE = dense[indiciesE[0]][indiciesE[1]];
          expect(sparseElement.nextE!.value, equals(denseE));
        } catch (e) {
          expect(sparseElement.nextE, equals(null));
        }

        // West
        try {
          final denseW = dense[indiciesW[0]][indiciesW[1]];
          expect(sparseElement.nextW!.value, equals(denseW));
        } catch (e) {
          expect(sparseElement.nextW, equals(null));
        }
      }

      final sparseNonNull = denseToSparseRandom(denseNonNull);

      int rowIdx = 0;
      for (final row in denseNonNull) {
        int colIdx = 0;
        for (final denseElement in row) {
          expect(sparseNonNull.elementAt(rowIdx, colIdx)!.value,
              equals(denseElement));
          checkNextElement(sparseNonNull, denseNonNull, rowIdx, colIdx);
          colIdx++;
        }
        rowIdx++;
      }

      // Check noncontiguous
      final sparse1 = denseToSparseRandom(dense1);
      expect(sparse1.elementAt(0, 0)!.nextS!.value, equals('d'));
      expect(sparse1.elementAt(0, 0)!.nextS!.nextS!.value, equals('e'));
      expect(sparse1.elementAt(0, 0)!.nextS!.nextE!.value, equals('c'));
      expect(sparse1.elementAt(5, 0)!.nextN!.nextE!.value, equals('c'));
      expect(sparse1.elementAt(5, 0)!.nextN!.nextE!.nextW!.value, equals('d'));
    });
  });
}
