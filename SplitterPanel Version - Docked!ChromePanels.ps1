$Error.Clear()

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
& $PSScriptRoot\Win32.ps1 #bunch of win32 api exports
& $PSScriptRoot\FontAwesome.ps1 # handy wrapper for FontAwesome as a .Net class, from here: https://github.com/microvb/FontAwesome-For-WinForms-CSharp

#save MainWindowHandle so we can hide explicitly here and keep available for showing at end for troubleshooting, IIF PowerShell errors were emitted 
#nugget: don't use -WindowStyle Hidden on the ps1 shortcut, it prevents retrieval of main MainWindowHandle here...
$process = Get-Process -Id $pid
$poShConsoleHwnd = $process.MainWindowHandle
if ($process.ProcessName -eq "powershell_ise") { $poShConsoleHwnd=0 }
function showPoShConsole {
  param([bool]$show = $true)
  
  if ($show -and [Win32]::IsWindowVisible($poShConsoleHwnd)) { $show=$false }

  [Win32]::ShowWindowAsync($poShConsoleHwnd, @([Win32]::SW_HIDE, [Win32]::SW_SHOWNORMAL)[$show]) | Out-Null
  [Win32]::SetForegroundWindow($poShConsoleHwnd) | Out-Null
}

showPoShConsole $false

function createButton {
  param( [string]$toolTipText, [FontAwesomeIcons.IconType]$iconType, $eventHandler )

  $faButton = New-Object FontAwesomeIcons.IconButton
  ([System.ComponentModel.ISupportInitialize]($faButton)).BeginInit()
  $faButton.ActiveColor = [System.Drawing.Color]::Blue
  $faButton.BackColor = [System.Drawing.Color]::LightGray
  $faButton.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $faButton.IconType = $iconType
  $faButton.InActiveColor = [System.Drawing.Color]::Black
  #$faButton.Location = new-object System.Drawing.Point(255, 191)
  #$faButton.Name = "iconButton4"
  $faButton.Size = new-object System.Drawing.Size(60, 60)
  #$faButton.TabIndex = 4
  #$faButton.TabStop = false
  $faButton.ToolTipText = $toolTipText
  $faButton.Add_Click($eventHandler)

  return $faButton
}

$global:movingSplitter = $null

$moving = {
$global:movingSplitter = $this
write-host "moving"
}

$resizePanelList = new-object System.Collections.Generic.List[System.Windows.Forms.Panel]
$resizePanels = {
  
  if ($this -is [System.Windows.Forms.SplitContainer]) {
    if ($this -ne $global:movingSplitter) { $this.SplitterDistance = $this.Tag }
    else { $this.Tag = $this.SplitterDistance }
  }

  write-host "moved"
  write-host $this.Name
  write-host ([System.Windows.Forms.Control]::MouseButtons).toString()

  $resizePanelList | % { if ($_.Tag.hwnd) {
    [Win32]::SetWindowPos(
      $_.Tag.hwnd,
      [Win32]::HWND_TOP,
      $_.ClientRectangle.Left,
      $_.ClientRectangle.Top,
      $_.ClientRectangle.Width,
      $_.ClientRectangle.Height,
      [Win32]::NOACTIVATE -bor [Win32]::SHOWWINDOW
    ) | Out-Null
  }}
}

function SetParent {
  param([int]$hwnd, [System.Windows.Forms.Panel]$panel, [bool]$isLeftSide)

  #close existing if there is one since we're replacing it with a new
  if ($panel.Tag.hwnd) {
    [Win32]::SendMessage($panel.Tag.hwnd, [Win32]::WM_SYSCOMMAND, [Win32]::SC_CLOSE, 0) | Out-Null
  }

  #nugget: on the fly expando property object
  $panel.Tag = New-Object –TypeName PSObject -Property @{ hwnd=$hwnd; isLeftSide=$isLeftSide }
  $resizePanelList.Add($panel)
  [Win32]::SetParent($hwnd, $panel.Handle) | Out-Null
  [Win32]::HideTitleBar($hwnd)
  [Win32]::SetWindowText($hwnd, "empty")
  [Win32]::ShowWindowAsync($hwnd, [Win32]::SW_SHOWMAXIMIZED) | Out-Null
}

function GrabWindow {
  param([string]$windowClass, [string]$windowTitle)
  #if ($windowClass -eq "") { return [Win32]::FindWindowByTitle($windowTitle) }
  #if ($windowTitle -eq "") { return [Win32]::FindWindowByClass($windowTitle) }
}

$splitterList = new-object System.Collections.Generic.List[System.Windows.Forms.SplitContainer]

