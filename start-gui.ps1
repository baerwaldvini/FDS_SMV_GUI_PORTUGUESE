$ErrorActionPreference = "Stop"

$HostName = "127.0.0.1"
$Port = 8765
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

    if ($Method -eq "GET") {
      $StaticPath = if ($Path -eq "/" -or $Path -eq "/index.html") { "index.html" } else { $Path.TrimStart("/") }
      Send-File $Context $StaticPath
      continue
    }

    if ($Method -eq "POST" -and $Path -eq "/api/validate") {
      $Payload = Read-JsonBody $Context
      $InputFile = [string]$Payload.inputFile
      Send-Json $Context 200 @{
        ok = ((Test-Path -LiteralPath $FdsExe) -and (Test-Path -LiteralPath $SmokeviewExe) -and (Test-Path -LiteralPath $InputFile))
        checks = @{
          fds = Test-Path -LiteralPath $FdsExe
          smokeview = Test-Path -LiteralPath $SmokeviewExe
          input = Test-Path -LiteralPath $InputFile
        }
        fds = $FdsExe
        smokeview = $SmokeviewExe
        inputFile = $InputFile
      }
      continue
    }

    if ($Method -eq "POST" -and $Path -eq "/api/run") {
      Refresh-State
      if ($State.running) {
        Send-Json $Context 409 @{ error = "Ja existe uma execucao em andamento." }
        continue
      }
      $Payload = Read-JsonBody $Context
      $InputFile = [string]$Payload.inputFile
      if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        Send-Json $Context 400 @{ error = "Arquivo .fds nao encontrado." }
        continue
      }
      Start-FdsRun $InputFile
      Send-Json $Context 202 @{ ok = $true; message = "FDS iniciado." }
      continue
    }

    if ($Method -eq "POST" -and $Path -eq "/api/open-smokeview") {
      $Payload = Read-JsonBody $Context
      $InputFile = [string]$Payload.inputFile
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
