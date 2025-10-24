-- =========================
-- Window Resizer & Mover
-- =========================
-- Window Size/Location Picker (HS 1.0.0 호환)
-- ⌃⌥⌘ + B : 열기/다시 열기
-- OK: 선택 Size/Location 적용(현재 모니터 유지, 패널 열기 직전 창에만)
-- Cancel: 닫기
-- =========================

local sizePicker      -- 캔버스 레퍼런스
local pickerTargetWin -- 패널 열기 직전의 대상 창 보관

-- 공백/특수문자 제거(안전)
local function normalizeKey(s)
  if not s then return nil end
  s = s:gsub("%s+", ""):gsub("[-_]", "")
  return s
end

-- 선택된 Size/Location을 지정 창에 적용
local function applySizeAndLocation(sizeKey, locKey, win)
  if not (win and win:id()) then
    hs.alert.show("대상 창이 없습니다.")
    return
  end
  local sf = win:screen():frame()

  -- Size 결정 (절대/분할)
  local w, h
  if sizeKey == "CURRENT" then
    local f = win:frame()
    w, h = f.w, f.h
  else
    local absMap = {
      HD  = {1280,  720},
      FHD = {1920, 1080},
      QHD = {2560, 1440},
      UHD = {3840, 2160},
    }
    local pair = absMap[sizeKey]
    if pair then
      w, h = pair[1], pair[2]
    else
      -- 분할형: a x b → w/a, h/b  (예: 2x2, 1x3, 3x1 ...)
      local frac = {
        ["2x2"] = {2,2}, ["3x3"] = {3,3}, ["4x4"] = {4,4},
        ["1x2"] = {2,1}, ["1x3"] = {3,1},
        ["2x1"] = {1,2}, ["3x1"] = {1,3},
      }
      local ab = frac[sizeKey]
      if ab then
        local ax, ay = ab[1], ab[2]
        w = math.floor(sf.w / ax)
        h = math.floor(sf.h / ay)
      else
        local f = win:frame(); w, h = f.w, f.h
      end
    end
  end

  -- Location 계산 (Top/Center/Bottom × Left/Center/Right)
  local key = normalizeKey(locKey or ""):lower()
  local anchor = {
    topleft      = function() return sf.x, sf.y end,
    topcenter    = function() return sf.x + math.floor((sf.w - w)/2), sf.y end,
    topright     = function() return sf.x + sf.w - w, sf.y end,

    centerleft   = function() return sf.x, sf.y + math.floor((sf.h - h)/2) end,
    centercenter = function() return sf.x + math.floor((sf.w - w)/2), sf.y + math.floor((sf.h - h)/2) end,
    centerright  = function() return sf.x + sf.w - w, sf.y + math.floor((sf.h - h)/2) end,

    bottomleft   = function() return sf.x, sf.y + sf.h - h end,
    bottomcenter = function() return sf.x + math.floor((sf.w - w)/2), sf.y + sf.h - h end,
    bottomright  = function() return sf.x + sf.w - w, sf.y + sf.h - h end,
  }
  local fn = anchor[key] or anchor.topcenter
  local x, y = fn()

  -- 디버그 출력
  hs.openConsole()
  print(string.format("[Window Resizer & Mover] APPLY -> Size=%s (%dx%d), Location=%s, x=%d, y=%d",
    tostring(sizeKey), w, h, tostring(locKey), x, y))

  -- 적용
  win:setFrame({x = x, y = y, w = w, h = h})
end

