abstract type AbstractBSONType end

struct BSONValue{type <: ValueField} <: AbstractBSONType
    function BSONValue(::Type{type}) where {type<:ValueField}
        new{type}()
    end
end
gettype(::BSONValue{type}) where {type} = type
gettype(::Type{<:BSONValue{type}}) where {type} = type

struct BSONAbstract <: AbstractBSONType end

struct BSONField{name,type<:AbstractBSONType}
    type::type
    function BSONField(name::Symbol,type::AbstractBSONType)
        new{name,typeof(type)}()
    end
end
function BSONField(name::Symbol,::Type{T}) where {T<:ValueField}
    BSONField(name, BSONValue(T))
end

getname(::BSONField{name}) where {name} = name
gettype(x::T) where {T<:BSONField} = x.type

struct BSONDocument{fields} <: AbstractBSONType
    fields::fields
    function BSONDocument(fields::BSONField...)
        allunique(map(getname, fields)) || throw(ErrorException("fields are not unique"))
        new{typeof(fields)}(fields)
    end
end

_getfields(document::BSONDocument) = document.fields
_getfield(document::BSONDocument, name::Symbol) = _getfield(document.fields, name)

function _getfield(fields::Tuple{Vararg{BSONField}}, name::Symbol)
    length(fields) == 0 && return nothing
    field = first(fields)
    getname(field) == name ? field : _getfield(Base.tail(fields), name)
end

struct BSONArray{type<:AbstractBSONType} <: AbstractBSONType
    type::type
    function BSONArray(type::AbstractBSONType)
        new{typeof(type)}(type)
    end
end
BSONArray(::Type{T}) where {T<:ValueField} = BSONArray(BSONValue(T))
gettype(x::T) where {T<:BSONArray} = x.type

struct BSONSchema{element<:AbstractBSONType,version} <: AbstractBSONType
    element::element
    function BSONSchema(element::AbstractBSONType; version::Union{Nothing,Int32}=nothing)
        new{typeof(element),version}()
    end
end
getelement(x::BSONSchema) = getfield(x, :element)
getversion(::BSONSchema{document,version}) where {document,version} = version

function Base.getproperty(schema::BSONSchema, name::Symbol, removeschema::Bool=true)
    element = schema |> getelement
    @assert element isa BSONDocument
    field = _getfield(element, name)
    isnothing(field) && throw(KeyError(name))
    type = gettype(field)
    if type isa BSONSchema && removeschema
        type
    else
        BSONSchema(type, version=getversion(schema))
    end
end

function Base.getindex(schema::BSONSchema, removeschema::Bool=true)
    array = schema |> getelement
    @assert array isa BSONArray
    type = gettype(array)
    if type isa BSONSchema && removeschema
        type
    else
        BSONSchema(type, version=getversion(schema))
    end
end

function Base.propertynames(schema::BSONSchema)
    element = schema |> getelement
    @assert element isa BSONDocument
    tuple(map(getname, _getfields(element)))
end

struct SchemaBSONReader{S<:BSONSchema,T<:AbstractBSONReader} <: AbstractBSONReader
    schema::S
    reader::T
end

function SchemaBSONReader(schema::BSONSchema, x::SchemaBSONReader)
    element = x |> getschema |> getelement
    @assert element isa BSONAbstract
    SchemaBSONReader(schema, getreader(x))
end

getreader(x::SchemaBSONReader) = getfield(x,:reader)
getschema(x::SchemaBSONReader) = getfield(x,:schema)
bson_schema_version(x::SchemaBSONReader) = getreader(x)[:_v][Int32] # todo: not hardcode the symbol

function Base.getproperty(x::SchemaBSONReader, name::Symbol)
    schema = x |> getschema
    document = schema |> getelement
    @assert document isa BSONDocument

    field = _getfield(document, name)
    isnothing(field) && throw(KeyError(name))
    type = gettype(field)

    reader = getreader(x)[name]

    if type isa Union{BSONDocument,BSONArray}
        SchemaBSONReader(
            getproperty(schema, name),
            reader,
        )
    elseif type isa BSONAbstract
        reader
    else
        @assert type isa BSONValue
        reader[gettype(type)]
    end
end

function Base.propertynames(x::SchemaBSONReader)
    schema = x |> getschema
    document = schema |> getelement
    @assert document isa BSONDocument
    tuple(map(getname, _getfields(document)))
end

function Base.getindex(x::SchemaBSONReader, i::Integer)
    schema = x |> getschema
    array = schema |> getelement
    @assert array isa BSONArray
    type = gettype(array)

    reader = getreader(x)[i]

    if type isa Union{BSONDocument,BSONArray}
        SchemaBSONReader(schema[], reader)
    elseif type isa BSONAbstract
        reader
    else
        @assert type isa BSONValue
        reader[gettype(type)]
    end
end

struct SchemaBSONWriter{S<:BSONSchema,T<:BSONWriter}
    schema::S
    writer::T
end

@inline getwriter(x::SchemaBSONWriter) = getfield(x,:writer)
@inline getschema(x::SchemaBSONWriter) = getfield(x,:schema)
@inline Base.close(x::SchemaBSONWriter) = close(getwriter(x))

@inline function Base.setindex!(x::SchemaBSONWriter, value)
    schema = getschema(x)
    writer = getwriter(x)
 
    version = getversion(schema)
    if !isnothing(version)
        writer[:_v] = version
    end

    build_closure(schema, value)(writer)
end

@inline function build_closure(schema::BSONSchema, value)
    element = getelement(schema)
    if element isa BSONValue
        convert(gettype(element), value)
    elseif element isa BSONDocument
        fields = _getfields(element)
        @inline writer -> _setfields!(schema, fields, writer, value)
    elseif element isa BSONArray
        @inline writer -> _setarrayfields!(schema, writer, value)
    elseif element isa BSONAbstract
        throw(ErrorException("schema contains a BSONAbstract field"))
    elseif element isa BSONSchema
        schema_ = getelement(schema)
        @inline writer -> (SchemaBSONWriter(schema_, writer)[] = value)
    else
        throw(ErrorException("not implemented yet"))
    end
end

@inline function _setfields!(schema, fields, writer, value)
    length(fields) == 0 && return
    field = fields[1]
    name = getname(field)
    writer[name] = build_closure(getproperty(schema, name, false), getproperty(value, name))
    _setfields!(schema, Base.tail(fields), writer, value)
end

@inline function _setarrayfields!(schema, writer, value)
    _schema = getindex(schema, false)
    for (i, x) in enumerate(value)
        is = i <= length(SMALL_INDEX_STRINGS) ? SMALL_INDEX_STRINGS[i] : string(i - 1)
        writer[is] = build_closure(_schema, x)
    end
    nothing
end


