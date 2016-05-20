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

$resizePanelList = new-object System.Collections.Generic.List[System.Windows.Forms.Panel]
$resizePanels = {
  $resizePanelList | % { if ($_.Tag.hwnd) {
    [Win32]::SetWindowPos(
      $_.Tag.hwnd,
      [Win32]::HWND_BOTTOM, #crucial to let other buttons show on top of the browsers
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
  [Win32]::ShowWindowAsync($hwnd, [Win32]::SW_SHOWMAXIMIZED) | Out-Null
}

$script:panelCount = 0
$script:AddNewChromePanel = {
  param([bool] $isLeftSide, [string]$url, [string]$grabWindowByTitle, [int]$height)

  $addToPanel = @($mainSplitter.Panel2, $mainSplitter.Panel1)[$isLeftSide]

  if ($isLeftSide) { $script:panelCount++ }

  if (!$height) { $height = 200 }

  if (!$url -and !$grabWindowByTitle) {
    $url = "https://www.google.com"
    $grabWindowByTitle = "Google"
  }

  $grabWindowByTitle += (@(" - Google Chrome","")[$isLeftSide])

  #need new chrome windows so we can grab them by distinct window title, otherwise chrome slams them into single container where current tab is window title
  if (!!$url) { & 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe' "$(@("--new-window ", "--app=")[$isLeftSide])$url" }
  $hwnd = [Win32]::FindWindowByTitle($grabWindowByTitle, @($null, "New Tab")[$url -eq "http://www.google.com"])

  if ($isLeftSide -and $script:panelCount -gt 1) {
    #then split it into 2 by creating new splitter...
    $newSplitter = new-object System.Windows.Forms.Splitter
    $newSplitter.BackColor = "LightGray"
    $newSplitter.BorderStyle = "Fixed3D"
    $newSplitter.Dock = "Top"
    $newSplitter.Height = 15
    $newSplitter.Add_SplitterMoved($resizePanels)
    $newSplitter.Name = $script:panelCount

    $addToPanel.Controls.Add($newSplitter)
    $newSplitter.BringToFront()
  }

  $pnlBrowserPlaceholder = new-object System.Windows.Forms.Panel
  $pnlBrowserPlaceholder.Dock = @("Fill", "Top")[$isLeftSide]
  $addToPanel.Controls.Add($pnlBrowserPlaceholder)
  $pnlBrowserPlaceholder.BringToFront()
  $pnlBrowserPlaceholder.Height = $height

  if ($isLeftSide) { $bottomSplitter.BringToFront() }

  SetParent $hwnd $pnlBrowserPlaceholder $isLeftSide

  $btnClosePanel = new-object System.Windows.Forms.Button
  $btnClosePanel.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left)
  $btnClosePanel.Text = "X"
  $btnClosePanel.Width = "30"
  $toolTip.SetToolTip($btnClosePanel, "Close Panel")
  $btnClosePanel.add_Click({
    #close the browser
    [Win32]::SendMessage($pnlBrowserPlaceholder.Tag.hwnd, [Win32]::WM_SYSCOMMAND, [Win32]::SC_CLOSE, 0) | Out-Null
    $this.Parent.Parent.Controls.Remove($newSplitter)
    $this.Parent.Parent.Controls.Remove($pnlBrowserPlaceholder)
    #$resizePanels.Invoke()
  }.GetNewClosure())

  <#
  $label = new-object System.Windows.Forms.Label
  $label.AutoSize = $true
  $label.Text = $script:panelCount.ToString()
  $pnlBrowserPlaceholder.Controls.Add($label)
  $label.BringToFront()
  #>

  $pnlBrowserPlaceholder.Controls.Add($btnClosePanel)
  $btnClosePanel.BringToFront()

  $resizePanels.Invoke()
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

$bottomSplitter = new-object System.Windows.Forms.Splitter
$bottomSplitter.BackColor = "LightGray"
$bottomSplitter.BorderStyle = "Fixed3D"
$bottomSplitter.Dock = "Top"
$bottomSplitter.Height = 15
$bottomSplitter.Add_SplitterMoved($resizePanels)
#$bottomSplitter.Add_MouseDown({ 
#write-host "Y: $($bottomSplitter.Location.Y.toString()), panel1.height: $($mainSplitter.Panel1.Height - 45)"
#if ($bottomSplitter.Location.Y -gt $mainSplitter.Panel1.Height - 45) {
$bottomSplitter.BringToFront()

<#
$spaceMaker = new-object System.Windows.Forms.Panel
$spaceMaker.Anchor = "Left, Right"
$spaceMaker.AutoSize = $true
$mainSplitter.Panel1.Controls.Add($spaceMaker)
#>

$mainSplitter.Panel1.Controls.Add($bottomSplitter)

#going for no horizontal scrollbar, client windows forced to auto resize when left side width changes
#nugget: very unintuitive solution from here (thank goodness): http://stackoverflow.com/a/28583501/813599
$mainSplitter.Panel1.HorizontalScroll.Maximum = 0
$mainSplitter.Panel1.AutoScroll = $false
$mainSplitter.Panel1.VerticalScroll.Visible = $false
$mainSplitter.Panel1.AutoScroll = $true

$mainToolBar = new-object System.Windows.Forms.FlowLayoutPanel
$mainToolBar.Height = 90
$mainToolBar.Dock = [System.Windows.Forms.DockStyle]::Top
$frmMain.Controls.Add($mainSplitter) | Out-Null
$frmMain.Controls.Add($mainToolBar) | Out-Null

$txtGrabWindowTitle = new-object System.Windows.Forms.TextBox
$btnNewPanel =  new-object System.Windows.Forms.Button
$btnNewPanel.Text = "<= Grab Window by Title (Blank = New Browser)"
$btnNewPanel.Width = "260"
$btnNewPanel.Add_Click({
  $script:AddNewChromePanel.Invoke($true, $null, $script:txtGrabWindowTitle.Text)
})
$mainToolBar.Controls.Add($txtGrabWindowTitle)
$mainToolBar.Controls.Add($btnNewPanel)

function createButton {
    param([string]$toolTip, [string]$caption, [string]$faType, [scriptblock]$action)
    $faBtn = New-Object FaButton(65, 80, 25, $toolTip, $caption, 32, $faType, $mainToolBar);
    #nugget: GetNewClosure() *copies* current scope value into the future scope, it can't be changed in that future calling scope and come back like a true closure, but we don't need it to in this case
    $faBtn.Button.Add_Click({ $action.Invoke($faBtn.Button) }.GetNewClosure() ) #nugget: pass pointer to wrappered button back into the action script to be able to change the icon upon state toggle
}

#createButton -toolTip "Open Selected Folder New Tab RIGHT" -caption "Open Right" -faType ([Fa]::FolderO) -action { }

$frmMain.add_Load({
  #fire up left side default panels
  $AddNewChromePanel.Invoke($true, "http://www.di.fm/glitchhop/", "Glitch Hop Radio - DI Radio", 117)
  $AddNewChromePanel.Invoke($true, "http://kiroradio.com/category/kiroradiolive/", "KIRO Radio 97.3 FM. Seattle's News. Seattle's Talk. >> KIRORadio.com")
  $AddNewChromePanel.Invoke($true, "https://calendar.google.com/calendar/render?tab=mc#main_7%7Cmonth", "Next-Technologies - Calendar - Month of $([System.DateTime]::Now.Date.toString("MMM yyyy"))")
  $AddNewChromePanel.Invoke($true, "chrome-extension://eggkanocgddhmamlbiijnphhppkpkmkl/activesessionview.html", "Tabs Outliner")
  $AddNewChromePanel.Invoke($true, "https://gmail.com/", "Next-Technologies Mail")
  $AddNewChromePanel.Invoke($true, "https://todoist.com/app?lang=en&v=732#project%2F169132708", "Inbox: Todoist")

  #start with one big panel on the right side
  $AddNewChromePanel.Invoke($false)

  $mainSplitter.SplitterDistance = 300

  $mainSplitter.Add_SplitterMoved($resizePanels)
  $resizePanels.Invoke()
})

$frmMain.add_FormClosing({
  $resizePanelList | %{
    [Win32]::SendMessage($_.Tag.hwnd, [Win32]::WM_SYSCOMMAND, [Win32]::SC_CLOSE, 0) | Out-Null
    [System.Threading.Thread]::Sleep(100)
  }
})

[System.Windows.Forms.Application]::Run($frmMain)

if ($Error -and $poShConsoleHwnd -ne 0) { showPoShConsole; pause }