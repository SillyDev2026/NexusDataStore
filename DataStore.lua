--!native
--!optimize 2

local Data = require(script.Parent.PlayersData)
export type DataTable = Data.Data

export type DataTemplate = {
	Version: number,
	Data: DataTable,
}

export type LockMode = "Wait" | "Cancel" | "Steal"
export type StorageMode = "Buffer" | "Table"
export type TableStrategy = "Auto" | "Compact" | "Dynamic"
export type StringStrategy = "Auto" | "Raw" | "LZ" | "ASCII7" | "LowASCII5" | "Identifier6" | "Numeric4"
export type BufferStrategy = "Auto" | "Raw" | "LZ" | "Sparse" | "Nibble"
export type EntropyStrategy = "Auto" | "Huffman" | "None"
export type UserSubject = Player | number

export type OpenOptions = {
	Locked: LockMode?,
}

export type CompressionOptions = {
	Mode: "Binary"?,
	CompressStrings: boolean?,
	StringStrategy: StringStrategy?,
	UseStringDictionary: boolean?,
	TableCompression: boolean?,
	HomogeneousArrays: boolean?,
	DeltaArrays: boolean?,
	RunLengthArrays: boolean?,
	CompactMapKeys: boolean?,
	TableKeyMapping: boolean?,
	TableStrategy: TableStrategy?,
	CompressBuffers: boolean?,
	BufferStrategy: BufferStrategy?,
	BufferMinLength: number?,
	BufferSearchDepth: number?,
	BufferWindowSize: number?,
	BufferMaxMatch: number?,
	EntropyCoding: boolean?,
	EntropyStrategy: EntropyStrategy?,
	AllowExpansion: boolean?,
}

type CompressionPacket = {
	Data: buffer,
	Hash: number?,
	Bytes: number,
	Bits: number,
	RawBytes: number?,
	SavedBytes: number?,
	Codec: string?,
	UsefulBits: number?,
	PhysicalBits: number?,
	PaddingBits: number?,
	Entropy: string?,
	[string]: any,
}

type IndexedLayoutObject = {
	Version: number,
	Keys: {string},
	Mode: string,
	Encode: (self: IndexedLayoutObject, value: DataTable, options: CompressionOptions?) -> CompressionPacket,
	Decode: (self: IndexedLayoutObject, packet: CompressionPacket | buffer, options: CompressionOptions?) -> DataTable,
	Stats: ((self: IndexedLayoutObject, value: DataTable, options: CompressionOptions?) -> DataTable)?,
	[string]: any,
}

type CompressionModule = {
	Version: () -> string,
	Encode: (value: any, options: CompressionOptions?) -> CompressionPacket,
	Decode: (packet: CompressionPacket | buffer, options: CompressionOptions?) -> any,
	Pack: (value: any, options: CompressionOptions?) -> CompressionPacket,
	Unpack: (packet: CompressionPacket | buffer, options: CompressionOptions?) -> any,
	CompressTablePacket: (value: DataTable, options: CompressionOptions?) -> CompressionPacket,
	DecompressTable: (packet: CompressionPacket | buffer, options: CompressionOptions?) -> DataTable,
	IndexedLayout: (template: DataTable, version: number?) -> IndexedLayoutObject,
	CompressBuffer: (data: buffer, options: CompressionOptions?) -> buffer,
	DecompressBuffer: (data: buffer, options: CompressionOptions?) -> buffer,
	Hash: (data: buffer) -> number,
	BufferMode: ((data: buffer) -> string)?,
	[string]: any,
}

export type Migration = (data: DataTable, fromVersion: number, toVersion: number) -> DataTable?

export type DataStoreConfig = {
	Name: string,
	Scope: string?,
	KeyPrefix: string?,
	CompactPlayerKeys: boolean?,
	CompactKeyPrefix: string?,
	MigrateLegacyPlayerKeys: boolean?,
	DeleteLegacyPlayerKeys: boolean?,

	DataTemplate: DataTemplate?,
	Template: DataTable?,
	DataVersion: number?,
	Migrations: {[number]: Migration}?,
	RejectFutureDataVersion: boolean?,
	Reconcile: boolean?,

	AutoSave: boolean?,
	AutoSaveInterval: number?,

	SessionLocking: boolean?,
	SessionLockTimeout: number?,
	LoadTimeout: number?,
	LockRetryInterval: number?,
	MemoryLockRetryAttempts: number?,
	SessionCompressionEnabled: boolean?,
	SessionStoreDiagnostics: boolean?,

	RetryAttempts: number?,
	RetryDelay: number?,
	MaxRetryDelay: number?,
	ShutdownTimeout: number?,
	BudgetAware: boolean?,
	BudgetWaitTimeout: number?,

	StorageMode: StorageMode?,
	BufferStorage: boolean?,
	CompressionEnabled: boolean?,
	BufferUtilEnabled: boolean?,
	BufferWriterInitialCapacity: number?,

	SchemaBufferEnabled: boolean?,
	SchemaBufferCompress: boolean?,
	SchemaFallbackToGeneric: boolean?,
	SchemaHistory: {[number | string]: DataTable | DataTemplate}?,

	CompressionIndexedLayout: boolean?,
	CompressionCompareAdaptiveTable: boolean?,
	CompressionLayoutHistory: {[number | string]: DataTable | DataTemplate}?,

	CompressionTableStrategy: TableStrategy?,
	CompressionCompressStrings: boolean?,
	CompressionStringStrategy: StringStrategy?,
	CompressionUseStringDictionary: boolean?,
	CompressionHomogeneousArrays: boolean?,
	CompressionDeltaArrays: boolean?,
	CompressionRunLengthArrays: boolean?,
	CompressionCompactMapKeys: boolean?,
	CompressionTableKeyMapping: boolean?,
	CompressionEntropyCoding: boolean?,
	CompressionEntropyStrategy: EntropyStrategy?,
	CompressionAllowExpansion: boolean?,
	CompressionCompareLegacyBuffer: boolean?,

	CompressionMinBufferBytes: number?,
	CompressionMinSavingsBytes: number?,
	CompressionBufferStrategy: BufferStrategy?,
	CompressionBufferMinLength: number?,
	CompressionBufferSearchDepth: number?,
	CompressionBufferWindowSize: number?,
	CompressionBufferMaxMatch: number?,

	MaxBufferBytes: number?,
	MaxDepth: number?,
	MaxTableEntries: number?,
	Debug: boolean?,

	[string]: any,
}

type LegacySchemaLeaf = {
	Path: {string},
	PathText: string,
	Kind: string,
	Default: any,
}

type LegacySchema = {
	Version: number,
	Template: DataTable,
	Leaves: {LegacySchemaLeaf},
	FieldCount: number,
	BitmapBytes: number,
	Fingerprint: number,
	Descriptor: string,
}

export type ResolvedConfig = {
	Name: string?,
	Scope: string?,
	KeyPrefix: string,
	CompactPlayerKeys: boolean,
	CompactKeyPrefix: string,
	MigrateLegacyPlayerKeys: boolean,
	DeleteLegacyPlayerKeys: boolean,

	DataTemplate: DataTemplate,
	Template: DataTable,
	DataVersion: number,
	Migrations: {[number]: Migration}?,
	RejectFutureDataVersion: boolean,
	Reconcile: boolean,

	AutoSave: boolean,
	AutoSaveInterval: number,

	SessionLocking: boolean,
	SessionLockTimeout: number,
	LoadTimeout: number,
	LockRetryInterval: number,
	MemoryLockRetryAttempts: number,
	SessionCompressionEnabled: boolean,
	SessionStoreDiagnostics: boolean,

	RetryAttempts: number,
	RetryDelay: number,
	MaxRetryDelay: number,
	ShutdownTimeout: number,
	BudgetAware: boolean,
	BudgetWaitTimeout: number,

	StorageMode: StorageMode,
	BufferStorage: boolean?,
	CompressionEnabled: boolean,
	BufferUtilEnabled: boolean,
	BufferWriterInitialCapacity: number,

	SchemaBufferEnabled: boolean,
	SchemaBufferCompress: boolean,
	SchemaFallbackToGeneric: boolean,
	SchemaHistory: {[number | string]: DataTable | DataTemplate}?,

	CompressionIndexedLayout: boolean,
	CompressionCompareAdaptiveTable: boolean,
	CompressionLayoutHistory: {[number | string]: DataTable | DataTemplate}?,

	CompressionTableStrategy: TableStrategy,
	CompressionCompressStrings: boolean,
	CompressionStringStrategy: StringStrategy,
	CompressionUseStringDictionary: boolean,
	CompressionHomogeneousArrays: boolean,
	CompressionDeltaArrays: boolean,
	CompressionRunLengthArrays: boolean,
	CompressionCompactMapKeys: boolean,
	CompressionTableKeyMapping: boolean,
	CompressionEntropyCoding: boolean,
	CompressionEntropyStrategy: EntropyStrategy,
	CompressionAllowExpansion: boolean,
	CompressionCompareLegacyBuffer: boolean,

	CompressionMinBufferBytes: number,
	CompressionMinSavingsBytes: number,
	CompressionBufferStrategy: BufferStrategy,
	CompressionBufferMinLength: number,
	CompressionBufferSearchDepth: number,
	CompressionBufferWindowSize: number,
	CompressionBufferMaxMatch: number,

	MaxBufferBytes: number,
	MaxDepth: number,
	MaxTableEntries: number,
	Debug: boolean,

	_CompressionLayoutsPrepared: boolean,
	_CompressionLayoutsByVersion: {[number]: IndexedLayoutObject},
	_CompressionLayoutErrors: {[number]: string},
	_SessionCompressionLayout: IndexedLayoutObject?,

	_SchemaPrepared: boolean,
	_SchemaByVersion: {[number]: LegacySchema},
	_SchemaCurrent: LegacySchema?,
	_SchemaReason: string?,

	[string]: any,
}

type SignalConnection = {
	Connected: boolean,
	Disconnect: (self: SignalConnection) -> (),
}

