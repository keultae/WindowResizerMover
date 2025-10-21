; ==============================
; Window Resizer & Mover (AHK v2)
; Ctrl + Alt + Win + B  : 팝업 열기/다시 열기
; Ctrl + LeftClick      : 팝업 열기 (기본 클릭 동작 유지)
; Ctrl + Alt + Win + L  : 로그창 토글
; Ctrl + Alt + Win + C  : 로그 비우기
; ==============================

#Requires AutoHotkey v2.0
Persistent

global g_gui := 0
global g_targetHwnd := 0
global g_sizeSel := "CURRENT"
global g_locSel := "TopCenter"

; 로그 GUI 상태
global g_logGui := 0
global g_logEdit := 0
global g_logShown := false

; ---- 단축키 ----
^!#b::ShowPicker()
~^LButton::ShowPicker()   ; 기본 클릭 유지. 막고 싶다면 ~ 제거해서 ^LButton::ShowPicker()
^!#l::ToggleLog()
^!#c::ClearLog()

; ==============================
; 로그 유틸 (내장 콘솔)
; ==============================
EnsureLogGui() {
    global g_logGui, g_logEdit, g_logShown
    if IsObject(g_logGui)
        return
    g_logGui := Gui("+AlwaysOnTop +Resize", "Window Resizer & Mover - Log")
    g_logGui.OnEvent("Close", (*) => (g_logGui.Hide(), g_logShown := false))

    ; 로그 에디트
    g_logEdit := g_logGui.AddEdit("xm ym w620 h380 ReadOnly -Wrap +WantCtrlA vLogEdit")
    ; ✅ SetFont는 옵션과 폰트명을 분리 인자로 전달
    g_logEdit.SetFont("s10", "Consolas")

    ; 버튼들
    g_logGui.AddButton("xm y+6 w80", "Close").OnEvent("Click", (*) => (g_logGui.Hide(), g_logShown := false))
    g_logGui.AddButton("x+10 w80", "Clear").OnEvent("Click", (*) => ClearLog())
    ; 처음엔 표시하지 않음 (ToggleLog로 제어)
}

ShowLog() {
    global g_logGui, g_logShown
    EnsureLogGui()
    g_logGui.Show("AutoSize")
    g_logShown := true
}
HideLog() {
    global g_logGui, g_logShown
    if IsObject(g_logGui) {
        g_logGui.Hide()
        g_logShown := false
    }
}
ToggleLog() {
    global g_logShown
    if g_logShown
        HideLog()
    else
        ShowLog()
}
ClearLog() {
    global g_logEdit
    EnsureLogGui()
    g_logEdit.Value := ""
}
Log(msg) {
    global g_logEdit
    EnsureLogGui()
    ts := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    line := ts "  " msg
    g_logEdit.Value := (g_logEdit.Value ? g_logEdit.Value "`r`n" : "") line
    OutputDebug line
}

