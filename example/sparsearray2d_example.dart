import 'package:sparsearray2d/sparsearray2d.dart';

void main() {
  final matrix = SparseArray2D<int>.fromDense([
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
  ]);

  // ignore: avoid_print
  print(matrix);

  final transposed = SparseArray2D<int>();
  for (final element in matrix.elements) {
    transposed.put(element.columnIndex, element.rowIndex, element.value);
  }

  // ignore: avoid_print
  print(transposed);
}
