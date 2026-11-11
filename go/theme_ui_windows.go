//go:build windows && amd64

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
)

func (t *winTray) combo(items []string, x, y int32, id uintptr) uintptr {
	h := t.child("COMBOBOX", "", 0x00210003, x, y, 140, 190, id)
	for _, v := range items {
		uiCall("SendMessageW", h, 0x143, 0, tu(v))
	}
	return h
}
func (t *winTray) syncThemeFields() {
	s := defaultIconTheme()
	if t.theme != nil {
		s = t.theme.snapshot()
	}
	mode := uintptr(0)
	if s.Mode == "random" {
		mode = 1
	}
	period := uintptr(0)
	if s.Period == "hour" {
		period = 1
	}
	if s.Period == "5min" {
		period = 2
	}
	uiCall("SendMessageW", t.modeCombo, 0x14e, mode, 0)
	uiCall("SendMessageW", t.fixedCombo, 0x14e, uintptr(s.Fixed-45), 0)
	uiCall("SendMessageW", t.periodCombo, 0x14e, period, 0)
	t.enableThemeFields()
}
func (t *winTray) enableThemeFields() {
	random := uiCall("SendMessageW", t.modeCombo, 0x147, 0, 0) == 1
	fixedOn, randomOn := uintptr(1), uintptr(0)
	if random {
		fixedOn, randomOn = 0, 1
	}
	uiCall("EnableWindow", t.fixedCombo, fixedOn)
	uiCall("EnableWindow", t.periodCombo, randomOn)
}
func resolveThemeAsset(id int) (string, error) {
	exe, e := os.Executable()
	if e != nil {
		return "", e
	}
	dir := filepath.Dir(exe)
	name := strconv.Itoa(id) + ".ico"
	for _, base := range []string{"themes", "assets/themes", "../assets/themes", "../../assets/themes", "../../../assets/themes"} {
		p := filepath.Join(dir, base, name)
		if st, e := os.Stat(p); e == nil && st.Mode().IsRegular() {
			return p, nil
		}
	}
	return "", fmt.Errorf("图标资源不可用：%d", id)
}
func loadThemeAsset(id int) (uintptr, error) {
	p, e := resolveThemeAsset(id)
	if e != nil {
		return 0, e
	}
	h := uiCall("LoadImageW", 0, tu(p), 1, 0, 0, 0x50)
	if h == 0 {
		return 0, fmt.Errorf("图标资源无法加载：%d", id)
	}
	return h, nil
}
func (t *winTray) validateThemeAsset(id int) error {
	h, e := t.loadThemeIcon(id)
	if e == nil {
		uiCall("DestroyIcon", h)
	}
	return e
}
func (t *winTray) installThemeAsset(id int) error {
	if t.iconID == id {
		return nil
	}
	h, e := t.loadThemeIcon(id)
	if e != nil {
		return e
	}
	old, owned := t.icon, t.iconOwned
	t.nid.Icon = h
	if !t.test && !t.updateIcon(1) {
		t.nid.Icon = old
		uiCall("DestroyIcon", h)
		return fmt.Errorf("托盘图标更新失败")
	}
	for _, w := range []uintptr{t.hwnd, t.panel} {
		if w != 0 {
			uiCall("SendMessageW", w, 0x80, 0, h)
			uiCall("SendMessageW", w, 0x80, 1, h)
		}
	}
	t.icon = h
	t.iconOwned = true
	t.iconID = id
	if owned && old != 0 {
		uiCall("DestroyIcon", old)
	}
	return nil
}

func (t *winTray) loadThemeIcon(id int) (uintptr, error) {
	if t.assetLoader != nil {
		return t.assetLoader(id)
	}
	return loadThemeAsset(id)
}