; ==============================
; 메인 GUI
; ==============================
ShowPicker() {
    global g_gui, g_targetHwnd, g_sizeSel, g_locSel

    ; 대상 창: 팝업 띄우기 직전 활성 창
    g_targetHwnd := WinExist("A")

    if IsObject(g_gui)
        try g_gui.Destroy()

    g_gui := Gui("+AlwaysOnTop +ToolWindow", "Window Resizer & Mover")
    g_gui.MarginX := 12, g_gui.MarginY := 10

    ; 제목
    titleCtl := g_gui.AddText("w560 Center cWhite BackgroundTrans", "Window Resizer & Mover")
    titleCtl.SetFont("s12 Bold")

    ; Size
    g_gui.AddText("xm ym+28 cCCCCCC", "Size:")
    rSize := []
    x0 := 20, y0 := 55, gapX := 85

    sizesRow1 := ["CURRENT","HD","FHD","QHD","UHD"]
    for index, lbl in sizesRow1 {
        opt := (index=1 ? "Checked" : "")
        r := g_gui.AddRadio(Format("x{1} y{2} {3}", x0+(index-1)*gapX, y0, opt), lbl)
        r.OnEvent("Click", SizeChanged)   ; 클릭시 적용 금지(OK에서만 적용)
        rSize.Push(r)
    }

    y1 := y0 + 28
    sizesRow2 := ["2x2","3x3","4x4"]
    for index, lbl in sizesRow2 {
        r := g_gui.AddRadio(Format("x{1} y{2}", x0+(index-1)*gapX, y1), lbl)
        r.OnEvent("Click", SizeChanged)
        rSize.Push(r)
    }

    y2 := y1 + 28
    sizesRow3 := ["1x2","1x3","2x1","3x1"]
    for index, lbl in sizesRow3 {
        r := g_gui.AddRadio(Format("x{1} y{2}", x0+(index-1)*gapX, y2), lbl)
        r.OnEvent("Click", SizeChanged)
        rSize.Push(r)
    }

    ; Location
    g_gui.AddText("xm y+20 cCCCCCC", "Location:")
    locX0 := 20, locY0 := y2 + 60, locGapX := 120, locGapY := 26
    locGrid := [
        ["TopLeft","TopCenter","TopRight"],
        ["CenterLeft","CenterCenter","CenterRight"],
        ["BottomLeft","BottomCenter","BottomRight"]
    ]
    rLoc := Map()
    for row, cols in locGrid {
        for colIndex, lbl in cols {
            opt := (lbl="TopCenter" ? "Checked" : "")
            r := g_gui.AddRadio(Format("x{1} y{2} {3}", locX0+(colIndex-1)*locGapX, locY0+(row-1)*locGapY, opt), lbl)
            r.OnEvent("Click", LocChanged) ; 클릭시 적용 금지(OK에서만 적용)
            rLoc[lbl] := r
        }
    }

    ; 버튼
    btnY := locY0 + 3*locGapY + 20
    btnOk := g_gui.AddButton(Format("x{1} y{2} w100 h28", 340, btnY), "Ok")
    btnCancel := g_gui.AddButton(Format("x{1} y{2} w100 h28", 450, btnY), "Cancel")
    btnOk.OnEvent("Click", ApplyAndClose)
    btnCancel.OnEvent("Click", CancelAndClose)

    ; 초기 선택값
    g_sizeSel := "CURRENT"
    g_locSel := "TopCenter"

    ; ----- 커서가 있는 모니터 중앙에 표시 -----
    CoordMode "Mouse", "Screen"
    MouseGetPos &mx, &my
    mon := GetMonitorForPoint(mx, my)
    if !mon
        mon := GetMonitorForWindow(g_targetHwnd)
    if !mon
        mon := GetMonitorByIndex(1)

    g_gui.Show("AutoSize Hide")
    g_gui.GetPos(&gx, &gy, &gw, &gh)
    if mon {
        monX := mon["left"], monY := mon["top"]
        monW := mon["right"] - mon["left"]
        monH := mon["bottom"] - mon["top"]
        nx := monX + (monW - gw) // 2
        ny := monY + (monH - gh) // 2
        g_gui.Show("x" nx " y" ny)
    } else {
        g_gui.Show("Center")
    }

    SizeChanged(*) {
        for r in rSize {
            if r.Value {
                g_sizeSel := r.Text
                break
            }
        }
        Log("[Pick] Size=" g_sizeSel)
    }
    LocChanged(ctrl, *) {
        g_locSel := ctrl.Text
        Log("[Pick] Location=" g_locSel)
    }
}

CancelAndClose(*) {
    global g_gui
    if IsObject(g_gui)
        try g_gui.Destroy()
}

ApplyAndClose(*) {
    global g_gui, g_targetHwnd, g_sizeSel, g_locSel
    if !g_targetHwnd || !WinExist("ahk_id " g_targetHwnd) {
        MsgBox "대상 창을 찾을 수 없습니다."
        CancelAndClose()
        return
    }
    Log("[OK] Size=" g_sizeSel ", Location=" g_locSel)
    ApplySizeAndLocation(g_sizeSel, g_locSel, g_targetHwnd)
    CancelAndClose()
}

