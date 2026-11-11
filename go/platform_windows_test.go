//go:build windows && amd64

package main

import (
	"runtime"
	"testing"
	"unsafe"
)

func TestNativeCOMConditionABI(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	hr, _, _ := ole.NewProc("CoInitializeEx").Call(0, 0)
	if failed(hr) {
		t.Fatal("com-init")
	}
	defer ole.NewProc("CoUninitialize").Call()
	cls := guid{0xFF48DBA4, 0x60EF, 0x4201, [8]byte{0xAA, 0x87, 0x54, 0x10, 0x3E, 0xEF, 0x59, 0x4E}}
	iid := guid{0x30CBE57D, 0xD9D0, 0x452A, [8]byte{0xAB, 0x13, 0x7A, 0xC5, 0xAC, 0x48, 0x25, 0xEE}}
	var a, c uintptr
	hr, _, _ = ole.NewProc("CoCreateInstance").Call(uintptr(unsafe.Pointer(&cls)), 0, 1, uintptr(unsafe.Pointer(&iid)), uintptr(unsafe.Pointer(&a)))
	if failed(hr) || a == 0 {
		t.Fatal("uia-create")
	}
	defer release(a)
	v := variant{VT: 3}
	v.Data[0] = 50030
	hr, _, _ = vcall(a, 23, 30003, uintptr(unsafe.Pointer(&v)), uintptr(unsafe.Pointer(&c)))
	if failed(hr) || c == 0 {
		t.Fatal("variant-by-value-document-condition")
	}
	release(c)
	c = 0
	v = variant{VT: 11}
	hr, _, _ = vcall(a, 23, 30022, uintptr(unsafe.Pointer(&v)), uintptr(unsafe.Pointer(&c)))
	if failed(hr) || c == 0 {
		t.Fatal("variant-by-value-visible-condition")
	}
	release(c)
	// This validates native COM ABI without reading any application tree.
}
