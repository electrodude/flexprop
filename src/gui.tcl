# Simple GUI for Spin
# Copyright 2018 Total Spectrum Software
# Distributed under the terms of the MIT license;
# see License.txt for details.
#
#
# The guts of the interpreter
#

# global variables
set CONFIG_FILE "~/.spin2gui.config"
set ROOTDIR [file dirname $::argv0]
set OPT "-O2"

if { $tcl_platform(platform) == "windows" } {
    set WINPREFIX "cmd.exe /c start"
} else {
    set WINPREFIX "xterm -fs 14 -e"
}
# provide some default settings
proc setShadowP1Defaults {} {
    global shadow
    global WINPREFIX
    
    set shadow(compilecmd) "%D/bin/fastspin -l %O -L %L %S"
    set shadow(runcmd) "$WINPREFIX %D/bin/propeller-load %B -r -t"
}
proc setShadowP2Defaults {} {
    global shadow
    global WINPREFIX
    
    set shadow(compilecmd) "%D/bin/fastspin -2 -l %O -L %L %S"
    set shadow(runcmd) "$WINPREFIX %D/bin/loadp2 %B -t"
}
proc copyShadowToConfig {} {
    global config
    global shadow
    set config(compilecmd) $shadow(compilecmd)
    set config(runcmd) $shadow(runcmd)
}

set config(library) "./lib"
set config(spinext) ".spin"
set config(lastdir) "."
set OPT "-O1"

setShadowP2Defaults
copyShadowToConfig
    
#
# set font and tab stops for a window
#
proc setfont { w fnt } {
    $w configure -font $fnt
#    set mwidth [expr 8*[font measure $fnt "m"]]
#    set mwidth2 [expr 2*$mwidth]
#    set mwidth3 [expr 3*$mwidth]
#    set mwidth4 [expr 3*$mwidth]
#    $w configure -tabs "$mwidth $mwidth2 $mwidth3 $mwidth4"
}

# configuration settings
proc config_open {} {
    global config
    global CONFIG_FILE
    global OPT
    
    if {[file exists $CONFIG_FILE]} {
	set fp [open $CONFIG_FILE r]
    } else {
	return 0
    }
    # read config values
    while {![eof $fp]} {
	set data [gets $fp]
	switch [lindex $data 0] {
	    \# {
		# ignore the comment
	    }
	    geometry {
		# restore last position on screen
		wm geometry [winfo toplevel .] [lindex $data 1]
	    }
	    font {
		# restore font
		setfont .nb.main.txt [lindex $data 1]
	    }
	    opt {
		# set optimize level
		set OPT [lindex $data 1]
	    }
	    default {
		set config([lindex $data 0]) [lindex $data 1]
	    }
	}
    }
    close $fp
    return 1
}

proc config_save {} {
    global config
    global CONFIG_FILE
    global OPT
    set fp [open $CONFIG_FILE w]
    puts $fp "# spin2gui config info"
    puts $fp "geometry\t[winfo geometry [winfo toplevel .]]"
    puts $fp "font\t\{[.nb.main.txt cget -font]\}"
    puts $fp "opt\t\{$OPT\}"
    foreach i [array names config] {
	if {$i != ""} {
	    puts $fp "$i\t\{$config($i)\}"
	}
    }
    close $fp
}

#
# read a file and return its text
# does UCS-16 to UTF-8 conversion
#
proc uread {name} {
    set encoding ""
    set len [file size $name]
    set f [open $name r]
    gets $f line
    if {[regexp \xFE\xFF $line] || [regexp \xFF\xFE $line]} {
	fconfigure $f -encoding unicode
	set encoding unicode
    }
    seek $f 0 start ;# rewind
    set text [read $f $len]
    close $f
    if {$encoding=="unicode"} {
	regsub -all "\uFEFF|\uFFFE" $text "" text
    }
    return $text
}

#
# reset anything associated with the output file and configuration
#
proc resetOutputVars { } {
    global BINFILE
    
    set BINFILE ""
}

# exit the program
proc exitProgram { } {
    checkChanges
    config_save
    exit
}

# close tab
proc closeTab { } {
    set w [focus]
    set s [.nb select]
    puts "focus = $w select =  $s"
}

# load a file into a text (or ctext) window
proc loadFileToWindow { fname win } {
    set file_data [uread $fname]
    $win delete 1.0 end
    $win insert end $file_data
    $win edit modified false
}

