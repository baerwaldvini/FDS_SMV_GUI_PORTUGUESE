$ErrorActionPreference = "Stop"

$HostName = "127.0.0.1"
$Port = 8766
$Prefix = "http://${HostName}:${Port}/"
$Root = $PSScriptRoot
$FdsExe = "C:\Program Files\firemodels\FDS6\bin\fds.exe"
$SmokeviewExe = "C:\Program Files\firemodels\SMV6\smokeview.exe"

$State = @{
  running = $false
  last_return_code = $null
  last_input = $null
  last_smv = $null
  log = @("Servidor local iniciado em $Prefix")
  job = $null
  log_file = $null
  rc_file = $null
}

function Add-Log($Message) {
  $State.log += $Message
  if ($State.log.Count -gt 400) {
    $State.log = $State.log[($State.log.Count - 400)..($State.log.Count - 1)]
  }
}

function Send-Json($Context, $StatusCode, $Payload) {
  $Json = $Payload | ConvertTo-Json -Depth 8
  $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
  $Context.Response.StatusCode = $StatusCode
  $Context.Response.ContentType = "application/json; charset=utf-8"
  $Context.Response.Headers.Add("Access-Control-Allow-Origin", "*")
  $Context.Response.ContentLength64 = $Bytes.Length
  $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
  $Context.Response.OutputStream.Close()
}

function Send-File($Context, $Path) {
  $FullPath = Join-Path $Root $Path
  if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
    Send-Json $Context 404 @{ error = "Arquivo nao encontrado." }
    return
  }

  $Extension = [System.IO.Path]::GetExtension($FullPath)
  $ContentType = "text/plain; charset=utf-8"
  if ($Extension -eq ".html") { $ContentType = "text/html; charset=utf-8" }
  if ($Extension -eq ".css") { $ContentType = "text/css; charset=utf-8" }
  if ($Extension -eq ".js") { $ContentType = "application/javascript; charset=utf-8" }

  $Bytes = [System.IO.File]::ReadAllBytes($FullPath)
  $Context.Response.StatusCode = 200
  $Context.Response.ContentType = $ContentType
  $Context.Response.ContentLength64 = $Bytes.Length
  $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
  $Context.Response.OutputStream.Close()
}

function Read-JsonBody($Context) {
  $Reader = New-Object System.IO.StreamReader($Context.Request.InputStream, $Context.Request.ContentEncoding)
  $Text = $Reader.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($Text)) {
    return @{}
  }
  return $Text | ConvertFrom-Json
}

