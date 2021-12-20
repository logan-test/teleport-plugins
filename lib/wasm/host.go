package wasm

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"strings"
	"time"
	"unicode/utf16"

	"github.com/gogo/protobuf/proto"
	"github.com/gravitational/trace"
	log "github.com/sirupsen/logrus"
	wasmer "github.com/wasmerio/wasmer-go/wasmer"
)

const (
	CRANELIFT       = "cranelift"
	LLVM            = "llvm"
	protobufAllocFn = "__protobuf_alloc"
	protobufSetU8Fn = "__protobuf_setu8"
)

var (
	interopFnsNames = []string{
		protobufAllocFn, "__protobuf_free", protobufSetU8Fn, "__protobuf_getAddr", "__protobuf_getLength",
	}

	// AssemblyScript abort() signature
	asAbortSignature = wasmer.NewFunctionType(
		wasmer.NewValueTypes(
			wasmer.ValueKind(wasmer.I32), // message: string | null
			wasmer.ValueKind(wasmer.I32), // fileName: string | null,
			wasmer.ValueKind(wasmer.I32), // lineNumber: i32
			wasmer.ValueKind(wasmer.I32), // columnNumber: i32
		),
		wasmer.NewValueTypes(), // void
	)

	// AssemblyScript trace() signature
	asTraceSignature = wasmer.NewFunctionType(
		wasmer.NewValueTypes(
			wasmer.ValueKind(wasmer.I32), // message: string
			wasmer.ValueKind(wasmer.I32), // n:i32
			wasmer.ValueKind(wasmer.F64), // a0?:f64
			wasmer.ValueKind(wasmer.F64), // a1?:f64
			wasmer.ValueKind(wasmer.F64), // a2?:F64
			wasmer.ValueKind(wasmer.F64), // a3?:f64
			wasmer.ValueKind(wasmer.F64), // a4?:f64
		),
		wasmer.NewValueTypes(), // void
	)

	// seed()
	asSeed = wasmer.NewFunctionType(
		wasmer.NewValueTypes(),
		wasmer.NewValueTypes(
			wasmer.ValueKind(wasmer.F64),
		),
	)

	// getFixture()
	getFixtureSignature = wasmer.NewFunctionType(
		wasmer.NewValueTypes(wasmer.ValueKind(wasmer.I32)), // n:i32
		wasmer.NewValueTypes(wasmer.ValueKind(wasmer.I32)), // usize
	)
)

type Host struct {
	engine       *wasmer.Engine
	store        *wasmer.Store
	module       *wasmer.Module
	importObject *wasmer.ImportObject
	instance     *wasmer.Instance
	memory       *wasmer.Memory
	interopFns   map[string]wasmer.NativeFunction
	log          log.FieldLogger
	test         bool
	FixtureIndex *FixtureIndex
}

type Options struct {
	Compiler   string
	Logger     log.FieldLogger
	Test       bool
	FixtureDir string
}

func (o Options) AsConfig() (*wasmer.Config, error) {
	c := wasmer.NewConfig()

	switch o.Compiler {
	case CRANELIFT:
		c = c.UseCraneliftCompiler()
	case LLVM:
		c = c.UseLLVMCompiler()
	default:
		return nil, trace.BadParameter("Unknown compiler kind %v!", o.Compiler)
	}

	return c, nil
}

func NewHost(options Options) (*Host, error) {
	config, err := options.AsConfig()
	if err != nil {
		return nil, trace.Wrap(err)
	}

	engine := wasmer.NewEngineWithConfig(config)
	store := wasmer.NewStore(engine)

	var fixtureIndex *FixtureIndex

	if options.Test {
		fixtureIndex, err = NewFixtureIndex(options.FixtureDir)
		if err != nil {
			return nil, trace.Wrap(err)
		}
	}

	return &Host{
		engine:       engine,
		store:        store,
		log:          options.Logger,
		test:         options.Test,
		interopFns:   make(map[string]wasmer.NativeFunction),
		FixtureIndex: fixtureIndex,
	}, nil
}

