-- Public AppleScriptObjC menu companion for the Go and Rust implementations.
-- Uses system osascript/AppKit, private settings/stop files, and one per-user LaunchAgent.
use framework "AppKit"
use framework "Foundation"
use scripting additions
property app : missing value
property statusItem : missing value
property enableItem : missing value
property settingsPanel : missing value
property foregroundField : missing value
property backgroundField : missing value
property configPath : ""
property stopPath : ""
property storageFormat : ""
property foregroundSeconds : 2
property backgroundSeconds : 5
property titlesEnabled : true
property autoStartEnabled : true
property startupPreferences : missing value
property startupItem : missing value
property startupCheckbox : missing value
property launchExecutable : ""
property iconMode : "fixed"
property fixedIcon : 45
property iconPeriod : "day"
property randomIcon : 45
property iconSlot : ""
property themeRoot : ""
property currentImage : missing value
property currentIconNumber : 0
property iconErrorSlot : ""
property iconTimer : missing value
property iconDateFormatter : missing value
property iconModeChoice : missing value
property fixedIconChoice : missing value
property iconPeriodChoice : missing value
on run argv
    if (count argv) is not 11 then error "Expected config, stop, format, foreground, background, enabled, ready, icon, implementation, autostart, executable."
    set configPath to item 1 of argv
    set stopPath to item 2 of argv
    set storageFormat to item 3 of argv
    set foregroundSeconds to (item 4 of argv) as integer
    set backgroundSeconds to (item 5 of argv) as integer
    set titlesEnabled to (item 6 of argv) is "true"
    set readyPath to item 7 of argv
    set autoStartEnabled to (item 10 of argv) is "true"
    set launchExecutable to item 11 of argv
    set startupPreferences to current application's NSUserDefaults's alloc()'s initWithSuiteName:"io.github.hpsun.ChatGPTTitleSync"
    if (startupPreferences's objectForKey:"AutoStartEnabled") is not missing value then set autoStartEnabled to startupPreferences's boolForKey:"AutoStartEnabled" as boolean
    set baseImagePath to current application's NSString's stringWithString:(item 8 of argv)
    set themeRoot to (baseImagePath's stringByDeletingLastPathComponent() as text) & "/themes"
    set iconMode to "fixed"
    set fixedIcon to 45
    set iconPeriod to "day"
    set randomIcon to 45
    set iconSlot to ""
    try
        my initializeTheme()
    on error
        my noteIconError("initialize")
    end try
    my applyStartup(autoStartEnabled)
    my persistValues()
    set app to current application's NSApplication's sharedApplication()
    app's setActivationPolicy:1
    set statusItem to current application's NSStatusBar's systemStatusBar()'s statusItemWithLength:(current application's NSVariableStatusItemLength)
    try
        set selectedNumber to my themeNumber({iconMode, fixedIcon, iconPeriod, randomIcon, iconSlot})
        my applyThemeImage(my loadThemeImage(selectedNumber), selectedNumber)
    on error
        statusItem's button()'s setTitle:"GPT"
        my noteIconError("initial_load")
    end try
    statusItem's button()'s setToolTip:("ChatGPT 标题同步助手 · " & item 9 of argv)
    set trayMenu to current application's NSMenu's alloc()'s initWithTitle:"ChatGPT-TitleSync"
    set enableItem to current application's NSMenuItem's alloc()'s initWithTitle:"启用窗口标题" action:"toggleEnabled:" keyEquivalent:""
    enableItem's setTarget:me
    if titlesEnabled then enableItem's setState:1
    trayMenu's addItem:enableItem
    set startupItem to current application's NSMenuItem's alloc()'s initWithTitle:"开机自启动 / Start at sign-in" action:"toggleAutoStart:" keyEquivalent:""
    startupItem's setTarget:me
    if autoStartEnabled then startupItem's setState:1
    trayMenu's addItem:startupItem
    set settingItem to current application's NSMenuItem's alloc()'s initWithTitle:"扫描间隔设置…" action:"openSettings:" keyEquivalent:""
    settingItem's setTarget:me
    trayMenu's addItem:settingItem
    trayMenu's addItem:(current application's NSMenuItem's separatorItem())
    set quitItem to current application's NSMenuItem's alloc()'s initWithTitle:"退出并还原标题" action:"quitHelper:" keyEquivalent:""
    quitItem's setTarget:me
    trayMenu's addItem:quitItem
    statusItem's setMenu:trayMenu
    -- The existing companion had no metadata timer: one AppKit-only timer checks
    -- slots without title/config reads, AX access, IPC arguments or another helper.
    set iconTimer to current application's NSTimer's scheduledTimerWithTimeInterval:1 target:me selector:"iconTimerFired:" userInfo:(missing value) repeats:true
    iconTimer's setTolerance:0.2
    my writeText("ready", readyPath)
    app's |run|()
end run
on writeText(contentText, destinationPath)
    set nsText to current application's NSString's stringWithString:contentText
    set didWrite to nsText's writeToFile:destinationPath atomically:true encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
    if not (didWrite as boolean) then error "Could not save private settings."
end writeText
on persistValues()
    set boolText to "false"
    if titlesEnabled then set boolText to "true"
    set autoText to "false"
    if autoStartEnabled then set autoText to "true"
    if storageFormat is "json" then
        set contentText to "{\"foreground_seconds\":" & foregroundSeconds & ",\"background_seconds\":" & backgroundSeconds & ",\"enabled\":" & boolText & ",\"autostart_enabled\":" & autoText & "}"
    else if storageFormat is "conf" then
        set contentText to "foreground_seconds=" & foregroundSeconds & linefeed & "background_seconds=" & backgroundSeconds & linefeed & "enabled=" & boolText & linefeed & "autostart_enabled=" & autoText & linefeed
    else
        error "Unknown settings format."
    end if
    my writeText(contentText, configPath)
end persistValues
on toggleEnabled:sender
    set oldValue to titlesEnabled
    set titlesEnabled to not titlesEnabled
    try
        my persistValues()
        if titlesEnabled then
            enableItem's setState:1
        else
            enableItem's setState:0
        end if
    on error errorText
        set titlesEnabled to oldValue
        my showError(errorText)
    end try
end toggleEnabled:
on makeLabel(labelText, x, y, widthValue)
    set field to current application's NSTextField's labelWithString:labelText
    field's setFrame:{{x, y}, {widthValue, 24}}
    return field
end makeLabel
on openSettings:sender
    if settingsPanel is missing value then
        set settingsPanel to current application's NSPanel's alloc()'s initWithContentRect:{{0, 0}, {440, 430}} styleMask:3 backing:2 defer:false
        settingsPanel's setTitle:"ChatGPT 标题同步助手 — 扫描间隔"
        settingsPanel's setReleasedWhenClosed:false
        set contentView to settingsPanel's contentView()
        contentView's addSubview:(my makeLabel("前台扫描间隔（秒，1–3600）", 20, 373, 295))
        set foregroundField to current application's NSTextField's alloc()'s initWithFrame:{{320, 375}, {95, 24}}
        contentView's addSubview:foregroundField
        contentView's addSubview:(my makeLabel("后台刷新间隔（秒，5–3600）", 20, 325, 295))
        set backgroundField to current application's NSTextField's alloc()'s initWithFrame:{{320, 327}, {95, 24}}
        contentView's addSubview:backgroundField
        contentView's addSubview:(my makeLabel("后台标题回改仍每秒检查一次。", 20, 278, 400))
        set startupCheckbox to current application's NSButton's alloc()'s initWithFrame:{{20, 235}, {395, 26}}
        startupCheckbox's setButtonType:3
        startupCheckbox's setTitle:"开机自启动 / Start at sign-in"
        contentView's addSubview:startupCheckbox
        set saveButton to current application's NSButton's alloc()'s initWithFrame:{{245, 20}, {80, 30}}
        saveButton's setTitle:"保存"
        saveButton's setBezelStyle:1
        saveButton's setTarget:me
        saveButton's setAction:"saveSettings:"
        contentView's addSubview:saveButton
        set cancelButton to current application's NSButton's alloc()'s initWithFrame:{{335, 20}, {80, 30}}
        cancelButton's setTitle:"取消"
        cancelButton's setBezelStyle:1
        cancelButton's setTarget:me
        cancelButton's setAction:"closeSettings:"
        contentView's addSubview:cancelButton
        set iconLabels to {"图标模式 / Icon mode", "固定配色 / Palette", "随机周期 / Period"}
        set iconValues to {{"固定 / Fixed", "随机 / Random"}, {"45", "46", "47", "48", "49", "50", "51", "52"}, {"每日 / Daily", "每小时 / Hourly", "每5分钟 / Every 5 minutes"}}
        set iconChoices to {}
        repeat with rowIndex from 1 to 3
            set rowY to 190 - 40 * (rowIndex - 1)
            contentView's addSubview:(my makeLabel(item rowIndex of iconLabels, 20, rowY, 195))
            set popup to current application's NSPopUpButton's alloc()'s initWithFrame:{{230, rowY - 2}, {185, 26}} pullsDown:false
            popup's addItemsWithTitles:(item rowIndex of iconValues)
            contentView's addSubview:popup
            set end of iconChoices to popup
        end repeat
        set iconModeChoice to item 1 of iconChoices
        set fixedIconChoice to item 2 of iconChoices
        set iconPeriodChoice to item 3 of iconChoices
        iconModeChoice's setTarget:me
        iconModeChoice's setAction:"iconModeChanged:"
        settingsPanel's center()
    end if
    startupCheckbox's setState:(autoStartEnabled as integer)
    set selectedModeIndex to 0
    if iconMode is "random" then set selectedModeIndex to 1
    iconModeChoice's selectItemAtIndex:selectedModeIndex
    set selectedPaletteIndex to (my fixedIcon) - 45
    fixedIconChoice's selectItemAtIndex:selectedPaletteIndex
    set selectedPeriodIndex to 0
    if iconPeriod is "hour" then set selectedPeriodIndex to 1
    if iconPeriod is "5min" then set selectedPeriodIndex to 2
    iconPeriodChoice's selectItemAtIndex:selectedPeriodIndex
    my iconModeChanged:me
    foregroundField's setStringValue:(foregroundSeconds as text)
    backgroundField's setStringValue:(backgroundSeconds as text)
    app's activateIgnoringOtherApps:true
    settingsPanel's makeKeyAndOrderFront:me
end openSettings:
on positiveInteger(rawText)
    if rawText is "" then error "请输入整数秒数。"
    repeat with letterValue in characters of rawText
        if (letterValue as text) is not in "0123456789" then error "请输入整数秒数。"
    end repeat
    return rawText as integer
end positiveInteger
on saveSettings:sender
    try
        set nextForeground to my positiveInteger(foregroundField's stringValue() as text)
        set nextBackground to my positiveInteger(backgroundField's stringValue() as text)
        if nextForeground < 1 or nextForeground > 3600 or nextBackground < 5 or nextBackground > 3600 then error "前台间隔需为1–3600秒，后台间隔需为5–3600秒。"
        set modeIndex to iconModeChoice's indexOfSelectedItem() as integer
        set fixedIndex to fixedIconChoice's indexOfSelectedItem() as integer
        set periodIndex to iconPeriodChoice's indexOfSelectedItem() as integer
        if modeIndex < 0 or modeIndex > 1 or fixedIndex < 0 or fixedIndex > 7 or periodIndex < 0 or periodIndex > 2 then error "Choose all icon settings."
        set modeValue to "fixed"
        if modeIndex is 1 then set modeValue to "random"
        set periodValues to {"day", "hour", "5min"}
        set nextTheme to my prepareTheme(modeValue, 45 + fixedIndex, item (periodIndex + 1) of periodValues)
        set imageObject to my loadThemeImage(my themeNumber(nextTheme))
        -- All assets and numeric values are checked before changing startup or persistence.
        set beforeTheme to my themeSnapshot()
        set beforeStartup to my startupSnapshot()
        set beforeConfig to my fileSnapshot(configPath)
        set oldAutoStart to autoStartEnabled
        set oldForeground to foregroundSeconds
        set oldBackground to backgroundSeconds
        set oldImage to currentImage
        set oldImageNumber to currentIconNumber
        set autoStartEnabled to (startupCheckbox's state() as integer) is 1
        set foregroundSeconds to nextForeground
        set backgroundSeconds to nextBackground
        try
            my applyStartup(autoStartEnabled)
            my commitTheme(nextTheme)
            my persistValues()
            my applyThemeImage(imageObject, my themeNumber(nextTheme))
            startupItem's setState:(autoStartEnabled as integer)
        on error errorText
            set rollbackFailed to false
            try
                my restoreTheme(beforeTheme)
            on error
                set rollbackFailed to true
            end try
            try
                my restoreStartup(beforeStartup)
            on error
                set rollbackFailed to true
            end try
            try
                my restoreFile(beforeConfig, configPath)
            on error
                set rollbackFailed to true
            end try
            set autoStartEnabled to oldAutoStart
            set foregroundSeconds to oldForeground
            set backgroundSeconds to oldBackground
            if oldImage is not missing value then
                try
                    my applyThemeImage(oldImage, oldImageNumber)
                on error
                    set rollbackFailed to true
                end try
            end if
            startupItem's setState:(oldAutoStart as integer)
            if rollbackFailed then set errorText to errorText & "; rollback failed"
            error errorText
        end try
        settingsPanel's orderOut:me
    on error errorText
        my showError(errorText)
    end try
end saveSettings:
on closeSettings:sender
    settingsPanel's orderOut:me
end closeSettings:
on showError(errorText)
    set alert to current application's NSAlert's alloc()'s init()
    alert's setMessageText:"扫描间隔设置"
    alert's setInformativeText:errorText
    alert's runModal()
end showError
on quitHelper:sender
    try
        my writeText("stop", stopPath)
        if iconTimer is not missing value then iconTimer's invalidate()
        app's terminate:me
    on error errorText
        my showError(errorText)
    end try
end quitHelper:

-- No shell interpolation and no bootstrap: the selected binary runs at the next login.
on applyStartup(wanted)
    set manager to current application's NSFileManager's defaultManager()
    set homePath to (manager's homeDirectoryForCurrentUser()'s path()) as text
    set folderPath to homePath & "/Library/LaunchAgents"
    set targetPath to folderPath & "/io.github.hpsun.ChatGPTTitleSync.plist"
    if wanted then
        set execText to current application's NSString's stringWithString:launchExecutable
        if not (execText's isAbsolutePath() as boolean) then error "Startup needs an absolute executable path."
        if not (manager's isExecutableFileAtPath:launchExecutable as boolean) then error "Startup executable is unavailable."
        if not (manager's createDirectoryAtPath:folderPath withIntermediateDirectories:true attributes:(missing value) |error|:(missing value) as boolean) then error "Could not create the user LaunchAgents directory."
        set entry to current application's NSMutableDictionary's dictionary()
        entry's setObject:"io.github.hpsun.ChatGPTTitleSync" forKey:"Label"
        entry's setObject:(current application's NSArray's arrayWithArray:{launchExecutable}) forKey:"ProgramArguments"
        entry's setObject:true forKey:"RunAtLoad"
        entry's setObject:false forKey:"KeepAlive"
        if not (entry's writeToFile:targetPath atomically:true as boolean) then error "Could not write the login item."
    else if (manager's fileExistsAtPath:targetPath as boolean) then
        if not (manager's removeItemAtPath:targetPath |error|:(missing value) as boolean) then error "Could not remove the login item."
    end if
    startupPreferences's setBool:wanted forKey:"AutoStartEnabled"
end applyStartup
on toggleAutoStart:sender
    set oldValue to autoStartEnabled
    set autoStartEnabled to not autoStartEnabled
    try
        my applyStartup(autoStartEnabled)
        my persistValues()
        startupItem's setState:(autoStartEnabled as integer)
        if startupCheckbox is not missing value then startupCheckbox's setState:(autoStartEnabled as integer)
    on error errorText
        set autoStartEnabled to oldValue
        try
            my applyStartup(oldValue)
        end try
        my showError(errorText)
    end try
end toggleAutoStart:

-- Five shared icon values only; this timer never reads ChatGPT or its AX tree.
on iconNames()
    return {"IconMode", "FixedIcon", "IconPeriod", "RandomIcon", "IconSlot"}
end iconNames
on loadThemeImage(numberValue)
    if numberValue < 45 or numberValue > 52 then error "Icon palette must be 45 through 52."
    set imagePath to themeRoot & "/" & numberValue & ".png"
    set imageObject to current application's NSImage's alloc()'s initWithContentsOfFile:imagePath
    if imageObject is missing value then error "Icon asset is unavailable."
    if not (imageObject's isValid() as boolean) then error "Icon asset is invalid."
    imageObject's setSize:{18, 18}
    imageObject's setTemplate:false
    return imageObject
end loadThemeImage
on validateTheme(modeValue, fixedValue, periodValue)
    set allowedModes to current application's NSArray's arrayWithArray:{"fixed", "random"}
    if not (allowedModes's containsObject:modeValue as boolean) then error "Choose fixed or random icon mode."
    if fixedValue < 45 or fixedValue > 52 then error "Choose a palette from 45 through 52."
    set allowedPeriods to current application's NSArray's arrayWithArray:{"day", "hour", "5min"}
    if not (allowedPeriods's containsObject:periodValue as boolean) then error "Choose day, hour or five minutes."
    if modeValue is "random" then
        repeat with numberValue from 45 to 52
            my loadThemeImage(numberValue)
        end repeat
    else
        my loadThemeImage(fixedValue)
    end if
end validateTheme
on iconSlotFor(periodValue, dateValue)
    if iconDateFormatter is missing value then
        set iconDateFormatter to current application's NSDateFormatter's alloc()'s init()
        iconDateFormatter's setLocale:(current application's NSLocale's alloc()'s initWithLocaleIdentifier:"en_US_POSIX")
        iconDateFormatter's setCalendar:(current application's NSCalendar's alloc()'s initWithCalendarIdentifier:(current application's NSCalendarIdentifierGregorian))
    end if
    iconDateFormatter's setTimeZone:(current application's NSTimeZone's localTimeZone())
    if periodValue is "day" then
        iconDateFormatter's setDateFormat:"yyyyMMdd"
        return iconDateFormatter's stringFromDate:dateValue as text
    end if
    if periodValue is "hour" then
        iconDateFormatter's setDateFormat:"yyyyMMddHHZ"
        return iconDateFormatter's stringFromDate:dateValue as text
    end if
    if periodValue is not "5min" then error "Invalid icon period."
    iconDateFormatter's setDateFormat:"yyyyMMddHH"
    set headText to iconDateFormatter's stringFromDate:dateValue as text
    set calendarValue to current application's NSCalendar's currentCalendar()
    calendarValue's setTimeZone:(current application's NSTimeZone's localTimeZone())
    set minuteValue to calendarValue's component:(current application's NSCalendarUnitMinute) fromDate:dateValue as integer
    set bucketText to "0" & ((minuteValue div 5) as text)
    set bucketText to text -2 thru -1 of bucketText
    iconDateFormatter's setDateFormat:"Z"
    return headText & bucketText & (iconDateFormatter's stringFromDate:dateValue as text)
end iconSlotFor
on chooseIconAvoiding(priorValue)
    -- A separate handler allows deterministic picker substitution on a future test Mac.
    repeat
        set selectedValue to random number from 45 to 52
        if selectedValue is not priorValue then return selectedValue
    end repeat
end chooseIconAvoiding
on prepareTheme(modeValue, fixedValue, periodValue)
    my validateTheme(modeValue, fixedValue, periodValue)
    set nextRandom to randomIcon
    set nextSlot to iconSlot
    if modeValue is "random" then
        set nextSlot to my iconSlotFor(periodValue, current application's NSDate's date())
        if iconMode is not "random" or iconPeriod is not periodValue or iconSlot is not nextSlot then set nextRandom to my chooseIconAvoiding(randomIcon)
    end if
    return {modeValue, fixedValue, periodValue, nextRandom, nextSlot}
end prepareTheme
on themeSnapshot()
    set valuesObject to current application's NSMutableDictionary's dictionary()
    repeat with keyName in my iconNames()
        set keyText to keyName as text
        set oldValue to startupPreferences's objectForKey:keyText
        if oldValue is missing value then set oldValue to current application's NSNull's null()
        valuesObject's setObject:oldValue forKey:keyText
    end repeat
    return {valuesObject, {iconMode, fixedIcon, iconPeriod, randomIcon, iconSlot}}
end themeSnapshot
on setThemeState(planValues)
    set iconMode to item 1 of planValues
    set fixedIcon to item 2 of planValues
    set iconPeriod to item 3 of planValues
    set randomIcon to item 4 of planValues
    set iconSlot to item 5 of planValues
end setThemeState
on restoreTheme(beforeValues)
    set valuesObject to item 1 of beforeValues
    repeat with keyName in my iconNames()
        set keyText to keyName as text
        set oldValue to valuesObject's objectForKey:keyText
        if oldValue's isKindOfClass:(current application's NSNull) as boolean then
            startupPreferences's removeObjectForKey:keyText
        else
            startupPreferences's setObject:oldValue forKey:keyText
        end if
    end repeat
    if not (startupPreferences's synchronize() as boolean) then error "Could not restore icon preferences."
    my setThemeState(item 2 of beforeValues)
end restoreTheme
on commitTheme(planValues)
    my validateTheme(item 1 of planValues, item 2 of planValues, item 3 of planValues)
    if (item 4 of planValues) < 45 or (item 4 of planValues) > 52 then error "Invalid random icon."
    set beforeValues to my themeSnapshot()
    try
        startupPreferences's setObject:(item 1 of planValues) forKey:"IconMode"
        startupPreferences's setInteger:(item 2 of planValues) forKey:"FixedIcon"
        startupPreferences's setObject:(item 3 of planValues) forKey:"IconPeriod"
        startupPreferences's setInteger:(item 4 of planValues) forKey:"RandomIcon"
        startupPreferences's setObject:(item 5 of planValues) forKey:"IconSlot"
        if not (startupPreferences's synchronize() as boolean) then error "Could not save icon preferences."
        if (startupPreferences's stringForKey:"IconMode" as text) is not (item 1 of planValues) then error "Icon mode readback failed."
        if (startupPreferences's integerForKey:"FixedIcon" as integer) is not (item 2 of planValues) then error "Icon palette readback failed."
        if (startupPreferences's stringForKey:"IconPeriod" as text) is not (item 3 of planValues) then error "Icon period readback failed."
        if (startupPreferences's integerForKey:"RandomIcon" as integer) is not (item 4 of planValues) then error "Random icon readback failed."
        if (startupPreferences's stringForKey:"IconSlot" as text) is not (item 5 of planValues) then error "Icon slot readback failed."
    on error errorText
        try
            my restoreTheme(beforeValues)
        on error
            error "Icon save and rollback failed."
        end try
        error errorText
    end try
    my setThemeState(planValues)
    set iconErrorSlot to ""
end commitTheme
on initializeTheme()
    set modeValue to "fixed"
    set fixedValue to 45
    set periodValue to "day"
    set randomValue to 45
    set slotValue to ""
    repeat with keyName in {"IconMode", "IconPeriod", "IconSlot"}
        set keyText to keyName as text
        set rawValue to startupPreferences's objectForKey:keyText
        if rawValue is not missing value then
            if not (rawValue's isKindOfClass:(current application's NSString) as boolean) then error "Invalid icon preference type."
            if keyText is "IconMode" then set modeValue to rawValue as text
            if keyText is "IconPeriod" then set periodValue to rawValue as text
            if keyText is "IconSlot" then set slotValue to rawValue as text
        end if
    end repeat
    repeat with keyName in {"FixedIcon", "RandomIcon"}
        set keyText to keyName as text
        set rawValue to startupPreferences's objectForKey:keyText
        if rawValue is not missing value then
            if not (rawValue's isKindOfClass:(current application's NSNumber) as boolean) then error "Invalid icon preference type."
            set numberValue to rawValue's integerValue() as integer
            if (rawValue's doubleValue() as real) is not numberValue then error "Icon palette must be an integer."
            if keyText is "FixedIcon" then set fixedValue to numberValue
            if keyText is "RandomIcon" then set randomValue to numberValue
        end if
    end repeat
    my validateTheme(modeValue, fixedValue, periodValue)
    if randomValue < 45 or randomValue > 52 then error "Invalid stored random icon."
    my setThemeState({modeValue, fixedValue, periodValue, randomValue, slotValue})
    if iconMode is "random" then
        set nextValues to my prepareTheme(iconMode, fixedIcon, iconPeriod)
        if nextValues is not {iconMode, fixedIcon, iconPeriod, randomIcon, iconSlot} then my commitTheme(nextValues)
    end if
end initializeTheme
on applyThemeImage(imageObject, numberValue)
    statusItem's button()'s setImage:imageObject
    statusItem's button()'s setTitle:""
    app's setApplicationIconImage:imageObject
    set currentImage to imageObject
    set currentIconNumber to numberValue
end applyThemeImage
on themeNumber(planValues)
    if (item 1 of planValues) is "fixed" then return item 2 of planValues
    return item 4 of planValues
end themeNumber
on noteIconError(slotValue)
    if iconErrorSlot is not slotValue then log "icon_rotation_failed"
    set iconErrorSlot to slotValue
end noteIconError
on iconTimerFired:sender
    if iconMode is not "random" then return
    set slotValue to my iconSlotFor(iconPeriod, current application's NSDate's date())
    if slotValue is iconSlot or slotValue is iconErrorSlot then return
    try
        set nextValues to my prepareTheme(iconMode, fixedIcon, iconPeriod)
        set imageObject to my loadThemeImage(my themeNumber(nextValues))
        my commitTheme(nextValues)
        my applyThemeImage(imageObject, my themeNumber(nextValues))
    on error
        my noteIconError(slotValue)
    end try
end iconTimerFired:
on iconModeChanged:sender
    set fixedMode to (iconModeChoice's indexOfSelectedItem() as integer) is 0
    fixedIconChoice's setEnabled:fixedMode
    iconPeriodChoice's setEnabled:(not fixedMode)
end iconModeChanged:
on fileSnapshot(pathValue)
    set manager to current application's NSFileManager's defaultManager()
    if not (manager's fileExistsAtPath:pathValue as boolean) then return current application's NSNull's null()
    set dataObject to current application's NSData's dataWithContentsOfFile:pathValue
    if dataObject is missing value then error "Could not snapshot owned settings file."
    return dataObject
end fileSnapshot
on restoreFile(dataObject, pathValue)
    set manager to current application's NSFileManager's defaultManager()
    if dataObject's isKindOfClass:(current application's NSNull) as boolean then
        if manager's fileExistsAtPath:pathValue as boolean then
            if not (manager's removeItemAtPath:pathValue |error|:(missing value) as boolean) then error "Could not restore absent owned file."
        end if
    else
        set currentData to current application's NSData's dataWithContentsOfFile:pathValue
        if currentData is not missing value then
            if currentData's isEqualToData:dataObject as boolean then return
        end if
        set directoryPath to (current application's NSString's stringWithString:pathValue)'s stringByDeletingLastPathComponent()
        if not (manager's createDirectoryAtPath:directoryPath withIntermediateDirectories:true attributes:(missing value) |error|:(missing value) as boolean) then error "Could not restore owned settings directory."
        if not (dataObject's writeToFile:pathValue atomically:true as boolean) then error "Could not restore owned settings file."
    end if
end restoreFile
on startupTarget()
    set manager to current application's NSFileManager's defaultManager()
    return (manager's homeDirectoryForCurrentUser()'s path() as text) & "/Library/LaunchAgents/io.github.hpsun.ChatGPTTitleSync.plist"
end startupTarget
on startupSnapshot()
    set dataObject to my fileSnapshot(my startupTarget())
    set oldValue to startupPreferences's objectForKey:"AutoStartEnabled"
    if oldValue is missing value then set oldValue to current application's NSNull's null()
    return {dataObject, oldValue}
end startupSnapshot
on restoreStartup(beforeValues)
    my restoreFile(item 1 of beforeValues, my startupTarget())
    set oldValue to item 2 of beforeValues
    if oldValue's isKindOfClass:(current application's NSNull) as boolean then
        startupPreferences's removeObjectForKey:"AutoStartEnabled"
    else
        startupPreferences's setObject:oldValue forKey:"AutoStartEnabled"
    end if
    if not (startupPreferences's synchronize() as boolean) then error "Could not restore login preference."
end restoreStartup