# save contents of a window to a file
proc saveFileFromWindow { fname win } {
    set fp [open $fname w]
    set file_data [$win get 1.0 end]

    # HACK: the text widget inserts an extra \n at end of file
    set file_data [string trimright $file_data]
    
    set len [string len $file_data]
    #puts " writing $len bytes"

    # we trimmed away all the \n above, so put one back here
    # by leaving off the -nonewline to puts
    puts $fp $file_data
    close $fp
    $win edit modified false
}


#
# tag text containing "error:" in a text widget w
#
proc tagerrors { w } {
    $w tag remove errtxt 0.0 end
    # set current position at beginning of file
    set cur 1.0
    # search through looking for error:
    while 1 {
	set cur [$w search -count length "error:" $cur end]
	if {$cur eq ""} {break}
	$w tag add errtxt $cur "$cur lineend"
	set cur [$w index "$cur + $length char"]
    }
    $w tag configure errtxt -foreground red
}

set SpinTypes {
    {{Spin2 files}   {.spin2 .spin} }
    {{Spin files}   {.spin} }
    {{All files}    *}
}

set BinTypes {
    {{Binary files}   {.binary .bin} }
    {{All files}    *}
}

#
# see if anything has changed in the main text window
#
proc checkChanges {} {
    global filenames
    set s filenames(.nb.main)
    if {[.nb.main.txt edit modified]==1} {
	set answer [tk_messageBox -icon question -type yesno -message "Save file $s?" -default yes]
	if { $answer eq yes } {
	    saveSpinFile
	}
    }
}

proc getLibrary {} {
    global config
    set config(library) [tk_chooseDirectory -title "Choose Spin library directory" -initialdir $config(library) ]
}

proc newSpinFile {} {
    global filenames
    set BINFILE ""
    checkChanges
    .nb.main.txt delete 1.0 end
    .bot.txt delete 1.0 end
    set filenames(.nb.main) ""
    .nb tab .nb.main -text "New File"
}

set TABCOUNTER 0
proc newTab {} {
    global TABCOUNTER
    set s "f$TABCOUNTER"
    set TABCOUNTER [expr "$TABCOUNTER + 1"]
    return ".nb.$s"
}

# load a secondary file into a read-only window
# the window name is w
# its title is title
# if title is "" then set the title based on
# the file name
#
proc loadFileForBrowse {w filename title} {
    global config
    set viewpos 0
    if {$title eq ""} {
	set title [file tail $filename]
    }
    if {[winfo exists $w]} {
	.nb select $w
	set viewpos [$w.txt yview]
	set viewpos [lindex $viewpos 0]
    } else {
	frame $w
	set yscmd "$w.v set"
	set xscmd "$w.h set"
	set yvcmd "$w.txt yview"
	set xvcmd "$w.txt xview"
	set searchcmd "searchrep $w.txt 0"

	.nb add $w -text "$title"
	ctext $w.txt -wrap none -yscrollcommand $yscmd -xscroll $xscmd -tabstyle wordprocessor
	scrollbar $w.v -orient vertical -command $yvcmd
	scrollbar $w.h -orient horizontal -command $xvcmd

#	grid columnconfigure $w 0 -weight 1
#	grid rowconfigure $w 0 -weight 1
	
#	grid $w -sticky nsew
	grid $w.txt $w.v -sticky nsew
	grid $w.h -sticky nsew
	grid rowconfigure $w $w.txt -weight 1
	grid columnconfigure $w $w.txt -weight 1

	setHighlightingSpin $w.txt
	bind $w.txt <Control-f> $searchcmd
    }

    setfont $w.txt [.nb.main.txt cget -font]
    loadFileToWindow $filename $w.txt
    $w.txt yview moveto $viewpos
    $w.txt highlight 1.0 end
    ctext::comments $w.txt
    ctext::linemapUpdate $w.txt
    .nb select $w
}

proc browseFile {} {
    global config
    global SpinTypes
    
    set filename [tk_getOpenFile -filetypes $SpinTypes -defaultextension $config(spinext) -initialdir $config(lastdir) -title "Browse File" ]
    if { [string length $filename] == 0 } {
	return
    }
    set config(lastdir) [file dirname $filename]
    loadFileForBrowse [newTab] $filename ""
}