$global:panelCount = 0
$global:AddNewChromePanel = {
  param([System.Windows.Forms.Panel]$existingPanel, [bool] $isLeftSide, [string]$url, [string]$grabWindowByTitle, [int]$height)

  write-host "new panel========="

  if ($isLeftSide) { $global:panelCount++ }

  if (!$height) { $height = 200 }

  if (!$url -and !$grabWindowByTitle) {
    $url = "https://www.google.com"
    $grabWindowByTitle = "Google"
  }

  $grabWindowByTitle += (@(" - Google Chrome","")[$isLeftSide])

  #need new chrome windows so we can grab them by distinct window title, otherwise chrome slams them into single container where current tab is window title
  if (!!$url) { & 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe' "$(@("--new-window ", "--app=")[$isLeftSide])$url" }
  $hwnd = [Win32]::FindWindowByTitle($grabWindowByTitle, @($null, "New Tab")[$url -eq "http://www.google.com"])

  # if this panel already has content...
  if ($existingPanel.Controls.Count -gt 0) {

      #then split it into 2 by creating new splitter...
      $newSplitContainer = new-object System.Windows.Forms.SplitContainer
      $splitterList.Add($newSplitContainer)
      $newSplitContainer.Dock = "Fill"
      $newSplitContainer.SplitterWidth = 20
      $newSplitContainer.Orientation = "Horizontal"
      $newSplitContainer.BorderStyle = "Fixed3D"
      $newSplitContainer.Add_SplitterMoved($resizePanels)
      $newSplitContainer.Add_SplitterMoving($moving)
      $newSplitContainer.Tag = $height
      $newSplitContainer.Name = $global:panelCount

      # *moving* existing content from existing panel and down into into the top panel of the new splitter...
      # Controls.Add automatically removes from the previous parent - didn't initially expect that
      $savePosition = 0
      while($existingPanel.Controls.Count -gt 0) {
        $moveCtrl = $existingPanel.Controls[0]
        if ($moveCtrl -is [System.Windows.Forms.SplitContainer]) {
          $moveCtrl.Dock = "Fill"
          $savePosition = $moveCtrl.SplitterDistance
        }
        $newSplitContainer.Panel1.Controls.Add($existingPanel.Controls[0])
      }

      #add the new splitter to be the only remaining child of the existing panel
      $existingPanel.Controls.Add($newSplitContainer)

      if ($global:panelCount * 200 -gt $mainSplitter.Panel1.Height) {
        $newSplitContainer.Dock = "Top"
        $newSplitContainer.Height = $mainSplitter.Panel1.Height + 200

        $mainSplitter.Panel1.HorizontalScroll.Maximum = 0
        $mainSplitter.Panel1.AutoScroll = $false
        $mainSplitter.Panel1.VerticalScroll.Visible = $false
        $mainSplitter.Panel1.AutoScroll = $true
      }

      $newSplitContainer.SplitterDistance = ($global:panelCount-1) * 200
      if ($savePosition) { $moveCtrl.SplitterDistance = $savePosition }


      #and finally adding a new blank panel to the bottom half of the splitter ready to take another chrome window
      $existingPanel = $newSplitContainer.Panel2
  }
 

  $pnlBrowserPlaceholder = new-object System.Windows.Forms.Panel
  $pnlBrowserPlaceholder.Height = $height
  $pnlBrowserPlaceholder.Dock = "Fill"

  $btnClosePanel = new-object System.Windows.Forms.Button
  $btnClosePanel.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left)
  $btnClosePanel.Text = "X"
  $btnClosePanel.Width = "30"
  $toolTip.SetToolTip($btnClosePanel, "Close Panel")
  $btnClosePanel.add_Click({
    #close the browser
    [Win32]::SendMessage($pnlBrowserPlaceholder.Tag.hwnd, [Win32]::WM_SYSCOMMAND, [Win32]::SC_CLOSE, 0) | Out-Null
    #back out this splitter by taking the Panel2 controls and adding them to the parent
    while($newSplitContainer.Panel1.Controls.Count -gt 0) {
      $newSplitContainer.Parent.Controls.Add($newSplitContainer.Panel1.Controls[0])
    }
    #and lastly removing the splitter itself
    $newSplitContainer.Parent.Controls.Remove($newSplitContainer)
    $resizePanels.Invoke()
  }.GetNewClosure())

  
  $label = new-object System.Windows.Forms.Label
  $label.AutoSize = $true
  $label.Text = $global:panelCount.ToString()

  $existingPanel.Controls.Add($pnlBrowserPlaceholder)
  $existingPanel.Controls.Add($btnClosePanel)
  $existingPanel.Controls.Add($label)
  $btnClosePanel.BringToFront()
  $label.BringToFront()

  SetParent $hwnd $pnlBrowserPlaceholder $isLeftSide
  #[System.Threading.Thread]::Sleep(500)
  #$resizePanels.Invoke()
}

