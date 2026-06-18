-- Session restore for the M-E micro popup: record the open tabs keyed by the
-- launch directory, so micro-session.sh reopens them all per-directory on next
-- launch (micro has no native session restore). Persisted via micro-lastfile.sh
-- into a per-dir store under ~/.cache/micro/.
local os = import("os")
local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")
local util = import("micro/util")

local lastfileScript = os.Getenv("HOME") .. "/.local/bin/micro-lastfile.sh"

-- Record the full set of open tabs (one path per line) for the launch directory
-- so micro-session.sh reopens every tab next time. forcePath ensures a buffer is
-- included even if micro.Tabs() hasn't registered its tab yet (onBufferOpen fires
-- before the tab is fully wired). Unnamed/empty buffers are skipped; an empty list
-- clears the store.
local function recordSession(forcePath)
    local cwd = os.Getwd() or ""
    if cwd == "" then
        return
    end
    local seen, files = {}, {}
    local tabs = micro.Tabs()
    if tabs ~= nil then
        for i = 1, #tabs.List do
            local pane = tabs.List[i]:CurPane()
            local p = (pane ~= nil) and pane.Buf.AbsPath or ""
            if p ~= "" and not seen[p] then
                seen[p] = true
                files[#files + 1] = p
            end
        end
    end
    if forcePath ~= nil and forcePath ~= "" and not seen[forcePath] then
        files[#files + 1] = forcePath
    end
    if #files == 0 then
        return -- nothing real is open; leave any prior session intact, don't wipe it
    end
    shell.ExecCommand(lastfileScript, "set", cwd, table.concat(files, "\n"))
end

function onBufferOpen(buf)
    recordSession(buf.AbsPath)
end

function onSetActive(bp)
    recordSession(bp.Buf.AbsPath)
end

-- Telescope-style fuzzy finders: Ctrl-P = files, Ctrl-G = live grep.
-- All fzf/rg logic lives in micro-fzf.sh; here we run it (micro suspends the
-- screen so fzf owns the terminal), then open the selection.
local fzfScript = os.Getenv("HOME") .. "/.local/bin/micro-fzf.sh"

-- Strip ANSI SGR codes (rg --color=always) and any trailing newline.
local function fzfClean(s)
    s = s:gsub("\27%[[0-9;]*m", "")
    return (s:gsub("%s+$", ""))
end

-- Open file in the current pane, jumping to the 1-indexed line/col when given.
local function fzfOpen(file, line, col)
    if file == nil or file == "" then
        return
    end
    local buf, err = buffer.NewBufferFromFile(file)
    if err ~= nil then
        micro.InfoBar():Error("micro-fzf: cannot open " .. file)
        return
    end
    micro.CurPane():OpenBuffer(buf)
    local l = tonumber(line)
    if l ~= nil then
        local c = tonumber(col) or 1
        buf:GetActiveCursor():GotoLoc(buffer.Loc(c - 1, l - 1))
        micro.CurPane():Relocate()
    end
    -- onBufferOpen fired during NewBufferFromFile above, before OpenBuffer swapped
    -- the file into the pane, so it recorded the file we just replaced (the pane
    -- still showed it) via forcePath. Re-record now the swap is done to drop it.
    recordSession()
end

function fzfFiles(bp)
    local out, err = shell.RunInteractiveShell(fzfScript .. " files", false, true)
    if err == nil then
        fzfOpen(fzfClean(out))
    end
end

function fzfGrep(bp)
    local out, err = shell.RunInteractiveShell(fzfScript .. " grep", false, true)
    if err ~= nil then
        return
    end
    out = fzfClean(out)
    if out == "" then
        return
    end
    local file, line, col = string.match(out, "^(.-):(%d+):(%d+):")
    if file == nil then
        file, line = string.match(out, "^(.-):(%d+):")
    end
    fzfOpen(file, line, col)
end

-- Ctrl-B: yazi file browser. Like the fzf finders, micro suspends its screen so
-- yazi owns the terminal; yazi runs in chooser mode (see micro-yazi.sh) and emits
-- the chosen path(s), one per line. Open the first selection in the current pane,
-- mirroring the file finder; fzfOpen no-ops on an empty pick (quit without choosing).
local yaziScript = os.Getenv("HOME") .. "/.local/bin/micro-yazi.sh"

function yaziBrowse(bp)
    local out, err = shell.RunInteractiveShell(yaziScript, false, true)
    if err ~= nil then
        return
    end
    fzfOpen(fzfClean(out):match("^[^\n]*"))
end

-- The built-in linter runs `g++ -fsyntax-only -Wall -Wextra` with no -std, so
-- valid C++23 (std::views::enumerate/adjacent) is falsely flagged as errors.
-- Re-register the g++ linter at -std=c++23 to match how the projects build.
local function fixCppLinter()
    if linter == nil then
        return
    end
    linter.removeLinter("g++")
    linter.makeLinter("g++", "c++", "g++",
        {"-std=c++23", "-fsyntax-only", "-Wall", "-Wextra", "%f"},
        "%f:%l:%c:.+: %m")
end

-- VSCode-style multi-cursor paste. When the clipboard's line count equals the
-- number of cursors, each cursor gets its own line ("spread"); otherwise defer
-- to micro's default (whole clipboard at every cursor). micro has no setting for
-- this and doesn't expose the clipboard to Lua, so we read it via xclip; any
-- error falls back to the default paste, so non-Linux/no-xclip is a no-op.
local function clipboardLines()
    local out, err = shell.ExecCommand("xclip", "-selection", "clipboard", "-o")
    if err ~= nil then
        return nil
    end
    out = out:gsub("\r", ""):gsub("\n$", "")
    local lines = {}
    for line in (out .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

-- All cursors in document order (top-to-bottom, left-to-right).
local function sortedCursors(buf)
    local cs = {}
    for i = 0, buf:NumCursors() - 1 do
        cs[#cs + 1] = buf:GetCursor(i)
    end
    table.sort(cs, function(a, b)
        if a.Y ~= b.Y then
            return a.Y < b.Y
        end
        return a.X < b.X
    end)
    return cs
end

local function spreadPaste(bp)
    local buf = bp.Buf
    local n = buf:NumCursors()
    if n <= 1 then
        return true
    end
    local lines = clipboardLines()
    if lines == nil or #lines ~= n then
        return true
    end
    local cs = sortedCursors(buf)
    -- Edit bottom-to-top so earlier inserts don't shift later cursor locations.
    for i = n, 1, -1 do
        local c = cs[i]
        if c:HasSelection() then
            c:DeleteSelection()
            c:ResetSelection()
        end
        buf:Insert(buffer.Loc(c.X, c.Y), lines[i])
    end
    return false
end

-- VSCode-style whole-line paste. Ctrl-c with nothing selected runs CopyLine,
-- putting the line plus its trailing newline on the clipboard; micro's default
-- paste then dumps that at the cursor column, splitting the line you're on.
-- Instead, when the last copy/cut was a whole-line one, drop the line in below
-- the current line (like duplicating it). Re-reads the clipboard as a guard: if
-- you copied something else since (in micro or another app) the stored text no
-- longer matches and we defer to the normal paste.
local lineClip = nil -- text of the last whole-line copy/cut; nil = not a line

-- Remember the current line as a whole-line copy. Single cursor only; multi-
-- cursor copies stay with the spread-paste path above.
local function recordLineCopy(bp)
    if bp.Buf:NumCursors() ~= 1 then
        lineClip = nil
        return
    end
    lineClip = bp.Buf:Line(bp.Buf:GetActiveCursor().Y)
end

-- Insert the remembered line below the current one. Returns false to cancel the
-- default paste, true to defer to it.
local function linePaste(bp)
    if lineClip == nil then
        return true
    end
    local buf = bp.Buf
    if buf:NumCursors() ~= 1 then
        return true
    end
    local c = buf:GetActiveCursor()
    if c:HasSelection() then
        return true -- pasting over a selection: let the default replace it
    end
    local clip = clipboardLines()
    if clip == nil or #clip ~= 1 or clip[1] ~= lineClip then
        return true -- clipboard changed since the line copy
    end
    local x, y = c.X, c.Y
    local endX = util.CharacterCountInString(buf:Line(y))
    buf:Insert(buffer.Loc(endX, y), "\n" .. lineClip)
    local col = math.min(x, util.CharacterCountInString(lineClip))
    c:GotoLoc(buffer.Loc(col, y + 1))
    micro.CurPane():Relocate()
    return false
end

-- prePaste returning false cancels micro's default paste.
function prePaste(bp)
    local ok, defer = pcall(spreadPaste, bp)
    if not ok then
        return true
    end
    if not defer then
        return false -- multi-cursor spread paste handled it
    end
    ok, defer = pcall(linePaste, bp)
    if not ok then
        return true
    end
    return defer
end

-- micro joins a multi-cursor copy with no separator ("AAABBBCCC"), so pasting it
-- elsewhere — or at a single cursor — mashes the pieces together. Write our own
-- newline-joined version to the clipboard so each selection is its own line
-- (round-trips through the spread paste above, and pastes cleanly into any app).
local function writeClipboard(text)
    local path = os.Getenv("HOME") .. "/.cache/micro/.mcclip"
    local f, err = os.Create(path)
    if err ~= nil then
        return
    end
    f:WriteString(text)
    f:Close()
    shell.ExecCommand("xclip", "-selection", "clipboard", path)
end

local function rejoinMultiCopy(bp)
    local buf = bp.Buf
    local n = buf:NumCursors()
    if n <= 1 then
        return
    end
    local cs = sortedCursors(buf)
    local parts = {}
    for i = 1, n do
        local sel = cs[i]:GetSelection()
        if type(sel) ~= "string" then
            sel = util.String(sel)
        end
        parts[#parts + 1] = sel
    end
    writeClipboard(table.concat(parts, "\n"))
end

-- Runs after micro's own copy; rewrites the clipboard newline-joined.
function onCopy(bp)
    lineClip = nil -- a selection copy is not a whole-line copy
    pcall(rejoinMultiCopy, bp)
    return true
end

-- Whole-line copy/cut recorders for the line paste above. CopyLine restores the
-- cursor onto the copied line so we read it afterwards; CutLine removes the line
-- so we read it beforehand. A selection cut clears the flag, mirroring onCopy.
function onCopyLine(bp) pcall(recordLineCopy, bp) end
function preCutLine(bp) pcall(recordLineCopy, bp) end
function onCut(bp) lineClip = nil end

-- Cursor jump history (browser-style AltLeft / AltRight). micro has no jump
-- list, so we build one: before every "big jump" action (paging, half-page,
-- top/bottom of file, goto-line, search, jump-to-definition, tab switch, fzf
-- grep open) we push the location being left onto a back-stack. AltLeft walks
-- back through it, AltRight forward. Entries store the file path, so a jump can
-- cross tabs — AltLeft re-activates the tab holding that file (reopening it in
-- the current pane only if its tab was since closed). Plain cursor moves and
-- typing are deliberately NOT recorded, so back-steps land on real jumps, not
-- adjacent lines. Both stacks are depth-capped.
local JUMP_DEPTH = 30
local jbBack = {}          -- locations to go back to (newest last)
local jbForward = {}       -- locations to go forward to (newest last)
local jbNavigating = false -- guard: don't record while we jump programmatically

local function jbLoc(bp)
    local c = bp.Buf:GetActiveCursor()
    return { path = bp.Buf.AbsPath, x = c.X, y = c.Y }
end

local function jbSameLine(a, b)
    return a ~= nil and b ~= nil and a.path == b.path and a.y == b.y
end

local function jbPush(stack, loc)
    stack[#stack + 1] = loc
    if #stack > JUMP_DEPTH then
        table.remove(stack, 1)
    end
end

-- Record the position about to be left. Called from the pre<Action> hooks below.
local function jbRecord(bp)
    if jbNavigating then
        return
    end
    local loc = jbLoc(bp)
    if loc.path == nil or loc.path == "" then
        return
    end
    jbForward = {}                            -- a fresh jump abandons forward
    if jbSameLine(jbBack[#jbBack], loc) then  -- coalesce repeats on the same line
        return
    end
    jbPush(jbBack, loc)
end

-- Move the active view to loc, switching tabs when it lives in another one.
-- Falls back to reopening the file in the current pane if it isn't open anywhere.
local function jbGoto(loc)
    local cur = micro.CurPane()
    if cur ~= nil and cur.Buf.AbsPath == loc.path then
        cur.Buf:GetActiveCursor():GotoLoc(buffer.Loc(loc.x, loc.y))
        cur:Relocate()
        return true
    end
    local tabs = micro.Tabs()
    for i = 1, #tabs.List do                  -- List is 1-based in Lua,
        local pane = tabs.List[i]:CurPane()
        if pane ~= nil and pane.Buf.AbsPath == loc.path then
            tabs:SetActive(i - 1)             -- but SetActive is 0-based
            pane.Buf:GetActiveCursor():GotoLoc(buffer.Loc(loc.x, loc.y))
            pane:Relocate()
            return true
        end
    end
    local buf, err = buffer.NewBufferFromFile(loc.path)
    if err ~= nil then
        return false
    end
    micro.CurPane():OpenBuffer(buf)
    buf:GetActiveCursor():GotoLoc(buffer.Loc(loc.x, loc.y))
    micro.CurPane():Relocate()
    recordSession() -- reopened a closed file in this pane; refresh session (see fzfOpen)
    return true
end

function jumpBack(bp)
    if #jbBack == 0 then
        micro.InfoBar():Message("Jump history: oldest")
        return true
    end
    local here = jbLoc(bp)
    jbNavigating = true
    if jbGoto(jbBack[#jbBack]) then
        jbBack[#jbBack] = nil
        if not jbSameLine(jbForward[#jbForward], here) then
            jbPush(jbForward, here)
        end
    end
    jbNavigating = false
    return true
end

function jumpForward(bp)
    if #jbForward == 0 then
        micro.InfoBar():Message("Jump history: newest")
        return true
    end
    local here = jbLoc(bp)
    jbNavigating = true
    if jbGoto(jbForward[#jbForward]) then
        jbForward[#jbForward] = nil
        if not jbSameLine(jbBack[#jbBack], here) then
            jbPush(jbBack, here)
        end
    end
    jbNavigating = false
    return true
end

-- F12: record where we are, then hand off to the LSP definition command.
function jumpToDefinition(bp)
    jbRecord(bp)
    bp:HandleCommand("definition")
    return true
end

-- pre<Action> recorders — micro calls these by name right before each action.
function preCursorPageUp(bp)   jbRecord(bp) end
function preCursorPageDown(bp) jbRecord(bp) end
function preHalfPageUp(bp)     jbRecord(bp) end
function preHalfPageDown(bp)   jbRecord(bp) end
function preCursorStart(bp)    jbRecord(bp) end
function preCursorEnd(bp)      jbRecord(bp) end
function preJumpLine(bp)       jbRecord(bp) end
function preFind(bp)           jbRecord(bp) end
function preFindNext(bp)       jbRecord(bp) end
function preFindPrevious(bp)   jbRecord(bp) end
function preNextTab(bp)        jbRecord(bp) end
function prePreviousTab(bp)    jbRecord(bp) end

function init()
    config.MakeCommand("findfiles", fzfFiles, config.NoComplete)
    config.MakeCommand("livegrep", fzfGrep, config.NoComplete)
    config.MakeCommand("browse", yaziBrowse, config.NoComplete)
    fixCppLinter()
    -- Runs after InitTabs, so micro.Tabs() is populated: capture every tab opened
    -- at startup (onBufferOpen fires too early — before the tab list exists).
    recordSession()
end