proc loadSpinFile {} {
    global BINFILE
    global filenames
    global SpinTypes
    global config
    
    checkChanges
    set filename [tk_getOpenFile -filetypes $SpinTypes -defaultextension $config(spinext) -initialdir $config(lastdir) ]
    if { [string length $filename] == 0 } {
	return
    }
    set config(lastdir) [file dirname $filename]
    set config(spinext) [file extension $filename]
    loadFileToWindow $filename .nb.main.txt
    .nb.main.txt highlight 1.0 end
    ctext::comments .nb.main.txt
    ctext::linemapUpdate .nb.main.txt
    
    set filenames(.nb.main) $filename
    set BINFILE ""
    .nb tab .nb.main -text $filename
}

proc saveSpinFile {} {
    global filenames
    global BINFILE
    global SpinTypes
    global config
    
    if { [string length $filenames(.nb.main)] == 0 } {
	set filename [tk_getSaveFile -initialfile $filenames(.nb.main) -filetypes $SpinTypes -defaultextension $config(spinext) ]
	if { [string length $filename] == 0 } {
	    return
	}
	set config(lastdir) [file dirname $filename]
	set config(spinext) [file extension $filename]
	set filenames(.nb.main) $filename
	set BINFILE ""
    }
    
    saveFileFromWindow $filenames(.nb.main) .nb.main.txt
    .nb tab .nb.main -text $filenames(.nb.main) 
}

proc saveSpinAs {} {
    global filenames
    global BINFILE
    global SpinTypes
    global config
    set filename [tk_getSaveFile -filetypes $SpinTypes -defaultextension $config(spinext) -initialdir $config(lastdir) ]
    if { [string length $filename] == 0 } {
	return
    }
    set config(lastdir) [file dirname $filename]
    set config(spinext) [file extension $filename]
    set BINFILE ""
    set filenames(.nb.main) $filename
    .nb tab .nb.main -text $filename
    saveSpinFile
}

set aboutMsg {
GUI tool for .spin2
Version 1.0.4    
Copyright 2018 Total Spectrum Software Inc.
------
There is no warranty and no guarantee that
output will be correct.    
}

proc doAbout {} {
    global aboutMsg
    tk_messageBox -icon info -type ok -message "Spin 2 GUI" -detail $aboutMsg
}

proc doHelp {} {
    loadFileForBrowse .nb.help "doc/help.txt" "Help"
    makeReadOnly .nb.help
}