-- UI
local function showPicker()
  if sizePicker then sizePicker:delete(); sizePicker = nil end

  -- 패널 생성 직전의 대상 창 캡처(Hammerspoon/콘솔이면 제외)
  local fw = hs.window.frontmostWindow()
  if fw and fw:application() and fw:application():name() == "Hammerspoon" then
    pickerTargetWin = nil
  else
    pickerTargetWin = fw
  end

  local screen = hs.screen.mainScreen()
  local sf = screen:fullFrame()

  -- 레이아웃 상수
  local GAP, PAD, BTN_R = 10, 12, 10
  local TITLEBAR_H      = 40   -- 상단 제목 영역
  local SIZE_ROW_H      = 38
  local TITLE_H         = 22
  local GRID_ROW_H      = 34
  local GRID_ROWS       = 3
  local GRID_TOTAL_H    = TITLE_H + GAP + GRID_ROW_H*GRID_ROWS
  local BAR_H           = 46

  local CANVAS_W = 640
  local CANVAS_H = TITLEBAR_H
                  + PAD + TITLE_H + GAP + SIZE_ROW_H     -- Size 1행
                  + 6 + SIZE_ROW_H                       -- Size 2행
                  + 6 + SIZE_ROW_H                       -- Size 3행
                  + GAP + GRID_TOTAL_H                   -- Location
                  + GAP + BAR_H + PAD                    -- Buttons

  local frame = {
    x = sf.x + (sf.w - CANVAS_W)/2,
    y = sf.y + (sf.h - CANVAS_H)/2,
    w = CANVAS_W, h = CANVAS_H
  }

  local cv = hs.canvas.new(frame)
    :level(hs.canvas.windowLevels.floating)
    :behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)

  -- 인덱스 & 맵
  local z = 1
  local function add(el) cv[z] = el; z = z + 1; return (z-1) end
  local idToIdx = {}

  -- Size 라디오 옵션 (세 줄 구성)
  local selectedSize = "CURRENT"
  local sizeRow1 = { "CURRENT", "HD", "FHD", "QHD", "UHD" }
  local sizeRow2 = { "2x2", "3x3", "4x4" }
  local sizeRow3 = { "1x2", "1x3", "2x1", "3x1" }

  -- Location 라디오 옵션
  local selectedLoc = "TopCenter"
  local locGrid = {
    {"TopLeft",    "TopCenter",    "TopRight"},
    {"CenterLeft", "CenterCenter", "CenterRight"},
    {"BottomLeft", "BottomCenter", "BottomRight"},
  }

  -- 라디오 생성기 (HS 1.0.0: alpha는 fillColor 내부에서 토글)
  local function radioAdd(x, y, label, groupPrefix, isSelected)
    local r = 16
    local cx, cy = x + r/2, y + r/2
    local center = {x=cx, y=cy}
    local hitId  = groupPrefix.."_"..label.."_hit"
    local dotId  = groupPrefix.."_"..label.."_dot"
    local lblId  = groupPrefix.."_"..label.."_label"
    local outerId= groupPrefix.."_"..label.."_outer"

    local hitIdx = add({
      id = hitId, type="rectangle", action="fill",
      fillColor={alpha=0}, frame={x=x-4, y=y-8, w=200, h=r+16},
      trackMouseEnterExit=true, trackMouseDown=true, trackMouseUp=true,
    }); idToIdx[hitId] = hitIdx

    idToIdx[outerId] = add({
      id=outerId, type="circle", action="stroke",
      strokeColor={hex="#777777", alpha=1}, strokeWidth=1.2,
      center=center, radius=r/2,
    })

    local dotIdx = add({
      id=dotId, type="circle", action="fill",
      fillColor={hex="#e9e9e9", alpha = isSelected and 1 or 0},
      center=center, radius=r/2-4,
    }); idToIdx[dotId] = dotIdx

    local lblIdx = add({
      id=lblId, type="text", text=label, textSize=14,
      textColor = isSelected and {hex="#ffffff"} or {hex="#e9e9e9"},
      textAlignment="left",
      frame={x=x + r + 6, y=y - 1, w=200, h=r + 2},
    }); idToIdx[lblId] = lblIdx

    return {hitId=hitId, dotIdx=dotIdx, lblIdx=lblIdx, label=label}
  end

  -- 배경
  add({
    id="rootBg", type="rectangle", action="fill",
    fillColor={hex="#0f0f10", alpha=1},
    roundedRectRadii={xRadius=14, yRadius=14}
  })

  -- 상단 제목
  add({
    type="text",
    text="Window Resizer & Mover",
    textSize=20,
    textFont="Helvetica-Bold",
    textColor={hex="#ffffff"},
    textAlignment="center",
    frame={x=0, y=8, w=CANVAS_W, h=TITLEBAR_H-8}
  })

  -- ===== Size 섹션 =====
  local curY = TITLEBAR_H + PAD
  add({
    type="text", text="Size:", textSize=14, textColor={hex="#cccccc"},
    textAlignment="left", frame={x=PAD, y=curY, w=CANVAS_W-PAD*2, h=TITLE_H}
  })
  curY = curY + TITLE_H + GAP

  -- Size 1행 (CURRENT~UHD)
  local sizeRadio = {}
  do
    local startX = PAD + 6
    local spacing = 110
    for i, label in ipairs(sizeRow1) do
      local x = startX + (i-1)*spacing
      local y = curY
      sizeRadio[label] = radioAdd(x, y, label, "size", label == selectedSize)
    end
  end

  -- 다음 줄로 이동
  curY = curY + SIZE_ROW_H + 6

  -- Size 2행 (2x2, 3x3, 4x4)
  do
    local startX = PAD + 6
    local spacing = 110
    for i, label in ipairs(sizeRow2) do
      local x = startX + (i-1)*spacing
      local y = curY
      sizeRadio[label] = radioAdd(x, y, label, "size", label == selectedSize)
    end
  end

  -- 다음 줄로 이동 (새 행)
  curY = curY + SIZE_ROW_H + 6

  -- Size 3행 (1x2, 1x3, 2x1, 3x1)
  do
    local startX = PAD + 6
    local spacing = 110
    for i, label in ipairs(sizeRow3) do
      local x = startX + (i-1)*spacing
      local y = curY
      sizeRadio[label] = radioAdd(x, y, label, "size", label == selectedSize)
    end
  end
  curY = curY + SIZE_ROW_H + GAP

  -- ===== Location 섹션 =====
  add({
    type="text", text="Location:", textSize=14, textColor={hex="#cccccc"},
    textAlignment="left", frame={x=PAD, y=curY, w=CANVAS_W-PAD*2, h=TITLE_H}
  })
  curY = curY + TITLE_H + GAP

  local locRadio = {}
  do
    local startX = PAD + 6
    local colSpacing = 190
    local rowSpacing = 34
    for r=1,3 do
      for c=1,3 do
        local label = locGrid[r][c]
        local x = startX + (c-1)*colSpacing
        local y = curY + (r-1)*rowSpacing
        locRadio[label] = radioAdd(x, y, label, "loc", label == selectedLoc)
      end
    end
    curY = curY + GRID_ROW_H*3
  end

  -- ===== OK / Cancel 버튼 =====
  curY = curY + GAP
  local btnH, btnW = BAR_H-10, 120
  local okX     = CANVAS_W - PAD - btnW*2 - 10
  local cancelX = CANVAS_W - PAD - btnW

  local function addButton(id, label, x)
    local rectIdx = add({
      id=id, type="rectangle", action="fill",
      fillColor={hex="#1f1f1f", alpha=1},
      strokeColor={white=1, alpha=0.08}, strokeWidth=1,
      roundedRectRadii={xRadius=BTN_R, yRadius=BTN_R},
      frame={x=x, y=curY, w=btnW, h=btnH},
      trackMouseEnterExit=true, trackMouseDown=true, trackMouseUp=true,
    }); idToIdx[id] = rectIdx

    -- 텍스트도 이벤트 추적 ON (텍스트 클릭 시에도 동작 보장)
    local labelId = id.."_label"
    local labelIdx = add({
      id=labelId, type="text", text=label, textSize=16, textColor={hex="#e9e9e9"},
      textAlignment="center",
      frame={x=x, y=curY + (btnH-20)/2, w=btnW, h=20},
      trackMouseEnterExit=true, trackMouseDown=true, trackMouseUp=true,
    })
    idToIdx[labelId] = labelIdx
  end

  addButton("btnOk", "Ok", okX)
  addButton("btnCancel", "Cancel", cancelX)

  -- ===== 라디오 선택 표시 갱신 =====
  local function updateSizeSelection(newLabel)
    selectedSize = newLabel
    for label, refs in pairs(sizeRadio) do
      cv[refs.dotIdx].fillColor = {hex="#e9e9e9", alpha = (label == selectedSize) and 1 or 0}
      cv[refs.lblIdx].textColor = (label == selectedSize) and {hex="#ffffff"} or {hex="#e9e9e9"}
    end
  end
  local function updateLocSelection(newLabel)
    selectedLoc = newLabel
    for label, refs in pairs(locRadio) do
      cv[refs.dotIdx].fillColor = {hex="#e9e9e9", alpha = (label == selectedLoc) and 1 or 0}
      cv[refs.lblIdx].textColor = (label == selectedLoc) and {hex="#ffffff"} or {hex="#e9e9e9"}
    end
  end

  -- ===== 마우스 콜백 =====
  cv:mouseCallback(function(self, event, elementArg)
    local idx = (type(elementArg)=="number") and elementArg or idToIdx[elementArg]
    if not idx then return end

    -- OK
    local isOk = (idx == idToIdx["btnOk"] or idx == idToIdx["btnOk_label"])
    if isOk then
      if event == "mouseEnter" then
        cv[idToIdx["btnOk"]].fillColor = {hex="#2b2b2b", alpha=1}
      elseif event == "mouseExit" then
        cv[idToIdx["btnOk"]].fillColor = {hex="#1f1f1f", alpha=1}
      elseif event == "mouseDown" then
        cv[idToIdx["btnOk"]].fillColor = {hex="#383838", alpha=1}
      elseif event == "mouseUp" then
        hs.openConsole()
        print(string.format("[Window Resizer & Mover] Size=%s, Location=%s", selectedSize, selectedLoc))
        applySizeAndLocation(selectedSize, selectedLoc, pickerTargetWin)
        if sizePicker then sizePicker:delete(); sizePicker = nil end
      end
      return
    end

    -- Cancel
    local isCancel = (idx == idToIdx["btnCancel"] or idx == idToIdx["btnCancel_label"])
    if isCancel then
      if event == "mouseEnter" then
        cv[idToIdx["btnCancel"]].fillColor = {hex="#2b2b2b", alpha=1}
      elseif event == "mouseExit" then
        cv[idToIdx["btnCancel"]].fillColor = {hex="#1f1f1f", alpha=1}
      elseif event == "mouseDown" then
        cv[idToIdx["btnCancel"]].fillColor = {hex="#383838", alpha=1}
      elseif event == "mouseUp" then
        if sizePicker then sizePicker:delete(); sizePicker = nil end
      end
      return
    end

    -- Size 라디오?
    for label, refs in pairs(sizeRadio) do
      if idx == idToIdx["size_"..label.."_hit"] then
        if event == "mouseEnter" then
          cv[refs.lblIdx].textColor = {hex="#ffffff"}
        elseif event == "mouseExit" then
          cv[refs.lblIdx].textColor = (label == selectedSize) and {hex="#ffffff"} or {hex="#e9e9e9"}
        elseif event == "mouseUp" then
          updateSizeSelection(label)
        end
        return
      end
    end

    -- Location 라디오?
    for label, refs in pairs(locRadio) do
      if idx == idToIdx["loc_"..label.."_hit"] then
        if event == "mouseEnter" then
          cv[refs.lblIdx].textColor = {hex="#ffffff"}
        elseif event == "mouseExit" then
          cv[refs.lblIdx].textColor = (label == selectedLoc) and {hex="#ffffff"} or {hex="#e9e9e9"}
        elseif event == "mouseUp" then
          updateLocSelection(label)
        end
        return
      end
    end
  end)

  cv:show()
  cv:bringToFront(true)
  sizePicker = cv