; ==============================
; 적용 로직
; ==============================
ApplySizeAndLocation(sizeKey, locKey, hwnd) {
    ; 지역 변수로 충돌 방지
    local colsVar := 1, rowsVar := 1, w := 0, h := 0, x := 0, y := 0

    mon := GetMonitorForWindow(hwnd)
    if !mon
        mon := GetMonitorByIndex(1)
    if !mon
        return

    WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
    monX := mon["left"], monY := mon["top"]
    monW := mon["right"] - mon["left"]
    monH := mon["bottom"] - mon["top"]

    ; ---- Size 계산 ----
    if (sizeKey = "CURRENT") {
        w := ww, h := wh
        Log("[Apply] CURRENT size 유지")
    } else {
        abs := Map("HD",[1280,720], "FHD",[1920,1080], "QHD",[2560,1440], "UHD",[3840,2160])
        if abs.Has(sizeKey) {
            w := abs[sizeKey][1], h := abs[sizeKey][2]
        } else if RegExMatch(sizeKey, "i)^\s*(\d+)x(\d+)\s*$", &mx) {
            Log(Format("monW={1}, monH={2}, w={3}, h={4}", monW, monH, w, h))
            Log(Format("mx[1]={1}, mx[2]={2}", mx[1], mx[2]))
            colsVar := Integer(mx[1])
            rowsVar := Integer(mx[2])
            Log(Format("1 colsVar={1}, rowsVar={2}", colsVar, rowsVar))
            ; 1xN / Nx1 스왑 (요청 로직)
            if (colsVar = 1 || rowsVar = 1) {
                tmp := colsVar, colsVar := rowsVar, rowsVar := tmp
            }
            Log(Format("2 colsVar={1}, rowsVar={2}", colsVar, rowsVar))
            if (colsVar < 1)
              colsVar := 1
            if (rowsVar < 1)
              rowsVar := 1
            Log(Format("3 colsVar={1}, rowsVar={2}", colsVar, rowsVar))
            w := Floor(monW / colsVar)
            h := Floor(monH / rowsVar)
        } else {
            w := ww, h := wh
        }
        ; 모니터보다 크면 클램프 (여분의 } 없음)
        if (w > monW)
            w := monW
        if (h > monH)
            h := monH
    }

    ; ---- Location 계산 (대소문자 보존 + prefix/suffix 매칭) ----
    ; locKey 예: "TopLeft", "BottomCenter", "CenterRight" ...
    ; 공백/언더스코어만 제거하고 대소문자는 유지
    cleanLoc := StrReplace(StrReplace(Trim(locKey), " ", ""), "_", "")
    Log(Format("locKey={1}, cleanLoc={2}", locKey, cleanLoc))

    ; x축: 문자열의 시작이 Left|Center|Right ?
    xTok := ""
    if RegExMatch(cleanLoc, "(Left|Center|Right)$", &mx)
        xTok := mx[1]

    ; y축: 문자열의 끝이 Top|Center|Bottom ?
    yTok := ""
    if RegExMatch(cleanLoc, "^(Top|Center|Bottom)", &my)
        yTok := my[1]

    ; 토큰 기본값 (이전 기본과 동일: x=Center, y=Top)
    if !xTok
        xTok := "Center"
    if !yTok
        yTok := "Top"

    Log(Format("xTok={1}, yTok={2}", xTok, yTok))

    ; x 좌표
    switch xTok {
        case "Left":
            x := monX
            Log(Format("1. Left  x={1}", x))
        case "Center":
            x := monX + Floor((monW - w) / 2)
            Log(Format("2. Center x={1}", x))
        case "Right":
            x := monX + (monW - w)
            Log(Format("3. Right x={1}", x))
    }

    ; y 좌표
    switch yTok {
        case "Top":
            y := monY
            Log(Format("4. Top    y={1}", y))
        case "Center":
            y := monY + Floor((monH - h) / 2)
            Log(Format("5. Center y={1}", y))
        case "Bottom":
            y := monY + (monH - h)
            Log(Format("6. Bottom y={1}", y))
    }


    ; 적용: 최대화/스냅 해제 후 이동/리사이즈
    try WinRestore "ahk_id " hwnd
    WinMove x, y, w, h, "ahk_id " hwnd
    Log(Format("[Apply] MOVE -> x={1}, y={2}, w={3}, h={4}", x, y, w, h))
}

; ==============================
; 모니터 유틸
; ==============================
GetMonitorForPoint(px, py) {
    monCount := MonitorGetCount()
    loop monCount {
        i := A_Index
        MonitorGetWorkArea i, &l, &t, &r, &b
        if (px >= l && px <= r && py >= t && py <= b)
            return Map("left",l, "top",t, "right",r, "bottom",b)
    }
    return 0
}

GetMonitorForWindow(hwnd) {
    WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    cx := x + w//2
    cy := y + h//2
    monCount := MonitorGetCount()
    loop monCount {
        i := A_Index
        MonitorGetWorkArea i, &l, &t, &r, &b
        if (cx >= l && cx <= r && cy >= t && cy <= b)
            return Map("left",l, "top",t, "right",r, "bottom",b)
    }
    ; 교차 최대 fallback
    maxArea := -1, best := 0
    loop monCount {
        i := A_Index
        MonitorGetWorkArea i, &l, &t, &r, &b
        inter := IntersectArea(x, y, x+w, y+h, l, t, r, b)
        if (inter > maxArea) {
            maxArea := inter
            best := Map("left",l, "top",t, "right",r, "bottom",b)
        }
    }
    return best
}

GetMonitorByIndex(i) {
    try {
        MonitorGetWorkArea i, &l, &t, &r, &b
        return Map("left",l, "top",t, "right",r, "bottom",b)
    } catch {
        return 0
    }
}

IntersectArea(x1, y1, x2, y2, a1, b1, a2, b2) {
    ix1 := Max(x1, a1), iy1 := Max(y1, b1)
    ix2 := Min(x2, a2), iy2 := Min(y2, b2)
    w := ix2 - ix1, h := iy2 - iy1
    if (w <= 0 || h <= 0)
        return 0
    return w*h
}