export type SignalObject = {
	_listeners: {[any]: (...any) -> ()},
	_destroyed: boolean,
	Connect: (self: SignalObject, callback: (...any) -> ()) -> SignalConnection,
	Once: (self: SignalObject, callback: (...any) -> ()) -> SignalConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type EntryState = {
	Entries: number,
}

type CompactionInfo = {
	WorkingBytes: number,
	UsedBytes: number,
	RemovedBytes: number,
	UsedBits: number,
	PaddingBits: number,
}

type WriterObject = {
	Data: buffer,
	Position: number,
	LastWorkingBytes: number,
	LastUsedBytes: number,
	LastRemovedBytes: number,
	Ensure: (self: WriterObject, additional: number) -> (),
	U8: (self: WriterObject, value: number) -> (),
	U32: (self: WriterObject, value: number) -> (),
	F64: (self: WriterObject, value: number) -> (),
	RawString: (self: WriterObject, value: string) -> (),
	RawBuffer: (self: WriterObject, value: buffer) -> (),
	VarUInt: (self: WriterObject, value: number) -> (),
	VarInt: (self: WriterObject, value: number) -> (),
	Finish: (self: WriterObject) -> buffer,
	GetCompactionInfo: (self: WriterObject) -> CompactionInfo,
}

type ReaderObject = {
	Data: buffer,
	Position: number,
	Length: number,
	Need: (self: ReaderObject, bytes: number) -> (),
	U8: (self: ReaderObject) -> number,
	U32: (self: ReaderObject) -> number,
	F64: (self: ReaderObject) -> number,
	RawString: (self: ReaderObject, length: number) -> string,
	RawBuffer: (self: ReaderObject, length: number) -> buffer,
	VarUInt: (self: ReaderObject) -> number,
	VarInt: (self: ReaderObject) -> number,
}

type LegacyBitWriter = {
	Data: buffer,
	BitPosition: number,
	VarUIntMode: number,
	Scratch8: buffer,
	LastWorkingBytes: number,
	LastUsedBytes: number,
	LastUsedBits: number,
	LastPaddingBits: number,
	LastRemovedBytes: number,
	Need: (self: LegacyBitWriter, bitCount: number) -> (),
	Bit: (self: LegacyBitWriter, value: boolean) -> (),
	UInt: (self: LegacyBitWriter, bitCount: number, value: number) -> (),
	U8: (self: LegacyBitWriter, value: number) -> (),
	U32: (self: LegacyBitWriter, value: number) -> (),
	RawBuffer: (self: LegacyBitWriter, value: buffer) -> (),
	RawString: (self: LegacyBitWriter, value: string) -> (),
	F64: (self: LegacyBitWriter, value: number) -> (),
	LegacyVarUInt: (self: LegacyBitWriter, value: number) -> (),
	TieredVarUInt: (self: LegacyBitWriter, value: number) -> (),
	VarUInt: (self: LegacyBitWriter, value: number) -> (),
	VarInt: (self: LegacyBitWriter, value: number) -> (),
	Finish: (self: LegacyBitWriter) -> buffer,
	GetCompactionInfo: (self: LegacyBitWriter) -> CompactionInfo,
}

type LegacyBitReader = {
	Data: buffer,
	BitPosition: number,
	BitLength: number,
	VarUIntMode: number,
	Scratch8: buffer,
	Need: (self: LegacyBitReader, bitCount: number) -> (),
	Bit: (self: LegacyBitReader) -> boolean,
	UInt: (self: LegacyBitReader, bitCount: number) -> number,
	U8: (self: LegacyBitReader) -> number,
	U32: (self: LegacyBitReader) -> number,
	RawBuffer: (self: LegacyBitReader, length: number) -> buffer,
	RawString: (self: LegacyBitReader, length: number) -> string,
	F64: (self: LegacyBitReader) -> number,
	LegacyVarUInt: (self: LegacyBitReader) -> number,
	TieredVarUInt: (self: LegacyBitReader) -> number,
	VarUInt: (self: LegacyBitReader) -> number,
	VarInt: (self: LegacyBitReader) -> number,
	RemainingBits: (self: LegacyBitReader) -> number,
	RequireZeroPadding: (self: LegacyBitReader) -> (),
}

export type StorageStats = {
	RawBytes: number,
	StoredBytes: number,
	SavedBytes: number,
	SavingsPercent: number,
	Mode: string,
	Codec: string?,
	Compressed: boolean?,
	FrameBytes: number?,
	PayloadBytes: number?,
	UsefulBits: number?,
	PhysicalBits: number?,
	PaddingBits: number?,
	WorkingBufferBytes: number?,
	CompactedPayloadBytes: number?,
	UnusedWorkingBytesRemoved: number?,
	SchemaEligible: boolean?,
	SchemaCandidateAvailable: boolean?,
	SchemaSelected: boolean?,
	SchemaCandidateBytes: number?,
	SchemaCandidateMode: string?,
	SchemaRawBytes: number?,
	SchemaRawBits: number?,
	SchemaUsefulBits: number?,
	SchemaPaddingBits: number?,
	SchemaVarUIntMode: string?,
	SchemaFieldCount: number?,
	SchemaPresentFields: number?,
	SchemaDefaultFieldsOmitted: number?,
	SchemaFingerprint: number?,
	SchemaWorkingBufferBytes: number?,
	SchemaCompactedPayloadBytes: number?,
	SchemaUnusedWorkingBytesRemoved: number?,
	AdaptiveCandidateBytes: number?,
	IndexedCandidateError: string?,
	[string]: any,
}

export type PreparedStorage = {
	Value: any,
	RawBuffer: buffer?,
	Bytes: number?,
	RawBytes: number?,
	SavedBytes: number,
	SavingsPercent: number,
	Compressed: boolean,
	CompressionMode: string,
	WorkingBufferBytes: number?,
	CompactedPayloadBytes: number?,
	UnusedWorkingBytesRemoved: number,
	SchemaEligible: boolean,
	SchemaCandidateAvailable: boolean,
	SchemaSelected: boolean,
	SchemaCandidateBytes: number?,
	SchemaCandidateMode: string?,
	SchemaRawBytes: number?,
	SchemaRawBits: number?,
	SchemaUsefulBits: number?,
	SchemaPaddingBits: number?,
	SchemaVarUIntMode: string?,
	SchemaFieldCount: number?,
	SchemaPresentFields: number?,
	SchemaDefaultFieldsOmitted: number?,
	SchemaFingerprint: number?,
	SchemaWorkingBufferBytes: number?,
	SchemaCompactedPayloadBytes: number?,
	SchemaUnusedWorkingBytesRemoved: number,
}

export type SessionLock = {
	Id: string,
	JobId: string?,
	PlaceId: number?,
	TouchedAt: number?,
	Released: boolean?,
	Corrupt: boolean?,
	Error: any?,
}

export type SessionStats = {
	RawBytes: number?,
	StoredBytes: number?,
	SavedBytes: number,
	SavingsPercent: number,
	Compressed: boolean,
	Mode: string,
	Format: number?,
	WorkingBufferBytes: number?,
	CompactedPayloadBytes: number?,
	UnusedWorkingBytesRemoved: number?,
	UsefulBits: number?,
	PhysicalBits: number?,
	PaddingBits: number?,
}

export type KeyInfo = {
	UserId: number,
	Key: string,
	KeyBytes: number,
	LegacyKey: string,
	LegacyKeyBytes: number,
	SavedBytes: number,
	SavingsPercent: number,
	Compact: boolean,
}

type StoreCore = {
	Name: string,
	Config: ResolvedConfig,
	_store: any,
	_lockMap: any,
	_profiles: {[number]: any},
	_closed: boolean,
	_autosaveCursor: number,
	_playerRemovingConnection: RBXScriptConnection?,
	ProfileLoaded: SignalObject,
	ProfileReleased: SignalObject,
	Issue: SignalObject,
	[string]: any,
}

export type ProfileObject = {
	Store: StoreCore,
	UserId: number,
	Player: Player?,
	Key: string,
	SessionId: string,
	Version: number,
	Data: DataTable,
	MetaData: {[string]: any},
	Changed: SignalObject,
	Saved: SignalObject,
	Released: SignalObject,

	_active: boolean,
	_saving: boolean,
	_dirty: boolean,
	_revision: number,
	_lastSavedRevision: number,
	_lastSave: number,
	_lastBufferBytes: number?,
	_lastRawBufferBytes: number?,
	_lastBufferCompressed: boolean,
	_lastCompressionMode: string?,
	_lastWorkingBufferBytes: number?,
	_lastCompactedPayloadBytes: number?,
	_lastUnusedWorkingBytesRemoved: number,
	_lastSchemaEligible: boolean,
	_lastSchemaCandidateAvailable: boolean,
	_lastSchemaSelected: boolean,
	_lastSchemaCandidateBytes: number?,
	_lastSchemaCandidateMode: string?,
	_lastSchemaRawBytes: number?,
	_lastSchemaRawBits: number?,
	_lastSchemaUsefulBits: number?,
	_lastSchemaPaddingBits: number?,
	_lastSchemaVarUIntMode: string?,
	_lastSchemaFieldCount: number?,
	_lastSchemaPresentFields: number?,
	_lastSchemaDefaultFieldsOmitted: number?,
	_lastSchemaFingerprint: number?,
	_lastSchemaWorkingBufferBytes: number?,
	_lastSchemaCompactedPayloadBytes: number?,
	_lastSchemaUnusedWorkingBytesRemoved: number,
	_lastSessionLockBytes: number?,
	_lastSessionRawBytes: number?,
	_lastSessionCompressed: boolean,
	_lastSessionCompressionMode: string?,
	_lastSessionWorkingBufferBytes: number?,
	_lastSessionCompactedPayloadBytes: number?,
	_lastSessionUnusedWorkingBytesRemoved: number,
	_releaseRequested: string?,
	_releaseReason: string?,
	_legacyKeyToDelete: string?,

	_deactivate: (self: ProfileObject, reason: string?) -> (),
	_markChanged: (self: ProfileObject) -> (),
	IsActive: (self: ProfileObject) -> boolean,
	IsDirty: (self: ProfileObject) -> boolean,
	Get: (self: ProfileObject, key: any) -> any,
	GetDataCopy: (self: ProfileObject) -> DataTable,
	GetDataTemplate: (self: ProfileObject) -> DataTemplate,
	GetBuffer: (self: ProfileObject) -> buffer,
	ToBuffer: (self: ProfileObject) -> buffer,
	GetStorageInfo: (self: ProfileObject) -> {[string]: any},
	MarkDirty: (self: ProfileObject) -> (),
	Set: (self: ProfileObject, key: any, value: any) -> any,
	Update: (self: ProfileObject, key: any, callback: (any) -> any) -> any,
	Increment: (self: ProfileObject, key: any, amount: number?) -> number,
	Overwrite: (self: ProfileObject, data: DataTable) -> DataTable,
	Reconcile: (self: ProfileObject) -> DataTable,
	_waitForOperation: (self: ProfileObject) -> boolean,
	_snapshotForSave: (self: ProfileObject) -> (DataTable, PreparedStorage, number),
	SaveAsync: (self: ProfileObject) -> (boolean, any?),
	ReleaseAsync: (self: ProfileObject, reason: string?) -> (boolean, any?),
}

export type StoreObject = {
	Name: string,
	Config: ResolvedConfig,
	_store: any,
	_lockMap: any,
	_profiles: {[number]: ProfileObject},
	_closed: boolean,
	_autosaveCursor: number,
	_playerRemovingConnection: RBXScriptConnection?,
	ProfileLoaded: SignalObject,
	ProfileReleased: SignalObject,
	Issue: SignalObject,

	_lockKey: (self: StoreObject, userId: number) -> string,
	_makeLockValue: (self: StoreObject, sessionId: string, released: boolean) -> (any, SessionStats),
	_acquireSessionLock: (self: StoreObject, userId: number, sessionId: string, mode: LockMode) -> (boolean, any?, SessionStats?),
	_refreshSessionLock: (self: StoreObject, profile: ProfileObject) -> (boolean, any?),
	_releaseSessionLock: (self: StoreObject, profile: ProfileObject | {UserId: number, SessionId: string}) -> (boolean, any?),
	_legacyKey: (self: StoreObject, userId: number) -> string,
	_key: (self: StoreObject, userId: number) -> string,
	_readStoredValue: (self: StoreObject, userId: number) -> (boolean, any, string, string),
	_autoSaveLoop: (self: StoreObject) -> (),

	GetKeyInfo: (self: StoreObject, subject: UserSubject) -> KeyInfo,
	GetCompressionLayoutInfo: (self: StoreObject) -> {[string]: any},
	GetSchemaInfo: (self: StoreObject) -> {[string]: any},
	GetLegacySchemaInfo: (self: StoreObject) -> {[string]: any},
	GetProfile: (self: StoreObject, subject: UserSubject) -> ProfileObject?,
	OpenPlayerAsync: (self: StoreObject, subject: UserSubject, options: OpenOptions?) -> (ProfileObject?, any?, any?),
	LoadPlayerAsync: (self: StoreObject, subject: UserSubject, options: OpenOptions?) -> (ProfileObject?, any?, any?),
	ViewTemplateAsync: (self: StoreObject, subject: UserSubject) -> (DataTemplate?, any?, string?),
	ViewAsync: (self: StoreObject, subject: UserSubject) -> (DataTable?, any?, any?, string?),
	GetStoredBufferAsync: (self: StoreObject, subject: UserSubject) -> (buffer?, any?),
	GetStoredPayloadAsync: (self: StoreObject, subject: UserSubject) -> (any, string?, string?),
	GetSessionLockInfoAsync: (self: StoreObject, subject: UserSubject) -> (SessionLock?, any?, number?),
	SavePlayerAsync: (self: StoreObject, subject: UserSubject) -> (boolean, any?),
	ReleasePlayerAsync: (self: StoreObject, subject: UserSubject, reason: string?) -> (boolean, any?),
	CloseAsync: (self: StoreObject) -> boolean,
}

export type DataStoreModule = {
	new: (config: DataStoreConfig) -> StoreObject,
	CompressDataTemplate: (dataTemplate: DataTemplate, options: {[string]: any}?) -> {[string]: any},
	DecompressDataTemplate: (dataBuffer: buffer, options: {[string]: any}?) -> (DataTemplate | DataTable),
	Encode: (data: any, options: {[string]: any}?) -> buffer,
	Decode: (dataBuffer: buffer, options: {[string]: any}?) -> any,
	CompressStorageBuffer: (dataBuffer: buffer, options: {[string]: any}?) -> (buffer, boolean, StorageStats),
	DecompressStorageBuffer: (dataBuffer: buffer, options: {[string]: any}?) -> buffer,
	CompactBufferExact: (dataBuffer: buffer, usedBytes: number?) -> buffer,
	EncodeUserIdKey: (userId: number) -> string,
	DecodeUserIdKey: (encoded: string) -> number,
	Version: () -> string,
	FormatVersion: () -> number,
	BufferUtilVersion: () -> string,
	CompressionVersion: () -> string,
	BufferEncoding: string,
	SessionFormatVersion: number,
	SchemaFormatVersion: number,
	Profile: {[string]: any},
	Signal: {
		new: () -> SignalObject,
	},
}

type ValidateState = EntryState


local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Compression: CompressionModule? = nil

local function getCompression(): CompressionModule
	if Compression ~= nil then
		return Compression
	end

	local moduleScript = assert(
		script:WaitForChild("Compression", 10),
		"DataStore v2.1.0 requires a child ModuleScript named Compression v3.0.0"
	)

	local codec: any = require(moduleScript)
	assert(
		type(codec) == "table"
			and type(codec.Version) == "function"
			and codec.Version() == "3.0.0"
			and type(codec.Encode) == "function"
			and type(codec.Decode) == "function"
			and type(codec.Pack) == "function"
			and type(codec.Unpack) == "function"
			and type(codec.CompressTablePacket) == "function"
			and type(codec.DecompressTable) == "function"
			and type(codec.IndexedLayout) == "function"
			and type(codec.CompressBuffer) == "function"
			and type(codec.DecompressBuffer) == "function"
			and type(codec.Hash) == "function",
		"DataStore v2.1.0 requires Compression v3.0.0 with indexed + adaptive table codecs"
	)

	Compression = codec :: CompressionModule
	return Compression :: CompressionModule
end

local DataStore: {[string]: any} = {}
DataStore.__index = DataStore

local Profile: {[string]: any} = {}
Profile.__index = Profile

local Signal: {[string]: any} = {}
Signal.__index = Signal

local VERSION = "2.1.0"
local STORAGE_FORMAT_VERSION = 8
local SESSION_FORMAT_VERSION = 2
local LEGACY_SESSION_FORMAT_VERSION = 1
local SESSION_MAGIC = 0x53
local SESSION_FLAG_RELEASED = 0x01
local SESSION_FLAG_ID_GUID = 0x02
local SESSION_FLAG_JOB_GUID = 0x04
local SESSION_FLAG_DIAGNOSTICS = 0x08
local BUFFER_ENCODING = "BufferV1"
local TABLE_ENCODING = "Table"
local STORAGE_FRAME_MAGIC = 0xB7
local STORAGE_CODEC_INDEXED = 1
local STORAGE_CODEC_TABLE = 2
local SESSION_LAYOUT_VERSION = 1
local SESSION_TEMPLATE: DataTable = {
	-- Session ids are generated GUIDs. Storing the UUID as 16 raw bytes avoids
	-- paying for a 36-byte textual GUID while still letting Compression own the
	-- actual schema/bit encoding.
	Id = buffer.create(16),
	JobId = "",
	PlaceId = 0,
	TouchedAt = 0,
	Released = false,
}

local LEGACY_FORMAT_TAG = "__SimpleDataStore"
local LEGACY_FORMAT_V151 = 3
local LEGACY_FORMAT_V150 = 2
local LEGACY_FORMAT_V1 = 1

local CODEC_MAGIC = "SDSB"
local CODEC_VERSION = 1
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_SAFE_SIGNED_VARINT = math.floor(MAX_SAFE_INTEGER / 2)
local ADLER_MOD = 65521

-- v1.9.0 compact player-key codec. Base62 keeps keys printable and reversible
-- while avoiding binary/Base64 expansion. A one-byte prefix namespaces new keys
-- away from legacy decimal/custom-prefix keys during migration.
local KEY_BASE62_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local KEY_BASE62_RADIX = #KEY_BASE62_ALPHABET

local function encodeBase62UInt(value: number): string
	assert(type(value) == "number" and value >= 0 and value <= MAX_SAFE_INTEGER and value == math.floor(value), "Base62 expects a non-negative safe integer")
	if value == 0 then
		return "0"
	end

	local chars: {string} = {}
	while value > 0 do
		local remainder = value % KEY_BASE62_RADIX
		value = math.floor(value / KEY_BASE62_RADIX)
		chars[#chars + 1] = string.sub(KEY_BASE62_ALPHABET, remainder + 1, remainder + 1)
	end

	local left = 1
	local right = #chars
	while left < right do
		chars[left], chars[right] = chars[right], chars[left]
		left += 1
		right -= 1
	end

	return table.concat(chars)
end

local function decodeBase62UInt(value: string): number
	assert(type(value) == "string" and #value > 0, "Base62 expects a non-empty string")
	local result = 0
	for i = 1, #value do
		local byte = string.byte(value, i)
		local digit: number
		if byte >= 48 and byte <= 57 then
			digit = byte - 48
		elseif byte >= 65 and byte <= 90 then
			digit = byte - 65 + 10
		elseif byte >= 97 and byte <= 122 then
			digit = byte - 97 + 36
		else
			error("Invalid Base62 character", 2)
		end

		result = result * KEY_BASE62_RADIX + digit
		if result > MAX_SAFE_INTEGER then
			error("Base62 value exceeds Luau safe integer range", 2)
		end
	end
	return result
end

local TAG_NIL = 0
local TAG_FALSE = 1
local TAG_TRUE = 2
local TAG_UINT = 3
local TAG_SINT = 4
local TAG_F64 = 5
local TAG_STRING = 6
local TAG_ARRAY = 7
local TAG_MAP = 8
local TAG_BUFFER = 9
local TAG_VECTOR2 = 10
local TAG_VECTOR3 = 11
local TAG_COLOR3 = 12
local TAG_CFRAME = 13
local TAG_UDIM = 14
local TAG_UDIM2 = 15

local DEFAULTS: ResolvedConfig = {
	Scope = nil,
	KeyPrefix = "Player_",
	CompactPlayerKeys = true,
	CompactKeyPrefix = "p",
	MigrateLegacyPlayerKeys = true,
	DeleteLegacyPlayerKeys = true,

	DataTemplate = {
		Version = 1,
		Data = {},
	},

	Template = {},
	DataVersion = 1,
	Migrations = nil,
	RejectFutureDataVersion = true,
	Reconcile = true,

	AutoSave = true,
	AutoSaveInterval = 60,

	SessionLocking = true,
	SessionLockTimeout = 180,
	LoadTimeout = 30,
	LockRetryInterval = 1,
	MemoryLockRetryAttempts = 4,
	SessionCompressionEnabled = true,
	SessionStoreDiagnostics = false,

	RetryAttempts = 5,
	RetryDelay = 0.75,
	MaxRetryDelay = 8,

	ShutdownTimeout = 25,

	BudgetAware = true,
	BudgetWaitTimeout = 10,

	StorageMode = "Buffer",

	CompressionEnabled = true,

	-- v2.0.0 uses native buffer growth only. BufferUtil is no longer required.
	-- BufferWriterInitialCapacity remains for legacy SDSB encode helpers.
	BufferUtilEnabled = false,
	BufferWriterInitialCapacity = 32,

	-- Legacy v1.9 SchemaBitBuffer settings are decode-only. They are retained so
	-- existing v1.9 saves can migrate forward, but new saves never use this codec.
	SchemaBufferEnabled = true,
	SchemaBufferCompress = false,
	SchemaFallbackToGeneric = true,
	SchemaHistory = nil,

	-- v2.0.0 Compression v3 storage. IndexedLayout removes template field names and
	-- default values; adaptive table compression is also evaluated as a safe
	-- self-describing fallback for dynamic/unknown runtime structures.
	CompressionIndexedLayout = true,
	CompressionCompareAdaptiveTable = true,
	CompressionLayoutHistory = nil,

	-- DataStore persists Packet.Data, so the persistence codec intentionally uses
	-- Compression "Binary" mode. BinaryWithHash stores its hash in Packet metadata
	-- rather than inside Packet.Data and would lose that metadata in DataStore.
	-- Compression v3 adaptive table options.
	CompressionTableStrategy = "Auto",
	CompressionCompressStrings = true,
	CompressionStringStrategy = "Auto",
	CompressionUseStringDictionary = true,
	CompressionHomogeneousArrays = true,
	CompressionDeltaArrays = true,
	CompressionRunLengthArrays = true,
	CompressionCompactMapKeys = true,
	CompressionTableKeyMapping = true,
	CompressionEntropyCoding = true,
	CompressionEntropyStrategy = "Auto",
	CompressionAllowExpansion = false,
	CompressionCompareLegacyBuffer = true,

	-- Legacy BufferV1 compression settings retained only for old-save decoding
	-- and the public CompressStorageBuffer compatibility helper.
	CompressionMinBufferBytes = 16,
	CompressionMinSavingsBytes = 1,
	CompressionBufferStrategy = "Auto",
	CompressionBufferMinLength = 6,
	CompressionBufferSearchDepth = 32,
	CompressionBufferWindowSize = 32767,
	CompressionBufferMaxMatch = 66,

	MaxBufferBytes = 3800000,
	MaxDepth = 64,
	MaxTableEntries = 100000,

	_CompressionLayoutsPrepared = false,
	_CompressionLayoutsByVersion = {},
	_CompressionLayoutErrors = {},
	_SessionCompressionLayout = nil,
	_SchemaPrepared = false,
	_SchemaByVersion = {},
	_SchemaCurrent = nil,
	_SchemaReason = "SchemaBufferDisabled",

	Debug = false,
}

local function debugWarn(config: ResolvedConfig, ...: any): ()
	if config.Debug then
		warn("[DataStore v" .. VERSION .. "]", ...)
	end
end

function Signal.new(): SignalObject
	return setmetatable({
		_listeners = {},
		_destroyed = false,
	}, Signal)
end

function Signal.Connect(self: SignalObject, callback: (...any) -> ()): SignalConnection
	assert(type(callback) == "function", "Signal:Connect expects a function")
	assert(not self._destroyed, "Signal is destroyed")

	local signal = self
	local token = {}
	local connection = { Connected = true } :: any
	signal._listeners[token] = callback

	function connection.Disconnect(self: SignalConnection): ()
		if not connection.Connected then
			return
		end
		connection.Connected = false
		if not signal._destroyed then
			signal._listeners[token] = nil
		end
	end

	return connection
end

function Signal.Once(self: SignalObject, callback: (...any) -> ()): SignalConnection
	local connection: SignalConnection? = nil
	connection = self:Connect(function(...: any): ()
		local activeConnection = connection
		if activeConnection ~= nil then
			activeConnection:Disconnect()
		end
		callback(...)
	end)
	return connection :: SignalConnection
end

function Signal.Fire(self: SignalObject, ...: any): ()
	if self._destroyed then
		return
	end

	for _, callback in pairs(self._listeners) do
		task.spawn(callback, ...)
	end
end

function Signal.Destroy(self: SignalObject): ()
	if self._destroyed then
		return
	end
	self._destroyed = true
	table.clear(self._listeners)
end

local function cloneBuffer(source: buffer): buffer
	local length = buffer.len(source)
	local out = buffer.create(length)
	if length > 0 then
		buffer.copy(out, 0, source, 0, length)
	end
	return out
end

local function deepCopy(value: any, seen: {[any]: boolean}?): any
	local robloxType = typeof(value)
	if robloxType == "buffer" then
		return cloneBuffer(value)
	end

	if type(value) ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		error("Circular tables cannot be copied", 3)
	end

	seen[value] = true
	local out = {}
	for key, child in pairs(value) do
		out[deepCopy(key, seen)] = deepCopy(child, seen)
	end
	seen[value] = nil
	return out
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value)
end

local function isArray(value: any): (boolean, number)
	if type(value) ~= "table" then
		return false, 0
	end

	local count = 0
	local maxIndex = 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			return false, 0
		end
		count += 1
		if key > maxIndex then
			maxIndex = key
		end
	end

	return count == maxIndex, maxIndex
end

local function reconcile(target: DataTable, template: DataTable): DataTable
	if type(target) ~= "table" or type(template) ~= "table" then
		return target
	end

	local templateIsArray = isArray(template)
	if templateIsArray then
		return target
	end

	for key, defaultValue in pairs(template) do
		local current = target[key]
		if current == nil then
			target[key] = deepCopy(defaultValue)
		elseif type(current) == "table" and type(defaultValue) == "table" then
			local defaultIsArray = isArray(defaultValue)
			if not defaultIsArray then
				reconcile(current, defaultValue)
			end
		end
	end

	return target
end

local function validateSavable(value: any, path: string?, seen: {[any]: boolean}?, depth: number?, state: ValidateState?, config: ResolvedConfig?): boolean
	path = path or "Data"
	seen = seen or {}
	depth = depth or 0
	state = state or { Entries = 0 }
	config = config or DEFAULTS

	if depth > config.MaxDepth then
		error(path .. " exceeded MaxDepth", 3)
	end

	local robloxType = typeof(value)
	local valueType = type(value)

	if value == nil or valueType == "boolean" then
		return true
	end

	if valueType == "number" then
		if not isFiniteNumber(value) then
			error(path .. " contains NaN or infinity", 3)
		end
		return true
	end

	if valueType == "string" then
		if config.StorageMode == "Table" and utf8.len(value) == nil then
			error(path .. " contains invalid UTF-8; use Buffer storage for arbitrary byte strings", 3)
		end
		return true
	end

	if robloxType == "buffer" then
		return true
	end

	if robloxType == "Vector2" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains Vector2, which requires Buffer storage", 3)
		end
		if not isFiniteNumber(value.X) or not isFiniteNumber(value.Y) then
			error(path .. " contains a non-finite Vector2", 3)
		end
		return true
	elseif robloxType == "Vector3" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains Vector3, which requires Buffer storage", 3)
		end
		if not isFiniteNumber(value.X) or not isFiniteNumber(value.Y) or not isFiniteNumber(value.Z) then
			error(path .. " contains a non-finite Vector3", 3)
		end
		return true
	elseif robloxType == "Color3" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains Color3, which requires Buffer storage", 3)
		end
		if not isFiniteNumber(value.R) or not isFiniteNumber(value.G) or not isFiniteNumber(value.B) then
			error(path .. " contains a non-finite Color3", 3)
		end
		return true
	elseif robloxType == "CFrame" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains CFrame, which requires Buffer storage", 3)
		end
		for _, component in ipairs({ value:GetComponents() }) do
			if not isFiniteNumber(component) then
				error(path .. " contains a non-finite CFrame", 3)
			end
		end
		return true
	elseif robloxType == "UDim" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains UDim, which requires Buffer storage", 3)
		end
		if not isFiniteNumber(value.Scale) or not isInteger(value.Offset) or math.abs(value.Offset) > MAX_SAFE_SIGNED_VARINT then
			error(path .. " contains an invalid UDim", 3)
		end
		return true
	elseif robloxType == "UDim2" then
		if config.StorageMode ~= "Buffer" then
			error(path .. " contains UDim2, which requires Buffer storage", 3)
		end
		if not isFiniteNumber(value.X.Scale) or not isFiniteNumber(value.Y.Scale)
			or not isInteger(value.X.Offset) or not isInteger(value.Y.Offset)
			or math.abs(value.X.Offset) > MAX_SAFE_SIGNED_VARINT or math.abs(value.Y.Offset) > MAX_SAFE_SIGNED_VARINT then
			error(path .. " contains an invalid UDim2", 3)
		end
		return true
	end

	if valueType ~= "table" then
		error(path .. " contains unsupported type " .. robloxType, 3)
	end

	if seen[value] then
		error(path .. " contains a circular table", 3)
	end
	seen[value] = true

	local numericKeys = 0
	local stringKeys = 0
	local maxIndex = 0

	for key, child in pairs(value) do
		state.Entries += 1
		if state.Entries > config.MaxTableEntries then
			error(path .. " exceeded MaxTableEntries", 3)
		end

		local keyType = type(key)
		if keyType == "number" then
			if key < 1 or key ~= math.floor(key) then
				error(path .. " contains a non-positive or non-integer numeric key", 3)
			end
			numericKeys += 1
			if key > maxIndex then
				maxIndex = key
			end
		elseif keyType == "string" then
			if config.StorageMode == "Table" and utf8.len(key) == nil then
				error(path .. " contains an invalid UTF-8 table key", 3)
			end
			stringKeys += 1
		else
			error(path .. " contains unsupported table key type " .. keyType, 3)
		end

		if numericKeys > 0 and stringKeys > 0 then
			error(path .. " mixes numeric and string keys", 3)
		end

		validateSavable(child, path .. "." .. tostring(key), seen, depth + 1, state, config)
	end

	if numericKeys > 0 and numericKeys ~= maxIndex then
		error(path .. " contains a numeric array with gaps", 3)
	end

	seen[value] = nil
	return true
end

local function resizeBuffer(source: buffer, newLength: number): buffer
	assert(typeof(source) == "buffer", "resizeBuffer expects buffer")
	assert(type(newLength) == "number" and newLength >= 0 and newLength == math.floor(newLength), "resizeBuffer expects integer length")

	local out = buffer.create(newLength)
	local copyLength = math.min(buffer.len(source), newLength)
	if copyLength > 0 then
		buffer.copy(out, 0, source, 0, copyLength)
	end
	return out
end

local function compactBufferBytes(source: buffer, usedBytes: number): buffer
	assert(typeof(source) == "buffer", "compactBufferBytes expects buffer")
	assert(type(usedBytes) == "number" and usedBytes >= 0 and usedBytes == math.floor(usedBytes), "compactBufferBytes expects integer usedBytes")
	assert(usedBytes <= buffer.len(source), "compactBufferBytes exceeds source length")

	if usedBytes == buffer.len(source) then
		return cloneBuffer(source)
	end

	local out = buffer.create(usedBytes)
	if usedBytes > 0 then
		buffer.copy(out, 0, source, 0, usedBytes)
	end
	return out
end

local function writeUintBitsNative(data: buffer, bitOffset: number, bitCount: number, value: number): ()
	assert(typeof(data) == "buffer", "writeUintBitsNative expects buffer")
	assert(bitCount >= 1 and bitCount <= 53, "writeUintBitsNative width must be 1..53")
	assert(value >= 0 and value == math.floor(value), "writeUintBitsNative expects unsigned integer")

	local remaining = bitCount
	local position = bitOffset
	local current = value

	while remaining > 0 do
		local byteIndex = position // 8
		local bitIndex = position % 8
		local take = math.min(8 - bitIndex, remaining)
		local base = 2 ^ take
		local chunk = current % base
		local oldByte = buffer.readu8(data, byteIndex)
		local lowBase = 2 ^ bitIndex
		local highShift = bitIndex + take
		local low = oldByte % lowBase
		local high = math.floor(oldByte / (2 ^ highShift)) * (2 ^ highShift)
		buffer.writeu8(data, byteIndex, low + chunk * lowBase + high)

		current = math.floor(current / base)
		position += take
		remaining -= take
	end
end

local function readUintBitsNative(data: buffer, bitOffset: number, bitCount: number): number
	assert(typeof(data) == "buffer", "readUintBitsNative expects buffer")
	assert(bitCount >= 1 and bitCount <= 53, "readUintBitsNative width must be 1..53")

	local remaining = bitCount
	local position = bitOffset
	local result = 0
	local multiplier = 1

	while remaining > 0 do
		local byteIndex = position // 8
		local bitIndex = position % 8
		local take = math.min(8 - bitIndex, remaining)
		local base = 2 ^ take
		local byte = buffer.readu8(data, byteIndex)
		local chunk = math.floor(byte / (2 ^ bitIndex)) % base
		result += chunk * multiplier
		multiplier *= base
		position += take
		remaining -= take
	end

	return result
end

local Writer: {[string]: any} = {}
Writer.__index = Writer

function Writer.new(capacity: number?): WriterObject
	local requested = math.max(1, math.floor(capacity or DEFAULTS.BufferWriterInitialCapacity or 32))
	return setmetatable({
		Data = buffer.create(requested),
		Position = 0,
		LastWorkingBytes = requested,
		LastUsedBytes = 0,
		LastRemovedBytes = 0,
	}, Writer)
end

function Writer.Ensure(self: WriterObject, additional: number): ()
	local needed = self.Position + additional
	if needed <= buffer.len(self.Data) then
		return
	end

	local nextLength = math.max(needed, math.max(16, buffer.len(self.Data) * 2))
	self.Data = resizeBuffer(self.Data, nextLength)
end

function Writer.U8(self: WriterObject, value: number): ()
	self:Ensure(1)
	buffer.writeu8(self.Data, self.Position, value)
	self.Position += 1
end

function Writer.U32(self: WriterObject, value: number): ()
	self:Ensure(4)
	buffer.writeu32(self.Data, self.Position, value)
	self.Position += 4
end

function Writer.F64(self: WriterObject, value: number): ()
	self:Ensure(8)
	buffer.writef64(self.Data, self.Position, value)
	self.Position += 8
end

function Writer.RawString(self: WriterObject, value: string): ()
	local length = #value
	self:Ensure(length)
	if length > 0 then
		buffer.writestring(self.Data, self.Position, value)
		self.Position += length
	end
end

function Writer.RawBuffer(self: WriterObject, value: buffer): ()
	local length = buffer.len(value)
	self:Ensure(length)
	if length > 0 then
		buffer.copy(self.Data, self.Position, value, 0, length)
		self.Position += length
	end
end

function Writer.VarUInt(self: WriterObject, value: number): ()
	assert(value >= 0 and value <= MAX_SAFE_INTEGER and isInteger(value), "VarUInt expects a non-negative safe integer")
	local remaining = value
	repeat
		local byte = remaining % 128
		remaining = math.floor(remaining / 128)
		if remaining > 0 then
			byte += 128
		end
		self:U8(byte)
	until remaining == 0
end

function Writer.VarInt(self: WriterObject, value: number): ()
	assert(math.abs(value) <= MAX_SAFE_SIGNED_VARINT and isInteger(value), "VarInt expects a safe integer")
	local encoded = if value >= 0 then value * 2 else -value * 2 - 1
	self:VarUInt(encoded)
end

function Writer.Finish(self: WriterObject): buffer
	local workingBytes = buffer.len(self.Data)
	local usedBytes = self.Position
	local out = compactBufferBytes(self.Data, usedBytes)

	self.LastWorkingBytes = workingBytes
	self.LastUsedBytes = usedBytes
	self.LastRemovedBytes = math.max(0, workingBytes - usedBytes)
	return out
end

function Writer.GetCompactionInfo(self: WriterObject): CompactionInfo
	local usedBytes = self.LastUsedBytes or 0
	return {
		WorkingBytes = self.LastWorkingBytes or 0,
		UsedBytes = usedBytes,
		RemovedBytes = self.LastRemovedBytes or 0,
		UsedBits = usedBytes * 8,
		PaddingBits = 0,
	}
end

local Reader: {[string]: any} = {}
Reader.__index = Reader

function Reader.new(data: buffer): ReaderObject
	return setmetatable({
		Data = data,
		Position = 0,
		Length = buffer.len(data),
	}, Reader)
end

function Reader.Need(self: ReaderObject, bytes: number): ()
	if bytes < 0 or self.Position + bytes > self.Length then
		error("DataStore buffer decode overflow", 0)
	end
end

function Reader.U8(self: ReaderObject): number
	self:Need(1)
	local value = buffer.readu8(self.Data, self.Position)
	self.Position += 1
	return value
end

function Reader.U32(self: ReaderObject): number
	self:Need(4)
	local value = buffer.readu32(self.Data, self.Position)
	self.Position += 4
	return value
end

function Reader.F64(self: ReaderObject): number
	self:Need(8)
	local value = buffer.readf64(self.Data, self.Position)
	self.Position += 8
	return value
end

function Reader.RawString(self: ReaderObject, length: number): string
	self:Need(length)
	local value = if length == 0 then "" else buffer.readstring(self.Data, self.Position, length)
	self.Position += length
	return value
end

function Reader.RawBuffer(self: ReaderObject, length: number): buffer
	self:Need(length)
	local out = buffer.create(length)
	if length > 0 then
		buffer.copy(out, 0, self.Data, self.Position, length)
		self.Position += length
	end
	return out
end

function Reader.VarUInt(self: ReaderObject): number
	local result = 0
	local multiplier = 1
	for _ = 1, 8 do
		local byte = self:U8()
		result += (byte % 128) * multiplier
		if result > MAX_SAFE_INTEGER then
			error("DataStore buffer VarUInt exceeds safe integer range", 0)
		end
		if byte < 128 then
			return result
		end
		multiplier *= 128
	end
	error("DataStore buffer VarUInt overflow", 0)
end

function Reader.VarInt(self: ReaderObject): number
	local value = self:VarUInt()
	if value % 2 == 0 then
		return value / 2
	end
	return -((value + 1) / 2)
end

local function adler32(data: buffer, startOffset: number, length: number): number
	local a = 1
	local b = 0
	local stop = startOffset + length
	local i = startOffset
	while i < stop do
		local chunkStop = math.min(i + 4096, stop)
		while i < chunkStop do
			a = (a + buffer.readu8(data, i)) % ADLER_MOD
			b = (b + a) % ADLER_MOD
			i += 1
		end
	end
	return b * 65536 + a
end

-- v1.9.0 positional SchemaBitBuffer codec. Only one top-level local is used for the
-- whole implementation so the module keeps substantial headroom under Luau's
-- 200-local/register limit.
local SchemaCodec: any = {
	MAGIC = 0xA4,
	LEGACY_VERSION = 1,
	VERSION = 2,
	VARUINT_LEGACY = 0,
	VARUINT_TIERED = 1,
	KIND_UINT = "uint",
	KIND_INT = "int",
	KIND_F64 = "f64",
	KIND_BOOL = "bool",
	KIND_STRING = "string",
	KIND_BUFFER = "buffer",
	KIND_VECTOR2 = "Vector2",
	KIND_VECTOR3 = "Vector3",
	KIND_COLOR3 = "Color3",
	KIND_CFRAME = "CFrame",
	KIND_UDIM = "UDim",
	KIND_UDIM2 = "UDim2",
}

function SchemaCodec.kindForDefault(value: any): string?
	local kind = typeof(value)
	if kind == "number" then
		if isInteger(value) and value >= 0 and value <= MAX_SAFE_INTEGER then
			return SchemaCodec.KIND_UINT
		elseif isInteger(value) and math.abs(value) <= MAX_SAFE_SIGNED_VARINT then
			return SchemaCodec.KIND_INT
		end
		return SchemaCodec.KIND_F64
	elseif kind == "boolean" then
		return SchemaCodec.KIND_BOOL
	elseif kind == "string" then
		return SchemaCodec.KIND_STRING
	elseif kind == "buffer" then
		return SchemaCodec.KIND_BUFFER
	elseif kind == "Vector2" then
		return SchemaCodec.KIND_VECTOR2
	elseif kind == "Vector3" then
		return SchemaCodec.KIND_VECTOR3
	elseif kind == "Color3" then
		return SchemaCodec.KIND_COLOR3
	elseif kind == "CFrame" then
		return SchemaCodec.KIND_CFRAME
	elseif kind == "UDim" then
		return SchemaCodec.KIND_UDIM
	elseif kind == "UDim2" then
		return SchemaCodec.KIND_UDIM2
	end
	return nil
end

function SchemaCodec.pathValue(root: DataTable, path: {string}): any
	local current = root
	for i = 1, #path do
		if type(current) ~= "table" then
			return nil
		end
		current = current[path[i]]
	end
	return current
end

function SchemaCodec.setPathValue(root: DataTable, path: {string}, value: any): ()
	local current = root
	for i = 1, #path - 1 do
		local key = path[i]
		local nextValue = current[key]
		if type(nextValue) ~= "table" then
			nextValue = {}
			current[key] = nextValue
		end
		current = nextValue
	end
	current[path[#path]] = value
end

function SchemaCodec.valuesEqual(a: any, b: any, kind: string): boolean
	if kind == SchemaCodec.KIND_BUFFER then
		if typeof(a) ~= "buffer" or typeof(b) ~= "buffer" then
			return false
		end
		local length = buffer.len(a)
		if length ~= buffer.len(b) then
			return false
		end
		for i = 0, length - 1 do
			if buffer.readu8(a, i) ~= buffer.readu8(b, i) then
				return false
			end
		end
		return true
	end
	return a == b
end

function SchemaCodec.defaultDescriptor(value: any, kind: string): string
	if kind == SchemaCodec.KIND_UINT or kind == SchemaCodec.KIND_INT or kind == SchemaCodec.KIND_F64 then
		return string.format("%.17g", value)
	elseif kind == SchemaCodec.KIND_BOOL then
		return value and "1" or "0"
	elseif kind == SchemaCodec.KIND_STRING then
		return value
	elseif kind == SchemaCodec.KIND_BUFFER then
		local length = buffer.len(value)
		return length > 0 and buffer.readstring(value, 0, length) or ""
	elseif kind == SchemaCodec.KIND_VECTOR2 then
		return string.format("%.17g,%.17g", value.X, value.Y)
	elseif kind == SchemaCodec.KIND_VECTOR3 then
		return string.format("%.17g,%.17g,%.17g", value.X, value.Y, value.Z)
	elseif kind == SchemaCodec.KIND_COLOR3 then
		return string.format("%.17g,%.17g,%.17g", value.R, value.G, value.B)
	elseif kind == SchemaCodec.KIND_CFRAME then
		local components = {value:GetComponents()}
		local parts: {string} = table.create(12)
		for i = 1, 12 do parts[i] = string.format("%.17g", components[i]) end
		return table.concat(parts, ",")
	elseif kind == SchemaCodec.KIND_UDIM then
		return string.format("%.17g,%.0f", value.Scale, value.Offset)
	elseif kind == SchemaCodec.KIND_UDIM2 then
		return string.format("%.17g,%.0f,%.17g,%.0f", value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
	end
	return ""
end

function SchemaCodec.compile(template: DataTable, version: number): (LegacySchema?, string?)
	if type(template) ~= "table" then
		return nil, "Schema template must be a table"
	end

	local leaves: {LegacySchemaLeaf} = {}
	local descriptor: {string} = {}

	local function walk(node: any, path: {string}): (boolean, string?)
		if type(node) == "table" then
			local arrayMode, arrayLength = isArray(node)
			if arrayMode and arrayLength > 0 then
				return false, "SchemaBuffer does not encode variable/array template nodes"
			end
			if next(node) == nil then
				return false, "SchemaBuffer does not encode empty/dynamic template tables"
			end

			local keys: {string} = {}
			for key in pairs(node) do
				if type(key) ~= "string" then
					return false, "SchemaBuffer map keys must be strings"
				end
				keys[#keys + 1] = key
			end
			table.sort(keys)

			for _, key in ipairs(keys) do
				local childPath = table.clone(path)
				childPath[#childPath + 1] = key
				local ok, reason = walk(node[key], childPath)
				if not ok then
					return false, reason
				end
			end
			return true
		end

		local kind = SchemaCodec.kindForDefault(node)
		if kind == nil then
			return false, "SchemaBuffer unsupported template leaf type " .. typeof(node)
		end

		local pathText = table.concat(path, ".")
		leaves[#leaves + 1] = {
			Path = path,
			PathText = pathText,
			Kind = kind,
			Default = deepCopy(node),
		}

		for _, component in ipairs(path) do
			descriptor[#descriptor + 1] = tostring(#component)
			descriptor[#descriptor + 1] = ":"
			descriptor[#descriptor + 1] = component
			descriptor[#descriptor + 1] = "/"
		end
		descriptor[#descriptor + 1] = kind
		descriptor[#descriptor + 1] = "="
		local defaultDescriptor = SchemaCodec.defaultDescriptor(node, kind)
		descriptor[#descriptor + 1] = tostring(#defaultDescriptor)
		descriptor[#descriptor + 1] = ":"
		descriptor[#descriptor + 1] = defaultDescriptor
		descriptor[#descriptor + 1] = ";"
		return true
	end

	local ok, reason = walk(template, {})
	if not ok then
		return nil, reason
	end
	if #leaves == 0 then
		return nil, "SchemaBuffer requires at least one fixed leaf"
	end

	local descriptorString = table.concat(descriptor)
	local descriptorBuffer = buffer.fromstring(descriptorString)
	local fingerprint = adler32(descriptorBuffer, 0, buffer.len(descriptorBuffer))

	return {
		Version = version,
		Template = deepCopy(template),
		Leaves = leaves,
		FieldCount = #leaves,
		BitmapBytes = math.ceil(#leaves / 8),
		Fingerprint = fingerprint,
		Descriptor = descriptorString,
	}
end

function SchemaCodec.ensureConfig(config: ResolvedConfig): ()
	if config._SchemaPrepared == true then
		return
	end

	config._SchemaPrepared = true
	config._SchemaByVersion = {}
	config._SchemaCurrent = nil
	config._SchemaReason = "SchemaBufferDisabled"

	if config.SchemaBufferEnabled ~= true then
		return
	end

	local current, currentReason = SchemaCodec.compile(config.Template or {}, config.DataVersion or 1)
	if current ~= nil then
		config._SchemaCurrent = current
		config._SchemaByVersion[current.Version] = current
		config._SchemaReason = nil
	else
		config._SchemaReason = currentReason
	end

	if type(config.SchemaHistory) == "table" then
		for rawVersion, historical in pairs(config.SchemaHistory) do
			local historyVersion = if type(rawVersion) == "number" then rawVersion else tonumber(rawVersion)
			if historyVersion ~= nil and historyVersion >= 0 and historyVersion == math.floor(historyVersion) then
				local historyData = historical
				if type(historical) == "table" and type(historical.Data) == "table" then
					historyData = historical.Data
				end
				if type(historyData) == "table" and config._SchemaByVersion[historyVersion] == nil then
					local compiled = SchemaCodec.compile(historyData :: DataTable, historyVersion)
					if compiled ~= nil then
						config._SchemaByVersion[historyVersion] = compiled
					end
				end
			end
		end
	end
end

function SchemaCodec.isFrame(data: any): boolean
	return typeof(data) == "buffer"
		and buffer.len(data) >= 2
		and buffer.readu8(data, 0) == SchemaCodec.MAGIC
end

function SchemaCodec.legacyVarUIntBits(value: number): number
	assert(value >= 0 and value <= MAX_SAFE_INTEGER and isInteger(value), "legacyVarUIntBits expects a non-negative safe integer")
	local bits = 8
	local remaining = value
	while remaining >= 128 do
		remaining = math.floor(remaining / 128)
		bits += 8
	end
	return bits
end

function SchemaCodec.tieredVarUIntBits(value: number): number
	assert(value >= 0 and value <= MAX_SAFE_INTEGER and isInteger(value), "tieredVarUIntBits expects a non-negative safe integer")
	if value <= 3 then
		return 4
	elseif value <= 35 then
		return 7
	elseif value <= 4131 then
		return 14
	elseif value <= 1052707 then
		return 23
	elseif value <= 4296020003 then
		return 36
	elseif value <= 281479272730659 then
		return 53
	end
	return 58
end

function SchemaCodec.zigzagEncode(value: number): number
	if value >= 0 then
		return value * 2
	end
	return (-value) * 2 - 1
end

function SchemaCodec.varUIntCostForLeaf(leaf: LegacySchemaLeaf, value: any): (number, number)
	local tiered = 0
	local legacy = 0

	local function addUnsigned(raw: number): ()
		tiered += SchemaCodec.tieredVarUIntBits(raw)
		legacy += SchemaCodec.legacyVarUIntBits(raw)
	end

	local kind = leaf.Kind
	if kind == SchemaCodec.KIND_UINT then
		if type(value) == "number" and isInteger(value) and value >= 0 and value <= MAX_SAFE_INTEGER then
			addUnsigned(value)
		end
	elseif kind == SchemaCodec.KIND_INT then
		if type(value) == "number" and isInteger(value) and math.abs(value) <= MAX_SAFE_SIGNED_VARINT then
			addUnsigned(SchemaCodec.zigzagEncode(value))
		end
	elseif kind == SchemaCodec.KIND_STRING then
		if type(value) == "string" then
			addUnsigned(#value)
		end
	elseif kind == SchemaCodec.KIND_BUFFER then
		if typeof(value) == "buffer" then
			addUnsigned(buffer.len(value))
		end
	elseif kind == SchemaCodec.KIND_UDIM then
		if typeof(value) == "UDim" and isInteger(value.Offset) and math.abs(value.Offset) <= MAX_SAFE_SIGNED_VARINT then
			addUnsigned(SchemaCodec.zigzagEncode(value.Offset))
		end
	elseif kind == SchemaCodec.KIND_UDIM2 then
		if typeof(value) == "UDim2" then
			if isInteger(value.X.Offset) and math.abs(value.X.Offset) <= MAX_SAFE_SIGNED_VARINT then
				addUnsigned(SchemaCodec.zigzagEncode(value.X.Offset))
			end
			if isInteger(value.Y.Offset) and math.abs(value.Y.Offset) <= MAX_SAFE_SIGNED_VARINT then
				addUnsigned(SchemaCodec.zigzagEncode(value.Y.Offset))
			end
		end
	end

	return tiered, legacy
end

function SchemaCodec.chooseVarUIntMode(dataTemplate: DataTemplate, schema: LegacySchema, present: {boolean}): (number, number, number)
	local tiered = SchemaCodec.tieredVarUIntBits(dataTemplate.Version)
	local legacy = SchemaCodec.legacyVarUIntBits(dataTemplate.Version)

	for index, leaf in ipairs(schema.Leaves) do
		if present[index] then
			local value = SchemaCodec.pathValue(dataTemplate.Data, leaf.Path)
			if value == nil then
				value = leaf.Default
			end
			local tieredBits, legacyBits = SchemaCodec.varUIntCostForLeaf(leaf, value)
			tiered += tieredBits
			legacy += legacyBits
		end
	end

	if tiered < legacy then
		return SchemaCodec.VARUINT_TIERED, tiered, legacy
	end
	return SchemaCodec.VARUINT_LEGACY, tiered, legacy
end

SchemaCodec.BitWriter = {}
SchemaCodec.BitWriter.__index = SchemaCodec.BitWriter

function SchemaCodec.BitWriter.new(capacity: number?, varUIntMode: number?): LegacyBitWriter
	local requested = math.max(1, math.floor(capacity or DEFAULTS.BufferWriterInitialCapacity or 32))
	return setmetatable({
		Data = buffer.create(requested),
		BitPosition = 0,
		VarUIntMode = varUIntMode or SchemaCodec.VARUINT_LEGACY,
		Scratch8 = buffer.create(8),
		LastWorkingBytes = requested,
		LastUsedBytes = 0,
		LastUsedBits = 0,
		LastPaddingBits = 0,
		LastRemovedBytes = 0,
	}, SchemaCodec.BitWriter)
end

function SchemaCodec.BitWriter.Need(self: LegacyBitWriter, bitCount: number): ()
	if bitCount < 0 then
		error("SchemaBitBuffer cannot reserve a negative bit count", 0)
	end

	local neededBytes = (self.BitPosition + bitCount + 7) // 8
	local currentBytes = buffer.len(self.Data)
	if neededBytes <= currentBytes then
		return
	end

	local nextBytes = math.max(neededBytes, math.max(1, currentBytes * 2))
	self.Data = resizeBuffer(self.Data, nextBytes)
end

function SchemaCodec.BitWriter.Bit(self: LegacyBitWriter, value: boolean): ()
	self:Need(1)
	writeUintBitsNative(self.Data, self.BitPosition, 1, value and 1 or 0)
	self.BitPosition += 1
end

function SchemaCodec.BitWriter.UInt(self: LegacyBitWriter, bitCount: number, value: number): ()
	if bitCount < 1 or bitCount > 53 then
		error("SchemaBitBuffer UInt width must be 1..53 bits", 0)
	end
	self:Need(bitCount)
	writeUintBitsNative(self.Data, self.BitPosition, bitCount, value)
	self.BitPosition += bitCount
end

function SchemaCodec.BitWriter.U8(self: LegacyBitWriter, value: number): ()
	self:UInt(8, value)
end

function SchemaCodec.BitWriter.U32(self: LegacyBitWriter, value: number): ()
	self:UInt(32, value)
end

function SchemaCodec.BitWriter.RawBuffer(self: LegacyBitWriter, value: buffer): ()
	local length = buffer.len(value)
	local offset = 0
	while offset + 4 <= length do
		self:UInt(32, buffer.readu32(value, offset))
		offset += 4
	end
	while offset < length do
		self:UInt(8, buffer.readu8(value, offset))
		offset += 1
	end
end

function SchemaCodec.BitWriter.RawString(self: LegacyBitWriter, value: string): ()
	if #value == 0 then
		return
	end
	self:RawBuffer(buffer.fromstring(value))
end

function SchemaCodec.BitWriter.F64(self: LegacyBitWriter, value: number): ()
	buffer.writef64(self.Scratch8, 0, value)
	self:UInt(32, buffer.readu32(self.Scratch8, 0))
	self:UInt(32, buffer.readu32(self.Scratch8, 4))
end

function SchemaCodec.BitWriter.LegacyVarUInt(self: LegacyBitWriter, value: number): ()
	assert(value >= 0 and value <= MAX_SAFE_INTEGER and isInteger(value), "Bit VarUInt expects a non-negative safe integer")
	local remaining = value
	repeat
		local byte = remaining % 128
		remaining = math.floor(remaining / 128)
		if remaining > 0 then
			byte += 128
		end
		self:UInt(8, byte)
	until remaining == 0
end

function SchemaCodec.BitWriter.TieredVarUInt(self: LegacyBitWriter, value: number): ()
	assert(value >= 0 and value <= MAX_SAFE_INTEGER and isInteger(value), "Tiered BitVarUInt expects a non-negative safe integer")

	if value <= 3 then
		self:Bit(false)
		self:Bit(false)
		self:UInt(2, value)
		return
	elseif value <= 35 then
		self:Bit(false)
		self:Bit(true)
		self:UInt(5, value - 4)
		return
	elseif value <= 4131 then
		self:Bit(true)
		self:Bit(false)
		self:UInt(12, value - 36)
		return
	elseif value <= 1052707 then
		self:Bit(true)
		self:Bit(true)
		self:Bit(false)
		self:UInt(20, value - 4132)
		return
	elseif value <= 4296020003 then
		self:Bit(true)
		self:Bit(true)
		self:Bit(true)
		self:Bit(false)
		self:UInt(32, value - 1052708)
		return
	elseif value <= 281479272730659 then
		self:Bit(true)
		self:Bit(true)
		self:Bit(true)
		self:Bit(true)
		self:Bit(false)
		self:UInt(48, value - 4296020004)
		return
	end

	self:Bit(true)
	self:Bit(true)
	self:Bit(true)
	self:Bit(true)
	self:Bit(true)
	self:UInt(53, value - 281479272730660)
end

function SchemaCodec.BitWriter.VarUInt(self: LegacyBitWriter, value: number): ()
	if self.VarUIntMode == SchemaCodec.VARUINT_TIERED then
		self:TieredVarUInt(value)
	else
		self:LegacyVarUInt(value)
	end
end

function SchemaCodec.BitWriter.VarInt(self: LegacyBitWriter, value: number): ()
	assert(math.abs(value) <= MAX_SAFE_SIGNED_VARINT and isInteger(value), "Bit VarInt expects a safe integer")
	self:VarUInt(SchemaCodec.zigzagEncode(value))
end

function SchemaCodec.BitWriter.Finish(self: LegacyBitWriter): buffer
	local workingBytes = buffer.len(self.Data)
	local usedBits = self.BitPosition
	local usedBytes = (usedBits + 7) // 8
	local paddingBits = usedBytes * 8 - usedBits
	local out = compactBufferBytes(self.Data, usedBytes)

	self.LastWorkingBytes = workingBytes
	self.LastUsedBytes = usedBytes
	self.LastUsedBits = usedBits
	self.LastPaddingBits = paddingBits
	self.LastRemovedBytes = math.max(0, workingBytes - usedBytes)
	return out
end

function SchemaCodec.BitWriter.GetCompactionInfo(self: LegacyBitWriter): CompactionInfo
	return {
		WorkingBytes = self.LastWorkingBytes or 0,
		UsedBytes = self.LastUsedBytes or 0,
		UsedBits = self.LastUsedBits or 0,
		PaddingBits = self.LastPaddingBits or 0,
		RemovedBytes = self.LastRemovedBytes or 0,
	}
end

SchemaCodec.BitReader = {}
SchemaCodec.BitReader.__index = SchemaCodec.BitReader

function SchemaCodec.BitReader.new(data: buffer, bitLength: number?, varUIntMode: number?): LegacyBitReader
	return setmetatable({
		Data = data,
		BitPosition = 0,
		BitLength = bitLength or (buffer.len(data) * 8),
		VarUIntMode = varUIntMode or SchemaCodec.VARUINT_LEGACY,
		Scratch8 = buffer.create(8),
	}, SchemaCodec.BitReader)
end

function SchemaCodec.BitReader.Need(self: LegacyBitReader, bitCount: number): ()
	if bitCount < 0 or self.BitPosition + bitCount > self.BitLength then
		error("SchemaBitBuffer decode overflow", 0)
	end
end

function SchemaCodec.BitReader.Bit(self: LegacyBitReader): boolean
	self:Need(1)
	local value = readUintBitsNative(self.Data, self.BitPosition, 1) ~= 0
	self.BitPosition += 1
	return value
end

function SchemaCodec.BitReader.UInt(self: LegacyBitReader, bitCount: number): number
	if bitCount < 1 or bitCount > 53 then
		error("SchemaBitBuffer UInt width must be 1..53 bits", 0)
	end
	self:Need(bitCount)
	local value = readUintBitsNative(self.Data, self.BitPosition, bitCount)
	self.BitPosition += bitCount
	return value
end

function SchemaCodec.BitReader.U8(self: LegacyBitReader): number
	return self:UInt(8)
end

function SchemaCodec.BitReader.U32(self: LegacyBitReader): number
	return self:UInt(32)
end

function SchemaCodec.BitReader.RawBuffer(self: LegacyBitReader, length: number): buffer
	if length < 0 then
		error("SchemaBitBuffer negative raw buffer length", 0)
	end

	self:Need(length * 8)
	local out = buffer.create(length)
	local offset = 0
	while offset + 4 <= length do
		buffer.writeu32(out, offset, self:UInt(32))
		offset += 4
	end
	while offset < length do
		buffer.writeu8(out, offset, self:UInt(8))
		offset += 1
	end
	return out
end

function SchemaCodec.BitReader.RawString(self: LegacyBitReader, length: number): string
	if length == 0 then
		return ""
	end
	local raw = self:RawBuffer(length)
	return buffer.readstring(raw, 0, length)
end

function SchemaCodec.BitReader.F64(self: LegacyBitReader): number
	buffer.writeu32(self.Scratch8, 0, self:UInt(32))
	buffer.writeu32(self.Scratch8, 4, self:UInt(32))
	return buffer.readf64(self.Scratch8, 0)
end

function SchemaCodec.BitReader.LegacyVarUInt(self: LegacyBitReader): number
	local result = 0
	local multiplier = 1
	for _ = 1, 8 do
		local byte = self:UInt(8)
		result += (byte % 128) * multiplier
		if result > MAX_SAFE_INTEGER then
			error("SchemaBitBuffer VarUInt exceeds safe integer range", 0)
		end
		if byte < 128 then
			return result
		end
		multiplier *= 128
	end
	error("SchemaBitBuffer VarUInt overflow", 0)
end

function SchemaCodec.BitReader.TieredVarUInt(self: LegacyBitReader): number
	local first = self:Bit()
	if not first then
		if not self:Bit() then
			return self:UInt(2)
		end
		return 4 + self:UInt(5)
	end

	if not self:Bit() then
		return 36 + self:UInt(12)
	end
	if not self:Bit() then
		return 4132 + self:UInt(20)
	end
	if not self:Bit() then
		return 1052708 + self:UInt(32)
	end
	if not self:Bit() then
		return 4296020004 + self:UInt(48)
	end

	local value = 281479272730660 + self:UInt(53)
	if value > MAX_SAFE_INTEGER then
		error("SchemaBitBuffer tiered VarUInt exceeds safe integer range", 0)
	end
	return value
end

function SchemaCodec.BitReader.VarUInt(self: LegacyBitReader): number
	if self.VarUIntMode == SchemaCodec.VARUINT_TIERED then
		return self:TieredVarUInt()
	end
	return self:LegacyVarUInt()
end

function SchemaCodec.BitReader.VarInt(self: LegacyBitReader): number
	local value = self:VarUInt()
	if value % 2 == 0 then
		return value / 2
	end
	return -((value + 1) / 2)
end

function SchemaCodec.BitReader.RemainingBits(self: LegacyBitReader): number
	return self.BitLength - self.BitPosition
end

function SchemaCodec.BitReader.RequireZeroPadding(self: LegacyBitReader): ()
	local remaining = self:RemainingBits()
	if remaining < 0 or remaining > 7 then
		error("SchemaBitBuffer frame contains trailing payload bits", 0)
	end
	if remaining > 0 and self:UInt(remaining) ~= 0 then
		error("SchemaBitBuffer frame contains non-zero padding bits", 0)
	end
end

function SchemaCodec.writeLeaf(writer: LegacyBitWriter, leaf: LegacySchemaLeaf, value: any): ()
	local kind = leaf.Kind
	if kind == SchemaCodec.KIND_UINT then
		if type(value) ~= "number" or not isInteger(value) or value < 0 or value > MAX_SAFE_INTEGER then
			error("SchemaBuffer unsigned field " .. leaf.PathText .. " is outside VarUInt range", 0)
		end
		writer:VarUInt(value)
	elseif kind == SchemaCodec.KIND_INT then
		if type(value) ~= "number" or not isInteger(value) or math.abs(value) > MAX_SAFE_SIGNED_VARINT then
			error("SchemaBuffer integer field " .. leaf.PathText .. " is outside signed VarInt range", 0)
		end
		writer:VarInt(value)
	elseif kind == SchemaCodec.KIND_F64 then
		if not isFiniteNumber(value) then
			error("SchemaBuffer number field " .. leaf.PathText .. " must be finite", 0)
		end
		writer:F64(value)
	elseif kind == SchemaCodec.KIND_BOOL then
		if type(value) ~= "boolean" then
			error("SchemaBuffer boolean field " .. leaf.PathText .. " changed type", 0)
		end
		-- A present boolean is always the inverse of its template default, so the
		-- presence bit itself stores the complete value with zero payload bytes.
	elseif kind == SchemaCodec.KIND_STRING then
		if type(value) ~= "string" then
			error("SchemaBuffer string field " .. leaf.PathText .. " changed type", 0)
		end
		writer:VarUInt(#value)
		writer:RawString(value)
	elseif kind == SchemaCodec.KIND_BUFFER then
		if typeof(value) ~= "buffer" then
			error("SchemaBuffer buffer field " .. leaf.PathText .. " changed type", 0)
		end
		writer:VarUInt(buffer.len(value))
		writer:RawBuffer(value)
	elseif kind == SchemaCodec.KIND_VECTOR2 then
		if typeof(value) ~= "Vector2" then error("SchemaBuffer Vector2 type mismatch at " .. leaf.PathText, 0) end
		writer:F64(value.X); writer:F64(value.Y)
	elseif kind == SchemaCodec.KIND_VECTOR3 then
		if typeof(value) ~= "Vector3" then error("SchemaBuffer Vector3 type mismatch at " .. leaf.PathText, 0) end
		writer:F64(value.X); writer:F64(value.Y); writer:F64(value.Z)
	elseif kind == SchemaCodec.KIND_COLOR3 then
		if typeof(value) ~= "Color3" then error("SchemaBuffer Color3 type mismatch at " .. leaf.PathText, 0) end
		writer:F64(value.R); writer:F64(value.G); writer:F64(value.B)
	elseif kind == SchemaCodec.KIND_CFRAME then
		if typeof(value) ~= "CFrame" then error("SchemaBuffer CFrame type mismatch at " .. leaf.PathText, 0) end
		local components = {value:GetComponents()}
		for i = 1, 12 do writer:F64(components[i]) end
	elseif kind == SchemaCodec.KIND_UDIM then
		if typeof(value) ~= "UDim" then error("SchemaBuffer UDim type mismatch at " .. leaf.PathText, 0) end
		writer:F64(value.Scale); writer:VarInt(value.Offset)
	elseif kind == SchemaCodec.KIND_UDIM2 then
		if typeof(value) ~= "UDim2" then error("SchemaBuffer UDim2 type mismatch at " .. leaf.PathText, 0) end
		writer:F64(value.X.Scale); writer:VarInt(value.X.Offset)
		writer:F64(value.Y.Scale); writer:VarInt(value.Y.Offset)
	else
		error("SchemaBuffer has unknown field kind " .. tostring(kind), 0)
	end
end

function SchemaCodec.readLeaf(reader: LegacyBitReader, leaf: LegacySchemaLeaf, config: ResolvedConfig): any
	local kind = leaf.Kind
	if kind == SchemaCodec.KIND_UINT then
		return reader:VarUInt()
	elseif kind == SchemaCodec.KIND_INT then
		return reader:VarInt()
	elseif kind == SchemaCodec.KIND_F64 then
		return reader:F64()
	elseif kind == SchemaCodec.KIND_BOOL then
		return not leaf.Default
	elseif kind == SchemaCodec.KIND_STRING then
		local length = reader:VarUInt()
		if length > config.MaxBufferBytes then error("SchemaBuffer string exceeds MaxBufferBytes", 0) end
		return reader:RawString(length)
	elseif kind == SchemaCodec.KIND_BUFFER then
		local length = reader:VarUInt()
		if length > config.MaxBufferBytes then error("SchemaBuffer nested buffer exceeds MaxBufferBytes", 0) end
		return reader:RawBuffer(length)
	elseif kind == SchemaCodec.KIND_VECTOR2 then
		return Vector2.new(reader:F64(), reader:F64())
	elseif kind == SchemaCodec.KIND_VECTOR3 then
		return Vector3.new(reader:F64(), reader:F64(), reader:F64())
	elseif kind == SchemaCodec.KIND_COLOR3 then
		return Color3.new(reader:F64(), reader:F64(), reader:F64())
	elseif kind == SchemaCodec.KIND_CFRAME then
		local components: {number} = table.create(12)
		for i = 1, 12 do components[i] = reader:F64() end
		return CFrame.new(table.unpack(components, 1, 12))
	elseif kind == SchemaCodec.KIND_UDIM then
		return UDim.new(reader:F64(), reader:VarInt())
	elseif kind == SchemaCodec.KIND_UDIM2 then
		return UDim2.new(reader:F64(), reader:VarInt(), reader:F64(), reader:VarInt())
	end
	error("SchemaBuffer contains unknown field kind " .. tostring(kind), 0)
end

function SchemaCodec.structureCompatible(data: any, template: any, pathText: string?): (boolean, string?)
	pathText = pathText or "Data"
	if type(template) ~= "table" then
		return true
	end
	if data == nil then
		return true
	end
	if type(data) ~= "table" then
		return false, pathText .. " changed from a schema table into " .. typeof(data)
	end

	for key in pairs(data) do
		if template[key] == nil then
			return false, pathText .. " contains schema-unknown field " .. tostring(key)
		end
	end

	for key, defaultValue in pairs(template) do
		if type(defaultValue) == "table" then
			local ok, reason = SchemaCodec.structureCompatible(data[key], defaultValue, pathText .. "." .. tostring(key))
			if not ok then return false, reason end
		end
	end
	return true
end

function SchemaCodec.encode(dataTemplate: DataTemplate, config: ResolvedConfig): (buffer?, any)
	SchemaCodec.ensureConfig(config)
	if config.SchemaBufferEnabled ~= true then
		return nil, "Disabled"
	end
	if type(dataTemplate) ~= "table" or type(dataTemplate.Data) ~= "table" or type(dataTemplate.Version) ~= "number" then
		return nil, "InvalidDataTemplate"
	end

	local schema = config._SchemaByVersion and config._SchemaByVersion[dataTemplate.Version] or nil
	if schema == nil then
		return nil, "No schema is available for DataTemplate version " .. tostring(dataTemplate.Version)
	end

	local compatible, compatibilityError = SchemaCodec.structureCompatible(dataTemplate.Data, schema.Template, "Data")
	if not compatible then
		return nil, compatibilityError
	end

	local present = table.create(schema.FieldCount, false)
	local presentCount = 0

	for index, leaf in ipairs(schema.Leaves) do
		local value = SchemaCodec.pathValue(dataTemplate.Data, leaf.Path)
		if value == nil then
			value = leaf.Default
		end
		if not SchemaCodec.valuesEqual(value, leaf.Default, leaf.Kind) then
			present[index] = true
			presentCount += 1
		end
	end

	local varUIntMode, tieredVarUIntBits, legacyVarUIntBits =
		SchemaCodec.chooseVarUIntMode(dataTemplate, schema, present)

	local writer = SchemaCodec.BitWriter.new(
		config.BufferWriterInitialCapacity or 32,
		varUIntMode
	)

	writer:U8(SchemaCodec.MAGIC)
	writer:U8(SchemaCodec.VERSION)
	writer:Bit(varUIntMode == SchemaCodec.VARUINT_TIERED)
	writer:VarUInt(dataTemplate.Version)
	writer:U32(schema.Fingerprint)

	-- v2 presence flags occupy exactly one bit per schema leaf. There is no
	-- standalone bitmap buffer and no forced byte boundary before payload data.
	for index = 1, schema.FieldCount do
		writer:Bit(present[index] == true)
	end

	local okWrite, writeError = pcall(function(): ()
		for index, leaf in ipairs(schema.Leaves) do
			if present[index] then
				local value = SchemaCodec.pathValue(dataTemplate.Data, leaf.Path)
				if value == nil then
					value = leaf.Default
				end
				SchemaCodec.writeLeaf(writer, leaf, value)
			end
		end
	end)
	if not okWrite then
		return nil, writeError
	end

	local body = writer:Finish()
	local compactInfo = writer:GetCompactionInfo()
	local bodyLength = buffer.len(body)
	local out = buffer.create(bodyLength + 4)
	if bodyLength > 0 then
		buffer.copy(out, 0, body, 0, bodyLength)
	end
	buffer.writeu32(out, bodyLength, adler32(out, 0, bodyLength))

	return out, {
		RawBytes = buffer.len(out),
		RawBits = buffer.len(out) * 8,
		UsefulBits = compactInfo.UsedBits + 32,
		BodyUsefulBits = compactInfo.UsedBits,
		PaddingBits = compactInfo.PaddingBits,
		FieldCount = schema.FieldCount,
		PresentFields = presentCount,
		DefaultFieldsOmitted = schema.FieldCount - presentCount,
		Fingerprint = schema.Fingerprint,
		Version = schema.Version,
		SchemaCodecVersion = SchemaCodec.VERSION,
		VarUIntMode = if varUIntMode == SchemaCodec.VARUINT_TIERED then "TieredBits" else "Legacy8BitGroups",
		TieredVarUIntBits = tieredVarUIntBits,
		LegacyVarUIntBits = legacyVarUIntBits,
		WorkingBufferBytes = compactInfo.WorkingBytes,
		CompactedPayloadBytes = compactInfo.UsedBytes + 4,
		UnusedWorkingBytesRemoved = compactInfo.RemovedBytes,
	}
end

function SchemaCodec.decodeLegacy(raw: buffer, config: ResolvedConfig): (DataTemplate, DataTable)
	local length = buffer.len(raw)
	if length < 11 then
		error("SchemaBuffer v1 frame is too small", 0)
	end

	local reader = Reader.new(raw)
	reader.Length = length - 4
	if reader:U8() ~= SchemaCodec.MAGIC then
		error("SchemaBuffer v1 magic mismatch", 0)
	end

	local codecVersion = reader:U8()
	if codecVersion ~= SchemaCodec.LEGACY_VERSION then
		error("Unsupported legacy SchemaBuffer codec version " .. tostring(codecVersion), 0)
	end

	local dataVersion = reader:VarUInt()
	local fingerprint = reader:U32()
	local schema = config._SchemaByVersion and config._SchemaByVersion[dataVersion] or nil
	if schema == nil then
		error(
			"SchemaBuffer v1 save uses DataTemplate version " .. tostring(dataVersion)
				.. ", but Config.SchemaHistory does not contain that template",
			0
		)
	end
	if fingerprint ~= schema.Fingerprint then
		error(
			"SchemaBuffer v1 fingerprint mismatch for DataTemplate version " .. tostring(dataVersion)
				.. "; bump DataTemplate.Version and preserve the old template in Config.SchemaHistory",
			0
		)
	end

	local bitmap = reader:RawBuffer(schema.BitmapBytes)
	local data = deepCopy(schema.Template)
	local presentCount = 0

	for index, leaf in ipairs(schema.Leaves) do
		if readUintBitsNative(bitmap, index - 1, 1) ~= 0 then
			presentCount += 1
			SchemaCodec.setPathValue(data, leaf.Path, SchemaCodec.readLeaf(reader, leaf, config))
		end
	end

	if reader.Position ~= reader.Length then
		error("SchemaBuffer v1 frame contains trailing payload bytes", 0)
	end

	validateSavable(data, "SchemaBufferV1Data", nil, 0, nil, config)
	return {
		Version = dataVersion,
		Data = data,
	}, {
		SchemaCodecVersion = SchemaCodec.LEGACY_VERSION,
		FieldCount = schema.FieldCount,
		PresentFields = presentCount,
		DefaultFieldsOmitted = schema.FieldCount - presentCount,
		Fingerprint = fingerprint,
		VarUIntMode = "LegacyByteAligned",
	}
end

function SchemaCodec.decode(raw: buffer, config: ResolvedConfig): (DataTemplate?, DataTable?)
	if not SchemaCodec.isFrame(raw) then
		return nil
	end
	SchemaCodec.ensureConfig(config)

	local length = buffer.len(raw)
	if length < 6 then
		error("SchemaBuffer frame is too small", 0)
	end

	local expectedChecksum = buffer.readu32(raw, length - 4)
	local actualChecksum = adler32(raw, 0, length - 4)
	if expectedChecksum ~= actualChecksum then
		error("SchemaBuffer checksum mismatch", 0)
	end

	local codecVersion = buffer.readu8(raw, 1)
	if codecVersion == SchemaCodec.LEGACY_VERSION then
		return SchemaCodec.decodeLegacy(raw, config)
	end
	if codecVersion ~= SchemaCodec.VERSION then
		error("Unsupported SchemaBuffer codec version " .. tostring(codecVersion), 0)
	end

	local bodyBitLength = (length - 4) * 8
	local reader = SchemaCodec.BitReader.new(raw, bodyBitLength, SchemaCodec.VARUINT_LEGACY)

	if reader:U8() ~= SchemaCodec.MAGIC then
		error("SchemaBitBuffer magic mismatch", 0)
	end
	if reader:U8() ~= SchemaCodec.VERSION then
		error("SchemaBitBuffer codec version mismatch", 0)
	end

	reader.VarUIntMode = if reader:Bit() then SchemaCodec.VARUINT_TIERED else SchemaCodec.VARUINT_LEGACY

	local dataVersion = reader:VarUInt()
	local fingerprint = reader:U32()
	local schema = config._SchemaByVersion and config._SchemaByVersion[dataVersion] or nil
	if schema == nil then
		error(
			"SchemaBitBuffer save uses DataTemplate version " .. tostring(dataVersion)
				.. ", but Config.SchemaHistory does not contain that template",
			0
		)
	end
	if fingerprint ~= schema.Fingerprint then
		error(
			"SchemaBitBuffer fingerprint mismatch for DataTemplate version " .. tostring(dataVersion)
				.. "; bump DataTemplate.Version and preserve the old template in Config.SchemaHistory",
			0
		)
	end

	local present = table.create(schema.FieldCount, false)
	for index = 1, schema.FieldCount do
		present[index] = reader:Bit()
	end

	local data = deepCopy(schema.Template)
	local presentCount = 0
	for index, leaf in ipairs(schema.Leaves) do
		if present[index] then
			presentCount += 1
			SchemaCodec.setPathValue(data, leaf.Path, SchemaCodec.readLeaf(reader, leaf, config))
		end
	end

	reader:RequireZeroPadding()
	validateSavable(data, "SchemaBitBufferData", nil, 0, nil, config)

	return {
		Version = dataVersion,
		Data = data,
	}, {
		SchemaCodecVersion = SchemaCodec.VERSION,
		FieldCount = schema.FieldCount,
		PresentFields = presentCount,
		DefaultFieldsOmitted = schema.FieldCount - presentCount,
		Fingerprint = fingerprint,
		VarUIntMode = if reader.VarUIntMode == SchemaCodec.VARUINT_TIERED then "TieredBits" else "Legacy8BitGroups",
	}
end

local writeValue: (WriterObject, any, number, {[any]: boolean}, EntryState, ResolvedConfig) -> ()
local readValue: (ReaderObject, number, EntryState, ResolvedConfig) -> any

writeValue = function(writer: WriterObject, value: any, depth: number, seen: {[any]: boolean}, state: EntryState, config: ResolvedConfig): ()
	if depth > config.MaxDepth then
		error("DataStore buffer encode exceeded MaxDepth", 0)
	end

	local robloxType = typeof(value)
	local valueType = type(value)

	if value == nil then
		writer:U8(TAG_NIL)
	elseif valueType == "boolean" then
		writer:U8(if value then TAG_TRUE else TAG_FALSE)
	elseif valueType == "number" then
		if not isFiniteNumber(value) then
			error("DataStore buffer cannot encode NaN or infinity", 0)
		end
		if isInteger(value) and value >= 0 and value <= MAX_SAFE_INTEGER then
			writer:U8(TAG_UINT)
			writer:VarUInt(value)
		elseif isInteger(value) and math.abs(value) <= MAX_SAFE_SIGNED_VARINT then
			writer:U8(TAG_SINT)
			writer:VarInt(value)
		else
			writer:U8(TAG_F64)
			writer:F64(value)
		end
	elseif valueType == "string" then
		writer:U8(TAG_STRING)
		writer:VarUInt(#value)
		writer:RawString(value)
	elseif robloxType == "buffer" then
		writer:U8(TAG_BUFFER)
		writer:VarUInt(buffer.len(value))
		writer:RawBuffer(value)
	elseif robloxType == "Vector2" then
		writer:U8(TAG_VECTOR2)
		writer:F64(value.X)
		writer:F64(value.Y)
	elseif robloxType == "Vector3" then
		writer:U8(TAG_VECTOR3)
		writer:F64(value.X)
		writer:F64(value.Y)
		writer:F64(value.Z)
	elseif robloxType == "Color3" then
		writer:U8(TAG_COLOR3)
		writer:F64(value.R)
		writer:F64(value.G)
		writer:F64(value.B)
	elseif robloxType == "CFrame" then
		writer:U8(TAG_CFRAME)
		local components = { value:GetComponents() }
		for i = 1, 12 do
			writer:F64(components[i])
		end
	elseif robloxType == "UDim" then
		writer:U8(TAG_UDIM)
		writer:F64(value.Scale)
		writer:VarInt(value.Offset)
	elseif robloxType == "UDim2" then
		writer:U8(TAG_UDIM2)
		writer:F64(value.X.Scale)
		writer:VarInt(value.X.Offset)
		writer:F64(value.Y.Scale)
		writer:VarInt(value.Y.Offset)
	elseif valueType == "table" then
		if seen[value] then
			error("DataStore buffer cannot encode circular tables", 0)
		end
		seen[value] = true

		local arrayMode, length = isArray(value)
		if arrayMode then
			writer:U8(TAG_ARRAY)
			writer:VarUInt(length)
			state.Entries += length
			if state.Entries > config.MaxTableEntries then
				error("DataStore buffer encode exceeded MaxTableEntries", 0)
			end
			for i = 1, length do
				writeValue(writer, value[i], depth + 1, seen, state, config)
			end
		else
			local keys: {string} = {}
			for key in pairs(value) do
				if type(key) ~= "string" then
					error("DataStore buffer maps require string keys", 0)
				end
				keys[#keys + 1] = key
			end
			table.sort(keys)
			writer:U8(TAG_MAP)
			writer:VarUInt(#keys)
			state.Entries += #keys
			if state.Entries > config.MaxTableEntries then
				error("DataStore buffer encode exceeded MaxTableEntries", 0)
			end
			for _, key in ipairs(keys) do
				writer:VarUInt(#key)
				writer:RawString(key)
				writeValue(writer, value[key], depth + 1, seen, state, config)
			end
		end

		seen[value] = nil
	else
		error("DataStore buffer cannot encode type " .. robloxType, 0)
	end
end

readValue = function(reader: ReaderObject, depth: number, state: EntryState, config: ResolvedConfig): any
	if depth > config.MaxDepth then
		error("DataStore buffer decode exceeded MaxDepth", 0)
	end

	local tag = reader:U8()
	if tag == TAG_NIL then
		return nil
	elseif tag == TAG_FALSE then
		return false
	elseif tag == TAG_TRUE then
		return true
	elseif tag == TAG_UINT then
		return reader:VarUInt()
	elseif tag == TAG_SINT then
		return reader:VarInt()
	elseif tag == TAG_F64 then
		local value = reader:F64()
		if not isFiniteNumber(value) then
			error("DataStore buffer decoded NaN or infinity", 0)
		end
		return value
	elseif tag == TAG_STRING then
		local length = reader:VarUInt()
		return reader:RawString(length)
	elseif tag == TAG_BUFFER then
		local length = reader:VarUInt()
		return reader:RawBuffer(length)
	elseif tag == TAG_VECTOR2 then
		return Vector2.new(reader:F64(), reader:F64())
	elseif tag == TAG_VECTOR3 then
		return Vector3.new(reader:F64(), reader:F64(), reader:F64())
	elseif tag == TAG_COLOR3 then
		return Color3.new(reader:F64(), reader:F64(), reader:F64())
	elseif tag == TAG_CFRAME then
		local components: {number} = table.create(12)
		for i = 1, 12 do
			components[i] = reader:F64()
		end
		return CFrame.new(table.unpack(components, 1, 12))
	elseif tag == TAG_UDIM then
		return UDim.new(reader:F64(), reader:VarInt())
	elseif tag == TAG_UDIM2 then
		local xScale = reader:F64()
		local xOffset = reader:VarInt()
		local yScale = reader:F64()
		local yOffset = reader:VarInt()
		return UDim2.new(xScale, xOffset, yScale, yOffset)
	elseif tag == TAG_ARRAY then
		local length = reader:VarUInt()
		state.Entries += length
		if state.Entries > config.MaxTableEntries then
			error("DataStore buffer decode exceeded MaxTableEntries", 0)
		end
		local out = table.create(length)
		for i = 1, length do
			out[i] = readValue(reader, depth + 1, state, config)
		end
		return out
	elseif tag == TAG_MAP then
		local count = reader:VarUInt()
		state.Entries += count
		if state.Entries > config.MaxTableEntries then
			error("DataStore buffer decode exceeded MaxTableEntries", 0)
		end
		local out = {}
		for _ = 1, count do
			local keyLength = reader:VarUInt()
			local key = reader:RawString(keyLength)
			out[key] = readValue(reader, depth + 1, state, config)
		end
		return out
	end

	error("DataStore buffer contains unknown type tag " .. tostring(tag), 0)
end

local function encodeBuffer(value: any, config: ResolvedConfig?): (buffer, CompactionInfo)
	config = config or DEFAULTS
	local codecConfig = table.clone(config)
	codecConfig.StorageMode = "Buffer"
	validateSavable(value, "Data", nil, 0, nil, codecConfig)

	local payloadWriter = Writer.new(config.BufferWriterInitialCapacity or 32)
	writeValue(payloadWriter, value, 0, {}, { Entries = 0 }, codecConfig)
	local payload = payloadWriter:Finish()
	local compactionInfo = payloadWriter:GetCompactionInfo()
	local payloadLength = buffer.len(payload)
	local totalLength = 4 + 1 + payloadLength + 4

	if totalLength > codecConfig.MaxBufferBytes then
		error(string.format("Encoded buffer is %d bytes, above MaxBufferBytes (%d)", totalLength, codecConfig.MaxBufferBytes), 2)
	end

	local out = buffer.create(totalLength)
	buffer.writestring(out, 0, CODEC_MAGIC)
	buffer.writeu8(out, 4, CODEC_VERSION)
	if payloadLength > 0 then
		buffer.copy(out, 5, payload, 0, payloadLength)
	end
	buffer.writeu32(out, 5 + payloadLength, adler32(out, 0, 5 + payloadLength))
	return out, compactionInfo
end

local function decodeBuffer(data: buffer, config: ResolvedConfig?): any
	config = config or DEFAULTS
	local codecConfig = table.clone(config)
	codecConfig.StorageMode = "Buffer"
	assert(typeof(data) == "buffer", "Decode expects a buffer")

	local length = buffer.len(data)
	if length < 9 then
		error("DataStore buffer is too small", 2)
	end
	if length > codecConfig.MaxBufferBytes then
		error("DataStore buffer exceeds MaxBufferBytes", 2)
	end

	local magic = buffer.readstring(data, 0, 4)
	if magic ~= CODEC_MAGIC then
		error("DataStore buffer has invalid magic", 2)
	end

	local version = buffer.readu8(data, 4)
	if version ~= CODEC_VERSION then
		error("Unsupported DataStore buffer codec version " .. tostring(version), 2)
	end

	local expectedChecksum = buffer.readu32(data, length - 4)
	local actualChecksum = adler32(data, 0, length - 4)
	if expectedChecksum ~= actualChecksum then
		error("DataStore buffer checksum mismatch", 2)
	end

	local payloadLength = length - 9
	local payload = buffer.create(payloadLength)
	if payloadLength > 0 then
		buffer.copy(payload, 0, data, 5, payloadLength)
	end

	local reader = Reader.new(payload)
	local value = readValue(reader, 0, { Entries = 0 }, codecConfig)
	if reader.Position ~= reader.Length then
		error("DataStore buffer contains trailing bytes", 2)
	end
	validateSavable(value, "Data", nil, 0, nil, codecConfig)
	return value
end

local function compressionOptions(config: ResolvedConfig): CompressionOptions
	return {
		Mode = "Binary",
		CompressBuffers = true,
		BufferStrategy = config.CompressionBufferStrategy,
		BufferMinLength = config.CompressionBufferMinLength,
		BufferSearchDepth = config.CompressionBufferSearchDepth,
		BufferWindowSize = config.CompressionBufferWindowSize,
		BufferMaxMatch = config.CompressionBufferMaxMatch,
		EntropyCoding = config.CompressionEntropyCoding,
		EntropyStrategy = config.CompressionEntropyStrategy,
		AllowExpansion = config.CompressionAllowExpansion,
	}
end

local function tableCompressionOptions(config: ResolvedConfig): CompressionOptions
	return {
		Mode = "Binary",
		TableCompression = true,
		TableStrategy = config.CompressionTableStrategy,
		CompressStrings = config.CompressionCompressStrings,
		StringStrategy = config.CompressionStringStrategy,
		UseStringDictionary = config.CompressionUseStringDictionary,
		HomogeneousArrays = config.CompressionHomogeneousArrays,
		DeltaArrays = config.CompressionDeltaArrays,
		RunLengthArrays = config.CompressionRunLengthArrays,
		CompactMapKeys = config.CompressionCompactMapKeys,
		TableKeyMapping = config.CompressionTableKeyMapping,
		CompressBuffers = true,
		BufferStrategy = config.CompressionBufferStrategy,
		BufferMinLength = config.CompressionBufferMinLength,
		BufferSearchDepth = config.CompressionBufferSearchDepth,
		BufferWindowSize = config.CompressionBufferWindowSize,
		BufferMaxMatch = config.CompressionBufferMaxMatch,
		EntropyCoding = config.CompressionEntropyCoding,
		EntropyStrategy = config.CompressionEntropyStrategy,
		AllowExpansion = config.CompressionAllowExpansion,
	}
end

local function cloneRawBuffer(value: buffer): buffer
	local out = buffer.create(buffer.len(value))
	if buffer.len(value) > 0 then
		buffer.copy(out, 0, value, 0, buffer.len(value))
	end
	return out
end

local function compressStorageBuffer(rawPayload: buffer, config: ResolvedConfig): (buffer, boolean, StorageStats)
	local rawBytes = buffer.len(rawPayload)
	if not config.CompressionEnabled or rawBytes < config.CompressionMinBufferBytes then
		return cloneRawBuffer(rawPayload), false, {
			RawBytes = rawBytes,
			StoredBytes = rawBytes,
			SavedBytes = 0,
			SavingsPercent = 0,
			Mode = "Raw",
		}
	end

	local codec = getCompression()
	local ok, packed = pcall(codec.CompressBuffer, rawPayload, compressionOptions(config))
	if not ok or typeof(packed) ~= "buffer" then
		debugWarn(config, "Buffer compression failed; saving raw BufferV1 payload instead:", packed)
		return cloneRawBuffer(rawPayload), false, {
			RawBytes = rawBytes,
			StoredBytes = rawBytes,
			SavedBytes = 0,
			SavingsPercent = 0,
			Mode = "RawFallback",
		}
	end

	local storedBytes = buffer.len(packed)
	local savedBytes = rawBytes - storedBytes
	if savedBytes < config.CompressionMinSavingsBytes then
		return cloneRawBuffer(rawPayload), false, {
			RawBytes = rawBytes,
			StoredBytes = rawBytes,
			SavedBytes = 0,
			SavingsPercent = 0,
			Mode = "Raw",
		}
	end

	local mode = "Compressed"
	if type(codec.BufferMode) == "function" then
		local modeOk, modeResult = pcall(codec.BufferMode, packed)
		if modeOk and type(modeResult) == "string" then
			mode = modeResult
		end
	end

	return packed, true, {
		RawBytes = rawBytes,
		StoredBytes = storedBytes,
		SavedBytes = savedBytes,
		SavingsPercent = rawBytes > 0 and (savedBytes / rawBytes * 100) or 0,
		Mode = mode,
	}
end

local function prepareCompressionLayouts(config: ResolvedConfig): ()
	if config._CompressionLayoutsPrepared == true then
		return
	end

	config._CompressionLayoutsPrepared = true
	config._CompressionLayoutsByVersion = {}
	config._CompressionLayoutErrors = {}

	local codec = getCompression()

	local function addLayout(dataVersion: number?, template: any): ()
		if type(dataVersion) ~= "number"
			or dataVersion < 0
			or dataVersion ~= math.floor(dataVersion)
			or type(template) ~= "table" then
			return
		end

		if config._CompressionLayoutsByVersion[dataVersion] ~= nil then
			return
		end

		-- IndexedLayout requires a positive layout version. DataVersion itself may
		-- legally be 0, so the internal Compression schema version is +1.
		local layoutVersion = dataVersion + 1
		local ok, layout = pcall(codec.IndexedLayout, template, layoutVersion)
		if ok and type(layout) == "table" then
			config._CompressionLayoutsByVersion[dataVersion] = layout
		else
			config._CompressionLayoutErrors[dataVersion] = tostring(layout)
		end
	end

	addLayout(config.DataVersion or 1, config.Template or {})

	local history = config.CompressionLayoutHistory
	if history == nil then
		-- Reuse the existing SchemaHistory table as a migration convenience.
		history = config.SchemaHistory
	end

	if type(history) == "table" then
		for rawVersion, historical in pairs(history) do
			local dataVersion = if type(rawVersion) == "number" then rawVersion else tonumber(rawVersion)
			local template = historical
			if type(historical) == "table" and type(historical.Data) == "table" then
				template = historical.Data
			end
			addLayout(dataVersion, template)
		end
	end
end

local function getCompressionLayout(config: ResolvedConfig, dataVersion: number): IndexedLayoutObject?
	prepareCompressionLayouts(config)
	return config._CompressionLayoutsByVersion[dataVersion]
end

local function isCompressionStorageFrame(value: any): boolean
	return typeof(value) == "buffer"
		and buffer.len(value) >= 2
		and buffer.readu8(value, 0) == STORAGE_FRAME_MAGIC
end

local function buildCompressionStorageFrame(codecKind: number, dataVersion: number, payload: buffer, config: ResolvedConfig): (buffer, number)
	assert(typeof(payload) == "buffer", "Compression storage payload must be a buffer")

	local writer = Writer.new(8)
	writer:U8(STORAGE_FRAME_MAGIC)
	writer:U8(STORAGE_FORMAT_VERSION)
	writer:U8(codecKind)
	writer:VarUInt(dataVersion)
	local header = writer:Finish()

	local totalBytes = buffer.len(header) + buffer.len(payload)
	if totalBytes > config.MaxBufferBytes then
		error(string.format(
			"Encoded Compression storage frame is %d bytes, above MaxBufferBytes (%d)",
			totalBytes,
			config.MaxBufferBytes
			), 2)
	end

	local out = buffer.create(totalBytes)
	buffer.copy(out, 0, header, 0, buffer.len(header))
	if buffer.len(payload) > 0 then
		buffer.copy(out, buffer.len(header), payload, 0, buffer.len(payload))
	end

	return out, buffer.len(header)
end

local function parseCompressionStorageFrame(value: buffer, config: ResolvedConfig): (number?, number?, buffer?)
	if not isCompressionStorageFrame(value) then
		return nil
	end

	if buffer.len(value) > config.MaxBufferBytes then
		error("Compression storage frame exceeds MaxBufferBytes", 2)
	end

	local reader = Reader.new(value)
	if reader:U8() ~= STORAGE_FRAME_MAGIC then
		error("Compression storage frame magic mismatch", 2)
	end

	local formatVersion = reader:U8()
	if formatVersion ~= STORAGE_FORMAT_VERSION then
		error("Unsupported Compression storage frame version " .. tostring(formatVersion), 2)
	end

	local codecKind = reader:U8()
	if codecKind ~= STORAGE_CODEC_INDEXED and codecKind ~= STORAGE_CODEC_TABLE then
		error("Compression storage frame has unknown codec kind " .. tostring(codecKind), 2)
	end

	local dataVersion = reader:VarUInt()
	local payload = reader:RawBuffer(reader.Length - reader.Position)
	return codecKind, dataVersion, payload
end

local function compressStorageTable(dataTemplate: DataTemplate, config: ResolvedConfig): (buffer, StorageStats)
	validateSavable(dataTemplate, "DataTemplate", nil, 0, nil, config)

	local dataVersion = assert(dataTemplate.Version, "DataTemplate requires Version")
	local data = assert(dataTemplate.Data, "DataTemplate requires Data")
	local codec = getCompression()
	local options = tableCompressionOptions(config)

	prepareCompressionLayouts(config)

	-- Candidate A: self-describing adaptive Compression v3 table packet. This is
	-- always available and is the safe fallback for dynamic maps/extra fields.
	local adaptiveOptions = options
	if not config.CompressionEnabled then
		adaptiveOptions = table.clone(options)
		adaptiveOptions.TableCompression = false
		adaptiveOptions.EntropyCoding = false
	end

	local adaptivePacket: CompressionPacket
	if config.CompressionEnabled then
		adaptivePacket = codec.CompressTablePacket(data, adaptiveOptions)
	else
		adaptivePacket = codec.Encode(data, adaptiveOptions)
	end

	if type(adaptivePacket) ~= "table" or typeof(adaptivePacket.Data) ~= "buffer" then
		error("Compression v3 adaptive table encoder returned an invalid packet", 2)
	end

	local selectedPacket = adaptivePacket
	local selectedKind = STORAGE_CODEC_TABLE
	local selectedMode = type(adaptivePacket.Codec) == "string" and adaptivePacket.Codec or "CompressionTable"
	local indexedPacket: CompressionPacket? = nil
	local indexedError: string? = nil
	local layout: IndexedLayoutObject? = nil

	-- Candidate B: reusable IndexedLayout. For fixed DataTemplates this removes
	-- field names and lets Compression's inferred schema/default-elision encode
	-- values at bit granularity. If runtime data contains unknown fields the
	-- layout throws and we safely keep the adaptive candidate.
	if config.CompressionEnabled and config.CompressionIndexedLayout ~= false then
		layout = getCompressionLayout(config, dataVersion)
		if layout ~= nil then
			local ok, packetOrError = pcall(function(): CompressionPacket
				return layout:Encode(data, options)
			end)

			if ok
				and type(packetOrError) == "table"
				and typeof(packetOrError.Data) == "buffer" then
				local validIndexedPacket = packetOrError :: CompressionPacket
				indexedPacket = validIndexedPacket
				local indexedBytes = buffer.len(validIndexedPacket.Data)
				local adaptiveBytes = buffer.len(adaptivePacket.Data)

				if config.CompressionCompareAdaptiveTable == false
					or indexedBytes < adaptiveBytes then
					selectedPacket = validIndexedPacket
					selectedKind = STORAGE_CODEC_INDEXED
					selectedMode = type(validIndexedPacket.Codec) == "string"
						and validIndexedPacket.Codec
						or "IndexedLayout"
				end
			else
				indexedError = tostring(packetOrError)
				debugWarn(config, "IndexedLayout candidate unavailable; adaptive table codec selected:", indexedError)
			end
		end
	end

	local stored, headerBytes = buildCompressionStorageFrame(
		selectedKind,
		dataVersion,
		selectedPacket.Data,
		config
	)

	local storedBytes = buffer.len(stored)
	local selectedPayloadBytes = buffer.len(selectedPacket.Data)
	local rawBytes = selectedPacket.RawBytes
	if type(rawBytes) ~= "number" then
		rawBytes = adaptivePacket.RawBytes
	end
	if type(rawBytes) ~= "number" then
		rawBytes = selectedPayloadBytes
	end

	local savedBytes = math.max(0, rawBytes - storedBytes)
	local usefulBits = selectedPacket.UsefulBits or selectedPacket.Bits or (selectedPayloadBytes * 8)
	local physicalBits = storedBytes * 8
	local payloadPhysicalBits = selectedPacket.PhysicalBits or (selectedPayloadBytes * 8)
	local paddingBits = selectedPacket.PaddingBits or math.max(0, payloadPhysicalBits - usefulBits)

	local indexedBytes: number? = nil
	if indexedPacket ~= nil then
		indexedBytes = buffer.len(indexedPacket.Data) + headerBytes
	end
	local adaptiveBytes = buffer.len(adaptivePacket.Data) + headerBytes

	return stored, {
		RawBytes = rawBytes,
		StoredBytes = storedBytes,
		SavedBytes = savedBytes,
		SavingsPercent = rawBytes > 0 and (savedBytes / rawBytes * 100) or 0,
		Mode = "CompressionV3/" .. selectedMode,
		Codec = selectedMode,
		Compressed = config.CompressionEnabled == true,
		FrameBytes = headerBytes,
		PayloadBytes = selectedPayloadBytes,
		UsefulBits = usefulBits,
		PhysicalBits = physicalBits,
		PaddingBits = paddingBits,
		WorkingBufferBytes = selectedPayloadBytes,
		CompactedPayloadBytes = selectedPayloadBytes,
		UnusedWorkingBytesRemoved = 0,

		SchemaEligible = layout ~= nil,
		SchemaCandidateAvailable = indexedPacket ~= nil,
		SchemaSelected = selectedKind == STORAGE_CODEC_INDEXED,
		SchemaCandidateBytes = indexedBytes,
		SchemaCandidateMode = indexedPacket and (indexedPacket.Codec or "IndexedLayout") or nil,
		SchemaRawBytes = indexedPacket and indexedPacket.RawBytes or nil,
		SchemaRawBits = indexedPacket and indexedPacket.RawBytes and (indexedPacket.RawBytes * 8) or nil,
		SchemaUsefulBits = indexedPacket and (indexedPacket.UsefulBits or indexedPacket.Bits) or nil,
		SchemaPaddingBits = indexedPacket and indexedPacket.PaddingBits or nil,
		SchemaVarUIntMode = nil,
		SchemaFieldCount = layout and #layout.Keys or nil,
		SchemaPresentFields = nil,
		SchemaDefaultFieldsOmitted = nil,
		SchemaFingerprint = nil,
		SchemaWorkingBufferBytes = indexedPacket and buffer.len(indexedPacket.Data) or nil,
		SchemaCompactedPayloadBytes = indexedPacket and buffer.len(indexedPacket.Data) or nil,
		SchemaUnusedWorkingBytesRemoved = 0,

		AdaptiveCandidateBytes = adaptiveBytes,
		IndexedCandidateError = indexedError,
	}
end

local function decodeCompressionStorageFrame(value: buffer, config: ResolvedConfig): (DataTemplate?, string?)
	local codecKind, dataVersion, payload = parseCompressionStorageFrame(value, config)
	if codecKind == nil then
		return nil
	end

	local resolvedVersion = assert(dataVersion, "Compression storage frame missing DataVersion")
	local resolvedPayload = assert(payload, "Compression storage frame missing payload")
	local codec = getCompression()
	local options = tableCompressionOptions(config)
	local data: DataTable

	if codecKind == STORAGE_CODEC_INDEXED then
		local layout = getCompressionLayout(config, resolvedVersion)
		if layout == nil then
			error(
				"Indexed Compression save uses DataTemplate version " .. tostring(resolvedVersion)
					.. ", but no matching template exists in Config.CompressionLayoutHistory/SchemaHistory",
				2
			)
		end

		data = layout:Decode(resolvedPayload, options)
	else
		data = codec.DecompressTable(resolvedPayload, options)
	end

	if type(data) ~= "table" then
		error("Compression storage frame decoded a non-table Data value", 2)
	end

	validateSavable(data, "Data", nil, 0, nil, config)
	return {
		Version = resolvedVersion,
		Data = deepCopy(data),
	}, codecKind == STORAGE_CODEC_INDEXED and "CompressionV3Indexed" or "CompressionV3Table"
end

local function tryDecodeCompressionTable(storedPayload: buffer, config: ResolvedConfig): DataTable?
	local codec = getCompression()
	local ok, decoded = pcall(codec.DecompressTable, storedPayload, tableCompressionOptions(config))
	if not ok or type(decoded) ~= "table" then
		return nil
	end

	local valid = pcall(validateSavable, decoded, "DecodedDataTemplate", nil, 0, nil, config)
	if not valid then
		return nil
	end

	return decoded
end


local function decompressStorageBuffer(storedPayload: buffer, compressed: boolean, config: ResolvedConfig): buffer
	if not compressed then
		return cloneRawBuffer(storedPayload)
	end

	local codec = getCompression()
	local ok, rawPayload = pcall(codec.DecompressBuffer, storedPayload)
	if not ok then
		error("DataStore compressed BufferV1 payload failed to decompress: " .. tostring(rawPayload), 2)
	end
	if typeof(rawPayload) ~= "buffer" then
		error("DataStore Compression.DecompressBuffer returned a non-buffer value", 2)
	end
	if buffer.len(rawPayload) > config.MaxBufferBytes then
		error("DataStore decompressed BufferV1 payload exceeds MaxBufferBytes", 2)
	end
	return rawPayload
end


local function waitForBudget(config: ResolvedConfig, requestType: Enum.DataStoreRequestType): (boolean, string?)
	if not config.BudgetAware then
		return true
	end

	local deadline = os.clock() + config.BudgetWaitTimeout
	while DataStoreService:GetRequestBudgetForRequestType(requestType) <= 0 do
		if os.clock() >= deadline then
			return false, "DataStoreBudgetTimeout"
		end
		task.wait(0.25)
	end
	return true
end

local function retryAsync(config: ResolvedConfig, requestType: Enum.DataStoreRequestType, callback: () -> any): (boolean, any)
	local lastError: any = nil

	for attempt = 1, config.RetryAttempts do
		local budgetOk, budgetError = waitForBudget(config, requestType)
		if not budgetOk then
			lastError = budgetError
		else
			local ok, result = pcall(callback)
			if ok then
				return true, result
			end
			lastError = result
		end

		if attempt < config.RetryAttempts then
			local delayTime = math.min(config.RetryDelay * (2 ^ (attempt - 1)), config.MaxRetryDelay)
			delayTime += math.random() * 0.2
			task.wait(delayTime)
		end
	end

	return false, lastError
end

local function resolveUserId(subject: UserSubject): (number, Player?)
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		local player = subject :: Player
		return player.UserId, player
	end

	assert(type(subject) == "number" and subject > 0 and subject == math.floor(subject), "Expected a Player or positive integer UserId")
	return subject, Players:GetPlayerByUserId(subject)
end



local function makeDataTemplate(version: number, data: DataTable): DataTemplate
	return {
		Version = version,
		Data = deepCopy(data),
	}
end

local function mergeConfig(config: DataStoreConfig): ResolvedConfig
	local out = table.clone(DEFAULTS)

	for key, value in pairs(config) do
		out[key] = value
	end

	local suppliedTemplate = config.DataTemplate
	if type(suppliedTemplate) == "table" and type(suppliedTemplate.Data) == "table" then
		out.DataVersion = suppliedTemplate.Version
		out.Template = deepCopy(suppliedTemplate.Data)
		out.DataTemplate = {
			Version = suppliedTemplate.Version,
			Data = deepCopy(suppliedTemplate.Data),
		}
	elseif type(config.Template) == "table" then
		local version = config.DataVersion
		if version == nil then
			version = 1
		end
		out.DataVersion = version
		out.Template = deepCopy(config.Template)
		out.DataTemplate = {
			Version = version,
			Data = deepCopy(config.Template),
		}
	else
		out.DataTemplate = {
			Version = out.DataVersion or 1,
			Data = deepCopy(out.Template or {}),
		}
	end

	if config.BufferStorage ~= nil and config.StorageMode == nil then
		out.StorageMode = if config.BufferStorage then "Buffer" else "Table"
	end

	return out
end

local function retryMemoryAsync(config: ResolvedConfig, callback: () -> any): (boolean, any)
	local attempts = math.max(1, config.MemoryLockRetryAttempts or 4)
	local lastError: any = nil

	for attempt = 1, attempts do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end

		lastError = result

		if attempt < attempts then
			local delayTime = math.min(0.25 * (2 ^ (attempt - 1)), 2)
			delayTime += math.random() * 0.1
			task.wait(delayTime)
		end
	end

	return false, lastError
end

local function autoDecompressStorageBuffer(storedPayload: buffer, config: ResolvedConfig): buffer
	assert(typeof(storedPayload) == "buffer", "Stored payload must be a buffer")

	local codec = getCompression()
	local ok, rawPayload = pcall(codec.DecompressBuffer, storedPayload)
	if not ok then
		error("DataStore buffer failed to decompress: " .. tostring(rawPayload), 2)
	end

	if typeof(rawPayload) ~= "buffer" then
		error("Compression.DecompressBuffer returned a non-buffer value", 2)
	end

	if buffer.len(rawPayload) > config.MaxBufferBytes then
		error("DataStore decompressed payload exceeds MaxBufferBytes", 2)
	end

	return rawPayload
end

local function prepareStorage(data: DataTable, version: number, config: ResolvedConfig): PreparedStorage
	local dataTemplate = makeDataTemplate(version, data)

	if config.StorageMode == "Buffer" then
		local storedPayload, stats = compressStorageTable(dataTemplate, config)

		return {
			Value = storedPayload,
			RawBuffer = nil,
			Bytes = stats.StoredBytes,
			RawBytes = stats.RawBytes,
			SavedBytes = stats.SavedBytes,
			SavingsPercent = stats.SavingsPercent,
			Compressed = stats.Compressed == true,
			CompressionMode = stats.Mode,
			WorkingBufferBytes = stats.WorkingBufferBytes,
			CompactedPayloadBytes = stats.CompactedPayloadBytes,
			UnusedWorkingBytesRemoved = stats.UnusedWorkingBytesRemoved or 0,
			SchemaEligible = stats.SchemaEligible == true,
			SchemaCandidateAvailable = stats.SchemaCandidateAvailable == true,
			SchemaSelected = stats.SchemaSelected == true,
			SchemaCandidateBytes = stats.SchemaCandidateBytes,
			SchemaCandidateMode = stats.SchemaCandidateMode,
			SchemaRawBytes = stats.SchemaRawBytes,
			SchemaRawBits = stats.SchemaRawBits,
			SchemaUsefulBits = stats.SchemaUsefulBits,
			SchemaPaddingBits = stats.SchemaPaddingBits,
			SchemaVarUIntMode = stats.SchemaVarUIntMode,
			SchemaFieldCount = stats.SchemaFieldCount,
			SchemaPresentFields = stats.SchemaPresentFields,
			SchemaDefaultFieldsOmitted = stats.SchemaDefaultFieldsOmitted,
			SchemaFingerprint = stats.SchemaFingerprint,
			SchemaWorkingBufferBytes = stats.SchemaWorkingBufferBytes,
			SchemaCompactedPayloadBytes = stats.SchemaCompactedPayloadBytes,
			SchemaUnusedWorkingBytesRemoved = stats.SchemaUnusedWorkingBytesRemoved or 0,
		}
	end

	validateSavable(dataTemplate, "DataTemplate", nil, 0, nil, config)

	return {
		Value = deepCopy(dataTemplate),
		RawBuffer = nil,
		Bytes = nil,
		RawBytes = nil,
		SavedBytes = 0,
		SavingsPercent = 0,
		Compressed = false,
		CompressionMode = "None",
		WorkingBufferBytes = nil,
		CompactedPayloadBytes = nil,
		UnusedWorkingBytesRemoved = 0,
		SchemaEligible = false,
		SchemaCandidateAvailable = false,
		SchemaSelected = false,
		SchemaCandidateBytes = nil,
		SchemaCandidateMode = nil,
		SchemaRawBytes = nil,
		SchemaRawBits = nil,
		SchemaUsefulBits = nil,
		SchemaPaddingBits = nil,
		SchemaVarUIntMode = nil,
		SchemaFieldCount = nil,
		SchemaPresentFields = nil,
		SchemaDefaultFieldsOmitted = nil,
		SchemaFingerprint = nil,
		SchemaWorkingBufferBytes = nil,
		SchemaCompactedPayloadBytes = nil,
		SchemaUnusedWorkingBytesRemoved = 0,
	}
end

local function decodeLegacyRecord(record: DataTable, config: ResolvedConfig): (DataTemplate?, string?)
	local format = record[LEGACY_FORMAT_TAG]
	if format ~= LEGACY_FORMAT_V151 and format ~= LEGACY_FORMAT_V150 and format ~= LEGACY_FORMAT_V1 then
		return nil
	end

	local data: DataTable
	local savedVersion = config.DataVersion or 1

	if type(record.Meta) == "table" and type(record.Meta.DataVersion) == "number" then
		savedVersion = record.Meta.DataVersion
	end

	if record.Encoding == BUFFER_ENCODING and typeof(record.Payload) == "buffer" then
		local rawPayload: buffer
		if format == LEGACY_FORMAT_V151 and record.PayloadCompressed == true then
			rawPayload = autoDecompressStorageBuffer(record.Payload, config)
		else
			rawPayload = cloneRawBuffer(record.Payload)
		end
		data = decodeBuffer(rawPayload, config)
	elseif type(record.Data) == "table" then
		data = deepCopy(record.Data)
	else
		data = deepCopy(config.Template)
	end

	return {
		Version = savedVersion,
		Data = data,
	}, "LegacyRecord"
end

local function decodeStoredValue(value: any, config: ResolvedConfig): (DataTemplate, string)
	if value == nil then
		return deepCopy(config.DataTemplate), "New"
	end

	if typeof(value) == "buffer" then
		-- v2.0.0 native Compression v3 frame. The tiny DataStore envelope stores
		-- DataVersion + codec kind while Compression owns the actual table bits.
		if isCompressionStorageFrame(value) then
			local decoded, source = decodeCompressionStorageFrame(value, config)
			if decoded ~= nil then
				return decoded, source
			end
		end

		-- v1.8/v1.9 compatibility: try the old direct Compression table frame.
		-- table structure visible to the compressor and avoids double encoding.
		local compressedTable = tryDecodeCompressionTable(value, config)
		if compressedTable ~= nil then
			if type(compressedTable.Version) == "number" and type(compressedTable.Data) == "table" then
				return {
					Version = compressedTable.Version,
					Data = deepCopy(compressedTable.Data),
				}, "CompressionTableV267"
			end

			return {
				Version = config.DataVersion or 1,
				Data = deepCopy(compressedTable),
			}, "CompressionRawTableV267"
		end

		-- v1.6 and older: BufferV1/SDSB, optionally wrapped in CompressBuffer.
		-- Compression v3 keeps the passthrough behavior needed to unwrap old
		-- DataStore-owned frames without making them part of the new write path.
		local rawPayload = autoDecompressStorageBuffer(value, config)

		-- v1.9.0 SchemaBitBuffer v2 may be stored raw or wrapped by CompressBufferSmart.
		-- DecompressBuffer passes raw unknown frames through unchanged, so one path
		-- safely handles both forms.
		if SchemaCodec.isFrame(rawPayload) then
			local codecVersion = if buffer.len(rawPayload) >= 2 then buffer.readu8(rawPayload, 1) else 0
			local schemaTemplate = SchemaCodec.decode(rawPayload, config)
			if schemaTemplate ~= nil then
				return schemaTemplate, if codecVersion == SchemaCodec.VERSION then "SchemaBitBufferV2" else "SchemaBufferV1"
			end
		end

		local decoded = decodeBuffer(rawPayload, config)

		if type(decoded) ~= "table" then
			error("Decoded DataStore buffer must contain a table", 0)
		end

		if type(decoded.Version) == "number" and type(decoded.Data) == "table" then
			return {
				Version = decoded.Version,
				Data = deepCopy(decoded.Data),
			}, "DataTemplateBuffer"
		end

		return {
			Version = config.DataVersion or 1,
			Data = deepCopy(decoded),
		}, "LegacyRawBuffer"
	end

	if type(value) ~= "table" then
		error("Existing DataStore value has unsupported type " .. typeof(value), 0)
	end

	if value[LEGACY_FORMAT_TAG] ~= nil then
		local legacy, source = decodeLegacyRecord(value, config)
		if legacy ~= nil then
			return legacy, source
		end
	end

	if type(value.Version) == "number" and type(value.Data) == "table" then
		return {
			Version = value.Version,
			Data = deepCopy(value.Data),
		}, "DataTemplateTable"
	end

	return {
		Version = config.DataVersion or 1,
		Data = deepCopy(value),
	}, "LegacyRawTable"
end

local function applyMigrations(data: DataTable, savedVersion: number, config: ResolvedConfig): (DataTable, number)
	local targetVersion = config.DataVersion or 1

	if savedVersion > targetVersion and config.RejectFutureDataVersion then
		error(
			string.format(
				"Saved DataTemplate version %d is newer than configured version %d",
				savedVersion,
				targetVersion
			),
			0
		)
	end

	local currentVersion = savedVersion

	if currentVersion < targetVersion then
		for version = currentVersion + 1, targetVersion do
			if type(config.Migrations) == "table" then
				local migration = config.Migrations[version]
				if migration ~= nil then
					assert(type(migration) == "function", "Migration " .. tostring(version) .. " must be a function")
					local migrated = migration(data, version - 1, version)
					if migrated ~= nil then
						assert(type(migrated) == "table", "Migration must return a table or nil")
						data = migrated
					end
				end
			end

			currentVersion = version
		end
	end

	return data, targetVersion
end

function Profile._deactivate(self: ProfileObject, reason: string?): ()
	if not self._active then
		return
	end

	self._active = false
	self._releaseReason = reason or "Released"
	self.Store._profiles[self.UserId] = nil

	self.Released:Fire(self._releaseReason)
	self.Store.ProfileReleased:Fire(self, self._releaseReason)

	self.Changed:Destroy()
	self.Saved:Destroy()
	self.Released:Destroy()
end

function Profile._markChanged(self: ProfileObject): ()
	self._revision += 1
	self._dirty = true
end

function Profile.IsActive(self: ProfileObject): boolean
	return self._active
end

function Profile.IsDirty(self: ProfileObject): boolean
	return self._dirty
end

function Profile.Get(self: ProfileObject, key: any): any
	return self.Data[key]
end

function Profile.GetDataCopy(self: ProfileObject): DataTable
	return deepCopy(self.Data)
end

function Profile.GetDataTemplate(self: ProfileObject): DataTemplate
	return makeDataTemplate(self.Version, self.Data)
end

function Profile.GetBuffer(self: ProfileObject): buffer
	assert(self._active, "Cannot encode an inactive profile")
	local stored = compressStorageTable(self:GetDataTemplate(), self.Store.Config)
	return stored
end

Profile.ToBuffer = Profile.GetBuffer

function Profile.GetStorageInfo(self: ProfileObject): {[string]: any}
	local rawBytes = self._lastRawBufferBytes
	local storedBytes = self._lastBufferBytes
	local savedBytes = 0

	if type(rawBytes) == "number" and type(storedBytes) == "number" then
		savedBytes = math.max(0, rawBytes - storedBytes)
	end

	local keyInfo = self.Store:GetKeyInfo(self.UserId)

	return {
		Mode = self.Store.Config.StorageMode,
		Version = self.Version,
		PlayerKey = keyInfo.Key,
		PlayerKeyBytes = keyInfo.KeyBytes,
		LegacyPlayerKeyBytes = keyInfo.LegacyKeyBytes,
		PlayerKeySavedBytes = keyInfo.SavedBytes,
		PlayerKeySavingsPercent = keyInfo.SavingsPercent,
		CompactPlayerKeys = keyInfo.Compact,
		KeyMigrationPending = self._legacyKeyToDelete ~= nil,
		LastBufferBytes = storedBytes,
		LastRawBufferBytes = rawBytes,
		LastCompressionSavedBytes = savedBytes,
		LastCompressionSavingsPercent = if type(rawBytes) == "number" and rawBytes > 0
			then savedBytes / rawBytes * 100
			else 0,
		LastBufferCompressed = self._lastBufferCompressed == true,
		LastCompressionMode = self._lastCompressionMode,
		BufferUtilEnabled = false,
		BufferUtilVersion = "Removed",
		LastWorkingBufferBytes = self._lastWorkingBufferBytes,
		LastCompactedPayloadBytes = self._lastCompactedPayloadBytes,
		LastUnusedWorkingBytesRemoved = self._lastUnusedWorkingBytesRemoved or 0,
		LegacySchemaBufferDecodeEnabled = self.Store.Config.SchemaBufferEnabled == true,
		LegacySchemaFormatVersion = SchemaCodec.VERSION,
		CompressionIndexedLayoutEnabled = self.Store.Config.CompressionIndexedLayout == true,
		IndexedLayoutAvailable = self.Store.Config._CompressionLayoutsByVersion ~= nil
			and self.Store.Config._CompressionLayoutsByVersion[self.Version] ~= nil,
		IndexedCandidateAvailable = self._lastSchemaCandidateAvailable == true,
		IndexedSelected = self._lastSchemaSelected == true,
		LastIndexedCandidateBytes = self._lastSchemaCandidateBytes,
		LastIndexedCandidateMode = self._lastSchemaCandidateMode,
		-- v1.9-compatible aliases:
		SchemaEligible = self.Store.Config._CompressionLayoutsByVersion ~= nil
			and self.Store.Config._CompressionLayoutsByVersion[self.Version] ~= nil,
		SchemaCandidateAvailable = self._lastSchemaCandidateAvailable == true,
		SchemaSelected = self._lastSchemaSelected == true,
		LastSchemaCandidateBytes = self._lastSchemaCandidateBytes,
		LastSchemaCandidateMode = self._lastSchemaCandidateMode,
		LastSchemaRawBytes = self._lastSchemaRawBytes,
		LastSchemaRawBits = self._lastSchemaRawBits,
		LastSchemaUsefulBits = self._lastSchemaUsefulBits,
		LastSchemaPaddingBits = self._lastSchemaPaddingBits,
		LastSchemaVarUIntMode = self._lastSchemaVarUIntMode,
		SchemaFieldCount = self._lastSchemaFieldCount,
		LastSchemaPresentFields = self._lastSchemaPresentFields,
		LastSchemaDefaultFieldsOmitted = self._lastSchemaDefaultFieldsOmitted,
		SchemaFingerprint = self._lastSchemaFingerprint,
		LastSchemaWorkingBufferBytes = self._lastSchemaWorkingBufferBytes,
		LastSchemaCompactedPayloadBytes = self._lastSchemaCompactedPayloadBytes,
		LastSchemaUnusedWorkingBytesRemoved = self._lastSchemaUnusedWorkingBytesRemoved or 0,
		CompressionEnabled = self.Store.Config.CompressionEnabled,
		CompressionVersion = DataStore.CompressionVersion(),
		StorageFormatVersion = STORAGE_FORMAT_VERSION,
		DataStoreValueContainsOnlyDataTemplate = false,
		DataStoreValueContainsOnlyPlayerData = true,
		SessionLockStorage = if self.Store.Config.SessionLocking
			then (self.Store.Config.SessionCompressionEnabled and "MemoryStore/CompressionV3Indexed" or "MemoryStore/Table")
			else "Disabled",
		SessionLockFormatVersion = SESSION_FORMAT_VERSION,
		SessionCompressionEnabled = self.Store.Config.SessionCompressionEnabled == true,
		SessionStoreDiagnostics = self.Store.Config.SessionStoreDiagnostics == true,
		LastSessionLockBytes = self._lastSessionLockBytes,
		LastSessionRawBytes = self._lastSessionRawBytes,
		LastSessionCompressed = self._lastSessionCompressed == true,
		LastSessionCompressionMode = self._lastSessionCompressionMode,
		LastSessionWorkingBufferBytes = self._lastSessionWorkingBufferBytes,
		LastSessionCompactedPayloadBytes = self._lastSessionCompactedPayloadBytes,
		LastSessionUnusedWorkingBytesRemoved = self._lastSessionUnusedWorkingBytesRemoved or 0,
		Dirty = self._dirty,
		Revision = self._revision,
		LastSavedRevision = self._lastSavedRevision,
		LastSaveClock = self._lastSave,
	}
end

function Profile.MarkDirty(self: ProfileObject): ()
	assert(self._active, "Cannot modify an inactive profile")
	self:_markChanged()
end

function Profile.Set(self: ProfileObject, key: any, value: any): any
	assert(self._active, "Cannot modify an inactive profile")

	local oldValue = self.Data[key]
	self.Data[key] = value

	local ok, err = pcall(validateSavable, self.Data, "Data", nil, 0, nil, self.Store.Config)
	if not ok then
		self.Data[key] = oldValue
		error(err, 2)
	end

	self:_markChanged()
	self.Changed:Fire(key, value, oldValue)
	return value
end

function Profile.Update(self: ProfileObject, key: any, callback: (any) -> any): any
	assert(self._active, "Cannot modify an inactive profile")
	assert(type(callback) == "function", "Profile:Update expects a function")

	local backup = deepCopy(self.Data)
	local oldValue = self.Data[key]
	local okCallback, newValue = pcall(callback, oldValue)

	if not okCallback then
		self.Data = backup
		error(newValue, 2)
	end

	self.Data[key] = newValue

	local ok, err = pcall(validateSavable, self.Data, "Data", nil, 0, nil, self.Store.Config)
	if not ok then
		self.Data = backup
		error(err, 2)
	end

	self:_markChanged()
	self.Changed:Fire(key, newValue, oldValue)
	return newValue
end

function Profile.Increment(self: ProfileObject, key: any, amount: number?): number
	amount = amount or 1
	assert(type(amount) == "number" and isFiniteNumber(amount), "Profile:Increment amount must be a finite number")

	return self:Update(key, function(value: any): any
		value = value or 0
		assert(type(value) == "number" and isFiniteNumber(value), "Profile:Increment target must be a finite number")
		return value + amount
	end)
end

function Profile.Overwrite(self: ProfileObject, data: DataTable): DataTable
	assert(self._active, "Cannot modify an inactive profile")
	assert(type(data) == "table", "Profile:Overwrite expects a table")

	validateSavable(data, "Data", nil, 0, nil, self.Store.Config)

	local oldData = self.Data
	self.Data = deepCopy(data)

	self:_markChanged()
	self.Changed:Fire(nil, self.Data, oldData)
	return self.Data
end

function Profile.Reconcile(self: ProfileObject): DataTable
	assert(self._active, "Cannot reconcile an inactive profile")

	local before = deepCopy(self.Data)
	reconcile(self.Data, self.Store.Config.Template)
	validateSavable(self.Data, "Data", nil, 0, nil, self.Store.Config)

	self:_markChanged()
	self.Changed:Fire(nil, self.Data, before)
	return self.Data
end

function Profile._waitForOperation(self: ProfileObject): boolean
	while self._saving do
		if not self._active then
			return false
		end
		task.wait()
	end

	return self._active
end

function Profile._snapshotForSave(self: ProfileObject): (DataTable, PreparedStorage, number)
	validateSavable(self.Data, "Data", nil, 0, nil, self.Store.Config)

	local snapshot = deepCopy(self.Data)
	local prepared = prepareStorage(snapshot, self.Version, self.Store.Config)

	return snapshot, prepared, self._revision
end

local function guidHex(value: any): string?
	if type(value) ~= "string" then
		return nil
	end

	local compact = string.gsub(value, "-", "")
	if #compact ~= 32 or string.find(compact, "[^0-9a-fA-F]") ~= nil then
		return nil
	end

	return string.lower(compact)
end

local function guidToBuffer(value: any): buffer?
	local compact = guidHex(value)
	if compact == nil then
		return nil
	end

	local out = buffer.create(16)
	for i = 1, 16 do
		local byteText = string.sub(compact, (i - 1) * 2 + 1, i * 2)
		buffer.writeu8(out, i - 1, assert(tonumber(byteText, 16)))
	end
	return out
end

local function bufferToGuid(value: any): string?
	if typeof(value) ~= "buffer" or buffer.len(value) ~= 16 then
		return nil
	end

	local parts: {string} = table.create(16)
	for i = 0, 15 do
		parts[i + 1] = string.format("%02x", buffer.readu8(value, i))
	end

	local compact = table.concat(parts)
	return string.sub(compact, 1, 8)
		.. "-" .. string.sub(compact, 9, 12)
		.. "-" .. string.sub(compact, 13, 16)
		.. "-" .. string.sub(compact, 17, 20)
		.. "-" .. string.sub(compact, 21, 32)
end

local function writeGuidOrString(writer: WriterObject, value: string): boolean
	local compact = guidHex(value)
	if compact == nil then
		writer:VarUInt(#value)
		writer:RawString(value)
		return false
	end

	for i = 1, 32, 2 do
		local byte = assert(tonumber(string.sub(compact, i, i + 1), 16))
		writer:U8(byte)
	end
	return true
end

local function readGuid(reader: ReaderObject): string
	local parts: {string} = table.create(16)
	for i = 1, 16 do
		parts[i] = string.format("%02x", reader:U8())
	end
	local compact = table.concat(parts)
	return string.sub(compact, 1, 8)
		.. "-" .. string.sub(compact, 9, 12)
		.. "-" .. string.sub(compact, 13, 16)
		.. "-" .. string.sub(compact, 17, 20)
		.. "-" .. string.sub(compact, 21, 32)
end

local function readGuidOrString(reader: ReaderObject, isGuid: boolean): string
	if isGuid then
		return readGuid(reader)
	end
	return reader:RawString(reader:VarUInt())
end

local function sessionIdsEqual(a: string?, b: string?): boolean
	if a == b then
		return true
	end
	local ah = guidHex(a)
	local bh = guidHex(b)
	return ah ~= nil and bh ~= nil and ah == bh
end

local function makeSessionRaw(session: SessionLock, config: ResolvedConfig): (buffer, CompactionInfo)
	local id = assert(session.Id, "Session lock requires Id")
	local released = session.Released == true
	local diagnostics = not released and config.SessionStoreDiagnostics == true
	local idGuid = guidHex(id) ~= nil
	local jobId = diagnostics and tostring(session.JobId or "") or ""
	local jobGuid = diagnostics and guidHex(jobId) ~= nil

	local flags = 0
	if released then flags = bit32.bor(flags, SESSION_FLAG_RELEASED) end
	if idGuid then flags = bit32.bor(flags, SESSION_FLAG_ID_GUID) end
	if jobGuid then flags = bit32.bor(flags, SESSION_FLAG_JOB_GUID) end
	if diagnostics then flags = bit32.bor(flags, SESSION_FLAG_DIAGNOSTICS) end

	local writer = Writer.new(config.BufferWriterInitialCapacity or 32)
	writer:U8(SESSION_MAGIC)
	writer:U8(LEGACY_SESSION_FORMAT_VERSION)
	writer:U8(flags)
	writeGuidOrString(writer, id)

	if diagnostics then
		writeGuidOrString(writer, jobId)
		writer:VarUInt(session.PlaceId or 0)
		writer:VarUInt(session.TouchedAt or os.time())
	end

	local raw = writer:Finish()
	return raw, writer:GetCompactionInfo()
end

local function decodeSessionRaw(raw: buffer): SessionLock
	assert(typeof(raw) == "buffer", "Session lock decode expects buffer")
	local reader = Reader.new(raw)
	if reader.Length < 3 then
		error("Session lock buffer is too small", 2)
	end
	if reader:U8() ~= SESSION_MAGIC then
		error("Session lock buffer has invalid magic", 2)
	end

	local version = reader:U8()
	if version ~= LEGACY_SESSION_FORMAT_VERSION then
		error("Unsupported legacy session lock format version " .. tostring(version), 2)
	end

	local flags = reader:U8()
	local released = bit32.band(flags, SESSION_FLAG_RELEASED) ~= 0
	local idGuid = bit32.band(flags, SESSION_FLAG_ID_GUID) ~= 0
	local diagnostics = bit32.band(flags, SESSION_FLAG_DIAGNOSTICS) ~= 0
	local jobGuid = bit32.band(flags, SESSION_FLAG_JOB_GUID) ~= 0

	local session: SessionLock = {
		Id = readGuidOrString(reader, idGuid),
	}

	if released then
		session.Released = true
	elseif diagnostics then
		session.JobId = readGuidOrString(reader, jobGuid)
		session.PlaceId = reader:VarUInt()
		session.TouchedAt = reader:VarUInt()
	end

	if reader.Position ~= reader.Length then
		error("Session lock buffer contains trailing bytes", 2)
	end

	return session
end

local function getSessionCompressionLayout(config: ResolvedConfig): IndexedLayoutObject
	local cachedLayout = config._SessionCompressionLayout
	if cachedLayout ~= nil then
		return cachedLayout
	end

	local codec = getCompression()
	local layout = codec.IndexedLayout(SESSION_TEMPLATE, SESSION_LAYOUT_VERSION)
	config._SessionCompressionLayout = layout
	return layout
end

local function sessionAsTable(session: SessionLock, config: ResolvedConfig): DataTable
	local released = session.Released == true
	local diagnostics = not released and config.SessionStoreDiagnostics == true

	return {
		Id = tostring(assert(session.Id, "Session lock requires Id")),
		JobId = diagnostics and tostring(session.JobId or "") or "",
		PlaceId = diagnostics and (session.PlaceId or 0) or 0,
		TouchedAt = diagnostics and (session.TouchedAt or os.time()) or 0,
		Released = released,
	}
end

local function normalizeSessionForCompression(session: SessionLock, config: ResolvedConfig): DataTable
	local plain = sessionAsTable(session, config)
	local idBuffer = guidToBuffer(plain.Id)
	if idBuffer == nil then
		error("Compression v3 session locking requires a GUID session Id", 2)
	end

	plain.Id = idBuffer
	return plain
end

local function cleanDecodedSession(session: DataTable, config: ResolvedConfig): SessionLock?
	if type(session) ~= "table" then
		return nil
	end

	local id: string?
	if type(session.Id) == "string" then
		id = session.Id
	elseif typeof(session.Id) == "buffer" then
		id = bufferToGuid(session.Id)
	end
	if id == nil then
		return nil
	end

	local out: SessionLock = {
		Id = id,
	}

	if session.Released == true then
		out.Released = true
	elseif config.SessionStoreDiagnostics == true then
		out.JobId = type(session.JobId) == "string" and session.JobId or ""
		out.PlaceId = type(session.PlaceId) == "number" and session.PlaceId or 0
		out.TouchedAt = type(session.TouchedAt) == "number" and session.TouchedAt or 0
	end

	return out
end

local function encodeSessionLock(session: SessionLock, config: ResolvedConfig): (any, SessionStats)
	if not config.SessionCompressionEnabled then
		local plain = sessionAsTable(session, config)
		return deepCopy(plain), {
			RawBytes = nil,
			StoredBytes = nil,
			SavedBytes = 0,
			SavingsPercent = 0,
			Compressed = false,
			Mode = "Table",
			Format = SESSION_FORMAT_VERSION,
			WorkingBufferBytes = nil,
			CompactedPayloadBytes = nil,
			UnusedWorkingBytesRemoved = 0,
		}
	end

	local normalized = normalizeSessionForCompression(session, config)
	local layout = getSessionCompressionLayout(config)
	local packet = layout:Encode(normalized, tableCompressionOptions(config))
	if type(packet) ~= "table" or typeof(packet.Data) ~= "buffer" then
		error("Compression v3 session layout returned an invalid packet", 2)
	end

	local storedBytes = buffer.len(packet.Data)
	local rawBytes = type(packet.RawBytes) == "number" and packet.RawBytes or storedBytes
	local savedBytes = math.max(0, rawBytes - storedBytes)

	return packet.Data, {
		RawBytes = rawBytes,
		StoredBytes = storedBytes,
		SavedBytes = savedBytes,
		SavingsPercent = rawBytes > 0 and savedBytes / rawBytes * 100 or 0,
		Compressed = true,
		Mode = "CompressionV3/" .. tostring(packet.Codec or "IndexedSchema"),
		Format = SESSION_FORMAT_VERSION,
		WorkingBufferBytes = storedBytes,
		CompactedPayloadBytes = storedBytes,
		UnusedWorkingBytesRemoved = 0,
		UsefulBits = packet.UsefulBits or packet.Bits,
		PhysicalBits = packet.PhysicalBits or storedBytes * 8,
		PaddingBits = packet.PaddingBits,
	}
end

local function decodeSessionLock(value: any, config: ResolvedConfig): (SessionLock?, string)
	if value == nil then
		return nil, "Empty"
	end

	-- v1.7.1 and older, plus SessionCompressionEnabled=false in v2.0.0.
	if type(value) == "table" then
		local session = cleanDecodedSession(value, config)
		if session == nil then
			return nil, "Session lock table is missing Id"
		end
		return session, "Table"
	end

	if typeof(value) ~= "buffer" then
		return nil, "Unsupported session lock type " .. typeof(value)
	end

	-- v2.0.0: Compression v3 owns the entire session table representation.
	local layout = getSessionCompressionLayout(config)
	local okNew, decodedNew = pcall(function(): DataTable
		return layout:Decode(value, tableCompressionOptions(config))
	end)
	if okNew then
		local session = cleanDecodedSession(decodedNew, config)
		if session ~= nil then
			return session, "CompressionV3Indexed"
		end
	end

	-- Rollout compatibility for v1.9 CompactBufferV1 session locks.
	local codec = getCompression()
	local okDecompress, raw = pcall(codec.DecompressBuffer, value)
	if not okDecompress or typeof(raw) ~= "buffer" then
		return nil, "Session lock decompression failed: " .. tostring(raw)
	end

	local okDecode, session = pcall(decodeSessionRaw, raw)
	if not okDecode then
		return nil, tostring(session)
	end

	return session, "CompactBufferV1"
end

function DataStore._lockKey(self: StoreObject, userId: number): string
	return tostring(userId)
end

function DataStore._makeLockValue(self: StoreObject, sessionId: string, released: boolean): (any, SessionStats)
	return encodeSessionLock({
		Id = sessionId,
		JobId = game.JobId,
		PlaceId = game.PlaceId,
		TouchedAt = os.time(),
		Released = released == true,
	}, self.Config)
end

function DataStore._acquireSessionLock(self: StoreObject, userId: number, sessionId: string, mode: LockMode): (boolean, any?, SessionStats?)
	if not self.Config.SessionLocking then
		return true, nil, nil
	end

	local key = self:_lockKey(userId)
	local claimed = false
	local observed: any = nil
	local writeStats: SessionStats? = nil

	local ok, result = retryMemoryAsync(self.Config, function(): any
		return self._lockMap:UpdateAsync(key, function(current: any): any
			local currentSession, decodeError = decodeSessionLock(current, self.Config)
			if current ~= nil and currentSession == nil then
				observed = { Corrupt = true, Error = decodeError }
			else
				observed = currentSession and deepCopy(currentSession) or nil
			end

			local available = current == nil
				or (currentSession ~= nil and currentSession.Released == true)
				or (currentSession ~= nil and sessionIdsEqual(currentSession.Id, sessionId))

			if available or mode == "Steal" then
				claimed = true
				local packed: any
				packed, writeStats = self:_makeLockValue(sessionId, false)
				return packed
			end

			claimed = false
			return nil
		end, self.Config.SessionLockTimeout)
	end)

	if not ok then
		return false, result, nil
	end

	local resultSession = decodeSessionLock(result, self.Config)
	if claimed and resultSession ~= nil and sessionIdsEqual(resultSession.Id, sessionId) then
		return true, nil, writeStats
	end

	return false, observed or result, nil
end

function DataStore._refreshSessionLock(self: StoreObject, profile: ProfileObject): (boolean, any?)
	if not self.Config.SessionLocking then
		return true
	end

	local key = self:_lockKey(profile.UserId)
	local refreshed = false
	local writeStats: SessionStats? = nil

	local ok, result = retryMemoryAsync(self.Config, function(): any
		return self._lockMap:UpdateAsync(key, function(current: any): any
			local currentSession = decodeSessionLock(current, self.Config)
			if currentSession ~= nil and sessionIdsEqual(currentSession.Id, profile.SessionId) then
				refreshed = true
				local packed: any
				packed, writeStats = self:_makeLockValue(profile.SessionId, false)
				return packed
			end

			refreshed = false
			return nil
		end, self.Config.SessionLockTimeout)
	end)

	if not ok then
		return false, result
	end

	local resultSession = decodeSessionLock(result, self.Config)
	if refreshed and resultSession ~= nil and sessionIdsEqual(resultSession.Id, profile.SessionId) then
		if writeStats then
			profile._lastSessionLockBytes = writeStats.StoredBytes
			profile._lastSessionRawBytes = writeStats.RawBytes
			profile._lastSessionCompressed = writeStats.Compressed == true
			profile._lastSessionCompressionMode = writeStats.Mode
			profile._lastSessionWorkingBufferBytes = writeStats.WorkingBufferBytes
			profile._lastSessionCompactedPayloadBytes = writeStats.CompactedPayloadBytes
			profile._lastSessionUnusedWorkingBytesRemoved = writeStats.UnusedWorkingBytesRemoved or 0
		end
		return true
	end

	return false, "SessionLost"
end

function DataStore._releaseSessionLock(self: StoreObject, profile: ProfileObject | {UserId: number, SessionId: string}): (boolean, any?)
	if not self.Config.SessionLocking then
		return true
	end

	local key = self:_lockKey(profile.UserId)
	local released = false

	local ok, result = retryMemoryAsync(self.Config, function(): any
		return self._lockMap:UpdateAsync(key, function(current: any): any
			local currentSession = decodeSessionLock(current, self.Config)
			if currentSession ~= nil and sessionIdsEqual(currentSession.Id, profile.SessionId) then
				released = true
				local packed = self:_makeLockValue(profile.SessionId, true)
				return packed
			end

			released = false
			return nil
		end, 1)
	end)

	if not ok then
		return false, result
	end

	return released or result == nil
end

function Profile.SaveAsync(self: ProfileObject): (boolean, any?)
	if not self._active then
		return false, "ProfileInactive"
	end

	if not self:_waitForOperation() then
		return false, "ProfileInactive"
	end

	self._saving = true

	local lockOk, lockError = self.Store:_refreshSessionLock(self)
	if not lockOk then
		self._saving = false
		self:_deactivate("SessionLost")
		self.Store.Issue:Fire("SessionLost", self, lockError)
		return false, "SessionLost"
	end

	local okSnapshot, snapshot, prepared, revision = pcall(function(): (DataTable, PreparedStorage, number)
		local data, storage, currentRevision = self:_snapshotForSave()
		return data, storage, currentRevision
	end)

	if not okSnapshot then
		self._saving = false
		return false, snapshot
	end

	local ok, result = retryAsync(self.Store.Config, Enum.DataStoreRequestType.SetIncrementAsync, function(): any
		return self.Store._store:SetAsync(self.Key, prepared.Value)
	end)

	if not ok then
		self._saving = false
		debugWarn(self.Store.Config, "Save failed for", self.Key, result)
		self.Store.Issue:Fire("SaveFailed", self, result)
		return false, result
	end

	-- v1.9.0: only remove the old player key after the compact-key write succeeds.
	-- A failed cleanup is non-destructive; the compact copy is already durable and
	-- the old key is retried on a later save instead of risking data loss.
	if self._legacyKeyToDelete ~= nil then
		local legacyKey = self._legacyKeyToDelete
		local cleanupOk, cleanupError = retryAsync(self.Store.Config, Enum.DataStoreRequestType.SetIncrementAsync, function(): any
			return self.Store._store:RemoveAsync(legacyKey)
		end)
		if cleanupOk then
			self._legacyKeyToDelete = nil
			self.MetaData.KeyMigrated = true
		else
			debugWarn(self.Store.Config, "Legacy player-key cleanup failed for", legacyKey, cleanupError)
			self.Store.Issue:Fire("LegacyKeyCleanupFailed", self, legacyKey, cleanupError)
		end
	end

	self._lastSave = os.clock()
	self._lastBufferBytes = prepared.Bytes
	self._lastRawBufferBytes = prepared.RawBytes
	self._lastBufferCompressed = prepared.Compressed == true
	self._lastCompressionMode = prepared.CompressionMode
	self._lastWorkingBufferBytes = prepared.WorkingBufferBytes
	self._lastCompactedPayloadBytes = prepared.CompactedPayloadBytes
	self._lastUnusedWorkingBytesRemoved = prepared.UnusedWorkingBytesRemoved or 0
	self._lastSchemaEligible = prepared.SchemaEligible == true
	self._lastSchemaCandidateAvailable = prepared.SchemaCandidateAvailable == true
	self._lastSchemaSelected = prepared.SchemaSelected == true
	self._lastSchemaCandidateBytes = prepared.SchemaCandidateBytes
	self._lastSchemaCandidateMode = prepared.SchemaCandidateMode
	self._lastSchemaRawBytes = prepared.SchemaRawBytes
	self._lastSchemaRawBits = prepared.SchemaRawBits
	self._lastSchemaUsefulBits = prepared.SchemaUsefulBits
	self._lastSchemaPaddingBits = prepared.SchemaPaddingBits
	self._lastSchemaVarUIntMode = prepared.SchemaVarUIntMode
	self._lastSchemaFieldCount = prepared.SchemaFieldCount
	self._lastSchemaPresentFields = prepared.SchemaPresentFields
	self._lastSchemaDefaultFieldsOmitted = prepared.SchemaDefaultFieldsOmitted
	self._lastSchemaFingerprint = prepared.SchemaFingerprint
	self._lastSchemaWorkingBufferBytes = prepared.SchemaWorkingBufferBytes
	self._lastSchemaCompactedPayloadBytes = prepared.SchemaCompactedPayloadBytes
	self._lastSchemaUnusedWorkingBytesRemoved = prepared.SchemaUnusedWorkingBytesRemoved or 0
	self._lastSavedRevision = revision

	if self._revision == revision then
		self._dirty = false
	end

	self._saving = false
	self.Saved:Fire(self:GetStorageInfo())
	return true
end

function Profile.ReleaseAsync(self: ProfileObject, reason: string?): (boolean, any?)
	if not self._active then
		return true
	end

	if not self:_waitForOperation() then
		return true
	end

	local saved, saveError = self:SaveAsync()
	if not saved then
		return false, saveError
	end

	local releasedLock, releaseError = self.Store:_releaseSessionLock(self)
	if not releasedLock then
		debugWarn(self.Store.Config, "MemoryStore session lock release failed for", self.Key, releaseError)
	end

	self:_deactivate(reason or "Released")
	return true
end

function DataStore.new(config: DataStoreConfig): StoreObject
	assert(RunService:IsServer(), "DataStore can only be used from the server")
	assert(type(config) == "table", "DataStore.new expects a config table")
	assert(type(config.Name) == "string" and #config.Name > 0, "DataStore.new requires Config.Name")

	local merged = mergeConfig(config)

	assert(type(merged.DataTemplate) == "table", "Config.DataTemplate must be a table")
	assert(type(merged.DataTemplate.Data) == "table", "Config.DataTemplate.Data must be a table")
	assert(type(merged.DataVersion) == "number" and merged.DataVersion >= 0 and merged.DataVersion == math.floor(merged.DataVersion), "DataTemplate.Version must be a non-negative integer")
	assert(type(merged.KeyPrefix) == "string", "Config.KeyPrefix must be a string")
	assert(type(merged.CompactPlayerKeys) == "boolean", "Config.CompactPlayerKeys must be a boolean")
	assert(type(merged.CompactKeyPrefix) == "string", "Config.CompactKeyPrefix must be a string")
	assert(type(merged.MigrateLegacyPlayerKeys) == "boolean", "Config.MigrateLegacyPlayerKeys must be a boolean")
	assert(type(merged.DeleteLegacyPlayerKeys) == "boolean", "Config.DeleteLegacyPlayerKeys must be a boolean")
	assert(#merged.CompactKeyPrefix <= 16, "Config.CompactKeyPrefix must be at most 16 bytes")
	assert(merged.StorageMode == "Buffer" or merged.StorageMode == "Table", "Config.StorageMode must be Buffer or Table")
	assert(type(merged.CompressionEnabled) == "boolean", "Config.CompressionEnabled must be a boolean")
	assert(type(merged.BufferUtilEnabled) == "boolean", "Config.BufferUtilEnabled must be a boolean compatibility flag")
	assert(type(merged.BufferWriterInitialCapacity) == "number" and merged.BufferWriterInitialCapacity >= 1 and merged.BufferWriterInitialCapacity == math.floor(merged.BufferWriterInitialCapacity), "Config.BufferWriterInitialCapacity must be a positive integer")
	assert(type(merged.SchemaBufferEnabled) == "boolean", "Config.SchemaBufferEnabled must be a boolean")
	assert(type(merged.SchemaBufferCompress) == "boolean", "Config.SchemaBufferCompress must be a boolean")
	assert(type(merged.SchemaFallbackToGeneric) == "boolean", "Config.SchemaFallbackToGeneric must be a boolean")
	assert(merged.SchemaHistory == nil or type(merged.SchemaHistory) == "table", "Config.SchemaHistory must be nil or a table keyed by DataTemplate version")
	assert(type(merged.CompressionIndexedLayout) == "boolean", "Config.CompressionIndexedLayout must be a boolean")
	assert(type(merged.CompressionCompareAdaptiveTable) == "boolean", "Config.CompressionCompareAdaptiveTable must be a boolean")
	assert(merged.CompressionLayoutHistory == nil or type(merged.CompressionLayoutHistory) == "table", "Config.CompressionLayoutHistory must be nil or a table keyed by DataTemplate version")
	assert(
		merged.CompressionTableStrategy == "Auto"
			or merged.CompressionTableStrategy == "Compact"
			or merged.CompressionTableStrategy == "Dynamic",
		"Config.CompressionTableStrategy is invalid"
	)
	assert(
		merged.CompressionStringStrategy == "Auto"
			or merged.CompressionStringStrategy == "Raw"
			or merged.CompressionStringStrategy == "LZ"
			or merged.CompressionStringStrategy == "ASCII7"
			or merged.CompressionStringStrategy == "LowASCII5"
			or merged.CompressionStringStrategy == "Identifier6"
			or merged.CompressionStringStrategy == "Numeric4",
		"Config.CompressionStringStrategy is invalid"
	)
	assert(
		merged.CompressionEntropyStrategy == "Auto"
			or merged.CompressionEntropyStrategy == "Huffman"
			or merged.CompressionEntropyStrategy == "None",
		"Config.CompressionEntropyStrategy is invalid"
	)
	assert(type(merged.CompressionCompareLegacyBuffer) == "boolean", "Config.CompressionCompareLegacyBuffer must be a boolean")
	assert(type(merged.CompressionMinBufferBytes) == "number" and merged.CompressionMinBufferBytes >= 0, "Config.CompressionMinBufferBytes must be >= 0")
	assert(type(merged.CompressionMinSavingsBytes) == "number" and merged.CompressionMinSavingsBytes >= 1, "Config.CompressionMinSavingsBytes must be >= 1")
	assert(
		merged.CompressionBufferStrategy == "Auto"
			or merged.CompressionBufferStrategy == "Raw"
			or merged.CompressionBufferStrategy == "LZ"
			or merged.CompressionBufferStrategy == "Sparse"
			or merged.CompressionBufferStrategy == "Nibble",
		"Config.CompressionBufferStrategy is invalid"
	)
	assert(type(merged.AutoSaveInterval) == "number" and merged.AutoSaveInterval >= 10, "Config.AutoSaveInterval must be at least 10 seconds")
	assert(type(merged.SessionLocking) == "boolean", "Config.SessionLocking must be a boolean")
	assert(type(merged.SessionCompressionEnabled) == "boolean", "Config.SessionCompressionEnabled must be a boolean")
	assert(type(merged.SessionStoreDiagnostics) == "boolean", "Config.SessionStoreDiagnostics must be a boolean")
	assert(type(merged.SessionLockTimeout) == "number" and merged.SessionLockTimeout >= merged.AutoSaveInterval * 2, "SessionLockTimeout must be at least 2x AutoSaveInterval")
	assert(type(merged.LoadTimeout) == "number" and merged.LoadTimeout > 0, "Config.LoadTimeout must be > 0")
	assert(type(merged.RetryAttempts) == "number" and merged.RetryAttempts >= 1, "Config.RetryAttempts must be >= 1")
	assert(type(merged.MaxBufferBytes) == "number" and merged.MaxBufferBytes > 0, "Config.MaxBufferBytes must be > 0")
	assert(type(merged.MaxDepth) == "number" and merged.MaxDepth >= 1, "Config.MaxDepth must be >= 1")
	assert(type(merged.MaxTableEntries) == "number" and merged.MaxTableEntries >= 1, "Config.MaxTableEntries must be >= 1")

	validateSavable(merged.DataTemplate, "DataTemplate", nil, 0, nil, merged)

	-- Compression must be required/compiled before MemoryStore UpdateAsync callbacks,
	-- because callback bodies cannot yield. BufferUtil is no longer required.
	if merged.SessionLocking or merged.StorageMode == "Buffer" then
		getCompression()
	end
	if merged.StorageMode == "Buffer" then
		prepareCompressionLayouts(merged)
	end
	if merged.SessionLocking and merged.SessionCompressionEnabled then
		getSessionCompressionLayout(merged)
	end

	if merged.StorageMode == "Buffer" then
		local prepared = prepareStorage(merged.Template, merged.DataVersion, merged)
		local decodedTemplate = decodeStoredValue(prepared.Value, merged)
		assert(
			type(decodedTemplate) == "table"
				and type(decodedTemplate.Version) == "number"
				and type(decodedTemplate.Data) == "table",
			"DataTemplate v2.1.0 Compression storage self-test failed"
		)
	end

	local robloxStore: any
	if merged.Scope ~= nil then
		robloxStore = DataStoreService:GetDataStore(config.Name, merged.Scope)
	else
		robloxStore = DataStoreService:GetDataStore(config.Name)
	end

	local lockName = "SDS16:" .. config.Name
	if merged.Scope ~= nil then
		lockName ..= ":" .. tostring(merged.Scope)
	end
	if #lockName > 120 then
		lockName = string.sub(lockName, 1, 120)
	end

	local self: StoreObject = setmetatable({
		Name = config.Name,
		Config = merged,
		_store = robloxStore,
		_lockMap = MemoryStoreService:GetHashMap(lockName),
		_profiles = {},
		_closed = false,
		_autosaveCursor = 1,

		ProfileLoaded = Signal.new(),
		ProfileReleased = Signal.new(),
		Issue = Signal.new(),
	}, DataStore) :: any

	self._playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player): ()
		local profile = self._profiles[player.UserId]
		if profile then
			profile._releaseRequested = "PlayerRemoving"

			task.spawn(function(): ()
				local ok, err = profile:ReleaseAsync("PlayerRemoving")
				if not ok and profile:IsActive() then
					debugWarn(merged, "PlayerRemoving release will be retried by autosave", profile.Key, err)
				end
			end)
		end
	end)

	if merged.AutoSave then
		task.spawn(function(): ()
			self:_autoSaveLoop()
		end)
	end

	game:BindToClose(function(): ()
		self:CloseAsync()
	end)

	return self
end

function DataStore._legacyKey(self: StoreObject, userId: number): string
	return self.Config.KeyPrefix .. tostring(userId)
end

function DataStore._key(self: StoreObject, userId: number): string
	if not self.Config.CompactPlayerKeys then
		return self:_legacyKey(userId)
	end
	return self.Config.CompactKeyPrefix .. encodeBase62UInt(userId)
end

function DataStore.GetKeyInfo(self: StoreObject, subject: UserSubject): KeyInfo
	local userId = resolveUserId(subject)
	local key = self:_key(userId)
	local legacyKey = self:_legacyKey(userId)
	local keyBytes = #key
	local legacyBytes = #legacyKey
	local savedBytes = math.max(0, legacyBytes - keyBytes)

	return {
		UserId = userId,
		Key = key,
		KeyBytes = keyBytes,
		LegacyKey = legacyKey,
		LegacyKeyBytes = legacyBytes,
		SavedBytes = savedBytes,
		SavingsPercent = legacyBytes > 0 and savedBytes / legacyBytes * 100 or 0,
		Compact = self.Config.CompactPlayerKeys == true,
	}
end

function DataStore.GetCompressionLayoutInfo(self: StoreObject): {[string]: any}
	prepareCompressionLayouts(self.Config)

	local layout = self.Config._CompressionLayoutsByVersion
		and self.Config._CompressionLayoutsByVersion[self.Config.DataVersion]
	local reason = self.Config._CompressionLayoutErrors
		and self.Config._CompressionLayoutErrors[self.Config.DataVersion]
		or nil

	if layout == nil then
		return {
			Enabled = self.Config.CompressionIndexedLayout == true,
			Available = false,
			Reason = reason or "No indexed layout compiled",
			DataVersion = self.Config.DataVersion,
			StorageFormatVersion = STORAGE_FORMAT_VERSION,
			CompressionVersion = DataStore.CompressionVersion(),
		}
	end

	return {
		Enabled = self.Config.CompressionIndexedLayout == true,
		Available = true,
		Reason = nil,
		DataVersion = self.Config.DataVersion,
		LayoutVersion = layout.Version,
		Mode = layout.Mode,
		FieldCount = #layout.Keys,
		Keys = table.clone(layout.Keys),
		StorageFormatVersion = STORAGE_FORMAT_VERSION,
		CompressionVersion = DataStore.CompressionVersion(),
	}
end

-- v2.0: GetSchemaInfo now describes the active Compression v3 indexed layout.
DataStore.GetSchemaInfo = DataStore.GetCompressionLayoutInfo

-- Legacy v1.9 SchemaBitBuffer inspector retained only for migration debugging.
function DataStore.GetLegacySchemaInfo(self: StoreObject): {[string]: any}
	SchemaCodec.ensureConfig(self.Config)
	local schema = self.Config._SchemaCurrent
	if schema == nil then
		return {
			Enabled = self.Config.SchemaBufferEnabled == true,
			Eligible = false,
			Reason = self.Config._SchemaReason,
			FormatVersion = SchemaCodec.VERSION,
			DataVersion = self.Config.DataVersion,
		}
	end

	local fields = table.create(schema.FieldCount)
	for index, leaf in ipairs(schema.Leaves) do
		fields[index] = {
			Index = index,
			Path = leaf.PathText,
			Kind = leaf.Kind,
		}
	end

	return {
		Enabled = self.Config.SchemaBufferEnabled == true,
		Eligible = true,
		Reason = nil,
		FormatVersion = SchemaCodec.VERSION,
		DataVersion = schema.Version,
		Fingerprint = schema.Fingerprint,
		FieldCount = schema.FieldCount,
		BitmapBytes = schema.BitmapBytes,
		Fields = fields,
	}
end

function DataStore._readStoredValue(self: StoreObject, userId: number): (boolean, any, string, string)
	local primaryKey = self:_key(userId)
	local ok, result = retryAsync(self.Config, Enum.DataStoreRequestType.GetAsync, function(): any
		return self._store:GetAsync(primaryKey)
	end)
	if not ok then
		return false, result, primaryKey, "PrimaryKey"
	end

	if result ~= nil then
		return true, result, primaryKey, self.Config.CompactPlayerKeys and "CompactKey" or "LegacyKey"
	end

	if self.Config.CompactPlayerKeys and self.Config.MigrateLegacyPlayerKeys then
		local legacyKey = self:_legacyKey(userId)
		if legacyKey ~= primaryKey then
			local legacyOk, legacyResult = retryAsync(self.Config, Enum.DataStoreRequestType.GetAsync, function(): any
				return self._store:GetAsync(legacyKey)
			end)
			if not legacyOk then
				return false, legacyResult, legacyKey, "LegacyKey"
			end
			if legacyResult ~= nil then
				return true, legacyResult, legacyKey, "LegacyKey"
			end
		end
	end

	return true, nil, primaryKey, "New"
end

function DataStore._autoSaveLoop(self: StoreObject): ()
	while not self._closed do
		local profiles = {}

		for _, profile in pairs(self._profiles) do
			if profile._active then
				profiles[#profiles + 1] = profile
			end
		end

		local count = #profiles

		if count == 0 then
			task.wait(1)
		else
			if self._autosaveCursor > count then
				self._autosaveCursor = 1
			end

			local profile = profiles[self._autosaveCursor]
			self._autosaveCursor += 1

			local spacing = math.max(0.5, self.Config.AutoSaveInterval / count)
			task.wait(spacing)

			if not self._closed and profile and profile._active then
				task.spawn(function(): ()
					local ok, err

					if profile._releaseRequested then
						ok, err = profile:ReleaseAsync(profile._releaseRequested)
					else
						ok, err = profile:SaveAsync()
					end

					if not ok and err ~= "ProfileInactive" and err ~= "SessionLost" then
						self.Issue:Fire("AutoSaveFailed", profile, err)
					end
				end)
			end
		end
	end
end

function DataStore.GetProfile(self: StoreObject, subject: UserSubject): ProfileObject?
	local userId = resolveUserId(subject)
	return self._profiles[userId]
end

function DataStore.OpenPlayerAsync(self: StoreObject, subject: UserSubject, options: OpenOptions?): (ProfileObject?, any?, any?)
	assert(not self._closed, "DataStore is closed")

	options = options or {}

	local userId, player = resolveUserId(subject)

	local existing = self._profiles[userId]
	if existing and existing._active then
		return existing
	end

	local key = self:_key(userId)
	local sessionId = HttpService:GenerateGUID(false)
	local deadline = os.clock() + self.Config.LoadTimeout
	local lockMode = options.Locked or "Wait"

	assert(lockMode == "Wait" or lockMode == "Cancel" or lockMode == "Steal", "options.Locked must be Wait, Cancel, or Steal")

	while not self._closed do
		local lockOk, lockInfo, lockStats = self:_acquireSessionLock(userId, sessionId, lockMode)

		if lockOk then
			local okRead, stored, loadedKey, keySource = self:_readStoredValue(userId)

			if not okRead then
				local tempProfile = {
					UserId = userId,
					SessionId = sessionId,
				}
				self:_releaseSessionLock(tempProfile)
				self.Issue:Fire("LoadFailed", userId, stored)
				return nil, stored
			end

			local okDecode, dataTemplate, source = pcall(decodeStoredValue, stored, self.Config)
			if not okDecode then
				local tempProfile = {
					UserId = userId,
					SessionId = sessionId,
				}
				self:_releaseSessionLock(tempProfile)
				self.Issue:Fire("DecodeFailed", userId, dataTemplate)
				return nil, dataTemplate
			end

			local data = deepCopy(dataTemplate.Data)
			local version = dataTemplate.Version

			local okMigrate, migratedData, migratedVersion = pcall(applyMigrations, data, version, self.Config)
			if not okMigrate then
				local tempProfile = {
					UserId = userId,
					SessionId = sessionId,
				}
				self:_releaseSessionLock(tempProfile)
				self.Issue:Fire("MigrationFailed", userId, migratedData)
				return nil, migratedData
			end

			data = migratedData
			version = migratedVersion

			if self.Config.Reconcile then
				reconcile(data, self.Config.Template)
			end

			local okValidate, validationError = pcall(validateSavable, data, "Data", nil, 0, nil, self.Config)
			if not okValidate then
				local tempProfile = {
					UserId = userId,
					SessionId = sessionId,
				}
				self:_releaseSessionLock(tempProfile)
				self.Issue:Fire("InvalidLoadedData", userId, validationError)
				return nil, validationError
			end

			local profile: ProfileObject = setmetatable({
				Store = self,
				UserId = userId,
				Player = player,
				Key = key,
				SessionId = sessionId,

				Version = version,
				Data = data,

				MetaData = {
					RuntimeOnly = true,
					LoadSource = source,
					KeySource = keySource,
					LoadedKey = loadedKey,
					StorageKey = key,
				},

				Changed = Signal.new(),
				Saved = Signal.new(),
				Released = Signal.new(),

				_active = true,
				_saving = false,
				_dirty = source ~= "New",
				_revision = 0,
				_lastSavedRevision = 0,
				_lastSave = os.clock(),
				_lastBufferBytes = nil,
				_lastRawBufferBytes = nil,
				_lastBufferCompressed = false,
				_lastCompressionMode = nil,
				_lastWorkingBufferBytes = nil,
				_lastCompactedPayloadBytes = nil,
				_lastUnusedWorkingBytesRemoved = 0,
				_lastSchemaEligible = self.Config._SchemaCurrent ~= nil,
				_lastSchemaCandidateAvailable = false,
				_lastSchemaSelected = false,
				_lastSchemaCandidateBytes = nil,
				_lastSchemaCandidateMode = nil,
				_lastSchemaRawBytes = nil,
				_lastSchemaRawBits = nil,
				_lastSchemaUsefulBits = nil,
				_lastSchemaPaddingBits = nil,
				_lastSchemaVarUIntMode = nil,
				_lastSchemaFieldCount = self.Config._SchemaCurrent and self.Config._SchemaCurrent.FieldCount or nil,
				_lastSchemaPresentFields = nil,
				_lastSchemaDefaultFieldsOmitted = nil,
				_lastSchemaFingerprint = self.Config._SchemaCurrent and self.Config._SchemaCurrent.Fingerprint or nil,
				_lastSchemaWorkingBufferBytes = nil,
				_lastSchemaCompactedPayloadBytes = nil,
				_lastSchemaUnusedWorkingBytesRemoved = 0,
				_lastSessionLockBytes = lockStats and lockStats.StoredBytes or nil,
				_lastSessionRawBytes = lockStats and lockStats.RawBytes or nil,
				_lastSessionCompressed = lockStats and lockStats.Compressed == true or false,
				_lastSessionCompressionMode = lockStats and lockStats.Mode or nil,
				_lastSessionWorkingBufferBytes = lockStats and lockStats.WorkingBufferBytes or nil,
				_lastSessionCompactedPayloadBytes = lockStats and lockStats.CompactedPayloadBytes or nil,
				_lastSessionUnusedWorkingBytesRemoved = lockStats and lockStats.UnusedWorkingBytesRemoved or 0,
				_releaseRequested = nil,
				_legacyKeyToDelete = if keySource == "LegacyKey" and loadedKey ~= key and self.Config.DeleteLegacyPlayerKeys then loadedKey else nil,
			}, Profile) :: any

			self._profiles[userId] = profile
			self.ProfileLoaded:Fire(profile)
			return profile
		end

		if lockMode == "Cancel" then
			return nil, "SessionLocked", lockInfo
		end

		if lockMode == "Steal" then
			return nil, "UnableToStealSession", lockInfo
		end

		if os.clock() >= deadline then
			return nil, "SessionLocked", lockInfo
		end

		task.wait(self.Config.LockRetryInterval)
	end

	return nil, "StoreClosed"
end

DataStore.LoadPlayerAsync = DataStore.OpenPlayerAsync

function DataStore.ViewTemplateAsync(self: StoreObject, subject: UserSubject): (DataTemplate?, any?, string?)
	local userId = resolveUserId(subject)
	local ok, result, _, keySource = self:_readStoredValue(userId)

	if not ok then
		return nil, result
	end

	if result == nil then
		return nil
	end

	local okDecode, dataTemplate, source = pcall(decodeStoredValue, result, self.Config)
	if not okDecode then
		self.Issue:Fire("ViewDecodeFailed", userId, dataTemplate)
		return nil, dataTemplate
	end

	return dataTemplate, source, keySource
end

function DataStore.ViewAsync(self: StoreObject, subject: UserSubject): (DataTable?, any?, any?, string?)
	local dataTemplate, sourceOrError, keySource = self:ViewTemplateAsync(subject)
	if dataTemplate == nil then
		return nil, sourceOrError
	end

	return deepCopy(dataTemplate.Data), dataTemplate.Version, sourceOrError, keySource
end

function DataStore.GetStoredBufferAsync(self: StoreObject, subject: UserSubject): (buffer?, any?)
	local userId = resolveUserId(subject)
	local ok, result = self:_readStoredValue(userId)

	if not ok then
		return nil, result
	end

	if result == nil then
		return nil
	end

	local okDecode, dataTemplate = pcall(decodeStoredValue, result, self.Config)
	if not okDecode then
		return nil, dataTemplate
	end

	return encodeBuffer(dataTemplate, self.Config)
end

function DataStore.GetStoredPayloadAsync(self: StoreObject, subject: UserSubject): (any, string?, string?)
	local userId = resolveUserId(subject)
	local ok, result, _, keySource = self:_readStoredValue(userId)

	if not ok then
		return nil, result
	end

	if typeof(result) == "buffer" then
		return cloneBuffer(result), "buffer", keySource
	end

	if type(result) == "table" then
		return deepCopy(result), "table", keySource
	end

	return result, typeof(result), keySource
end

function DataStore.GetSessionLockInfoAsync(self: StoreObject, subject: UserSubject): (SessionLock?, any?, number?)
	if not self.Config.SessionLocking then
		return nil, "SessionLockingDisabled"
	end

	local userId = resolveUserId(subject)
	local key = self:_lockKey(userId)
	local ok, result = retryMemoryAsync(self.Config, function(): any
		return self._lockMap:GetAsync(key)
	end)
	if not ok then
		return nil, result
	end

	local session, source = decodeSessionLock(result, self.Config)
	if result ~= nil and session == nil then
		return nil, source
	end
	return session, source, typeof(result) == "buffer" and buffer.len(result) or nil
end

function DataStore.SavePlayerAsync(self: StoreObject, subject: UserSubject): (boolean, any?)
	local profile = self:GetProfile(subject)
	if not profile then
		return false, "ProfileNotLoaded"
	end

	return profile:SaveAsync()
end

function DataStore.ReleasePlayerAsync(self: StoreObject, subject: UserSubject, reason: string?): (boolean, any?)
	local profile = self:GetProfile(subject)
	if not profile then
		return true
	end

	return profile:ReleaseAsync(reason)
end

function DataStore.CloseAsync(self: StoreObject): boolean
	if self._closed then
		return true
	end

	self._closed = true

	if self._playerRemovingConnection then
		self._playerRemovingConnection:Disconnect()
		self._playerRemovingConnection = nil
	end

	local profiles = {}

	for _, profile in pairs(self._profiles) do
		if profile._active then
			profiles[#profiles + 1] = profile
		end
	end

	local remaining = #profiles
	local failures = 0
	local deadline = os.clock() + self.Config.ShutdownTimeout

	for _, profile in ipairs(profiles) do
		task.spawn(function(): ()
			profile._releaseRequested = "ServerClosing"

			local ok = profile:ReleaseAsync("ServerClosing")
			if not ok and profile:IsActive() then
				failures += 1
			end

			remaining -= 1
		end)
	end

	while remaining > 0 and os.clock() < deadline do
		task.wait(0.05)
	end

	if remaining > 0 then
		warn(string.format("[DataStore v%s] Shutdown timed out with %d profile operation(s) still pending", VERSION, remaining))
	elseif failures > 0 then
		warn(string.format("[DataStore v%s] Shutdown finished with %d profile release failure(s)", VERSION, failures))
	end

	return remaining == 0 and failures == 0
end

function DataStore.CompressDataTemplate(dataTemplate: DataTemplate, options: {[string]: any}?): {[string]: any}
	assert(type(dataTemplate) == "table", "CompressDataTemplate expects a table")
	assert(type(dataTemplate.Version) == "number", "CompressDataTemplate expects DataTemplate.Version")
	assert(type(dataTemplate.Data) == "table", "CompressDataTemplate expects DataTemplate.Data")

	local config = table.clone(DEFAULTS)
	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	config.DataVersion = dataTemplate.Version
	config.Template = deepCopy(dataTemplate.Data)
	config.DataTemplate = deepCopy(dataTemplate)

	local stored, stats = compressStorageTable(dataTemplate, config)
	return {
		Data = stored,
		Bytes = stats.StoredBytes,
		Bits = stats.PhysicalBits or (stats.StoredBytes * 8),
		UsefulBits = stats.UsefulBits,
		PhysicalBits = stats.PhysicalBits,
		PaddingBits = stats.PaddingBits,
		RawBytes = stats.RawBytes,
		SavedBytes = stats.SavedBytes,
		SavingsPercent = stats.SavingsPercent,
		Codec = stats.Mode,
		IndexedSelected = stats.SchemaSelected == true,
		IndexedCandidateBytes = stats.SchemaCandidateBytes,
		AdaptiveCandidateBytes = stats.AdaptiveCandidateBytes,
	}
end

function DataStore.DecompressDataTemplate(dataBuffer: buffer, options: {[string]: any}?): (DataTemplate | DataTable)
	assert(typeof(dataBuffer) == "buffer", "DecompressDataTemplate expects a buffer")

	local config = table.clone(DEFAULTS)
	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
		if type(options.DataTemplate) == "table"
			and type(options.DataTemplate.Data) == "table" then
			config.DataVersion = options.DataTemplate.Version
			config.Template = deepCopy(options.DataTemplate.Data)
		end
	end

	if isCompressionStorageFrame(dataBuffer) then
		local decoded = decodeCompressionStorageFrame(dataBuffer, config)
		return assert(decoded, "Compression storage frame unexpectedly returned nil")
	end

	-- Compatibility with v1.8/v1.9 direct Compression table buffers.
	local decoded = tryDecodeCompressionTable(dataBuffer, config)
	if decoded ~= nil then
		return decoded
	end

	error("DataStore could not decode Compression DataTemplate buffer", 2)
end

function DataStore.Encode(data: any, options: {[string]: any}?): buffer
	local config = table.clone(DEFAULTS)
	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	local codec = getCompression()
	local packet = codec.Pack(data, tableCompressionOptions(config))
	return packet.Data
end

function DataStore.Decode(dataBuffer: buffer, options: {[string]: any}?): any
	assert(typeof(dataBuffer) == "buffer", "Decode expects a buffer")

	local config = table.clone(DEFAULTS)
	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	return getCompression().Unpack(dataBuffer, tableCompressionOptions(config))
end

-- Compatibility helpers for old raw BufferV1 payloads. New DataStore saves do
-- not use this path.
function DataStore.CompressStorageBuffer(dataBuffer: buffer, options: {[string]: any}?): (buffer, boolean, StorageStats)
	assert(typeof(dataBuffer) == "buffer", "CompressStorageBuffer expects a buffer")

	local config = table.clone(DEFAULTS)
	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	return compressStorageBuffer(dataBuffer, config)
end

function DataStore.DecompressStorageBuffer(dataBuffer: buffer, options: {[string]: any}?): buffer
	assert(typeof(dataBuffer) == "buffer", "DecompressStorageBuffer expects a buffer")

	local config = table.clone(DEFAULTS)
	if type(options) == "table" then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	return autoDecompressStorageBuffer(dataBuffer, config)
end

function DataStore.CompactBufferExact(dataBuffer: buffer, usedBytes: number?): buffer
	assert(typeof(dataBuffer) == "buffer", "CompactBufferExact expects a buffer")
	local actualUsed: number = usedBytes or buffer.len(dataBuffer)
	assert(actualUsed >= 0 and actualUsed == math.floor(actualUsed), "CompactBufferExact usedBytes must be a non-negative integer")
	assert(actualUsed <= buffer.len(dataBuffer), "CompactBufferExact usedBytes exceeds buffer length")
	return compactBufferBytes(dataBuffer, actualUsed)
end

function DataStore.EncodeUserIdKey(userId: number): string
	assert(type(userId) == "number" and userId > 0 and userId <= MAX_SAFE_INTEGER and userId == math.floor(userId), "EncodeUserIdKey expects a positive safe integer")
	return encodeBase62UInt(userId)
end

function DataStore.DecodeUserIdKey(encoded: string): number
	return decodeBase62UInt(encoded)
end

function DataStore.Version(): string
	return VERSION
end

function DataStore.FormatVersion(): number
	return STORAGE_FORMAT_VERSION
end

function DataStore.BufferUtilVersion(): string
	return "Removed"
end

function DataStore.CompressionVersion(): string
	local codec = getCompression()
	return type(codec.Version) == "function" and codec.Version() or "Unknown"
end

DataStore.Profile = Profile
DataStore.Signal = Signal
DataStore.BufferEncoding = BUFFER_ENCODING
DataStore.SessionFormatVersion = SESSION_FORMAT_VERSION
DataStore.SchemaFormatVersion = SchemaCodec.VERSION -- legacy decode format

return DataStore :: DataStoreModule
