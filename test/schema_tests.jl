@testset "Schema" begin
    schema = BSONSchema(
        BSONDocument(
            BSONField(:a, Int64),
            BSONField(:b, Float64),
        ),
        version = Int32(1),
    )

    buf = UInt8[]
    writer = SchemaBSONWriter(schema, BSONWriter(buf))
    writer[] = (;a=1, b=2.5, c=3)
    close(writer)
    reader = SchemaBSONReader(schema, BSONReader(buf))
    @test reader.a == 1
    @test reader.b == 2.5
    @test_throws KeyError reader.c
    @test bson_schema_version(reader) == 1
end

@testset "Schema recursive" begin
    schema = BSONSchema(
        BSONDocument(
            BSONField(:a, Int64),
            BSONField(
                :b,
                BSONDocument(
                    BSONField(:c, Int64),
                )
            ),
        )
    )

    buf = UInt8[]
    writer = SchemaBSONWriter(schema, BSONWriter(buf))
    writer[] = (;a=1, b=(;c=2))
    close(writer)
    reader = SchemaBSONReader(schema, BSONReader(buf))
    @test reader.a == 1
    @test reader.b.c == 2
end

@testset "Schema BSONAbstract" begin
    schema = field -> BSONSchema(
        BSONDocument(
            BSONField(:a, field),
        ),
        version = Int32(1)
    )

    @testset "read/write" begin
        schema2 = BSONSchema(
            BSONDocument(
                BSONField(:b, Int64),
            ),
            version = Int32(2)
        )
    
        buf = UInt8[]
        writer = SchemaBSONWriter(schema(schema2), BSONWriter(buf))
        writer[] = (;a=(;b=3))
        close(writer)
        reader1 = SchemaBSONReader(schema(BSONAbstract()), BSONReader(buf))
        @test bson_schema_version(reader1) == 1
        reader2 = SchemaBSONReader(schema2, reader1.a)
        @test bson_schema_version(reader2) == 2
        @test reader2.b == 3
    end

    @testset "write abstract" begin
        buf = UInt8[]
        writer = SchemaBSONWriter(schema(BSONAbstract()), BSONWriter(buf))
        @test_throws ErrorException (writer[] = (;a=(;b=3)))
        close(writer)
    end
end

@testset "Schema BSONArray" begin
    schema = BSONSchema(
        BSONDocument(
            BSONField(:a, BSONArray(Int64)),
            BSONField(:b, BSONArray(BSONDocument(BSONField(:c, Int64)))),
        ),
    )
    buf = UInt8[]
    writer = SchemaBSONWriter(schema, BSONWriter(buf))
    writer[] = (;a=(i for i=1:3), b=((;c=i) for i=1:3))
    close(writer)
    reader = SchemaBSONReader(schema, BSONReader(buf))
    @test [reader.a[i] for i=1:3] == 1:3
    @test [reader.b[i].c for i=1:3] == 1:3
end