//go:build darwin && cgo

package main

// Experimental native AX backend: source only, not compiled or run on this Windows host.

/*
#cgo LDFLAGS: -framework ApplicationServices -framework CoreFoundation -framework AppKit -lobjc -lproc
#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
typedef struct { AXUIElementRef window; uint32_t pid; uint64_t start; char *exe; } CTCandidate;
static double ct_clock(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1000000000.0;}
static int ct_process(uint32_t pid,uint64_t *start,char *path,int cap){struct proc_bsdinfo b;memset(&b,0,sizeof(b));if(proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&b,sizeof(b))!=sizeof(b)||proc_pidpath(pid,path,cap)<=0)return 0;*start=b.pbi_start_tvsec*1000000ULL+b.pbi_start_tvusec;return 1;}
static int ct_trusted(void){return AXIsProcessTrusted()?1:0;}
static int ct_target(const char *p){const char *s="/Contents/MacOS/ChatGPT";size_t a=strlen(p),b=strlen(s);return a>=b&&!strcmp(p+a-b,s);}
static uint32_t ct_front_pid(void){id pool=((id(*)(id,SEL))objc_msgSend)((id)objc_getClass("NSAutoreleasePool"),sel_registerName("new"));id ws=((id(*)(id,SEL))objc_msgSend)((id)objc_getClass("NSWorkspace"),sel_registerName("sharedWorkspace"));id app=((id(*)(id,SEL))objc_msgSend)(ws,sel_registerName("frontmostApplication"));int pid=app?((int(*)(id,SEL))objc_msgSend)(app,sel_registerName("processIdentifier")):0;((void(*)(id,SEL))objc_msgSend)(pool,sel_registerName("drain"));return pid;}
static CFTypeRef ct_copy(AXUIElementRef e,CFStringRef key){CFTypeRef v=NULL;if(AXUIElementCopyAttributeValue(e,key,&v)!=kAXErrorSuccess)return NULL;return v;}
static char *ct_text(CFTypeRef v){if(!v||CFGetTypeID(v)!=CFStringGetTypeID()||CFStringGetLength(v)>4096)return NULL;CFIndex n=CFStringGetMaximumSizeForEncoding(CFStringGetLength(v),kCFStringEncodingUTF8)+1;char *s=malloc(n);if(!s)return NULL;if(!CFStringGetCString(v,s,n,kCFStringEncodingUTF8)){free(s);return NULL;}return s;}
static int ct_valid(AXUIElementRef w,uint32_t pid,uint64_t start,const char *exe){uint64_t stamp;char path[PROC_PIDPATHINFO_MAXSIZE];if(!ct_process(pid,&stamp,path,sizeof(path))||stamp!=start||strcmp(path,exe))return 0;pid_t actual=0;if(AXUIElementGetPid(w,&actual)!=kAXErrorSuccess||actual!=pid)return 0;CFTypeRef role=ct_copy(w,kAXRoleAttribute);int yes=role&&CFEqual(role,kAXWindowRole);if(role)CFRelease(role);return yes;}
static AXUIElementRef ct_focused(uint32_t pid){if(ct_front_pid()!=pid)return NULL;AXUIElementRef sys=AXUIElementCreateSystemWide();if(!sys)return NULL;AXUIElementSetMessagingTimeout(sys,0.5);CFTypeRef app=ct_copy(sys,kAXFocusedApplicationAttribute);CFRelease(sys);if(!app)return NULL;pid_t actual=0;if(AXUIElementGetPid((AXUIElementRef)app,&actual)!=kAXErrorSuccess||actual!=pid){CFRelease(app);return NULL;}AXUIElementSetMessagingTimeout((AXUIElementRef)app,0.5);CFTypeRef win=ct_copy((AXUIElementRef)app,kAXFocusedWindowAttribute);CFRelease(app);if(win&&CFGetTypeID(win)==AXUIElementGetTypeID()&&ct_front_pid()==pid){AXUIElementSetMessagingTimeout((AXUIElementRef)win,0.5);return (AXUIElementRef)win;}if(win)CFRelease(win);return NULL;}
static int ct_active(AXUIElementRef w,uint32_t pid){if(ct_front_pid()!=pid)return 0;AXUIElementRef f=ct_focused(pid);int yes=f&&CFEqual(f,w);if(f)CFRelease(f);return yes;}
static void ct_release(AXUIElementRef w){if(w)CFRelease(w);}
static AXUIElementRef ct_retain(AXUIElementRef w){return (AXUIElementRef)CFRetain(w);}
static int ct_equal(AXUIElementRef a,AXUIElementRef b){return CFEqual(a,b);}
static char *ct_caption(AXUIElementRef w,uint32_t pid,uint64_t start,const char *exe){if(!ct_valid(w,pid,start,exe))return NULL;CFTypeRef v=ct_copy(w,kAXTitleAttribute);char *s=ct_text(v);if(v)CFRelease(v);if(!ct_valid(w,pid,start,exe)){free(s);return NULL;}return s;}
static int ct_set(AXUIElementRef w,uint32_t pid,uint64_t start,const char *exe,const char *old,const char *text,int mode){
 if(!ct_valid(w,pid,start,exe)||(mode==1&&!ct_active(w,pid))||(mode==-1&&ct_active(w,pid)))return 1;
 char *current=ct_caption(w,pid,start,exe);int same=current&&!strcmp(current,old);free(current);if(!same)return 2;
 Boolean writable=0;if(AXUIElementIsAttributeSettable(w,kAXTitleAttribute,&writable)!=kAXErrorSuccess||!writable)return 3;
 CFStringRef v=CFStringCreateWithCString(NULL,text,kCFStringEncodingUTF8);if(!v)return 4;
 if((mode==1&&!ct_active(w,pid))||(mode==-1&&ct_active(w,pid))){CFRelease(v);return 5;}
 AXError written=AXUIElementSetAttributeValue(w,kAXTitleAttribute,v);CFRelease(v);
 if((mode==1&&!ct_active(w,pid))||(mode==-1&&ct_active(w,pid))){if(written==kAXErrorSuccess)ct_set(w,pid,start,exe,text,old,0);return 6;}
 current=ct_caption(w,pid,start,exe);same=current&&!strcmp(current,text);free(current);return written==kAXErrorSuccess&&same?0:7;
}
static int ct_collect(CTCandidate **out,int *count){
 *out=NULL;*count=0;if(!AXIsProcessTrusted())return 1;int cap=proc_listpids(PROC_ALL_PIDS,0,NULL,0)+16384;if(cap<=16384)return 2;
 pid_t *pids=calloc(1,cap);int bytes=proc_listpids(PROC_ALL_PIDS,0,pids,cap);if(bytes<=0||bytes>=cap){free(pids);return 2;}
 double deadline=ct_clock()+4;
 CTCandidate *items=calloc(512,sizeof(CTCandidate));if(!items){free(pids);return 2;}
 for(int i=0;i<bytes/sizeof(pid_t)&&*count<512&&ct_clock()<deadline;i++){
  uint64_t stamp;char path[PROC_PIDPATHINFO_MAXSIZE];if(pids[i]<=0||!ct_process(pids[i],&stamp,path,sizeof(path))||!ct_target(path))continue;
  AXUIElementRef app=AXUIElementCreateApplication(pids[i]);if(!app)continue;AXUIElementSetMessagingTimeout(app,0.5);CFTypeRef array=ct_copy(app,kAXWindowsAttribute);CFRelease(app);
  if(!array||CFGetTypeID(array)!=CFArrayGetTypeID()){if(array)CFRelease(array);continue;}
  for(CFIndex n=0;n<CFArrayGetCount(array)&&*count<512&&ct_clock()<deadline;n++){
   AXUIElementRef w=(AXUIElementRef)CFArrayGetValueAtIndex(array,n);if(!w||CFGetTypeID(w)!=AXUIElementGetTypeID())continue;AXUIElementSetMessagingTimeout(w,0.5);
   if(!ct_valid(w,pids[i],stamp,path))continue;char *copy=strdup(path);if(!copy)continue;
   items[*count]=(CTCandidate){ct_retain(w),(uint32_t)pids[i],stamp,copy};(*count)++;
  }CFRelease(array);
 }free(pids);*out=items;return 0;
}
static void ct_free_candidates(CTCandidate *p,int n){for(int i=0;i<n;i++){ct_release(p[i].window);free(p[i].exe);}free(p);}
static char *ct_name(AXUIElementRef w,uint32_t pid,uint64_t start,const char *exe,int foreground){
 if(!ct_valid(w,pid,start,exe)||ct_active(w,pid)!=foreground)return NULL;
 AXUIElementRef q[64];int depth[64],head=0,tail=1,bad=0,docs=0;q[0]=ct_retain(w);depth[0]=0;CFTypeRef title=NULL;double end=ct_clock()+2;
 while(head<tail){
  if(ct_clock()>=end||ct_active(w,pid)!=foreground){bad=1;break;}
  AXUIElementRef node=q[head];int d=depth[head++];CFTypeRef role=ct_copy(node,kAXRoleAttribute);
  if(!role||CFGetTypeID(role)!=CFStringGetTypeID()){if(role)CFRelease(role);bad=1;break;}
  if(CFEqual(role,CFSTR("AXWebArea"))){docs++;if(docs==1)title=ct_copy(node,kAXTitleAttribute);CFRelease(role);continue;}
  int container=CFEqual(role,kAXWindowRole)||CFEqual(role,CFSTR("AXGroup"))||CFEqual(role,CFSTR("AXSplitGroup"))||CFEqual(role,CFSTR("AXScrollArea"))||CFEqual(role,CFSTR("AXLayoutArea"));CFRelease(role);
  if(!container)continue;if(d>=8){bad=1;break;}CFTypeRef children=ct_copy(node,kAXChildrenAttribute);
  if(!children||CFGetTypeID(children)!=CFArrayGetTypeID()){if(children)CFRelease(children);bad=1;break;}
  CFIndex n=CFArrayGetCount(children);if(n>64-tail){CFRelease(children);bad=1;break;}
  for(CFIndex i=0;i<n;i++){AXUIElementRef child=(AXUIElementRef)CFArrayGetValueAtIndex(children,i);if(!child||CFGetTypeID(child)!=AXUIElementGetTypeID()){bad=1;break;}AXUIElementSetMessagingTimeout(child,0.5);q[tail]=ct_retain(child);depth[tail++]=d+1;}
  CFRelease(children);if(bad)break;
 }
 char *s=!bad&&docs==1&&ct_valid(w,pid,start,exe)&&ct_active(w,pid)==foreground?ct_text(title):NULL;
 if(title)CFRelease(title);for(int i=0;i<tail;i++)ct_release(q[i]);return s;
}
*/
import "C"
import (
	"context"
	"errors"
	"os/exec"
	"sync"
	"unsafe"
)

