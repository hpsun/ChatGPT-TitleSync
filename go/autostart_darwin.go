//go:build darwin && cgo

package main

// The public macOS companion owns LaunchAgent registration; the language monitor only sends committed settings.
func prepareNativeStartup(v scanSettings) (scanSettings, startupPreference, error) {
	return v, nil, nil
}