#
# set up syntax highlighting for a given ctext widget
proc setHighlightingSpin {w} {
    set color(comments) grey
    set color(keywords) DarkBlue
    set color(brackets) purple
    set color(numbers) DeepPink
    set color(operators) green
    set color(strings)  red
    set color(varnames) black
    set color(preprocessor) cyan
    set keywordsbase [list Con Obj Dat Var Pub Pri Quit Exit Repeat While Until If Then Else Return Abort Long Word Byte Asm Endasm String]
    foreach i $keywordsbase {
	lappend keywordsupper [string toupper $i]
    }
    foreach i $keywordsbase {
	lappend keywordslower [string tolower $i]
    }
    set keywords [concat $keywordsbase $keywordsupper $keywordslower]

    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) \$ 
    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) \%
    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) 0
    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) 1
    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) 2
    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) 3
    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) 4
    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) 5
    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) 6
    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) 7
    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) 8
    ctext::addHighlightClassWithOnlyCharStart $w numbers $color(numbers) 9

    ctext::addHighlightClass $w keywords $color(keywords) $keywords

    ctext::addHighlightClassForSpecialChars $w brackets $color(brackets) {[]()}
    ctext::addHighlightClassForSpecialChars $w operators $color(operators) {+-=><!@~\*/&:|}

    ctext::addHighlightClassForRegexp $w strings $color(strings) {"(\\"||^"])*"}
    ctext::addHighlightClassForRegexp $w preprocessor $color(preprocessor) {^\#[a-z]+}

    ctext::addHighlightClassForRegexp $w comments $color(comments) {\'[^\n\r]*}
    ctext::enableComments $w
    $w tag configure _cComment -foreground $color(comments)
    $w tag raise _cComment
}

menu .mbar
. configure -menu .mbar
menu .mbar.file -tearoff 0
menu .mbar.edit -tearoff 0
menu .mbar.options -tearoff 0
menu .mbar.run -tearoff 0
menu .mbar.help -tearoff 0

.mbar add cascade -menu .mbar.file -label File
.mbar.file add command -label "New Spin File..." -accelerator "^N" -command { newSpinFile }
.mbar.file add command -label "Open Spin File..." -accelerator "^O" -command { loadSpinFile }
.mbar.file add command -label "Save Spin File" -accelerator "^S" -command { saveSpinFile }
.mbar.file add command -label "Save File As..." -command { saveSpinAs }
.mbar.file add separator
.mbar.file add command -label "Browse File..." -accelerator "^B" -command { browseFile }
.mbar.file add separator
.mbar.file add command -label "Library directory..." -command { getLibrary }
.mbar.file add separator
.mbar.file add command -label "Close tab" -accelerator "^W" -command { closeTab }
.mbar.file add separator
.mbar.file add command -label Exit -accelerator "^Q" -command { exitProgram }

.mbar add cascade -menu .mbar.edit -label Edit
.mbar.edit add command -label "Cut" -accelerator "^X" -command {event generate [focus] <<Cut>>}
.mbar.edit add command -label "Copy" -accelerator "^C" -command {event generate [focus] <<Copy>>}
.mbar.edit add command -label "Paste" -accelerator "^V" -command {event generate [focus] <<Paste>>}
.mbar.edit add separator
.mbar.edit add command -label "Undo" -accelerator "^Z" -command {event generate [focus] <<Undo>>}
.mbar.edit add command -label "Redo" -accelerator "^Y" -command {event generate [focus] <<Redo>>}
.mbar.edit add separator
.mbar.edit add command -label "Find..." -accelerator "^F" -command {searchrep [focus] 0}
.mbar.edit add separator

.mbar.edit add command -label "Select Font..." -command { tk fontchooser show }
    
.mbar add cascade -menu .mbar.options -label Options
.mbar.options add radiobutton -label "No Optimization" -variable OPT -value "-O0"
.mbar.options add radiobutton -label "Default Optimization" -variable OPT -value "-O1"
.mbar.options add radiobutton -label "Full Optimization" -variable OPT -value "-O2"

.mbar add cascade -menu .mbar.run -label Commands
.mbar.run add command -label "Compile" -command { doCompile }
.mbar.run add command -label "Run binary on device" -command { doLoadRun }
.mbar.run add command -label "Compile and run" -accelerator "^R" -command { doCompileRun }
.mbar.run add separator
.mbar.run add command -label "Open listing file" -accelerator "^L" -command { doListing }
.mbar.run add separator
.mbar.run add command -label "Configure Commands..." -command { doRunOptions }

.mbar add cascade -menu .mbar.help -label Help
.mbar.help add command -label "Help" -command { doHelp }
.mbar.help add separator
.mbar.help add command -label "About..." -command { doAbout }

wm title . "Spin 2 GUI"

grid columnconfigure . {0 1} -weight 1
grid rowconfigure . 1 -weight 1
ttk::notebook .nb
frame .nb.main
frame .bot
frame .toolbar -bd 1 -relief raised

.nb add .nb.main -text "New File"

grid .toolbar -column 0 -row 0 -columnspan 2 -sticky nsew
grid .nb -column 0 -row 1 -columnspan 2 -rowspan 1 -sticky nsew
grid .bot -column 0 -row 2 -columnspan 2 -sticky nsew

button .toolbar.compile -text "Compile" -command doCompile
button .toolbar.runBinary -text "Run Binary" -command doLoadRun
button .toolbar.compileRun -text "Compile & Run" -command doCompileRun
grid .toolbar.compile .toolbar.runBinary .toolbar.compileRun -sticky nsew

scrollbar .nb.main.v -orient vertical -command {.nb.main.txt yview}
scrollbar .nb.main.h -orient horizontal -command {.nb.main.txt xview}
ctext .nb.main.txt -wrap none -xscroll {.nb.main.h set} -yscrollcommand {.nb.main.v set} -undo 1 -tabstyle wordprocessor

grid .nb.main.txt .nb.main.v -sticky nsew
grid .nb.main.h           -sticky nsew
grid rowconfigure .nb.main .nb.main.txt -weight 1
grid columnconfigure .nb.main .nb.main.txt -weight 1

scrollbar .bot.v -orient vertical -command {.bot.txt yview}
scrollbar .bot.h -orient horizontal -command {.bot.txt xview}
text .bot.txt -wrap none -xscroll {.bot.h set} -yscroll {.bot.v set} -height 8
label .bot.label -background DarkGrey -foreground white -text "Compiler Output"

grid .bot.label      -sticky nsew
grid .bot.txt .bot.v -sticky nsew
grid .bot.h          -sticky nsew
grid rowconfigure .bot .bot.txt -weight 1
grid columnconfigure .bot .bot.txt -weight 1

tk fontchooser configure -parent .
bind .nb.main.txt <FocusIn> [list fontchooserFocus .nb.main.txt]

bind . <Control-n> { newSpinFile }
bind . <Control-o> { loadSpinFile }
bind . <Control-s> { saveSpinFile }
bind . <Control-b> { browseFile }
bind . <Control-q> { exitProgram }
bind . <Control-r> { doCompileRun }
bind . <Control-l> { doListing }
bind . <Control-f> { searchrep [focus] 0 }
bind . <Control-w> { closeTab }

wm protocol . WM_DELETE_WINDOW {
    exitProgram
}

autoscroll::autoscroll .nb.main.v
autoscroll::autoscroll .nb.main.h
autoscroll::autoscroll .bot.v
autoscroll::autoscroll .bot.h

# actually read in our config info
config_open

# font configuration stuff
proc fontchooserFocus {w} {
    tk fontchooser configure -font [$w cget -font] -command [list fontchooserFontSelection $w]
}

proc fontchooserFontSelection {w font args} {
    $w configure -font [font actual $font]
}

# translate % escapes in our command line strings
proc mapPercent {str} {
    global filenames
    global BINFILE
    global ROOTDIR
    global OPT
    global config
    
    set percentmap [ list "%%" "%" "%D" $ROOTDIR "%L" $config(library) "%S" $filenames(.nb.main) "%B" $BINFILE "%O" $OPT ]
    set result [string map $percentmap $str]
    return $result
}

### utility: make a window read only
proc makeReadOnly {hWnd} {
# Disable all key sequences for widget named in variable hWnd, except
# the cursor navigation keys (regardless of the state ctrl/shift/etc.)
# and Ctrl-C (Copy to Clipboard).
    # from ActiveState Code >> Recipes
    
bind $hWnd <KeyPress> {
    switch -- %K {
        "Up" -
        "Left" -
        "Right" -
        "Down" -
        "Next" -
        "Prior" -
        "Home" -
        "End" {
        }

	"f" -
	"F" -
        "c" -
        "C" {
            if {(%s & 0x04) == 0} {
                break
            }
        }

        default {
            break
        }
    }
}

# Addendum: also a good idea disable the cut and paste events.

bind $hWnd <<Paste>> "break"
bind $hWnd <<Cut>> "break"
}

### utility: compile the program

proc doCompile {} {
    global config
    global BINFILE
    global filenames
    
    set status 0
    saveSpinFile
    set cmdstr [mapPercent $config(compilecmd)]
    set runcmd [list exec -ignorestderr]
    set runcmd [concat $runcmd $cmdstr]
    lappend runcmd 2>@1
    if {[catch $runcmd errout options]} {
	set status 1
    }
    .bot.txt replace 1.0 end "$cmdstr\n"
    .bot.txt insert 2.0 $errout
    tagerrors .bot.txt
    if { $status != 0 } {
	tk_messageBox -icon error -type ok -message "Compilation failed" -detail "see compiler output window for details"
	set BINFILE ""
    } else {
	set BINFILE [file rootname $filenames(.nb.main)]
	set BINFILE "$BINFILE.binary"
	# load the listing if a listing window is open
	if {[winfo exists .list]} {
	    doListing
	}
    }
    return $status
}

proc doListing {} {
    global filenames
    set LSTFILE [file rootname $filenames(.nb.main)]
    set LSTFILE "$LSTFILE.lst"
    loadFileForBrowse .nb.list $LSTFILE Listing
    makeReadOnly .nb.list
}

proc doJustRun {} {
    global config
    global BINFILE
    
    set cmdstr [mapPercent $config(runcmd)]
    .bot.txt insert end "$cmdstr\n"

    set runcmd [list exec -ignorestderr]
    set runcmd [concat $runcmd $cmdstr]
    lappend runcmd "&"

    if {[catch $runcmd errout options]} {
	.bot.txt insert 2.0 $errout
	tagerrors .bot.txt
    }
}

proc doLoadRun {} {
    global config
    global BINFILE
    global BinTypes
    
    set filename [tk_getOpenFile -filetypes $BinTypes -initialdir $config(lastdir)]
    if { [string length $filename] == 0 } {
	return
    }
    set BINFILE $filename
    .bot.txt delete 1.0 end
    doJustRun
}

proc doCompileRun {} {
    set status [doCompile]
    if { $status eq 0 } {
	.bot.txt insert end "\n"
	doJustRun
    }
}

set cmddialoghelptext {
  Strings for various commands
  Some special % escapes:
    %D = Replace with directory of spin2gui executable  
    %S = Replace with current Spin file name
    %B = Replace with current binary file name
    %O = Replace with optimization level
    %% = Insert a % character
}
proc copyShadowClose {w} {
    copyShadowToConfig
    wm withdraw $w
}

proc doRunOptions {} {
    global config
    global shadow
    global cmddialoghelptext
    
    set shadow(compilecmd) $config(compilecmd)
    set shadow(runcmd) $config(runcmd)
    
    if {[winfo exists .runopts]} {
	if {![winfo viewable .runopts]} {
	    wm deiconify .runopts
	    set shadow(compilecmd) $config(compilecmd)
	    set shadow(runcmd) $config(runcmd)
	}
	raise .runopts
	return
    }

    toplevel .runopts
    label .runopts.toplabel -text $cmddialoghelptext
    ttk::labelframe .runopts.a -text "Compile command"
    entry .runopts.a.compiletext -width 32 -textvariable shadow(compilecmd)

    ttk::labelframe .runopts.b -text "Run command"
    entry .runopts.b.runtext -width 32 -textvariable shadow(runcmd)

    frame .runopts.change
    frame .runopts.end

    button .runopts.change.p2 -text "P2 defaults" -command setShadowP2Defaults
    button .runopts.change.p1 -text "P1 defaults" -command setShadowP1Defaults
    
    button .runopts.end.ok -text " OK " -command {copyShadowClose .runopts}
    button .runopts.end.cancel -text " Cancel " -command {wm withdraw .runopts}
    
    grid .runopts.toplabel
    grid .runopts.a
    grid .runopts.b
    grid .runopts.change
    grid .runopts.end
    
    grid .runopts.a.compiletext
    grid .runopts.b.runtext

    grid .runopts.change.p2 .runopts.change.p1
    grid .runopts.end.ok .runopts.end.cancel
    
    wm title .runopts "Executable Paths"
}

#
# simple search and replace widget by Richard Suchenwirth, from wiki.tcl.tk
#
proc searchrep {t {replace 1}} {
   set w .sr
   if ![winfo exists $w] {
       toplevel $w
       wm title $w "Search"
       grid [label $w.1 -text Find:] [entry $w.f -textvar Find] \
               [button $w.bn -text Next \
               -command [list searchrep'next $t]] -sticky ew
       bind $w.f <Return> [list $w.bn invoke]
       if $replace {
           grid [label $w.2 -text Replace:] [entry $w.r -textvar Replace] \
                   [button $w.br -text Replace \
                   -command [list searchrep'rep1 $t]] -sticky ew
           bind $w.r <Return> [list $w.br invoke]
           grid x x [button $w.ba -text "Replace all" \
                   -command [list searchrep'all $t]] -sticky ew
       }
       grid x [checkbutton $w.i -text "Ignore case" -variable IgnoreCase] \
               [button $w.c -text Cancel -command "destroy $w"] -sticky ew
       grid $w.i -sticky w
       grid columnconfigure $w 1 -weight 1
       $t tag config hilite -background yellow
       focus $w.f
   } else {
       raise $w.f
       focus $w
   }
}

# Find the next instance
proc searchrep'next w {
    foreach {from to} [$w tag ranges hilite] {
        $w tag remove hilite $from $to
    }
    set cmd [list $w search -count n -- $::Find insert+2c]
    if $::IgnoreCase {set cmd [linsert $cmd 2 -nocase]}
    set pos [eval $cmd]
    if {$pos ne ""} {
        $w mark set insert $pos
        $w see insert
        $w tag add hilite $pos $pos+${n}c
    }
}

# Replace the current instance, and find the next
proc searchrep'rep1 w {
    if {[$w tag ranges hilite] ne ""} {
        $w delete insert insert+[string length $::Find]c
        $w insert insert $::Replace
        searchrep'next $w
        return 1
    } else {return 0}
}

# Replace all
proc searchrep'all w {
    set go 1
    while {$go} {set go [searchrep'rep1 $w]}
}

# main code
setHighlightingSpin .nb.main.txt


if { $::argc > 0 } {
    loadFileToWindow $argv .nb.main.txt
} else {
    set filenames(.nb.main) ""
}