$frmMain = New-Object System.Windows.Forms.Form
$frmMain.Text = "Chrome Panels!"
$frmMain.Icon = New-Object system.drawing.icon ("$PSScriptRoot\icon.ico")
$frmMain.WindowState = "Maximized";
$frmMain.Add_Resize($resizePanels)
$toolTip = new-object System.Windows.Forms.ToolTip

$mainSplitter = new-object System.Windows.Forms.SplitContainer
$mainSplitter.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainSplitter.SplitterWidth = 15
$mainSplitter.BorderStyle = "Fixed3D"
$mainSplitter.Name = "mainSplitter"
$mainSplitter.Panel1.Name = "main Panel 1"
$frmMain.Controls.Add($mainSplitter)
$mainSplitter.SplitterDistance = $frmMain.ClientRectangle.Width / 4

#going for no horizontal scrollbar, client windows forced to auto resize when left side width changes
#nugget: very unintuitive solution from here (thank goodness): http://stackoverflow.com/a/28583501/813599
$mainSplitter.Panel1.HorizontalScroll.Maximum = 0
$mainSplitter.Panel1.AutoScroll = $false
$mainSplitter.Panel1.VerticalScroll.Visible = $false
$mainSplitter.Panel1.AutoScroll = $true

#button toolbar
#https://adminscache.wordpress.com/2014/08/03/powershell-winforms-menu/
$buttonPanel = new-object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.Height = 90
$buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$frmMain.Controls.Add($mainSplitter) | Out-Null
$frmMain.Controls.Add($buttonPanel) | Out-Null

$txtWindowTitle = new-object System.Windows.Forms.TextBox
$btnNewPanel =  new-object System.Windows.Forms.Button
$btnNewPanel.Text = "<= Grab Window by Title (Blank = New Browser)"
$btnNewPanel.Width = "260"
$btnNewPanel.Add_Click({
  $global:AddNewChromePanel.Invoke($mainSplitter.Panel1, $true, $null, $txtWindowTitle.Text)
}.GetNewClosure())
$buttonPanel.Controls.Add($txtWindowTitle)
$buttonPanel.Controls.Add($btnNewPanel)

function createButton {
    param([string]$toolTip, [string]$caption, [string]$faType, [scriptblock]$action)
    $faBtn = New-Object FaButton(65, 80, 25, $toolTip, $caption, 32, $faType, $buttonPanel);
    #nugget: GetNewClosure() *copies* current scope value into the future scope, it can't be changed in that future calling scope and come back like a true closure, but we don't need it to in this case
    $faBtn.Button.Add_Click({ $action.Invoke($faBtn.Button) }.GetNewClosure() ) #nugget: pass pointer to wrappered button back into the action script to be able to change the icon upon state toggle
}

#createButton -toolTip "Open Selected Folder New Tab RIGHT" -caption "Open Right" -faType ([Fa]::FolderO) -action { }

$frmMain.add_Load({
  #fire up left side default panels
  $AddNewChromePanel.Invoke($mainSplitter.Panel1, $true, "http://www.di.fm/glitchhop/", "Glitch Hop Radio - DI Radio", 117)
  $AddNewChromePanel.Invoke($mainSplitter.Panel1, $true, "http://kiroradio.com/category/kiroradiolive/", "KIRO Radio 97.3 FM. Seattle's News. Seattle's Talk. >> KIRORadio.com")
  #$AddNewChromePanel.Invoke($mainSplitter.Panel1, $true, "https://calendar.google.com/calendar/render?tab=mc#main_7%7Cmonth", "Next-Technologies - Calendar - Month of $([System.DateTime]::Now.Date.toString("MMM yyyy"))")
  #$AddNewChromePanel.Invoke($mainSplitter.Panel1, $true, "chrome-extension://eggkanocgddhmamlbiijnphhppkpkmkl/activesessionview.html", "Tabs Outliner")
  #$AddNewChromePanel.Invoke($mainSplitter.Panel1, $true, "https://gmail.com/", "Next-Technologies Mail")
  #$AddNewChromePanel.Invoke($mainSplitter.Panel1, $true, "https://todoist.com/app?lang=en&v=732#project%2F169132708", "Inbox: Todoist")

  #start with one big panel on the right side
  #$AddNewChromePanel.Invoke($mainSplitter.Panel2)

  $mainSplitter.Add_SplitterMoved($resizePanels)
})

$frmMain.add_FormClosing({
  $resizePanelList | %{
    [Win32]::SendMessage($_.Tag.hwnd, [Win32]::WM_SYSCOMMAND, [Win32]::SC_CLOSE, 0) | Out-Null
    [System.Threading.Thread]::Sleep(100)
  }
})

[System.Windows.Forms.Application]::Run($frmMain)

if ($Error -and $poShConsoleHwnd -ne 0) { showPoShConsole; pause }