end

-- 단축키: ⌃⌥⌘ + B 로 열기/다시 열기
hs.hotkey.bind({"ctrl","alt","cmd"}, "B", showPicker)

-- CMD + 좌클릭으로 showPicker 실행 (GC 방지: 전역 변수에 보관)
if ctrlLeftClickTap and ctrlLeftClickTap:stop() then end  -- 중복 생성 방지용 안전장치

ctrlLeftClickTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
  local flags = event:getFlags()

  -- Ctrl만 눌린 상태(원하면 아래 조건을 flags.ctrl로만 단순화 가능)
  if flags.ctrl and flags.shift and  not (flags.alt or flags.cmd or flags.fn) then
    -- 이미 패널이 떠 있으면 또 안 띄우도록 차단
    if sizePicker then return true end
    showPicker()
    return true   -- 클릭 이벤트 소비(원하지 않으면 false로 바꿔도 됨)
  end
  return false
end)

ctrlLeftClickTap:start()

------------------------------------------------------------
-- Ctrl + Shift + ← / → : 선택 창을 이전/다음 디스플레이로 이동
------------------------------------------------------------

-- 현재 스크린 배열을 x좌표 기준으로 정렬(좌→우)해 래핑 이동 지원
local function getOrderedScreens()
  local screens = hs.screen.allScreens()
  table.sort(screens, function(a, b)
    return a:fullFrame().x < b:fullFrame().x
  end)
  return screens