function Read-Chid($InputFile) {
  $Text = Get-Content -LiteralPath $InputFile -Raw -ErrorAction Stop
  $Match = [regex]::Match($Text, "CHID\s*=\s*['""]([^'""]+)['""]", "IgnoreCase")
  if ($Match.Success) {
    return $Match.Groups[1].Value
  }
  return [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
}

function New-SafeName($Value) {
  $Name = [string]$Value
  if ([string]::IsNullOrWhiteSpace($Name)) {
    $Name = "fds_case"
  }
  $Name = $Name.Normalize([Text.NormalizationForm]::FormD)
  $Builder = New-Object System.Text.StringBuilder
  foreach ($Char in $Name.ToCharArray()) {
    $Category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($Char)
    if ($Category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$Builder.Append($Char)
    }
  }
  $Name = $Builder.ToString().Normalize([Text.NormalizationForm]::FormC)
  $Name = $Name -replace "[^A-Za-z0-9_-]+", "_"
  $Name = $Name.Trim("_")
  if ([string]::IsNullOrWhiteSpace($Name)) {
    return "fds_case"
  }
  return $Name
}

function Convert-MeshSizeToCell($MeshSize) {
  $Text = [string]$MeshSize
  if ($Text -match "0,10|0\.10") { return "0.10" }
  if ($Text -match "0,50|0\.50") { return "0.50" }
  return "0.25"
}

function Count-FdsRecords($Text, $RecordName) {
  $Pattern = "(?im)^\s*&$RecordName\b"
  return ([regex]::Matches($Text, $Pattern)).Count
}

function Test-FdsKeyword($Text, $Keyword) {
  return [regex]::IsMatch($Text, $Keyword, "IgnoreCase")
}

function Convert-FdsToModel($InputFile, $Payload) {
  $Text = Get-Content -LiteralPath $InputFile -Raw -ErrorAction Stop
  $ObstCount = Count-FdsRecords $Text "OBST"
  $VentCount = Count-FdsRecords $Text "VENT"
  $MeshCount = Count-FdsRecords $Text "MESH"
  $DeviceCount = Count-FdsRecords $Text "DEVC"
  $ExitCount = ([regex]::Matches($Text, "(?i)EXIT|SA[IÍ]DA|DOOR|PORTA|OPEN")).Count
  $HydrantCount = ([regex]::Matches($Text, "(?i)HYDRANT|HIDRANTE")).Count
  $ExtinguisherCount = ([regex]::Matches($Text, "(?i)EXTINGUISHER|EXTINTOR")).Count
  $RoomCount = ([regex]::Matches($Text, "(?i)ROOM|SALA|COMPART")).Count

  if ($ExitCount -gt 0) {
    $ExitCount = [Math]::Min($ExitCount, [Math]::Max($VentCount, 1))
  }

  $Notes = @(
    "Arquivo FDS lido: $InputFile"
    "Geometria encontrada: $ObstCount solidos, $VentCount vents/aberturas e $MeshCount malha(s)."
  )

  if ($DeviceCount -gt 0) {
    $Notes += "Dispositivos FDS detectados: $DeviceCount DEVC."
  } else {
    $Notes += "Nenhum DEVC encontrado; preventivos precisam ser conferidos manualmente."
  }

  if (-not (Test-FdsKeyword $Text "REAC|SURF")) {
    $Notes += "Nao encontrei REAC/SURF suficientes para validar o incendio; revise o cenario antes de simular."
  }

  return @{
    title = "FDS interpretado"
    status = "Modelo lido"
    sourceType = "fds"
    extension = ".fds"
    geometry = @{
      solids = $ObstCount
      vents = $VentCount
      meshes = $MeshCount
      rooms = $RoomCount
    }
    preventives = @{
      extinguishers = $ExtinguisherCount
      hydrants = $HydrantCount
      exits = $ExitCount
    }
    notes = $Notes
    reviewRequired = $true
  }
}

function Get-ScaleMeters($ScaleText) {
  $Text = [string]$ScaleText
  if ($Text -match "1\s*:\s*(\d+)") {
    return [double]$Matches[1]
  }
  return 100.0
}

function New-RasterWall($X, $Y, $W, $H) {
  return @{
    x = [Math]::Round([double]$X, 4)
    y = [Math]::Round([double]$Y, 4)
    w = [Math]::Round([double]$W, 4)
    h = [Math]::Round([double]$H, 4)
  }
}

function Get-LineGroups($Values, $Threshold, $MinimumThickness) {
  $Groups = @()
  $Start = -1
  for ($Index = 0; $Index -lt $Values.Count; $Index += 1) {
    $Active = $Values[$Index] -ge $Threshold
    if ($Active -and $Start -lt 0) {
      $Start = $Index
    }
    if ((-not $Active -or $Index -eq ($Values.Count - 1)) -and $Start -ge 0) {
      $End = if ($Active -and $Index -eq ($Values.Count - 1)) { $Index } else { $Index - 1 }
      if (($End - $Start + 1) -ge $MinimumThickness) {
        $Groups += @{ start = $Start; end = $End; center = (($Start + $End) / 2.0); thickness = ($End - $Start + 1) }
      }
      $Start = -1
    }
  }
  return $Groups
}

function Convert-RasterDrawingToModel($InputFile, $Payload) {
  Add-Type -AssemblyName System.Drawing
  $Bitmap = [System.Drawing.Bitmap]::FromFile($InputFile)
  try {
    $Width = $Bitmap.Width
    $Height = $Bitmap.Height
    $RowCounts = New-Object int[] $Height
    $ColumnCounts = New-Object int[] $Width
    $MinX = $Width
    $MinY = $Height
    $MaxX = 0
    $MaxY = 0

    for ($Y = 0; $Y -lt $Height; $Y += 1) {
      for ($X = 0; $X -lt $Width; $X += 1) {
        $Pixel = $Bitmap.GetPixel($X, $Y)
        $Average = (($Pixel.R + $Pixel.G + $Pixel.B) / 3.0)
        $IsDark = $Average -lt 135 -and $Pixel.A -gt 32
        if ($IsDark) {
          $RowCounts[$Y] += 1
          $ColumnCounts[$X] += 1
          if ($X -lt $MinX) { $MinX = $X }
          if ($Y -lt $MinY) { $MinY = $Y }
          if ($X -gt $MaxX) { $MaxX = $X }
          if ($Y -gt $MaxY) { $MaxY = $Y }
        }
      }
    }

    if ($MaxX -le $MinX -or $MaxY -le $MinY) {
      throw "Nao encontrei linhas escuras suficientes para montar geometria."
    }

    $HorizontalGroups = @(Get-LineGroups $RowCounts ([Math]::Max([int]($Width * 0.18), 40)) 2)
    $VerticalGroups = @(Get-LineGroups $ColumnCounts ([Math]::Max([int]($Height * 0.18), 40)) 2)
    $PlanWidth = [Math]::Max($MaxX - $MinX, 1)
    $PlanHeight = [Math]::Max($MaxY - $MinY, 1)
    $Walls = @()

    foreach ($Group in $HorizontalGroups) {
      $Y = (($Group.start - $MinY) / $PlanHeight)
      $H = [Math]::Max(($Group.thickness / $PlanHeight), 0.01)
      $Walls += New-RasterWall 0 $Y 1 $H
    }

    foreach ($Group in $VerticalGroups) {
      $X = (($Group.start - $MinX) / $PlanWidth)
      $W = [Math]::Max(($Group.thickness / $PlanWidth), 0.01)
      $Walls += New-RasterWall $X 0 $W 1
    }

    $MaxWalls = 80
    if ($Walls.Count -gt $MaxWalls) {
      $Walls = @($Walls | Select-Object -First $MaxWalls)
    }

    $Notes = @(
      "Imagem lida: $InputFile"
      "Previa gerada por deteccao de linhas escuras: $($Walls.Count) parede(s)/obstaculo(s)."
      "Confira escala, paredes falsas geradas por textos/carimbos e aberturas antes de simular."
    )

    return @{
      title = "Prancha interpretada"
      status = "Previa CV"
      sourceType = "raster"
      extension = [System.IO.Path]::GetExtension($InputFile).ToLowerInvariant()
      geometry = @{
        solids = $Walls.Count
        vents = 0
        meshes = 1
        rooms = [Math]::Max(($HorizontalGroups.Count - 1) * ($VerticalGroups.Count - 1), 0)
        walls = $Walls
        imageWidth = $Width
        imageHeight = $Height
      }
      preventives = @{
        extinguishers = 0
        hydrants = 0
        exits = 0
      }
      notes = $Notes
      reviewRequired = $true
    }
  }
  finally {
    $Bitmap.Dispose()
  }
}

function Get-EdgePath {
  $Candidates = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
  )
  foreach ($Candidate in $Candidates) {
    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
      return $Candidate
    }
  }
  return $null
}

