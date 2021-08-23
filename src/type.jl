const BSON_TYPE_DOUBLE = 0x01
const BSON_TYPE_STRING = 0x02
const BSON_TYPE_DOCUMENT = 0x03
const BSON_TYPE_ARRAY = 0x04
const BSON_TYPE_BINARY = 0x05
const BSON_TYPE_UNDEFINED = 0x06
const BSON_TYPE_OBJECTID = 0x07
const BSON_TYPE_BOOL = 0x08
const BSON_TYPE_DATETIME = 0x09
const BSON_TYPE_NULL = 0x0A
const BSON_TYPE_REGEX = 0x0B
const BSON_TYPE_DB_POINTER = 0x0C
const BSON_TYPE_CODE = 0x0D
const BSON_TYPE_SYMBOL = 0x0E
const BSON_TYPE_CODE_WITH_SCOPE = 0x0F
const BSON_TYPE_INT32 = 0x10
const BSON_TYPE_TIMESTAMP = 0x11
const BSON_TYPE_INT64 = 0x12
const BSON_TYPE_DECIMAL128 = 0x13
const BSON_TYPE_MIN_KEY = 0xFF
const BSON_TYPE_MAX_KEY = 0x7F

const BSON_SUBTYPE_GENERIC_BINARY = 0x00
const BSON_SUBTYPE_FUNCTION = 0x01
const BSON_SUBTYPE_BINARY_OLD = 0x02
const BSON_SUBTYPE_UUID_OLD = 0x03
const BSON_SUBTYPE_UUID = 0x04
const BSON_SUBTYPE_MD5 = 0x05
const BSON_SUBTYPE_ENCRYPTED = 0x06

bson_type(::Type{Float64}) = BSON_TYPE_DOUBLE