end

-- 현재 스크린의 인덱스 찾기
local function indexOfScreen(screens, target)
  for i, s in ipairs(screens) do
    if s:id() == target:id() then return i end
  end
  return 1
end

-- 창 프레임을 비율로 보존하며 다른 스크린으로 이동
local function moveWindowToScreen(win, targetScreen)
  if not (win and win:id() and targetScreen) then return end

  local wf  = win:frame()
  local sf  = win:screen():frame()
  local tsf = targetScreen:frame()

  -- 원 스크린 대비 상대 비율
  local rx = (wf.x - sf.x) / sf.w
  local ry = (wf.y - sf.y) / sf.h
  local rw = wf.w / sf.w
  local rh = wf.h / sf.h

  -- 대상 스크린에 같은 비율로 배치
  local newFrame = {
    x = tsf.x + rx * tsf.w,
    y = tsf.y + ry * tsf.h,
    w = rw * tsf.w,
    h = rh * tsf.h,
  }

  -- duration=0 으로 자연스런 즉시 이동
  win:move(newFrame, targetScreen, 0)
end

local function moveFocusedWindow(direction) -- "prev" or "next"
  local win = hs.window.frontmostWindow()
  if not (win and win:id()) then
    hs.alert.show("이동할 창이 없습니다.")
    return
  end

  local screens = getOrderedScreens()
  local curIdx  = indexOfScreen(screens, win:screen())
  local n       = #screens
  if n <= 1 then return end

  local newIdx
  if direction == "prev" then
    newIdx = ((curIdx - 2) % n) + 1   -- 래핑하여 이전
  else
    newIdx = (curIdx % n) + 1         -- 래핑하여 다음
  end

  moveWindowToScreen(win, screens[newIdx])
end

-- ⌃ + ← : 이전 디스플레이
hs.hotkey.bind({"ctrl", "shift"}, "left", function()
  moveFocusedWindow("prev")
end)

-- ⌃ + → : 다음 디스플레이
hs.hotkey.bind({"ctrl", "shift"}, "right", function()
  moveFocusedWindow("next")
end)