function Convert-PdfDrawingToModel($InputFile, $Payload) {
  $EdgePath = Get-EdgePath
  if ([string]::IsNullOrWhiteSpace($EdgePath)) {
    throw "Nao encontrei renderizador de PDF local. Converta a prancha para PNG/JPG ou instale Microsoft Edge/Poppler para interpretar PDF."
  }

  $RenderFile = Join-Path $env:TEMP "fds-gui-pdf-render-$([guid]::NewGuid().ToString('N')).png"
  $InputUri = ([System.Uri](Get-Item -LiteralPath $InputFile).FullName).AbsoluteUri
  $Arguments = @(
    "--headless=new"
    "--disable-gpu"
    "--no-first-run"
    "--disable-extensions"
    "--hide-scrollbars"
    "--window-size=1800,1400"
    "--screenshot=$RenderFile"
    $InputUri
  )

  $Process = Start-Process -FilePath $EdgePath -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
  if ($Process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $RenderFile -PathType Leaf)) {
    throw "Nao consegui renderizar o PDF para imagem. Exporte a primeira folha da PPCI como PNG/JPG e tente novamente."
  }

  $Model = Convert-RasterDrawingToModel $RenderFile $Payload
  $Model["title"] = "PDF interpretado"
  $Model["status"] = "Previa PDF/CV"
  $Model["sourceType"] = "raster"
  $Model["extension"] = ".pdf"
  $Model["notes"] = @(
    "PDF renderizado para imagem temporaria e analisado por deteccao de linhas."
  ) + $Model["notes"] + @(
    "Esta leitura usa a primeira pagina renderizada; pranchas multipagina ainda precisam de selecao de folha."
  )
  return $Model
}

