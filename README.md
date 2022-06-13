<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages). 
-->

A fast and flexible generic sparse 2 dimensional array.

## Features

* Exposes graph such that clients may easily walk directly between neighbouring elements to allow fast array traversal.
* Easy conversion between dense and sparse formats.

## Usage

**Example:**

```dart
final sparse = SparseArray2D<String>();

sparse.put(2, 0, 'a');
sparse.put(2, 1, 'b');
sparse.put(2, 5, 'c');
sparse.put(2, 8, 'd');
sparse.put(0, 5, 'e');

print('Sparse form elements');
print(sparse.rows.join('\n'));

print('Dense form values');
print(sparse.denseRows.join('\n'));

print('Dense form with default value "_"');
print(sparse.denseRows.map((final row) => row.padded('-')).join('\n'));

print('Extract row as sparse elements');
print(sparse.rowAt(2));

print('Extract row as sparse values with default value "*"');
print(sparse.rowAt(2)!.dense.padded('*'));

print('Extract column as sparse elements');
print(sparse.columnAt(5)!.join('\n'));

print('Extract column as sparse values with default value "*"');
print(sparse.columnAt(5)!.dense.padded('*').join('\n'));

```

**Output:**

```
Sparse form elements
(0)[(0, 5)[e]]
(2)[(2, 0)[a],(2, 1)[b],(2, 5)[c],(2, 8)[d]]

Dense form values
(null, null, null, null, null, e, null, null, null)
(null, null, null, null, null, null, null, null, null)
(a, b, null, null, null, c, null, null, d)

Dense form with default value "_"
(-, -, -, -, -, e, -, -, -)
(-, -, -, -, -, -, -, -, -)
(a, b, -, -, -, c, -, -, d)

Extract row as sparse elements
(2)[(2, 0)[a],(2, 1)[b],(2, 5)[c],(2, 8)[d]]

Extract row as sparse values with default value "*"
(a, b, *, *, *, c, *, *, d)

Extract column as sparse elements
(0, 5)[e]
(2, 5)[c]

Extract column as sparse values with default value "*"
e
*
c
```