type macEntry struct {
	W   Window
	Ref C.AXUIElementRef
}

var macMu sync.Mutex
var macEntries = map[uint64]macEntry{}
var macNext uint64

func processIdentity(pid uint32) (uint64, string, error) {
	var stamp C.uint64_t
	var path [4096]C.char
	if C.ct_process(C.uint32_t(pid), &stamp, &path[0], 4096) == 0 {
		return 0, "", errors.New("process-identity")
	}
	return uint64(stamp), C.GoString(&path[0]), nil
}
func registerMac(ref C.AXUIElementRef, pid uint32, start uint64, exe string) Window {
	macMu.Lock()
	defer macMu.Unlock()
	for _, e := range macEntries {
		if e.W.PID == pid && e.W.Start == start && e.W.Exe == exe && C.ct_equal(e.Ref, ref) != 0 {
			return e.W
		}
	}
	macNext++
	w := Window{macNext, pid, start, "AXWindow", exe}
	macEntries[macNext] = macEntry{w, C.ct_retain(ref)}
	return w
}
func takeMac(w Window) (C.AXUIElementRef, error) {
	macMu.Lock()
	defer macMu.Unlock()
	e, ok := macEntries[w.Handle]
	if !ok || e.W.Key() != w.Key() {
		return C.AXUIElementRef(0), errors.New("identity")
	}
	return C.ct_retain(e.Ref), nil
}
func nativeList() ([]Window, error) {
	pid := uint32(C.ct_front_pid())
	stamp, exe, e := processIdentity(pid)
	if e != nil {
		return nil, nil
	}
	p := C.CString(exe)
	defer C.free(unsafe.Pointer(p))
	if C.ct_target(p) == 0 {
		return nil, nil
	}
	if C.ct_trusted() == 0 {
		return nil, errors.New("AX-permission")
	}
	ref := C.ct_focused(C.uint32_t(pid))
	if ref == C.AXUIElementRef(0) {
		return nil, nil
	}
	defer C.ct_release(ref)
	return []Window{registerMac(ref, pid, stamp, exe)}, nil
}
func nativeListAll() ([]Window, error) {
	var p *C.CTCandidate
	var n C.int
	if C.ct_collect(&p, &n) != 0 {
		return nil, errors.New("AX-discovery")
	}
	defer C.ct_free_candidates(p, n)
	out := []Window{}
	for _, e := range unsafe.Slice(p, int(n)) {
		out = append(out, registerMac(e.window, uint32(e.pid), uint64(e.start), C.GoString(e.exe)))
	}
	return out, nil
}
func withMac(w Window, action func(C.AXUIElementRef, *C.char) error) error {
	ref, e := takeMac(w)
	if e != nil {
		return e
	}
	defer C.ct_release(ref)
	exe := C.CString(w.Exe)
	defer C.free(unsafe.Pointer(exe))
	return action(ref, exe)
}
func nativeSame(w Window) bool {
	ok := false
	_ = withMac(w, func(ref C.AXUIElementRef, exe *C.char) error {
		ok = C.ct_valid(ref, C.uint32_t(w.PID), C.uint64_t(w.Start), exe) != 0
		return nil
	})
	return ok
}
func nativeActive(w Window) bool {
	if uint32(C.ct_front_pid()) != w.PID {
		return false
	}
	ok := false
	_ = withMac(w, func(ref C.AXUIElementRef, _ *C.char) error { ok = C.ct_active(ref, C.uint32_t(w.PID)) != 0; return nil })
	return ok
}
func nativeCaption(w Window) (string, error) {
	var value string
	e := withMac(w, func(ref C.AXUIElementRef, exe *C.char) error {
		p := C.ct_caption(ref, C.uint32_t(w.PID), C.uint64_t(w.Start), exe)
		if p == nil {
			return errors.New("caption")
		}
		defer C.free(unsafe.Pointer(p))
		value = C.GoString(p)
		return nil
	})
	return value, e
}
func macSet(w Window, a, b string, mode int) error {
	return withMac(w, func(ref C.AXUIElementRef, exe *C.char) error {
		old, text := C.CString(a), C.CString(b)
		defer C.free(unsafe.Pointer(old))
		defer C.free(unsafe.Pointer(text))
		if C.ct_set(ref, C.uint32_t(w.PID), C.uint64_t(w.Start), exe, old, text, C.int(mode)) != 0 {
			return errors.New("write-unconfirmed")
		}
		return nil
	})
}
func nativeSet(w Window, a, b string) error       { return macSet(w, a, b, 0) }
func nativeSetActive(w Window, a, b string) error { return macSet(w, a, b, 1) }
func nativeReadName(w Window) (string, error)     { return nativeReadNameMode(w, true) }
func nativeReadNameMode(w Window, foreground bool) (string, error) {
	var title string
	mode := 0
	if foreground {
		mode = 1
	}
	e := withMac(w, func(ref C.AXUIElementRef, exe *C.char) error {
		p := C.ct_name(ref, C.uint32_t(w.PID), C.uint64_t(w.Start), exe, C.int(mode))
		if p == nil {
			return errors.New("source-unavailable")
		}
		defer C.free(unsafe.Pointer(p))
		title = C.GoString(p)
		return nil
	})
	return title, e
}
func nativeReadSource(ctx context.Context, w Window, foreground bool) (string, error) {
	if e := ctx.Err(); e != nil {
		return "", e
	}
	s, e := nativeReadNameMode(w, foreground)
	if ctx.Err() != nil {
		return "", ctx.Err()
	}
	return s, e
}
func isolatedName(ctx context.Context, w Window) (string, error) {
	return nativeReadSource(ctx, w, true)
}
func hideChild(*exec.Cmd)   {}
func nativeSelfTest() error { return errors.New("Experimental: no native Mac fixture was run") }
func nativeAcquire() (func(), error) {
	return func() {
		macMu.Lock()
		defer macMu.Unlock()
		for k, e := range macEntries {
			C.ct_release(e.Ref)
			delete(macEntries, k)
		}
	}, nil
}
func nativeRequestStop() error  { return nil }
func nativeStopRequested() bool { return false }

func nativeSetInactive(w Window, a, b string) error { return macSet(w, a, b, -1) }

func backgroundChild(*exec.Cmd) {}