function Convert-DrawingToModel($Payload) {
  $InputFile = [string]$Payload.drawingFile
  if ([string]::IsNullOrWhiteSpace($InputFile)) {
    throw "Informe o arquivo da prancha antes de interpretar."
  }
  if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
    throw "Arquivo da prancha nao encontrado: $InputFile"
  }

  $Extension = [System.IO.Path]::GetExtension($InputFile).ToLowerInvariant()
  if ($Extension -eq ".fds") {
    return Convert-FdsToModel $InputFile $Payload
  }
  if ($Extension -eq ".pdf") {
    return Convert-PdfDrawingToModel $InputFile $Payload
  }
  if (@(".png", ".jpg", ".jpeg", ".bmp") -contains $Extension) {
    return Convert-RasterDrawingToModel $InputFile $Payload
  }

  return @{
    title = "Prancha pendente"
    status = "OCR/CV pendente"
    sourceType = "drawing_pending"
    extension = $Extension
    geometry = @{
      solids = 0
      vents = 0
      meshes = 0
      rooms = 0
    }
    preventives = @{
      extinguishers = 0
      hydrants = 0
      exits = 0
    }
    notes = @(
      "Formato selecionado: $Extension."
      "A leitura automatica deste formato ainda depende de um importador especifico."
      "Use PDF, PNG, JPG, BMP ou .fds para leitura imediata nesta versao."
    )
    reviewRequired = $true
  }
}

