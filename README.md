# LightBSON

[![Build Status](https://github.com/ancapdev/LightBSON.jl/workflows/CI/badge.svg)](https://github.com/ancapdev/LightBSON.jl/actions)
[![codecov](https://codecov.io/gh/ancapdev/LightBSON.jl/branch/master/graph/badge.svg?token=9IEAWVLPCN)](https://codecov.io/gh/ancapdev/LightBSON.jl)

High performance encoding and decoding of [BSON](https://bsonspec.org/) data.

## What It Is
* Allocation free API for reading and writing BSON data.
* Natural mapping of Julia types to corresponding BSON types.
* Convenience API to read and write `Dict{String, Any}` or `OrderedDict{String, Any}` (default, for roundtrip consistency) as BSON.
* Struct API tunable for tradeoffs between flexibility, performance, and evolution.
* Configurable validation levels.
* Light weight indexing for larger documents.
* [Transducers.jl](https://github.com/JuliaFolds/Transducers.jl) compatible.
* Tested for conformance against the [BSON corpus](https://github.com/mongodb/specifications/blob/master/source/bson-corpus/bson-corpus.rst).

## What It Is Not
* Generic serialization of all Julia types to BSON. See [BSON.jl](https://github.com/JuliaIO/BSON.jl). `LightBSON` aims for natural representations, suitable for interop with other languages and long term persistence.
* Integrated with [FileIO.jl](https://github.com/JuliaIO/FileIO.jl). [BSON.jl](https://github.com/JuliaIO/BSON.jl) already is, and adding another with different semantics would be confusing.
* A BSON mutation API. Reading and writing are entirely separate and only complete documents can be written.
* Conversion to and from [Extended JSON](https://docs.mongodb.com/manual/reference/mongodb-extended-json/). This may be added later.

## Basic Usage
* Documents are read and write to and from byte arrays with `BSONReader` and `BSONWriter`.
* `BSONReader` and `BSONWriter` are immutable struct types with no state. They can be instantiated without allocation.
* `BSONWriter` will append to the destination array. User is responsble for not writing duplicate fields.
* `reader["foo"]` or `reader[:foo]` finds `foo` and returns a new reader pointing to the field.
* `reader[T]` materializes a field to the type `T`.
* `writer["foo"] = x` or `writer[:foo] = x` appends a field with name `foo` and value `x`.
* `close(writer)` finalizes a document (writes the document length and terminating null byte).

### Example
```
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = Int64(123)
close(writer)
reader = BSONReader(buf)
reader["x"][Int64] # 123
```

## Nested Documents
Nested documents are written by assigning a field with a function that takes a nested writer. Nested fields are read by index.
```
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = nested_writer -> begin
    nested_writer["a"] = 1
    nested_writer["b"] = 2
end
close(writer)
reader = BSONReader(buf)
reader["x"]["a"][Int64] # 1
reader["x"]["b"][Int64] # 2
```

## Arrays
Arrays are written by assigning array values, or by generators. Arrays can be materialized to Julia arrays, or be accessed by index.
```
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = Int64[1, 2, 3]
writer["y"] = (Int64(x * x) for x in 1:3)
close(writer)
reader = BSONReader(buf)
reader["x"][Vector{Int64}] # [1, 2, 3]
reader["y"][Vector{Int64}] # [1, 4, 9]
reader["x"][2][Int64] # 2
reader["y"][2][Int64] # 4
```

## Read as Dict or Any
Where performance is not a concern, elements can be materialized to a dictionaries (recursively) or the most appropriate Julia type for leaf fields.
```
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = Int64(1)
writer["y"] = "foo"
close(writer)
reader = BSONReader(buf)
reader[Dict{String, Any}] # Dict{String, Any}("x" => 1, "y" => "foo")
reader[OrderedDict{String, Any}] # OrderedDict{String, Any}("x" => 1, "y" => "foo")
reader[Any] # OrderedDict{String, Any}("x" => 1, "y" => "foo")
reader["x"][Any] # 1
reader["y"][Any] # "foo"
```

## Arrays With Nested Documents
Generators can be used to directly write nested documents in arrays.
```
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = (
    nested_writer -> begin
        nested_writer["a"] = Int64(x)
        nested_writer["b"] = Int64(x * x)
    end
    for x in 1:3
)
close(writer)
reader = BSONReader(buf)
reader["x"][Vector{Any}] # Any[OrderedDict{String, Any}("a" => 1, "b" => 1), OrderedDict{String, Any}("a" => 2, "b" => 4), OrderedDict{String, Any}("a" => 3, "b" => 9)]
reader["x"][3]["b"][Int64] # 9
```

## Read Abstract Types
The abstract types `Number`, `Integer`, and `AbstractFloat` can be used to materialize numeric fields to the most appropriate Julia constrained under the abstract type.
```
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = Int32(123)
writer["y"] = 1.25
close(writer)
reader = BSONReader(buf)
reader["x"][Number] # 123
reader["x"][Integer] # 123
reader["y"][Number] # 1.25
reader["y"][AbstractFloat] # 1.25
```

## Unsafe String
String fields can be materialized as `WeakRefString{UInt8}`, aliased as `UnsafeBSONString`. This will create a string object with pointers to the underlying buffer without performing any allocations. User must take care of GC safety.
```
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = "foo"
close(writer)
reader = BSONReader(buf)
s = reader["x"][UnsafeBSONString]
GC.@preserve buf s == "foo" # true
```

# Binary
Binary fields are represented with `BSONBinary`.
```
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = BSONBinary([0x1, 0x2, 0x3], BSON_SUBTYPE_GENERIC_BINARY)
close(writer)
reader = BSONReader(buf)
x = reader["x"][BSONBinary]
x.data # [0x1, 0x2, 0x3]
x.subtype # BSON_SUBTYPE_GENERIC_BINARY
```

## Unsafe Binary
Binary fields can be materialized as `UnsafeBSONBinary` for zero alocations, where the `data` field is an `UnsafeArray{UInt8, 1}` with pointers into the underlying buffer. User must take care of GC safety.
```
buf = UInt8[]
writer = BSONWriter(buf)
writer["x"] = BSONBinary([0x1, 0x2, 0x3], BSON_SUBTYPE_GENERIC_BINARY)
close(writer)
reader = BSONReader(buf)
x = reader["x"][UnsafeBSONBinary]
GC.@preserve buf x.data == [0x1, 0x2, 0x3] # true
x.subtype # BSON_SUBTYPE_GENERIC_BINARY
```

## String vs Symbol

## Reading

### Iteration
### Indexing
### Validation
## Writing
### Faster Buffer
## Structs
### Generic
### Simple
### Super Simple
### Schema Evolution
## Named Tuples
## Performance
## Related Packages
* [BSON.jl](https://github.com/JuliaIO/BSON.jl) - Generic serialization of all Julia types to and from BSON.
* [Mongoc.jl](https://github.com/felipenoris/Mongoc.jl) - Julia MongoDB client.
* [Transducers.jl](https://github.com/JuliaFolds/Transducers.jl) - Data iteration and transformation API.
* [WeakRefStrings.jl](https://github.com/JuliaData/WeakRefStrings.jl) - Pointer based strings.
* [UnsafeArrays.jl](https://github.com/JuliaArrays/UnsafeArrays.jl) - Pointer based arrays.