// asGetString reads and returns AssemblyScript string by it's memory address. It assumes that
// a string has the standard AS GC header.
func (i *Host) asGetString(s wasmer.Value) string {
	addr := s.I32()
	if addr == 0 {
		return ""
	}

	data := i.memory.Data()
	len := int32(binary.LittleEndian.Uint32(data[addr-4 : addr]))

	// Copy UTF16 string to a buffer
	utf16buf := make([]uint16, len/2)
	for n := 0; n < int(len); n += 2 {
		pos := addr + int32(n)
		utf16buf[n/2] = binary.LittleEndian.Uint16(data[pos : pos+2])
	}

	// Convert UTF16 to UTF8
	stringBuf := &bytes.Buffer{}
	for _, r := range utf16.Decode(utf16buf) {
		stringBuf.WriteRune(r)
	}

	return stringBuf.String()
}

// asAbort AssemblyScript abort() function
func (i *Host) asAbort(args []wasmer.Value) ([]wasmer.Value, error) {
	i.log.Error(fmt.Sprintf(
		"Wasmer: abort! %v (%v:%v:%v)",
		i.asGetString(args[0]),
		i.asGetString(args[1]),
		args[2].I32(),
		args[3].I32(),
	))

	return []wasmer.Value{}, nil
}

// asAbort AssemblyScript trace() function
func (i *Host) asTrace(args []wasmer.Value) ([]wasmer.Value, error) {
	s := i.asGetString(args[0])

	if len(args) > 1 {
		var params []string

		l := int(args[1].I32())
		if len(args)-2 < l {
			l = len(args) - 2
		}

		params = make([]string, l)

		for n := 0; n < l; n++ {
			params[n] = fmt.Sprintf("%v", args[n+2].F64())
		}

		s = s + " " + strings.Join(params, ", ")
	}

	i.log.Info(s)

	return []wasmer.Value{}, nil
}

// asSeed implements random seed function
func (i *Host) asSeed(args []wasmer.Value) ([]wasmer.Value, error) {
	return []wasmer.Value{wasmer.NewF64(float64(time.Now().UnixNano()))}, nil
}

// getFixture returns fixture number n
func (i *Host) getFixture(args []wasmer.Value) ([]wasmer.Value, error) {
	n := int(args[0].I32())

	fixture := i.FixtureIndex.Get(n)
	if fixture == nil {
		return []wasmer.Value{wasmer.NewI32(0)}, trace.Errorf("Fixture %v not found", n)
	}

	return i.sendProtoMessage(fixture)
}

// TODO: make fn names constants
// sendProtoMessage sends proto.Message to the AS side
func (i *Host) sendProtoMessage(message proto.Message) ([]wasmer.Value, error) {
	size := proto.Size(message)
	bytes, err := proto.Marshal(message)
	if err != nil {
		return nil, trace.Wrap(err)
	}

	handler, err := i.interopFns[protobufAllocFn](size)
	if err != nil {
		return nil, trace.Wrap(err)
	}

	for n := 0; n < size; n++ {
		_, err := i.interopFns[protobufSetU8Fn](handler, n, bytes[n])
		if err != nil {
			return nil, trace.Wrap(err)
		}
	}

	return []wasmer.Value{wasmer.NewI32(handler)}, nil
}

// LoadPlugin loads plugin from a wasm file and ensures that all exports required exports are present
func (i *Host) LoadPlugin(b []byte) error {
	var err error

	i.module, err = wasmer.NewModule(i.store, b)
	if err != nil {
		return trace.Wrap(err)
	}

	i.importObject = wasmer.NewImportObject()
	i.importObject.Register("env", map[string]wasmer.IntoExtern{
		"abort": wasmer.NewFunction(i.store, asAbortSignature, i.asAbort),
		"trace": wasmer.NewFunction(i.store, asTraceSignature, i.asTrace),
		"seed":  wasmer.NewFunction(i.store, asSeed, i.asSeed),
	})

	if i.test {
		i.importObject.Register("test", map[string]wasmer.IntoExtern{
			"getFixture": wasmer.NewFunction(i.store, getFixtureSignature, i.getFixture),
		})
	}

	i.instance, err = wasmer.NewInstance(i.module, i.importObject)
	if err != nil {
		return trace.Wrap(err)
	}

	for _, name := range interopFnsNames {
		i.interopFns[name], err = i.instance.Exports.GetFunction(name)
		if err != nil {
			return trace.Wrap(err)
		}
	}

	i.memory, err = i.instance.Exports.GetMemory("memory")
	if err != nil {
		return trace.Wrap(err)
	}

	return nil
}

func (i *Host) Test() error {
	fn, err := i.instance.Exports.GetFunction("test")
	if err != nil {
		return trace.Wrap(err)
	}

	_, err = fn()
	if err != nil {
		return trace.Wrap(err)
	}

	return nil
}