function New-FdsDraft($Payload) {
  $ProjectName = [string]$Payload.projectName
  $OutputFolder = [string]$Payload.outputFolder
  $DrawingFile = [string]$Payload.drawingFile
  $CeilingHeight = [double]::Parse(([string]$Payload.ceilingHeight).Replace(",", "."), [Globalization.CultureInfo]::InvariantCulture)
  $Area = [double]::Parse(([string]$Payload.area).Replace(",", "."), [Globalization.CultureInfo]::InvariantCulture)
  $Duration = [double]::Parse(([string]$Payload.duration).Replace(",", "."), [Globalization.CultureInfo]::InvariantCulture)
  $Hrrpua = [double]::Parse(([string]$Payload.hrrpua).Replace(",", "."), [Globalization.CultureInfo]::InvariantCulture)
  $CellSize = [double]::Parse((Convert-MeshSizeToCell $Payload.meshSize), [Globalization.CultureInfo]::InvariantCulture)

  if (-not (Test-Path -LiteralPath $OutputFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
  }

  $Chid = New-SafeName $ProjectName
  $FdsFile = Join-Path $OutputFolder "$Chid.fds"
  $Length = [Math]::Max([Math]::Sqrt($Area), 1.0)
  $Width = [Math]::Max($Area / $Length, 1.0)
  $XMax = [Math]::Ceiling($Length)
  $YMax = [Math]::Ceiling($Width)
  $ZMax = [Math]::Ceiling([Math]::Max($CeilingHeight + 1.0, 3.0))
  $I = [Math]::Max([int][Math]::Ceiling($XMax / $CellSize), 4)
  $J = [Math]::Max([int][Math]::Ceiling($YMax / $CellSize), 4)
  $K = [Math]::Max([int][Math]::Ceiling($ZMax / $CellSize), 4)
  $FireX1 = [Math]::Round(($XMax / 2.0) - 0.5, 2)
  $FireX2 = [Math]::Round(($XMax / 2.0) + 0.5, 2)
  $FireY1 = [Math]::Round(($YMax / 2.0) - 0.5, 2)
  $FireY2 = [Math]::Round(($YMax / 2.0) + 0.5, 2)
  $GeometryModel = $null
  $DrawingExtension = [System.IO.Path]::GetExtension($DrawingFile).ToLowerInvariant()

  if (@(".pdf", ".png", ".jpg", ".jpeg", ".bmp", ".fds") -contains $DrawingExtension) {
    try {
      $GeometryModel = Convert-DrawingToModel $Payload
    }
    catch {
      $GeometryModel = $null
    }
  }

  $WallLines = @()
  if ($GeometryModel -and $GeometryModel.sourceType -eq "raster" -and $GeometryModel.geometry.walls) {
    $Index = 1
    foreach ($Wall in $GeometryModel.geometry.walls) {
      $X1 = [Math]::Max([double]$Wall.x * $XMax, 0.0)
      $X2 = [Math]::Min(([double]$Wall.x + [double]$Wall.w) * $XMax, $XMax)
      $Y1 = [Math]::Max([double]$Wall.y * $YMax, 0.0)
      $Y2 = [Math]::Min(([double]$Wall.y + [double]$Wall.h) * $YMax, $YMax)

      if (($X2 - $X1) -lt 0.12) {
        $CenterX = ($X1 + $X2) / 2.0
        $X1 = [Math]::Max($CenterX - 0.06, 0.0)
        $X2 = [Math]::Min($CenterX + 0.06, $XMax)
      }
      if (($Y2 - $Y1) -lt 0.12) {
        $CenterY = ($Y1 + $Y2) / 2.0
        $Y1 = [Math]::Max($CenterY - 0.06, 0.0)
        $Y2 = [Math]::Min($CenterY + 0.06, $YMax)
      }

      $WallLines += "&OBST ID='PPCI_WALL_$Index', XB=$($X1.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)),$($X2.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)),$($Y1.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)),$($Y2.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)),0.0,$($CeilingHeight.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)), SURF_ID='INERT' /"
      $Index += 1
    }
  }

  $Lines = @(
    "! ============================================================"
    "! FDS draft generated by FDS & SMV Guided GUI"
    "! This is an initial placeholder case."
    "! Drawing source: $DrawingFile"
    "! Review geometry, materials, openings, vents, and prevention systems before final simulation."
    "! ============================================================"
    ""
    "&HEAD CHID='$Chid', TITLE='$ProjectName' /"
    ""
    "&TIME T_BEGIN=0.0, T_END=$($Duration.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)) /"
    ""
    "&DUMP DT_DEVC=1.0, DT_HRR=1.0, DT_SLCF=2.0, DT_BNDF=5.0 /"
    ""
    "! Draft mesh based on informed area and ceiling height."
    "&MESH IJK=$I,$J,$K, XB=0.0,$($XMax.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)),0.0,$($YMax.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)),0.0,$($ZMax.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)) /"
    ""
    "! Solid geometry extracted or drafted by the GUI."
  )

  if ($WallLines.Count -gt 0) {
    $Lines += $WallLines
  } else {
    $Lines += "! No drawing wall geometry was extracted yet. Review/import a raster plan or provide editable geometry."
  }

  $Lines += @(
    "&VENT MB='XMIN', SURF_ID='OPEN' /"
    "&VENT MB='XMAX', SURF_ID='OPEN' /"
    "&VENT MB='YMIN', SURF_ID='OPEN' /"
    "&VENT MB='YMAX', SURF_ID='OPEN' /"
    ""
    "! Fuel/scenario selected in GUI."
    "! Fuel type: $($Payload.fuelType)"
    "! Incident location: $($Payload.incidentLocation)"
    "! Ventilation assumption: $($Payload.ventilation)"
    "&REAC FUEL='PROPANE', SOOT_YIELD=0.05, CO_YIELD=0.02 /"
    "&SURF ID='GUI_FIRE', HRRPUA=$($Hrrpua.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)), COLOR='RED' /"
    "&VENT XB=$($FireX1.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)),$($FireX2.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)),$($FireY1.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)),$($FireY2.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)),0.0,0.0, SURF_ID='GUI_FIRE' /"
    ""
    "! Slice files for first Smokeview inspection."
    "&SLCF PBY=$(([Math]::Round($YMax / 2.0, 2)).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)), QUANTITY='TEMPERATURE' /"
    "&SLCF PBZ=$(([Math]::Round($CeilingHeight / 2.0, 2)).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)), QUANTITY='VISIBILITY' /"
    ""
    "&TAIL /"
  )

  Set-Content -LiteralPath $FdsFile -Value $Lines -Encoding UTF8
  return $FdsFile
}

function Show-FileDialog($Mode, $Filter, $CurrentPath) {
  $InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
  $DefaultFileName = ""

  if (-not [string]::IsNullOrWhiteSpace($CurrentPath)) {
    $Parent = Split-Path -Parent $CurrentPath -ErrorAction SilentlyContinue
    if ($Parent -and (Test-Path -LiteralPath $Parent -PathType Container)) {
      $InitialDirectory = $Parent
    }
    $DefaultFileName = Split-Path -Leaf $CurrentPath -ErrorAction SilentlyContinue
  }

  $DialogScript = @"
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if ('$Mode' -eq 'save') {
  `$dialog = New-Object System.Windows.Forms.SaveFileDialog
} else {
  `$dialog = New-Object System.Windows.Forms.OpenFileDialog
}
`$dialog.Filter = '$Filter'
`$dialog.InitialDirectory = '$InitialDirectory'
`$dialog.FileName = '$DefaultFileName'
if (`$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output `$dialog.FileName
}
"@

  $Bytes = [System.Text.Encoding]::Unicode.GetBytes($DialogScript)
  $Encoded = [Convert]::ToBase64String($Bytes)
  $Result = & powershell -NoProfile -STA -EncodedCommand $Encoded
  return ($Result | Select-Object -First 1)
}

function Show-FolderDialog($CurrentPath) {
  $InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
  if (-not [string]::IsNullOrWhiteSpace($CurrentPath) -and (Test-Path -LiteralPath $CurrentPath -PathType Container)) {
    $InitialDirectory = $CurrentPath
  }

  $DialogScript = @"
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
`$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
`$dialog.SelectedPath = '$InitialDirectory'
`$dialog.Description = 'Selecione a pasta onde a GUI deve gerar o caso FDS'
if (`$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output `$dialog.SelectedPath
}
"@

  $Bytes = [System.Text.Encoding]::Unicode.GetBytes($DialogScript)
  $Encoded = [Convert]::ToBase64String($Bytes)
  $Result = & powershell -NoProfile -STA -EncodedCommand $Encoded
  return ($Result | Select-Object -First 1)
}

function Escape-PowerShellLiteral($Value) {
  return ([string]$Value).Replace("'", "''")
}

function Start-PickerProcess($Kind, $CurrentPath) {
  $Token = [guid]::NewGuid().ToString("N")
  $ResultPath = Join-Path $env:TEMP "fds-gui-picker-$Token.txt"
  $InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
  $DefaultFileName = ""

  if (-not [string]::IsNullOrWhiteSpace($CurrentPath)) {
    if (Test-Path -LiteralPath $CurrentPath -PathType Container) {
      $InitialDirectory = $CurrentPath
    } else {
      $Parent = Split-Path -Parent $CurrentPath -ErrorAction SilentlyContinue
      if ($Parent -and (Test-Path -LiteralPath $Parent -PathType Container)) {
        $InitialDirectory = $Parent
      }
      $DefaultFileName = Split-Path -Leaf $CurrentPath -ErrorAction SilentlyContinue
    }
  }

  $EscapedResultPath = Escape-PowerShellLiteral $ResultPath
  $EscapedInitialDirectory = Escape-PowerShellLiteral $InitialDirectory
  $EscapedDefaultFileName = Escape-PowerShellLiteral $DefaultFileName

  if ($Kind -eq "folder") {
    $DialogScript = @"
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
`$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
`$dialog.SelectedPath = '$EscapedInitialDirectory'
`$dialog.Description = 'Selecione a pasta onde a GUI deve gerar o caso FDS'
if (`$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Set-Content -LiteralPath '$EscapedResultPath' -Value `$dialog.SelectedPath -Encoding UTF8
} else {
  Set-Content -LiteralPath '$EscapedResultPath' -Value '' -Encoding UTF8
}
"@
  } else {
    $DialogScript = @"
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
`$dialog = New-Object System.Windows.Forms.OpenFileDialog
`$dialog.Filter = 'Pranchas e arquivos FDS|*.fds;*.pdf;*.dxf;*.dwg;*.png;*.jpg;*.jpeg|Todos os arquivos|*.*'
`$dialog.InitialDirectory = '$EscapedInitialDirectory'
`$dialog.FileName = '$EscapedDefaultFileName'
if (`$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Set-Content -LiteralPath '$EscapedResultPath' -Value `$dialog.FileName -Encoding UTF8
} else {
  Set-Content -LiteralPath '$EscapedResultPath' -Value '' -Encoding UTF8
}
"@
  }

  $Bytes = [System.Text.Encoding]::Unicode.GetBytes($DialogScript)
  $Encoded = [Convert]::ToBase64String($Bytes)
  Start-Process powershell -ArgumentList "-NoProfile", "-STA", "-EncodedCommand", $Encoded | Out-Null
  return @{ token = $Token; resultPath = $ResultPath }
}

function Refresh-State {
  if ($State.job -ne $null) {
    $Job = Get-Job -Id $State.job.Id -ErrorAction SilentlyContinue
    if ($State.log_file -and (Test-Path -LiteralPath $State.log_file)) {
      $State.log = Get-Content -LiteralPath $State.log_file -Tail 400
    }
    if ($Job -and $Job.State -eq "Running") {
      $State.running = $true
      return
    }

    $State.running = $false
    if ($State.rc_file -and (Test-Path -LiteralPath $State.rc_file)) {
      $State.last_return_code = [int](Get-Content -LiteralPath $State.rc_file -Raw)
    }
    if ($Job) {
      Remove-Job -Id $Job.Id -Force -ErrorAction SilentlyContinue
    }
    $State.job = $null
  }
}

function Start-FdsRun($InputFile) {
  $InputPath = Get-Item -LiteralPath $InputFile
  $Chid = Read-Chid $InputPath.FullName
  $SmvPath = Join-Path $InputPath.DirectoryName "$Chid.smv"
  $LogFile = Join-Path $env:TEMP "fds-gui-$([guid]::NewGuid()).log"
  $RcFile = Join-Path $env:TEMP "fds-gui-$([guid]::NewGuid()).rc"

  $State.running = $true
  $State.last_return_code = $null
  $State.last_input = $InputPath.FullName
  $State.last_smv = $SmvPath
  $State.log_file = $LogFile
  $State.rc_file = $RcFile
  $State.log = @("Executando: $FdsExe $($InputPath.Name)")

  $State.job = Start-Job -ArgumentList $FdsExe, $InputPath.FullName, $LogFile, $RcFile -ScriptBlock {
    param($FdsExe, $InputFile, $LogFile, $RcFile)
    $Directory = Split-Path -Parent $InputFile
    $FileName = Split-Path -Leaf $InputFile
    Push-Location $Directory
    try {
      "Executando: $FdsExe $FileName" | Set-Content -LiteralPath $LogFile
      & $FdsExe $FileName *>&1 | Tee-Object -FilePath $LogFile -Append
      $Code = $LASTEXITCODE
      "FDS finalizado com codigo $Code." | Add-Content -LiteralPath $LogFile
    }
    catch {
      $_ | Out-String | Add-Content -LiteralPath $LogFile
      $Code = -1
    }
    finally {
      Pop-Location
    }
    Set-Content -LiteralPath $RcFile -Value $Code
  }
}

$Listener = New-Object System.Net.HttpListener
$Listener.Prefixes.Add($Prefix)
$Listener.Start()
Write-Host "FDS & SMV GUI em $Prefix"
Write-Host "Pressione Ctrl+C para encerrar."
try {
  Start-Process $Prefix
} catch {
  Write-Host "Abra manualmente: $Prefix"
}

while ($Listener.IsListening) {
  $Context = $Listener.GetContext()
  $Path = $Context.Request.Url.AbsolutePath
  $Method = $Context.Request.HttpMethod

  if ($Method -eq "OPTIONS") {
    $Context.Response.StatusCode = 204
    $Context.Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $Context.Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $Context.Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    $Context.Response.OutputStream.Close()
    continue
  }

  try {
    if ($Method -eq "GET" -and $Path -eq "/api/status") {
      Refresh-State
      Send-Json $Context 200 @{
        running = $State.running
        last_return_code = $State.last_return_code
        last_input = $State.last_input
        last_smv = $State.last_smv
        log = $State.log
      }
      continue
    }

    if ($Method -eq "GET" -and $Path -eq "/api/select-file-result") {
      $Token = [string]$Context.Request.QueryString["token"]
      if ([string]::IsNullOrWhiteSpace($Token) -or $Token -notmatch "^[a-fA-F0-9]{32}$") {
        Send-Json $Context 400 @{ error = "Token invalido." }
        continue
      }
      $ResultPath = Join-Path $env:TEMP "fds-gui-picker-$Token.txt"
      if (Test-Path -LiteralPath $ResultPath -PathType Leaf) {
        $SelectedPath = (Get-Content -LiteralPath $ResultPath -Raw -ErrorAction SilentlyContinue).Trim()
        Remove-Item -LiteralPath $ResultPath -Force -ErrorAction SilentlyContinue
        Send-Json $Context 200 @{ done = $true; path = $SelectedPath }
      } else {
        Send-Json $Context 200 @{ done = $false }
      }
      continue
    }

    if ($Method -eq "GET") {
      $StaticPath = if ($Path -eq "/" -or $Path -eq "/index.html") { "index.html" } else { $Path.TrimStart("/") }
      Send-File $Context $StaticPath
      continue
    }

    if ($Method -eq "POST" -and $Path -eq "/api/validate") {
      $Payload = Read-JsonBody $Context
      $InputFile = [string]$Payload.drawingFile
      $OutputFolder = [string]$Payload.outputFolder
      Send-Json $Context 200 @{
        ok = ((Test-Path -LiteralPath $FdsExe) -and (Test-Path -LiteralPath $SmokeviewExe) -and (Test-Path -LiteralPath $InputFile) -and (Test-Path -LiteralPath $OutputFolder -PathType Container))
        checks = @{
          fds = Test-Path -LiteralPath $FdsExe
          smokeview = Test-Path -LiteralPath $SmokeviewExe
          input = Test-Path -LiteralPath $InputFile
          outputFolder = Test-Path -LiteralPath $OutputFolder -PathType Container
        }
        fds = $FdsExe
        smokeview = $SmokeviewExe
        inputFile = $InputFile
        outputFolder = $OutputFolder
      }
      continue
    }

    if ($Method -eq "POST" -and $Path -eq "/api/select-file") {
      $Payload = Read-JsonBody $Context
      $Kind = [string]$Payload.kind
      $CurrentPath = [string]$Payload.currentPath
      $Picker = Start-PickerProcess $Kind $CurrentPath
      Send-Json $Context 202 @{ pending = $true; token = $Picker.token }
      continue
    }

    if ($Method -eq "POST" -and $Path -eq "/api/interpret-drawing") {
      $Payload = Read-JsonBody $Context
      $Model = Convert-DrawingToModel $Payload
      Send-Json $Context 200 @{
        ok = $true
        reviewRequired = $Model.reviewRequired
        message = "Interpretacao concluida; revise os dados antes de exportar o FDS final."
        model = $Model
        notes = $Model.notes
      }
      continue
    }

    if ($Method -eq "POST" -and $Path -eq "/api/generate-fds") {
      $Payload = Read-JsonBody $Context
      $OutputFolder = [string]$Payload.outputFolder
      if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
        Send-Json $Context 400 @{ error = "Informe uma pasta de saida." }
        continue
      }
      $FdsFile = New-FdsDraft $Payload
      Send-Json $Context 201 @{ ok = $true; fdsFile = $FdsFile }
      continue
    }

    if ($Method -eq "POST" -and $Path -eq "/api/run") {
      Refresh-State
      if ($State.running) {
        Send-Json $Context 409 @{ error = "Ja existe uma execucao em andamento." }
        continue
      }
      $Payload = Read-JsonBody $Context
      $InputFile = [string]$Payload.drawingFile
      if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        Send-Json $Context 400 @{ error = "Arquivo base ainda nao encontrado. Nesta etapa, o gerador FDS deve criar o .fds na pasta de saida antes de executar." }
        continue
      }
      Start-FdsRun $InputFile
      Send-Json $Context 202 @{ ok = $true; message = "FDS iniciado." }
      continue
    }

    if ($Method -eq "POST" -and $Path -eq "/api/open-smokeview") {
      $Payload = Read-JsonBody $Context
      $InputFile = [string]$Payload.drawingFile
      if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        Send-Json $Context 400 @{ error = "Arquivo .fds nao encontrado." }
        continue
      }
      $Chid = Read-Chid $InputFile
      $SmvPath = Join-Path (Split-Path -Parent $InputFile) "$Chid.smv"
      if (-not (Test-Path -LiteralPath $SmvPath -PathType Leaf)) {
        Send-Json $Context 404 @{ error = "Arquivo SMV ainda nao encontrado: $SmvPath" }
        continue
      }
      Start-Process -FilePath $SmokeviewExe -ArgumentList "`"$SmvPath`"" -WorkingDirectory (Split-Path -Parent $InputFile)
      Send-Json $Context 200 @{ ok = $true; smv = $SmvPath }
      continue
    }

    Send-Json $Context 404 @{ error = "Rota nao encontrada." }
  }
  catch {
    Send-Json $Context 500 @{ error = ($_ | Out-String) }
  }
}
